module WeightStreamSlave #
(
    parameter integer P_WEIGHT_AXIS_DATA_WIDTH = 256
)
(
    output wire [P_WEIGHT_AXIS_DATA_WIDTH-1:0] o_weight_stream_data,
    output wire         o_weight_stream_valid,
    output wire         o_weight_stream_last,
    input  wire         i_weight_stream_ready,

    input wire  weight_axis_aclk,
    input wire  weight_axis_aresetn,
    output wire weight_axis_tready,
    input wire [P_WEIGHT_AXIS_DATA_WIDTH-1:0] weight_axis_tdata,
    input wire [(P_WEIGHT_AXIS_DATA_WIDTH/8)-1:0] weight_axis_tstrb,
    input wire         weight_axis_tlast,
    input wire         weight_axis_tvalid
);

WeightAxisFullBeatSlave #(
    .P_STREAM_DATA_WIDTH(P_WEIGHT_AXIS_DATA_WIDTH)
)
u_weight_axis_full_beat_slave
(
    .o_weight_stream_data(o_weight_stream_data),
    .o_weight_stream_valid(o_weight_stream_valid),
    .o_weight_stream_last(o_weight_stream_last),
    .i_weight_stream_ready(i_weight_stream_ready),

    .S_AXIS_ACLK(weight_axis_aclk),
    .S_AXIS_ARESETN(weight_axis_aresetn),
    .S_AXIS_TREADY(weight_axis_tready),
    .S_AXIS_TDATA(weight_axis_tdata),
    .S_AXIS_TSTRB(weight_axis_tstrb),
    .S_AXIS_TLAST(weight_axis_tlast),
    .S_AXIS_TVALID(weight_axis_tvalid)
);

endmodule
