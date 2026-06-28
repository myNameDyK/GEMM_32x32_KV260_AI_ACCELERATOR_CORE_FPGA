# GEMM Accelerator Module Signal Tables

Source of truth:

```text
RTL: E:/Everything_with_VIVADO/MM_final_DSP/MM_final.srcs/sources_1/imports/src
IP:  E:/Everything_with_VIVADO/MM_final_DSP/MM_final.srcs/sources_1/ip/mult_IP/mult_IP.xci
```

The tables below cover the 18 synthesizable RTL modules found in the active source folder. Testbenches, debug monitors, generated `.gen` simulation files, and obsolete temporary source folders are not included.

## GEMM_top

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `S_AXI_ACLK` [1 bit] | input | AXI-Lite/control clock. |
| `S_AXI_ARESETN` [1 bit] | input | Active-low AXI-Lite/control reset. |
| `S_AXI_AWADDR` [P_AXI_LITE_ADDR_WIDTH-1:0] | input | AXI-Lite write address. |
| `S_AXI_AWPROT` [2:0] | input | AXI-Lite write protection sideband. |
| `S_AXI_AWVALID` [1 bit] | input | AXI-Lite write address valid. |
| `S_AXI_AWREADY` [1 bit] | output | AXI-Lite write address ready. |
| `S_AXI_WDATA` [P_AXI_LITE_DATA_WIDTH-1:0] | input | AXI-Lite write data. |
| `S_AXI_WSTRB` [(P_AXI_LITE_DATA_WIDTH/8)-1:0] | input | AXI-Lite byte write strobes. |
| `S_AXI_WVALID` [1 bit] | input | AXI-Lite write data valid. |
| `S_AXI_WREADY` [1 bit] | output | AXI-Lite write data ready. |
| `S_AXI_BRESP` [1:0] | output | AXI-Lite write response. |
| `S_AXI_BVALID` [1 bit] | output | AXI-Lite write response valid. |
| `S_AXI_BREADY` [1 bit] | input | AXI-Lite write response ready. |
| `S_AXI_ARADDR` [P_AXI_LITE_ADDR_WIDTH-1:0] | input | AXI-Lite read address. |
| `S_AXI_ARPROT` [2:0] | input | AXI-Lite read protection sideband. |
| `S_AXI_ARVALID` [1 bit] | input | AXI-Lite read address valid. |
| `S_AXI_ARREADY` [1 bit] | output | AXI-Lite read address ready. |
| `S_AXI_RDATA` [P_AXI_LITE_DATA_WIDTH-1:0] | output | AXI-Lite read data. |
| `S_AXI_RRESP` [1:0] | output | AXI-Lite read response. |
| `S_AXI_RVALID` [1 bit] | output | AXI-Lite read data valid. |
| `S_AXI_RREADY` [1 bit] | input | AXI-Lite read data ready. |
| `feature_axis_tready` [1 bit] | output | Ready signal for feature AXI-Stream slave input. |
| `feature_axis_tdata` [P_ARRAY_SIZE*P_DATA_WIDTH-1:0] | input | Packed feature AXI-Stream data beat. |
| `feature_axis_tstrb` [(P_ARRAY_SIZE*P_DATA_WIDTH/8)-1:0] | input | Feature AXI-Stream byte strobes. |
| `feature_axis_tlast` [1 bit] | input | Feature AXI-Stream final-beat marker. |
| `feature_axis_tvalid` [1 bit] | input | Feature AXI-Stream valid. |
| `weight_axis_tready` [1 bit] | output | Ready signal for weight AXI-Stream slave input. |
| `weight_axis_tdata` [P_ARRAY_SIZE*P_DATA_WIDTH-1:0] | input | Packed weight AXI-Stream data beat. |
| `weight_axis_tstrb` [(P_ARRAY_SIZE*P_DATA_WIDTH/8)-1:0] | input | Weight AXI-Stream byte strobes. |
| `weight_axis_tlast` [1 bit] | input | Weight AXI-Stream final-beat marker. |
| `weight_axis_tvalid` [1 bit] | input | Weight AXI-Stream valid. |
| `result_axis_tvalid` [1 bit] | output | Result AXI-Stream master valid. |
| `result_axis_tdata` [P_ARRAY_SIZE*P_DATA_WIDTH-1:0] | output | Packed result AXI-Stream data beat. |
| `result_axis_tstrb` [(P_ARRAY_SIZE*P_DATA_WIDTH/8)-1:0] | output | Result AXI-Stream byte strobes, driven all ones by the adapter. |
| `result_axis_tlast` [1 bit] | output | Result AXI-Stream final-beat marker. |
| `result_axis_tready` [1 bit] | input | Result AXI-Stream master ready. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_AXI_LITE_DATA_WIDTH` | parameter | AXI-Lite data width, default 32. |
| `P_AXI_LITE_ADDR_WIDTH` | parameter | AXI-Lite address width, default 4. |
| `P_ARRAY_SIZE` | parameter | Number of lanes/array rows and columns, default 32. |
| `P_DATA_WIDTH` | parameter | Feature, weight, and result lane width, default 8. |
| `P_SHIFT_WIDTH` | parameter | Output shift register width, default 10. |
| `P_WEIGHT_BUFFER_DEPTH` | parameter | Weight input buffer depth, default 2400. |
| `P_FEATURE_BUFFER_DEPTH` | parameter | Feature input buffer depth, default 2400. |
| `P_OUTPUT_BUFFER_DEPTH` | parameter | Output accumulation buffer depth, default 2400. |
| `P_ACCUM_WIDTH` | parameter | Accumulation lane width, default 32. |
| `P_ROW_COUNT_WIDTH` | parameter | Row count width, default 9. |
| `P_K_BLOCK_COUNT_WIDTH` | parameter | K-block count width, default 5. |
| `P_N_BLOCK_COUNT_WIDTH` | parameter | N-block count width, default 5. |
| `cfg_shift` [P_SHIFT_WIDTH-1:0] | wire | Shift configuration from the AXI-Lite register file. |
| `cfg_row_count` [P_ROW_COUNT_WIDTH-1:0] | wire | Row-count configuration from the AXI-Lite register file. |
| `cfg_k_block_count` [P_K_BLOCK_COUNT_WIDTH-1:0] | wire | K-block-count configuration from the AXI-Lite register file. |
| `cfg_n_block_count` [P_N_BLOCK_COUNT_WIDTH-1:0] | wire | N-block-count configuration from the AXI-Lite register file. |
| `w_job_start_clear` [1 bit] | wire | Clear request pulse from register 0 bit 16. |
| `r_job_busy` [1 bit] | reg | Software-visible busy status. |
| `r_job_done` [1 bit] | reg | Software-visible done status. |
| `w_job_idle` [1 bit] | wire | Inverse of `r_job_busy`. |
| `r_job_clear_accepted` [1 bit] | reg | One-clock pulse for accepted clear while idle. |
| `r_job_clear_busy_error` [1 bit] | reg | One-clock pulse for attempted clear while busy. |
| `w_feature_stream_data` [P_ARRAY_SIZE*P_DATA_WIDTH-1:0] | wire | Internal packed feature stream data. |
| `w_feature_stream_valid` [1 bit] | wire | Internal feature stream valid. |
| `w_feature_stream_last` [1 bit] | wire | Internal feature stream last. |
| `w_feature_stream_ready` [1 bit] | wire | Internal feature stream ready. |
| `w_weight_stream_data` [P_ARRAY_SIZE*P_DATA_WIDTH-1:0] | wire | Internal packed weight stream data. |
| `w_weight_stream_valid` [1 bit] | wire | Internal weight stream valid. |
| `w_weight_stream_last` [1 bit] | wire | Internal weight stream last. |
| `w_weight_stream_ready` [1 bit] | wire | Internal weight stream ready. |
| `w_result_stream_data` [P_ARRAY_SIZE*P_DATA_WIDTH-1:0] | wire | Internal packed result stream data. |
| `w_result_stream_valid` [1 bit] | wire | Internal result stream valid. |
| `w_result_stream_last` [1 bit] | wire | Internal result stream last. |
| `w_result_stream_ready` [1 bit] | wire | Internal result stream ready. |
| `w_feature_stream_accept` [1 bit] | wire | Feature stream handshake detector. |
| `w_weight_stream_accept` [1 bit] | wire | Weight stream handshake detector. |
| `w_result_stream_accept` [1 bit] | wire | Result stream handshake detector. |
| `w_final_result_accept` [1 bit] | wire | Final result beat handshake detector. |

## ControlRegisterFile

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `o_cfg_shift` [9:0] | output | Stored output shift value from register 0 bits `[9:0]`. |
| `o_cfg_row_count` [8:0] | output | Stored row count from register 1 bits `[8:0]`. |
| `o_cfg_k_block_count` [4:0] | output | Stored K block count from register 2 bits `[4:0]`. |
| `o_cfg_n_block_count` [4:0] | output | Stored N block count from register 3 bits `[4:0]`. |
| `o_job_start_clear` [1 bit] | output | Pulse when register 0 is written with bit 16 set. |
| `i_job_busy` [1 bit] | input | Busy status from `GEMM_top`. |
| `i_job_done` [1 bit] | input | Done status from `GEMM_top`. |
| `i_job_idle` [1 bit] | input | Idle status from `GEMM_top`. |
| `i_job_clear_accepted` [1 bit] | input | Clear-accepted pulse from `GEMM_top`. |
| `i_job_clear_busy_error` [1 bit] | input | Clear-while-busy pulse from `GEMM_top`. |
| `S_AXI_ACLK` [1 bit] | input | AXI-Lite clock. |
| `S_AXI_ARESETN` [1 bit] | input | Active-low AXI-Lite reset. |
| `S_AXI_AWADDR` [P_AXI_LITE_ADDR_WIDTH-1:0] | input | AXI-Lite write address. |
| `S_AXI_AWPROT` [2:0] | input | AXI-Lite write protection. |
| `S_AXI_AWVALID` [1 bit] | input | AXI-Lite write address valid. |
| `S_AXI_AWREADY` [1 bit] | output | AXI-Lite write address ready. |
| `S_AXI_WDATA` [P_AXI_LITE_DATA_WIDTH-1:0] | input | AXI-Lite write data. |
| `S_AXI_WSTRB` [(P_AXI_LITE_DATA_WIDTH/8)-1:0] | input | AXI-Lite byte write strobes. |
| `S_AXI_WVALID` [1 bit] | input | AXI-Lite write data valid. |
| `S_AXI_WREADY` [1 bit] | output | AXI-Lite write data ready. |
| `S_AXI_BRESP` [1:0] | output | AXI-Lite write response. |
| `S_AXI_BVALID` [1 bit] | output | AXI-Lite write response valid. |
| `S_AXI_BREADY` [1 bit] | input | AXI-Lite write response ready. |
| `S_AXI_ARADDR` [P_AXI_LITE_ADDR_WIDTH-1:0] | input | AXI-Lite read address. |
| `S_AXI_ARPROT` [2:0] | input | AXI-Lite read protection. |
| `S_AXI_ARVALID` [1 bit] | input | AXI-Lite read address valid. |
| `S_AXI_ARREADY` [1 bit] | output | AXI-Lite read address ready. |
| `S_AXI_RDATA` [P_AXI_LITE_DATA_WIDTH-1:0] | output | AXI-Lite read data. |
| `S_AXI_RRESP` [1:0] | output | AXI-Lite read response. |
| `S_AXI_RVALID` [1 bit] | output | AXI-Lite read valid. |
| `S_AXI_RREADY` [1 bit] | input | AXI-Lite read ready. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_AXI_LITE_DATA_WIDTH` | parameter | AXI-Lite data width, default 32. |
| `P_AXI_LITE_ADDR_WIDTH` | parameter | AXI-Lite address width, default 4. |
| `LP_ADDR_LSB` | localparam | AXI-Lite byte-address-to-word-address shift. |
| `LP_OPT_MEM_ADDR_BITS` | localparam | Register decode address bit count. |
| `axi_awaddr` [P_AXI_LITE_ADDR_WIDTH-1:0] | reg | Latched AXI-Lite write address. |
| `axi_awready` [1 bit] | reg | Registered write address ready. |
| `axi_wready` [1 bit] | reg | Registered write data ready. |
| `axi_bresp` [1:0] | reg | Registered write response. |
| `axi_bvalid` [1 bit] | reg | Registered write response valid. |
| `axi_araddr` [P_AXI_LITE_ADDR_WIDTH-1:0] | reg | Latched AXI-Lite read address. |
| `axi_arready` [1 bit] | reg | Registered read address ready. |
| `axi_rdata` [P_AXI_LITE_DATA_WIDTH-1:0] | reg | Registered read data. |
| `axi_rresp` [1:0] | reg | Registered read response. |
| `axi_rvalid` [1 bit] | reg | Registered read valid. |
| `slv_reg0` [P_AXI_LITE_DATA_WIDTH-1:0] | reg | Shift register and write-only clear bit storage. |
| `slv_reg1` [P_AXI_LITE_DATA_WIDTH-1:0] | reg | Row count register storage. |
| `slv_reg2` [P_AXI_LITE_DATA_WIDTH-1:0] | reg | K block count register storage. |
| `slv_reg3` [P_AXI_LITE_DATA_WIDTH-1:0] | reg | N block count register storage. |
| `slv_reg_rden` [1 bit] | wire | Register read enable. |
| `slv_reg_wren` [1 bit] | wire | Register write enable. |
| `slv_reg0_wren` [1 bit] | wire | Register 0 write enable. |
| `reg_data_out` [P_AXI_LITE_DATA_WIDTH-1:0] | reg | Decoded readback mux output. |
| `aw_en` [1 bit] | reg | AXI-Lite write-address acceptance gate. |

