#include "FPGA_GEMM.h"

#include "fpga_win_mock.h"
#ifndef _WIN32
#    include <fcntl.h>
#    include <sys/mman.h>
#    include <unistd.h>
#endif
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <unordered_map>

// ── FPGA register map ──────────────────────────────────────────────────────
#define DMA_FEAT_BASE 0xA0000000ULL
#define DMA_WGHT_BASE 0xA0010000ULL
#define DMA_RSLT_BASE 0xA0020000ULL
#define AXILITE_BASE  0xA0030000ULL
#define MAP_SIZE      0x10000ULL

// ── DDR fixed addresses ────────────────────────────────────────────────────
#define DDR_FEAT_BASE 0x80000000ULL
#define DDR_WGHT_BASE 0x84000000ULL
#define DDR_RSLT_BASE 0xA4000000ULL
#define DDR_FEAT_SIZE 0x04000000ULL
#define DDR_WGHT_SIZE 0x20000000ULL
#define DDR_RSLT_SIZE 0x04000000ULL

// ── AXI-Lite control registers ─────────────────────────────────────────────
#define REG_SHIFT    0x00
#define REG_F_LENGTH 0x04
#define REG_F_WIDTH  0x08
#define REG_W_WIDTH  0x0C

// ── DMA register offsets ───────────────────────────────────────────────────
#define DMA_MM2S_CR   0x00
#define DMA_MM2S_SR   0x04
#define DMA_MM2S_SA   0x18
#define DMA_MM2S_LEN  0x28
#define DMA_S2MM_CR   0x30
#define DMA_S2MM_SR   0x34
#define DMA_S2MM_DA   0x48
#define DMA_S2MM_LEN  0x58
#define DMA_CR_RUN    0x0001
#define DMA_CR_RESET  0x0004
#define DMA_SR_IDLE   0x0002
#define DMA_SR_HALTED 0x0001

#define ARRAY_SIZE 32

// Align x up to nearest multiple of 32
static inline int align32(int x) {
    return (x + ARRAY_SIZE - 1) & ~(ARRAY_SIZE - 1);
}

// ── Quantization block layouts (ggml spec) ─────────────────────────────────
#define QK5_0 32

typedef struct {
    uint16_t d;
    uint8_t  qh[4];
    uint8_t  qs[16];
} block_q5_0;

#define QK8_0 32

typedef struct {
    uint16_t d;
    int8_t   qs[32];
} block_q8_0;

#define QK_K         256
#define K_SCALE_SIZE 12

typedef struct {
    uint8_t  scales[K_SCALE_SIZE];
    uint8_t  qs[QK_K / 2];
    uint16_t d;
    uint16_t dmin;
} block_q4_K;

// ── FP16 → FP32 ───────────────────────────────────────────────────────────
static float fp16_to_fp32(uint16_t h) {
    uint32_t sign = (uint32_t) (h & 0x8000) << 16;
    uint32_t exp  = (h >> 10) & 0x1F;
    uint32_t mant = h & 0x03FF;
    uint32_t f;
    if (exp == 0) {
        if (!mant) {
            f = sign;
        } else {
            exp = 1;
            while (!(mant & 0x0400)) {
                mant <<= 1;
                exp--;
            }
            mant &= 0x03FF;
            f = sign | ((exp + 112) << 23) | (mant << 13);
        }
    } else if (exp == 0x1F) {
        f = sign | 0x7F800000 | (mant << 13);  // Inf/NaN
    } else {
        f = sign | ((exp + 112) << 23) | (mant << 13);
    }
    float r;
    memcpy(&r, &f, 4);
    return r;
}

