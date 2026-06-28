`timescale 1ns / 1ps

module ProcessingElement
#(
    parameter P_DATA_WIDTH = 8,           
    parameter P_ARRAY_ROWS = 32,             
    parameter P_ARRAY_COLS = 32,              
    parameter P_ROW_INDEX_WIDTH = 5
)
(
    input                                                   i_clk,
    input                                                   i_weight_load,      
    input                                                   i_rst_n,      
    input signed [P_DATA_WIDTH-1:0]                           i_feature_value,
    input signed [P_DATA_WIDTH-1:0]                           i_weight_value,
    input signed [2*P_DATA_WIDTH+P_ROW_INDEX_WIDTH-1:0]            i_partial_sum,   
    output reg signed [P_DATA_WIDTH-1:0]                      o_feature_value,
    output reg signed [2*P_DATA_WIDTH+P_ROW_INDEX_WIDTH-1:0]       o_partial_sum    
);
localparam integer LP_PSUM_WIDTH       = 2*P_DATA_WIDTH + P_ROW_INDEX_WIDTH;
localparam integer LP_MULT_LATENCY     = 1;
localparam integer LP_PE_TOTAL_LATENCY = LP_MULT_LATENCY + 1;

reg signed [P_DATA_WIDTH-1:0] r_weight_value;
reg signed [LP_PSUM_WIDTH-1:0] r_partial_sum_d1;
wire signed [15:0] w_product_raw;
wire signed [LP_PSUM_WIDTH-1:0] w_product_ext;

mult_IP u_mult_IP (
    .CLK(i_clk),
    .A(i_feature_value),
    .B(r_weight_value),
    .P(w_product_raw)
);

assign w_product_ext = {{(LP_PSUM_WIDTH-16){w_product_raw[15]}}, w_product_raw};

always @(posedge i_clk or negedge i_rst_n) begin
    if(~i_rst_n)begin
        o_partial_sum <= 0;
        r_weight_value <= 0;
        o_feature_value <= 0;
        r_partial_sum_d1 <= 0;
    end
    else begin
        if(i_weight_load) 
            r_weight_value <=i_weight_value;
        r_partial_sum_d1 <= i_partial_sum;
        o_partial_sum <= r_partial_sum_d1 + w_product_ext;
        o_feature_value <= i_feature_value;
    end
end
endmodule
