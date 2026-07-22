`timescale 1ns/1ps

module tb_mode5_ym2203_audio_mixer;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic signed [15:0] existing_l = 16'sd0;
    logic signed [15:0] existing_r = 16'sd0;
    logic signed [15:0] pcm_l = 16'sd0;
    logic signed [15:0] pcm_r = 16'sd0;
    logic signed [15:0] md_l = 16'sd0;
    logic signed [15:0] md_r = 16'sd0;
    logic signed [15:0] raw_l = 16'sd0;
    logic signed [15:0] raw_r = 16'sd0;
    logic raw_valid = 1'b0;
    logic chip_present = 1'b0;
    logic ym_lane_enable = 1'b1;

    wire signed [15:0] held_l;
    wire signed [15:0] held_r;
    wire signed [15:0] selected_l;
    wire signed [15:0] selected_r;
    wire signed [17:0] sum_l;
    wire signed [17:0] sum_r;
    wire clipped_l;
    wire clipped_r;
    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;

    integer checks = 0;

    always #5 clk = ~clk;

    mode5_ym2203_audio_mixer dut (
        .clk                     (clk),
        .reset                   (reset),
        .existing_nonpcm_l       (existing_l),
        .existing_nonpcm_r       (existing_r),
        .segapcm_l               (pcm_l),
        .segapcm_r               (pcm_r),
        .md_l                    (md_l),
        .md_r                    (md_r),
        .ym2203_raw_l            (raw_l),
        .ym2203_raw_r            (raw_r),
        .ym2203_raw_sample_valid (raw_valid),
        .ym2203_chip_present     (chip_present),
        .ym2203_lane_enable      (ym_lane_enable),
        .ym2203_held_l           (held_l),
        .ym2203_held_r           (held_r),
        .ym2203_selected_l       (selected_l),
        .ym2203_selected_r       (selected_r),
        .mix_sum_l               (sum_l),
        .mix_sum_r               (sum_r),
        .mix_clipped_l           (clipped_l),
        .mix_clipped_r           (clipped_r),
        .audio_l                 (audio_l),
        .audio_r                 (audio_r)
    );

    task automatic fail_now(input string reason);
        begin
            $display("FAIL %s held=%0d/%0d selected=%0d/%0d sum=%0d/%0d audio=%0d/%0d clip=%0b/%0b",
                     reason, held_l, held_r, selected_l, selected_r,
                     sum_l, sum_r, audio_l, audio_r, clipped_l, clipped_r);
            $fatal(1);
        end
    endtask

    task automatic expect_mix(
        input string label,
        input logic signed [17:0] expected_sum_l,
        input logic signed [17:0] expected_sum_r,
        input logic signed [15:0] expected_l,
        input logic signed [15:0] expected_r,
        input logic expected_clip_l,
        input logic expected_clip_r
    );
        begin
            #1;
            if ((^{held_l, held_r, selected_l, selected_r, sum_l, sum_r,
                   clipped_l, clipped_r, audio_l, audio_r}) === 1'bx)
                fail_now({label, " X/Z"});
            if ($signed(sum_l) !== expected_sum_l ||
                $signed(sum_r) !== expected_sum_r ||
                audio_l !== expected_l || audio_r !== expected_r ||
                clipped_l !== expected_clip_l ||
                clipped_r !== expected_clip_r)
                fail_now(label);
            checks = checks + 1;
        end
    endtask

    task automatic push_ym_sample(
        input logic signed [15:0] sample_l,
        input logic signed [15:0] sample_r
    );
        begin
            @(negedge clk);
            raw_l = sample_l;
            raw_r = sample_r;
            raw_valid = 1'b1;
            @(posedge clk);
            #1;
            raw_valid = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        #1;
        if (held_l !== 16'sd0 || held_r !== 16'sd0)
            fail_now("reset did not clear held sample");
        @(negedge clk);
        reset = 1'b0;

        // Existing-source-only must be unchanged while YM2203 is absent.
        existing_l = 16'sd1000;
        existing_r = -16'sd1000;
        pcm_l = 16'sd500;
        pcm_r = -16'sd500;
        expect_mix("existing only", 1500, -1500, 16'sd1500,
                   -16'sd1500, 1'b0, 1'b0);

        // The production MD lane joins at unity gain without changing the
        // established final accumulator width or saturation point.
        md_l = 16'sd250;
        md_r = -16'sd250;
        expect_mix("MD lane", 1750, -1750, 16'sd1750,
                   -16'sd1750, 1'b0, 1'b0);
        md_l = 16'sd0;
        md_r = 16'sd0;

        // Existing selector outputs remain exact for absent YM2203 files.
        // PCM Only arrives with the non-PCM input already muted.
        existing_l = 16'sd0;
        existing_r = 16'sd0;
        pcm_l = 16'sd2222;
        pcm_r = -16'sd3333;
        ym_lane_enable = 1'b0;
        expect_mix("absent PCM only", 2222, -3333, 16'sd2222,
                   -16'sd3333, 1'b0, 1'b0);

        // FM Only arrives with the SegaPCM input already muted.
        existing_l = 16'sd4444;
        existing_r = -16'sd5555;
        pcm_l = 16'sd0;
        pcm_r = 16'sd0;
        ym_lane_enable = 1'b1;
        expect_mix("absent FM only", 4444, -5555, 16'sd4444,
                   -16'sd5555, 1'b0, 1'b0);

        // 0-clock file: no held value or raw residue reaches the mix.
        existing_l = 16'sd1000;
        existing_r = -16'sd1000;
        pcm_l = 16'sd500;
        pcm_r = -16'sd500;
        chip_present = 1'b0;
        raw_l = 16'sd7000;
        raw_r = -16'sd8000;
        repeat (2) @(posedge clk);
        expect_mix("absent gate", 1500, -1500, 16'sd1500,
                   -16'sd1500, 1'b0, 1'b0);

        // A 0-clock file followed by a present file starts from the reset-zero
        // hold until the first real YM2203 sample strobe arrives.
        existing_l = 16'sd0;
        existing_r = 16'sd0;
        pcm_l = 16'sd0;
        pcm_r = 16'sd0;
        chip_present = 1'b1;
        expect_mix("absent to present before first sample", 0, 0, 16'sd0,
                   16'sd0, 1'b0, 1'b0);

        // The first present sample is held at full signed width and unity gain.
        push_ym_sample(16'sd1234, -16'sd2345);
        expect_mix("YM only signed", 1234, -2345, 16'sd1234,
                   -16'sd2345, 1'b0, 1'b0);

        // No sample-valid means hold, not an inserted zero or live raw value.
        raw_l = 16'sd30000;
        raw_r = 16'sd30000;
        repeat (3) @(posedge clk);
        expect_mix("sample hold", 1234, -2345, 16'sd1234,
                   -16'sd2345, 1'b0, 1'b0);

        push_ym_sample(16'sd0, 16'sd0);
        expect_mix("YM zero", 0, 0, 16'sd0, 16'sd0, 1'b0, 1'b0);

        // Normal: existing non-PCM + SegaPCM + YM2203.
        existing_l = 16'sd10000;
        existing_r = -16'sd10000;
        pcm_l = 16'sd10000;
        pcm_r = -16'sd10000;
        push_ym_sample(16'sd10000, -16'sd10000);
        expect_mix("normal same sign", 30000, -30000, 16'sd30000,
                   -16'sd30000, 1'b0, 1'b0);

        existing_l = 16'sd20000;
        existing_r = -16'sd20000;
        pcm_l = -16'sd15000;
        pcm_r = 16'sd15000;
        push_ym_sample(-16'sd3000, 16'sd3000);
        expect_mix("normal opposite sign", 2000, -2000, 16'sd2000,
                   -16'sd2000, 1'b0, 1'b0);

        existing_l = 16'sd30000;
        existing_r = -16'sd30000;
        pcm_l = 16'sd30000;
        pcm_r = -16'sd30000;
        push_ym_sample(16'sd30000, -16'sd30000);
        expect_mix("three-source saturation", 90000, -90000, 16'sh7fff,
                   16'sh8000, 1'b1, 1'b1);

        md_l = 16'sd30000;
        md_r = -16'sd30000;
        expect_mix("four-source saturation", 120000, -120000, 16'sh7fff,
                   16'sh8000, 1'b1, 1'b1);
        md_l = 16'sd0;
        md_r = 16'sd0;

        // PCM Only: the existing selector has already muted JT51; this input
        // disables the complete YM2203 FM+SSG non-PCM lane as well.
        existing_l = 16'sd0;
        existing_r = 16'sd0;
        pcm_l = 16'sd3210;
        pcm_r = -16'sd4321;
        ym_lane_enable = 1'b0;
        expect_mix("PCM only", 3210, -4321, 16'sd3210,
                   -16'sd4321, 1'b0, 1'b0);

        // FM Only: SegaPCM is already zero and JT51+YM2203 remain active.
        existing_l = 16'sd1000;
        existing_r = -16'sd1000;
        pcm_l = 16'sd0;
        pcm_r = 16'sd0;
        ym_lane_enable = 1'b1;
        push_ym_sample(16'sd2000, -16'sd3000);
        expect_mix("FM only", 3000, -4000, 16'sd3000,
                   -16'sd4000, 1'b0, 1'b0);

        // present -> absent gates an old nonzero held sample immediately.
        chip_present = 1'b0;
        expect_mix("present to absent", 1000, -1000, 16'sd1000,
                   -16'sd1000, 1'b0, 1'b0);
        if (held_l !== 16'sd2000 || held_r !== -16'sd3000)
            fail_now("absent transition reset or changed the core hold");

        $display("PASS tb_mode5_ym2203_audio_mixer checks=%0d held=%0d/%0d",
                 checks, held_l, held_r);
        $finish;
    end
endmodule