## FeatureStreamSlave

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `o_feature_stream_data` [P_FEATURE_AXIS_DATA_WIDTH-1:0] | output | Internal feature stream data. |
| `o_feature_stream_valid` [1 bit] | output | Internal feature stream valid. |
| `o_feature_stream_last` [1 bit] | output | Internal feature stream last. |
| `i_feature_stream_ready` [1 bit] | input | Internal feature stream ready from the accelerator. |
| `feature_axis_aclk` [1 bit] | input | Feature AXI-Stream clock. |
| `feature_axis_aresetn` [1 bit] | input | Active-low feature AXI-Stream reset. |
| `feature_axis_tready` [1 bit] | output | External feature AXI-Stream ready. |
| `feature_axis_tdata` [P_FEATURE_AXIS_DATA_WIDTH-1:0] | input | External feature AXI-Stream data. |
| `feature_axis_tstrb` [(P_FEATURE_AXIS_DATA_WIDTH/8)-1:0] | input | External feature AXI-Stream byte strobes. |
| `feature_axis_tlast` [1 bit] | input | External feature AXI-Stream last. |
| `feature_axis_tvalid` [1 bit] | input | External feature AXI-Stream valid. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_FEATURE_AXIS_DATA_WIDTH` | parameter | Feature AXI-Stream data width, default 256. |

## FeatureAxisFullBeatSlave

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `o_feature_stream_data` [P_STREAM_DATA_WIDTH-1:0] | output | Internal feature stream data forwarded from `S_AXIS_TDATA`. |
| `o_feature_stream_valid` [1 bit] | output | Internal valid, gated by full `TSTRB`. |
| `o_feature_stream_last` [1 bit] | output | Internal last, gated by full `TSTRB`. |
| `i_feature_stream_ready` [1 bit] | input | Internal ready from downstream logic. |
| `S_AXIS_ACLK` [1 bit] | input | AXI-Stream slave clock. |
| `S_AXIS_ARESETN` [1 bit] | input | Active-low AXI-Stream slave reset. |
| `S_AXIS_TREADY` [1 bit] | output | External stream ready, gated by downstream ready and full `TSTRB`. |
| `S_AXIS_TDATA` [P_STREAM_DATA_WIDTH-1:0] | input | External stream data. |
| `S_AXIS_TSTRB` [(P_STREAM_DATA_WIDTH/8)-1:0] | input | External stream byte strobes. |
| `S_AXIS_TLAST` [1 bit] | input | External stream last. |
| `S_AXIS_TVALID` [1 bit] | input | External stream valid. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_STREAM_DATA_WIDTH` | parameter | AXI-Stream data width, default 256. |
| `w_full_beat` [1 bit] | wire | High only when all `S_AXIS_TSTRB` bits are asserted. |
| `r_partial_beat_error` [1 bit] | reg | Sticky internal flag set when `TVALID` is high with partial `TSTRB`. |