// ── Dequantize helpers ─────────────────────────────────────────────────────
static void dequant_q5_0(const block_q5_0 * b, int nb, float * out) {
    for (int i = 0; i < nb; i++) {
        float    d = fp16_to_fp32(b[i].d);
        uint32_t qh;
        memcpy(&qh, b[i].qh, 4);
        for (int j = 0; j < 32; j++) {
            uint8_t lo      = (j < 16) ? (b[i].qs[j] & 0x0F) : (b[i].qs[j - 16] >> 4);
            uint8_t hi      = (qh >> j) & 1;
            out[i * 32 + j] = d * (float) ((int) ((hi << 4) | lo) - 16);
        }
    }
}

static void dequant_q8_0(const block_q8_0 * b, int nb, float * out) {
    for (int i = 0; i < nb; i++) {
        float d = fp16_to_fp32(b[i].d);
        for (int j = 0; j < 32; j++) {
            out[i * 32 + j] = d * (float) b[i].qs[j];
        }
    }
}

static void dequant_q4_K(const block_q4_K * b, int nb, float * out) {
    for (int i = 0; i < nb; i++) {
        float           d    = fp16_to_fp32(b[i].d);
        float           dmin = fp16_to_fp32(b[i].dmin);
        const uint8_t * sc   = b[i].scales;
        const uint8_t * q    = b[i].qs;
        float *         dst  = out + i * QK_K;
        uint8_t         sv[8], mv[8];
        for (int j = 0; j < 4; j++) {
            sv[j]     = sc[j] & 0x3F;
            sv[j + 4] = sc[j + 4] & 0x3F;
            mv[j]     = (sc[j] >> 6) | ((sc[j + 8] & 0x0F) << 2);
            mv[j + 4] = (sc[j + 4] >> 6) | ((sc[j + 8] >> 4) << 2);
        }
        for (int sub = 0; sub < 8; sub++) {
            float sf = d * (float) sv[sub];
            float mf = dmin * (float) mv[sub];
            for (int j = 0; j < 32; j++) {
                int     idx       = sub * 16 + j / 2;
                uint8_t nib       = (j & 1) ? (q[idx] >> 4) : (q[idx] & 0x0F);
                dst[sub * 32 + j] = sf * (float) nib - mf;
            }
        }
    }
}

// ── Weight cache ───────────────────────────────────────────────────────────
struct WeightEntry {
    uint64_t phys_addr;  // 0 = invalid
    float    scale_W;
    uint32_t size;       // bytes in weight pool
    int      K_pad;
    int      N_pad;
};

static std::unordered_map<const void *, WeightEntry> g_weight_cache;
static uint64_t                                      g_wpool_offset = 0;

// ── Static state ───────────────────────────────────────────────────────────
static bool     g_ready      = false;
static int      mem_fd       = -1;
static void *   axilite_map  = nullptr;
static void *   dma_feat_map = nullptr;
static void *   dma_wght_map = nullptr;
static void *   dma_rslt_map = nullptr;
static int8_t * ddr_feat     = nullptr;
static void *   ddr_wght     = nullptr;
static int8_t * ddr_rslt     = nullptr;

// ── Register access (Linux only) ───────────────────────────────────────────
#ifndef _WIN32
static void wr32(void * base, uint32_t off, uint32_t val) {
    *(volatile uint32_t *) ((char *) base + off) = val;
}

static uint32_t rd32(void * base, uint32_t off) {
    return *(volatile uint32_t *) ((char *) base + off);
}
#endif

// Map physical address via /dev/mem
// _WIN32: mock mmap nhận uint64_t trực tiếp, không cast qua off_t (off_t = 32-bit trên MSVC → sign-extend)
// Linux : off_t = 64-bit khi _FILE_OFFSET_BITS=64, cast an toàn
static void * map_phys(uint64_t base, size_t size) {
#ifdef _WIN32
    void * p = mmap(0, size, PROT_READ | PROT_WRITE, MAP_SHARED, mem_fd, base);
#else
    void * p = mmap(0, size, PROT_READ | PROT_WRITE, MAP_SHARED, mem_fd, (off_t) base);
#endif
    return (p == MAP_FAILED) ? nullptr : p;
}

