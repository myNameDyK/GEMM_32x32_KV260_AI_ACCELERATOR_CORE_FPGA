# RTL Module Signal Reference

This document lists the external ports of the synthesizable RTL modules in the GEMM accelerator source set. For each signal, it records the direction, parameterized width, default width, and purpose.

## Default Width Definitions

| Symbol | Default | Meaning |
|---|---:|---|
| `P_ARRAY_SIZE` | 32 | Number of INT8 lanes and systolic-array dimension |
| `P_ARRAY_ROWS` | 32 | Number of systolic-array rows |
| `P_ARRAY_COLS` | 32 | Number of systolic-array columns |
| `P_DATA_WIDTH` | 8 | Feature, weight, and final result width |
| `P_ACCUM_WIDTH` | 32 | Output-buffer accumulation width |
| `P_ROW_INDEX_WIDTH` | 5 | Additional partial-sum growth width |
| `P_SHIFT_WIDTH` | 10 at top level | Output right-shift configuration width |
| `P_ROW_COUNT_WIDTH` | 9 at top level | Configured output-row count width |
| `P_K_BLOCK_COUNT_WIDTH` | 5 | Configured K-block count width |
| `P_N_BLOCK_COUNT_WIDTH` | 5 | Configured N-block count width |

With the default array configuration:

```text
AXI-Stream data width = 32 × 8 = 256 bits
PE partial-sum width  = 2 × 8 + 5 = 21 bits
Partial vector width  = 32 × 21 = 672 bits
Weight-matrix width   = 32 × 32 × 8 = 8192 bits
```

---

# 1. `GEMM_top`

Top-level packaged accelerator interface.

## AXI4-Lite control interface

| Signal | Direction | Parameterized width | Default width | Description |
|---|---|---:|---:|---|
| `S_AXI_ACLK` | Input | 1 | 1 | AXI4-Lite and accelerator clock |
| `S_AXI_ARESETN` | Input | 1 | 1 | Active-low reset |
| `S_AXI_AWADDR` | Input | `P_AXI_LITE_ADDR_WIDTH` | 4 | Write address |
| `S_AXI_AWPROT` | Input | 3 | 3 | Write protection attributes |
| `S_AXI_AWVALID` | Input | 1 | 1 | Write address valid |
| `S_AXI_AWREADY` | Output | 1 | 1 | Write address ready |
| `S_AXI_WDATA` | Input | `P_AXI_LITE_DATA_WIDTH` | 32 | Write data |
| `S_AXI_WSTRB` | Input | `P_AXI_LITE_DATA_WIDTH/8` | 4 | Byte write strobes |
| `S_AXI_WVALID` | Input | 1 | 1 | Write data valid |
| `S_AXI_WREADY` | Output | 1 | 1 | Write data ready |
| `S_AXI_BRESP` | Output | 2 | 2 | Write response |
| `S_AXI_BVALID` | Output | 1 | 1 | Write response valid |
| `S_AXI_BREADY` | Input | 1 | 1 | Write response ready |
| `S_AXI_ARADDR` | Input | `P_AXI_LITE_ADDR_WIDTH` | 4 | Read address |
| `S_AXI_ARPROT` | Input | 3 | 3 | Read protection attributes |
| `S_AXI_ARVALID` | Input | 1 | 1 | Read address valid |
| `S_AXI_ARREADY` | Output | 1 | 1 | Read address ready |
| `S_AXI_RDATA` | Output | `P_AXI_LITE_DATA_WIDTH` | 32 | Read data |
| `S_AXI_RRESP` | Output | 2 | 2 | Read response |
| `S_AXI_RVALID` | Output | 1 | 1 | Read data valid |
| `S_AXI_RREADY` | Input | 1 | 1 | Read data ready |

## Feature AXI4-Stream slave

