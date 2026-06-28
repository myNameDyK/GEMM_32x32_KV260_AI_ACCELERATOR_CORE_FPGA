#include "xil_types.h"
#include "xparameters.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xaxidma_hw.h"
#include "Defines.h"

// ============================================================
// Matrix configuration
// ============================================================
#define IN_ROWS_NUM 32U
#define IN_COLS_NUM 32U
#define OUT_COLS_NUM 32U

#define R_SHIFT 0U

#define MATRIX_A_BYTES (IN_ROWS_NUM * IN_COLS_NUM)
#define MATRIX_B_BYTES (IN_COLS_NUM * OUT_COLS_NUM)
#define MATRIX_C_BYTES (IN_ROWS_NUM * OUT_COLS_NUM)

typedef DATA_TYPE data_t;

// ============================================================
// Buffers
// 64-byte aligned for cache/DMA safety.
// ============================================================
alignas(64) static data_t A_buf[MATRIX_A_BYTES];
alignas(64) static data_t B_buf[MATRIX_B_BYTES];
alignas(64) static data_t C_sw[MATRIX_C_BYTES];
alignas(64) static data_t C_hw[MATRIX_C_BYTES];

// ============================================================
// Utility
// ============================================================
static data_t clip_int8(int x)
{
if (x > MAX_LIMIT) {
return (data_t)MAX_LIMIT;
}

if (x < MIN_LIMIT) {
    return (data_t)MIN_LIMIT;
}

return (data_t)x;

}

static int quantize_acc(int acc)
{
if (R_SHIFT > 0U) {
acc = acc >> R_SHIFT;
}

return (int)clip_int8(acc);

}

static void init_matrices(void)
{
for (u32 r = 0U; r < IN_ROWS_NUM; r++) {
for (u32 c = 0U; c < IN_COLS_NUM; c++) {
int v = (int)((r + c) % 5U) - 2;
A_buf[r * IN_COLS_NUM + c] = (data_t)v;
}
}

for (u32 r = 0U; r < IN_COLS_NUM; r++) {
    for (u32 c = 0U; c < OUT_COLS_NUM; c++) {
        int v = (int)(((r * 2U) + c) % 5U) - 2;
        B_buf[r * OUT_COLS_NUM + c] = (data_t)v;
    }
}

for (u32 i = 0U; i < MATRIX_C_BYTES; i++) {
    C_sw[i] = 0;
    C_hw[i] = 0;
}

}

static void gemm_soft(void)
{
for (u32 r = 0U; r < IN_ROWS_NUM; r++) {
for (u32 c = 0U; c < OUT_COLS_NUM; c++) {
int acc = 0;

        for (u32 k = 0U; k < IN_COLS_NUM; k++) {
            int a = (int)A_buf[r * IN_COLS_NUM + k];
            int b = (int)B_buf[k * OUT_COLS_NUM + c];
            acc += a * b;
        }

        C_sw[r * OUT_COLS_NUM + c] = (data_t)quantize_acc(acc);
    }
}

}

// ============================================================
// DMA helpers
// ============================================================
static int dma_reset_channel(const char *name, u32 cr_addr)
{
xil_printf("Reset %s...\r\n", name);

Xil_Out32(cr_addr, XAXIDMA_CR_RESET_MASK);

u32 timeout = 1000000U;

while ((Xil_In32(cr_addr) & XAXIDMA_CR_RESET_MASK) != 0U) {
    timeout--;

    if (timeout == 0U) {
        xil_printf("ERROR: reset timeout %s\r\n", name);
        return -1;
    }
}

xil_printf("Reset %s done\r\n", name);
return 0;

}

static void dma_start_mm2s(const char *name,
u32 cr_addr,
u32 sr_addr,
u32 sa_addr,
u32 sa_msb_addr,
u32 len_addr,
UINTPTR src_addr,
u32 length_bytes)
{
xil_printf("Start %s MM2S, addr=0x%08X, len=%lu\r\n",
name,
(u32)(src_addr & 0xFFFFFFFFU),
(unsigned long)length_bytes);

Xil_Out32(sr_addr, DMA_SR_ALL_IRQ);
Xil_Out32(cr_addr, XAXIDMA_CR_RUNSTOP_MASK);

Xil_Out32(sa_addr,     (u32)(src_addr & 0xFFFFFFFFU));
Xil_Out32(sa_msb_addr, (u32)((src_addr >> 32) & 0xFFFFFFFFU));

Xil_Out32(len_addr, length_bytes);

}

