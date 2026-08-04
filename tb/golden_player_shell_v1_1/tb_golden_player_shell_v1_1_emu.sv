`timescale 1ns/1ps

module tb_golden_player_shell_v1_1_emu;
    logic clk = 1'b0;
    logic reset = 1'b1;
    always #25 clk = ~clk; // pll stub makes this the real 20 MHz clk_sys

    tri [48:0] hps_bus;
    wire [15:0] audio_l;
    wire [15:0] audio_r;
    wire audio_s;
    wire [1:0] audio_mix;
    integer failures = 0;
    integer cycles = 0;
    integer nonzero_cycles = 0;
    integer peak = 0;
    integer signed_value;

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
            if ($isunknown({audio_l, audio_r, audio_s, audio_mix}))
                failures = failures + 1;
            if (audio_l !== audio_r)
                failures = failures + 1;
            signed_value = $signed(audio_l);
            if (signed_value != 0) begin
                nonzero_cycles = nonzero_cycles + 1;
                if (signed_value < 0) signed_value = -signed_value;
                if (signed_value > peak) peak = signed_value;
            end
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        reset = 1'b0;
`ifdef V1_1_AUDIO_LAB_TEST
        while (nonzero_cycles == 0 && cycles < 65_000_000) @(posedge clk);
        if (nonzero_cycles == 0) failures = failures + 1;
        if (peak != 2048) failures = failures + 1;
        while (dut.audio_gate_open && cycles < 90_000_000) @(posedge clk);
        repeat (20) @(posedge clk);
        if (dut.audio_gate_open || !dut.audio_muted || audio_l != 0 || audio_r != 0)
            failures = failures + 1;
`else
        repeat (200000) @(posedge clk);
        if (nonzero_cycles != 0 || dut.audio_gate_open || !dut.audio_muted)
            failures = failures + 1;
`endif
        if (failures == 0) begin
            $display("GOLDEN_SHELL_V1_1_EMU_AUDIO_RESULT PASS cycles=%0d nonzero=%0d peak=%0d",
                     cycles, nonzero_cycles, peak);
            $finish;
        end else begin
            $fatal(1, "GOLDEN_SHELL_V1_1_EMU_AUDIO_RESULT FAIL failures=%0d", failures);
        end
    end
endmodule
