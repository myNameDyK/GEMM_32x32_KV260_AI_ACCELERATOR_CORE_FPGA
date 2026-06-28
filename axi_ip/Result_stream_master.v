`timescale 1 ns / 1 ps

module ResultStreamMaster #
(
    parameter integer P_RESULT_AXIS_DATA_WIDTH = 256
)
(
    // To/From GemmAccelerator
    input wire [P_RESULT_AXIS_DATA_WIDTH-1:0] i_result_stream_data,
    input wire         i_result_stream_valid,
    input wire         i_result_stream_last,
    output wire        o_result_stream_ready,

    // AXI Stream Master
    input wire result_axis_aclk,
    input wire result_axis_aresetn,

    output wire result_axis_tvalid,
    output wire [P_RESULT_AXIS_DATA_WIDTH-1:0] result_axis_tdata,
    output wire [(P_RESULT_AXIS_DATA_WIDTH/8)-1:0] result_axis_tstrb,
    output wire result_axis_tlast,
    input wire result_axis_tready
);

ResultAxisMasterAdapter #(
    .P_STREAM_DATA_WIDTH(P_RESULT_AXIS_DATA_WIDTH)
)
u_result_axis_master_adapter
(
    .i_result_stream_data(i_result_stream_data),
    .i_result_stream_valid(i_result_stream_valid),
    .i_result_stream_last(i_result_stream_last),
    .o_result_stream_ready(o_result_stream_ready),

    .M_AXIS_ACLK(result_axis_aclk),
    .M_AXIS_ARESETN(result_axis_aresetn),

    .M_AXIS_TVALID(result_axis_tvalid),
    .M_AXIS_TDATA(result_axis_tdata),
    .M_AXIS_TSTRB(result_axis_tstrb),
    .M_AXIS_TLAST(result_axis_tlast),
    .M_AXIS_TREADY(result_axis_tready)
);

endmodule
