`timescale 1ns / 1ps

module ProcessingElementArray
(
    i_clk,
    i_rst_n,
    i_weight_load,
    i_feature_vector,
    i_weight_matrix,
    o_partial_sum_vector
);
parameter integer P_DATA_WIDTH = 8;
parameter integer P_ARRAY_ROWS = 32;
parameter integer P_ARRAY_COLS = 32;
parameter integer P_ROW_INDEX_WIDTH = 5;
localparam integer LP_MULT_LATENCY = 1;
localparam integer LP_PE_TOTAL_LATENCY = LP_MULT_LATENCY + 1;


input wire i_clk;
input wire i_rst_n;
input wire i_weight_load;
input [P_DATA_WIDTH*P_ARRAY_ROWS-1:0]                     i_feature_vector;
input [P_ARRAY_ROWS*P_ARRAY_COLS*P_DATA_WIDTH-1:0]             i_weight_matrix; 
output [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0]   o_partial_sum_vector;

wire [P_ARRAY_COLS*P_DATA_WIDTH-1:0] w_weight_row_bus [P_ARRAY_ROWS-1:0];
wire [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] w_partial_sum_row_bus [P_ARRAY_ROWS:0];

wire [P_DATA_WIDTH-1:0] w_feature_lane [P_ARRAY_ROWS-1:0];

//assign o_partial_sum_vector = w_partial_sum_row_bus[P_ARRAY_ROWS];
wire [P_ARRAY_COLS*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] w_partial_sum_aligned;
assign w_partial_sum_aligned = w_partial_sum_row_bus[P_ARRAY_ROWS];
genvar i;
generate
    for(i=P_ARRAY_COLS-1;i>=0;i=i-1) begin:g_align_output_column
        if(i==P_ARRAY_COLS-1)begin
            assign o_partial_sum_vector[(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)*i +: (P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)] =  w_partial_sum_aligned[(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)*i +: (P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)];
        end
        else begin
            reg [(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)-1:0] r_output_delay [P_ARRAY_COLS-2-i:0];
            always @(posedge i_clk or negedge i_rst_n) begin
                if(~i_rst_n)
                    r_output_delay[0]<=0;
                else
                    r_output_delay[0]<=w_partial_sum_aligned[i*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2) +: (P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)];
            end
            
            genvar k;
            for (k=1;k<=P_ARRAY_COLS-2-i;k=k+1)begin:g_output_delay
                always@(posedge i_clk or negedge i_rst_n)begin
                    if(~i_rst_n)
                        r_output_delay[k]<=0;
                    else
                        r_output_delay[k]<=r_output_delay[k-1];
                end
            end
            assign o_partial_sum_vector[i*(P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2) +: (P_ROW_INDEX_WIDTH+P_DATA_WIDTH*2)] = r_output_delay [P_ARRAY_COLS-2-i];
        end
    end
endgenerate
assign w_partial_sum_row_bus[0] = 0;


generate
    for (i=0;i<P_ARRAY_ROWS;i=i+1)begin:g_unpack_array_inputs
        assign w_feature_lane[i] = i_feature_vector[P_DATA_WIDTH*i +: P_DATA_WIDTH];
        assign w_weight_row_bus[i] = i_weight_matrix[(P_ARRAY_COLS*P_DATA_WIDTH)*i +: (P_ARRAY_COLS*P_DATA_WIDTH)];
    end
endgenerate

generate
    for (i=0; i<P_ARRAY_ROWS; i=i+1) begin:g_pe_row
        if (i==0) begin
            ProcessingElementRow #(
                .P_DATA_WIDTH (P_DATA_WIDTH),
                .P_ARRAY_ROWS(P_ARRAY_ROWS),
                .P_ARRAY_COLS(P_ARRAY_COLS),
                .P_ROW_INDEX_WIDTH(P_ROW_INDEX_WIDTH)
            )
            u_processing_element_row
            (
                .i_clk(i_clk),
                .i_rst_n(i_rst_n),
                .i_weight_load(i_weight_load),
                .i_feature_value(w_feature_lane[i]),
                .i_partial_sum_vector(w_partial_sum_row_bus[i]),
                .i_weight_matrix(w_weight_row_bus[i]),
                .o_partial_sum_vector(w_partial_sum_row_bus[i+1])
            );            
        end
        else begin
            reg [P_DATA_WIDTH-1:0] r_feature_delay [LP_PE_TOTAL_LATENCY*i-1:0];
            always @(posedge i_clk or negedge i_rst_n) begin
                if(~i_rst_n)
                    r_feature_delay[0]<=0;
                else
                    r_feature_delay[0]<=w_feature_lane[i];
            end

            genvar k;
            for (k=1;k<=LP_PE_TOTAL_LATENCY*i-1;k=k+1)begin:g_feature_delay
                always@(posedge i_clk or negedge i_rst_n)begin
                    if(~i_rst_n)
                        r_feature_delay[k]<=0;
                    else
                        r_feature_delay[k]<=r_feature_delay[k-1];
                end
            end

             ProcessingElementRow #(
                .P_DATA_WIDTH (P_DATA_WIDTH),
                .P_ARRAY_ROWS(P_ARRAY_ROWS),
                .P_ARRAY_COLS(P_ARRAY_COLS),
                .P_ROW_INDEX_WIDTH(P_ROW_INDEX_WIDTH)
            )
            u_processing_element_row
            (
                .i_clk(i_clk),
                .i_rst_n(i_rst_n),
                .i_weight_load(i_weight_load),
                .i_feature_value(r_feature_delay[LP_PE_TOTAL_LATENCY*i-1]),
                .i_partial_sum_vector(w_partial_sum_row_bus[i]),
                .i_weight_matrix(w_weight_row_bus[i]),
                .o_partial_sum_vector(w_partial_sum_row_bus[i+1])
            );           
        end
    end
endgenerate
endmodule