static void dma_start_s2mm(const char *name,
u32 cr_addr,
u32 sr_addr,
u32 da_addr,
u32 da_msb_addr,
u32 len_addr,
UINTPTR dst_addr,
u32 length_bytes)
{
xil_printf("Start %s S2MM, addr=0x%08X, len=%lu\r\n",
name,
(u32)(dst_addr & 0xFFFFFFFFU),
(unsigned long)length_bytes);

Xil_Out32(sr_addr, DMA_SR_ALL_IRQ);
Xil_Out32(cr_addr, XAXIDMA_CR_RUNSTOP_MASK);

Xil_Out32(da_addr,     (u32)(dst_addr & 0xFFFFFFFFU));
Xil_Out32(da_msb_addr, (u32)((dst_addr >> 32) & 0xFFFFFFFFU));

Xil_Out32(len_addr, length_bytes);

}

static int wait_dma_done(const char *name, u32 sr_addr)
{
xil_printf("Wait %s done...\r\n", name);

u32 timeout = 200000000U;

while (timeout > 0U) {
    u32 st = Xil_In32(sr_addr);

    if ((st & DMA_SR_ERR_MASK) != 0U) {
        xil_printf("ERROR: %s DMA error, status=0x%08X\r\n", name, st);
        return -1;
    }

    if ((st & DMA_SR_IOC_IRQ) != 0U) {
        xil_printf("%s done, status=0x%08X\r\n", name, st);
        return 0;
    }

    timeout--;
}

u32 final_st = Xil_In32(sr_addr);
xil_printf("ERROR: %s timeout, status=0x%08X\r\n", name, final_st);

return -2;

}

// ============================================================
// GEMM AXI-Lite helpers
// ============================================================
static int gemm_wait_idle(void)
{
u32 timeout = 10000000U;

while (timeout > 0U) {
    u32 st = Xil_In32(SHIFT_ADDR);

    if ((st & GEMM_IDLE_MASK) != 0U) {
        return 0;
    }

    timeout--;
}

xil_printf("ERROR: GEMM wait idle timeout, status=0x%08X\r\n",
           Xil_In32(SHIFT_ADDR));
return -1;

}

static int gemm_wait_done(void)
{
u32 timeout = 200000000U;

while (timeout > 0U) {
    u32 st = Xil_In32(SHIFT_ADDR);

    if ((st & GEMM_DONE_MASK) != 0U) {
        xil_printf("GEMM done, status=0x%08X\r\n", st);
        return 0;
    }

    timeout--;
}

xil_printf("ERROR: GEMM wait done timeout, status=0x%08X\r\n",
           Xil_In32(SHIFT_ADDR));
return -1;

}

static void gemm_clear_done_if_needed(void)
{
u32 st = Xil_In32(SHIFT_ADDR);

if ((st & GEMM_DONE_MASK) != 0U) {
    xil_printf("Clear previous GEMM done/status, status=0x%08X\r\n", st);

    Xil_Out32(SHIFT_ADDR, (R_SHIFT & GEMM_SHIFT_MASK) | GEMM_CLEAR_DONE_MASK);
    Xil_Out32(SHIFT_ADDR, (R_SHIFT & GEMM_SHIFT_MASK));
}

}

