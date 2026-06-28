# GEMM Accelerator Software Programming Guide

Source of truth:

```text
Project: E:/Everything_with_VIVADO/MM_final_DSP/MM_final.xpr
RTL:     E:/Everything_with_VIVADO/MM_final_DSP/MM_final.srcs/sources_1/imports/src
IP:      E:/Everything_with_VIVADO/MM_final_DSP/MM_final.srcs/sources_1/ip/mult_IP/mult_IP.xci
```

This guide describes how PS/software should configure and drive the current `GEMM_top` IP. The behavior below is based on the active RTL source folder, not on older `CODEX_tmp/rtl_newname/src` files.

## Project/IP Overview

`GEMM_top` exposes:

- One 32-bit AXI-Lite slave control interface.
- One 256-bit AXI-Stream slave for feature matrix data.
- One 256-bit AXI-Stream slave for weight matrix data.
- One 256-bit AXI-Stream master for result data.

The compute array is 32 lanes wide with signed INT8 feature and weight lanes. Each stream beat contains 32 signed 8-bit values. Internally, the design accumulates partial sums, applies a configurable arithmetic right shift with rounding/saturation, and streams signed 8-bit results.

No separate AXI-Lite start bit exists. A job becomes active when the first feature or weight stream word is accepted, and it finishes when the final result word is accepted by the result stream master.

## Register Map

The AXI-Lite data width is 32 bits. The address width is 4 bits. With the active RTL decode, the software-visible byte offsets are:

| Offset | Register | Access | Meaning |
|---:|---|---|---|
| `0x00` | Shift/status register | RW/RO mixed | Write bits `[9:0]` for `shift`; write bit `16` as a one-cycle done/status clear request. Read returns `shift` plus job status bits. |
| `0x04` | Row count / `F_length` | RW | Number of output rows / feature rows to process. |
| `0x08` | K block count / `F_width_block_num` | RW | Number of 32-wide K blocks in the feature/weight inner dimension. |
| `0x0C` | N block count / `W_width_block_num` | RW | Number of 32-column output/weight blocks. |

Use full-word writes with `WSTRB = 4'b1111` unless intentionally doing byte writes.

## Register Details

### Offset `0x00`: Shift/Status

Write behavior:

| Bits | Name | Meaning |
|---|---|---|
| `[9:0]` | `shift` | Arithmetic right-shift amount used during output quantization. |
| `[16]` | clear request | Write `1` to request done/status clear. The RTL clears stored bit 16 back to `0` after the write cycle. |

Read behavior:

| Bits | Name | Meaning |
|---|---|---|
| `[9:0]` | `shift` | Current stored shift value. |
| `[23:10]` | reserved | Reads as `0`. |
| `[24]` | `busy` | `1` after input stream acceptance or result activity, until final result is accepted. |
| `[25]` | `done` | `1` after the final result beat handshakes. Cleared by accepted clear request while idle. |
| `[26]` | `idle` | Inverse of `busy`. |
| `[27]` | `clear_accepted` | One-clock pulse when software writes clear while the job is idle. May be missed by slow polling. |
| `[28]` | `clear_busy_error` | One-clock pulse when software writes clear while the job is busy. May be missed by slow polling. |
| `[31:29]` | reserved | Reads as `0`. |

Practical note: because bit 16 shares the same register as `shift`, clear with `(shift & 0x3ff) | (1u << 16)` if you want to preserve the shift value.

### Offset `0x04`: `row_count` / `F_length`

`row_count` is `slv_reg1[8:0]`. It is the number of feature rows and result rows. For a 32x32 matrix multiply, use `32`. For a 64x64 multiply, use `64`.

### Offset `0x08`: `k_block_count` / `F_width_block_num`

`k_block_count` is `slv_reg2[4:0]`. It is the number of K tiles, where each tile is 32 elements wide:

```c
k_block_count = (K + 31) / 32;
```

For `K = 32`, use `1`. For `K = 64`, use `2`.

