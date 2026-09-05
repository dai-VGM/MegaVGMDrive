`timescale 1ns/1ps

module tb_megavgm_mode5_stop_diagnostic;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic reset;
    logic [31:0] session_id;
    logic playback_started;
    logic player_busy;
    logic player_done;
    logic [31:0] progress_count;
    logic raw_audio_sample_valid;
    logic handoff_audio_valid;
    logic audio_runtime_open;
    logic [8:0] audio_runtime_gain;
    logic signed [15:0] raw_audio_l;
    logic signed [15:0] raw_audio_r;
    logic signed [15:0] output_audio_l;
    logic signed [15:0] output_audio_r;
    logic load_active;
    logic ioctl_download;
    logic ioctl_wait;
    logic player_session_reset;
    logic sound_core_reset;
    logic ended_pulse;
    logic [31:0] ended_count;
    logic load_begin_pulse;
    logic [31:0] load_begin_count;
    logic session_start_pulse;
    logic [31:0] session_start_count;
    logic loop_boundary_pulse;
    logic loop_length_valid;
    logic [31:0] loop_length;
    logic loop_limit_armed;
    logic loop_limit_active;
    logic fade_active;
    logic [2:0] transition_reason;
    logic fatal_live;
    logic [7:0] fatal_code;
    wire [383:0] snapshot_bus;

    megavgm_mode5_stop_diagnostic #(
        .PLAY_WINDOW_CYCLES(32'd8),
        .HANDOFF_TIMEOUT_CYCLES(32'd12),
        .LOOP_TIMEOUT_CYCLES(32'd20),
        .RAW_MISSING_WINDOWS(3'd2)
    ) dut (.*);

    task automatic defaults;
        begin
            session_id = 32'd1;
            playback_started = 1'b0;
            player_busy = 1'b0;
            player_done = 1'b0;
            progress_count = 32'd0;
            raw_audio_sample_valid = 1'b0;
            handoff_audio_valid = 1'b1;
            audio_runtime_open = 1'b1;
            audio_runtime_gain = 9'd256;
            raw_audio_l = 16'sd0;
            raw_audio_r = 16'sd0;
            output_audio_l = 16'sd0;
            output_audio_r = 16'sd0;
            load_active = 1'b0;
            ioctl_download = 1'b0;
            ioctl_wait = 1'b0;
            player_session_reset = 1'b0;
            sound_core_reset = 1'b0;
            ended_pulse = 1'b0;
            ended_count = 32'd0;
            load_begin_pulse = 1'b0;
            load_begin_count = 32'd0;
            session_start_pulse = 1'b0;
            session_start_count = 32'd0;
            loop_boundary_pulse = 1'b0;
            loop_length_valid = 1'b0;
            loop_length = 32'd0;
            loop_limit_armed = 1'b0;
            loop_limit_active = 1'b0;
            fade_active = 1'b0;
            transition_reason = 3'd0;
            fatal_live = 1'b0;
            fatal_code = 8'd0;
        end
    endtask

    task automatic reset_dut;
        begin
            defaults();
            reset = 1'b1;
            repeat (2) @(posedge clk);
            reset = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic expect_class(
        input logic [2:0] expected,
        input string label
    );
        begin
            if (!snapshot_bus[329] || snapshot_bus[2:0] != expected) begin
                $display("FAIL %s valid=%0b class=%0d session=%0d progress=%0d",
                         label, snapshot_bus[329], snapshot_bus[2:0],
                         snapshot_bus[34:3], snapshot_bus[68:37]);
                $fatal(1);
            end
        end
    endtask

    initial begin
        reset = 1'b1;
        defaults();

        // Musical silence is not a failure: transport advances and regular
        // sample-valid events arrive even though raw/output samples are zero.
        reset_dut();
        playback_started = 1'b1;
        player_busy = 1'b1;
        session_start_count = 32'd1;
        repeat (40) begin
            @(negedge clk);
            progress_count = progress_count + 32'd1;
            raw_audio_sample_valid = ~raw_audio_sample_valid;
        end
        @(posedge clk);
        if (snapshot_bus[329]) $fatal(1, "normal silence false trigger");

        // A: parser and mixer-valid advance, but the handoff/output gate stays
        // closed for a complete observation window.
        reset_dut();
        session_id = 32'd2;
        playback_started = 1'b1;
        player_busy = 1'b1;
        session_start_count = 32'd1;
        handoff_audio_valid = 1'b0;
        audio_runtime_open = 1'b0;
        repeat (10) begin
            @(negedge clk);
            progress_count = progress_count + 32'd1;
            raw_audio_sample_valid = 1'b1;
            raw_audio_l = 16'sd123;
        end
        @(posedge clk);
        expect_class(3'd1, "AUDIO_ONLY_STOP");
        fatal_live = 1'b1;
        fatal_code = 8'hee;
        repeat (3) @(posedge clk);
        expect_class(3'd1, "first snapshot remains sticky");

        // B: busy remains asserted but the authoritative consumed-wait count
        // does not change for a complete window.
        reset_dut();
        session_id = 32'd3;
        playback_started = 1'b1;
        player_busy = 1'b1;
        session_start_count = 32'd1;
        raw_audio_sample_valid = 1'b1;
        repeat (10) @(posedge clk);
        expect_class(3'd2, "PLAYER_STOP busy/no progress");

        // B also covers a started session which loses busy without DONE.
        reset_dut();
        session_id = 32'd4;
        playback_started = 1'b1;
        session_start_count = 32'd1;
        repeat (10) @(posedge clk);
        expect_class(3'd2, "PLAYER_STOP missing busy");

        // C: an accepted load remains ahead of session start after download.
        reset_dut();
        session_id = 32'd5;
        load_begin_count = 32'd1;
        session_start_count = 32'd0;
        repeat (14) @(posedge clk);
        expect_class(3'd3, "LOAD_HANDOFF_STOP");

        // D: loop-limit fade ownership is live but wait/gain/count state does
        // not advance for one play window (shorter than absolute timeout).
        reset_dut();
        session_id = 32'd6;
        playback_started = 1'b1;
        player_busy = 1'b1;
        loop_limit_armed = 1'b1;
        loop_limit_active = 1'b1;
        fade_active = 1'b1;
        transition_reason = 3'd4;
        repeat (10) @(posedge clk);
        expect_class(3'd4, "LOOP_LIMIT_TRANSITION_STOP");

        // E: live fatal/reject wins immediately and records its code.
        reset_dut();
        session_id = 32'd7;
        fatal_code = 8'h0d;
        fatal_live = 1'b1;
        @(posedge clk);
        #1;
        expect_class(3'd5, "FATAL_REJECT");
        if (snapshot_bus[325:318] != 8'h0d)
            $fatal(1, "fatal code not captured");

        // F: transport advances, but no authoritative mixer-valid event is
        // seen for two whole windows. This is not mislabeled as class A.
        reset_dut();
        session_id = 32'd8;
        playback_started = 1'b1;
        player_busy = 1'b1;
        session_start_count = 32'd1;
        repeat (20) begin
            @(negedge clk);
            progress_count = progress_count + 32'd1;
        end
        @(posedge clk);
        expect_class(3'd6, "OTHER missing raw valid");

        // Core reset is the only sticky clear condition.
        reset = 1'b1;
        @(posedge clk);
        #1;
        if (snapshot_bus[329] || snapshot_bus[2:0] != 3'd0)
            $fatal(1, "core reset did not clear sticky snapshot");

        $display("PASS tb_megavgm_mode5_stop_diagnostic");
        $finish;
    end
endmodule