## WeightStreamSlave

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `o_weight_stream_data` [P_WEIGHT_AXIS_DATA_WIDTH-1:0] | output | Internal weight stream data. |
| `o_weight_stream_valid` [1 bit] | output | Internal weight stream valid. |
| `o_weight_stream_last` [1 bit] | output | Internal weight stream last. |
| `i_weight_stream_ready` [1 bit] | input | Internal weight stream ready from the accelerator. |
| `weight_axis_aclk` [1 bit] | input | Weight AXI-Stream clock. |
| `weight_axis_aresetn` [1 bit] | input | Active-low weight AXI-Stream reset. |
| `weight_axis_tready` [1 bit] | output | External weight AXI-Stream ready. |
| `weight_axis_tdata` [P_WEIGHT_AXIS_DATA_WIDTH-1:0] | input | External weight AXI-Stream data. |
| `weight_axis_tstrb` [(P_WEIGHT_AXIS_DATA_WIDTH/8)-1:0] | input | External weight AXI-Stream byte strobes. |
| `weight_axis_tlast` [1 bit] | input | External weight AXI-Stream last. |
| `weight_axis_tvalid` [1 bit] | input | External weight AXI-Stream valid. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_WEIGHT_AXIS_DATA_WIDTH` | parameter | Weight AXI-Stream data width, default 256. |

## WeightAxisFullBeatSlave

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `o_weight_stream_data` [P_STREAM_DATA_WIDTH-1:0] | output | Internal weight stream data forwarded from `S_AXIS_TDATA`. |
| `o_weight_stream_valid` [1 bit] | output | Internal valid, gated by full `TSTRB`. |
| `o_weight_stream_last` [1 bit] | output | Internal last, gated by full `TSTRB`. |
| `i_weight_stream_ready` [1 bit] | input | Internal ready from downstream logic. |
| `S_AXIS_ACLK` [1 bit] | input | AXI-Stream slave clock. |
| `S_AXIS_ARESETN` [1 bit] | input | Active-low AXI-Stream slave reset. |
| `S_AXIS_TREADY` [1 bit] | output | External stream ready, gated by downstream ready and full `TSTRB`. |
| `S_AXIS_TDATA` [P_STREAM_DATA_WIDTH-1:0] | input | External stream data. |
| `S_AXIS_TSTRB` [(P_STREAM_DATA_WIDTH/8)-1:0] | input | External stream byte strobes. |
| `S_AXIS_TLAST` [1 bit] | input | External stream last. |
| `S_AXIS_TVALID` [1 bit] | input | External stream valid. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_STREAM_DATA_WIDTH` | parameter | AXI-Stream data width, default 256. |
| `w_full_beat` [1 bit] | wire | High only when all `S_AXIS_TSTRB` bits are asserted. |
| `r_partial_beat_error` [1 bit] | reg | Sticky internal flag set when `TVALID` is high with partial `TSTRB`. |

## ResultStreamMaster

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `i_result_stream_data` [P_RESULT_AXIS_DATA_WIDTH-1:0] | input | Internal result stream data. |
| `i_result_stream_valid` [1 bit] | input | Internal result stream valid. |
| `i_result_stream_last` [1 bit] | input | Internal result stream final-beat marker. |
| `o_result_stream_ready` [1 bit] | output | Internal ready backpressure from the external master interface. |
| `result_axis_aclk` [1 bit] | input | Result AXI-Stream clock. |
| `result_axis_aresetn` [1 bit] | input | Active-low result AXI-Stream reset. |
| `result_axis_tvalid` [1 bit] | output | External result AXI-Stream valid. |
| `result_axis_tdata` [P_RESULT_AXIS_DATA_WIDTH-1:0] | output | External result AXI-Stream data. |
| `result_axis_tstrb` [(P_RESULT_AXIS_DATA_WIDTH/8)-1:0] | output | External result AXI-Stream byte strobes. |
| `result_axis_tlast` [1 bit] | output | External result AXI-Stream last. |
| `result_axis_tready` [1 bit] | input | External result AXI-Stream ready. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_RESULT_AXIS_DATA_WIDTH` | parameter | Result AXI-Stream data width, default 256. |

## ResultAxisMasterAdapter

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `i_result_stream_data` [P_STREAM_DATA_WIDTH-1:0] | input | Internal result stream data. |
| `i_result_stream_valid` [1 bit] | input | Internal result stream valid. |
| `i_result_stream_last` [1 bit] | input | Internal result stream last. |
| `o_result_stream_ready` [1 bit] | output | Internal ready from external `M_AXIS_TREADY`. |
| `M_AXIS_ACLK` [1 bit] | input | AXI-Stream master clock. |
| `M_AXIS_ARESETN` [1 bit] | input | Active-low AXI-Stream master reset. |
| `M_AXIS_TVALID` [1 bit] | output | External result stream valid. |
| `M_AXIS_TDATA` [P_STREAM_DATA_WIDTH-1:0] | output | External result stream data. |
| `M_AXIS_TSTRB` [(P_STREAM_DATA_WIDTH/8)-1:0] | output | External result stream byte strobes, tied all ones. |
| `M_AXIS_TLAST` [1 bit] | output | External result stream last. |
| `M_AXIS_TREADY` [1 bit] | input | External result stream ready. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_STREAM_DATA_WIDTH` | parameter | AXI-Stream data width, default 256. |