### Offset `0x0C`: `n_block_count` / `W_width_block_num`

`n_block_count` is `slv_reg3[4:0]`. It is the number of 32-column output tiles:

```c
n_block_count = (N + 31) / 32;
```

For `N = 32`, use `1`. For `N = 64`, use `2`.

## AXI-Lite Write Sequence

1. Poll register `0x00` until `idle` bit 26 is `1`.
2. If `done` bit 25 is set from a previous job, write register `0x00` with the desired `shift` plus bit 16 set.
3. Write register `0x00` with the desired `shift` value.
4. Write register `0x04` with `row_count`.
5. Write register `0x08` with `k_block_count`.
6. Write register `0x0C` with `n_block_count`.
7. Start DMA, with result S2MM first, then feature and weight MM2S.

AXI-Lite writes are byte-enabled in the RTL. Full 32-bit writes are the simplest and least surprising software interface.

## AXI-Lite Readback Sequence

Read register `0x00` for status. The AXI-Lite slave captures read address and returns one 32-bit data beat. A software poll loop should check:

```c
status = Xil_In32(base + 0x00);
busy = (status >> 24) & 1;
done = (status >> 25) & 1;
idle = (status >> 26) & 1;
```

Read `0x04`, `0x08`, and `0x0C` to confirm the stored configuration registers if needed. During an active job, these readback registers can change if software writes them, but the active datapath uses frozen copies described below.

## Busy, Done, Idle, and Clear Behavior

`busy` is set when a feature word is accepted, a weight word is accepted, or the result stream is active. `busy` is cleared when the final result beat handshakes on the result stream.

`done` is set at the same final result handshake. `done` is cleared only when software writes bit 16 while the job is idle.

`idle` is `~busy`.

If software writes clear while idle, `done` is cleared and `clear_accepted` pulses for one clock. If software writes clear while busy, the job is not aborted, `done` is not cleared, and `clear_busy_error` pulses for one clock. The pulse-like bits are useful in simulation but may be hard to observe by normal software polling.

## Config-Freeze Behavior

`GemmAccelerator` copies `shift`, `row_count`, `k_block_count`, and `n_block_count` into internal registers only while the core is inactive. Once any input beat is accepted or internal/output activity is present, those frozen values drive the active job.

Software may write AXI-Lite configuration registers during a job, but those writes are intended for a later job. Do not expect mid-job writes to change the active computation.

## AXI-Stream Common Rules

All three stream interfaces are 256 bits wide:

```text
32 lanes * 8 bits/lane = 256 bits
```

Lane mapping:

| Lane | Bits |
|---:|---|
| 0 | `[7:0]` |
| 1 | `[15:8]` |
| ... | ... |
| 31 | `[255:248]` |

Feature and weight slave adapters accept only full beats:

```verilog
w_full_beat = &TSTRB
```

For the 256-bit streams, software/DMA must drive:

```text
TSTRB = 32'hFFFF_FFFF
```

Partial `TSTRB` causes the adapter to withhold `TREADY`; the partial-beat error flag is internal only.

## Feature Input Format

Each feature beat contains 32 signed INT8 values from one feature row and one K block.

Recommended sequence:

```text
for row = 0 .. row_count-1:
  for k_block = 0 .. k_block_count-1:
    send one 256-bit beat
```

Within a beat:

```text
lane -> K index = k_block * 32 + lane
```

If the true K dimension is not a multiple of 32, pad unused lanes with zero.

`TLAST` should be asserted only on the final feature beat of the job. The input buffer uses `TLAST` to reset its feature write address, so early `TLAST` can corrupt the buffered feature layout.

Feature beat count:

```c
feature_beats = row_count * k_block_count;
```

## Weight Input Format

Each weight beat contains 32 signed INT8 weight values for one K element and one 32-column N block.

Recommended sequence:

```text
for k_block = 0 .. k_block_count-1:
  for k_lane = 0 .. 31:
    for n_block = 0 .. n_block_count-1:
      send one 256-bit beat
```

