`timescale 1ns/1ps

module tb_golden_player_shell_v1_1_audio_lab;
    localparam int TEST_CLK_HZ = 200_000;
    localparam int SAMPLE_HZ = 44_100;
    localparam int SILENCE_SAMPLES = 88_200;
    localparam int TONE_SAMPLES = 44_100;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic download_active = 1'b0;
    always #5 clk = ~clk;

    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire sample_valid;
    wire audio_enable;
    wire file_read_request;
    wire [22:0] file_read_address;
    wire pcm_a_read_request;
    wire [22:0] pcm_a_read_address;
    wire pcm_b_read_request;
    wire [22:0] pcm_b_read_address;
    wire playback_active;
    wire profile_fatal;
    wire [15:0] profile_status;
    wire [15:0] debug_page_data;
    wire [31:0] parser_start_count;
    wire [31:0] scanner_start_count;
    wire [31:0] sound_write_count;

    integer failures = 0;
    integer enable_rises = 0;
    integer x_reports = 0;
    logic enable_d = 1'b0;

    task automatic fail(input string message);
        begin
            failures = failures + 1;
            $display("V1_1_AUDIO_LAB_FAIL %s", message);
        end
    endtask

    golden_player_shell_v1_1_profile #(
        .VGM_ADDR_WIDTH(23),
        .CLK_SYS_HZ(TEST_CLK_HZ),
        .SAMPLE_HZ(SAMPLE_HZ),
        .SILENCE_SAMPLES(SILENCE_SAMPLES),
        .TONE_SAMPLES(TONE_SAMPLES),
        .TONE_HZ(1_000),
        .TONE_AMPLITUDE(16'sd2048)
    ) dut (
        .clk_sys(clk), .reset(reset),
        .download_active(download_active),
        .uploaded_physical_size(32'd0), .upload_complete(1'b0),
        .file_read_ready(1'b0), .file_read_valid(1'b0),
        .file_read_data(8'd0), .file_read_request(file_read_request),
        .file_read_address(file_read_address),
        .pcm_a_read_request(pcm_a_read_request),
        .pcm_a_read_address(pcm_a_read_address),
        .pcm_b_read_request(pcm_b_read_request),
        .pcm_b_read_address(pcm_b_read_address),
        .osd_audio_lpf_mode(2'd0), .osd_audio_gain_boost(1'b0),
        .osd_audio_psg_level(2'd0), .title_valid(1'b0),
        .title_text_byte(8'd0), .shell_sample_timing(1'b0),
        .profile_audio_l(audio_l), .profile_audio_r(audio_r),
        .profile_audio_sample_valid(sample_valid),
        .profile_audio_enable(audio_enable),
        .playback_active(playback_active), .profile_fatal(profile_fatal),
        .profile_status(profile_status), .debug_page_data(debug_page_data),
        .parser_start_count(parser_start_count),
        .scanner_start_count(scanner_start_count),
        .sound_write_count(sound_write_count)
    );

    always @(posedge clk) begin
        #1;
        if (audio_enable && !enable_d)
            enable_rises = enable_rises + 1;
        enable_d = audio_enable;
        if (!reset) begin
            if (($isunknown(audio_l) || $isunknown(audio_r) ||
                 $isunknown(sample_valid) || $isunknown(audio_enable) ||
                 $isunknown(file_read_request) || $isunknown(file_read_address) ||
                 $isunknown(pcm_a_read_request) || $isunknown(pcm_a_read_address) ||
                 $isunknown(pcm_b_read_request) || $isunknown(pcm_b_read_address) ||
                 $isunknown(playback_active) || $isunknown(profile_fatal) ||
                 $isunknown(parser_start_count) || $isunknown(scanner_start_count) ||
                 $isunknown(sound_write_count)) && x_reports == 0) begin
                $display("V1_1_AUDIO_LAB_X l=%h r=%h valid=%b enable=%b fr=%b fa=%h pa=%b paa=%h pb=%b pba=%h play=%b fatal=%b parser=%h scanner=%h writes=%h",
                    audio_l, audio_r, sample_valid, audio_enable,
                    file_read_request, file_read_address, pcm_a_read_request,
                    pcm_a_read_address, pcm_b_read_request, pcm_b_read_address,
                    playback_active, profile_fatal, parser_start_count,
                    scanner_start_count, sound_write_count);
                x_reports = x_reports + 1;
                fail("relevant X/Z");
            end
            if (file_read_request || pcm_a_read_request || pcm_b_read_request ||
                playback_active || profile_fatal || parser_start_count != 0 ||
                scanner_start_count != 0 || sound_write_count != 0)
                fail("forbidden activity");
            if (!audio_enable && (audio_l != 0 || audio_r != 0 || sample_valid))
                fail("disabled output not zero");
            if (audio_l !== audio_r)
                fail("L/R mismatch");
        end
    end

    task automatic check_sequence(input integer expected_rise_count);
        integer timeout;
        integer valid_count;
        integer sign_changes;
        integer positive_count;
        integer negative_count;
        integer peak;
        logic signed [15:0] prior;
        logic prior_valid;
        begin
            timeout = 0;
            while (!audio_enable && timeout < 500_000) begin
                @(posedge clk); #1;
                if (!audio_enable &&
                    (audio_l != 0 || audio_r != 0 || sample_valid))
                    fail("pre-tone silence violated");
                timeout = timeout + 1;
            end
            if (!audio_enable)
                fail("tone enable timeout");
            if (enable_rises != expected_rise_count)
                fail("enable did not assert exactly once per reset");

            valid_count = 0;
            sign_changes = 0;
            positive_count = 0;
            negative_count = 0;
            peak = 0;
            prior = 16'sd0;
            prior_valid = 1'b0;
            while (audio_enable && valid_count < TONE_SAMPLES + 8) begin
                @(posedge clk); #1;
                if (audio_enable && sample_valid) begin
                    valid_count = valid_count + 1;
                    if (audio_l == 16'sd2048) positive_count = positive_count + 1;
                    else if (audio_l == -16'sd2048) negative_count = negative_count + 1;
                    else fail("tone amplitude is not +/-2048");
                    if (audio_l < 0 ? -audio_l > peak : audio_l > peak)
                        peak = audio_l < 0 ? -audio_l : audio_l;
                    if (prior_valid && audio_l != prior)
                        sign_changes = sign_changes + 1;
                    prior = audio_l;
                    prior_valid = 1'b1;
                end
            end
            repeat (8) @(posedge clk);
            #1;
            if (audio_enable || audio_l != 0 || audio_r != 0 || sample_valid)
                fail("post-tone idle is not zero");
            if (valid_count < TONE_SAMPLES-2 || valid_count > TONE_SAMPLES)
                fail("tone sample duration mismatch");
            if (sign_changes < 1997 || sign_changes > 2001)
                fail("tone frequency outside 1 kHz tolerance");
            if (positive_count == 0 || negative_count == 0 || peak != 2048)
                fail("tone polarity/peak contract");
            $display("V1_1_AUDIO_LAB_SEQUENCE PASS valid=%0d sign_changes=%0d peak=%0d",
                     valid_count, sign_changes, peak);
        end
    endtask

    initial begin
        repeat (8) @(posedge clk);
        reset = 1'b0;
        check_sequence(1);

        // A VGM upload must not trigger another lab tone.
        download_active = 1'b1;
        repeat (20) @(posedge clk);
        download_active = 1'b0;
        repeat (1000) @(posedge clk);
        if (audio_enable || enable_rises != 1)
            fail("upload retriggered lab audio");

        // Software Reset explicitly rearms the same one-shot sequence.
        reset = 1'b1;
        repeat (8) @(posedge clk);
        reset = 1'b0;
        check_sequence(2);

        if (failures == 0) begin
            $display("GOLDEN_SHELL_V1_1_AUDIO_LAB_RESULT PASS enable_rises=%0d",
                     enable_rises);
            $finish;
        end
        $fatal(1, "GOLDEN_SHELL_V1_1_AUDIO_LAB_RESULT FAIL failures=%0d", failures);
    end
endmodule