## GemmAccelerator

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `i_clk` [1 bit] | input | Datapath clock. |
| `i_rst_n` [1 bit] | input | Active-low datapath reset. |
| `i_cfg_shift` [P_SHIFT_WIDTH-1:0] | input | Live shift setting from AXI-Lite register file. |
| `i_cfg_row_count` [P_ROW_COUNT_WIDTH-1:0] | input | Live row-count setting from AXI-Lite register file. |
| `i_cfg_k_block_count` [P_K_BLOCK_COUNT_WIDTH-1:0] | input | Live K-block-count setting from AXI-Lite register file. |
| `i_cfg_n_block_count` [P_N_BLOCK_COUNT_WIDTH-1:0] | input | Live N-block-count setting from AXI-Lite register file. |
| `i_feature_valid` [1 bit] | input | Internal feature stream valid. |
| `i_feature_last` [1 bit] | input | Internal feature stream last. |
| `o_feature_ready` [1 bit] | output | Internal feature stream ready. |
| `i_feature_data` [P_ARRAY_SIZE * P_DATA_WIDTH - 1:0] | input | Packed feature stream data. |
| `i_weight_valid` [1 bit] | input | Internal weight stream valid. |
| `i_weight_last` [1 bit] | input | Internal weight stream last. |
| `o_weight_ready` [1 bit] | output | Internal weight stream ready. |
| `i_weight_data` [P_ARRAY_SIZE * P_DATA_WIDTH - 1:0] | input | Packed weight stream data. |
| `o_result_valid` [1 bit] | output | Internal result stream valid. |
| `i_result_ready` [1 bit] | input | Internal result stream ready. |
| `o_result_last` [1 bit] | output | Internal result stream last. |
| `o_result_data` [P_ARRAY_SIZE * P_DATA_WIDTH -1:0] | output | Packed result stream data. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_ARRAY_SIZE` | parameter | Array/lane count, default 32. |
| `P_DATA_WIDTH` | parameter | Feature, weight, and result lane width, default 8. |
| `P_SHIFT_WIDTH` | parameter | Shift configuration width, default 10. |
| `P_WEIGHT_BUFFER_DEPTH` | parameter | Weight buffer depth. |
| `P_FEATURE_BUFFER_DEPTH` | parameter | Feature buffer depth. |
| `P_OUTPUT_BUFFER_DEPTH` | parameter | Output buffer depth. |
| `P_ACCUM_WIDTH` | parameter | Accumulation lane width. |
| `P_ROW_COUNT_WIDTH` | parameter | Row count width. |
| `P_K_BLOCK_COUNT_WIDTH` | parameter | K-block count width. |
| `P_N_BLOCK_COUNT_WIDTH` | parameter | N-block count width. |
| `LP_LOG2_ARRAY_M` | localparam | Log2 array-size helper used for partial-sum row index width. |
| `r_cfg_shift` [P_SHIFT_WIDTH-1:0] | reg | Frozen shift value for the active job. |
| `r_cfg_row_count` [P_ROW_COUNT_WIDTH-1:0] | reg | Frozen row count for the active job. |
| `r_cfg_k_block_count` [P_K_BLOCK_COUNT_WIDTH-1:0] | reg | Frozen K block count for the active job. |
| `r_cfg_n_block_count` [P_N_BLOCK_COUNT_WIDTH-1:0] | reg | Frozen N block count for the active job. |
| `r_core_active` [1 bit] | reg | Tracks whether an active job or internal activity is in progress. |
| `w_compute_partial_data` [P_ARRAY_SIZE*(LP_LOG2_ARRAY_M+P_DATA_WIDTH*2)-1:0] | wire | Partial-sum vector from `BufferFeeder` to `OutputBuffer`. |
| `w_compute_partial_valid` [1 bit] | wire | Partial-sum valid from compute path. |
| `w_compute_partial_last` [1 bit] | wire | Partial-sum last marker from compute path. |
| `w_buffer_feature_valid` [1 bit] | wire | Feature data valid from `InputBuffer` to `BufferFeeder`. |
| `w_buffer_feature_last` [1 bit] | wire | Feature data last marker from `InputBuffer`. |
| `w_buffer_feature_ready` [1 bit] | wire | Feature ready from `BufferFeeder` to `InputBuffer`. |
| `w_buffer_feature_data` [P_ARRAY_SIZE * P_DATA_WIDTH - 1:0] | wire | Feature data from `InputBuffer` to `BufferFeeder`. |
| `w_buffer_weight_valid` [1 bit] | wire | Weight data valid from `InputBuffer` to `BufferFeeder`. |
| `w_buffer_weight_last` [1 bit] | wire | Weight data last marker from `InputBuffer`. |
| `w_buffer_weight_ready` [1 bit] | wire | Weight ready from `BufferFeeder` to `InputBuffer`. |
| `w_buffer_weight_data` [P_ARRAY_SIZE * P_DATA_WIDTH - 1:0] | wire | Weight data from `InputBuffer` to `BufferFeeder`. |
| `w_input_accept` [1 bit] | wire | Feature or weight input handshake detector. |
| `w_final_output_accept` [1 bit] | wire | Final result output handshake detector. |
| `w_core_active_for_config` [1 bit] | wire | Combined activity flag that prevents config refresh while busy. |

## InputBuffer

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `i_clk` [1 bit] | input | Buffer clock. |
| `i_rst_n` [1 bit] | input | Active-low buffer reset. |
| `i_cfg_n_block_count` [P_N_BLOCK_COUNT_WIDTH-1:0] | input | N-block count used for expected weight words and readout. |
| `i_cfg_k_block_count` [P_K_BLOCK_COUNT_WIDTH-1:0] | input | K-block count used for expected feature/weight words. |
| `i_cfg_row_count` [P_ROW_COUNT_WIDTH-1:0] | input | Row count used for expected feature words and readout. |
| `i_compute_partial_last` [1 bit] | input | Compute-path tile completion marker used to advance readout. |
| `i_feature_valid` [1 bit] | input | Incoming feature stream valid. |
| `i_feature_last` [1 bit] | input | Incoming feature stream last, resets feature write address. |
| `o_feature_ready` [1 bit] | output | Incoming feature stream ready. |
| `i_feature_data` [P_ARRAY_SIZE * P_DATA_WIDTH - 1:0] | input | Incoming packed feature word. |
| `i_weight_valid` [1 bit] | input | Incoming weight stream valid. |
| `i_weight_last` [1 bit] | input | Incoming weight stream last, resets weight write address. |
| `o_weight_ready` [1 bit] | output | Incoming weight stream ready. |
| `i_weight_data` [P_ARRAY_SIZE * P_DATA_WIDTH - 1:0] | input | Incoming packed weight word. |
| `o_buffer_feature_valid` [1 bit] | output | Buffered feature stream valid to `BufferFeeder`. |
| `o_buffer_feature_last` [1 bit] | output | Buffered feature last marker to `BufferFeeder`. |
| `i_buffer_feature_ready` [1 bit] | input | Ready from `BufferFeeder` for feature readout. |
| `o_buffer_feature_data` [P_ARRAY_SIZE * P_DATA_WIDTH - 1:0] | output | Buffered feature word to `BufferFeeder`. |
| `o_buffer_weight_valid` [1 bit] | output | Buffered weight stream valid to `BufferFeeder`. |
| `o_buffer_weight_last` [1 bit] | output | Buffered weight last marker to `BufferFeeder`. |
| `i_buffer_weight_ready` [1 bit] | input | Ready from `BufferFeeder` for weight readout. |
| `o_buffer_weight_data` [P_ARRAY_SIZE * P_DATA_WIDTH - 1:0] | output | Buffered weight word to `BufferFeeder`. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_ARRAY_SIZE` | parameter | Stream lane count, default 32. |
| `P_DATA_WIDTH` | parameter | Stream lane width, default 8. |
| `P_WEIGHT_BUFFER_DEPTH` | parameter | Weight memory depth. |
| `P_FEATURE_BUFFER_DEPTH` | parameter | Feature memory depth. |
| `P_ROW_COUNT_WIDTH` | parameter | Row counter width. |
| `P_K_BLOCK_COUNT_WIDTH` | parameter | K-block counter width. |
| `P_N_BLOCK_COUNT_WIDTH` | parameter | N-block counter width. |
| `LP_F_ADDR_WIDTH` | localparam | Feature buffer address width. |
| `LP_W_ADDR_WIDTH` | localparam | Weight buffer address width. |
| `LP_LOG_A_SIZE` | localparam | Log2 array-size helper. |
| `w_start_readout` [1 bit] | wire | Starts feature/weight replay once expected input is buffered or compute advances. |
| `w_accept_feature_word` [1 bit] | wire | Incoming feature handshake detector. |
| `w_accept_weight_word` [1 bit] | wire | Incoming weight handshake detector. |
| `w_accept_buffer_feature_word` [1 bit] | wire | Buffered feature readout handshake detector. |
| `w_accept_buffer_weight_word` [1 bit] | wire | Buffered weight readout handshake detector. |
| `w_feature_read_addr` [LP_F_ADDR_WIDTH-1:0] | wire | Feature memory read address formed from row and K block. |
| `r_feature_buffer_mem` [P_ARRAY_SIZE * P_DATA_WIDTH - 1:0] [P_FEATURE_BUFFER_DEPTH-1:0] | reg | Feature storage memory. |
| `r_weight_buffer_mem` [P_ARRAY_SIZE * P_DATA_WIDTH - 1:0] [P_WEIGHT_BUFFER_DEPTH-1:0] | reg | Weight storage memory. |
| `state` [1:0] | reg | Input buffer state machine. |
| `r_weight_words_expected` [LP_W_ADDR_WIDTH-1:0] | reg | Expected number of incoming weight words. |
| `r_feature_words_expected` [LP_F_ADDR_WIDTH-1:0] | reg | Expected number of incoming feature words. |
| `r_feature_write_count` [LP_F_ADDR_WIDTH-1:0] | reg | Count of accepted feature words. |
| `r_feature_write_addr` [LP_F_ADDR_WIDTH-1:0] | reg | Feature memory write address. |
| `r_weight_write_count` [LP_W_ADDR_WIDTH-1:0] | reg | Count of accepted weight words. |
| `r_weight_write_addr` [LP_W_ADDR_WIDTH-1:0] | reg | Weight memory write address. |
| `r_buffer_feature_count` [LP_F_ADDR_WIDTH-1:0] | reg | Count of feature words replayed to `BufferFeeder`. |
| `r_feature_read_row` [P_ROW_COUNT_WIDTH-1:0] | reg | Feature row index for replay. |
| `r_feature_read_k_block` [P_K_BLOCK_COUNT_WIDTH-1:0] | reg | Feature K-block index for replay. |
| `r_buffer_weight_count` [LP_W_ADDR_WIDTH-1:0] | reg | Count of weight words replayed to `BufferFeeder`. |
| `r_weight_read_addr` [LP_W_ADDR_WIDTH-1:0] | reg | Weight memory read address. |
| `r_k_elements_per_n_block` [LP_LOG_A_SIZE + P_K_BLOCK_COUNT_WIDTH-1:0] | reg | Computed padded K elements per N block. |

