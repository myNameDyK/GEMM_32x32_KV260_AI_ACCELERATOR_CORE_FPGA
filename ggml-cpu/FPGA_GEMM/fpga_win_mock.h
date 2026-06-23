#pragma once

#ifdef _WIN32

#    include <cstdint>
#    include <cstdio>
#    include <cstring>
#    include <vector>

#    ifndef WIN32_LEAN_AND_MEAN
#        define WIN32_LEAN_AND_MEAN
#    endif
#    include <windows.h>

// UTF-8 console (gọi một lần khi init)
static inline void fix_console_utf8() {
    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCP(CP_UTF8);
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h != INVALID_HANDLE_VALUE) {
        DWORD m = 0;
        GetConsoleMode(h, &m);
        SetConsoleMode(h, m | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
    }
}

// POSIX stubs
#    define _SYS_MMAN_H
#    define _UNISTD_H
#    define _FCNTL_H
#    define O_RDWR     2
#    define O_SYNC     0
#    define PROT_READ  0x1
#    define PROT_WRITE 0x2
#    define MAP_SHARED 0x01
#    define MAP_FAILED ((void *) -1)

// AXI-Lite register offsets (khớp FPGA_GEMM.cpp)
#    define MOCK_REG_SHIFT    0x00
#    define MOCK_REG_F_LENGTH 0x04
#    define MOCK_REG_F_WIDTH  0x08
#    define MOCK_REG_W_WIDTH  0x0C
#    define MOCK_ARRAY_SIZE   32

// DDR base addresses (khớp FPGA_GEMM.cpp)
#    define MOCK_FEAT_BASE 0x80000000ULL
#    define MOCK_WGHT_BASE 0x84000000ULL
#    define MOCK_RSLT_BASE 0xA4000000ULL

// AXI-Lite / DMA controller base addresses
#    define MOCK_AXILITE_BASE  0xA0030000ULL
#    define MOCK_DMA_FEAT_BASE 0xA0000000ULL
#    define MOCK_DMA_WGHT_BASE 0xA0010000ULL
#    define MOCK_DMA_RSLT_BASE 0xA0020000ULL

// ── Global buffers ────────────────────────────────────────────
static std::vector<uint8_t> g_axilite;        // AXI-Lite config regs  (64KB)
static std::vector<uint8_t> g_dma_feat_regs;  // DMA FEAT ctrl shadow  (64KB)
static std::vector<uint8_t> g_dma_wght_regs;  // DMA WGHT ctrl shadow  (64KB)
static std::vector<uint8_t> g_dma_rslt_regs;  // DMA RSLT ctrl shadow  (64KB)
static std::vector<uint8_t> g_ddr_feat;       // Activation int8       (64MB)
static std::vector<uint8_t> g_ddr_wght;       // Weight int8          (512MB)
static std::vector<uint8_t> g_ddr_rslt;       // Result int8           (64MB)
static bool                 g_mock_ready = false;

static inline void mock_init() {
    if (g_mock_ready) {
        return;
    }
    fix_console_utf8();
    printf("[MOCK] Allocating buffers...\n");
    g_axilite.assign(0x10000, 0);
    g_dma_feat_regs.assign(0x10000, 0);
    g_dma_wght_regs.assign(0x10000, 0);
    g_dma_rslt_regs.assign(0x10000, 0);
    g_ddr_feat.assign(0x04000000UL, 0);
    g_ddr_wght.assign(0x20000000UL, 0);
    g_ddr_rslt.assign(0x04000000UL, 0);
    printf("[MOCK] Buffers ready\n");
    g_mock_ready = true;
}

// ── DMA tracking ──────────────────────────────────────────────
static uint64_t g_feat_phys  = 0;
static uint32_t g_feat_bytes = 0;
static uint64_t g_wght_phys  = 0;
static uint32_t g_wght_bytes = 0;
static uint64_t g_rslt_phys  = 0;
static uint32_t g_rslt_bytes = 0;

// ── Software GEMM (giả lập Out_buffer.v) ─────────────────────
// Layout: feat[M x K_pad], wght[K_pad x N_pad], rslt[M x N_pad]
// acc[m,n] = Σ_k feat[m,k]*wght[k,n] → clamp(acc >> auto_shift, -128,127)
static inline void mock_compute_gemm() {
    if (!g_mock_ready) {
        fprintf(stderr, "[MOCK] not init\n");
        return;
    }

    uint32_t axi_shift = *(uint32_t *) (g_axilite.data() + MOCK_REG_SHIFT);
    int      M         = (int) *(uint32_t *) (g_axilite.data() + MOCK_REG_F_LENGTH);
    int      K         = (int) *(uint32_t *) (g_axilite.data() + MOCK_REG_F_WIDTH) * MOCK_ARRAY_SIZE;
    int      N         = (int) *(uint32_t *) (g_axilite.data() + MOCK_REG_W_WIDTH) * MOCK_ARRAY_SIZE;

    if (g_wght_phys < MOCK_WGHT_BASE || g_wght_phys >= MOCK_RSLT_BASE) {
        fprintf(stderr, "[MOCK] wght phys invalid (0x%llx)\n", (unsigned long long) g_wght_phys);
        return;
    }

    const int8_t * feat = (const int8_t *) g_ddr_feat.data();
    const int8_t * wght = (const int8_t *) g_ddr_wght.data() + (g_wght_phys - MOCK_WGHT_BASE);
    int8_t *       rslt = (int8_t *) g_ddr_rslt.data();

    // Pass 1: accumulate int32
    std::vector<int32_t> acc(M * N, 0);
    int32_t              max_abs_acc = 1;
    for (int m = 0; m < M; m++) {
        for (int n = 0; n < N; n++) {
            int32_t s = 0;
            for (int k = 0; k < K; k++) {
                s += (int32_t) feat[m * K + k] * (int32_t) wght[k * N + n];
            }
            acc[m * N + n] = s;
            int32_t a      = s < 0 ? -s : s;
            if (a > max_abs_acc) {
                max_abs_acc = a;
            }
        }
    }

    // Pass 2: auto shift từ max thực tế
    uint32_t auto_shift = 0;
    {
        int32_t v = max_abs_acc / 127;
        while (v > 0) {
            auto_shift++;
            v >>= 1;
        }
    }

    printf("[MOCK] M=%d K=%d N=%d  axi_shift=%u auto_shift=%u  max_acc=%d\n", M, K, N, axi_shift, auto_shift,
           max_abs_acc);

    // Pass 3: shift + clamp → rslt
    for (int i = 0; i < M * N; i++) {
        int32_t v = acc[i] >> auto_shift;
        rslt[i]   = (int8_t) (v > 127 ? 127 : v < -128 ? -128 : v);
    }

    // Ghi lại auto_shift để FPGA_GEMM.cpp tính out_scale đúng
    *(uint32_t *) (g_axilite.data() + MOCK_REG_SHIFT) = auto_shift;
}