Within a beat:

```text
K index -> k_block * 32 + k_lane
N index -> n_block * 32 + lane
```

If the true K or N dimension is not a multiple of 32, pad unused values with zero.

`TLAST` should be asserted only on the final weight beat of the job. The input buffer uses `TLAST` to reset its weight write address.

Weight beat count:

```c
weight_beats = (k_block_count * 32) * n_block_count;
```

## Result Output Format

Each result beat contains 32 signed INT8 output values for one output row and one 32-column N block.

Observed RTL output sequence:

```text
for row = 0 .. row_count-1:
  for n_block = 0 .. n_block_count-1:
    receive one 256-bit beat
```

Within a beat:

```text
N index -> n_block * 32 + lane
```

Ignore padded lanes for columns beyond the true N dimension.

The result stream master drives all result `TSTRB` bits high. `TLAST` is asserted on the last result beat:

```c
result_beats = row_count * n_block_count;
```

## Matrix Tiling Rules

The array size is 32. Software should tile matrix dimensions as:

```c
row_count     = M;
k_block_count = (K + 31) / 32;
n_block_count = (N + 31) / 32;
padded_K      = k_block_count * 32;
padded_N      = n_block_count * 32;
```

Feature data is padded across K lanes. Weight data is padded across K rows and N columns. Result data returns padded N lanes; software keeps only valid columns.

## Example: 32x32

For `M = 32`, `K = 32`, `N = 32`:

| Setting | Value |
|---|---:|
| `row_count` | `32` |
| `k_block_count` | `1` |
| `n_block_count` | `1` |
| `feature_beats` | `32` |
| `weight_beats` | `32` |
| `result_beats` | `32` |

Register writes:

```c
Xil_Out32(base + 0x00, shift & 0x3ff);
Xil_Out32(base + 0x04, 32);
Xil_Out32(base + 0x08, 1);
Xil_Out32(base + 0x0c, 1);
```

## Example: 64x64 on the 32x32 Array

For `M = 64`, `K = 64`, `N = 64`:

| Setting | Value |
|---|---:|
| `row_count` | `64` |
| `k_block_count` | `2` |
| `n_block_count` | `2` |
| `feature_beats` | `128` |
| `weight_beats` | `128` |
| `result_beats` | `128` |

The design computes two K blocks and two N column blocks. `OutputBuffer` accumulates across the two K blocks before streaming final quantized INT8 results.

Register writes:

```c
Xil_Out32(base + 0x00, shift & 0x3ff);
Xil_Out32(base + 0x04, 64);
Xil_Out32(base + 0x08, 2);
Xil_Out32(base + 0x0c, 2);
```

## DMA Order

Use this order:

1. Prepare and flush feature and weight buffers.
2. Prepare and invalidate or clean the result buffer as required by the platform cache policy.
3. Start result S2MM DMA first.
4. Start feature and weight MM2S DMA channels.
5. Wait for both MM2S channels and S2MM channel to complete.
6. Poll `done` or confirm the final result transfer.
7. Invalidate the result buffer before reading it from software.

Starting S2MM late can backpressure or stall result delivery. Starting it first is the simplest reliable sequence.

## Cache Notes for Vitis/Bare-Metal

Before MM2S:

```c
Xil_DCacheFlushRange((UINTPTR)feature_buf, feature_bytes);
Xil_DCacheFlushRange((UINTPTR)weight_buf, weight_bytes);
```

Before or after S2MM, follow the platform DMA cache discipline. A common bare-metal pattern is to invalidate the result range after DMA completion and before CPU reads:

```c
Xil_DCacheInvalidateRange((UINTPTR)result_buf, result_bytes);
```

If the result buffer was previously written by the CPU, clean or invalidate it according to the DMA/cache policy used by the BSP.

## Minimal One-Job Pseudo-Code