## BufferFeeder

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `i_clk` [1 bit] | input | Feeder clock. |
| `i_rst_n` [1 bit] | input | Active-low feeder reset. |
| `i_cfg_row_count` [P_ROW_COUNT_WIDTH-1:0] | input | Active job row count. |
| `i_cfg_n_block_count` [P_N_BLOCK_COUNT_WIDTH-1:0] | input | Active job N-block count. |
| `i_buffer_weight_data` [P_ARRAY_ROWS * P_DATA_WIDTH - 1:0] | input | Buffered weight word from `InputBuffer`. |
| `i_buffer_weight_valid` [1 bit] | input | Buffered weight valid. |
| `o_buffer_weight_ready` [1 bit] | output | Ready to accept buffered weight words. |
| `i_buffer_weight_last` [1 bit] | input | Buffered weight last marker. |
| `i_buffer_feature_data` [P_ARRAY_ROWS * P_DATA_WIDTH - 1:0] | input | Buffered feature word from `InputBuffer`. |
| `i_buffer_feature_valid` [1 bit] | input | Buffered feature valid. |
| `o_buffer_feature_ready` [1 bit] | output | Ready to accept buffered feature words. |
| `i_buffer_feature_last` [1 bit] | input | Buffered feature last marker. |
| `o_compute_partial_data` [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] | output | Partial-sum vector from compute core. |
| `o_compute_partial_valid` [1 bit] | output | Partial-sum valid. |
| `o_compute_partial_last` [1 bit] | output | Partial-sum last marker. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_ARRAY_ROWS` | parameter | Number of array rows, default 32. |
| `P_ARRAY_COLS` | parameter | Number of array columns, default 32. |
| `P_DATA_WIDTH` | parameter | Feature/weight lane width, default 8. |
| `P_ROW_INDEX_WIDTH` | parameter | Partial-sum row index width, default 5. |
| `P_ROW_COUNT_WIDTH` | parameter | Row count width. |
| `P_N_BLOCK_COUNT_WIDTH` | parameter | N-block count width. |
| `LP_FEATURE_BUFFER_DEPTH` | localparam | Local feature tile buffer depth. |
| `LP_WEIGHT_ADDR_WIDTH` | localparam | Local weight address width. |
| `LP_WEIGHT_BUFFER_DEPTH` | localparam | Local weight tile buffer depth. |
| `state` [1:0] | reg | Feeder state machine. |
| `start` [1 bit] | reg | Starts weight loading after local buffers fill. |
| `start_ahead1` [1 bit] | wire | One-cycle start detector when both local buffers are full. |
| `r_weight_loaded_d1` [1 bit] | reg | Delayed weight-loaded indicator. |
| `w_end` [1 bit] | reg | End-of-total-tile flag. |
| `weight_flag_up` [1 bit] | reg | Control flag for additional weight load phases. |
| `r_total_weight_words` [LP_WEIGHT_ADDR_WIDTH-1:0] | reg | Number of weight words per local tile. |
| `r_cfg_row_count_latched` [P_ROW_COUNT_WIDTH-1:0] | reg | Latched row count for local feature buffering. |
| `weight_buffer_cnt` [LP_WEIGHT_ADDR_WIDTH-1:0] | reg | Count of weight words loaded into local memory. |
| `weight_buffer_in_addr` [LP_WEIGHT_ADDR_WIDTH-1:0] | reg | Local weight memory write address. |
| `weight_buffer` [P_ARRAY_ROWS * P_DATA_WIDTH - 1:0] [LP_WEIGHT_BUFFER_DEPTH-1:0] | reg | Local weight tile memory. |
| `feature_buffer_cnt` [P_ROW_COUNT_WIDTH-1:0] | reg | Count of feature words loaded into local memory. |
| `feature_buffer_in_addr` [P_ROW_COUNT_WIDTH-1:0] | reg | Local feature memory write address. |
| `feature_buffer` [P_ARRAY_ROWS * P_DATA_WIDTH - 1:0] [LP_FEATURE_BUFFER_DEPTH-1:0] | reg | Local feature tile memory. |
| `both_full` [1 bit] | wire | High when local feature and weight buffers have expected words. |
| `both_full_delay1` [1 bit] | reg | Delayed `both_full` for edge detection. |
| `r_compute_input_data` [P_ARRAY_ROWS * P_DATA_WIDTH - 1:0] | reg | Data muxed into `GemmComputeCore`. |
| `r_compute_input_valid` [1 bit] | reg | Valid muxed into `GemmComputeCore`. |
| `r_compute_input_last` [1 bit] | reg | Last muxed into `GemmComputeCore`. |
| `input_weight_valid` [1 bit] | reg | Weight-load phase valid to compute core. |
| `input_weight_last` [1 bit] | wire | Last marker for a 32-word weight load phase. |
| `input_weight_data` [P_ARRAY_ROWS * P_DATA_WIDTH - 1:0] | reg | Local weight word read for compute core. |
| `input_weight_addr` [LP_WEIGHT_ADDR_WIDTH-1:0] | wire | Local weight read address. |
| `input_weight_col` [P_N_BLOCK_COUNT_WIDTH-1:0] | reg | Current N-block column index for weight loading. |
| `input_weight_row` [P_ROW_INDEX_WIDTH-1:0] | reg | Current row within a 32-word weight tile. |
| `weight_cnt` [LP_WEIGHT_ADDR_WIDTH-1:0] | reg | Weight-load phase counter. |
| `input_feature_valid` [1 bit] | reg | Feature-compute phase valid to compute core. |
| `input_feature_last` [1 bit] | wire | Last marker for the feature rows in a tile. |
| `input_feature_data` [P_ARRAY_ROWS * P_DATA_WIDTH - 1:0] | reg | Local feature word read for compute core. |
| `input_feature_addr` [P_ROW_COUNT_WIDTH-1:0] | reg | Local feature read address. |
| `feature_cnt` [P_ROW_COUNT_WIDTH-1:0] | reg | Feature-compute phase counter. |
| `w_weight_tile_loaded` [1 bit] | wire | Weight-loaded handshake from `GemmComputeCore`. |
| `total_last` [1 bit] | wire | Final marker for the complete feeder tile sequence. |
| `i_load_weight_phase` [1 bit] | wire | Control into `GemmComputeCore` indicating weight load phase. |
| `w_accept_input_weight` [1 bit] | wire | Buffered weight input handshake detector. |
| `w_accept_input_feature` [1 bit] | wire | Buffered feature input handshake detector. |
| `output_feature_data` [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] | wire | Partial-sum output from `GemmComputeCore`. |
| `output_feature_valid` [1 bit] | wire | Partial-sum valid from `GemmComputeCore`. |
| `output_feature_last` [1 bit] | wire | Partial-sum last from `GemmComputeCore`. |

## GemmComputeCore

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `i_clk` [1 bit] | input | Compute core clock. |
| `i_rst_n` [1 bit] | input | Active-low compute core reset. |
| `o_weight_tile_loaded` [1 bit] | output | Indicates that a full 32-word weight tile has loaded. |
| `i_load_weight_phase` [1 bit] | input | Selects weight-load behavior for incoming compute stream. |
| `i_compute_stream_data` [LP_AXIS_DATA_WIDTH-1:0] | input | Feature or weight word entering the compute core. |
| `i_compute_stream_valid` [1 bit] | input | Valid for compute stream word. |
| `i_compute_stream_last` [1 bit] | input | Last marker for weight-load or feature-compute phase. |
| `o_partial_data` [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] | output | Aligned partial-sum vector from the PE array. |
| `o_partial_valid` [1 bit] | output | Aligned partial-sum valid. |
| `o_partial_last` [1 bit] | output | Aligned partial-sum last. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_ARRAY_ROWS` | parameter | Number of PE array rows, default 32. |
| `P_ARRAY_COLS` | parameter | Number of PE array columns, default 32. |
| `P_DATA_WIDTH` | parameter | Feature/weight lane width, default 8. |
| `P_ROW_INDEX_WIDTH` | parameter | Partial-sum row index width, default 5. |
| `LP_AXIS_DATA_WIDTH` | localparam | Compute stream width, `P_ARRAY_ROWS * P_DATA_WIDTH`. |
| `LP_MULT_LATENCY` | localparam | Multiplier latency, 1. |
| `LP_PE_TOTAL_LATENCY` | localparam | PE latency helper, multiplier latency plus add stage. |
| `LP_RESULT_LATENCY` | localparam | Array result latency. |
| `LP_RESULT_VALID_LATENCY` | localparam | Valid/last pipe length. |
| `data_out_reg1` [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] | reg | Registered partial-sum output data. |
| `feature_in_reg1` [LP_AXIS_DATA_WIDTH-1:0] | reg | Registered feature vector into the array. |
| `weight_buffer` [LP_AXIS_DATA_WIDTH-1:0] [P_ARRAY_ROWS-1:0] | reg | Shifted storage for one 32-word weight tile. |
| `r_result_valid_pipe` [1 bit] [LP_RESULT_VALID_LATENCY:0] | reg | Valid alignment pipeline. |
| `r_result_last_pipe` [1 bit] [LP_RESULT_VALID_LATENCY:0] | reg | Last alignment pipeline. |
| `weight_buffer_cnt` [5:0] | reg | Counts weight words loaded into the tile buffer. |
| `r_loading_weights` [1 bit] | reg | Tracks whether incoming stream words are weights. |
| `w_weight_tile_loaded` [1 bit] | wire | High when `weight_buffer_cnt == P_ARRAY_ROWS`. |
| `o_data` [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] | wire | Raw PE array partial-sum vector. |
| `i_weight_matrix` [P_ARRAY_ROWS*P_ARRAY_COLS*P_DATA_WIDTH-1:0] | wire | Packed weight matrix bus into the PE array. |
| `o_partial_sum_vector` [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] | wire | PE array partial-sum output. |
| `feature_in` [LP_AXIS_DATA_WIDTH-1:0] | wire | Feature input word gated by compute phase. |
| `weight_in` [LP_AXIS_DATA_WIDTH-1:0] | wire | Weight input word gated by load phase. |
| `i_feature_vector` [P_DATA_WIDTH*P_ARRAY_ROWS-1:0] | wire | Feature vector into `ProcessingElementArray`. |