static int gemm_write_config(u32 row_count, u32 k_block_count, u32 n_block_count)
{
xil_printf("Write GEMM config...\r\n");

if (gemm_wait_idle() != 0) {
    return -1;
}

gemm_clear_done_if_needed();

Xil_Out32(SHIFT_ADDR, (R_SHIFT & GEMM_SHIFT_MASK));
Xil_Out32(FL_ADDR, row_count);
Xil_Out32(FWBN_ADDR, k_block_count);
Xil_Out32(WWBN_ADDR, n_block_count);

u32 shift_raw = Xil_In32(SHIFT_ADDR);
u32 fl_raw    = Xil_In32(FL_ADDR);
u32 fwbn_raw  = Xil_In32(FWBN_ADDR);
u32 wwbn_raw  = Xil_In32(WWBN_ADDR);

xil_printf("Readback SHIFT raw = 0x%08X, shift=%lu\r\n",
           shift_raw,
           (unsigned long)(shift_raw & GEMM_SHIFT_MASK));
xil_printf("Readback FL        = 0x%08X\r\n", fl_raw);
xil_printf("Readback FWBN      = 0x%08X\r\n", fwbn_raw);
xil_printf("Readback WWBN      = 0x%08X\r\n", wwbn_raw);

if ((shift_raw & GEMM_SHIFT_MASK) != (R_SHIFT & GEMM_SHIFT_MASK)) {
    xil_printf("ERROR: SHIFT readback mismatch\r\n");
    return -2;
}

if (fl_raw != row_count) {
    xil_printf("ERROR: FL readback mismatch\r\n");
    return -3;
}

if (fwbn_raw != k_block_count) {
    xil_printf("ERROR: FWBN readback mismatch\r\n");
    return -4;
}

if (wwbn_raw != n_block_count) {
    xil_printf("ERROR: WWBN readback mismatch\r\n");
    return -5;
}

return 0;

}

// ============================================================
// Bus smoke test
// Read DMA first, then GEMM.
// This helps detect stale bitstream/platform/AXI issues.
// ============================================================
static int bus_smoke_test(void)
{
xil_printf("READ DMA0 status...\r\n");
u32 dma0 = Xil_In32(FEATURE_MM2S_DMASR);
xil_printf("DMA0 MM2S status = 0x%08X\r\n", dma0);

xil_printf("READ DMA1 status...\r\n");
u32 dma1 = Xil_In32(WEIGHT_MM2S_DMASR);
xil_printf("DMA1 MM2S status = 0x%08X\r\n", dma1);

xil_printf("READ DMA2 status...\r\n");
u32 dma2 = Xil_In32(RESULT_S2MM_DMASR);
xil_printf("DMA2 S2MM status = 0x%08X\r\n", dma2);

xil_printf("READ GEMM status...\r\n");
u32 gemm = Xil_In32(SHIFT_ADDR);
xil_printf("GEMM status = 0x%08X\r\n", gemm);

return 0;

}

// ============================================================
// Hardware GEMM
// ============================================================
static int gemm_hard(void)
{
xil_printf("stage 0: bus smoke test\r\n");

if (bus_smoke_test() != 0) {
    return -1;
}

xil_printf("stage 1: write GEMM registers\r\n");

u32 row_count     = IN_ROWS_NUM;
u32 k_block_count = (IN_COLS_NUM  + A_SIZE - 1U) / A_SIZE;
u32 n_block_count = (OUT_COLS_NUM + A_SIZE - 1U) / A_SIZE;

xil_printf("row_count=%lu, k_block_count=%lu, n_block_count=%lu\r\n",
           (unsigned long)row_count,
           (unsigned long)k_block_count,
           (unsigned long)n_block_count);

if (gemm_write_config(row_count, k_block_count, n_block_count) != 0) {
    return -2;
}

xil_printf("stage 2: reset DMA\r\n");

if (dma_reset_channel("DMA0 feature", FEATURE_MM2S_DMACR) != 0) {
    return -3;
}

if (dma_reset_channel("DMA1 weight", WEIGHT_MM2S_DMACR) != 0) {
    return -4;
}

if (dma_reset_channel("DMA2 result", RESULT_S2MM_DMACR) != 0) {
    return -5;
}

xil_printf("stage 3: cache maintenance\r\n");

Xil_DCacheFlushRange((INTPTR)A_buf, MATRIX_A_BYTES);
Xil_DCacheFlushRange((INTPTR)B_buf, MATRIX_B_BYTES);
Xil_DCacheFlushRange((INTPTR)C_hw, MATRIX_C_BYTES);

xil_printf("stage 4: start result DMA S2MM first\r\n");

dma_start_s2mm("DMA2 result",
               RESULT_S2MM_DMACR,
               RESULT_S2MM_DMASR,
               RESULT_S2MM_DA,
               RESULT_S2MM_DA_MSB,
               RESULT_S2MM_LENGTH,
               (UINTPTR)C_hw,
               MATRIX_C_BYTES);

xil_printf("stage 5: start feature DMA MM2S\r\n");

dma_start_mm2s("DMA0 feature",
               FEATURE_MM2S_DMACR,
               FEATURE_MM2S_DMASR,
               FEATURE_MM2S_SA,
               FEATURE_MM2S_SA_MSB,
               FEATURE_MM2S_LENGTH,
               (UINTPTR)A_buf,
               MATRIX_A_BYTES);

xil_printf("stage 6: start weight DMA MM2S\r\n");

dma_start_mm2s("DMA1 weight",
               WEIGHT_MM2S_DMACR,
               WEIGHT_MM2S_DMASR,
               WEIGHT_MM2S_SA,
               WEIGHT_MM2S_SA_MSB,
               WEIGHT_MM2S_LENGTH,
               (UINTPTR)B_buf,
               MATRIX_B_BYTES);

xil_printf("stage 7: wait DMA done\r\n");

if (wait_dma_done("DMA0 feature", FEATURE_MM2S_DMASR) != 0) {
    return -6;
}

if (wait_dma_done("DMA1 weight", WEIGHT_MM2S_DMASR) != 0) {
    return -7;
}

if (wait_dma_done("DMA2 result", RESULT_S2MM_DMASR) != 0) {
    return -8;
}

xil_printf("stage 8: wait GEMM done status\r\n");

if (gemm_wait_done() != 0) {
    return -9;
}

xil_printf("stage 9: invalidate result cache\r\n");

Xil_DCacheInvalidateRange((INTPTR)C_hw, MATRIX_C_BYTES);

xil_printf("Hardware GEMM done\r\n");

return 0;

}

