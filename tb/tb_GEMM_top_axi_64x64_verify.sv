`timescale 1ns / 1ns

module tb_GEMM_top_axi_64x64_verify;

localparam integer P_AXI_LITE_DATA_WIDTH = 32;
localparam integer P_AXI_LITE_ADDR_WIDTH = 4;
localparam integer P_ARRAY_SIZE = 32;
localparam integer P_DATA_WIDTH = 8;
localparam integer P_SHIFT_WIDTH = 10;
localparam integer P_BUFFER_DEPTH = 512;
localparam integer P_ACCUM_WIDTH = 32;
localparam integer P_ROW_COUNT_WIDTH = 9;
localparam integer P_K_BLOCK_COUNT_WIDTH = 5;
localparam integer P_N_BLOCK_COUNT_WIDTH = 5;

localparam integer M = 64;
localparam integer K = 64;
localparam integer N = 64;
localparam integer P_SHIFT = 0;

localparam integer LP_K_BLOCKS = (K + P_ARRAY_SIZE - 1) / P_ARRAY_SIZE;
localparam integer LP_N_BLOCKS = (N + P_ARRAY_SIZE - 1) / P_ARRAY_SIZE;
localparam integer LP_PADDED_K = LP_K_BLOCKS * P_ARRAY_SIZE;
localparam integer LP_PADDED_N = LP_N_BLOCKS * P_ARRAY_SIZE;
localparam integer LP_EXPECTED_FEATURE_BEATS = M * LP_K_BLOCKS;
localparam integer LP_EXPECTED_WEIGHT_BEATS = LP_PADDED_K * LP_N_BLOCKS;
localparam integer LP_EXPECTED_OUTPUT_BEATS = M * LP_N_BLOCKS;
localparam integer LP_STREAM_WORD_WIDTH = P_ARRAY_SIZE * P_DATA_WIDTH;
localparam integer P_TIMEOUT_CYCLE = 160000;

localparam [P_AXI_LITE_ADDR_WIDTH-1:0] SHIFT_ADDR = 4'h0;
localparam [P_AXI_LITE_ADDR_WIDTH-1:0] FL_ADDR    = 4'h4;
localparam [P_AXI_LITE_ADDR_WIDTH-1:0] FWBN_ADDR  = 4'h8;
localparam [P_AXI_LITE_ADDR_WIDTH-1:0] WWBN_ADDR  = 4'hC;
localparam [P_ARRAY_SIZE-1:0] FULL_TSTRB = {P_ARRAY_SIZE{1'b1}};

localparam integer STATUS_BUSY_BIT = 24;
localparam integer STATUS_DONE_BIT = 25;
localparam integer STATUS_IDLE_BIT = 26;
localparam integer STATUS_CLEAR_ACCEPTED_BIT = 27;
localparam integer STATUS_CLEAR_BUSY_ERROR_BIT = 28;

logic clk;
logic rst_n;

logic [P_AXI_LITE_ADDR_WIDTH-1:0] S_AXI_AWADDR;
logic [2:0] S_AXI_AWPROT;
logic S_AXI_AWVALID;
wire S_AXI_AWREADY;
logic [P_AXI_LITE_DATA_WIDTH-1:0] S_AXI_WDATA;
logic [(P_AXI_LITE_DATA_WIDTH/8)-1:0] S_AXI_WSTRB;
logic S_AXI_WVALID;
wire S_AXI_WREADY;
wire [1:0] S_AXI_BRESP;
wire S_AXI_BVALID;
logic S_AXI_BREADY;
logic [P_AXI_LITE_ADDR_WIDTH-1:0] S_AXI_ARADDR;
logic [2:0] S_AXI_ARPROT;
logic S_AXI_ARVALID;
wire S_AXI_ARREADY;
wire [P_AXI_LITE_DATA_WIDTH-1:0] S_AXI_RDATA;
wire [1:0] S_AXI_RRESP;
wire S_AXI_RVALID;
logic S_AXI_RREADY;

wire feature_axis_tready;
logic [LP_STREAM_WORD_WIDTH-1:0] feature_axis_tdata;
logic [P_ARRAY_SIZE-1:0] feature_axis_tstrb;
logic feature_axis_tlast;
logic feature_axis_tvalid;

wire weight_axis_tready;
logic [LP_STREAM_WORD_WIDTH-1:0] weight_axis_tdata;
logic [P_ARRAY_SIZE-1:0] weight_axis_tstrb;
logic weight_axis_tlast;
logic weight_axis_tvalid;

wire result_axis_tvalid;
wire [LP_STREAM_WORD_WIDTH-1:0] result_axis_tdata;
wire [P_ARRAY_SIZE-1:0] result_axis_tstrb;
wire result_axis_tlast;
logic result_axis_tready;

integer cycle;
integer axil_write_done_count;
integer axil_read_done_count;
integer feature_accept_count;
integer weight_accept_count;
integer result_beat_count;
integer result_tvalid_first_cycle;
integer result_tlast_accept_cycle;
integer first_output_cycle;
integer last_output_cycle;
integer mismatch_count;
integer mismatch_print_count;
integer protocol_error_count;
integer pre_start_valid_count;
integer pre_start_accept_count;
integer expected_nonzero_count;
integer actual_nonzero_count;
integer first_failure_cycle;
integer first_failure_output_index;
integer first_failure_row;
integer first_failure_col;
integer first_failure_expected;
integer first_failure_actual;
integer first_last_error_index;
integer post_last_valid_count;

logic [31:0] axil_readback_shift;
logic [31:0] axil_readback_fl;
logic [31:0] axil_readback_fwbn;
logic [31:0] axil_readback_wwbn;

logic output_collection_enabled;
logic main_stream_active;
logic config_mutation_done;
logic busy_observed;
logic done_observed;
logic idle_after_done_observed;
logic clear_done_observed;
logic clear_while_busy_checked;
logic clear_while_busy_kept_busy;
logic clear_busy_error_observed;
logic partial_tstrb_rejected;
logic tstrb_full_pass;
logic tlast_pass;
logic output_all_zero_pass;
logic config_freeze_pass;
logic busy_done_status_pass;
logic force_result_ready_high;

logic prev_result_stall;
logic [LP_STREAM_WORD_WIDTH-1:0] prev_result_data;
logic prev_result_last;
logic prev_feature_stall;
logic [LP_STREAM_WORD_WIDTH-1:0] prev_feature_data;
logic prev_feature_last;
logic prev_weight_stall;
logic [LP_STREAM_WORD_WIDTH-1:0] prev_weight_data;
logic prev_weight_last;

logic signed [P_DATA_WIDTH-1:0] A [0:M-1][0:LP_PADDED_K-1];
logic signed [P_DATA_WIDTH-1:0] B [0:LP_PADDED_K-1][0:LP_PADDED_N-1];
integer golden_raw [0:M-1][0:LP_PADDED_N-1];
integer golden_q [0:M-1][0:LP_PADDED_N-1];

GEMM_top #(
    .P_AXI_LITE_DATA_WIDTH(P_AXI_LITE_DATA_WIDTH),
    .P_AXI_LITE_ADDR_WIDTH(P_AXI_LITE_ADDR_WIDTH),
    .P_ARRAY_SIZE(P_ARRAY_SIZE),
    .P_DATA_WIDTH(P_DATA_WIDTH),
    .P_SHIFT_WIDTH(P_SHIFT_WIDTH),
    .P_WEIGHT_BUFFER_DEPTH(P_BUFFER_DEPTH),
    .P_FEATURE_BUFFER_DEPTH(P_BUFFER_DEPTH),
    .P_OUTPUT_BUFFER_DEPTH(P_BUFFER_DEPTH),
    .P_ACCUM_WIDTH(P_ACCUM_WIDTH),
    .P_ROW_COUNT_WIDTH(P_ROW_COUNT_WIDTH),
    .P_K_BLOCK_COUNT_WIDTH(P_K_BLOCK_COUNT_WIDTH),
    .P_N_BLOCK_COUNT_WIDTH(P_N_BLOCK_COUNT_WIDTH)
) dut (
    .S_AXI_ACLK(clk),
    .S_AXI_ARESETN(rst_n),
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
    .S_AXI_RREADY(S_AXI_RREADY),
    .feature_axis_tready(feature_axis_tready),
    .feature_axis_tdata(feature_axis_tdata),
    .feature_axis_tstrb(feature_axis_tstrb),
    .feature_axis_tlast(feature_axis_tlast),
    .feature_axis_tvalid(feature_axis_tvalid),
    .weight_axis_tready(weight_axis_tready),
    .weight_axis_tdata(weight_axis_tdata),
    .weight_axis_tstrb(weight_axis_tstrb),
    .weight_axis_tlast(weight_axis_tlast),
    .weight_axis_tvalid(weight_axis_tvalid),
    .result_axis_tvalid(result_axis_tvalid),
    .result_axis_tdata(result_axis_tdata),
    .result_axis_tstrb(result_axis_tstrb),
    .result_axis_tlast(result_axis_tlast),
    .result_axis_tready(result_axis_tready)
);

function automatic integer quantize_to_int8(input integer value, input integer shift_amount);
    integer temp;
begin
    temp = value;
    if (shift_amount > 0)
        temp = (temp + (1 <<< (shift_amount - 1))) >>> shift_amount;
    if (temp > 127)
        temp = 127;
    else if (temp < -128)
        temp = -128;
    quantize_to_int8 = temp;
end
endfunction

function automatic signed [P_DATA_WIDTH-1:0] matrix_value_a(input integer row, input integer col);
    integer value;
begin
    if ((row < M) && (col < K)) begin
        value = ((row * 17 + col * 7 + (row % 5) * 3) % 29) - 14;
        matrix_value_a = value;
    end
    else begin
        matrix_value_a = 0;
    end
end
endfunction

function automatic signed [P_DATA_WIDTH-1:0] matrix_value_b(input integer row, input integer col);
    integer value;
begin
    if ((row < K) && (col < N)) begin
        value = ((row * 5 + col * 11 + (col % 7) * 4) % 31) - 15;
        matrix_value_b = value;
    end
    else begin
        matrix_value_b = 0;
    end
end
endfunction

function automatic [LP_STREAM_WORD_WIDTH-1:0] pack_feature_word(input integer word_addr);
    integer lane;
    integer row;
    integer k_block;
    integer kk;
    reg signed [P_DATA_WIDTH-1:0] lane_value;
begin
    pack_feature_word = 0;
    row = word_addr / LP_K_BLOCKS;
    k_block = word_addr % LP_K_BLOCKS;
    for (lane = 0; lane < P_ARRAY_SIZE; lane = lane + 1) begin
        kk = k_block * P_ARRAY_SIZE + lane;
        if ((row < M) && (kk < K))
            lane_value = A[row][kk];
        else
            lane_value = 0;
        pack_feature_word[lane*P_DATA_WIDTH +: P_DATA_WIDTH] = lane_value;
    end
end
endfunction

function automatic [LP_STREAM_WORD_WIDTH-1:0] pack_weight_word(input integer word_addr);
    integer lane;
    integer kk;
    integer n_block;
    integer col;
    reg signed [P_DATA_WIDTH-1:0] lane_value;
begin
    pack_weight_word = 0;
    kk = word_addr / LP_N_BLOCKS;
    n_block = word_addr % LP_N_BLOCKS;
    for (lane = 0; lane < P_ARRAY_SIZE; lane = lane + 1) begin
        col = n_block * P_ARRAY_SIZE + lane;
        if ((kk < K) && (col < N))
            lane_value = B[kk][col];
        else
            lane_value = 0;
        pack_weight_word[lane*P_DATA_WIDTH +: P_DATA_WIDTH] = lane_value;
    end
end
endfunction

task automatic remember_first_failure(
    input integer fail_cycle,
    input integer output_index,
    input integer row,
    input integer col,
    input integer expected,
    input integer actual
);
begin
    if (first_failure_cycle < 0) begin
        first_failure_cycle = fail_cycle;
        first_failure_output_index = output_index;
        first_failure_row = row;
        first_failure_col = col;
        first_failure_expected = expected;
        first_failure_actual = actual;
    end
end
endtask

task automatic init_matrices;
    integer row;
    integer col;
begin
    for (row = 0; row < M; row = row + 1) begin
        for (col = 0; col < LP_PADDED_K; col = col + 1)
            A[row][col] = matrix_value_a(row, col);
    end
    for (row = 0; row < LP_PADDED_K; row = row + 1) begin
        for (col = 0; col < LP_PADDED_N; col = col + 1)
            B[row][col] = matrix_value_b(row, col);
    end

    A[0][0] = 8'sd127;
    A[0][1] = 8'sh80;
    A[0][2] = 8'sd0;
    A[0][3] = 8'sd1;
    A[0][4] = -8'sd1;
    A[M/2][0] = 8'sh80;
    A[M-1][K-1] = -8'sd1;

    B[0][0] = 8'sd1;
    B[1][0] = -8'sd1;
    B[2][1] = 8'sd127;
    B[3][2] = 8'sh80;
    B[4][3] = 8'sd0;
    B[5][4] = 8'sd1;
    B[6][5] = -8'sd1;
    B[K/2][N/2] = 8'sd127;
    B[K-1][N-1] = -8'sd1;
end
endtask

task automatic compute_golden;
    integer row;
    integer col;
    integer kk;
    integer acc;
begin
    expected_nonzero_count = 0;
    for (row = 0; row < M; row = row + 1) begin
        for (col = 0; col < LP_PADDED_N; col = col + 1) begin
            acc = 0;
            for (kk = 0; kk < K; kk = kk + 1) begin
                if (col < N)
                    acc = acc + A[row][kk] * B[kk][col];
            end
            golden_raw[row][col] = acc;
            golden_q[row][col] = quantize_to_int8(acc, P_SHIFT);
            if ((col < N) && (golden_q[row][col] != 0))
                expected_nonzero_count = expected_nonzero_count + 1;
        end
    end
end
endtask

task automatic axi_lite_write(input [P_AXI_LITE_ADDR_WIDTH-1:0] addr, input [31:0] data);
begin
    @(posedge clk);
    S_AXI_AWADDR <= addr;
    S_AXI_AWPROT <= 3'b000;
    S_AXI_AWVALID <= 1'b1;
    S_AXI_WDATA <= data;
    S_AXI_WSTRB <= 4'hF;
    S_AXI_WVALID <= 1'b1;
    S_AXI_BREADY <= 1'b1;
    do @(posedge clk); while (!(S_AXI_AWREADY && S_AXI_WREADY));
    S_AXI_AWVALID <= 1'b0;
    S_AXI_WVALID <= 1'b0;
    do @(posedge clk); while (!S_AXI_BVALID);
    if (S_AXI_BRESP != 2'b00) begin
        protocol_error_count = protocol_error_count + 1;
        $display("FAIL AXI-Lite write BRESP addr=0x%0h resp=%0d cycle=%0d", addr, S_AXI_BRESP, cycle);
    end
    axil_write_done_count = axil_write_done_count + 1;
    $display("AXIL_WRITE_DONE addr=0x%0h data=0x%08h cycle=%0d", addr, data, cycle);
    @(posedge clk);
    S_AXI_BREADY <= 1'b0;
    S_AXI_AWADDR <= 0;
    S_AXI_WDATA <= 0;
end
endtask

task automatic axi_lite_read(input [P_AXI_LITE_ADDR_WIDTH-1:0] addr, output [31:0] data);
begin
    @(posedge clk);
    S_AXI_ARADDR <= addr;
    S_AXI_ARPROT <= 3'b000;
    S_AXI_ARVALID <= 1'b1;
    S_AXI_RREADY <= 1'b1;
    do @(posedge clk); while (!S_AXI_ARREADY);
    S_AXI_ARVALID <= 1'b0;
    do @(posedge clk); while (!S_AXI_RVALID);
    data = S_AXI_RDATA;
    if (S_AXI_RRESP != 2'b00) begin
        protocol_error_count = protocol_error_count + 1;
        $display("FAIL AXI-Lite read RRESP addr=0x%0h resp=%0d cycle=%0d", addr, S_AXI_RRESP, cycle);
    end
    axil_read_done_count = axil_read_done_count + 1;
    $display("AXIL_READ_DONE addr=0x%0h data=0x%08h cycle=%0d", addr, data, cycle);
    @(posedge clk);
    S_AXI_RREADY <= 1'b0;
    S_AXI_ARADDR <= 0;
end
endtask

task automatic check_readback(input [P_AXI_LITE_ADDR_WIDTH-1:0] addr, input [31:0] mask, input [31:0] expected);
    reg [31:0] data;
begin
    axi_lite_read(addr, data);
    if (addr == SHIFT_ADDR)
        axil_readback_shift = data;
    else if (addr == FL_ADDR)
        axil_readback_fl = data;
    else if (addr == FWBN_ADDR)
        axil_readback_fwbn = data;
    else if (addr == WWBN_ADDR)
        axil_readback_wwbn = data;
    $display("CONFIG_READBACK addr=0x%0h raw=0x%08h masked=0x%08h expected=0x%08h cycle=%0d",
             addr, data, data & mask, expected, cycle);
    if ((data & mask) !== expected) begin
        protocol_error_count = protocol_error_count + 1;
        remember_first_failure(cycle, -1, -1, -1, expected, data & mask);
        $display("FAIL AXI-Lite readback addr=0x%0h expected=0x%0h actual=0x%0h raw=0x%0h",
                 addr, expected, data & mask, data);
    end
end
endtask

task automatic negative_partial_tstrb_check;
begin
    partial_tstrb_rejected = 1'b1;
    @(posedge clk);
    feature_axis_tdata <= pack_feature_word(0);
    feature_axis_tstrb <= 32'hFFFF_FFFE;
    feature_axis_tlast <= 1'b0;
    feature_axis_tvalid <= 1'b1;
    weight_axis_tdata <= pack_weight_word(0);
    weight_axis_tstrb <= 32'h7FFF_FFFF;
    weight_axis_tlast <= 1'b0;
    weight_axis_tvalid <= 1'b1;
    repeat (4) begin
        @(posedge clk);
        if (feature_axis_tready || weight_axis_tready)
            partial_tstrb_rejected = 1'b0;
    end
    feature_axis_tvalid <= 1'b0;
    weight_axis_tvalid <= 1'b0;
    feature_axis_tstrb <= FULL_TSTRB;
    weight_axis_tstrb <= FULL_TSTRB;
    repeat (2) @(posedge clk);
    if (!partial_tstrb_rejected) begin
        protocol_error_count = protocol_error_count + 1;
        $display("FAIL partial TSTRB was accepted during negative precheck");
    end
end
endtask

task automatic drive_feature_stream;
    integer word_addr;
    integer gap_count;
begin
    for (word_addr = 0; word_addr < LP_EXPECTED_FEATURE_BEATS; word_addr = word_addr + 1) begin
        gap_count = (word_addr * 5 + 1) % 4;
        repeat (gap_count) @(posedge clk);
        @(posedge clk);
        feature_axis_tdata <= pack_feature_word(word_addr);
        feature_axis_tstrb <= FULL_TSTRB;
        feature_axis_tlast <= (word_addr == LP_EXPECTED_FEATURE_BEATS - 1);
        feature_axis_tvalid <= 1'b1;
        do @(posedge clk); while (!feature_axis_tready);
        feature_axis_tvalid <= 1'b0;
        feature_axis_tlast <= 1'b0;
    end
end
endtask

task automatic drive_weight_stream;
    integer word_addr;
    integer gap_count;
begin
    for (word_addr = 0; word_addr < LP_EXPECTED_WEIGHT_BEATS; word_addr = word_addr + 1) begin
        gap_count = (word_addr * 7 + 2) % 5;
        repeat (gap_count) @(posedge clk);
        @(posedge clk);
        weight_axis_tdata <= pack_weight_word(word_addr);
        weight_axis_tstrb <= FULL_TSTRB;
        weight_axis_tlast <= (word_addr == LP_EXPECTED_WEIGHT_BEATS - 1);
        weight_axis_tvalid <= 1'b1;
        do @(posedge clk); while (!weight_axis_tready);
        weight_axis_tvalid <= 1'b0;
        weight_axis_tlast <= 1'b0;
    end
end
endtask

task automatic mutate_config_and_check_status;
    reg [31:0] status;
    reg [31:0] data;
begin
    wait ((feature_accept_count > 4) && (weight_accept_count > 4));
    repeat (3) @(posedge clk);
    axi_lite_read(SHIFT_ADDR, status);
    if (status[STATUS_BUSY_BIT])
        busy_observed = 1'b1;
    else begin
        protocol_error_count = protocol_error_count + 1;
        $display("FAIL busy status not observed during active job, status=0x%0h cycle=%0d", status, cycle);
    end

    axi_lite_write(SHIFT_ADDR, 32'h0001_0000);
    clear_while_busy_checked = 1'b1;
    axi_lite_read(SHIFT_ADDR, status);
    if (status[STATUS_BUSY_BIT])
        clear_while_busy_kept_busy = 1'b1;
    if (status[STATUS_CLEAR_BUSY_ERROR_BIT])
        clear_busy_error_observed = 1'b1;

    axi_lite_write(SHIFT_ADDR, 32'd7);
    axi_lite_write(FL_ADDR, 32'd63);
    axi_lite_write(FWBN_ADDR, 32'd1);
    axi_lite_write(WWBN_ADDR, 32'd1);

    axi_lite_read(SHIFT_ADDR, data);
    if ((data[9:0] !== 10'd7)) begin
        protocol_error_count = protocol_error_count + 1;
        $display("FAIL mutated shift readback expected=7 actual=%0d", data[9:0]);
    end
    axi_lite_read(FL_ADDR, data);
    if (data[8:0] !== 9'd63) begin
        protocol_error_count = protocol_error_count + 1;
        $display("FAIL mutated row_count readback expected=63 actual=%0d", data[8:0]);
    end
    config_mutation_done = 1'b1;
end
endtask

task automatic check_done_and_clear_status;
    reg [31:0] status;
begin
    force_result_ready_high = 1'b1;
    repeat (30) @(posedge clk);
    axi_lite_read(SHIFT_ADDR, status);
    if (status[STATUS_DONE_BIT])
        done_observed = 1'b1;
    else begin
        protocol_error_count = protocol_error_count + 1;
        $display("FAIL done status not observed after job, status=0x%0h cycle=%0d", status, cycle);
    end
    if (status[STATUS_IDLE_BIT])
        idle_after_done_observed = 1'b1;
    else begin
        protocol_error_count = protocol_error_count + 1;
        $display("FAIL idle status not observed after job, status=0x%0h cycle=%0d", status, cycle);
    end

    axi_lite_write(SHIFT_ADDR, 32'h0001_0000);
    repeat (3) @(posedge clk);
    axi_lite_read(SHIFT_ADDR, status);
    if (!status[STATUS_DONE_BIT])
        clear_done_observed = 1'b1;
    else begin
        protocol_error_count = protocol_error_count + 1;
        $display("FAIL done status did not clear, status=0x%0h cycle=%0d", status, cycle);
    end
end
endtask

task automatic print_summary;
begin
    tlast_pass = (first_last_error_index < 0);
    tstrb_full_pass = tstrb_full_pass && partial_tstrb_rejected &&
                      (feature_accept_count == LP_EXPECTED_FEATURE_BEATS) &&
                      (weight_accept_count == LP_EXPECTED_WEIGHT_BEATS);
    output_all_zero_pass = (expected_nonzero_count == 0) || (actual_nonzero_count != 0);
    config_freeze_pass = config_mutation_done &&
                         (result_beat_count == LP_EXPECTED_OUTPUT_BEATS) &&
                         (mismatch_count == 0);
    busy_done_status_pass = busy_observed && done_observed && idle_after_done_observed &&
                            clear_done_observed && clear_while_busy_checked &&
                            clear_while_busy_kept_busy;

    $display("First accepted output cycle = %0d", first_output_cycle);
    $display("Last accepted output cycle = %0d", last_output_cycle);
    $display("AXI-Lite write completed count = %0d", axil_write_done_count);
    $display("AXI-Lite read completed count = %0d", axil_read_done_count);
    $display("AXI-Lite readback SHIFT = 0x%08h", axil_readback_shift);
    $display("AXI-Lite readback FL = 0x%08h", axil_readback_fl);
    $display("AXI-Lite readback FWBN = 0x%08h", axil_readback_fwbn);
    $display("AXI-Lite readback WWBN = 0x%08h", axil_readback_wwbn);
    $display("Output beat count = %0d", result_beat_count);
    $display("Expected output beat count = %0d", LP_EXPECTED_OUTPUT_BEATS);
    $display("Feature beat count = %0d", feature_accept_count);
    $display("Expected feature beat count = %0d", LP_EXPECTED_FEATURE_BEATS);
    $display("Weight beat count = %0d", weight_accept_count);
    $display("Expected weight beat count = %0d", LP_EXPECTED_WEIGHT_BEATS);
    $display("Mismatch count = %0d", mismatch_count);
    $display("Protocol error count = %0d", protocol_error_count);
    $display("Pre-start result valid cycles = %0d", pre_start_valid_count);
    $display("Pre-start accepted outputs = %0d", pre_start_accept_count);
    $display("Expected nonzero output values = %0d", expected_nonzero_count);
    $display("Actual nonzero output values = %0d", actual_nonzero_count);
    $display("Output all zero = %0d", (actual_nonzero_count == 0));
    $display("Result TVALID first cycle = %0d", result_tvalid_first_cycle);
    $display("Result TLAST accepted cycle = %0d", result_tlast_accept_cycle);
    $display("Config mutation during active job = %0d", config_mutation_done);
    $display("Config-freeze check = %s", config_freeze_pass ? "PASS" : "FAIL");
    $display("Busy/done/status check = %s", busy_done_status_pass ? "PASS" : "FAIL");
    $display("TSTRB/full-beat check = %s", tstrb_full_pass ? "PASS" : "FAIL");
    $display("TLAST check = %s", tlast_pass ? "PASS" : "FAIL");
    $display("Output all-zero check = %s", output_all_zero_pass ? "PASS" : "FAIL");
    $display("Partial TSTRB rejected = %0d", partial_tstrb_rejected);
    $display("Clear while busy checked = %0d", clear_while_busy_checked);
    $display("Clear busy error observed = %0d", clear_busy_error_observed);

    if (first_failure_cycle >= 0)
        $display("First mismatch/failure: cycle=%0d output_index=%0d row=%0d col=%0d expected=%0d actual=%0d",
                 first_failure_cycle, first_failure_output_index, first_failure_row,
                 first_failure_col, first_failure_expected, first_failure_actual);
    else
        $display("First mismatch = none");

    if (first_last_error_index < 0)
        $display("Last check = correct");
    else
        $display("Last check = wrong at output index %0d", first_last_error_index);

    if ((result_beat_count == LP_EXPECTED_OUTPUT_BEATS) &&
        (feature_accept_count == LP_EXPECTED_FEATURE_BEATS) &&
        (weight_accept_count == LP_EXPECTED_WEIGHT_BEATS) &&
        (mismatch_count == 0) &&
        (protocol_error_count == 0) &&
        (pre_start_accept_count == 0) &&
        config_freeze_pass &&
        busy_done_status_pass &&
        tstrb_full_pass &&
        tlast_pass &&
        output_all_zero_pass)
        $display("PASS");
    else
        $display("FAIL");
end
endtask

always #5 clk = ~clk;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        result_axis_tready <= 1'b0;
    else if (force_result_ready_high)
        result_axis_tready <= 1'b1;
    else if (output_collection_enabled)
        result_axis_tready <= ((cycle % 7) != 0) && ((cycle % 11) != 0);
    else
        result_axis_tready <= 1'b0;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cycle <= 0;
    else
        cycle <= cycle + 1;
end

always @(posedge clk) begin
    integer row;
    integer col;
    integer lane;
    integer n_block;
    integer actual;
    integer expected;

    if (rst_n) begin
        if (feature_axis_tvalid && feature_axis_tready) begin
            feature_accept_count = feature_accept_count + 1;
            $display("FEATURE_ACCEPT beat=%0d tlast=%0b tstrb=0x%08h cycle=%0d",
                     feature_accept_count, feature_axis_tlast, feature_axis_tstrb, cycle);
            if (main_stream_active && (feature_axis_tstrb !== FULL_TSTRB)) begin
                protocol_error_count = protocol_error_count + 1;
                $display("FAIL feature TSTRB not full on accepted beat index=%0d", feature_accept_count - 1);
            end
            if (main_stream_active && (feature_axis_tlast !== (feature_accept_count == LP_EXPECTED_FEATURE_BEATS))) begin
                protocol_error_count = protocol_error_count + 1;
                $display("FAIL feature TLAST mismatch beat=%0d expected=%0d actual=%0d",
                         feature_accept_count - 1,
                         (feature_accept_count == LP_EXPECTED_FEATURE_BEATS),
                         feature_axis_tlast);
            end
        end

        if (weight_axis_tvalid && weight_axis_tready) begin
            weight_accept_count = weight_accept_count + 1;
            $display("WEIGHT_ACCEPT beat=%0d tlast=%0b tstrb=0x%08h cycle=%0d",
                     weight_accept_count, weight_axis_tlast, weight_axis_tstrb, cycle);
            if (main_stream_active && (weight_axis_tstrb !== FULL_TSTRB)) begin
                protocol_error_count = protocol_error_count + 1;
                $display("FAIL weight TSTRB not full on accepted beat index=%0d", weight_accept_count - 1);
            end
            if (main_stream_active && (weight_axis_tlast !== (weight_accept_count == LP_EXPECTED_WEIGHT_BEATS))) begin
                protocol_error_count = protocol_error_count + 1;
                $display("FAIL weight TLAST mismatch beat=%0d expected=%0d actual=%0d",
                         weight_accept_count - 1,
                         (weight_accept_count == LP_EXPECTED_WEIGHT_BEATS),
                         weight_axis_tlast);
            end
        end

        if (prev_result_stall && result_axis_tvalid && !result_axis_tready) begin
            if (result_axis_tdata !== prev_result_data) begin
                protocol_error_count = protocol_error_count + 1;
                remember_first_failure(cycle, result_beat_count, -1, -1, 32'h53544142, 32'h44415441);
                $display("FAIL result data changed under backpressure at cycle=%0d", cycle);
            end
            if (result_axis_tlast !== prev_result_last) begin
                protocol_error_count = protocol_error_count + 1;
                remember_first_failure(cycle, result_beat_count, -1, -1, prev_result_last, result_axis_tlast);
                $display("FAIL result TLAST changed under backpressure at cycle=%0d", cycle);
            end
        end

        if (prev_feature_stall && feature_axis_tvalid && !feature_axis_tready) begin
            if ((feature_axis_tdata !== prev_feature_data) || (feature_axis_tlast !== prev_feature_last)) begin
                protocol_error_count = protocol_error_count + 1;
                $display("FAIL feature source changed under backpressure at cycle=%0d", cycle);
            end
        end

        if (prev_weight_stall && weight_axis_tvalid && !weight_axis_tready) begin
            if ((weight_axis_tdata !== prev_weight_data) || (weight_axis_tlast !== prev_weight_last)) begin
                protocol_error_count = protocol_error_count + 1;
                $display("FAIL weight source changed under backpressure at cycle=%0d", cycle);
            end
        end

        if (result_axis_tvalid && (result_axis_tstrb !== FULL_TSTRB)) begin
            protocol_error_count = protocol_error_count + 1;
            $display("FAIL result TSTRB not full at cycle=%0d", cycle);
        end

        if (result_axis_tvalid && (result_tvalid_first_cycle < 0)) begin
            result_tvalid_first_cycle = cycle;
            $display("RESULT_VALID_FIRST cycle=%0d", cycle);
        end

        if (!output_collection_enabled && result_axis_tvalid) begin
            pre_start_valid_count = pre_start_valid_count + 1;
            if (result_axis_tready)
                pre_start_accept_count = pre_start_accept_count + 1;
        end
        else if (output_collection_enabled && result_axis_tvalid && result_axis_tready) begin
            $display("RESULT_ACCEPT beat=%0d tlast=%0b cycle=%0d",
                     result_beat_count + 1, result_axis_tlast, cycle);
            if (result_axis_tlast && (result_tlast_accept_cycle < 0)) begin
                result_tlast_accept_cycle = cycle;
                $display("RESULT_TLAST_ACCEPT cycle=%0d beat=%0d",
                         cycle, result_beat_count + 1);
            end
            if (first_output_cycle < 0)
                first_output_cycle = cycle;
            last_output_cycle = cycle;

            if (result_beat_count >= LP_EXPECTED_OUTPUT_BEATS) begin
                protocol_error_count = protocol_error_count + 1;
                post_last_valid_count = post_last_valid_count + 1;
                remember_first_failure(cycle, result_beat_count, -1, -1, LP_EXPECTED_OUTPUT_BEATS, result_beat_count + 1);
                $display("FAIL extra result beat output_index=%0d cycle=%0d", result_beat_count, cycle);
            end
            else begin
                row = result_beat_count / LP_N_BLOCKS;
                n_block = result_beat_count % LP_N_BLOCKS;
                for (lane = 0; lane < P_ARRAY_SIZE; lane = lane + 1) begin
                    col = n_block * P_ARRAY_SIZE + lane;
                    actual = $signed(result_axis_tdata[lane*P_DATA_WIDTH +: P_DATA_WIDTH]);
                    expected = (col < N) ? golden_q[row][col] : 0;
                    if ((col < N) && (actual != 0))
                        actual_nonzero_count = actual_nonzero_count + 1;
                    if (actual !== expected) begin
                        mismatch_count = mismatch_count + 1;
                        remember_first_failure(cycle, result_beat_count, row, col, expected, actual);
                        if (mismatch_print_count < 32) begin
                            $display("FAIL output mismatch row=%0d col=%0d expected=%0d actual=%0d output_index=%0d cycle=%0d",
                                     row, col, expected, actual, result_beat_count, cycle);
                            mismatch_print_count = mismatch_print_count + 1;
                        end
                    end
                end
            end

            if (result_axis_tlast !== (result_beat_count == LP_EXPECTED_OUTPUT_BEATS - 1)) begin
                protocol_error_count = protocol_error_count + 1;
                if (first_last_error_index < 0)
                    first_last_error_index = result_beat_count;
                $display("FAIL result TLAST mismatch expected=%0d actual=%0d output_index=%0d cycle=%0d",
                         (result_beat_count == LP_EXPECTED_OUTPUT_BEATS - 1),
                         result_axis_tlast, result_beat_count, cycle);
            end

            result_beat_count = result_beat_count + 1;
        end

        prev_result_stall <= result_axis_tvalid && !result_axis_tready;
        prev_result_data <= result_axis_tdata;
        prev_result_last <= result_axis_tlast;
        prev_feature_stall <= feature_axis_tvalid && !feature_axis_tready;
        prev_feature_data <= feature_axis_tdata;
        prev_feature_last <= feature_axis_tlast;
        prev_weight_stall <= weight_axis_tvalid && !weight_axis_tready;
        prev_weight_data <= weight_axis_tdata;
        prev_weight_last <= weight_axis_tlast;
    end
end

initial begin
    reg [31:0] status;

    clk = 0;
    rst_n = 0;
    S_AXI_AWADDR = 0;
    S_AXI_AWPROT = 0;
    S_AXI_AWVALID = 0;
    S_AXI_WDATA = 0;
    S_AXI_WSTRB = 0;
    S_AXI_WVALID = 0;
    S_AXI_BREADY = 0;
    S_AXI_ARADDR = 0;
    S_AXI_ARPROT = 0;
    S_AXI_ARVALID = 0;
    S_AXI_RREADY = 0;
    feature_axis_tdata = 0;
    feature_axis_tstrb = FULL_TSTRB;
    feature_axis_tlast = 0;
    feature_axis_tvalid = 0;
    weight_axis_tdata = 0;
    weight_axis_tstrb = FULL_TSTRB;
    weight_axis_tlast = 0;
    weight_axis_tvalid = 0;
    result_axis_tready = 0;

    cycle = 0;
    axil_write_done_count = 0;
    axil_read_done_count = 0;
    feature_accept_count = 0;
    weight_accept_count = 0;
    result_beat_count = 0;
    result_tvalid_first_cycle = -1;
    result_tlast_accept_cycle = -1;
    first_output_cycle = -1;
    last_output_cycle = -1;
    mismatch_count = 0;
    mismatch_print_count = 0;
    protocol_error_count = 0;
    pre_start_valid_count = 0;
    pre_start_accept_count = 0;
    expected_nonzero_count = 0;
    actual_nonzero_count = 0;
    first_failure_cycle = -1;
    first_failure_output_index = -1;
    first_failure_row = -1;
    first_failure_col = -1;
    first_failure_expected = 0;
    first_failure_actual = 0;
    first_last_error_index = -1;
    post_last_valid_count = 0;
    axil_readback_shift = 0;
    axil_readback_fl = 0;
    axil_readback_fwbn = 0;
    axil_readback_wwbn = 0;
    output_collection_enabled = 0;
    main_stream_active = 0;
    config_mutation_done = 0;
    busy_observed = 0;
    done_observed = 0;
    idle_after_done_observed = 0;
    clear_done_observed = 0;
    clear_while_busy_checked = 0;
    clear_while_busy_kept_busy = 0;
    clear_busy_error_observed = 0;
    partial_tstrb_rejected = 0;
    tstrb_full_pass = 1;
    tlast_pass = 0;
    output_all_zero_pass = 0;
    config_freeze_pass = 0;
    busy_done_status_pass = 0;
    force_result_ready_high = 0;
    prev_result_stall = 0;
    prev_result_data = 0;
    prev_result_last = 0;
    prev_feature_stall = 0;
    prev_feature_data = 0;
    prev_feature_last = 0;
    prev_weight_stall = 0;
    prev_weight_data = 0;
    prev_weight_last = 0;

    init_matrices();
    compute_golden();

    $display("TEST START");
    $display("Testbench = tb_GEMM_top_axi_64x64_verify");
    $display("DUT = GEMM_top");
    $display("Array size: %0dx%0d", P_ARRAY_SIZE, P_ARRAY_SIZE);
    $display("Logical matrix size: A=%0dx%0d B=%0dx%0d C=%0dx%0d", M, K, K, N, M, N);
    $display("Config values: shift=%0d row_count=%0d k_block_count=%0d n_block_count=%0d",
             P_SHIFT, M, LP_K_BLOCKS, LP_N_BLOCKS);
    $display("Expected output beat count = %0d", LP_EXPECTED_OUTPUT_BEATS);

    repeat (8) @(posedge clk);
    rst_n <= 1'b1;
    repeat (8) @(posedge clk);

    negative_partial_tstrb_check();

    axi_lite_write(SHIFT_ADDR, P_SHIFT);
    axi_lite_write(FL_ADDR, M);
    axi_lite_write(FWBN_ADDR, LP_K_BLOCKS);
    axi_lite_write(WWBN_ADDR, LP_N_BLOCKS);
    check_readback(SHIFT_ADDR, 32'h0000_03FF, P_SHIFT);
    check_readback(FL_ADDR, 32'h0000_01FF, M);
    check_readback(FWBN_ADDR, 32'h0000_001F, LP_K_BLOCKS);
    check_readback(WWBN_ADDR, 32'h0000_001F, LP_N_BLOCKS);

    axi_lite_read(SHIFT_ADDR, status);
    if (!status[STATUS_IDLE_BIT]) begin
        protocol_error_count = protocol_error_count + 1;
        $display("FAIL idle status not high before job, status=0x%0h", status);
    end

    output_collection_enabled <= 1'b1;
    main_stream_active <= 1'b1;

    fork
        drive_feature_stream();
        drive_weight_stream();
        mutate_config_and_check_status();
    join_none

    fork
        begin
            wait (result_beat_count == LP_EXPECTED_OUTPUT_BEATS);
            check_done_and_clear_status();
            repeat (10) @(posedge clk);
            print_summary();
            $finish;
        end
        begin
            repeat (P_TIMEOUT_CYCLE) @(posedge clk);
            $display("FAIL timeout waiting for expected output beat count");
            $display("TIMEOUT_REASON=WAIT_RESULT_BEATS feature=%0d/%0d weight=%0d/%0d result=%0d/%0d result_valid_first=%0d result_tlast_cycle=%0d cycle=%0d",
                     feature_accept_count, LP_EXPECTED_FEATURE_BEATS,
                     weight_accept_count, LP_EXPECTED_WEIGHT_BEATS,
                     result_beat_count, LP_EXPECTED_OUTPUT_BEATS,
                     result_tvalid_first_cycle, result_tlast_accept_cycle, cycle);
            print_summary();
            $finish;
        end
    join
end

endmodule
