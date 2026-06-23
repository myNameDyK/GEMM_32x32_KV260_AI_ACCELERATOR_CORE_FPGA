#pragma once
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    FPGA_QUANT_Q5_0 = 0,
    FPGA_QUANT_Q8_0 = 1,
    FPGA_QUANT_Q4_K = 2,
} FpgaQuantType;

bool fpga_gemm_init();
void fpga_gemm_cleanup();
bool fpga_gemm_is_ready();

void fpga_gemm_run(const void *  A_raw,  // weight quantized [K × N]
                   FpgaQuantType quant,
                   const float * B_f32,  // activation F32   [M × K]
                   float *       C,      // output F32        [M × N]
                   int           M,
                   int           K_orig,
                   int           N_orig,
                   int           shift  // 0 = auto
);

#ifdef __cplusplus
}
#endif
