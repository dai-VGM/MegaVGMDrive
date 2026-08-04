`timescale 1ns/1ps

module tb_golden_player_shell_v1_1_shim;
    localparam int TEST_CLK_HZ = 200_000;
    logic clk = 1'b0;
    logic reset_n = 1'b0;
    always #5 clk = ~clk;

    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire audio_sample_valid;
    wire audio_gate_open;
    wire audio_muted;
    wire ddram_rd;
    wire ddram_we;
    integer failures = 0;
    integer cycles = 0;
    integer nonzero_cycles = 0;
    integer valid_pulses = 0;
    integer gate_rises = 0;
    logic gate_d = 1'b0;

    mister_vgm_md_top #(
        .VGM_LOAD_ADDR_WIDTH(23),
        .MODE5_VGM_BACKEND(1),
        .CLK_SYS_HZ(TEST_CLK_HZ)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .audio_l(audio_l), .audio_r(audio_r),
        .audio_sample_valid(audio_sample_valid),
        .audio_lpf_mode(2'd0), .audio_gain_boost(1'b0),
        .audio_psg_level(2'd0),
        .audio_gate_open(audio_gate_open), .audio_muted(audio_muted),
        .ioctl_download(1'b0), .ioctl_wr(1'b0), .ioctl_addr(27'd0),
        .ioctl_dout(8'd0), .ioctl_index(16'd0),
        .ddram_busy(1'b0), .ddram_dout(64'd0),
        .ddram_dout_ready(1'b0), .ddram_rd(ddram_rd), .ddram_we(ddram_we)
    );

    always @(posedge clk) begin
        #1;
        if (audio_gate_open && !gate_d) gate_rises = gate_rises + 1;
        gate_d = audio_gate_open;
        if (reset_n) begin
            cycles = cycles + 1;
            if ($isunknown({audio_l, audio_r, audio_sample_valid,
                            audio_gate_open, audio_muted, ddram_rd, ddram_we}))
                failures = failures + 1;
            if (audio_gate_open == audio_muted)
                failures = failures + 1;
            if (audio_l !== audio_r)
                failures = failures + 1;
            if (audio_l != 0) nonzero_cycles = nonzero_cycles + 1;
            if (audio_sample_valid) valid_pulses = valid_pulses + 1;
            if (ddram_rd || ddram_we) failures = failures + 1;
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        reset_n = 1'b1;
`ifdef V1_1_AUDIO_LAB_TEST
        while (gate_rises == 0 && cycles < 500_000) @(posedge clk);
        while (audio_gate_open && cycles < 1_200_000) @(posedge clk);
        repeat (20) @(posedge clk);
        if (gate_rises != 1 || nonzero_cycles == 0 || valid_pulses == 0)
            failures = failures + 1;
        if (audio_gate_open || !audio_muted || audio_l != 0 || audio_r != 0)
            failures = failures + 1;
`else
        repeat (120000) @(posedge clk);
        if (gate_rises != 0 || nonzero_cycles != 0 || valid_pulses != 0 ||
            audio_gate_open || !audio_muted)
            failures = failures + 1;
`endif
        if (failures == 0) begin
            $display("GOLDEN_SHELL_V1_1_SHIM_RESULT PASS gate_rises=%0d nonzero_cycles=%0d valid=%0d",
                     gate_rises, nonzero_cycles, valid_pulses);
            $finish;
        end
        $fatal(1, "GOLDEN_SHELL_V1_1_SHIM_RESULT FAIL failures=%0d", failures);
    end
endmodule