#ifndef _WIN32
static void dma_reset(void * dma) {
    wr32(dma, DMA_MM2S_CR, DMA_CR_RESET);
    wr32(dma, DMA_S2MM_CR, DMA_CR_RESET);
    usleep(1000);
    while (rd32(dma, DMA_MM2S_SR) & DMA_SR_HALTED) {
    }
    while (rd32(dma, DMA_S2MM_SR) & DMA_SR_HALTED) {
    }
}

static void dma_send(void * dma, uint64_t addr, uint32_t bytes) {
    wr32(dma, DMA_MM2S_CR, DMA_CR_RUN);
    wr32(dma, DMA_MM2S_SA, (uint32_t) (addr & 0xFFFFFFFF));
    wr32(dma, DMA_MM2S_LEN, bytes);
    while (!(rd32(dma, DMA_MM2S_SR) & DMA_SR_IDLE)) {
    }
}

static void dma_recv_start(void * dma, uint64_t addr, uint32_t bytes) {
    wr32(dma, DMA_S2MM_CR, DMA_CR_RUN);
    wr32(dma, DMA_S2MM_DA, (uint32_t) (addr & 0xFFFFFFFF));
    wr32(dma, DMA_S2MM_LEN, bytes);
}

static void dma_recv_wait(void * dma) {
    while (!(rd32(dma, DMA_S2MM_SR) & DMA_SR_IDLE)) {
    }
}
#endif

// ── Weight pool allocator (64-byte aligned) ────────────────────────────────
static uint64_t alloc_weight(uint32_t size) {
    uint64_t off = (g_wpool_offset + 63) & ~63ULL;
    if (off + size > DDR_WGHT_SIZE) {
        fprintf(stderr, "[FPGA] weight pool overflow (need %u, used %llu / %lu)\n", size, (unsigned long long) off,
                (unsigned long) DDR_WGHT_SIZE);
        return 0;
    }
    g_wpool_offset = off + size;
    return DDR_WGHT_BASE + off;
}

static int8_t * wphys_to_virt(uint64_t phys) {
    return (int8_t *) ddr_wght + (phys - DDR_WGHT_BASE);
}

// Quantize float W[K,N] → int8, zero-pad to K_pad x N_pad, store in weight pool
// scale_W = max_abs(W) / 127
static WeightEntry store_weight_f32(const float * W, int K, int N, int K_pad, int N_pad, const char * tag) {
    float max_abs = 1e-9f;
    for (int i = 0; i < K * N; i++) {
        float v = fabsf(W[i]);
        if (v > max_abs) {
            max_abs = v;
        }
    }

    float    scale_W     = max_abs / 127.0f;
    float    inv_scale_W = 127.0f / max_abs;
    uint32_t sz          = (uint32_t) (K_pad * N_pad);
    uint64_t phys        = alloc_weight(sz);
    if (!phys) {
        return { 0, 0.0f, 0, 0, 0 };
    }

    int8_t * virt = wphys_to_virt(phys);
    memset(virt, 0, sz);
    for (int k = 0; k < K; k++) {
        for (int n = 0; n < N; n++) {
            int iv              = (int) roundf(W[k * N + n] * inv_scale_W);
            iv                  = iv > 127 ? 127 : iv < -128 ? -128 : iv;
            virt[k * N_pad + n] = (int8_t) iv;
        }
    }
    printf("[FPGA] %s cached @ 0x%llx K=%d->%d N=%d->%d scale_W=%.4e\n", tag, (unsigned long long) phys, K, K_pad, N,
           N_pad, scale_W);
    return WeightEntry{ phys, scale_W, sz, K_pad, N_pad };
}

// ── Per-quant cache helpers ────────────────────────────────────────────────
static WeightEntry cache_q5_0(const void * raw, int K, int N) {
    int     nb = (K * N + QK5_0 - 1) / QK5_0;
    float * f  = new float[K * N];
    dequant_q5_0((const block_q5_0 *) raw, nb, f);
    auto we = store_weight_f32(f, K, N, align32(K), align32(N), "Q5_0");
    delete[] f;
    return we;
}