| Signal | Direction | Parameterized width | Default width | Description |
|---|---|---:|---:|---|
| `feature_axis_tdata` | Input | `P_ARRAY_SIZE × P_DATA_WIDTH` | 256 | Packed feature data |
| `feature_axis_tstrb` | Input | `P_ARRAY_SIZE × P_DATA_WIDTH / 8` | 32 | Valid-byte strobes |
| `feature_axis_tvalid` | Input | 1 | 1 | Feature beat valid |
| `feature_axis_tready` | Output | 1 | 1 | Feature beat ready |
| `feature_axis_tlast` | Input | 1 | 1 | Final feature beat |

## Weight AXI4-Stream slave

| Signal | Direction | Parameterized width | Default width | Description |
|---|---|---:|---:|---|
| `weight_axis_tdata` | Input | `P_ARRAY_SIZE × P_DATA_WIDTH` | 256 | Packed weight data |
| `weight_axis_tstrb` | Input | `P_ARRAY_SIZE × P_DATA_WIDTH / 8` | 32 | Valid-byte strobes |
| `weight_axis_tvalid` | Input | 1 | 1 | Weight beat valid |
| `weight_axis_tready` | Output | 1 | 1 | Weight beat ready |
| `weight_axis_tlast` | Input | 1 | 1 | Final weight beat |

## Result AXI4-Stream master

| Signal | Direction | Parameterized width | Default width | Description |
|---|---|---:|---:|---|
| `result_axis_tdata` | Output | `P_ARRAY_SIZE × P_DATA_WIDTH` | 256 | Packed INT8 result data |
| `result_axis_tstrb` | Output | `P_ARRAY_SIZE × P_DATA_WIDTH / 8` | 32 | Valid-byte strobes |
| `result_axis_tvalid` | Output | 1 | 1 | Result beat valid |
| `result_axis_tready` | Input | 1 | 1 | Result receiver ready |
| `result_axis_tlast` | Output | 1 | 1 | Final result beat |

---

# 2. `GemmAccelerator`

Connects configuration, input buffering, compute scheduling, and output buffering.

| Signal | Direction | Parameterized width | Default width | Description |
|---|---|---:|---:|---|
| `i_clk` | Input | 1 | 1 | Datapath clock |
| `i_rst_n` | Input | 1 | 1 | Active-low reset |
| `i_cfg_shift` | Input | `P_SHIFT_WIDTH` | 10 | Output requantization shift |
| `i_cfg_row_count` | Input | `P_ROW_COUNT_WIDTH` | 9 | Number of output rows |
| `i_cfg_k_block_count` | Input | `P_K_BLOCK_COUNT_WIDTH` | 5 | Number of 32-element K blocks |
| `i_cfg_n_block_count` | Input | `P_N_BLOCK_COUNT_WIDTH` | 5 | Number of 32-column N blocks |
| `i_feature_data` | Input | `P_ARRAY_SIZE × P_DATA_WIDTH` | 256 | Packed feature beat |
| `i_feature_valid` | Input | 1 | 1 | Feature beat valid |
| `o_feature_ready` | Output | 1 | 1 | Feature beat ready |
| `i_feature_last` | Input | 1 | 1 | Final feature beat |
| `i_weight_data` | Input | `P_ARRAY_SIZE × P_DATA_WIDTH` | 256 | Packed weight beat |
| `i_weight_valid` | Input | 1 | 1 | Weight beat valid |
| `o_weight_ready` | Output | 1 | 1 | Weight beat ready |
| `i_weight_last` | Input | 1 | 1 | Final weight beat |
| `o_result_data` | Output | `P_ARRAY_SIZE × P_DATA_WIDTH` | 256 | Packed result beat |
| `o_result_valid` | Output | 1 | 1 | Result beat valid |
| `i_result_ready` | Input | 1 | 1 | Result receiver ready |
| `o_result_last` | Output | 1 | 1 | Final result beat |

---

# 3. `InputBuffer`

Stores incoming feature and weight streams, then replays data by tile.

