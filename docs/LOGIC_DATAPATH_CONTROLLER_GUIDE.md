# GEMM Accelerator Logic, Datapath, and Controller Guide

Source of truth:

```text
Project: E:/Everything_with_VIVADO/MM_final_DSP/MM_final.xpr
RTL:     E:/Everything_with_VIVADO/MM_final_DSP/MM_final.srcs/sources_1/imports/src
IP:      E:/Everything_with_VIVADO/MM_final_DSP/MM_final.srcs/sources_1/ip/mult_IP/mult_IP.xci
```

This guide documents the active RTL implementation used for the passed GEMM simulations. It does not document obsolete modules from earlier rename/refactor folders.

## Overall Architecture

`GEMM_top` wraps a small AXI-Lite register file, two AXI-Stream slave adapters, one AXI-Stream result master adapter, and the GEMM datapath. The datapath buffers incoming feature and weight stream data, tiles the work for a 32x32 systolic array, accumulates partial sums across K blocks, quantizes with a configurable shift, and streams packed INT8 result beats.

```text
AXI-Lite
  |
  v
+---------------------+
| ControlRegisterFile |
+---------------------+
  | shift,row,k,n,status
  v
+---------------------------------------------------------------+
|                           GEMM_top                            |
|                                                               |
| feature AXIS -> FeatureStreamSlave ->                         |
| weight  AXIS -> WeightStreamSlave  -> GemmAccelerator ->      |
|                                      ResultStreamMaster -> AXIS|
+---------------------------------------------------------------+

GemmAccelerator
  |
  +--> InputBuffer --> BufferFeeder --> GemmComputeCore
                                      |      |
                                      |      +--> ProcessingElementArray
                                      |             +--> ProcessingElementRow
                                      |                    +--> ProcessingElement + mult_IP
                                      v
                                  OutputBuffer
                                      |
                                      +--> SignedAdder
                                      +--> RightShifter
```

## Top-Level Control

### `GEMM_top`

`GEMM_top` is the packaged IP boundary. It exposes the AXI-Lite slave, feature AXI-Stream slave, weight AXI-Stream slave, and result AXI-Stream master. It connects configuration wires from `ControlRegisterFile` to `GemmAccelerator` and produces software-visible job status.

The top-level status controller is intentionally simple:

- `r_job_busy` sets when a feature word is accepted, a weight word is accepted, or the result stream becomes valid.
- `r_job_busy` clears when the final result beat handshakes.
- `r_job_done` sets on that same final result handshake.
- `r_job_done` clears when software writes clear while the job is idle.
- `r_job_clear_accepted` and `r_job_clear_busy_error` are one-clock pulses.

### `ControlRegisterFile`

`ControlRegisterFile` is the AXI-Lite slave and configuration register block. It implements four 32-bit registers at byte offsets `0x00`, `0x04`, `0x08`, and `0x0C`.

Register 0 stores `shift` in bits `[9:0]`, accepts a write-only clear request through bit 16, and readbacks status as:

```text
{3'b000, clear_busy_error, clear_accepted, idle, done, busy, 14'b0, shift[9:0]}
```

Registers 1, 2, and 3 provide `row_count`, `k_block_count`, and `n_block_count`.

## Stream Boundary Modules

### `FeatureStreamSlave`

`FeatureStreamSlave` wraps `FeatureAxisFullBeatSlave`. It maps the external `feature_axis_*` signals into internal feature stream signals used by `GemmAccelerator`.

### `FeatureAxisFullBeatSlave`

`FeatureAxisFullBeatSlave` is the actual feature AXI-Stream adapter. It requires all `TSTRB` bits to be high:

```verilog
w_full_beat = &S_AXIS_TSTRB;
```

It passes `TDATA`, `TVALID`, and `TLAST` only when the beat is full. Partial beats set internal `r_partial_beat_error` and do not receive `TREADY`.

### `WeightStreamSlave`

`WeightStreamSlave` wraps `WeightAxisFullBeatSlave`. It maps the external `weight_axis_*` signals into internal weight stream signals.

### `WeightAxisFullBeatSlave`

`WeightAxisFullBeatSlave` mirrors the feature adapter behavior for weight data. It requires full 256-bit beats with `TSTRB = 32'hFFFF_FFFF`.

### `ResultStreamMaster`

`ResultStreamMaster` wraps `ResultAxisMasterAdapter`. It maps internal result stream signals out to the external `result_axis_*` master interface.

### `ResultAxisMasterAdapter`

`ResultAxisMasterAdapter` directly forwards result data, valid, last, and ready. It always drives all output `TSTRB` bits high:

```verilog
M_AXIS_TSTRB = {(P_STREAM_DATA_WIDTH/8){1'b1}};
```

## Datapath Modules

### `GemmAccelerator`

`GemmAccelerator` is the main datapath wrapper. It instantiates:

- `InputBuffer`
- `BufferFeeder`
- `OutputBuffer`

It also implements config-freeze logic. The input configuration wires are copied into `r_cfg_shift`, `r_cfg_row_count`, `r_cfg_k_block_count`, and `r_cfg_n_block_count` only while the core is inactive. Activity includes accepted input, buffered feature/weight traffic, compute partial output, or result output. This prevents mid-job AXI-Lite writes from changing an active computation.