## ProcessingElementArray

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `i_clk` [1 bit] | input | PE array clock. |
| `i_rst_n` [1 bit] | input | Active-low PE array reset. |
| `i_weight_load` [1 bit] | input | Weight-load control for each PE. |
| `i_feature_vector` [P_DATA_WIDTH*P_ARRAY_ROWS-1:0] | input | Packed feature vector into the array rows. |
| `i_weight_matrix` [P_ARRAY_ROWS*P_ARRAY_COLS*P_DATA_WIDTH-1:0] | input | Packed weight matrix into the array. |
| `o_partial_sum_vector` [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] | output | Aligned partial-sum vector from the array. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_DATA_WIDTH` | parameter | Feature/weight lane width, default 8. |
| `P_ARRAY_ROWS` | parameter | Number of PE rows, default 32. |
| `P_ARRAY_COLS` | parameter | Number of PE columns, default 32. |
| `P_ROW_INDEX_WIDTH` | parameter | Partial-sum row index width, default 5. |
| `LP_MULT_LATENCY` | localparam | Multiplier latency, 1. |
| `LP_PE_TOTAL_LATENCY` | localparam | PE latency helper, multiplier latency plus add stage. |
| `w_weight_row_bus` [P_ARRAY_COLS*P_DATA_WIDTH-1:0] [P_ARRAY_ROWS-1:0] | wire | Per-row slice of the packed weight matrix. |
| `w_partial_sum_row_bus` [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] [P_ARRAY_ROWS:0] | wire | Partial-sum bus between PE rows. |
| `w_feature_lane` [P_DATA_WIDTH-1:0] [P_ARRAY_ROWS-1:0] | wire | Skewed feature value for each PE row. |
| `w_partial_sum_aligned` [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] | wire | Column-aligned partial-sum vector. |
| `r_output_delay` [(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] [P_ARRAY_COLS-2-i:0] | reg | Generated per-column output alignment delays. |
| `r_feature_delay` [P_DATA_WIDTH-1:0] [LP_PE_TOTAL_LATENCY*i-1:0] | reg | Generated per-row feature skew delays. |

## ProcessingElementRow

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `i_clk` [1 bit] | input | PE row clock. |
| `i_rst_n` [1 bit] | input | Active-low PE row reset. |
| `i_weight_load` [1 bit] | input | Weight-load control for PEs in the row. |
| `i_feature_value` [P_DATA_WIDTH-1:0] | input | Feature value entering the first PE lane. |
| `i_partial_sum_vector` [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] | input | Partial-sum vector entering the row. |
| `i_weight_matrix` [P_ARRAY_COLS*P_DATA_WIDTH-1:0] | input | Packed row of weight values for all columns. |
| `o_partial_sum_vector` [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] | output | Partial-sum vector leaving the row. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_ARRAY_ROWS` | parameter | Number of array rows, default 32. |
| `P_ARRAY_COLS` | parameter | Number of array columns, default 32. |
| `P_DATA_WIDTH` | parameter | Feature/weight lane width, default 8. |
| `P_ROW_INDEX_WIDTH` | parameter | Partial-sum row index width, default 5. |
| `w_partial_sum_in_lane` [2*P_DATA_WIDTH+P_ROW_INDEX_WIDTH-1:0] [P_ARRAY_COLS-1:0] | wire | Per-column partial-sum input lane. |
| `w_partial_sum_out_lane` [2*P_DATA_WIDTH+P_ROW_INDEX_WIDTH-1:0] [P_ARRAY_COLS-1:0] | wire | Per-column partial-sum output lane. |
| `w_array` [P_DATA_WIDTH-1:0] [P_ARRAY_COLS-1:0] | wire | Per-column weight value slice. |
| `w_feature_lane` [P_DATA_WIDTH-1:0] [P_ARRAY_COLS:0] | wire | Feature value as it propagates across the PE row. |