| Signal | Direction | Parameterized width | Default width | Description |
|---|---|---:|---:|---|
| `i_clk` | Input | 1 | 1 | Clock |
| `i_rst_n` | Input | 1 | 1 | Active-low reset |
| `i_cfg_n_block_count` | Input | `P_N_BLOCK_COUNT_WIDTH` | 5 | Number of N blocks |
| `i_cfg_k_block_count` | Input | `P_K_BLOCK_COUNT_WIDTH` | 5 | Number of K blocks |
| `i_cfg_row_count` | Input | `P_ROW_COUNT_WIDTH` | 10 standalone | Number of feature/output rows |
| `i_compute_partial_last` | Input | 1 | 1 | Compute-tile completion feedback |
| `i_feature_data` | Input | `P_ARRAY_SIZE × P_DATA_WIDTH` | 256 | Incoming feature beat |
| `i_feature_valid` | Input | 1 | 1 | Feature input valid |
| `o_feature_ready` | Output | 1 | 1 | Feature input ready |
| `i_feature_last` | Input | 1 | 1 | Final feature input beat |
| `i_weight_data` | Input | `P_ARRAY_SIZE × P_DATA_WIDTH` | 256 | Incoming weight beat |
| `i_weight_valid` | Input | 1 | 1 | Weight input valid |
| `o_weight_ready` | Output | 1 | 1 | Weight input ready |
| `i_weight_last` | Input | 1 | 1 | Final weight input beat |
| `o_buffer_feature_data` | Output | `P_ARRAY_SIZE × P_DATA_WIDTH` | 256 | Buffered feature data |
| `o_buffer_feature_valid` | Output | 1 | 1 | Buffered feature valid |
| `i_buffer_feature_ready` | Input | 1 | 1 | Downstream feature ready |
| `o_buffer_feature_last` | Output | 1 | 1 | Final feature beat of the current tile |
| `o_buffer_weight_data` | Output | `P_ARRAY_SIZE × P_DATA_WIDTH` | 256 | Buffered weight data |
| `o_buffer_weight_valid` | Output | 1 | 1 | Buffered weight valid |
| `i_buffer_weight_ready` | Input | 1 | 1 | Downstream weight ready |
| `o_buffer_weight_last` | Output | 1 | 1 | Final weight beat of the current tile |

> `GemmAccelerator` overrides the standalone `P_ROW_COUNT_WIDTH = 10` default with the top-level configured width when instantiated.

---

# 4. `BufferFeeder`

Schedules buffered feature and weight tiles for `GemmComputeCore`.

| Signal | Direction | Parameterized width | Default width | Description |
|---|---|---:|---:|---|
| `i_clk` | Input | 1 | 1 | Clock |
| `i_rst_n` | Input | 1 | 1 | Active-low reset |
| `i_cfg_row_count` | Input | `P_ROW_COUNT_WIDTH` | 10 standalone | Number of rows |
| `i_cfg_n_block_count` | Input | `P_N_BLOCK_COUNT_WIDTH` | 5 | Number of N blocks |
| `i_buffer_weight_data` | Input | `P_ARRAY_ROWS × P_DATA_WIDTH` | 256 | Buffered weight beat |
| `i_buffer_weight_valid` | Input | 1 | 1 | Buffered weight valid |
| `o_buffer_weight_ready` | Output | 1 | 1 | Weight buffer ready |
| `i_buffer_weight_last` | Input | 1 | 1 | Final weight beat of a tile |
| `i_buffer_feature_data` | Input | `P_ARRAY_ROWS × P_DATA_WIDTH` | 256 | Buffered feature beat |
| `i_buffer_feature_valid` | Input | 1 | 1 | Buffered feature valid |
| `o_buffer_feature_ready` | Output | 1 | 1 | Feature buffer ready |
| `i_buffer_feature_last` | Input | 1 | 1 | Final feature beat of a tile |
| `o_compute_partial_data` | Output | `P_ARRAY_COLS × (P_ROW_INDEX_WIDTH + 2×P_DATA_WIDTH)` | 672 | Packed partial-sum vector |
| `o_compute_partial_valid` | Output | 1 | 1 | Partial result valid |
| `o_compute_partial_last` | Output | 1 | 1 | Final partial result for the tile |

---

# 5. `GemmComputeCore`

Loads one weight tile and streams feature vectors through the PE array.

