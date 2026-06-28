`timescale 1 ns / 1 ps

module ResultAxisMasterAdapter #
(
    parameter integer P_STREAM_DATA_WIDTH = 256
)
(
    // From GemmAccelerator
    input wire [P_STREAM_DATA_WIDTH-1:0] i_result_stream_data,
    input wire         i_result_stream_valid,
    input wire         i_result_stream_last,
    output wire        o_result_stream_ready,

    // AXI Stream Master
    input wire  M_AXIS_ACLK,
    input wire  M_AXIS_ARESETN,

    output wire                         M_AXIS_TVALID,
    output wire [P_STREAM_DATA_WIDTH-1:0] M_AXIS_TDATA,
    output wire [(P_STREAM_DATA_WIDTH/8)-1:0] M_AXIS_TSTRB,
    output wire                         M_AXIS_TLAST,
    input wire                          M_AXIS_TREADY
);

assign M_AXIS_TDATA  = i_result_stream_data;
assign M_AXIS_TVALID = i_result_stream_valid;
assign M_AXIS_TLAST  = i_result_stream_last;

assign o_result_stream_ready  = M_AXIS_TREADY;

assign M_AXIS_TSTRB = {(P_STREAM_DATA_WIDTH/8){1'b1}};

endmodule
