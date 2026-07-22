`timescale 1ps/1ps

// Investigation-only reset/CEN timing sweep.  RESET_MODE:
//   0: 24 reset clocks, no CEN
//   1: one chip CEN while reset remains asserted
//   2: chip CEN until one internal FM enable occurs during reset
//   3: chip CEN until one 12-slot YM2203 operator round occurs during reset
//   4: release one system clock later, no CEN
//   5: extend reset to 96 system clocks, no CEN
//   6 and above: hold reset for (RESET_MODE-4)*12 internal FM enables
module tb_jt12_fm_reset_sweep #(
    parameter integer RESET_MODE = 0
);
    localparam integer SYS_CLK_HZ = 32_000_000;
    localparam integer CHIP_CLK_HZ = 4_000_000;
    localparam integer CEN_DIV = SYS_CLK_HZ / CHIP_CLK_HZ;
    localparam integer HALF_PS = 500_000_000_000 / SYS_CLK_HZ;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cen = 1'b0;
    logic run_cen = 1'b0;
    logic released = 1'b0;
    integer div_count = 0;
    integer sys_cycle = 0;
    integer release_cycle = -1;
    integer reset_chip_cen = 0;
    integer reset_fm_en = 0;

    wire signed [15:0] fm_l, fm_r;
    integer first_op_x = -1;
    integer first_acc_x = -1;
    integer first_snd_x = -1;
    integer first_public_x = -1;
    integer first_zero = -1;
    integer first_sum = -1;
    integer first_op_known_update = -1;
    integer first_acc_known_again = -1;
    integer first_snd_known_again = -1;
    bit acc_was_x = 0;
    bit snd_was_x = 0;

    always #(HALF_PS) clk = ~clk;

    always @(posedge clk) begin
        sys_cycle <= sys_cycle + 1;
        if (!run_cen) begin
            cen <= 1'b0;
            div_count <= 0;
        end else if (div_count == CEN_DIV-1) begin
            cen <= 1'b1;
            div_count <= 0;
        end else begin
            cen <= 1'b0;
            div_count <= div_count + 1;
        end
        if (rst && cen)
            reset_chip_cen <= reset_chip_cen + 1;
        if (rst && dut.clk_en)
            reset_fm_en <= reset_fm_en + 1;
    end

    jt12_top #(
        .use_lfo(0), .use_ssg(0), .num_ch(3), .use_pcm(0),
        .use_adpcm(0), .JT49_DIV(2), .mask_div(0)
    ) dut (
        .rst(rst), .clk(clk), .cen(cen), .din(8'h00), .addr(2'b00),
        .cs_n(1'b1), .wr_n(1'b1), .ladder(1'b0), .en_hifi_pcm(1'b0),
        .adpcma_data(8'h00), .adpcmb_data(8'h00),
        .IOA_in(8'h00), .IOB_in(8'h00), .debug_bus(8'h00),
        .fm_snd_left(fm_l), .fm_snd_right(fm_r)
    );

    always @(posedge clk) begin : monitor_after_release
        integer edge_cycle;
        edge_cycle = sys_cycle;
        if (released) begin
            if (first_op_x < 0 && (^dut.op_result_hd) === 1'bx)
                first_op_x = edge_cycle-release_cycle;
            if (first_acc_x < 0 && (^dut.gen_2203_acc.u_acc.u_mono.acc) === 1'bx)
                first_acc_x = edge_cycle-release_cycle;
            if (first_snd_x < 0 && (^dut.gen_2203_acc.u_acc.u_mono.snd) === 1'bx)
                first_snd_x = edge_cycle-release_cycle;
            if (first_public_x < 0 && (^fm_l) === 1'bx)
                first_public_x = edge_cycle-release_cycle;
            if (first_zero < 0 && dut.zero === 1'b1)
                first_zero = edge_cycle-release_cycle;
            if (first_sum < 0 && dut.gen_2203_acc.u_acc.sum_en === 1'b1)
                first_sum = edge_cycle-release_cycle;
            if (first_op_known_update < 0 && dut.clk_en && (^dut.op_result_hd) !== 1'bx)
                first_op_known_update = edge_cycle-release_cycle;
            #1;
            if (first_acc_x < 0 && (^dut.gen_2203_acc.u_acc.u_mono.acc) === 1'bx)
                first_acc_x = edge_cycle-release_cycle;
            if (first_snd_x < 0 && (^dut.gen_2203_acc.u_acc.u_mono.snd) === 1'bx)
                first_snd_x = edge_cycle-release_cycle;
            if (first_public_x < 0 && (^fm_l) === 1'bx)
                first_public_x = edge_cycle-release_cycle;
            if (acc_was_x && first_acc_known_again < 0 && (^dut.gen_2203_acc.u_acc.u_mono.acc) !== 1'bx)
                first_acc_known_again = edge_cycle-release_cycle;
            if (snd_was_x && first_snd_known_again < 0 && (^dut.gen_2203_acc.u_acc.u_mono.snd) !== 1'bx)
                first_snd_known_again = edge_cycle-release_cycle;
            if ((^dut.gen_2203_acc.u_acc.u_mono.acc) === 1'bx)
                acc_was_x = 1'b1;
            if ((^dut.gen_2203_acc.u_acc.u_mono.snd) === 1'bx)
                snd_was_x = 1'b1;
        end
    end

    initial begin
        if (RESET_MODE == 5)
            repeat (96) @(posedge clk);
        else if (RESET_MODE == 4)
            repeat (25) @(posedge clk);
        else
            repeat (24) @(posedge clk);

        if ((RESET_MODE >= 1 && RESET_MODE <= 3) || RESET_MODE >= 6) begin
            run_cen = 1'b1;
            if (RESET_MODE == 1) begin
                wait (reset_chip_cen >= 1);
                @(negedge clk);
                run_cen = 1'b0;
                repeat (4) @(posedge clk);
            end else if (RESET_MODE == 2) begin
                wait (reset_fm_en >= 1);
                @(negedge clk);
                run_cen = 1'b0;
                repeat (4) @(posedge clk);
            end else if (RESET_MODE == 3) begin
                wait (reset_fm_en >= 12);
                @(negedge clk);
                run_cen = 1'b0;
                repeat (4) @(posedge clk);
            end else begin
                wait (reset_fm_en >= (RESET_MODE-4)*12);
                @(negedge clk);
                run_cen = 1'b0;
                repeat (4) @(posedge clk);
            end
        end

        @(negedge clk);
        rst = 1'b0;
        released = 1'b1;
        release_cycle = sys_cycle;
        run_cen = 1'b1;
        repeat (2600) @(posedge clk);
        #2;
        $display("SWEEP mode=%0d release_abs=%0d reset_chip_cen=%0d reset_fm_en=%0d first_op_x=%0d first_acc_x=%0d first_snd_x=%0d first_public_x=%0d acc_known_again=%0d snd_known_again=%0d first_zero=%0d first_sum=%0d first_op_known_update=%0d final_op=%h final_acc=%h final_snd=%h final_public=%h",
                 RESET_MODE, release_cycle, reset_chip_cen, reset_fm_en,
                 first_op_x, first_acc_x, first_snd_x, first_public_x,
                 first_acc_known_again, first_snd_known_again,
                 first_zero, first_sum, first_op_known_update,
                 dut.op_result_hd, dut.gen_2203_acc.u_acc.u_mono.acc,
                 dut.gen_2203_acc.u_acc.u_mono.snd, fm_l);
        if (first_op_x != -1 || first_acc_x != -1 ||
            first_snd_x != -1 || first_public_x != -1)
            $fatal(1, "YM2203 reset/CEN sweep detected X/Z");
        if ((^{dut.op_result_hd,dut.gen_2203_acc.u_acc.u_mono.acc,
               dut.gen_2203_acc.u_acc.u_mono.snd,fm_l,fm_r}) === 1'bx)
            $fatal(1, "YM2203 reset/CEN sweep ended unknown");
        if (fm_l !== fm_r)
            $fatal(1, "YM2203 reset/CEN sweep mono mismatch");
        $display("PASS_SWEEP mode=%0d", RESET_MODE);
        $finish;
    end
endmodule
