`timescale 1ns/1ps

module tb_golden_player_shell_v1_1_stage_c_profile;
    localparam int MAX_FILE = 1 << 20;

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
    logic pending = 1'b0;
    logic [22:0] pending_address = 23'd0;
    logic [22:0] held_address = 23'd0;
    integer response_delay = 0;
    integer held_cycles = 0;
    integer cycles = 0;
    integer accepts = 0;
    integer responses = 0;
    integer enable_rises = 0;
    integer enable_falls = 0;
    integer xz_count = 0;
    integer concurrent_count = 0;
    integer pcm_count = 0;
    integer nonzero_count = 0;
    logic enable_d = 1'b0;
    string fixture_dir;

    always #5 clk = ~clk;
    assign file_read_ready = !pending && cycles[2:0] != 3'd3;

    golden_player_shell_v1_1_profile #(
        .VGM_ADDR_WIDTH(23),
        .CLK_SYS_HZ(8_000_000)
    ) profile (
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

    always_ff @(posedge clk) begin
        cycles <= cycles + 1;
        file_read_valid <= 1'b0;

        if (reset) begin
            pending <= 1'b0;
            response_delay <= 0;
            held_cycles <= 0;
        end else begin
            if (file_read_request && !file_read_ready) begin
                if (held_cycles == 0)
                    held_address <= file_read_address;
                else if (file_read_address !== held_address)
                    $fatal(1, "reader address changed before accept");
                held_cycles <= held_cycles + 1;
            end else begin
                held_cycles <= 0;
            end

            if (file_read_request && file_read_ready) begin
                if (pending)
                    $fatal(1, "more than one DDR response outstanding");
                pending <= 1'b1;
                pending_address <= file_read_address;
                response_delay <= file_read_address[1:0] + 1;
                accepts <= accepts + 1;
            end

            if (pending) begin
                if (response_delay == 0) begin
                    file_read_data <= memory[pending_address];
                    file_read_valid <= 1'b1;
                    pending <= 1'b0;
                    responses <= responses + 1;
                end else begin
                    response_delay <= response_delay - 1;
                end
            end
        end
    end

    // The start pulse is consumed by the parser at this edge. The v1.1 gate
    // must already have been high for the preceding cycle.
    always @(posedge clk) begin
        if (!reset && profile.stage_c_core.parser_start &&
            !profile_audio_enable)
            $fatal(1, "parser consumed start before audio gate opened");
    end

    always @(posedge clk) begin
        #1;
        if (!reset) begin
            if (!enable_d && profile_audio_enable) begin
                enable_rises = enable_rises + 1;
                if (profile.stage_c_core.u_parser.active ||
                    !profile_status[14] || profile_status[13] ||
                    !profile_status[12] || profile_fatal)
                    $fatal(1, "unsafe enable rise active=%0d status=%04x",
                           profile.stage_c_core.u_parser.active,
                           profile_status);
            end
            if (enable_d && !profile_audio_enable)
                enable_falls = enable_falls + 1;
            enable_d = profile_audio_enable;

            if (!profile_audio_enable &&
                (profile_audio_l != 0 || profile_audio_r != 0 ||
                 profile_audio_sample_valid))
                $fatal(1, "disabled profile output was not zero");
            if (profile_audio_enable &&
                (profile_audio_l !== profile.stage_c_audio_l ||
                 profile_audio_r !== profile.stage_c_audio_r ||
                 profile_audio_sample_valid !==
                    profile.stage_c_audio_sample_valid))
                $fatal(1, "enabled signed audio/sample-valid mapping mismatch");
            if (download_active && profile_audio_enable)
                $fatal(1, "audio enabled during download");
            if (profile_fatal && profile_audio_enable)
                $fatal(1, "audio remained enabled in fatal state");
            if (profile.stage_c_core.scan_mem_req &&
                profile.stage_c_core.parser_mem_req)
                concurrent_count = concurrent_count + 1;
            if (pcm_a_read_request || pcm_b_read_request ||
                profile.stage_c_core.sound_adpcma_request ||
                profile.stage_c_core.sound_adpcmb_request ||
                profile.stage_c_core.sound_adpcma_l != 0 ||
                profile.stage_c_core.sound_adpcma_r != 0 ||
                profile.stage_c_core.sound_adpcmb_l != 0 ||
                profile.stage_c_core.sound_adpcmb_r != 0)
                pcm_count = pcm_count + 1;
            if (profile_audio_enable && profile_audio_sample_valid &&
                (profile_audio_l != 0 || profile_audio_r != 0))
                nonzero_count = nonzero_count + 1;
            if ((^{file_read_request, file_read_address,
                    pcm_a_read_request, pcm_a_read_address,
                    pcm_b_read_request, pcm_b_read_address,
                    profile_audio_l, profile_audio_r,
                    profile_audio_sample_valid, profile_audio_enable,
                    playback_active, profile_fatal, profile_status,
                    debug_page_data, parser_start_count,
                    scanner_start_count, sound_write_count}) === 1'bx)
                xz_count = xz_count + 1;
        end
    end

    task automatic load_fixture(input string name);
        integer fd;
        integer size;
        string path;
        begin
            path = {fixture_dir, "/", name, ".vgm"};
            @(negedge clk);
            upload_complete = 1'b0;
            download_active = 1'b1;
            fd = $fopen(path, "rb");
            if (!fd) $fatal(1, "cannot open %s", path);
            size = $fread(memory, fd);
            $fclose(fd);
            uploaded_physical_size = size;
            repeat (5) @(posedge clk);
            download_active = 1'b0;
            repeat (3) @(posedge clk);
            upload_complete = 1'b1;
        end
    endtask

    task automatic reset_case;
        begin
            reset = 1'b1;
            download_active = 1'b0;
            upload_complete = 1'b0;
            repeat (5) @(posedge clk);
            reset = 1'b0;
            repeat (3) @(posedge clk);
            #1;
            if (profile_audio_enable || profile_audio_l != 0 ||
                profile_audio_r != 0 || profile_audio_sample_valid ||
                file_read_request || parser_start_count != 0 ||
                scanner_start_count != 0 || sound_write_count != 0 ||
                profile_status[7:3] != 5'd0)
                $fatal(1, "reset did not establish WAIT_LOAD");
        end
    endtask

    task automatic wait_state(input integer wanted, input integer limit);
        integer timeout;
        begin
            timeout = 0;
            while (profile_status[7:3] != wanted && timeout < limit) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (profile_status[7:3] != wanted)
                $fatal(1, "state timeout wanted=%0d actual=%0d",
                       wanted, profile_status[7:3]);
        end
    endtask

    task automatic wait_enable(input integer limit);
        integer timeout;
        begin
            timeout = 0;
            while (!profile_audio_enable && timeout < limit) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            #1;
            if (!profile_audio_enable || parser_start_count != 1 ||
                scanner_start_count != 1 || !playback_active)
                $fatal(1, "playback arm failed enable=%0d starts=%0d/%0d",
                       profile_audio_enable, scanner_start_count,
                       parser_start_count);
        end
    endtask

    task automatic expect_safe_zero;
        begin
            #1;
            if (profile_audio_enable || profile_audio_l != 0 ||
                profile_audio_r != 0 || profile_audio_sample_valid ||
                file_read_request || pcm_a_read_request ||
                pcm_b_read_request)
                $fatal(1, "safe-zero contract failed state=%0d",
                       profile_status[7:3]);
        end
    endtask

    task automatic wait_audio_nonzero(input integer limit);
        integer wait_cycles;
        begin
            wait_cycles = 0;
            while (nonzero_count == 0 && wait_cycles < limit) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (nonzero_count == 0)
                $fatal(1, "profile audio did not become nonzero");
        end
    endtask

    task automatic reject_fixture(input string name);
        integer reject_rises;
        begin
            reject_rises = enable_rises;
            load_fixture(name);
            wait_state(12, 300_000);
            expect_safe_zero();
            if (enable_rises != reject_rises || parser_start_count != 0 ||
                sound_write_count != 0)
                $fatal(1, "reject fixture opened playback: %s", name);
        end
    endtask

    integer rises_before;
    integer timeout;
    initial begin
        if (!$value$plusargs("FIXTURES=%s", fixture_dir))
            $fatal(1, "use +FIXTURES=/tmp/stage-c-fixtures");

        reset_case();

        // An upload aborted by software Reset never reaches scan or opens
        // the v1.1 audio gate.
        download_active = 1'b1;
        repeat (4) @(posedge clk);
        reset = 1'b1;
        @(posedge clk);
        #1;
        expect_safe_zero();
        download_active = 1'b0;
        upload_complete = 1'b0;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (3) @(posedge clk);
        expect_safe_zero();

        // Representative B-only, dual, unknown-register, and unsupported-
        // opcode rejects remain silent and can be followed by a valid load
        // without resetting the shell.
        rises_before = enable_rises;
        reject_fixture("reject_b_key");
        reject_fixture("reject_dual");
        reject_fixture("reject_unknown");
        reject_fixture("reject_opcode");
        $display("V1_1_STAGE_C_PROGRESS reject"); $fflush();

        load_fixture("fm_only_raw");
        wait_enable(500_000);
        if (enable_rises != rises_before + 1)
            $fatal(1, "rejected-to-valid enable rise mismatch");
        nonzero_count = 0;
        wait_audio_nonzero(500_000);
        wait_state(13, 1_000_000);
        repeat (2) @(posedge clk);
        expect_safe_zero();
        if (profile.stage_c_core.parser_command_count != 37 ||
            profile.stage_c_core.parser_write_count != 34 ||
            profile.stage_c_core.parser_forwarded_fm_count != 34 ||
            profile.stage_c_core.parser_suppressed_a_count != 0 ||
            profile.stage_c_core.parser_suppressed_b_count != 0)
            $fatal(1, "FM parser result mismatch");
        $display("V1_1_STAGE_C_PROGRESS fm_end"); $fflush();

        // ENDED_IDLE accepts a new generation. Reset during that generation's
        // first playback wait closes the gate and cancels parser ownership.
        load_fixture("fm_only_raw");
        wait_enable(500_000);
        repeat (20) @(posedge clk);
        reset = 1'b1;
        @(posedge clk);
        #1;
        expect_safe_zero();
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (3) @(posedge clk);
        expect_safe_zero();

        // Same-file reload while audible closes the old gate and produces
        // exactly one fresh rise for the new generation.
        reset_case();
        rises_before = enable_rises;
        load_fixture("fm_only_prepared");
        wait_enable(500_000);
        nonzero_count = 0;
        wait_audio_nonzero(500_000);
        load_fixture("fm_only_prepared");
        if (profile_audio_enable)
            $fatal(1, "reload did not close enable");
        wait_enable(500_000);
        nonzero_count = 0;
        wait_audio_nonzero(500_000);
        if (enable_rises != rises_before + 2)
            $fatal(1, "same-file reload rise mismatch");
        $display("V1_1_STAGE_C_PROGRESS same_reload"); $fflush();

        // A different-file reload reaches the inherited SSG path without a
        // stale parser response or an additional read client.
        load_fixture("ssg_abc");
        wait_enable(500_000);
        wait_state(13, 1_000_000);
        repeat (2) @(posedge clk);
        expect_safe_zero();
        if (profile.stage_c_core.parser_forwarded_ssg_count != 13 ||
            profile.stage_c_core.parser_forwarded_fm_count != 0 ||
            profile.stage_c_core.parser_write_count != 13)
            $fatal(1, "different-file SSG reload mismatch");
        if (enable_rises != rises_before + 3)
            $fatal(1, "different-file reload rise mismatch");
        $display("V1_1_STAGE_C_PROGRESS different_reload"); $fflush();

        // Suppressed ADPCM writes remain trace-visible but cannot reach JT10
        // or either PCM request/lane.
        reset_case();
        rises_before = enable_rises;
        load_fixture("suppressed_pcm");
        wait_enable(500_000);
        nonzero_count = 0;
        wait_audio_nonzero(1_000_000);
        wait_state(13, 1_000_000);
        repeat (2) @(posedge clk);
        expect_safe_zero();
        if (profile.stage_c_core.parser_write_count != 43 ||
            profile.stage_c_core.parser_forwarded_fm_count != 34 ||
            profile.stage_c_core.parser_suppressed_a_count != 4 ||
            profile.stage_c_core.parser_suppressed_b_count != 5 ||
            sound_write_count != 34 || enable_rises != rises_before + 1)
            $fatal(1, "suppressed PCM accounting mismatch");
        $display("V1_1_STAGE_C_PROGRESS suppressed_pcm"); $fflush();

        // Loop changes only the parser PC. The gate/core stay live and neither
        // scanner nor playback start is repeated.
        reset_case();
        rises_before = enable_rises;
        load_fixture("fm_loop");
        wait_enable(500_000);
        timeout = 0;
        while (profile.stage_c_core.parser_loop_count == 0 &&
               timeout < 1_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        #1;
        if (timeout >= 1_000_000 || !profile_audio_enable ||
            enable_rises != rises_before + 1 || parser_start_count != 1 ||
            scanner_start_count != 1 ||
            profile.stage_c_core.sound_core_reset ||
            profile.stage_c_core.parser_timeline_sample != 288)
            $fatal(1, "loop continuity contract mismatch");
        $display("V1_1_STAGE_C_PROGRESS loop"); $fflush();

        // Software Reset during a live loop closes the gate immediately and
        // returns to WAIT_LOAD without a global/video dependency.
        reset = 1'b1;
        @(posedge clk);
        #1;
        if (profile_audio_enable || profile_audio_l != 0 ||
            profile_audio_r != 0 || profile_audio_sample_valid)
            $fatal(1, "software Reset did not close live audio");
        repeat (4) @(posedge clk);
        reset = 1'b0;
        repeat (3) @(posedge clk);
        expect_safe_zero();

        // Reset during scan and during sound reset both recover on a new load.
        load_fixture("fm_only_raw");
        wait_state(6, 300_000);
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);
        expect_safe_zero();
        load_fixture("fm_only_raw");
        wait_state(8, 300_000);
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);
        expect_safe_zero();

        if (concurrent_count != 0 || pcm_count != 0 || xz_count != 0 ||
            accepts < responses || accepts - responses > 1 ||
            nonzero_count == 0)
            $fatal(1, "global contract mismatch concurrent=%0d pcm=%0d xz=%0d reads=%0d/%0d audio=%0d",
                   concurrent_count, pcm_count, xz_count, accepts, responses,
                   nonzero_count);

        $display("V1_1_STAGE_C_PROFILE_RESULT PASS enable_rises=%0d enable_falls=%0d parser_before_gate=0 concurrent=0 pcm=0 xz=0 reads=%0d/%0d",
                 enable_rises, enable_falls, accepts, responses);
        $finish;
    end
endmodule
