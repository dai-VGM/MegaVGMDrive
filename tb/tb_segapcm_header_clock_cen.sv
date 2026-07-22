`timescale 1ns/1ps

module tb_segapcm_header_clock_cen;
    localparam integer CLK_SYS_HZ = 20_000_000;
    localparam integer STAGE_CLOCK_HZ = 4_026_987;
    localparam integer FOUR_MHZ = 4_000_000;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic session_reset = 1'b0;
    logic [31:0] header_clock_raw = 32'd0;
    logic header_clock_commit = 1'b0;
    wire cen;
    wire [31:0] raw_debug;
    wire [31:0] effective_debug;
    wire [31:0] fsm_enable_debug;
    logic stage_reference_reset = 1'b1;
    wire stage_reference_cen;
    integer i;
    integer cen_count;
    integer channel_updates;
    longint expected_updates_5s;

    always #1 clk = ~clk;

    segapcm_header_clock_cen #(
        .CLK_SYS_HZ(CLK_SYS_HZ),
        .FALLBACK_FSM_CEN_HZ(STAGE_CLOCK_HZ * 2)
    ) dut (
        .clk(clk),
        .reset(reset),
        .session_reset(session_reset),
        .header_clock_raw(header_clock_raw),
        .header_clock_commit(header_clock_commit),
        .cen(cen),
        .header_clock_raw_debug(raw_debug),
        .effective_header_clock_hz_debug(effective_debug),
        .fsm_enable_hz_debug(fsm_enable_debug)
    );

    segapcm_fractional_cen #(
        .CLK_SYS_HZ(CLK_SYS_HZ),
        .TARGET_HZ(STAGE_CLOCK_HZ * 2)
    ) stage_reference (
        .clk(clk), .reset(stage_reference_reset), .cen(stage_reference_cen)
    );

    task commit_clock(input logic [31:0] value);
        begin
            @(negedge clk);
            header_clock_raw = value;
            header_clock_commit = 1'b1;
            @(posedge clk);
            @(negedge clk);
            header_clock_commit = 1'b0;
            if (dut.accum !== 32'd0)
                $fatal(1, "accumulator did not reset on clock commit: %08h",
                       dut.accum);
        end
    endtask

    task pulse_session_reset;
        begin
            @(negedge clk);
            session_reset = 1'b1;
            @(posedge clk);
            @(negedge clk);
            session_reset = 1'b0;
            if (dut.accum !== 32'd0 || raw_debug !== 32'd0)
                $fatal(1, "session reset left stale clock/phase raw=%0d accum=%0d",
                       raw_debug, dut.accum);
        end
    endtask

    task count_cycles(input integer cycles, input integer expected_cen);
        begin
            cen_count = 0;
            for (i = 0; i < cycles; i = i + 1) begin
                @(negedge clk);
                if (cen)
                    cen_count = cen_count + 1;
            end
            if (cen_count != expected_cen)
                $fatal(1, "CEN count=%0d expected=%0d", cen_count, expected_cen);
        end
    endtask

    task compare_stage_cadence(input integer cycles);
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(negedge clk);
                if (cen !== stage_reference_cen)
                    $fatal(1, "Stage cadence differs at cycle %0d dynamic=%0b fixed=%0b",
                           i, cen, stage_reference_cen);
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        if (effective_debug !== STAGE_CLOCK_HZ ||
            fsm_enable_debug !== STAGE_CLOCK_HZ * 2)
            $fatal(1, "fallback clock effective=%0d fsm=%0d",
                   effective_debug, fsm_enable_debug);

        stage_reference_reset = 1'b1;
        commit_clock(STAGE_CLOCK_HZ);
        stage_reference_reset = 1'b0;
        compare_stage_cadence(100_000);
        pulse_session_reset();
        commit_clock(FOUR_MHZ);
        if (raw_debug !== FOUR_MHZ || effective_debug !== FOUR_MHZ ||
            fsm_enable_debug !== FOUR_MHZ * 2)
            $fatal(1, "4 MHz selection raw=%0d effective=%0d fsm=%0d",
                   raw_debug, effective_debug, fsm_enable_debug);
        count_cycles(20_000, 8_000);
        channel_updates = FOUR_MHZ / 128;
        expected_updates_5s = (FOUR_MHZ * 64'd5) / 128;
        if (channel_updates != 31_250 || expected_updates_5s != 156_250)
            $fatal(1, "4 MHz update rate one_s=%0d five_s=%0d",
                   channel_updates, expected_updates_5s);

        pulse_session_reset();
        commit_clock(STAGE_CLOCK_HZ);
        if (effective_debug !== STAGE_CLOCK_HZ ||
            fsm_enable_debug !== STAGE_CLOCK_HZ * 2)
            $fatal(1, "reverse reload retained old clock effective=%0d fsm=%0d",
                   effective_debug, fsm_enable_debug);
        pulse_session_reset();
        commit_clock(32'd0);
        if (raw_debug !== 32'd0 || effective_debug !== STAGE_CLOCK_HZ ||
            fsm_enable_debug !== STAGE_CLOCK_HZ * 2)
            $fatal(1, "zero-clock fallback raw=%0d effective=%0d fsm=%0d",
                   raw_debug, effective_debug, fsm_enable_debug);

        $display("PASS tb_segapcm_header_clock_cen 4MHz_cen=%0d updates/s=%0d updates/5s=%0d stage_fsm=%0d",
                 FOUR_MHZ * 2, channel_updates, expected_updates_5s,
                 STAGE_CLOCK_HZ * 2);
        $finish;
    end
endmodule
