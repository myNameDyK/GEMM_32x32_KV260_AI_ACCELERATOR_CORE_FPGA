`timescale 1 ns / 1 ps

module FeatureAxisFullBeatSlave #
(
    parameter integer P_STREAM_DATA_WIDTH = 256
)
(
    output wire [P_STREAM_DATA_WIDTH-1:0] o_feature_stream_data,
    output wire         o_feature_stream_valid,
    output wire         o_feature_stream_last,
    input  wire         i_feature_stream_ready,

    input wire  S_AXIS_ACLK,
    input wire  S_AXIS_ARESETN,
    output wire S_AXIS_TREADY,
    input wire [P_STREAM_DATA_WIDTH-1:0] S_AXIS_TDATA,
    input wire [(P_STREAM_DATA_WIDTH/8)-1:0] S_AXIS_TSTRB,
    input wire         S_AXIS_TLAST,
    input wire         S_AXIS_TVALID
);

wire w_full_beat;
reg r_partial_beat_error;

assign w_full_beat = &S_AXIS_TSTRB;

always @(posedge S_AXIS_ACLK or negedge S_AXIS_ARESETN) begin
    if(~S_AXIS_ARESETN)
        r_partial_beat_error <= 0;
    else if(S_AXIS_TVALID & ~w_full_beat)
        r_partial_beat_error <= 1;
    else
        r_partial_beat_error <= r_partial_beat_error;
end

assign o_feature_stream_data  = S_AXIS_TDATA;
assign o_feature_stream_valid = S_AXIS_TVALID & w_full_beat;
assign o_feature_stream_last  = S_AXIS_TLAST & w_full_beat;

assign S_AXIS_TREADY = i_feature_stream_ready & w_full_beat;

endmodule