## ProcessingElement

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `i_clk` [1 bit] | input | PE clock. |
| `i_weight_load` [1 bit] | input | Loads `i_weight_value` into the PE weight register. |
| `i_rst_n` [1 bit] | input | Active-low PE reset. |
| `i_feature_value` [P_DATA_WIDTH-1:0] | input | Signed feature input lane. |
| `i_weight_value` [P_DATA_WIDTH-1:0] | input | Signed weight input lane. |
| `i_partial_sum` [2*P_DATA_WIDTH+P_ROW_INDEX_WIDTH-1:0] | input | Signed incoming partial sum. |
| `o_feature_value` [P_DATA_WIDTH-1:0] | output | Registered feature value forwarded to next PE. |
| `o_partial_sum` [2*P_DATA_WIDTH+P_ROW_INDEX_WIDTH-1:0] | output | Registered signed partial sum output. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_DATA_WIDTH` | parameter | Feature/weight lane width, default 8. |
| `P_ARRAY_ROWS` | parameter | Array row count parameter passed through for consistency. |
| `P_ARRAY_COLS` | parameter | Array column count parameter passed through for consistency. |
| `P_ROW_INDEX_WIDTH` | parameter | Partial-sum row index width, default 5. |
| `LP_PSUM_WIDTH` | localparam | Partial-sum width, `2*P_DATA_WIDTH + P_ROW_INDEX_WIDTH`. |
| `LP_MULT_LATENCY` | localparam | Multiplier latency, 1. |
| `LP_PE_TOTAL_LATENCY` | localparam | PE latency helper. |
| `r_weight_value` [P_DATA_WIDTH-1:0] | reg | Latched signed PE weight. |
| `r_partial_sum_d1` [LP_PSUM_WIDTH-1:0] | reg | One-cycle delayed incoming partial sum. |
| `w_product_raw` [15:0] | wire | Signed 8x8 multiplier output from `mult_IP`. |
| `w_product_ext` [LP_PSUM_WIDTH-1:0] | wire | Sign-extended multiplier product. |

## OutputBuffer

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `i_clk` [1 bit] | input | Output buffer clock. |
| `i_rst_n` [1 bit] | input | Active-low output buffer reset. |
| `i_cfg_shift` [P_SHIFT_WIDTH - 1:0] | input | Quantization shift amount. |
| `i_cfg_row_count` [P_ROW_COUNT_WIDTH-1:0] | input | Active job row count. |
| `i_cfg_k_block_count` [P_K_BLOCK_COUNT_WIDTH-1:0] | input | Active job K-block count. |
| `i_cfg_n_block_count` [P_N_BLOCK_COUNT_WIDTH-1:0] | input | Active job N-block count. |
| `i_partial_valid` [1 bit] | input | Partial-sum input valid. |
| `i_partial_last` [1 bit] | input | Partial-sum K/tile completion marker. |
| `i_partial_data` [P_ARRAY_SIZE*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] | input | Packed partial-sum vector from compute core. |
| `o_result_valid` [1 bit] | output | Result stream valid. |
| `o_result_last` [1 bit] | output | Result stream final-beat marker. |
| `i_result_ready` [1 bit] | input | Result stream ready. |
| `o_result_data` [P_ARRAY_SIZE * P_DATA_WIDTH -1:0] | output | Packed quantized result data. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_DATA_WIDTH` | parameter | Result lane width, default 8. |
| `P_OUTPUT_BUFFER_DEPTH` | parameter | Output memory depth. |
| `P_ACCUM_WIDTH` | parameter | Accumulation lane width, default 32. |
| `P_ARRAY_SIZE` | parameter | Number of output lanes, default 32. |
| `P_SHIFT_WIDTH` | parameter | Quantization shift width. |
| `P_ROW_INDEX_WIDTH` | parameter | Partial-sum row index width. |
| `P_ROW_COUNT_WIDTH` | parameter | Row count width. |
| `P_K_BLOCK_COUNT_WIDTH` | parameter | K-block count width. |
| `P_N_BLOCK_COUNT_WIDTH` | parameter | N-block count width. |
| `LP_OUT_ADDR_WIDTH` | localparam | Output buffer address width. |
| `r_output_buffer_mem` [P_ARRAY_SIZE*P_ACCUM_WIDTH-1:0] [P_OUTPUT_BUFFER_DEPTH-1:0] | reg | Block-RAM-style accumulated output memory. |
| `r_result_words_expected` [LP_OUT_ADDR_WIDTH-1:0] | reg | Expected number of result stream words. |
| `r_accum_read_addr` [LP_OUT_ADDR_WIDTH-1:0] | reg | Read address used while accumulating partial sums. |
| `r_accum_write_addr` [LP_OUT_ADDR_WIDTH-1:0] | reg | Write address used while accumulating partial sums. |
| `w_partial_sum` [P_ARRAY_SIZE*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] | wire | Partial-sum input vector alias. |
| `w_partial_sum_ext` [P_ARRAY_SIZE*P_ACCUM_WIDTH-1:0] | wire | Partial sums sign-extended to accumulation width. |
| `w_accum_prev` [P_ARRAY_SIZE*P_ACCUM_WIDTH-1:0] | wire | Previous accumulated vector read from memory. |
| `w_accum_next` [P_ARRAY_SIZE*P_ACCUM_WIDTH-1:0] | wire | Next accumulated vector from `SignedAdder`. |
| `r_k_block_done_count` [P_K_BLOCK_COUNT_WIDTH-1:0] | reg | Counts completed K blocks. |
| `r_start_result_stream` [1 bit] | reg | Starts result streaming after all K blocks complete. |
| `r_output_mem_valid` [1 bit] | reg | Output memory read valid stage. |
| `r_output_mem_valid_d1` [1 bit] | reg | First delayed output memory valid stage. |
| `r_output_mem_valid_d2` [1 bit] | reg | Second delayed output memory valid stage. |
| `w_output_mem_last_d2` [1 bit] | wire | Delayed final output memory read marker. |
| `r_output_mem_count` [LP_OUT_ADDR_WIDTH-1:0] | reg | Output memory read counter. |
| `r_output_mem_count_d1` [LP_OUT_ADDR_WIDTH-1:0] | reg | Delayed output memory read counter. |
| `w_output_mem_data` [P_ARRAY_SIZE*P_ACCUM_WIDTH-1:0] | wire | Output memory data before quantization. |
| `r_output_mem_data_d1` [P_ARRAY_SIZE*P_ACCUM_WIDTH-1:0] | reg | Registered output memory data for quantization. |
| `w_quantized_result_data` [P_ARRAY_SIZE * P_DATA_WIDTH -1:0] | wire | Packed shifted and saturated result data. |
| `r_result_word_count` [LP_OUT_ADDR_WIDTH-1:0] | reg | Count of result words accepted by downstream. |
| `r_output_mem_write_addr` [LP_OUT_ADDR_WIDTH-1:0] | reg | Selected output memory write address. |
| `r_output_mem_write_data` [P_ARRAY_SIZE*P_ACCUM_WIDTH-1:0] | reg | Selected output memory write data. |
| `r_result_col_block` [P_N_BLOCK_COUNT_WIDTH-1:0] | reg | Current output N-block index while streaming. |
| `r_result_row` [P_ROW_COUNT_WIDTH-1:0] | reg | Current output row while streaming. |
| `w_result_read_addr` [LP_OUT_ADDR_WIDTH-1:0] | wire | Output memory read address for result streaming. |
| `r_clear_addr` [LP_OUT_ADDR_WIDTH-1:0] | reg | Address used to clear output memory entries after readout. |
| `w_output_mem_read_addr` [LP_OUT_ADDR_WIDTH-1:0] | wire | Selected output memory read address. |
| `r_output_mem_read_data` [P_ARRAY_SIZE*P_ACCUM_WIDTH-1:0] | reg | Registered output memory read data. |

