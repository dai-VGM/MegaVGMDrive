`timescale 1ns/1ps

module tb_ym2610b_acc;
    logic rst = 1'b0;
    logic clk = 1'b0;
    logic clk_en = 1'b0;
    logic ym2610b_mode;
    logic signed [13:0] op_result;
    logic [1:0] rl = 2'b11;
    logic zero = 1'b0;
    logic s1_enters = 1'b1;
    logic s2_enters = 1'b1;
    logic s3_enters = 1'b1;
    logic s4_enters = 1'b1;
    logic [2:0] cur_ch;
    logic [1:0] cur_op = 2'd0;
    logic [2:0] alg = 3'd7;
    logic signed [15:0] adpcmA_l, adpcmA_r;
    logic signed [15:0] adpcmB_l, adpcmB_r;
    wire signed [15:0] left, right;

    ym2610_hw0_jt10_acc dut (
        .rst(rst), .clk(clk), .clk_en(clk_en),
        .ym2610b_mode(ym2610b_mode), .op_result(op_result), .rl(rl),
        .zero(zero), .s1_enters(s1_enters), .s2_enters(s2_enters),
        .s3_enters(s3_enters), .s4_enters(s4_enters),
        .cur_ch(cur_ch), .cur_op(cur_op), .alg(alg),
        .adpcmA_l(adpcmA_l), .adpcmA_r(adpcmA_r),
        .adpcmB_l(adpcmB_l), .adpcmB_r(adpcmB_r),
        .left(left), .right(right)
    );

    task automatic expect_inputs(input signed [15:0] expected);
        #1;
        if (dut.acc_input_l !== expected || dut.acc_input_r !== expected)
            $fatal(1, "acc input expected=%0d actual=%0d/%0d A=%0d B=%0d FM=%0d en=%0b/%0b mode=%0b alg=%0d sum=%0b rl=%0b",
                   expected, dut.acc_input_l, dut.acc_input_r,
                   dut.adpcmA_mix_l, dut.adpcmB_mix_l, dut.fm_input,
                   dut.fm_en_l, dut.fm_en_r, ym2610b_mode, alg, dut.sum_en, rl);
    endtask

    initial begin
        rst = 1'b0;
        clk_en = 1'b0;
        rl = 2'b11;
        zero = 1'b0;
        s1_enters = 1'b1;
        s2_enters = 1'b1;
        s3_enters = 1'b1;
        s4_enters = 1'b1;
        cur_op = 2'd0;
        alg = 3'd0;
        adpcmA_l = 16'sd1000;
        adpcmA_r = 16'sd1000;
        adpcmB_l = 16'sd2000;
        adpcmB_r = 16'sd2000;
        op_result = 14'sd2000;
        cur_ch = 3'd0;
        ym2610b_mode = 1'b0;
        #1;
        alg = 3'd7;
        expect_inputs(16'sd6000);
        ym2610b_mode = 1'b1;
        expect_inputs(16'sd7000);

        adpcmA_l = 16'sd5000;
        adpcmA_r = 16'sd5000;
        op_result = 14'sd8191;
        expect_inputs(16'sd32767);
        adpcmA_l = -16'sd5000;
        adpcmA_r = -16'sd5000;
        op_result = -14'sd8192;
        expect_inputs(-16'sd32768);

        cur_ch = 3'd4;
        op_result = 14'sd2000;
        ym2610b_mode = 1'b0;
        expect_inputs(16'sd1000);
        ym2610b_mode = 1'b1;
        expect_inputs(16'sd2000);

        $display("YM2610B_ACC mode=PASS adpcma_plus_fm=PASS adpcmb_plus_fm=PASS saturation=PASS result=PASS");
        $finish;
    end
endmodule
