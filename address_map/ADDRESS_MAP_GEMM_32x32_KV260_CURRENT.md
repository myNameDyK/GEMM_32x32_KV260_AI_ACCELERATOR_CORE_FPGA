# Address Map — GEMM 32×32 INT8 on KV260

This document records the verified AXI address map, GEMM control registers, DMA register offsets, and run order for the 32×32 INT8 GEMM accelerator on the Xilinx Kria KV260.

## 1. Target Platform

| Item             | Value                      |
| ---------------- | -------------------------- |
| Board            | Xilinx Kria KV260          |
| Device           | K26, `xck26-sfvc784-2LV-c` |
| Tools            | Vivado / Vitis 2022.2      |
| CPU              | Cortex-A53 #0              |
| AXI-Stream width | 256 bits                   |
| Data type        | INT8                       |

## 2. AXI Address Map

| Block           | Function            | Base Address | Vitis Macro                   |
| --------------- | ------------------- | -----------: | ----------------------------- |
| `GEMM_DSP_IP_0` | GEMM control/status | `0xA0000000` | `XPAR_GEMM_DSP_IP_0_BASEADDR` |
| `axi_dma_0`     | Feature input, MM2S | `0xA0010000` | `XPAR_AXI_DMA_0_BASEADDR`     |
| `axi_dma_1`     | Weight input, MM2S  | `0xA0020000` | `XPAR_AXI_DMA_1_BASEADDR`     |
| `axi_dma_2`     | Result output, S2MM | `0xA0030000` | `XPAR_AXI_DMA_2_BASEADDR`     |

Recommended aliases:

```c
#define MM_ADDR          XPAR_GEMM_DSP_IP_0_BASEADDR
#define FEATURE_DMA_ADDR XPAR_AXI_DMA_0_BASEADDR
#define WEIGHT_DMA_ADDR  XPAR_AXI_DMA_1_BASEADDR
#define RESULT_DMA_ADDR  XPAR_AXI_DMA_2_BASEADDR
```

> Do not edit `xparameters.h` manually. Re-export the hardware platform after changing the Vivado block design.

## 3. GEMM Register Map

| Register            | Offset | Address          | Description                               |
| ------------------- | -----: | ---------------- | ----------------------------------------- |
| `SHIFT_STATUS`      | `0x00` | `MM_ADDR + 0x00` | Write output shift; read shift and status |
| `F_LENGTH`          | `0x04` | `MM_ADDR + 0x04` | Number of feature/output rows             |
| `F_WIDTH_BLOCK_NUM` | `0x08` | `MM_ADDR + 0x08` | Number of K blocks                        |
| `W_WIDTH_BLOCK_NUM` | `0x0C` | `MM_ADDR + 0x0C` | Number of N blocks                        |

### Status bits at offset `0x00`

|    Bits | Meaning            |
| ------: | ------------------ |
| `[9:0]` | Shift value        |
|  `[16]` | Clear-done request |
|  `[24]` | Busy               |
|  `[25]` | Done               |
|  `[26]` | Idle               |

Example configuration for one 32×32 GEMM:

```c
Xil_Out32(MM_ADDR + 0x00, 0);   // SHIFT
Xil_Out32(MM_ADDR + 0x04, 32);  // F_LENGTH
Xil_Out32(MM_ADDR + 0x08, 1);   // K blocks
Xil_Out32(MM_ADDR + 0x0C, 1);   // N blocks
```

Expected idle readback:

```text
SHIFT_STATUS = 0x04000000
F_LENGTH     = 0x00000020
K_BLOCKS     = 0x00000001
N_BLOCKS     = 0x00000001
```

## 4. AXI DMA Register Offsets

### MM2S — DMA0 and DMA1

| Register      | Offset |
| ------------- | -----: |
| `MM2S_DMACR`  | `0x00` |
| `MM2S_DMASR`  | `0x04` |
| `MM2S_SA`     | `0x18` |
| `MM2S_SA_MSB` | `0x1C` |
| `MM2S_LENGTH` | `0x28` |

### S2MM — DMA2

| Register      | Offset |
| ------------- | -----: |
| `S2MM_DMACR`  | `0x30` |
| `S2MM_DMASR`  | `0x34` |
| `S2MM_DA`     | `0x48` |
| `S2MM_DA_MSB` | `0x4C` |
| `S2MM_LENGTH` | `0x58` |

Write the DMA address first and write `LENGTH` last. Writing `LENGTH` starts a simple-mode transfer.

## 5. Transfer Size

For a 32×32 INT8 matrix:

```text
32 × 32 × 1 byte = 1024 bytes
```

Each AXI-Stream beat transfers:

```text
256 bits = 32 bytes
```

Therefore:

```text
1024 / 32 = 32 AXI-Stream beats
```

| Buffer           |       Size |
| ---------------- | ---------: |
| Feature matrix A | 1024 bytes |
| Weight matrix B  | 1024 bytes |
| Result matrix C  | 1024 bytes |

## 6. Required DMA Start Order

```text
1. Configure GEMM registers.
2. Flush feature, weight, and result buffers.
3. Start DMA2 S2MM.
4. Start DMA0 MM2S for feature data.
5. Start DMA1 MM2S for weight data.
6. Wait for DMA0, DMA1, and DMA2 completion.
7. Wait for GEMM done.
8. Invalidate the result buffer.
9. Compare against the software reference.
```

DMA2 must start first so the result path is ready before the accelerator produces output.

## 7. Cache Requirements

Use at least 32-byte alignment; 64-byte alignment is recommended.

```cpp
alignas(64) static int8_t A_buf[1024];
alignas(64) static int8_t B_buf[1024];
alignas(64) static int8_t C_hw[1024];
```

Before DMA:

```c
Xil_DCacheFlushRange((INTPTR)A_buf, 1024);
Xil_DCacheFlushRange((INTPTR)B_buf, 1024);
Xil_DCacheFlushRange((INTPTR)C_hw, 1024);
```

After DMA2 completes:

```c
Xil_DCacheInvalidateRange((INTPTR)C_hw, 1024);
```

## 8. Verified Status

Typical DMA status values:

|        Value | Meaning                    |
| -----------: | -------------------------- |
| `0x00000001` | Halted before transfer     |
| `0x00001002` | Transfer complete and idle |

Verified result:

```text
DMA0 feature done, status=0x00001002
DMA1 weight done, status=0x00001002
DMA2 result done, status=0x00001002
GEMM done, status=0x06000000
COMPARE PASS
```

This confirms that the hardware output matches the software reference for the verified 32×32 INT8 test.
