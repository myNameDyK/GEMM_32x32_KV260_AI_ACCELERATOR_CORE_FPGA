`timescale 1ns / 1ps

module ProcessingElementRow
#(
    parameter P_ARRAY_ROWS = 32, 
    parameter P_ARRAY_COLS = 32, 
    parameter P_DATA_WIDTH = 8,
    parameter P_ROW_INDEX_WIDTH = 5
)
(
    input                                               i_clk,
    input                                               i_rst_n,
    input                                               i_weight_load,
    input [P_DATA_WIDTH-1:0]                              i_feature_value,
    input [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0]     i_partial_sum_vector,
    input [P_ARRAY_COLS*P_DATA_WIDTH-1:0] i_weight_matrix,
    output [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0]    o_partial_sum_vector
);

wire [2*P_DATA_WIDTH+P_ROW_INDEX_WIDTH-1:0] w_partial_sum_in_lane [P_ARRAY_COLS-1:0];
wire [2*P_DATA_WIDTH+P_ROW_INDEX_WIDTH-1:0] w_partial_sum_out_lane [P_ARRAY_COLS-1:0];
wire [P_DATA_WIDTH-1:0] w_array [P_ARRAY_COLS-1:0];
wire [P_DATA_WIDTH-1:0] w_feature_lane [P_ARRAY_COLS:0]; 

assign w_feature_lane[0]=i_feature_value;

genvar i;
generate
    for(i=0;i<P_ARRAY_COLS;i=i+1)begin:g_unpack_row_inputs
        assign w_array[i] = i_weight_matrix[ P_DATA_WIDTH*i +: P_DATA_WIDTH];
        assign o_partial_sum_vector[(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)*i +: (P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)] = w_partial_sum_out_lane[i];
        assign w_partial_sum_in_lane[i] = i_partial_sum_vector[(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)*i +: (P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)];
    end
endgenerate

generate
    for(i=0;i<P_ARRAY_COLS;i=i+1)begin:g_pe_column
        ProcessingElement#(
            .P_DATA_WIDTH(P_DATA_WIDTH),
            .P_ARRAY_ROWS(P_ARRAY_ROWS),
            .P_ARRAY_COLS(P_ARRAY_COLS),   
            .P_ROW_INDEX_WIDTH(P_ROW_INDEX_WIDTH)
        )
        u_processing_element(
            .i_clk(i_clk),
            .i_weight_load(i_weight_load),   
            .i_rst_n(i_rst_n),   
            .i_feature_value(w_feature_lane[i]),
            .i_weight_value(w_array[i]),
            .i_partial_sum(w_partial_sum_in_lane[i]), 
            .o_feature_value(w_feature_lane[i+1]),
            .o_partial_sum(w_partial_sum_out_lane[i]) 
        );
    end
endgenerate
endmodule
