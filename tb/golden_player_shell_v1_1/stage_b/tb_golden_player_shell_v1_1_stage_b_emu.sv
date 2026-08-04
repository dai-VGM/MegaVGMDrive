`timescale 1ns/1ps

module tb_golden_player_shell_v1_1_stage_b_emu;
    logic clk = 1'b0;
    logic reset = 1'b1;
    always #25 clk = ~clk; // PLL stub makes clk_sys 20 MHz

    tri [48:0] hps_bus;
    wire [15:0] audio_l;
    wire [15:0] audio_r;
    wire audio_s;
    wire [1:0] audio_mix;
    integer cycles = 0;
    integer failures = 0;
    integer gate_rises = 0;
    logic gate_d = 1'b0;

    emu dut (
        .CLK_50M(clk), .RESET(reset), .HPS_BUS(hps_bus),
        .HDMI_WIDTH(12'd0), .HDMI_HEIGHT(12'd0),
`ifdef MISTER_FB
        .FB_VBL(1'b0), .FB_LL(1'b0),
`endif
        .CLK_AUDIO(clk), .AUDIO_L(audio_l), .AUDIO_R(audio_r),
        .AUDIO_S(audio_s), .AUDIO_MIX(audio_mix),
        .SD_MISO(1'b0), .SD_CD(1'b0),
        .DDRAM_BUSY(1'b0), .DDRAM_DOUT(64'd0),
        .DDRAM_DOUT_READY(1'b0), .UART_CTS(1'b0),
        .UART_RXD(1'b0), .UART_DSR(1'b0), .USER_IN(7'd0),
        .OSD_STATUS(1'b0)
    );

    always @(posedge clk) begin
        #1;
        if (!reset) begin
            cycles = cycles + 1;
            if (!gate_d && dut.audio_gate_open)
                gate_rises = gate_rises + 1;
            gate_d = dut.audio_gate_open;
            if ($isunknown(audio_l) || $isunknown(audio_r) ||
                $isunknown(dut.audio_sample_valid) ||
                $isunknown(dut.audio_gate_open) ||
                $isunknown(dut.audio_muted))
                failures = failures + 1;
            if (audio_l != 0 || audio_r != 0 || dut.audio_gate_open ||
                !dut.audio_muted || dut.audio_sample_valid)
                failures = failures + 1;
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        reset = 1'b0;
        repeat (17_000_000) @(posedge clk);
        if (dut.vgm_reset_hold_active)
            failures = failures + 1;
        if (gate_rises != 0)
            failures = failures + 1;
        if (failures == 0) begin
            $display("V1_1_STAGE_B_FINAL_EMU_AUDIO_RESULT PASS cycles=%0d gate_rises=%0d",
                     cycles, gate_rises);
            $finish;
        end else begin
            $fatal(1, "V1_1_STAGE_B_FINAL_EMU_AUDIO_RESULT FAIL failures=%0d",
                   failures);
        end
    end
endmodule
