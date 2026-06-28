`timescale 1ns / 1ps

module GEMM_top
#(
    parameter integer P_AXI_LITE_DATA_WIDTH = 32,
    parameter integer P_AXI_LITE_ADDR_WIDTH = 4,
    parameter integer P_ARRAY_SIZE = 32,
    parameter integer P_DATA_WIDTH = 8,
    parameter integer P_SHIFT_WIDTH = 10,
    parameter integer P_WEIGHT_BUFFER_DEPTH = 2400,
    parameter integer P_FEATURE_BUFFER_DEPTH = 2400,
    parameter integer P_OUTPUT_BUFFER_DEPTH = 2400,
    parameter integer P_ACCUM_WIDTH = 32,
    parameter integer P_ROW_COUNT_WIDTH = 9,
    parameter integer P_K_BLOCK_COUNT_WIDTH = 5,
    parameter integer P_N_BLOCK_COUNT_WIDTH = 5
)
(
    //----------------------------------
    // AXI-Lite Control
    //----------------------------------
    input wire  S_AXI_ACLK,
    input wire  S_AXI_ARESETN,

    input wire [P_AXI_LITE_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input wire [2:0] S_AXI_AWPROT,
    input wire S_AXI_AWVALID,
    output wire S_AXI_AWREADY,

    input wire [P_AXI_LITE_DATA_WIDTH-1:0] S_AXI_WDATA,
    input wire [(P_AXI_LITE_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input wire S_AXI_WVALID,
    output wire S_AXI_WREADY,

    output wire [1:0] S_AXI_BRESP,
    output wire S_AXI_BVALID,
    input wire S_AXI_BREADY,

    input wire [P_AXI_LITE_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input wire [2:0] S_AXI_ARPROT,
    input wire S_AXI_ARVALID,
    output wire S_AXI_ARREADY,

    output wire [P_AXI_LITE_DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0] S_AXI_RRESP,
    output wire S_AXI_RVALID,
    input wire S_AXI_RREADY,

    //----------------------------------
    // Feature AXIS Slave
    //----------------------------------
    output wire         feature_axis_tready,
    input  wire [P_ARRAY_SIZE*P_DATA_WIDTH-1:0] feature_axis_tdata,
    input  wire [(P_ARRAY_SIZE*P_DATA_WIDTH/8)-1:0]  feature_axis_tstrb,
    input  wire         feature_axis_tlast,
    input  wire         feature_axis_tvalid,

    //----------------------------------
    // Weight AXIS Slave
    //----------------------------------
    output wire         weight_axis_tready,
    input  wire [P_ARRAY_SIZE*P_DATA_WIDTH-1:0] weight_axis_tdata,
    input  wire [(P_ARRAY_SIZE*P_DATA_WIDTH/8)-1:0]  weight_axis_tstrb,
    input  wire         weight_axis_tlast,
    input  wire         weight_axis_tvalid,

    //----------------------------------
    // Result AXIS Master
    //----------------------------------
    output wire         result_axis_tvalid,
    output wire [P_ARRAY_SIZE*P_DATA_WIDTH-1:0] result_axis_tdata,
    output wire [(P_ARRAY_SIZE*P_DATA_WIDTH/8)-1:0]  result_axis_tstrb,
    output wire         result_axis_tlast,
    input  wire         result_axis_tready
);


//=====================================================
// AXI-Lite Control Registers
//=====================================================

wire [P_SHIFT_WIDTH-1:0] cfg_shift;
wire [P_ROW_COUNT_WIDTH-1:0] cfg_row_count;
wire [P_K_BLOCK_COUNT_WIDTH-1:0] cfg_k_block_count;
wire [P_N_BLOCK_COUNT_WIDTH-1:0] cfg_n_block_count;
wire w_job_start_clear;
reg  r_job_busy;
reg  r_job_done;
wire w_job_idle;
reg  r_job_clear_accepted;
reg  r_job_clear_busy_error;

assign w_job_idle = ~r_job_busy;

ControlRegisterFile #(
    .P_AXI_LITE_DATA_WIDTH(P_AXI_LITE_DATA_WIDTH),
    .P_AXI_LITE_ADDR_WIDTH(P_AXI_LITE_ADDR_WIDTH)
)
u_control_registers
(
    .o_cfg_shift(cfg_shift),
    .o_cfg_row_count(cfg_row_count),
    .o_cfg_k_block_count(cfg_k_block_count),
    .o_cfg_n_block_count(cfg_n_block_count),
    .o_job_start_clear(w_job_start_clear),
    .i_job_busy(r_job_busy),
    .i_job_done(r_job_done),
    .i_job_idle(w_job_idle),
    .i_job_clear_accepted(r_job_clear_accepted),
    .i_job_clear_busy_error(r_job_clear_busy_error),

    .S_AXI_ACLK(S_AXI_ACLK),
    .S_AXI_ARESETN(S_AXI_ARESETN),

    .S_AXI_AWADDR(S_AXI_AWADDR),
    .S_AXI_AWPROT(S_AXI_AWPROT),
    .S_AXI_AWVALID(S_AXI_AWVALID),
    .S_AXI_AWREADY(S_AXI_AWREADY),

    .S_AXI_WDATA(S_AXI_WDATA),
    .S_AXI_WSTRB(S_AXI_WSTRB),
    .S_AXI_WVALID(S_AXI_WVALID),
    .S_AXI_WREADY(S_AXI_WREADY),

    .S_AXI_BRESP(S_AXI_BRESP),
    .S_AXI_BVALID(S_AXI_BVALID),
    .S_AXI_BREADY(S_AXI_BREADY),

    .S_AXI_ARADDR(S_AXI_ARADDR),
    .S_AXI_ARPROT(S_AXI_ARPROT),
    .S_AXI_ARVALID(S_AXI_ARVALID),
    .S_AXI_ARREADY(S_AXI_ARREADY),

    .S_AXI_RDATA(S_AXI_RDATA),
    .S_AXI_RRESP(S_AXI_RRESP),
    .S_AXI_RVALID(S_AXI_RVALID),
    .S_AXI_RREADY(S_AXI_RREADY)
);


//=====================================================
// AXIS Signals
//=====================================================

wire [P_ARRAY_SIZE*P_DATA_WIDTH-1:0] w_feature_stream_data;
wire         w_feature_stream_valid;
wire         w_feature_stream_last;
wire         w_feature_stream_ready;

wire [P_ARRAY_SIZE*P_DATA_WIDTH-1:0] w_weight_stream_data;
wire         w_weight_stream_valid;
wire         w_weight_stream_last;
wire         w_weight_stream_ready;

wire [P_ARRAY_SIZE*P_DATA_WIDTH-1:0] w_result_stream_data;
wire         w_result_stream_valid;
wire         w_result_stream_last;
wire         w_result_stream_ready;

wire w_feature_stream_accept;
wire w_weight_stream_accept;
wire w_result_stream_accept;
wire w_final_result_accept;

assign w_feature_stream_accept = w_feature_stream_valid & w_feature_stream_ready;
assign w_weight_stream_accept = w_weight_stream_valid & w_weight_stream_ready;
assign w_result_stream_accept = w_result_stream_valid & w_result_stream_ready;
assign w_final_result_accept = w_result_stream_accept & w_result_stream_last;

always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
    if(~S_AXI_ARESETN) begin
        r_job_busy <= 0;
        r_job_done <= 0;
        r_job_clear_accepted <= 0;
        r_job_clear_busy_error <= 0;
    end
    else begin
        r_job_clear_accepted <= 0;
        r_job_clear_busy_error <= 0;

        if(w_job_start_clear) begin
            if(r_job_busy)
                r_job_clear_busy_error <= 1;
            else begin
                r_job_done <= 0;
                r_job_clear_accepted <= 1;
            end
        end

        if(w_final_result_accept) begin
            r_job_busy <= 0;
            r_job_done <= 1;
        end
        else if(w_feature_stream_accept | w_weight_stream_accept | w_result_stream_valid) begin
            r_job_busy <= 1;
            r_job_done <= 0;
        end
    end
end


//=====================================================
// Feature AXIS
//=====================================================

FeatureStreamSlave #(
    .P_FEATURE_AXIS_DATA_WIDTH(P_ARRAY_SIZE*P_DATA_WIDTH)
)
u_feature_stream_slave
(
    .o_feature_stream_data(w_feature_stream_data),
    .o_feature_stream_valid(w_feature_stream_valid),
    .o_feature_stream_last(w_feature_stream_last),
    .i_feature_stream_ready(w_feature_stream_ready),

    .feature_axis_aclk(S_AXI_ACLK),
    .feature_axis_aresetn(S_AXI_ARESETN),
    .feature_axis_tready(feature_axis_tready),
    .feature_axis_tdata(feature_axis_tdata),
    .feature_axis_tstrb(feature_axis_tstrb),
    .feature_axis_tlast(feature_axis_tlast),
    .feature_axis_tvalid(feature_axis_tvalid)
);


//=====================================================
// Weight AXIS
//=====================================================

WeightStreamSlave #(
    .P_WEIGHT_AXIS_DATA_WIDTH(P_ARRAY_SIZE*P_DATA_WIDTH)
)
u_weight_stream_slave
(
    .o_weight_stream_data(w_weight_stream_data),
    .o_weight_stream_valid(w_weight_stream_valid),
    .o_weight_stream_last(w_weight_stream_last),
    .i_weight_stream_ready(w_weight_stream_ready),

    .weight_axis_aclk(S_AXI_ACLK),
    .weight_axis_aresetn(S_AXI_ARESETN),
    .weight_axis_tready(weight_axis_tready),
    .weight_axis_tdata(weight_axis_tdata),
    .weight_axis_tstrb(weight_axis_tstrb),
    .weight_axis_tlast(weight_axis_tlast),
    .weight_axis_tvalid(weight_axis_tvalid)
);


//=====================================================
// GEMM Core
//=====================================================

GemmAccelerator #(
    .P_ARRAY_SIZE(P_ARRAY_SIZE),
    .P_DATA_WIDTH(P_DATA_WIDTH),
    .P_SHIFT_WIDTH(P_SHIFT_WIDTH),
    .P_WEIGHT_BUFFER_DEPTH(P_WEIGHT_BUFFER_DEPTH),
    .P_FEATURE_BUFFER_DEPTH(P_FEATURE_BUFFER_DEPTH),
    .P_OUTPUT_BUFFER_DEPTH(P_OUTPUT_BUFFER_DEPTH),
    .P_ACCUM_WIDTH(P_ACCUM_WIDTH),
    .P_ROW_COUNT_WIDTH(P_ROW_COUNT_WIDTH),
    .P_K_BLOCK_COUNT_WIDTH(P_K_BLOCK_COUNT_WIDTH),
    .P_N_BLOCK_COUNT_WIDTH(P_N_BLOCK_COUNT_WIDTH)
)
u_gemm_accelerator
(
    .i_clk(S_AXI_ACLK),
    .i_rst_n(S_AXI_ARESETN),

    .i_cfg_shift(cfg_shift),
    .i_cfg_row_count(cfg_row_count),
    .i_cfg_k_block_count(cfg_k_block_count),
    .i_cfg_n_block_count(cfg_n_block_count),

    .i_feature_valid(w_feature_stream_valid),
    .i_feature_last(w_feature_stream_last),
    .o_feature_ready(w_feature_stream_ready),
    .i_feature_data(w_feature_stream_data),

    .i_weight_valid(w_weight_stream_valid),
    .i_weight_last(w_weight_stream_last),
    .o_weight_ready(w_weight_stream_ready),
    .i_weight_data(w_weight_stream_data),

    .o_result_valid(w_result_stream_valid),
    .i_result_ready(w_result_stream_ready),
    .o_result_last(w_result_stream_last),
    .o_result_data(w_result_stream_data)
);


//=====================================================
// Result AXIS
//=====================================================

ResultStreamMaster #(
    .P_RESULT_AXIS_DATA_WIDTH(P_ARRAY_SIZE*P_DATA_WIDTH)
)
u_result_stream_master
(
    .i_result_stream_data(w_result_stream_data),
    .i_result_stream_valid(w_result_stream_valid),
    .i_result_stream_last(w_result_stream_last),
    .o_result_stream_ready(w_result_stream_ready),

    .result_axis_aclk(S_AXI_ACLK),
    .result_axis_aresetn(S_AXI_ARESETN),

    .result_axis_tvalid(result_axis_tvalid),
    .result_axis_tdata(result_axis_tdata),
    .result_axis_tstrb(result_axis_tstrb),
    .result_axis_tlast(result_axis_tlast),
    .result_axis_tready(result_axis_tready)
);

endmodule
