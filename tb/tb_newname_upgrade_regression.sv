`timescale 1ns / 1ns

module tb_newname_4x4_array_4x4_matrix;
    gemm_accelerator_matrix_verify_padded #(
        .P_ARRAY_SIZE(4),
        .M(4),
        .K(4),
        .N(4),
        .P_BUFFER_DEPTH(64),
        .P_TIMEOUT_CYCLE(20000),
        .P_TEST_ID(0)
    ) u_verify();
endmodule

module tb_newname_8x8_array_4x4_matrix;
    gemm_accelerator_matrix_verify_padded #(
        .P_ARRAY_SIZE(8),
        .M(4),
        .K(4),
        .N(4),
        .P_BUFFER_DEPTH(64),
        .P_TIMEOUT_CYCLE(30000),
        .P_TEST_ID(1)
    ) u_verify();
endmodule

module tb_newname_32x32_array_32x32_matrix;
    gemm_accelerator_matrix_verify_padded #(
        .P_ARRAY_SIZE(32),
        .M(32),
        .K(32),
        .N(32),
        .P_BUFFER_DEPTH(128),
        .P_TIMEOUT_CYCLE(50000),
        .P_TEST_ID(2)
    ) u_verify();
endmodule

module tb_newname_32x32_array_64x64_matrix;
    gemm_accelerator_matrix_verify_padded #(
        .P_ARRAY_SIZE(32),
        .M(64),
        .K(64),
        .N(64),
        .P_BUFFER_DEPTH(256),
        .P_TIMEOUT_CYCLE(120000),
        .P_TEST_ID(3)
    ) u_verify();
endmodule

module gemm_accelerator_matrix_verify_padded #(
    parameter integer P_ARRAY_SIZE = 32,
    parameter integer P_DATA_WIDTH = 8,
    parameter integer P_SHIFT_WIDTH = 10,
    parameter integer M = 64,
    parameter integer K = 64,
    parameter integer N = 64,
    parameter integer P_BUFFER_DEPTH = 256,
    parameter integer P_TIMEOUT_CYCLE = 100000,
    parameter integer P_TEST_ID = 0
);

localparam integer LP_K_BLOCKS = (K + P_ARRAY_SIZE - 1) / P_ARRAY_SIZE;
localparam integer LP_N_BLOCKS = (N + P_ARRAY_SIZE - 1) / P_ARRAY_SIZE;
localparam integer LP_PADDED_K = LP_K_BLOCKS * P_ARRAY_SIZE;
localparam integer LP_PADDED_N = LP_N_BLOCKS * P_ARRAY_SIZE;
localparam integer LP_EXPECTED_FEATURE_WORDS = M * LP_K_BLOCKS;
localparam integer LP_EXPECTED_WEIGHT_WORDS = LP_PADDED_K * LP_N_BLOCKS;
localparam integer LP_EXPECTED_OUTPUT_WORDS = M * LP_N_BLOCKS;
localparam integer LP_EXPECTED_RAW_PARTIAL_WORDS = M * LP_K_BLOCKS * LP_N_BLOCKS;
localparam integer LP_STREAM_WORD_WIDTH = P_ARRAY_SIZE * P_DATA_WIDTH;
localparam integer LP_ROW_INDEX_WIDTH = (P_ARRAY_SIZE <= 1) ? 1 : $clog2(P_ARRAY_SIZE);
localparam integer LP_PSUM_WIDTH = 2 * P_DATA_WIDTH + LP_ROW_INDEX_WIDTH;
localparam integer P_ACCUM_WIDTH = 32;
localparam integer P_ROW_COUNT_WIDTH = 9;
localparam integer P_K_BLOCK_COUNT_WIDTH = 5;
localparam integer P_N_BLOCK_COUNT_WIDTH = 5;
localparam integer P_SHIFT = 0;

logic r_tb_clk;
logic r_tb_rst_n;

logic [P_SHIFT_WIDTH-1:0] r_cfg_shift;
logic [P_ROW_COUNT_WIDTH-1:0] r_cfg_row_count;
logic [P_K_BLOCK_COUNT_WIDTH-1:0] r_cfg_k_block_count;
logic [P_N_BLOCK_COUNT_WIDTH-1:0] r_cfg_n_block_count;

logic i_feature_valid;
wire i_feature_last;
wire o_feature_ready;
logic [LP_STREAM_WORD_WIDTH-1:0] i_feature_data;

logic i_weight_valid;
wire i_weight_last;
wire o_weight_ready;
logic [LP_STREAM_WORD_WIDTH-1:0] i_weight_data;

wire o_result_valid;
logic i_result_ready;
wire o_result_last;
wire [LP_STREAM_WORD_WIDTH-1:0] o_result_data;

wire w_feature_fire;
wire w_weight_fire;

logic r_result_ready_random;
logic output_collection_enabled;
logic config_mutation_done;

integer cycle;
integer r_feature_write_addr;
integer r_weight_write_addr;
integer result_word_count;
integer first_output_cycle;
integer last_output_cycle;
integer mismatch_count;
integer mismatch_print_count;
integer protocol_error_count;
integer pre_start_valid_count;
integer pre_start_accept_count;
integer raw_partial_word_count;
integer raw_partial_mismatch_count;
integer raw_partial_mismatch_print_count;
integer first_raw_partial_cycle;
integer last_raw_partial_cycle;
integer first_failure_cycle;
integer first_failure_output_index;
integer first_failure_row;
integer first_failure_col;
integer first_failure_expected;
integer first_failure_actual;
integer first_last_error_index;
integer expected_nonzero_count;
integer actual_nonzero_count;

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
integer golden_raw_tile [0:LP_K_BLOCKS-1][0:M-1][0:LP_PADDED_N-1];
integer golden_q [0:M-1][0:LP_PADDED_N-1];

assign w_feature_fire = i_feature_valid & o_feature_ready;
assign w_weight_fire = i_weight_valid & o_weight_ready;
assign i_feature_last = i_feature_valid & (r_feature_write_addr == LP_EXPECTED_FEATURE_WORDS - 1);
assign i_weight_last = i_weight_valid & (r_weight_write_addr == LP_EXPECTED_WEIGHT_WORDS - 1);

GemmAccelerator #(
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
) u_gemm_accelerator (
    .i_clk(r_tb_clk),
    .i_rst_n(r_tb_rst_n),
    .i_cfg_shift(r_cfg_shift),
    .i_cfg_row_count(r_cfg_row_count),
    .i_cfg_k_block_count(r_cfg_k_block_count),
    .i_cfg_n_block_count(r_cfg_n_block_count),
    .i_feature_valid(i_feature_valid),
    .i_feature_last(i_feature_last),
    .o_feature_ready(o_feature_ready),
    .i_feature_data(i_feature_data),
    .i_weight_valid(i_weight_valid),
    .i_weight_last(i_weight_last),
    .o_weight_ready(o_weight_ready),
    .i_weight_data(i_weight_data),
    .o_result_valid(o_result_valid),
    .i_result_ready(i_result_ready),
    .o_result_last(o_result_last),
    .o_result_data(o_result_data)
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

    if ((M > 0) && (K > 0))
        A[0][0] = 8'sd127;
    if ((M > 0) && (K > 1))
        A[0][1] = 8'sh80;
    if ((M > 0) && (K > 2))
        A[0][2] = 8'sd0;
    if ((M > 0) && (K > 3))
        A[0][3] = 8'sd1;
    if ((M > 0) && (K > 4))
        A[0][4] = -8'sd1;
    if ((M > 0) && (K > 0))
        A[M/2][0] = 8'sh80;
    if ((M > 0) && (K > 0))
        A[M-1][K-1] = -8'sd1;

    if ((K > 0) && (N > 0))
        B[0][0] = 8'sd1;
    if ((K > 1) && (N > 0))
        B[1][0] = -8'sd1;
    if ((K > 2) && (N > 1))
        B[2][1] = 8'sd127;
    if ((K > 3) && (N > 2))
        B[3][2] = 8'sh80;
    if ((K > 4) && (N > 3))
        B[4][3] = 8'sd0;
    if ((K > 5) && (N > 4))
        B[5][4] = 8'sd1;
    if ((K > 6) && (N > 5))
        B[6][5] = -8'sd1;
    if ((K > 0) && (N > 0))
        B[K/2][N/2] = 8'sd127;
    if ((K > 0) && (N > 0))
        B[K-1][N-1] = -8'sd1;
end
endtask

task automatic compute_golden;
    integer row;
    integer col;
    integer kk;
    integer tile;
    integer partial;
    integer acc;
begin
    expected_nonzero_count = 0;
    for (tile = 0; tile < LP_K_BLOCKS; tile = tile + 1) begin
        for (row = 0; row < M; row = row + 1) begin
            for (col = 0; col < LP_PADDED_N; col = col + 1) begin
                partial = 0;
                for (kk = tile * P_ARRAY_SIZE; kk < (tile + 1) * P_ARRAY_SIZE; kk = kk + 1) begin
                    if ((kk < K) && (col < N))
                        partial = partial + A[row][kk] * B[kk][col];
                end
                golden_raw_tile[tile][row][col] = partial;
            end
        end
    end

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

task automatic drive_feature_stream;
    integer next_addr;
begin
    r_feature_write_addr = 0;
    i_feature_data = pack_feature_word(0);
    i_feature_valid = 1;
    while (r_feature_write_addr < LP_EXPECTED_FEATURE_WORDS) begin
        @(posedge r_tb_clk);
        if (w_feature_fire) begin
            next_addr = r_feature_write_addr + 1;
            r_feature_write_addr <= next_addr;
            if (next_addr < LP_EXPECTED_FEATURE_WORDS)
                i_feature_data <= pack_feature_word(next_addr);
            else
                i_feature_valid <= 0;
        end
    end
end
endtask

task automatic drive_weight_stream;
    integer next_addr;
begin
    r_weight_write_addr = 0;
    i_weight_data = pack_weight_word(0);
    i_weight_valid = 1;
    while (r_weight_write_addr < LP_EXPECTED_WEIGHT_WORDS) begin
        @(posedge r_tb_clk);
        if (w_weight_fire) begin
            next_addr = r_weight_write_addr + 1;
            r_weight_write_addr <= next_addr;
            if (next_addr < LP_EXPECTED_WEIGHT_WORDS)
                i_weight_data <= pack_weight_word(next_addr);
            else
                i_weight_valid <= 0;
        end
    end
end
endtask

task automatic mutate_config_while_busy;
begin
    wait(w_feature_fire || w_weight_fire);
    repeat (3) @(posedge r_tb_clk);
    r_cfg_shift <= 7;
    r_cfg_row_count <= M + 3;
    r_cfg_k_block_count <= LP_K_BLOCKS + 2;
    r_cfg_n_block_count <= LP_N_BLOCKS + 2;
    config_mutation_done <= 1;
end
endtask

task automatic print_summary;
begin
    $display("First accepted output cycle = %0d", first_output_cycle);
    $display("Last accepted output cycle = %0d", last_output_cycle);
    $display("Output count = %0d", result_word_count);
    $display("Expected output count = %0d", LP_EXPECTED_OUTPUT_WORDS);
    $display("Mismatch count = %0d", mismatch_count);
    $display("Protocol error count = %0d", protocol_error_count);
    $display("Raw partial first/last valid cycle = %0d / %0d", first_raw_partial_cycle, last_raw_partial_cycle);
    $display("Raw partial output count = %0d", raw_partial_word_count);
    $display("Expected Raw partial output count = %0d", LP_EXPECTED_RAW_PARTIAL_WORDS);
    $display("Raw partial mismatch count = %0d", raw_partial_mismatch_count);
    $display("Pre-start o_result_valid cycles = %0d", pre_start_valid_count);
    $display("Pre-start accepted outputs = %0d", pre_start_accept_count);
    $display("Expected nonzero output values = %0d", expected_nonzero_count);
    $display("Actual nonzero output values = %0d", actual_nonzero_count);
    $display("Output all zero = %0d", (actual_nonzero_count == 0));
    $display("Config mutation during active job = %0d", config_mutation_done);
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

    if (result_word_count != LP_EXPECTED_OUTPUT_WORDS) begin
        $display("FAIL output count expected=%0d actual=%0d", LP_EXPECTED_OUTPUT_WORDS, result_word_count);
        $display("FAIL");
    end
    else if (raw_partial_word_count != LP_EXPECTED_RAW_PARTIAL_WORDS) begin
        $display("FAIL Raw partial output count expected=%0d actual=%0d", LP_EXPECTED_RAW_PARTIAL_WORDS, raw_partial_word_count);
        $display("FAIL");
    end
    else if ((expected_nonzero_count > 0) && (actual_nonzero_count == 0)) begin
        $display("FAIL output is all zero while golden has nonzero values");
        $display("FAIL");
    end
    else if (mismatch_count == 0 && protocol_error_count == 0 && raw_partial_mismatch_count == 0) begin
        $display("PASS");
    end
    else begin
        $display("FAIL");
    end
end
endtask

always #5 r_tb_clk = ~r_tb_clk;
initial r_result_ready_random = 1'b0;
always #10 r_result_ready_random = {$random} % 2;

always @(posedge r_tb_clk or negedge r_tb_rst_n) begin
    if(~r_tb_rst_n)
        i_result_ready <= 0;
    else if(output_collection_enabled)
        i_result_ready <= r_result_ready_random;
    else
        i_result_ready <= 0;
end

always @(posedge r_tb_clk or negedge r_tb_rst_n) begin
    if(~r_tb_rst_n)
        cycle <= 0;
    else
        cycle <= cycle + 1;
end

always @(posedge r_tb_clk) begin
    integer row;
    integer col;
    integer lane;
    integer n_block;
    integer actual;
    integer expected;
    integer raw_tile;
    integer raw_in_tile;
    integer raw_n_block;
    integer raw_row;
    integer raw_expected;
    integer raw_actual;

    if (r_tb_rst_n) begin
        if (prev_result_stall && o_result_valid && !i_result_ready) begin
            if (o_result_data !== prev_result_data) begin
                protocol_error_count = protocol_error_count + 1;
                remember_first_failure(cycle, result_word_count, -1, -1, 32'h53544142, 32'h44415441);
                $display("FAIL output data changed under backpressure at cycle=%0d", cycle);
            end
            if (o_result_last !== prev_result_last) begin
                protocol_error_count = protocol_error_count + 1;
                remember_first_failure(cycle, result_word_count, -1, -1, prev_result_last, o_result_last);
                $display("FAIL output TLAST changed under backpressure at cycle=%0d", cycle);
            end
        end

        if (prev_feature_stall && i_feature_valid && !o_feature_ready) begin
            if ((i_feature_data !== prev_feature_data) || (i_feature_last !== prev_feature_last)) begin
                protocol_error_count = protocol_error_count + 1;
                $display("FAIL feature source changed under backpressure at cycle=%0d", cycle);
            end
        end

        if (prev_weight_stall && i_weight_valid && !o_weight_ready) begin
            if ((i_weight_data !== prev_weight_data) || (i_weight_last !== prev_weight_last)) begin
                protocol_error_count = protocol_error_count + 1;
                $display("FAIL weight source changed under backpressure at cycle=%0d", cycle);
            end
        end

        if (u_gemm_accelerator.r_core_active) begin
            if ((u_gemm_accelerator.r_cfg_shift !== P_SHIFT) ||
                (u_gemm_accelerator.r_cfg_row_count !== M) ||
                (u_gemm_accelerator.r_cfg_k_block_count !== LP_K_BLOCKS) ||
                (u_gemm_accelerator.r_cfg_n_block_count !== LP_N_BLOCKS)) begin
                protocol_error_count = protocol_error_count + 1;
                remember_first_failure(cycle, result_word_count, -1, -1, 32'h4346474f, 32'h43464742);
                $display("FAIL runtime config changed while core active at cycle=%0d", cycle);
            end
        end

        if (!output_collection_enabled && o_result_valid) begin
            pre_start_valid_count = pre_start_valid_count + 1;
            if (i_result_ready)
                pre_start_accept_count = pre_start_accept_count + 1;
        end
        else if (output_collection_enabled && o_result_valid && i_result_ready) begin
            if (first_output_cycle < 0)
                first_output_cycle = cycle;
            last_output_cycle = cycle;

            if (result_word_count >= LP_EXPECTED_OUTPUT_WORDS) begin
                protocol_error_count = protocol_error_count + 1;
                remember_first_failure(cycle, result_word_count, -1, -1, LP_EXPECTED_OUTPUT_WORDS, result_word_count + 1);
                $display("FAIL extra output word: output_index=%0d cycle=%0d data=0x%0h",
                         result_word_count, cycle, o_result_data);
            end
            else begin
                row = result_word_count / LP_N_BLOCKS;
                n_block = result_word_count % LP_N_BLOCKS;
                for (lane = 0; lane < P_ARRAY_SIZE; lane = lane + 1) begin
                    col = n_block * P_ARRAY_SIZE + lane;
                    actual = $signed(o_result_data[lane*P_DATA_WIDTH +: P_DATA_WIDTH]);
                    expected = (col < N) ? golden_q[row][col] : 0;
                    if ((col < N) && (actual != 0))
                        actual_nonzero_count = actual_nonzero_count + 1;
                    if (actual !== expected) begin
                        mismatch_count = mismatch_count + 1;
                        remember_first_failure(cycle, result_word_count, row, col, expected, actual);
                        if (mismatch_print_count < 32) begin
                            $display("FAIL output mismatch row=%0d col=%0d expected=%0d actual=%0d output_index=%0d cycle=%0d",
                                     row, col, expected, actual, result_word_count, cycle);
                            mismatch_print_count = mismatch_print_count + 1;
                        end
                    end
                end
            end

            if (o_result_last !== (result_word_count == LP_EXPECTED_OUTPUT_WORDS - 1)) begin
                protocol_error_count = protocol_error_count + 1;
                if (first_last_error_index < 0)
                    first_last_error_index = result_word_count;
                $display("FAIL output TLAST mismatch expected=%0d actual=%0d output_index=%0d cycle=%0d",
                         (result_word_count == LP_EXPECTED_OUTPUT_WORDS - 1), o_result_last, result_word_count, cycle);
            end
            result_word_count = result_word_count + 1;
        end

        if (u_gemm_accelerator.w_compute_partial_valid) begin
            if (first_raw_partial_cycle < 0)
                first_raw_partial_cycle = cycle;
            last_raw_partial_cycle = cycle;

            if (raw_partial_word_count >= LP_EXPECTED_RAW_PARTIAL_WORDS) begin
                protocol_error_count = protocol_error_count + 1;
                $display("FAIL extra Raw partial output: index=%0d cycle=%0d", raw_partial_word_count, cycle);
            end
            else begin
                raw_tile = raw_partial_word_count / (LP_N_BLOCKS * M);
                raw_in_tile = raw_partial_word_count % (LP_N_BLOCKS * M);
                raw_n_block = raw_in_tile / M;
                raw_row = raw_in_tile % M;
                for (lane = 0; lane < P_ARRAY_SIZE; lane = lane + 1) begin
                    col = raw_n_block * P_ARRAY_SIZE + lane;
                    raw_expected = golden_raw_tile[raw_tile][raw_row][col];
                    raw_actual = $signed(u_gemm_accelerator.w_compute_partial_data[lane*LP_PSUM_WIDTH +: LP_PSUM_WIDTH]);
                    if (raw_actual !== raw_expected) begin
                        raw_partial_mismatch_count = raw_partial_mismatch_count + 1;
                        if (raw_partial_mismatch_print_count < 32) begin
                            $display("FAIL raw mismatch tile=%0d row=%0d col=%0d expected=%0d actual=%0d raw_index=%0d cycle=%0d",
                                     raw_tile, raw_row, col, raw_expected, raw_actual, raw_partial_word_count, cycle);
                            raw_partial_mismatch_print_count = raw_partial_mismatch_print_count + 1;
                        end
                    end
                end
                if (u_gemm_accelerator.w_compute_partial_last !== (raw_in_tile == (LP_N_BLOCKS * M - 1))) begin
                    protocol_error_count = protocol_error_count + 1;
                    $display("FAIL raw TLAST mismatch expected=%0d actual=%0d raw_index=%0d cycle=%0d",
                             (raw_in_tile == (LP_N_BLOCKS * M - 1)),
                             u_gemm_accelerator.w_compute_partial_last, raw_partial_word_count, cycle);
                end
            end
            raw_partial_word_count = raw_partial_word_count + 1;
        end

        prev_result_stall <= o_result_valid && !i_result_ready;
        prev_result_data <= o_result_data;
        prev_result_last <= o_result_last;
        prev_feature_stall <= i_feature_valid && !o_feature_ready;
        prev_feature_data <= i_feature_data;
        prev_feature_last <= i_feature_last;
        prev_weight_stall <= i_weight_valid && !o_weight_ready;
        prev_weight_data <= i_weight_data;
        prev_weight_last <= i_weight_last;
    end
end

initial begin
    r_tb_clk = 0;
    r_tb_rst_n = 0;
    r_cfg_shift = 0;
    r_cfg_row_count = 0;
    r_cfg_k_block_count = 0;
    r_cfg_n_block_count = 0;
    i_feature_valid = 0;
    i_feature_data = 0;
    r_feature_write_addr = 0;
    i_weight_valid = 0;
    i_weight_data = 0;
    r_weight_write_addr = 0;
    output_collection_enabled = 0;
    config_mutation_done = 0;
    cycle = 0;
    result_word_count = 0;
    first_output_cycle = -1;
    last_output_cycle = -1;
    mismatch_count = 0;
    mismatch_print_count = 0;
    protocol_error_count = 0;
    pre_start_valid_count = 0;
    pre_start_accept_count = 0;
    raw_partial_word_count = 0;
    raw_partial_mismatch_count = 0;
    raw_partial_mismatch_print_count = 0;
    first_raw_partial_cycle = -1;
    last_raw_partial_cycle = -1;
    first_failure_cycle = -1;
    first_failure_output_index = -1;
    first_failure_row = -1;
    first_failure_col = -1;
    first_failure_expected = 0;
    first_failure_actual = 0;
    first_last_error_index = -1;
    expected_nonzero_count = 0;
    actual_nonzero_count = 0;
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
    $display("Test id = %0d", P_TEST_ID);
    $display("Array size: %0dx%0d", P_ARRAY_SIZE, P_ARRAY_SIZE);
    $display("Logical matrix size: A=%0dx%0d B=%0dx%0d C=%0dx%0d", M, K, K, N, M, N);
    $display("Padded K/N: K=%0d N=%0d", LP_PADDED_K, LP_PADDED_N);
    $display("Config values: shift=%0d cfg_row_count=%0d cfg_k_block_count=%0d cfg_n_block_count=%0d",
             P_SHIFT, M, LP_K_BLOCKS, LP_N_BLOCKS);
    $display("Expected output words = %0d", LP_EXPECTED_OUTPUT_WORDS);
    $display("Expected raw partial words = %0d", LP_EXPECTED_RAW_PARTIAL_WORDS);
    $display("No fake config writes are used; config inputs are deliberately changed mid-job to test freeze");

    repeat (5) @(posedge r_tb_clk);
    r_tb_rst_n <= 1;
    repeat (10) @(posedge r_tb_clk);

    r_cfg_shift <= P_SHIFT;
    r_cfg_row_count <= M;
    r_cfg_k_block_count <= LP_K_BLOCKS;
    r_cfg_n_block_count <= LP_N_BLOCKS;

    repeat (20) @(posedge r_tb_clk);
    $display("Config checkpoint before start: shift=%0d cfg_row_count=%0d cfg_k_block_count=%0d cfg_n_block_count=%0d",
             u_gemm_accelerator.r_cfg_shift, u_gemm_accelerator.r_cfg_row_count,
             u_gemm_accelerator.r_cfg_k_block_count, u_gemm_accelerator.r_cfg_n_block_count);

    output_collection_enabled <= 1;

    fork
        drive_feature_stream();
        drive_weight_stream();
        mutate_config_while_busy();
    join_none

    fork
        begin
            wait(result_word_count == LP_EXPECTED_OUTPUT_WORDS);
            repeat (20) @(posedge r_tb_clk);
            print_summary();
            $finish;
        end
        begin
            repeat (P_TIMEOUT_CYCLE) @(posedge r_tb_clk);
            $display("FAIL timeout waiting for expected output count");
            print_summary();
            $finish;
        end
    join
end

endmodule
