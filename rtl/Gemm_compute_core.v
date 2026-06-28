`timescale 1ns / 1ps

module GemmComputeCore
#(
    parameter P_ARRAY_ROWS = 32, 
    parameter P_ARRAY_COLS = 32, 
    parameter P_DATA_WIDTH = 8, 
    parameter P_ROW_INDEX_WIDTH = 5,
    localparam integer LP_AXIS_DATA_WIDTH = P_ARRAY_ROWS * P_DATA_WIDTH 
)
(
    i_clk,
    i_rst_n,

    o_weight_tile_loaded,

    i_load_weight_phase, 

    i_compute_stream_data,
    i_compute_stream_valid,
    i_compute_stream_last,

    o_partial_data,
    o_partial_valid,
    o_partial_last
);

input wire                                                      i_clk;
input wire                                                      i_rst_n;

output wire                                                      o_weight_tile_loaded;

input wire                                                      i_load_weight_phase; 

input wire [LP_AXIS_DATA_WIDTH-1:0]                                i_compute_stream_data;
input wire                                                      i_compute_stream_valid;
input wire                                                      i_compute_stream_last;

output wire [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0]           o_partial_data;
output wire                                                     o_partial_valid;
output wire                                                     o_partial_last;



localparam integer LP_MULT_LATENCY = 1;
localparam integer LP_PE_TOTAL_LATENCY = LP_MULT_LATENCY + 1;
localparam integer LP_RESULT_LATENCY = LP_PE_TOTAL_LATENCY * P_ARRAY_ROWS + P_ARRAY_COLS;
localparam integer LP_RESULT_VALID_LATENCY = LP_RESULT_LATENCY;

reg [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0]    data_out_reg1;
reg [LP_AXIS_DATA_WIDTH-1:0] feature_in_reg1;
reg [LP_AXIS_DATA_WIDTH-1:0] weight_buffer [P_ARRAY_ROWS-1:0];
reg r_result_valid_pipe [LP_RESULT_VALID_LATENCY:0];
reg r_result_last_pipe [LP_RESULT_VALID_LATENCY:0];
reg [5:0] weight_buffer_cnt;
reg r_loading_weights;

wire w_weight_tile_loaded;
wire [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0]  o_data;
wire [P_ARRAY_ROWS*P_ARRAY_COLS*P_DATA_WIDTH-1:0] i_weight_matrix;
wire [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] o_partial_sum_vector;
wire [LP_AXIS_DATA_WIDTH-1:0] feature_in;
wire [LP_AXIS_DATA_WIDTH-1:0] weight_in;
wire [P_DATA_WIDTH*P_ARRAY_ROWS-1:0] i_feature_vector;


genvar i;
generate
    for(i=0;i<P_ARRAY_ROWS;i=i+1)begin:g_pack_weight_matrix
        assign i_weight_matrix[(P_DATA_WIDTH*P_ARRAY_COLS)*i +: (P_DATA_WIDTH*P_ARRAY_COLS)] = weight_buffer[P_ARRAY_ROWS-1-i];//????�??????????
    end
endgenerate

assign o_weight_tile_loaded = w_weight_tile_loaded;
assign o_partial_data = data_out_reg1;
assign weight_in = (r_loading_weights & i_compute_stream_valid) ? i_compute_stream_data : 0;
assign feature_in = ((~r_loading_weights) & i_compute_stream_valid)? i_compute_stream_data : 0;
assign w_weight_tile_loaded = (weight_buffer_cnt==P_ARRAY_ROWS) ? 1:0;
assign i_feature_vector = feature_in_reg1;
assign o_partial_valid = r_result_valid_pipe[LP_RESULT_VALID_LATENCY];
assign o_partial_last = r_result_last_pipe[LP_RESULT_VALID_LATENCY];



always @(posedge i_clk or negedge i_rst_n) begin
    if(~i_rst_n)
        weight_buffer_cnt <= 0;
    else if(weight_buffer_cnt == P_ARRAY_ROWS)
        weight_buffer_cnt<=0;
    else if (r_loading_weights & i_compute_stream_valid)
        weight_buffer_cnt<=weight_buffer_cnt+1;
    else 
        weight_buffer_cnt<=weight_buffer_cnt;
end

always @(posedge i_clk or negedge i_rst_n) begin
    if(~i_rst_n)
        r_loading_weights<=0;
    else 
        case ({i_load_weight_phase,i_compute_stream_last})
            2'b10 :  r_loading_weights <= 1;
            2'b01 :  r_loading_weights <= 0;
            default :  r_loading_weights <= r_loading_weights;
        endcase
end

always @(posedge i_clk)begin
    data_out_reg1 <= o_data;
end

always @(posedge i_clk or negedge i_rst_n) begin
    if(~i_rst_n)
        feature_in_reg1 <= 0;
    else
        feature_in_reg1 <= feature_in;
end

always @(posedge i_clk or negedge i_rst_n) begin
    if(~i_rst_n)
        weight_buffer[0]<=0;
    else if(r_loading_weights & i_compute_stream_valid)
        weight_buffer[0]<=weight_in;
    else
        weight_buffer[0]<=weight_buffer[0];
end

integer j;
always @(posedge i_clk or negedge i_rst_n) begin
    for(j=1;j<P_ARRAY_ROWS;j=j+1)begin
        if(~i_rst_n)
            weight_buffer[j]<=0;
        else if (r_loading_weights & i_compute_stream_valid)
            weight_buffer[j]<=weight_buffer[j-1];
        else
            weight_buffer[j]<=weight_buffer[j];
    end
end

always @(posedge i_clk or negedge i_rst_n) begin
    if(~i_rst_n)
        r_result_valid_pipe[0]<=0;
    else
        r_result_valid_pipe[0]<=i_compute_stream_valid & (~r_loading_weights);
end
generate
    for(i=1;i<=LP_RESULT_VALID_LATENCY;i=i+1)begin
        always @(posedge i_clk or negedge i_rst_n) begin
            if(~i_rst_n)
                r_result_valid_pipe[i]<=0;
            else
                r_result_valid_pipe[i]<=r_result_valid_pipe[i-1];
        end
    end
endgenerate

always @(posedge i_clk or negedge i_rst_n) begin
    if(~i_rst_n)
        r_result_last_pipe[0]<=0;
    else
        r_result_last_pipe[0]<=i_compute_stream_last & (~r_loading_weights);
end

generate
    for(i=1;i<=LP_RESULT_VALID_LATENCY;i=i+1) begin
        always @(posedge i_clk or negedge i_rst_n) begin
            if(~i_rst_n)
                r_result_last_pipe[i]<=0;
            else
                r_result_last_pipe[i]<=r_result_last_pipe[i-1];
        end
    end
endgenerate

ProcessingElementArray#
(
    .P_DATA_WIDTH(P_DATA_WIDTH),
    .P_ARRAY_ROWS(P_ARRAY_ROWS),
    .P_ARRAY_COLS(P_ARRAY_COLS),
    .P_ROW_INDEX_WIDTH(P_ROW_INDEX_WIDTH)
)
u_processing_element_array
(
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_weight_load(w_weight_tile_loaded),
    .i_feature_vector(i_feature_vector),
    .i_weight_matrix(i_weight_matrix),
    .o_partial_sum_vector(o_partial_sum_vector)
);

assign o_data = o_partial_sum_vector;
endmodule