| Signal | Direction | Parameterized width | Default width | Description |
|---|---|---:|---:|---|
| `i_clk` | Input | 1 | 1 | Clock |
| `i_rst_n` | Input | 1 | 1 | Active-low reset |
| `i_load_weight_phase` | Input | 1 | 1 | Enables weight-loading phase |
| `i_compute_stream_data` | Input | `P_ARRAY_ROWS × P_DATA_WIDTH` | 256 | Weight or feature stream data |
| `i_compute_stream_valid` | Input | 1 | 1 | Compute input valid |
| `i_compute_stream_last` | Input | 1 | 1 | Final input of the current phase |
| `o_weight_tile_loaded` | Output | 1 | 1 | Indicates all 32 weight rows are loaded |
| `o_partial_data` | Output | `P_ARRAY_COLS × (P_ROW_INDEX_WIDTH + 2×P_DATA_WIDTH)` | 672 | Packed partial-sum vector |
| `o_partial_valid` | Output | 1 | 1 | Partial result valid after pipeline delay |
| `o_partial_last` | Output | 1 | 1 | Final partial result after pipeline delay |

---

# 6. `ProcessingElementArray`

Implements the 32×32 systolic array.

| Signal | Direction | Parameterized width | Default width | Description |
|---|---|---:|---:|---|
| `i_clk` | Input | 1 | 1 | Clock |
| `i_rst_n` | Input | 1 | 1 | Active-low reset |
| `i_weight_load` | Input | 1 | 1 | Enables PE weight loading |
| `i_feature_vector` | Input | `P_DATA_WIDTH × P_ARRAY_ROWS` | 256 | One feature value per array row |
| `i_weight_matrix` | Input | `P_ARRAY_ROWS × P_ARRAY_COLS × P_DATA_WIDTH` | 8192 | Complete 32×32 packed weight tile |
| `o_partial_sum_vector` | Output | `P_ARRAY_COLS × (P_ROW_INDEX_WIDTH + 2×P_DATA_WIDTH)` | 672 | One partial sum per output column |

---

# 7. `ProcessingElementRow`

Implements one row of processing elements.

| Signal | Direction | Parameterized width | Default width | Description |
|---|---|---:|---:|---|
| `i_clk` | Input | 1 | 1 | Clock |
| `i_rst_n` | Input | 1 | 1 | Active-low reset |
| `i_weight_load` | Input | 1 | 1 | Loads PE weights |
| `i_feature_value` | Input | `P_DATA_WIDTH` | 8 | Signed feature value entering the row |
| `i_partial_sum_vector` | Input | `P_ARRAY_COLS × (P_ROW_INDEX_WIDTH + 2×P_DATA_WIDTH)` | 672 | Partial sums entering the PE row |
| `i_weight_matrix` | Input | `P_ARRAY_COLS × P_DATA_WIDTH` | 256 | One packed row of weights |
| `o_partial_sum_vector` | Output | `P_ARRAY_COLS × (P_ROW_INDEX_WIDTH + 2×P_DATA_WIDTH)` | 672 | Updated partial sums |

---

# 8. `ProcessingElement`

Performs one signed INT8 multiply-accumulate operation.

| Signal | Direction | Parameterized width | Default width | Description |
|---|---|---:|---:|---|
| `i_clk` | Input | 1 | 1 | Clock |
| `i_rst_n` | Input | 1 | 1 | Active-low reset |
| `i_weight_load` | Input | 1 | 1 | Loads the local signed weight register |
| `i_feature_value` | Input | `P_DATA_WIDTH` | 8 | Signed feature operand |
| `i_weight_value` | Input | `P_DATA_WIDTH` | 8 | Signed weight operand |
| `i_partial_sum` | Input | `2×P_DATA_WIDTH + P_ROW_INDEX_WIDTH` | 21 | Incoming signed partial sum |
| `o_feature_value` | Output | `P_DATA_WIDTH` | 8 | Registered feature forwarded to the next PE |
| `o_partial_sum` | Output | `2×P_DATA_WIDTH + P_ROW_INDEX_WIDTH` | 21 | Updated signed partial sum |

---

# 9. `OutputBuffer`

Accumulates partial sums across K blocks and requantizes the final output.

