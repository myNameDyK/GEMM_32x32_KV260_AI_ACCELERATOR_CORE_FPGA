`timescale 1 ns / 1 ps

module FeatureStreamSlave #
(
    parameter integer P_FEATURE_AXIS_DATA_WIDTH = 256
)
(
    // Export sang GemmAccelerator
    output wire [P_FEATURE_AXIS_DATA_WIDTH-1:0] o_feature_stream_data,
    output wire         o_feature_stream_valid,
    output wire         o_feature_stream_last,
    input  wire         i_feature_stream_ready,

    // AXI Stream Slave
    input wire  feature_axis_aclk,
    input wire  feature_axis_aresetn,
    output wire feature_axis_tready,
    input wire [P_FEATURE_AXIS_DATA_WIDTH-1:0] feature_axis_tdata,
    input wire [(P_FEATURE_AXIS_DATA_WIDTH/8)-1:0] feature_axis_tstrb,
    input wire feature_axis_tlast,
    input wire feature_axis_tvalid
);

FeatureAxisFullBeatSlave #(
    .P_STREAM_DATA_WIDTH(P_FEATURE_AXIS_DATA_WIDTH)
)
u_feature_axis_full_beat_slave
(
    .o_feature_stream_data(o_feature_stream_data),
    .o_feature_stream_valid(o_feature_stream_valid),
    .o_feature_stream_last(o_feature_stream_last),
    .i_feature_stream_ready(i_feature_stream_ready),

    .S_AXIS_ACLK(feature_axis_aclk),
    .S_AXIS_ARESETN(feature_axis_aresetn),
    .S_AXIS_TREADY(feature_axis_tready),
    .S_AXIS_TDATA(feature_axis_tdata),
    .S_AXIS_TSTRB(feature_axis_tstrb),
    .S_AXIS_TLAST(feature_axis_tlast),
    .S_AXIS_TVALID(feature_axis_tvalid)
);

endmodule
