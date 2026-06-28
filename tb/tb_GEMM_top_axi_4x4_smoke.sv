`timescale 1ns / 1ns

module tb_GEMM_top_axi_4x4_smoke;

localparam integer P_AXI_LITE_DATA_WIDTH = 32;
localparam integer P_AXI_LITE_ADDR_WIDTH = 4;
localparam integer P_ARRAY_SIZE = 32;
localparam integer P_DATA_WIDTH = 8;
localparam integer P_SHIFT_WIDTH = 10;
localparam integer P_BUFFER_DEPTH = 128;
localparam integer P_ACCUM_WIDTH = 32;
localparam integer P_ROW_COUNT_WIDTH = 9;
localparam integer P_K_BLOCK_COUNT_WIDTH = 5;
localparam integer P_N_BLOCK_COUNT_WIDTH = 5;

localparam integer M = 4;
localparam integer K = 4;
localparam integer N = 4;
localparam integer P_SHIFT = 0;

localparam integer LP_K_BLOCKS = (K + P_ARRAY_SIZE - 1) / P_ARRAY_SIZE;
localparam integer LP_N_BLOCKS = (N + P_ARRAY_SIZE - 1) / P_ARRAY_SIZE;
localparam integer LP_PADDED_K = LP_K_BLOCKS * P_ARRAY_SIZE;
localparam integer LP_PADDED_N = LP_N_BLOCKS * P_ARRAY_SIZE;
localparam integer LP_EXPECTED_FEATURE_BEATS = M * LP_K_BLOCKS;
localparam integer LP_EXPECTED_WEIGHT_BEATS = P_ARRAY_SIZE * LP_K_BLOCKS * LP_N_BLOCKS;
localparam integer LP_EXPECTED_OUTPUT_BEATS = M * LP_N_BLOCKS;
localparam integer LP_STREAM_WORD_WIDTH = P_ARRAY_SIZE * P_DATA_WIDTH;
localparam integer P_TIMEOUT_CYCLE = 20000;

localparam [P_AXI_LITE_ADDR_WIDTH-1:0] SHIFT_ADDR = 4'h0;
localparam [P_AXI_LITE_ADDR_WIDTH-1:0] FL_ADDR    = 4'h4;
localparam [P_AXI_LITE_ADDR_WIDTH-1:0] FWBN_ADDR  = 4'h8;
localparam [P_AXI_LITE_ADDR_WIDTH-1:0] WWBN_ADDR  = 4'hC;
localparam [P_ARRAY_SIZE-1:0] FULL_TSTRB = {P_ARRAY_SIZE{1'b1}};

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
integer result_accept_count;
integer result_tvalid_first_cycle;
integer result_tlast_accept_cycle;
integer protocol_error_count;
integer mismatch_count;
integer first_failed_cycle;
integer actual_nonzero_count;

logic [31:0] axil_readback_shift;
logic [31:0] axil_readback_fl;
logic [31:0] axil_readback_fwbn;
logic [31:0] axil_readback_wwbn;

logic signed [P_DATA_WIDTH-1:0] A [0:M-1][0:LP_PADDED_K-1];
logic signed [P_DATA_WIDTH-1:0] B [0:LP_PADDED_K-1][0:LP_PADDED_N-1];
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

function automatic signed [P_DATA_WIDTH-1:0] value_a(input integer row, input integer col);
begin
    value_a = ((row * 5 + col * 3 + 1) % 13) - 6;
end
endfunction

function automatic signed [P_DATA_WIDTH-1:0] value_b(input integer row, input integer col);
begin
    value_b = ((row * 7 + col * 2 + 4) % 11) - 5;
end
endfunction

function automatic [LP_STREAM_WORD_WIDTH-1:0] pack_feature_word(input integer word_addr);
    integer lane;
    integer row;
    integer kk;
    reg signed [P_DATA_WIDTH-1:0] lane_value;
begin
    pack_feature_word = 0;
    row = word_addr;
    for (lane = 0; lane < P_ARRAY_SIZE; lane = lane + 1) begin
        kk = lane;
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
    integer col;
    reg signed [P_DATA_WIDTH-1:0] lane_value;
begin
    pack_weight_word = 0;
    kk = word_addr;
    for (lane = 0; lane < P_ARRAY_SIZE; lane = lane + 1) begin
        col = lane;
        if ((kk < K) && (col < N))
            lane_value = B[kk][col];
        else
            lane_value = 0;
        pack_weight_word[lane*P_DATA_WIDTH +: P_DATA_WIDTH] = lane_value;
    end
end
endfunction

task automatic fail_now(input string reason);
begin
    if (first_failed_cycle < 0)
        first_failed_cycle = cycle;
    $display("SMOKE_FAIL reason=%s cycle=%0d axil_writes=%0d axil_reads=%0d feature=%0d/%0d weight=%0d/%0d result=%0d/%0d result_valid_first=%0d result_tlast_cycle=%0d protocol_errors=%0d mismatches=%0d",
             reason, cycle, axil_write_done_count, axil_read_done_count,
             feature_accept_count, LP_EXPECTED_FEATURE_BEATS,
             weight_accept_count, LP_EXPECTED_WEIGHT_BEATS,
             result_accept_count, LP_EXPECTED_OUTPUT_BEATS,
             result_tvalid_first_cycle, result_tlast_accept_cycle,
             protocol_error_count, mismatch_count);
    $finish;
end
endtask

task automatic init_matrices;
    integer row;
    integer col;
    integer kk;
    integer acc;
begin
    for (row = 0; row < M; row = row + 1) begin
        for (col = 0; col < LP_PADDED_K; col = col + 1) begin
            if (col < K)
                A[row][col] = value_a(row, col);
            else
                A[row][col] = 0;
        end
    end

    for (row = 0; row < LP_PADDED_K; row = row + 1) begin
        for (col = 0; col < LP_PADDED_N; col = col + 1) begin
            if ((row < K) && (col < N))
                B[row][col] = value_b(row, col);
            else
                B[row][col] = 0;
        end
    end

    for (row = 0; row < M; row = row + 1) begin
        for (col = 0; col < LP_PADDED_N; col = col + 1) begin
            acc = 0;
            for (kk = 0; kk < K; kk = kk + 1) begin
                if (col < N)
                    acc = acc + A[row][kk] * B[kk][col];
            end
            golden_q[row][col] = (col < N) ? quantize_to_int8(acc, P_SHIFT) : 0;
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
        fail_now("AXI_LITE_WRITE_BRESP");
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
        fail_now("AXI_LITE_READ_RRESP");
    end
    axil_read_done_count = axil_read_done_count + 1;
    $display("AXIL_READ_DONE addr=0x%0h data=0x%08h cycle=%0d", addr, data, cycle);
    @(posedge clk);
    S_AXI_RREADY <= 1'b0;
    S_AXI_ARADDR <= 0;
end
endtask

task automatic read_and_expect(
    input [P_AXI_LITE_ADDR_WIDTH-1:0] addr,
    input [31:0] mask,
    input [31:0] expected
);
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
        $display("FAIL AXI-Lite readback addr=0x%0h expected=0x%0h actual=0x%0h raw=0x%0h",
                 addr, expected, data & mask, data);
        fail_now("AXI_LITE_READBACK");
    end
end
endtask

task automatic drive_feature_stream;
    integer word_addr;
begin
    for (word_addr = 0; word_addr < LP_EXPECTED_FEATURE_BEATS; word_addr = word_addr + 1) begin
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
begin
    for (word_addr = 0; word_addr < LP_EXPECTED_WEIGHT_BEATS; word_addr = word_addr + 1) begin
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

task automatic print_pass_summary;
begin
    $display("SMOKE_SUMMARY");
    $display("AXI-Lite write completed count = %0d", axil_write_done_count);
    $display("AXI-Lite read completed count = %0d", axil_read_done_count);
    $display("AXI-Lite readback SHIFT = 0x%08h", axil_readback_shift);
    $display("AXI-Lite readback FL = 0x%08h", axil_readback_fl);
    $display("AXI-Lite readback FWBN = 0x%08h", axil_readback_fwbn);
    $display("AXI-Lite readback WWBN = 0x%08h", axil_readback_wwbn);
    $display("Feature beat count = %0d", feature_accept_count);
    $display("Expected feature beat count = %0d", LP_EXPECTED_FEATURE_BEATS);
    $display("Weight beat count = %0d", weight_accept_count);
    $display("Expected weight beat count = %0d", LP_EXPECTED_WEIGHT_BEATS);
    $display("Result TVALID first cycle = %0d", result_tvalid_first_cycle);
    $display("Result beat count = %0d", result_accept_count);
    $display("Expected result beat count = %0d", LP_EXPECTED_OUTPUT_BEATS);
    $display("Result TLAST accepted cycle = %0d", result_tlast_accept_cycle);
    $display("Mismatch count = %0d", mismatch_count);
    $display("Protocol error count = %0d", protocol_error_count);
    $display("Actual nonzero output values = %0d", actual_nonzero_count);
    $display("PASS");
end
endtask

always #5 clk = ~clk;

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
    integer actual;
    integer expected;

    if (rst_n) begin
        if (feature_axis_tvalid && feature_axis_tready) begin
            feature_accept_count = feature_accept_count + 1;
            $display("FEATURE_ACCEPT beat=%0d tlast=%0b tstrb=0x%08h cycle=%0d",
                     feature_accept_count, feature_axis_tlast, feature_axis_tstrb, cycle);
            if (feature_axis_tstrb !== FULL_TSTRB) begin
                protocol_error_count = protocol_error_count + 1;
                fail_now("FEATURE_TSTRB");
            end
            if (feature_axis_tlast !== (feature_accept_count == LP_EXPECTED_FEATURE_BEATS)) begin
                protocol_error_count = protocol_error_count + 1;
                $display("FAIL feature TLAST expected=%0d actual=%0d beat=%0d",
                         (feature_accept_count == LP_EXPECTED_FEATURE_BEATS),
                         feature_axis_tlast, feature_accept_count);
                fail_now("FEATURE_TLAST");
            end
        end

        if (weight_axis_tvalid && weight_axis_tready) begin
            weight_accept_count = weight_accept_count + 1;
            $display("WEIGHT_ACCEPT beat=%0d tlast=%0b tstrb=0x%08h cycle=%0d",
                     weight_accept_count, weight_axis_tlast, weight_axis_tstrb, cycle);
            if (weight_axis_tstrb !== FULL_TSTRB) begin
                protocol_error_count = protocol_error_count + 1;
                fail_now("WEIGHT_TSTRB");
            end
            if (weight_axis_tlast !== (weight_accept_count == LP_EXPECTED_WEIGHT_BEATS)) begin
                protocol_error_count = protocol_error_count + 1;
                $display("FAIL weight TLAST expected=%0d actual=%0d beat=%0d",
                         (weight_accept_count == LP_EXPECTED_WEIGHT_BEATS),
                         weight_axis_tlast, weight_accept_count);
                fail_now("WEIGHT_TLAST");
            end
        end

        if (result_axis_tvalid && (result_tvalid_first_cycle < 0)) begin
            result_tvalid_first_cycle = cycle;
            $display("RESULT_VALID_FIRST cycle=%0d", cycle);
        end

        if (result_axis_tvalid && (result_axis_tstrb !== FULL_TSTRB)) begin
            protocol_error_count = protocol_error_count + 1;
            fail_now("RESULT_TSTRB");
        end

        if (result_axis_tvalid && result_axis_tready) begin
            $display("RESULT_ACCEPT beat=%0d tlast=%0b cycle=%0d",
                     result_accept_count + 1, result_axis_tlast, cycle);
            if (result_axis_tlast && (result_tlast_accept_cycle < 0)) begin
                result_tlast_accept_cycle = cycle;
                $display("RESULT_TLAST_ACCEPT cycle=%0d beat=%0d",
                         cycle, result_accept_count + 1);
            end
            if (result_accept_count >= LP_EXPECTED_OUTPUT_BEATS) begin
                protocol_error_count = protocol_error_count + 1;
                fail_now("EXTRA_RESULT_BEAT");
            end

            row = result_accept_count / LP_N_BLOCKS;
            for (lane = 0; lane < P_ARRAY_SIZE; lane = lane + 1) begin
                col = lane;
                actual = $signed(result_axis_tdata[lane*P_DATA_WIDTH +: P_DATA_WIDTH]);
                expected = golden_q[row][col];
                if ((col < N) && (actual != 0))
                    actual_nonzero_count = actual_nonzero_count + 1;
                if (actual !== expected) begin
                    mismatch_count = mismatch_count + 1;
                    $display("FAIL output mismatch row=%0d col=%0d expected=%0d actual=%0d output_index=%0d cycle=%0d",
                             row, col, expected, actual, result_accept_count, cycle);
                    fail_now("RESULT_MISMATCH");
                end
            end

            if (result_axis_tlast !== (result_accept_count == LP_EXPECTED_OUTPUT_BEATS - 1)) begin
                protocol_error_count = protocol_error_count + 1;
                $display("FAIL result TLAST expected=%0d actual=%0d beat=%0d",
                         (result_accept_count == LP_EXPECTED_OUTPUT_BEATS - 1),
                         result_axis_tlast, result_accept_count + 1);
                fail_now("RESULT_TLAST");
            end
            result_accept_count = result_accept_count + 1;
        end
    end
end

initial begin
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
    result_accept_count = 0;
    result_tvalid_first_cycle = -1;
    result_tlast_accept_cycle = -1;
    protocol_error_count = 0;
    mismatch_count = 0;
    first_failed_cycle = -1;
    actual_nonzero_count = 0;
    axil_readback_shift = 0;
    axil_readback_fl = 0;
    axil_readback_fwbn = 0;
    axil_readback_wwbn = 0;

    init_matrices();

    $display("TEST START");
    $display("Testbench = tb_GEMM_top_axi_4x4_smoke");
    $display("DUT = GEMM_top");
    $display("Array size: %0dx%0d", P_ARRAY_SIZE, P_ARRAY_SIZE);
    $display("Logical matrix size: A=%0dx%0d B=%0dx%0d C=%0dx%0d", M, K, K, N, M, N);
    $display("Config values: shift=%0d row_count=%0d k_block_count=%0d n_block_count=%0d",
             P_SHIFT, M, LP_K_BLOCKS, LP_N_BLOCKS);
    $display("Expected feature beat count = %0d", LP_EXPECTED_FEATURE_BEATS);
    $display("Expected weight beat count = %0d", LP_EXPECTED_WEIGHT_BEATS);
    $display("Expected result beat count = %0d", LP_EXPECTED_OUTPUT_BEATS);

    repeat (8) @(posedge clk);
    rst_n <= 1'b1;
    result_axis_tready <= 1'b1;
    repeat (8) @(posedge clk);

    axi_lite_write(SHIFT_ADDR, P_SHIFT);
    axi_lite_write(FL_ADDR, M);
    axi_lite_write(FWBN_ADDR, LP_K_BLOCKS);
    axi_lite_write(WWBN_ADDR, LP_N_BLOCKS);
    read_and_expect(SHIFT_ADDR, 32'h0000_03FF, P_SHIFT);
    read_and_expect(FL_ADDR, 32'h0000_01FF, M);
    read_and_expect(FWBN_ADDR, 32'h0000_001F, LP_K_BLOCKS);
    read_and_expect(WWBN_ADDR, 32'h0000_001F, LP_N_BLOCKS);

    fork
        drive_feature_stream();
        drive_weight_stream();
        begin
            repeat (P_TIMEOUT_CYCLE) @(posedge clk);
            $display("TIMEOUT_REASON=WAIT_RESULT_BEATS feature=%0d/%0d weight=%0d/%0d result=%0d/%0d result_valid_first=%0d result_tlast_cycle=%0d cycle=%0d",
                     feature_accept_count, LP_EXPECTED_FEATURE_BEATS,
                     weight_accept_count, LP_EXPECTED_WEIGHT_BEATS,
                     result_accept_count, LP_EXPECTED_OUTPUT_BEATS,
                     result_tvalid_first_cycle, result_tlast_accept_cycle, cycle);
            fail_now("TIMEOUT");
        end
        begin
            wait (result_accept_count == LP_EXPECTED_OUTPUT_BEATS);
            repeat (10) @(posedge clk);
            if (feature_accept_count != LP_EXPECTED_FEATURE_BEATS)
                fail_now("FEATURE_BEAT_COUNT");
            if (weight_accept_count != LP_EXPECTED_WEIGHT_BEATS)
                fail_now("WEIGHT_BEAT_COUNT");
            if (result_tlast_accept_cycle < 0)
                fail_now("RESULT_TLAST_MISSING");
            if ((protocol_error_count == 0) && (mismatch_count == 0)) begin
                print_pass_summary();
                $finish;
            end
            else begin
                fail_now("SUMMARY_ERROR");
            end
        end
    join
end

endmodule