static WeightEntry cache_q8_0(const void * raw, int K, int N) {
    int     nb = (K * N + QK8_0 - 1) / QK8_0;
    float * f  = new float[K * N];
    dequant_q8_0((const block_q8_0 *) raw, nb, f);
    auto we = store_weight_f32(f, K, N, align32(K), align32(N), "Q8_0");
    delete[] f;
    return we;
}

static WeightEntry cache_q4_K(const void * raw, int K, int N) {
    int     nb = (K * N + QK_K - 1) / QK_K;
    float * f  = new float[K * N];
    dequant_q4_K((const block_q4_K *) raw, nb, f);
    auto we = store_weight_f32(f, K, N, align32(K), align32(N), "Q4_K");
    delete[] f;
    return we;
}

// ── Public API ─────────────────────────────────────────────────────────────
bool fpga_gemm_init() {
#ifdef _WIN32
    mock_init();
    mem_fd = 3;  // fake fd for Windows mock
#else
    mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    printf("[DEBUG] mem_fd = %d\n", mem_fd);
    if (mem_fd < 0) {
        perror("[FPGA] open /dev/mem");
        return false;
    }
#endif
    axilite_map  = map_phys(AXILITE_BASE, MAP_SIZE);
    dma_feat_map = map_phys(DMA_FEAT_BASE, MAP_SIZE);
    dma_wght_map = map_phys(DMA_WGHT_BASE, MAP_SIZE);
    dma_rslt_map = map_phys(DMA_RSLT_BASE, MAP_SIZE);
    if (!axilite_map || !dma_feat_map || !dma_wght_map || !dma_rslt_map) {
        fprintf(stderr, "[FPGA] mmap AXI-Lite failed\n");
        return false;
    }
    ddr_feat = (int8_t *) map_phys(DDR_FEAT_BASE, DDR_FEAT_SIZE);
    ddr_wght = map_phys(DDR_WGHT_BASE, DDR_WGHT_SIZE);
    ddr_rslt = (int8_t *) map_phys(DDR_RSLT_BASE, DDR_RSLT_SIZE);
    if (!ddr_feat || !ddr_wght || !ddr_rslt) {
        fprintf(stderr, "[FPGA] mmap DDR failed\n");
        return false;
    }
#ifndef _WIN32
    dma_reset(dma_feat_map);
    dma_reset(dma_wght_map);
    dma_reset(dma_rslt_map);
#endif
    g_wpool_offset = 0;
    g_weight_cache.clear();
    g_ready = true;
    printf("[FPGA] init OK\n");
    return true;
}

void fpga_gemm_cleanup() {
    g_weight_cache.clear();
#ifndef _WIN32
    if (ddr_feat) {
        munmap(ddr_feat, DDR_FEAT_SIZE);
    }
    if (ddr_wght) {
        munmap(ddr_wght, DDR_WGHT_SIZE);
    }
    if (ddr_rslt) {
        munmap(ddr_rslt, DDR_RSLT_SIZE);
    }
    if (axilite_map) {
        munmap(axilite_map, MAP_SIZE);
    }
    if (dma_feat_map) {
        munmap(dma_feat_map, MAP_SIZE);
    }
    if (dma_wght_map) {
        munmap(dma_wght_map, MAP_SIZE);
    }
    if (dma_rslt_map) {
        munmap(dma_rslt_map, MAP_SIZE);
    }
    if (mem_fd >= 0) {
        close(mem_fd);
    }
#endif
    ddr_feat     = nullptr;
    ddr_wght     = nullptr;
    ddr_rslt     = nullptr;
    axilite_map  = nullptr;
    dma_feat_map = nullptr;
    dma_wght_map = nullptr;
    dma_rslt_map = nullptr;
    mem_fd       = -1;
    g_ready      = false;
}