// ── POSIX stubs ───────────────────────────────────────────────
static inline int open(const char * path, int) {
    mock_init();
    printf("[MOCK] open(\"%s\")\n", path);
    return 3;
}

static inline int close(int) {
    return 0;
}

static inline void usleep(unsigned) {}

static inline int munmap(void *, size_t) {
    return 0;
}

// mmap nhận uint64_t offset trực tiếp — tránh sign-extension qua off_t (off_t=32-bit trên MSVC)
static inline void * mmap(void *, size_t len, int, int, int, uint64_t offset) {
    mock_init();
    printf("[MOCK] mmap offset=0x%llx size=0x%zx\n", (unsigned long long) offset, len);

    if (offset == MOCK_AXILITE_BASE) {
        return g_axilite.data();
    }
    if (offset == MOCK_DMA_FEAT_BASE) {
        return g_dma_feat_regs.data();
    }
    if (offset == MOCK_DMA_WGHT_BASE) {
        return g_dma_wght_regs.data();
    }
    if (offset == MOCK_DMA_RSLT_BASE) {
        return g_dma_rslt_regs.data();
    }
    if (offset == MOCK_FEAT_BASE) {
        return g_ddr_feat.data();
    }
    if (offset == MOCK_WGHT_BASE) {
        return g_ddr_wght.data();
    }
    if (offset == MOCK_RSLT_BASE) {
        return g_ddr_rslt.data();
    }

    printf("[MOCK][WARN] unknown mmap offset=0x%llx\n", (unsigned long long) offset);
    return MAP_FAILED;
}

// ── Register mock ─────────────────────────────────────────────
static inline uint32_t mock_rd32(void *, uint32_t) {
    return 0x0002;  // DMA_SR_IDLE — thoát vòng poll ngay
}

static inline void mock_wr32(void * base, uint32_t off, uint32_t val) {
    // Chỉ ghi vào AXI-Lite; bỏ qua DMA CR writes
    if (base == (void *) g_axilite.data() && off + 4 <= (uint32_t) g_axilite.size()) {
        *(uint32_t *) (g_axilite.data() + off) = val;
    }
}

// ── DMA mock ─────────────────────────────────────────────────
static inline void mock_dma_reset(void *) {
    g_feat_phys  = 0;
    g_feat_bytes = 0;
    g_wght_phys  = 0;
    g_wght_bytes = 0;
    g_rslt_phys  = 0;
    g_rslt_bytes = 0;
}

static inline void mock_dma_send(void *, uint64_t phys, uint32_t bytes) {
    if (phys >= MOCK_FEAT_BASE && phys < MOCK_WGHT_BASE) {
        g_feat_phys  = phys;
        g_feat_bytes = bytes;
        printf("[MOCK] dma_send FEAT phys=0x%llx bytes=%u\n", (unsigned long long) phys, bytes);
    } else if (phys >= MOCK_WGHT_BASE && phys < MOCK_RSLT_BASE) {
        g_wght_phys  = phys;
        g_wght_bytes = bytes;
        printf("[MOCK] dma_send WGHT phys=0x%llx bytes=%u\n", (unsigned long long) phys, bytes);
    } else {
        fprintf(stderr, "[MOCK] dma_send unknown phys=0x%llx\n", (unsigned long long) phys);
    }
}

static inline void mock_dma_recv_start(void *, uint64_t phys, uint32_t bytes) {
    g_rslt_phys  = phys;
    g_rslt_bytes = bytes;
    printf("[MOCK] dma_recv_start RSLT phys=0x%llx bytes=%u\n", (unsigned long long) phys, bytes);
}

static inline void mock_dma_recv_wait(void *) {
    mock_compute_gemm();  // "FPGA done" → chạy software GEMM
}

// ── Override macros ───────────────────────────────────────────
#    define rd32(base, off)                  mock_rd32(base, off)
#    define wr32(base, off, val)             mock_wr32(base, off, val)
#    define dma_reset(dma)                   mock_dma_reset(dma)
#    define dma_send(dma, addr, bytes)       mock_dma_send(dma, addr, bytes)
#    define dma_recv_start(dma, addr, bytes) mock_dma_recv_start(dma, addr, bytes)
#    define dma_recv_wait(dma)               mock_dma_recv_wait(dma)

#endif  // _WIN32
