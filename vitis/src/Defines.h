#ifndef SRC_DEFINES_H_
#define SRC_DEFINES_H_

#include "xil_types.h"
#include "xparameters.h"
#include "xaxidma_hw.h"

// ============================================================
// Cache / data type
// ============================================================
#define CACHE_LINE_SIZE 32U

#define DATA_TYPE s8
#define MAX_LIMIT 127
#define MIN_LIMIT -128

// ============================================================
// GEMM_TOP AXI-Lite base address
// ============================================================
// Current xparameters.h from the new platform uses:
// XPAR_GEMM_DSP_IP_0_BASEADDR = 0xA0000000
//
// Keep fallback for older exported names.
#if defined(XPAR_GEMM_DSP_IP_0_BASEADDR)
#define MM_ADDR XPAR_GEMM_DSP_IP_0_BASEADDR
#elif defined(XPAR_GEMM_TOP_0_BASEADDR)
#define MM_ADDR XPAR_GEMM_TOP_0_BASEADDR
#else
#error "Cannot find GEMM IP base address macro in xparameters.h"
#endif

#define SHIFT_ADDR (MM_ADDR + 0x00U)
#define FL_ADDR (MM_ADDR + 0x04U)
#define FWBN_ADDR (MM_ADDR + 0x08U)
#define WWBN_ADDR (MM_ADDR + 0x0CU)

// ============================================================
// AXI DMA base addresses
// DMA 0: Feature input
// DMA 1: Weight input
// DMA 2: Result output
// ============================================================
#define FEATURE_DMA_ADDR XPAR_AXI_DMA_0_BASEADDR
#define WEIGHT_DMA_ADDR XPAR_AXI_DMA_1_BASEADDR
#define RESULT_DMA_ADDR XPAR_AXI_DMA_2_BASEADDR

// ============================================================
// AXI DMA MM2S register map
// MM2S = Memory Map to Stream = DDR -> accelerator
// ============================================================
#define FEATURE_MM2S_DMACR (FEATURE_DMA_ADDR + XAXIDMA_TX_OFFSET + XAXIDMA_CR_OFFSET)
#define FEATURE_MM2S_DMASR (FEATURE_DMA_ADDR + XAXIDMA_TX_OFFSET + XAXIDMA_SR_OFFSET)
#define FEATURE_MM2S_SA (FEATURE_DMA_ADDR + XAXIDMA_TX_OFFSET + XAXIDMA_SRCADDR_OFFSET)
#define FEATURE_MM2S_SA_MSB (FEATURE_DMA_ADDR + XAXIDMA_TX_OFFSET + XAXIDMA_SRCADDR_MSB_OFFSET)
#define FEATURE_MM2S_LENGTH (FEATURE_DMA_ADDR + XAXIDMA_TX_OFFSET + XAXIDMA_BUFFLEN_OFFSET)

#define WEIGHT_MM2S_DMACR (WEIGHT_DMA_ADDR + XAXIDMA_TX_OFFSET + XAXIDMA_CR_OFFSET)
#define WEIGHT_MM2S_DMASR (WEIGHT_DMA_ADDR + XAXIDMA_TX_OFFSET + XAXIDMA_SR_OFFSET)
#define WEIGHT_MM2S_SA (WEIGHT_DMA_ADDR + XAXIDMA_TX_OFFSET + XAXIDMA_SRCADDR_OFFSET)
#define WEIGHT_MM2S_SA_MSB (WEIGHT_DMA_ADDR + XAXIDMA_TX_OFFSET + XAXIDMA_SRCADDR_MSB_OFFSET)
#define WEIGHT_MM2S_LENGTH (WEIGHT_DMA_ADDR + XAXIDMA_TX_OFFSET + XAXIDMA_BUFFLEN_OFFSET)

// ============================================================
// AXI DMA S2MM register map
// S2MM = Stream to Memory Map = accelerator -> DDR
// ============================================================
#ifndef XAXIDMA_DESTADDR_OFFSET
#define XAXIDMA_DESTADDR_OFFSET XAXIDMA_SRCADDR_OFFSET
#endif

#ifndef XAXIDMA_DESTADDR_MSB_OFFSET
#define XAXIDMA_DESTADDR_MSB_OFFSET XAXIDMA_SRCADDR_MSB_OFFSET
#endif

#define RESULT_S2MM_DMACR (RESULT_DMA_ADDR + XAXIDMA_RX_OFFSET + XAXIDMA_CR_OFFSET)
#define RESULT_S2MM_DMASR (RESULT_DMA_ADDR + XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET)
#define RESULT_S2MM_DA (RESULT_DMA_ADDR + XAXIDMA_RX_OFFSET + XAXIDMA_DESTADDR_OFFSET)
#define RESULT_S2MM_DA_MSB (RESULT_DMA_ADDR + XAXIDMA_RX_OFFSET + XAXIDMA_DESTADDR_MSB_OFFSET)
#define RESULT_S2MM_LENGTH (RESULT_DMA_ADDR + XAXIDMA_RX_OFFSET + XAXIDMA_BUFFLEN_OFFSET)

// ============================================================
// DMA status / control masks
// ============================================================
#ifndef XAXIDMA_CR_RUNSTOP_MASK
#define XAXIDMA_CR_RUNSTOP_MASK 0x00000001U
#endif

#ifndef XAXIDMA_CR_RESET_MASK
#define XAXIDMA_CR_RESET_MASK 0x00000004U
#endif

#ifndef XAXIDMA_IDLE_MASK
#define XAXIDMA_IDLE_MASK 0x00000002U
#endif

#define DMA_ERROR_MASK 0x00000070U

#define DMA_SR_IDLE 0x00000002U
#define DMA_SR_IOC_IRQ 0x00001000U
#define DMA_SR_ERR_IRQ 0x00004000U
#define DMA_SR_ALL_IRQ 0x00007000U
#define DMA_SR_ERR_MASK 0x00004070U

// ============================================================
// GEMM status bits in SHIFT/status register
// ============================================================
#define GEMM_SHIFT_MASK 0x000003FFU
#define GEMM_CLEAR_DONE_MASK 0x00010000U
#define GEMM_BUSY_MASK 0x01000000U
#define GEMM_DONE_MASK 0x02000000U
#define GEMM_IDLE_MASK 0x04000000U

// ============================================================
// Systolic array / accelerator parameters
// ============================================================
#define A_SIZE 32U

// RTL register field widths
// shift: 10 bits
// F_length / row_count: 9 bits
// F_width_block_num / k_block_count: 5 bits
// W_width_block_num / n_block_count: 5 bits
#define F_length_width 9U
#define F_width_block_num_width 5U
#define W_width_block_num_width 5U
#define shift_width 10U

#define F_LENGTH_MAX ((1U << F_length_width) - 1U)
#define F_WIDTH_BLOCK_NUM_MAX ((1U << F_width_block_num_width) - 1U)
#define W_WIDTH_BLOCK_NUM_MAX ((1U << W_width_block_num_width) - 1U)

#define F_WIDTH_MAX (F_WIDTH_BLOCK_NUM_MAX * A_SIZE)
#define W_WIDTH_MAX (W_WIDTH_BLOCK_NUM_MAX * A_SIZE)

#endif