| Signal | Direction | Parameterized width | Default width | Description |
|---|---|---:|---:|---|
| `i_clk` | Input | 1 | 1 | Clock |
| `i_rst_n` | Input | 1 | 1 | Active-low reset |
| `i_cfg_shift` | Input | `P_SHIFT_WIDTH` | 20 standalone | Arithmetic right-shift amount |
| `i_cfg_row_count` | Input | `P_ROW_COUNT_WIDTH` | 10 standalone | Number of result rows |
| `i_cfg_k_block_count` | Input | `P_K_BLOCK_COUNT_WIDTH` | 5 | Number of K blocks to accumulate |
| `i_cfg_n_block_count` | Input | `P_N_BLOCK_COUNT_WIDTH` | 5 | Number of N blocks |
| `i_partial_data` | Input | `P_ARRAY_SIZE × (P_ROW_INDEX_WIDTH + 2×P_DATA_WIDTH)` | 672 | Packed partial-sum vector |
| `i_partial_valid` | Input | 1 | 1 | Partial input valid |
| `i_partial_last` | Input | 1 | 1 | Final partial input for the tile |
| `o_result_data` | Output | `P_ARRAY_SIZE × P_DATA_WIDTH` | 256 | Packed INT8 result |
| `o_result_valid` | Output | 1 | 1 | Result output valid |
| `i_result_ready` | Input | 1 | 1 | Result receiver ready |
| `o_result_last` | Output | 1 | 1 | Final result beat |

> In the integrated design, `GemmAccelerator` overrides `P_SHIFT_WIDTH` and `P_ROW_COUNT_WIDTH` so they match the top-level configuration widths.

---

# 10. `SignedAdder`

Performs lane-wise signed saturating addition.

| Signal | Direction | Parameterized width | Default width | Description |
|---|---|---:|---:|---|
| `i_addend_a` | Input | `P_ARRAY_SIZE × P_DATA_WIDTH` | 256 | First packed signed operand |
| `i_addend_b` | Input | `P_ARRAY_SIZE × P_DATA_WIDTH` | 256 | Second packed signed operand |
| `o_sum_sat` | Output | `P_ARRAY_SIZE × P_DATA_WIDTH` | 256 | Packed saturated sum |

When instantiated by `OutputBuffer`, `P_DATA_WIDTH` is set to the accumulation width, so the effective ports are normally:

```text
32 lanes × 32 bits = 1024 bits
```

---

# 11. `RightShifter`

Applies arithmetic right shift, rounding, and signed saturation.

| Signal | Direction | Parameterized width | Default width | Description |
|---|---|---:|---:|---|
| `i_shift_amount` | Input | `P_SHIFT_WIDTH` | 5 standalone | Arithmetic right-shift amount |
| `i_data` | Input | `P_INPUT_WIDTH` | 32 | Signed accumulator input |
| `o_data` | Output | `P_OUTPUT_WIDTH` | 8 | Rounded and saturated signed output |

---

# Module Connection Summary

| Source module | Destination module | Main signals |
|---|---|---|
| `GEMM_top` | `GemmAccelerator` | Configuration, feature stream, weight stream, result stream |
| `GemmAccelerator` | `InputBuffer` | Feature/weight input and configuration |
| `InputBuffer` | `BufferFeeder` | Buffered feature/weight valid-ready channels |
| `BufferFeeder` | `GemmComputeCore` | Compute stream and load-weight control |
| `GemmComputeCore` | `ProcessingElementArray` | Feature vector, packed weight matrix, partial vector |
| `ProcessingElementArray` | `ProcessingElementRow` | Feature lane, weight row, partial-sum row |
| `ProcessingElementRow` | `ProcessingElement` | Feature, weight, and partial-sum operands |
| `GemmComputeCore` | `OutputBuffer` | Partial data, valid, and last |
| `OutputBuffer` | `SignedAdder` | Packed accumulation operands |
| `OutputBuffer` | `RightShifter` | Per-lane accumulator and shift amount |
| `OutputBuffer` | `GEMM_top` | Result data, valid, ready, and last |