// ============================================================
// Result check
// ============================================================
static int compare_result(void)
{
int mismatch_count = 0;

for (u32 i = 0U; i < MATRIX_C_BYTES; i++) {
    if (C_sw[i] != C_hw[i]) {
        if (mismatch_count < 16) {
            xil_printf("Mismatch i=%lu, sw=%d, hw=%d\r\n",
                       (unsigned long)i,
                       (int)C_sw[i],
                       (int)C_hw[i]);
        }

        mismatch_count++;
    }
}

if (mismatch_count == 0) {
    xil_printf("COMPARE PASS\r\n");
    return 0;
}

xil_printf("COMPARE FAIL, mismatch_count=%d / %lu\r\n",
           mismatch_count,
           (unsigned long)MATRIX_C_BYTES);

return -1;

}

static void print_result_sample(void)
{
xil_printf("C_hw sample 8x8:\r\n");

for (u32 r = 0U; r < 8U; r++) {
    for (u32 c = 0U; c < 8U; c++) {
        xil_printf("%4d ", (int)C_hw[r * OUT_COLS_NUM + c]);
    }

    xil_printf("\r\n");
}

}

// ============================================================
// Main
// ============================================================
int main()
{
xil_printf("\r\n===== GEMM 32x32 DMA TEST START =====\r\n");

xil_printf("MM_ADDR          = 0x%08X\r\n", MM_ADDR);
xil_printf("FEATURE_DMA_ADDR = 0x%08X\r\n", FEATURE_DMA_ADDR);
xil_printf("WEIGHT_DMA_ADDR  = 0x%08X\r\n", WEIGHT_DMA_ADDR);
xil_printf("RESULT_DMA_ADDR  = 0x%08X\r\n", RESULT_DMA_ADDR);

xil_printf("A_SIZE=%lu, MATRIX_A_BYTES=%lu, MATRIX_B_BYTES=%lu, MATRIX_C_BYTES=%lu\r\n",
           (unsigned long)A_SIZE,
           (unsigned long)MATRIX_A_BYTES,
           (unsigned long)MATRIX_B_BYTES,
           (unsigned long)MATRIX_C_BYTES);

init_matrices();

xil_printf("Software GEMM start\r\n");
gemm_soft();
xil_printf("Software GEMM done\r\n");

int hard_ret = gemm_hard();

if (hard_ret != 0) {
    xil_printf("Hardware GEMM failed, ret=%d\r\n", hard_ret);

    while (1) {
        ;
    }
}

print_result_sample();

compare_result();

xil_printf("===== GEMM 32x32 DMA TEST END =====\r\n");

while (1) {
    ;
}

return 0;

}
