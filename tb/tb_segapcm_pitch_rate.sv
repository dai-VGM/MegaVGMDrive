`timescale 1ns/1ps

module tb_segapcm_pitch_rate;
    localparam integer CLK_SYS_HZ = 20_000_000;
    localparam integer VGM_SEGAPCM_HZ = 4_026_987;
    localparam integer FSM_CEN_HZ = VGM_SEGAPCM_HZ * 2;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cen;
    integer cycle_count = 0;
    integer cen_count = 0;
    integer channel_updates;
    integer integer_bytes_delta80;

    always #25 clk = ~clk;

    segapcm_fractional_cen #(
        .CLK_SYS_HZ (CLK_SYS_HZ),
        .TARGET_HZ  (FSM_CEN_HZ)
    ) dut (
        .clk   (clk),
        .reset (reset),
        .cen   (cen)
    );

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // Exactly one second at the 20 MHz system-clock rate.
        for (cycle_count = 0; cycle_count < CLK_SYS_HZ;
             cycle_count = cycle_count + 1) begin
            @(posedge clk);
            #1;
            if (cen)
                cen_count = cen_count + 1;
        end

        if (cen_count < FSM_CEN_HZ - 1 || cen_count > FSM_CEN_HZ + 1) begin
            $display("FAIL cen count=%0d expected=%0d", cen_count, FSM_CEN_HZ);
            $fatal(1);
        end

        // One voice advances once per 16 states * 16 voices.
        channel_updates = cen_count / 256;
        integer_bytes_delta80 = (channel_updates * 8'h80) / 256;
        if (integer_bytes_delta80 < 15729 || integer_bytes_delta80 > 15731) begin
            $display("FAIL delta80 bytes/s=%0d updates=%0d",
                     integer_bytes_delta80, channel_updates);
            $fatal(1);
        end

        $display("PASS tb_segapcm_pitch_rate cen/s=%0d updates/s=%0d delta80_bytes/s=%0d",
                 cen_count, channel_updates, integer_bytes_delta80);
        $finish;
    end
endmodule