### `InputBuffer`

The module name is `InputBuffer` and the file is `In_buffer.v`.

`InputBuffer` accepts full-width internal feature and weight stream words. It stores feature words in `r_feature_buffer_mem` and weight words in `r_weight_buffer_mem`, counts accepted words, and starts readout once both expected counts have arrived. Expected counts are:

```text
feature words = row_count * k_block_count
weight words  = n_block_count * (k_block_count * 32)
```

For each K block it replays:

- One feature word for each row.
- `n_block_count * 32` weight words for the corresponding K tile.

`i_feature_last` and `i_weight_last` reset the write addresses, so external TLAST should be asserted only on the final feature or weight stream beat of a job.

### `BufferFeeder`

`BufferFeeder` receives the replayed feature and weight tile data from `InputBuffer`. It first fills local feature and weight buffers, then alternates phases:

1. Load a 32-row weight tile into `GemmComputeCore`.
2. Stream feature rows through the compute core.
3. Repeat for the next N block and K block until `total_last`.

Important control signals include `both_full`, `start_ahead1`, `i_load_weight_phase`, `w_weight_tile_loaded`, `input_weight_last`, `input_feature_last`, and `total_last`.

### `GemmComputeCore`

`GemmComputeCore` separates weight-loading cycles from feature-compute cycles. During weight load, input words shift into `weight_buffer`. After 32 weight words, `o_weight_tile_loaded` asserts. During feature compute, feature words pass into `ProcessingElementArray`.

The module aligns valid and last using result pipes:

```text
LP_MULT_LATENCY = 1
LP_PE_TOTAL_LATENCY = LP_MULT_LATENCY + 1
LP_RESULT_LATENCY = LP_PE_TOTAL_LATENCY * P_ARRAY_ROWS + P_ARRAY_COLS
LP_RESULT_VALID_LATENCY = LP_RESULT_LATENCY
```

The output partial sum vector is delayed until it aligns with the systolic-array result latency.

### `ProcessingElementArray`

`ProcessingElementArray` builds the 32x32 systolic array. It instantiates one `ProcessingElementRow` per array row, skews feature inputs by row, and aligns output columns with generated delay registers.

### `ProcessingElementRow`

`ProcessingElementRow` instantiates one `ProcessingElement` per array column. It passes the feature value across the row and connects the partial-sum lane from one PE to the next.

### `ProcessingElement`

`ProcessingElement` is the signed multiply-accumulate cell. It latches a signed INT8 weight when `i_weight_load` is high, multiplies signed INT8 feature and weight values through `mult_IP`, sign-extends the 16-bit multiplier result to the partial-sum width, delays the incoming partial sum by one cycle, and adds.

### Multiplier IP

The active XCI is:

```text
E:/Everything_with_VIVADO/MM_final_DSP/MM_final.srcs/sources_1/ip/mult_IP/mult_IP.xci
```

The XCI identifies a Xilinx `mult_gen` multiplier with:

- Component name: `mult_IP`
- Port A type: signed
- Port A width: 8
- Port B type: signed
- Port B width: 8
- Output bits: 15 downto 0, giving 16 output bits
- `PipeStages = 1`
- Generated `C_LATENCY = 1`

### `OutputBuffer`

The module name is `OutputBuffer` and the file is `Out_buffer.v`.

`OutputBuffer` collects partial sums, accumulates across K blocks, and streams final quantized output beats. It uses `r_output_buffer_mem` as a block RAM style accumulation/output buffer. For each partial result, it reads the previous accumulated value, adds the new partial sum through `SignedAdder`, and writes the saturated accumulated value back.

When `r_k_block_done_count == i_cfg_k_block_count`, `r_start_result_stream` starts output streaming. Result word count is:

```text
row_count * n_block_count
```

The output order is row-major by output row, with N block inside each row:

```text
for row = 0 .. row_count-1:
  for n_block = 0 .. n_block_count-1:
    output one 256-bit result beat
```

`o_result_last` is asserted on the final result beat.

### `SignedAdder`

`SignedAdder` performs lane-wise signed saturating addition. In `OutputBuffer`, it is instantiated with `P_DATA_WIDTH = P_ACCUM_WIDTH`, so it saturates 32-bit accumulated lanes after adding the previous accumulation and the new partial sum.

### `RightShifter`

`RightShifter` performs the final quantization. It arithmetic-shifts each signed accumulated lane by `i_cfg_shift`, applies rounding using `r_round_bit`, and saturates to the 8-bit result lane width. `OutputBuffer` instantiates one `RightShifter` per output lane.

## Dataflow Summary

### Feature Dataflow

Feature AXI-Stream beats enter `FeatureStreamSlave`, are filtered for full `TSTRB`, and pass to `GemmAccelerator`. `InputBuffer` stores them in feature memory. For each K block, it replays one feature word per row into `BufferFeeder`, which stores them in a tile buffer and then streams them through `GemmComputeCore`.

### Weight Dataflow

