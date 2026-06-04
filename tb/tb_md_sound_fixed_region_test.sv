`timescale 1ns/1ps

module tb_md_sound_fixed_region_test;

    localparam int AUDIO_DUMP_SAMPLE_COUNT = 5000;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;

    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire               audio_sample_valid;

    wire        player_busy;
    wire        player_done;
    wire  [9:0] player_pc_debug;
    wire  [7:0] player_last_cmd_debug;

    integer audio_file = 0;
    integer audio_dump_count = 0;
    integer audio_sample_valid_edges = 0;
    integer watchdog_clk_count = 0;
    bit     audio_sample_valid_prev = 1'b0;

    md_sound_fixed_region_test dut (
        .clk                   (clk),
        .reset                 (reset),
        .start                 (start),
        .audio_l               (audio_l),
        .audio_r               (audio_r),
        .audio_sample_valid    (audio_sample_valid),
        .player_busy           (player_busy),
        .player_done           (player_done),
        .player_pc_debug       (player_pc_debug),
        .player_last_cmd_debug (player_last_cmd_debug)
    );

    // Simple simulation clock. The exact frequency is not important for this
    // smoke test; md_sound_module derives its internal enables from this clock.
    always #5 clk = ~clk;

    initial begin
        audio_file = $fopen("/tmp/md_sound_fixed_region_test_5k.txt", "w");
        if (audio_file == 0) begin
            $display("ERROR: failed to open /tmp/md_sound_fixed_region_test_5k.txt");
            $finish;
        end

        repeat (64) @(posedge clk);
        reset <= 1'b0;

        repeat (64) @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        $display("FIXED_REGION_TEST_START samples=%0d", AUDIO_DUMP_SAMPLE_COUNT);

        while (audio_dump_count < AUDIO_DUMP_SAMPLE_COUNT) begin
            @(posedge clk);
            watchdog_clk_count++;

            if (audio_sample_valid && !audio_sample_valid_prev) begin
                $fdisplay(audio_file, "%0d %0d", audio_l, audio_r);
                audio_dump_count++;
                audio_sample_valid_edges++;
                watchdog_clk_count = 0;
            end
            audio_sample_valid_prev = audio_sample_valid;

            if (watchdog_clk_count >= 1000000) begin
                $display("FIXED_REGION_WATCHDOG_TIMEOUT dump_count=%0d edges=%0d pc=%0d last_cmd=%02h busy=%0b done=%0b audio_l=%0d audio_r=%0d",
                         audio_dump_count,
                         audio_sample_valid_edges,
                         player_pc_debug,
                         player_last_cmd_debug,
                         player_busy,
                         player_done,
                         audio_l,
                         audio_r);
                $fclose(audio_file);
                $finish;
            end
        end

        $fclose(audio_file);

        $display("FIXED_REGION_TEST_DONE wav_written_samples=%0d audio_sample_valid_edges=%0d pc=%0d last_cmd=%02h busy=%0b done=%0b",
                 audio_dump_count,
                 audio_sample_valid_edges,
                 player_pc_debug,
                 player_last_cmd_debug,
                 player_busy,
                 player_done);

        repeat (1024) @(posedge clk);
        $finish;
    end

endmodule