```c
#define REG_SHIFT_STATUS 0x00u
#define REG_ROW_COUNT    0x04u
#define REG_K_BLOCKS     0x08u
#define REG_N_BLOCKS     0x0cu

static void gemm_wait_idle(uintptr_t base) {
    while (((Xil_In32(base + REG_SHIFT_STATUS) >> 26) & 1u) == 0u) {
        ;
    }
}

static void gemm_clear_done(uintptr_t base, uint32_t shift) {
    Xil_Out32(base + REG_SHIFT_STATUS, (shift & 0x3ffu) | (1u << 16));
}

void gemm_run_one(uintptr_t base,
                  void *feature_buf, size_t feature_bytes,
                  void *weight_buf,  size_t weight_bytes,
                  void *result_buf,  size_t result_bytes,
                  uint32_t shift, uint32_t rows,
                  uint32_t k_blocks, uint32_t n_blocks) {
    gemm_wait_idle(base);

    if ((Xil_In32(base + REG_SHIFT_STATUS) >> 25) & 1u) {
        gemm_clear_done(base, shift);
    }

    Xil_Out32(base + REG_SHIFT_STATUS, shift & 0x3ffu);
    Xil_Out32(base + REG_ROW_COUNT, rows);
    Xil_Out32(base + REG_K_BLOCKS, k_blocks);
    Xil_Out32(base + REG_N_BLOCKS, n_blocks);

    Xil_DCacheFlushRange((UINTPTR)feature_buf, feature_bytes);
    Xil_DCacheFlushRange((UINTPTR)weight_buf, weight_bytes);

    dma_start_s2mm(result_buf, result_bytes);
    dma_start_mm2s_feature(feature_buf, feature_bytes);
    dma_start_mm2s_weight(weight_buf, weight_bytes);

    dma_wait_mm2s_feature();
    dma_wait_mm2s_weight();
    dma_wait_s2mm();

    while (((Xil_In32(base + REG_SHIFT_STATUS) >> 25) & 1u) == 0u) {
        ;
    }

    Xil_DCacheInvalidateRange((UINTPTR)result_buf, result_bytes);
}
```

## Minimal Two Back-to-Back Jobs

```c
void gemm_run_two_jobs(uintptr_t base, struct job *a, struct job *b) {
    gemm_run_one(base,
                 a->feature, a->feature_bytes,
                 a->weight,  a->weight_bytes,
                 a->result,  a->result_bytes,
                 a->shift, a->rows, a->k_blocks, a->n_blocks);

    gemm_wait_idle(base);
    gemm_clear_done(base, b->shift);

    gemm_run_one(base,
                 b->feature, b->feature_bytes,
                 b->weight,  b->weight_bytes,
                 b->result,  b->result_bytes,
                 b->shift, b->rows, b->k_blocks, b->n_blocks);
}
```

The two-job 64x64 no-reset simulation passed, so normal back-to-back operation is simulation-verified.

## Common Mistakes

- Using word indices instead of byte offsets. The active offsets are `0x00`, `0x04`, `0x08`, and `0x0C`.
- Sending feature or weight stream beats with partial `TSTRB`; use `32'hFFFF_FFFF`.
- Asserting `TLAST` before the final feature or weight beat.
- Forgetting that result `TLAST` is produced by the IP on the final result beat.
- Changing configuration registers mid-job and expecting the active job to change.
- Starting result S2MM after feature/weight MM2S.
- Forgetting to flush feature/weight buffers or invalidate result buffers.
- Reusing stale IP output products or stale Vivado generated products after RTL changes.

## Verification Status

Verified by simulation:

- Core-level 4x4: PASS
- Core-level 8x8 padded: PASS
- Core-level 32x32: PASS
- Core-level 64x64: PASS
- `GEMM_top` AXI 4x4 smoke: PASS
- `GEMM_top` AXI 64x64: PASS
- `GEMM_top` AXI two-job 64x64 no-reset: PASS

Not claimed here:

- Hardware board validation.
- Synthesis, implementation, timing closure, or bitstream validation.