## SignedAdder

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `i_addend_a` [P_ARRAY_SIZE * P_DATA_WIDTH - 1:0] | input | Packed signed addend A lanes. |
| `i_addend_b` [P_ARRAY_SIZE * P_DATA_WIDTH - 1:0] | input | Packed signed addend B lanes. |
| `o_sum_sat` [P_ARRAY_SIZE * P_DATA_WIDTH - 1:0] | output | Packed signed saturated sum lanes. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_ARRAY_SIZE` | parameter | Number of packed lanes, default 32. |
| `P_DATA_WIDTH` | parameter | Width of each signed lane. |
| `w_lane_sum_ext` [(P_DATA_WIDTH + 1)-1:0] [P_ARRAY_SIZE-1:0] | wire | Per-lane signed sum with extra bit for overflow detection. |
| `w_sum_lane_display` [P_DATA_WIDTH - 1:0] [P_ARRAY_SIZE-1:0] | wire | Per-lane saturated sum before packing. |

## RightShifter

### Table 1: Input and Output Ports

| Name and bit width | Type | Function |
|---|---|---|
| `i_shift_amount` [P_SHIFT_WIDTH-1:0] | input | Arithmetic right-shift amount. |
| `i_data` [P_INPUT_WIDTH-1:0] | input | Signed input value to quantize. |
| `o_data` [P_OUTPUT_WIDTH-1:0] | output | Signed shifted, rounded, and saturated output value. |

### Table 2: Parameters, Wires, and Registers

| Name and bit width | Type | Function |
|---|---|---|
| `P_INPUT_WIDTH` | parameter | Signed input width, default 32. |
| `P_OUTPUT_WIDTH` | parameter | Signed output width, default 8. |
| `P_SHIFT_WIDTH` | parameter | Shift amount width, default 5. |
| `w_shifted_value` [P_INPUT_WIDTH-1:0] | wire | Arithmetic-shifted signed value. |
| `w_rounded_value` [P_INPUT_WIDTH-1:0] | wire | Shifted value after rounding increment. |
| `r_round_bit` [1 bit] | reg | Round bit selected from the discarded shift field. |
| `w_under_min` [1 bit] | wire | Negative overflow detector after shift. |
| `w_over_max` [1 bit] | wire | Positive overflow detector after shift. |
| `w_under_min_no_shift` [1 bit] | wire | Negative overflow detector when shift amount is zero. |
| `w_over_max_no_shift` [1 bit] | wire | Positive overflow detector when shift amount is zero. |

**Verification Status**

These tables were derived from the active synthesizable RTL modules in `E:/Everything_with_VIVADO/MM_final_DSP/MM_final.srcs/sources_1/imports/src`. Generated repetitive arrays are summarized using their RTL names and declared generate dimensions. No board validation, synthesis, implementation, or timing result is claimed by this document.
