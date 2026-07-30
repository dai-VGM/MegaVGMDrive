`timescale 1ns/1ps

module tb_jt10_standalone_elaboration;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cen = 1'b0;
    logic [7:0] din = 8'h00;
    logic [1:0] addr = 2'b00;
    logic cs_n = 1'b1;
    logic wr_n = 1'b1;
    logic [7:0] adpcma_data = 8'h00;
    logic [7:0] adpcmb_data = 8'h00;

    wire [7:0] dout;
    wire irq_n;
    wire [19:0] adpcma_addr;
    wire [3:0] adpcma_bank;
    wire adpcma_roe_n;
    wire [23:0] adpcmb_addr;
    wire adpcmb_roe_n;
    wire [7:0] psg_A;
    wire [7:0] psg_B;
    wire [7:0] psg_C;
    wire signed [15:0] fm_snd;
    wire [9:0] psg_snd;
    wire signed [15:0] snd_right;
    wire signed [15:0] snd_left;
    wire snd_sample;

    wire adpcma_fetch_valid =
        adpcma_roe_n === 1'b0 &&
        dut.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.decon === 1'b1;

    integer system_cycle = 0;
    integer post_reset_cen = 0;
    integer first_known_cen = -1;
    integer sample_count = 0;
    integer inactive_adpcma_x_count = 0;
    integer inactive_audio_x_count = 0;
    integer failures = 0;
    logic first_post_reset_x_reported = 1'b0;

    always #5 clk = ~clk;

    function automatic logic required_public_unknown;
        begin
            required_public_unknown =
                $isunknown(dout) ||
                $isunknown(irq_n) ||
                $isunknown(psg_A) ||
                $isunknown(psg_B) ||
                $isunknown(psg_C) ||
                $isunknown(psg_snd) ||
                $isunknown(snd_sample) ||
                (snd_sample === 1'b1 &&
                 ($isunknown(fm_snd) ||
                  $isunknown(snd_right) ||
                  $isunknown(snd_left))) ||
                (adpcma_fetch_valid &&
                 ($isunknown(adpcma_addr) ||
                  $isunknown(adpcma_bank)));
        end
    endfunction

    always @(posedge clk) begin
        system_cycle = system_cycle + 1;
        #1;
        if (!rst && cen) begin
            post_reset_cen = post_reset_cen + 1;
            if (!required_public_unknown() && first_known_cen < 0)
                first_known_cen = post_reset_cen;
            if (snd_sample === 1'b1)
                sample_count = sample_count + 1;
            if (!adpcma_fetch_valid &&
                ($isunknown(adpcma_addr) ||
                 $isunknown(adpcma_bank)))
                inactive_adpcma_x_count = inactive_adpcma_x_count + 1;
            if (snd_sample === 1'b0 &&
                ($isunknown(fm_snd) ||
                 $isunknown(snd_right) ||
                 $isunknown(snd_left)))
                inactive_audio_x_count = inactive_audio_x_count + 1;
            if (required_public_unknown() &&
                !first_post_reset_x_reported) begin
                first_post_reset_x_reported = 1'b1;
                report_first_unknown("POST_RESET");
            end
        end
    end

    task automatic report_first_unknown(input string phase);
        begin
            if ($isunknown(dout))
                $display("FIRST_X phase=%s cycle=%0d signal=dout module=jt12_dout/mmr",
                         phase, system_cycle);
            else if ($isunknown(irq_n))
                $display("FIRST_X phase=%s cycle=%0d signal=irq_n module=jt12_timers",
                         phase, system_cycle);
            else if (adpcma_fetch_valid &&
                     ($isunknown(adpcma_addr) ||
                      $isunknown(adpcma_bank)))
                $display("FIRST_X phase=%s cycle=%0d signal=valid_adpcma_rom module=jt10_adpcm_drvA",
                         phase, system_cycle);
            else if ($isunknown(psg_A) ||
                     $isunknown(psg_B) ||
                     $isunknown(psg_C) ||
                     $isunknown(psg_snd))
                $display("FIRST_X phase=%s cycle=%0d signal=psg module=jt49",
                         phase, system_cycle);
            else if (snd_sample === 1'b1 && $isunknown(fm_snd))
                $display("FIRST_X phase=%s cycle=%0d signal=fm_snd module=jt10_acc",
                         phase, system_cycle);
            else if (snd_sample === 1'b1 &&
                     ($isunknown(snd_left) || $isunknown(snd_right)))
                $display("FIRST_X phase=%s cycle=%0d signal=snd_l_r module=jt12_top_mix",
                         phase, system_cycle);
            else if ($isunknown(snd_sample))
                $display("FIRST_X phase=%s cycle=%0d signal=snd_sample module=jt12_mmr/div",
                         phase, system_cycle);
        end
    endtask

    task automatic snapshot(input string phase);
        begin
            $display(
                "SNAPSHOT phase=%s system_cycle=%0d chip_cen=%0d known=%0d dout=%02x irq_n=%b romA=%05x/%x/%b romB=%06x/%b snd_l=%04x snd_r=%04x sample=%b",
                phase, system_cycle, post_reset_cen,
                !required_public_unknown(),
                dout, irq_n, adpcma_addr, adpcma_bank, adpcma_roe_n,
                adpcmb_addr, adpcmb_roe_n, snd_left, snd_right, snd_sample
            );
            if (required_public_unknown())
                report_first_unknown(phase);
        end
    endtask

    task automatic require_known(input string phase);
        begin
            snapshot(phase);
            if (required_public_unknown()) begin
                failures = failures + 1;
                $display("FAIL phase=%s public output contains X/Z", phase);
            end
        end
    endtask

    jt10 dut (
        .rst(rst), .clk(clk), .cen(cen),
        .din(din), .addr(addr), .cs_n(cs_n), .wr_n(wr_n),
        .dout(dout), .irq_n(irq_n),
        .adpcma_addr(adpcma_addr), .adpcma_bank(adpcma_bank),
        .adpcma_roe_n(adpcma_roe_n), .adpcma_data(adpcma_data),
        .adpcmb_addr(adpcmb_addr), .adpcmb_roe_n(adpcmb_roe_n),
        .adpcmb_data(adpcmb_data),
        .psg_A(psg_A), .psg_B(psg_B), .psg_C(psg_C),
        .fm_snd(fm_snd), .psg_snd(psg_snd),
        .snd_right(snd_right), .snd_left(snd_left),
        .snd_sample(snd_sample)
    );

    initial begin
        // Inputs stay known and the CPU bus stays idle throughout Phase 0.
        repeat (32) @(posedge clk);
        #1;
        snapshot("RESET_NO_CEN");

        cen = 1'b1;
        repeat (64) @(posedge clk);
        #1;
        snapshot("RESET_WITH_CEN");

        @(negedge clk);
        rst = 1'b0;

        repeat (256) @(posedge clk);
        #1;
        require_known("POST_RESET_256_CEN");

        repeat (19744) @(posedge clk);
        #1;
        require_known("POST_RESET_20000_SYS");

        if ($isunknown({din, addr, cs_n, wr_n, adpcma_data, adpcmb_data})) begin
            failures = failures + 1;
            $display("FAIL known-input contract");
        end
        if (sample_count == 0) begin
            failures = failures + 1;
            $display("FAIL snd_sample never asserted");
        end

        $display(
            "RESULT first_known_cen=%0d post_reset_cen=%0d samples=%0d first_post_reset_x=%0d inactive_adpcma_x=%0d inactive_audio_x=%0d busy=%b",
            first_known_cen, post_reset_cen, sample_count,
            first_post_reset_x_reported, inactive_adpcma_x_count,
            inactive_audio_x_count, dout[7]
        );

        if (failures != 0)
            $fatal(1, "JT10 Phase 0 reset convergence failed (%0d)", failures);

        $display("PASS tb_jt10_standalone_elaboration");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "timeout");
    end
endmodule