Weight AXI-Stream beats enter `WeightStreamSlave`, are filtered for full `TSTRB`, and pass to `GemmAccelerator`. `InputBuffer` stores them in weight memory. For each K block and N block, `BufferFeeder` loads 32 weight words into `GemmComputeCore`. `GemmComputeCore` shifts them into `weight_buffer`, repacks them as a matrix, and presents them to `ProcessingElementArray`.

### Partial Sum Flow

Feature rows propagate through the systolic array while locally stored weights are used by each PE. Each `ProcessingElement` computes a signed 8x8 multiply, extends the 16-bit result, adds it to the delayed incoming partial sum, and passes the result across the row. `GemmComputeCore` delays `valid` and `last` to match the array pipeline.

### Output Collection Flow

`OutputBuffer` receives partial vectors. It stores accumulated vectors in `r_output_buffer_mem`, increments `r_k_block_done_count` on partial `last`, and starts result streaming after all K blocks are complete.

### Shift/Saturation Flow

Partial sums are sign-extended to the accumulation width. `SignedAdder` saturates accumulated lanes. During result streaming, each accumulated 32-bit lane passes through a `RightShifter`, which rounds and saturates to signed 8-bit output.

### Result AXI-Stream Flow

`OutputBuffer` drives internal result stream data, valid, and last. `ResultStreamMaster` forwards the stream to AXI-Stream master pins and drives full `TSTRB`.

## AXI-Lite Control Flow

Software writes `shift`, `row_count`, `k_block_count`, and `n_block_count` through `ControlRegisterFile`. `GemmAccelerator` freezes those values for a job once data starts moving. `GEMM_top` reports status back through register 0.

There is no explicit start register. Stream acceptance starts the job. Final result acceptance completes it.

## TSTRB and TLAST Behavior

Feature and weight stream adapters require full `TSTRB`. A partial input beat is not accepted because `TREADY` is gated by `w_full_beat`.

Feature and weight `TLAST` pass through only on full beats. The input buffer uses input `TLAST` to reset write addresses, so the practical software rule is to assert input `TLAST` only on the final beat of each feature or weight transfer.

Result `TLAST` is generated by `OutputBuffer` on the final result beat:

```verilog
o_result_last = o_result_valid & (r_result_word_count == r_result_words_expected-1);
```

## Pipeline Alignment Summary

- `mult_IP` has one pipeline stage.
- Each PE has one multiplier stage plus one add/output stage.
- `ProcessingElementArray` skews feature inputs by row.
- `ProcessingElementArray` delays output columns to realign the systolic result vector.
- `GemmComputeCore` delays `valid` and `last` through `r_result_valid_pipe` and `r_result_last_pipe` for `LP_RESULT_VALID_LATENCY` cycles.
- `OutputBuffer` has additional BRAM read/output valid staging before result data is presented.

## 64x64 Tiling on a 32x32 Array

For a 64x64 multiply:

```text
row_count = 64
k_block_count = 2
n_block_count = 2
```

Feature input provides 64 rows times 2 K blocks, or 128 beats. Weight input provides 64 K rows times 2 N blocks, or 128 beats. The array computes one 32-column N block and one 32-wide K block at a time. `OutputBuffer` accumulates the two K-block contributions before streaming 64 rows times 2 N blocks, or 128 result beats.

## Back-to-Back Jobs

Normal back-to-back operation is supported by the status/clear flow and was simulation-tested with two 64x64 jobs without resetting the IP. Software should wait for `done`, wait for `idle`, clear `done`, configure the next job, and start the next DMA sequence.

The design does not implement a software abort. A clear request while busy produces `clear_busy_error` for one clock and does not stop the active job.

## Known Remaining Warnings

- `OutputBuffer` uses BRAM-style memory with `initial` zero initialization and has some pipeline registers that are not reset in a formal-proof-clean way. The normal two-job no-reset simulation passed, so stale-data risk is reduced for the verified flow, but reset-after-mid-job-abort is not formally proven.
- `clear_busy_error` and `clear_accepted` are pulse-like in `GEMM_top`. They may not be software-observable with ordinary polling.
- Stale Vivado simulation or block-design references are project-environment risks. They are not evidence of a current RTL datapath bug, but they should be cleaned before final handoff if the project is regenerated or packaged on another machine.

## Final Verified Simulation List

Verified by simulation:

- Core-level 4x4: PASS
- Core-level 8x8 padded: PASS
- Core-level 32x32: PASS
- Core-level 64x64: PASS
- `GEMM_top` AXI 4x4 smoke: PASS
- `GEMM_top` AXI 64x64: PASS
- `GEMM_top` AXI two-job 64x64 no-reset: PASS

Audit status:

- Testbench independence audit: PASS
- AXI-Lite protocol audit: PASS
- AXI-Stream protocol audit: PASS
- Packing/golden model audit: PASS
- Negative/stress audit: PASS
- RTL audit: WARNING only

## Verification Status

This document is based on the active RTL source files and the active `mult_IP.xci`. It describes simulation-verified behavior and expected software usage. It does not claim board validation, synthesis success, implementation success, timing closure, or bitstream validation.