bool fpga_gemm_is_ready() {
    if (!g_ready) {
        g_ready = fpga_gemm_init();
    }
    return g_ready;
}

// ── fpga_gemm_run ──────────────────────────────────────────────────────────
// Math pipeline:
//   A) scale_B = max|B|/127 ; feat_q = clamp(round(B/scale_B), -128,127)
//   B) scale_W = max|W|/127 ; wght_q = clamp(round(W/scale_W), -128,127)  [cached]
//   C) FPGA: acc[m,n] = sum_k feat_q[m,k]*wght_q[k,n]  →  rslt = clamp(acc>>shift, -128,127)
//   D) C[m,n] = rslt[m,n] * scale_B * scale_W * 2^shift
//   shift = floor(log2(K_pad*127^2/127)) = floor(log2(K_pad*127)), clamped [0,24]
void fpga_gemm_run(const void *  A_raw,
                   FpgaQuantType quant,
                   const float * B_f32,
                   float *       C,
                   int           M,
                   int           K_orig,
                   int           N_orig,
                   int           shift_in) {
    if (!g_ready) {
        fprintf(stderr, "[FPGA] not initialised\n");
        return;
    }

    const int TILE       = 32;
    int       K_pad      = ((K_orig + TILE - 1) / TILE) * TILE;
    int       N_pad      = ((N_orig + TILE - 1) / TILE) * TILE;
    uint32_t  feat_bytes = (uint32_t) (M * K_pad);
    uint32_t  rslt_bytes = (uint32_t) (M * N_pad);

    // A: quantize activation B → int8, zero-pad K → K_pad
    float max_abs_B = 1e-9f;
    for (int i = 0; i < M * K_orig; i++) {
        float v = fabsf(B_f32[i]);
        if (v > max_abs_B) {
            max_abs_B = v;
        }
    }
    float scale_B     = max_abs_B / 127.0f;
    float inv_scale_B = 127.0f / max_abs_B;
    memset(ddr_feat, 0, feat_bytes);
    for (int m = 0; m < M; m++) {
        for (int k = 0; k < K_orig; k++) {
            int iv                  = (int) roundf(B_f32[m * K_orig + k] * inv_scale_B);
            iv                      = iv > 127 ? 127 : iv < -128 ? -128 : iv;
            ddr_feat[m * K_pad + k] = (int8_t) iv;
        }
    }

    // B: cache weight (once per pointer A_raw)
    WeightEntry we;
    auto        it = g_weight_cache.find(A_raw);
    if (it != g_weight_cache.end()) {
        we = it->second;
    } else {
        switch (quant) {
            case FPGA_QUANT_Q5_0:
                we = cache_q5_0(A_raw, K_orig, N_orig);
                break;
            case FPGA_QUANT_Q8_0:
                we = cache_q8_0(A_raw, K_orig, N_orig);
                break;
            case FPGA_QUANT_Q4_K:
                we = cache_q4_K(A_raw, K_orig, N_orig);
                break;
            default:
                fprintf(stderr, "[FPGA] unknown quant type %d\n", (int) quant);
                return;
        }
        if (!we.phys_addr) {
            fprintf(stderr, "[FPGA] weight alloc failed\n");
            return;
        }
        g_weight_cache[A_raw] = we;
    }

    // Sanity check: padding must match cached shape
    if (we.K_pad != K_pad || we.N_pad != N_pad) {
        fprintf(stderr, "[FPGA] padding mismatch: cached(%d,%d) vs current(%d,%d)\n", we.K_pad, we.N_pad, K_pad, N_pad);
        return;
    }

    // C: compute optimal shift = floor(log2(K_pad * 127)), clamped [0,24]
    int shift = shift_in;
    if (shift <= 0) {
        double s = floor(log2((double) K_pad * 127.0));
        shift    = (int) s;
        shift    = shift < 0 ? 0 : shift > 24 ? 24 : shift;
    }

    // D: configure AXI-Lite
    wr32(axilite_map, REG_SHIFT, (uint32_t) shift);
    wr32(axilite_map, REG_F_LENGTH, (uint32_t) M);
    wr32(axilite_map, REG_F_WIDTH, (uint32_t) (K_pad / ARRAY_SIZE));
    wr32(axilite_map, REG_W_WIDTH, (uint32_t) (N_pad / ARRAY_SIZE));

    // E: DMA sequence
    dma_recv_start(dma_rslt_map, DDR_RSLT_BASE, rslt_bytes);
    dma_send(dma_feat_map, DDR_FEAT_BASE, feat_bytes);
    dma_send(dma_wght_map, we.phys_addr, we.size);
    dma_recv_wait(dma_rslt_map);

    // F: dequant rslt int8 → float
#ifdef _WIN32
    uint32_t actual_shift = *(uint32_t *) ((char *) axilite_map + REG_SHIFT);  // mock may update shift
    float    out_scale    = scale_B * we.scale_W * (float) (1u << actual_shift);
#else
    float out_scale = scale_B * we.scale_W * (float) (1u << shift);
#endif
    for (int m = 0; m < M; m++) {
        for (int n = 0; n < N_orig; n++) {
            C[m * N_orig + n] = (float) ddr_rslt[m * N_pad + n] * out_scale;
        }
    }

    // G: CPU float reference check (first call only, Windows mock)
#ifdef _WIN32
    {
        static int dbg_count = 0;
        if (dbg_count++ != 0) {
            return;
        }

        int     n_elem = K_orig * N_orig;
        float * W_f    = new float[n_elem];
        int     nb;
        switch (quant) {
            case FPGA_QUANT_Q5_0:
                nb = (n_elem + QK5_0 - 1) / QK5_0;
                dequant_q5_0((const block_q5_0 *) A_raw, nb, W_f);
                break;
            case FPGA_QUANT_Q8_0:
                nb = (n_elem + QK8_0 - 1) / QK8_0;
                dequant_q8_0((const block_q8_0 *) A_raw, nb, W_f);
                break;
            case FPGA_QUANT_Q4_K:
                nb = (n_elem + QK_K - 1) / QK_K;
                dequant_q4_K((const block_q4_K *) A_raw, nb, W_f);
                break;
            default:
                break;
        }

        // CPU GEMM ground truth
        float * C_ref = new float[M * N_orig]();
        for (int m = 0; m < M; m++) {
            for (int k = 0; k < K_orig; k++) {
                for (int n = 0; n < N_orig; n++) {
                    C_ref[m * N_orig + n] += B_f32[m * K_orig + k] * W_f[k * N_orig + n];
                }
            }
        }

        // Error statistics
        float max_diff = 0, max_rel = 0, sum_diff = 0;
        for (int i = 0; i < M * N_orig; i++) {
            float diff = fabsf(C[i] - C_ref[i]);
            float rel  = diff / (fabsf(C_ref[i]) + 1e-6f);
            if (diff > max_diff) {
                max_diff = diff;
            }
            if (rel > max_rel) {
                max_rel = rel;
            }
            sum_diff += diff;
        }
        printf("[REF] M=%d K=%d N=%d shift=%d\n", M, K_orig, N_orig, shift);
        printf("[REF] scale_B=%.4e scale_W=%.4e out_scale=%.4e\n", scale_B, we.scale_W, out_scale);
        printf("[REF] max_abs=%.4e mean_abs=%.4e max_rel=%.2f%%\n", max_diff, sum_diff / (float) (M * N_orig),
               max_rel * 100.0f);
        printf("[REF] Sample n=0..7:");
        for (int n = 0; n < 8 && n < N_orig; n++) {
            printf(" [%d] fpga=%.4f ref=%.4f", n, C[n], C_ref[n]);
        }
        printf("\n");

        delete[] W_f;
        delete[] C_ref;
    }
#endif
}
