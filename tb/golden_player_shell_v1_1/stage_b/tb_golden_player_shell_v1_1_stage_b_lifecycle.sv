`timescale 1ns/1ps

module tb_golden_player_shell_v1_1_stage_b_lifecycle;
    localparam int MAX_FILE = 4096;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic download_active = 1'b0;
    logic [31:0] uploaded_physical_size = 32'd0;
    logic upload_complete = 1'b0;
    logic file_read_ready;
    logic file_read_valid = 1'b0;
    logic [7:0] file_read_data = 8'd0;
    logic file_read_request;
    logic [22:0] file_read_address;
    logic pcm_a_read_request, pcm_b_read_request;
    logic [22:0] pcm_a_read_address, pcm_b_read_address;
    logic signed [15:0] profile_audio_l, profile_audio_r;
    logic profile_audio_sample_valid, profile_audio_enable;
    logic playback_active, profile_fatal;
    logic [15:0] profile_status, debug_page_data;
    logic [31:0] parser_start_count, scanner_start_count, sound_write_count;
    logic [7:0] memory [0:MAX_FILE-1];
    logic pending;
    logic [22:0] pending_addr;
    integer response_delay, cycles, accepts, responses, failures;
    integer enable_rises;
    logic profile_audio_enable_d;
    logic inject_stale;
    logic [22:0] held_address;
    integer hold_count;
    string fixture_dir;

    always #5 clk = ~clk;
    assign file_read_ready = !pending && cycles[2:0] != 3'd2;

    golden_player_shell_v1_1_profile profile (
        .clk_sys(clk), .reset(reset), .download_active(download_active),
        .uploaded_physical_size(uploaded_physical_size),
        .upload_complete(upload_complete), .file_read_ready(file_read_ready),
        .file_read_valid(file_read_valid), .file_read_data(file_read_data),
        .file_read_request(file_read_request),
        .file_read_address(file_read_address),
        .pcm_a_read_request(pcm_a_read_request),
        .pcm_a_read_address(pcm_a_read_address),
        .pcm_b_read_request(pcm_b_read_request),
        .pcm_b_read_address(pcm_b_read_address),
        .osd_audio_lpf_mode(2'd0), .osd_audio_gain_boost(1'b0),
        .osd_audio_psg_level(2'd0), .title_valid(1'b0),
        .title_text_byte(8'd0), .shell_sample_timing(1'b0),
        .profile_audio_l(profile_audio_l),
        .profile_audio_r(profile_audio_r),
        .profile_audio_sample_valid(profile_audio_sample_valid),
        .profile_audio_enable(profile_audio_enable),
        .playback_active(playback_active), .profile_fatal(profile_fatal),
        .profile_status(profile_status), .debug_page_data(debug_page_data),
        .parser_start_count(parser_start_count),
        .scanner_start_count(scanner_start_count),
        .sound_write_count(sound_write_count)
    );

    task automatic load_memory(input string path, output integer size);
        integer fd;
        begin
            fd = $fopen(path, "rb");
            if (!fd) $fatal(1, "cannot open %s", path);
            size = $fread(memory, fd);
            $fclose(fd);
        end
    endtask

    task automatic begin_load(input string name);
        integer size;
        string path;
        begin
            path = {fixture_dir, "/", name, ".vgm"};
            upload_complete = 1'b0;
            download_active = 1'b1;
            load_memory(path, size);
            uploaded_physical_size = size;
            repeat (4) @(posedge clk);
            download_active = 1'b0;
            repeat (3) @(posedge clk);
            upload_complete = 1'b1;
        end
    endtask

    task automatic begin_short_abort;
        begin
            upload_complete = 1'b0;
            download_active = 1'b1;
            uploaded_physical_size = 11;
            repeat (4) @(posedge clk);
            download_active = 1'b0;
            repeat (3) @(posedge clk);
            upload_complete = 1'b1;
        end
    endtask

    task automatic wait_state(input integer wanted, input integer limit);
        integer timeout;
        begin
            timeout = 0;
            while (profile.stage_b_core.lifecycle_state != wanted && timeout < limit) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (profile.stage_b_core.lifecycle_state != wanted)
                $fatal(1, "lifecycle timeout wanted=%0d actual=%0d", wanted,
                       profile.stage_b_core.lifecycle_state);
        end
    endtask

    always_ff @(posedge clk) begin
        cycles <= cycles + 1;
        profile_audio_enable_d <= profile_audio_enable;
        if (!profile_audio_enable_d && profile_audio_enable)
            enable_rises <= enable_rises + 1;
        file_read_valid <= 1'b0;
        if (inject_stale) begin
            file_read_valid <= 1'b1;
            file_read_data <= 8'ha5;
            inject_stale <= 1'b0;
        end
        if (file_read_request && !file_read_ready) begin
            if (hold_count == 0) held_address <= file_read_address;
            else if (file_read_address !== held_address)
                $fatal(1, "profile read address changed before accept");
            hold_count <= hold_count + 1;
        end else hold_count <= 0;
        if (file_read_request && file_read_ready) begin
            if (pending) $fatal(1, "profile exceeded one outstanding");
            pending <= 1'b1;
            pending_addr <= file_read_address;
            response_delay <= file_read_address[1:0] + 1;
            accepts <= accepts + 1;
        end
        if (pending) begin
            if (response_delay == 0) begin
                file_read_data <= memory[pending_addr];
                file_read_valid <= 1'b1;
                pending <= 1'b0;
                responses <= responses + 1;
            end else response_delay <= response_delay - 1;
        end
        if (!reset) begin
            if (download_active && file_read_request)
                $fatal(1, "DDR read during upload");
            if (profile_audio_l != 0 || profile_audio_r != 0 ||
                profile_audio_sample_valid || profile_audio_enable ||
                playback_active || profile_fatal || pcm_a_read_request ||
                pcm_b_read_request || parser_start_count != 0 ||
                sound_write_count != 0)
                $fatal(1, "Stage B playback/audio invariant failed");
            if (^{file_read_request, file_read_address, profile_status,
                  debug_page_data, scanner_start_count, profile_audio_l,
                  profile_audio_r, profile_audio_sample_valid,
                  profile_audio_enable} === 1'bx)
                $fatal(1, "profile relevant X/Z");
        end
    end

    initial begin
        if (!$value$plusargs("FIXTURES=%s", fixture_dir))
            $fatal(1, "use +FIXTURES=/tmp/fixtures");
        pending = 0;
        pending_addr = 0;
        response_delay = 0;
        cycles = 0;
        accepts = 0;
        responses = 0;
        failures = 0;
        enable_rises = 0;
        profile_audio_enable_d = 0;
        inject_stale = 0;
        held_address = 0;
        hold_count = 0;
        repeat (5) @(posedge clk);
        reset = 1'b0;
        repeat (5) @(posedge clk);
        if (file_read_request || scanner_start_count != 0)
            $fatal(1, "cold idle contract");

        begin_load("standard_valid_raw");
        wait_state(7, 200000);
        if (scanner_start_count != 1 || profile.stage_b_core.prepared_file)
            $fatal(1, "cold raw load result");

        begin_load("prepared_valid");
        wait_state(7, 200000);
        if (scanner_start_count != 2 || !profile.stage_b_core.prepared_file ||
            profile.stage_b_core.exact_original_size + 128 != uploaded_physical_size)
            $fatal(1, "prepared load/result");

        begin_load("b_only_key_on");
        wait_state(8, 200000);
        if (scanner_start_count != 3 ||
            profile.stage_b_core.scan_classification != 2 ||
            profile.stage_b_core.scan_reject_code != 8'h03 || file_read_request)
            $fatal(1, "rejected idle contract");

        begin_load("standard_valid_raw");
        wait_state(7, 200000);
        if (scanner_start_count != 4)
            $fatal(1, "rejected-to-valid reload");

        begin_short_abort();
        repeat (200) @(posedge clk);
        if (scanner_start_count != 4 || file_read_request)
            $fatal(1, "aborted upload started scanner");
        begin_load("standard_valid_raw");
        wait_state(7, 200000);
        if (scanner_start_count != 5) $fatal(1, "abort reload failed");

        // A stale response while no transaction owns it is rejected safely.
        inject_stale = 1'b1;
        wait_state(8, 100);
        if (profile.stage_b_core.profile_reject_code != 8'h0a || file_read_request)
            $fatal(1, "stale response was not safely rejected");

        // A stale pulse during download belongs to the canceled generation and
        // must not poison the next completed load.
        upload_complete = 1'b0;
        download_active = 1'b1;
        inject_stale = 1'b1;
        repeat (5) @(posedge clk);
        download_active = 1'b0;
        begin_load("standard_valid_raw");
        wait_state(7, 200000);
        if (profile.stage_b_core.adapter_stale || scanner_start_count != 6)
            $fatal(1, "next-load stale response leaked");

        // Software reset during upload, then a fresh generation.
        upload_complete = 1'b0;
        download_active = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        download_active = 1'b0;
        begin_load("standard_valid_raw");
        wait_state(7, 200000);
        if (scanner_start_count != 1)
            $fatal(1, "reset-during-upload recovery");

        // Reset after scan has started; the next load must own every response.
        begin_load("standard_valid_raw");
        wait_state(6, 200000);
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        upload_complete = 1'b0;
        begin_load("standard_valid_raw");
        wait_state(7, 200000);
        if (scanner_start_count != 1 || profile.stage_b_core.adapter_stale)
            $fatal(1, "reset-during-scan recovery");

        repeat (120000) @(posedge clk);
        if (profile.stage_b_core.lifecycle_state != 7 || file_read_request ||
            profile.stage_b_core.adapter_outstanding || scanner_start_count != 1)
            $fatal(1, "120-second-equivalent idle changed state");
        if (accepts < responses || accepts - responses > 1)
            $fatal(1, "request/response accounting impossible");
        if (enable_rises != 0)
            $fatal(1, "Stage B audio enable rose %0d times", enable_rises);
        $display("V1_1_STAGE_B_LIFECYCLE_RESULT PASS starts=%0d accepts=%0d responses=%0d enable_rises=%0d idle_equivalent_seconds=120",
                 scanner_start_count, accepts, responses, enable_rises);
        $finish;
    end
endmodule
