`timescale 1ns/1ps

module tb_mode5_audio_session_lane_gate;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic session_begin = 1'b0;
    logic command_valid = 1'b0;
    logic setup_complete = 1'b0;
    logic sample_valid = 1'b0;
    logic signed [15:0] raw_audio_l = 16'sd0;
    logic signed [15:0] raw_audio_r = 16'sd0;
    wire session_ready;
    wire signed [15:0] session_audio_l;
    wire signed [15:0] session_audio_r;

    always #5 clk = ~clk;

    mode5_audio_session_lane_gate dut (
        .clk(clk),
        .reset(reset),
        .session_begin(session_begin),
        .command_valid(command_valid),
        .setup_complete(setup_complete),
        .sample_valid(sample_valid),
        .raw_audio_l(raw_audio_l),
        .raw_audio_r(raw_audio_r),
        .session_ready(session_ready),
        .session_audio_l(session_audio_l),
        .session_audio_r(session_audio_r)
    );

    task automatic expect_muted(input string label);
        #1;
        if (session_ready || session_audio_l !== 16'sd0 ||
            session_audio_r !== 16'sd0) begin
            $display("FAIL %s ready=%0b l=%0d r=%0d", label,
                     session_ready, session_audio_l, session_audio_r);
            $fatal(1);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset <= 1'b0;

        // A held previous-session sample is never current ownership.
        raw_audio_l <= 16'sd16000;
        raw_audio_r <= -16'sd16000;
        sample_valid <= 1'b1;
        @(posedge clk);
        sample_valid <= 1'b0;
        expect_muted("old sample without current command");

        // A current command and even a same-lane sample are insufficient
        // until the parser completes the timestamp-zero setup burst.
        command_valid <= 1'b1;
        sample_valid <= 1'b1;
        @(posedge clk);
        command_valid <= 1'b0;
        sample_valid <= 1'b0;
        expect_muted("sample before first positive wait");

        setup_complete <= 1'b1;
        @(posedge clk);
        expect_muted("setup completion is not itself an audio sample");

        // The first same-lane sample after setup becomes visible immediately;
        // no arbitrary delay and no valid sample are discarded.
        raw_audio_l <= 16'sd2345;
        raw_audio_r <= -16'sd3456;
        sample_valid <= 1'b1;
        @(posedge clk);
        #1;
        if (!session_ready || session_audio_l !== 16'sd2345 ||
            session_audio_r !== -16'sd3456) begin
            $display("FAIL current-session first sample ready=%0b l=%0d r=%0d",
                     session_ready, session_audio_l, session_audio_r);
            $fatal(1);
        end
        sample_valid <= 1'b0;

        // Every new file revokes the old lane ownership synchronously.
        session_begin <= 1'b1;
        @(posedge clk);
        session_begin <= 1'b0;
        expect_muted("next session clears ownership");

        $display("PASS tb_mode5_audio_session_lane_gate");
        $finish;
    end
endmodule
