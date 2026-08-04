`timescale 1ns/1ps

module tb_stage_c_profile_lifecycle;
    localparam int MAX_FILE = 1 << 20;
    localparam logic [63:0] FNV_OFFSET = 64'hcbf29ce484222325;

    logic clk_sys = 1'b0;
    logic reset = 1'b1;
    logic download_active = 1'b0;
    logic [31:0] uploaded_physical_size = 32'd0;
    logic upload_complete = 1'b0;
    logic file_read_ready;
    logic file_read_valid = 1'b0;
    logic [7:0] file_read_data = 8'd0;
    logic file_read_request;
    logic [22:0] file_read_address;
    logic pcm_a_read_request;
    logic [22:0] pcm_a_read_address;
    logic pcm_b_read_request;
    logic [22:0] pcm_b_read_address;
    logic [1:0] osd_audio_lpf_mode = 2'd0;
    logic osd_audio_gain_boost = 1'b0;
    logic [1:0] osd_audio_psg_level = 2'd0;
    logic title_valid = 1'b0;
    logic [7:0] title_text_byte = 8'd0;
    logic shell_sample_timing = 1'b0;
    logic signed [15:0] audio_l, audio_r;
    logic audio_sample_valid, playback_active, profile_fatal;
    logic [15:0] profile_status, debug_page_data;
    logic [31:0] parser_start_count, scanner_start_count;
    logic [31:0] sound_write_count;

    logic [7:0] memory [0:MAX_FILE-1];
    logic pending = 1'b0;
    logic [22:0] pending_address = 23'd0;
    integer response_delay = 0;
    integer cycle_count = 0;
    integer accepted_reads = 0;
    integer responses = 0;
    integer held_cycles = 0;
    logic [22:0] held_address = 23'd0;
    integer concurrent_cycles = 0;
    integer pcm_cycles = 0;
    integer preplay_audio_cycles = 0;
    integer playback_nonzero_cycles = 0;
    integer xz_count = 0;
    integer fd;
    integer file_size;
    integer timeout;
    integer expect_accept;
    integer expect_prepared;
    integer expect_commands;
    integer expect_writes;
    integer expect_fm;
    integer expect_ssg;
    integer expect_a;
    integer expect_b;
    integer expect_blocks;
    integer reload_test;
    integer different_reload_test;
    integer loop_test;
    integer reset_at;
    logic [63:0] expect_hash;
    logic [63:0] expect_audio_hash;
    logic [63:0] audio_hash = FNV_OFFSET;
    integer expect_audio_hash_valid;
    integer audio_hash_samples = 0;
    logic audio_hash_armed = 1'b0;
    logic audio_hash_started = 1'b0;
    logic [31:0] saved_loop_target;
    logic [31:0] saved_loop_sample;
    string filename;
    string filename2;
    integer expect2_prepared;
    integer expect2_commands;
    integer expect2_writes;
    integer expect2_fm;
    integer expect2_ssg;
    integer expect2_a;
    integer expect2_b;
    integer expect2_blocks;
    logic [63:0] expect2_hash;

    function automatic [63:0] hash_stereo(
        input logic [63:0] hash,
        input logic [15:0] left_sample,
        input logic [15:0] right_sample
    );
        integer byte_index;
        logic [31:0] sample_word;
        logic [63:0] next;
        begin
            sample_word = {right_sample, left_sample};
            next = hash;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                next = (next ^ sample_word[byte_index*8 +: 8]) *
                       64'h0000_0100_0000_01b3;
            hash_stereo = next;
        end
    endfunction

    always #5 clk_sys = ~clk_sys;
    assign file_read_ready = !pending && cycle_count[2:0] != 3'd3;

    ym2610_golden_stage_a #(
        .VGM_ADDR_WIDTH(23),
        .CLK_SYS_HZ(8_000_000)
    ) dut (.*);

    always_ff @(posedge clk_sys) begin
        cycle_count <= cycle_count + 1;
        file_read_valid <= 1'b0;

        if (file_read_request && !file_read_ready) begin
            if (held_cycles == 0)
                held_address <= file_read_address;
            else if (file_read_address !== held_address)
                $fatal(1, "profile reader address changed before accept");
            held_cycles <= held_cycles + 1;
        end else begin
            held_cycles <= 0;
        end

        if (file_read_request && file_read_ready) begin
            if (pending)
                $fatal(1, "profile reader exceeded one outstanding");
            pending <= 1'b1;
            pending_address <= file_read_address;
            response_delay <= file_read_address[1:0] + 1;
            accepted_reads <= accepted_reads + 1;
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

    always @(posedge clk_sys) begin
        #1;
        if (!reset) begin
            if (dut.scan_mem_req && dut.parser_mem_req)
                concurrent_cycles = concurrent_cycles + 1;
            if (pcm_a_read_request || pcm_b_read_request ||
                dut.sound_adpcma_request || dut.sound_adpcmb_request ||
                dut.sound_adpcma_l != 0 || dut.sound_adpcma_r != 0 ||
                dut.sound_adpcmb_l != 0 || dut.sound_adpcmb_r != 0)
                pcm_cycles = pcm_cycles + 1;
            if (!playback_active &&
                (audio_l != 0 || audio_r != 0 || audio_sample_valid))
                preplay_audio_cycles = preplay_audio_cycles + 1;
            if (playback_active && audio_sample_valid &&
                (audio_l != 0 || audio_r != 0))
                playback_nonzero_cycles = playback_nonzero_cycles + 1;
            if (!audio_hash_armed && dut.parser_trace_valid &&
                dut.parser_trace_forwarded &&
                dut.parser_trace_port == 1'b0 &&
                ((dut.parser_trace_address == 8'h28 &&
                  dut.parser_trace_data == 8'hf1) ||
                 (expect_fm == 0 && expect_ssg != 0 &&
                  dut.parser_trace_address == 8'h0a &&
                  dut.parser_trace_data == 8'h0f))) begin
                audio_hash_armed = 1'b1;
                audio_hash_started = 1'b0;
                audio_hash_samples = 0;
                audio_hash = FNV_OFFSET;
            end else if (audio_hash_armed && audio_hash_samples < 512 &&
                         dut.sound_public_sample_rise) begin
                if (audio_hash_started || audio_l != 0 || audio_r != 0) begin
                    audio_hash_started = 1'b1;
                    audio_hash = hash_stereo(audio_hash, audio_l, audio_r);
                    audio_hash_samples = audio_hash_samples + 1;
                end
            end
            if ((^{file_read_request, file_read_address,
                    pcm_a_read_request, pcm_a_read_address,
                    pcm_b_read_request, pcm_b_read_address}) === 1'bx ||
                (^{audio_l, audio_r, audio_sample_valid, playback_active,
                    profile_fatal, profile_status, debug_page_data}) === 1'bx ||
                (^{parser_start_count, scanner_start_count,
                    sound_write_count}) === 1'bx)
                xz_count = xz_count + 1;
        end
    end

    task automatic pulse_load;
        begin
            upload_complete = 1'b0;
            download_active = 1'b1;
            repeat (5) @(posedge clk_sys);
            download_active = 1'b0;
            upload_complete = 1'b1;
        end
    endtask

    task automatic pulse_software_reset;
        begin
            reset = 1'b1;
            repeat (5) @(posedge clk_sys);
            reset = 1'b0;
            while (pending) @(posedge clk_sys);
            repeat (5) @(posedge clk_sys);
            #1;
            if (dut.lifecycle_state != 5'd0 || playback_active ||
                parser_start_count != 0 || scanner_start_count != 0 ||
                sound_write_count != 0 || audio_l != 0 || audio_r != 0 ||
                audio_sample_valid || file_read_request)
                $fatal(1, "software reset did not establish WAIT_LOAD");
        end
    endtask

    task automatic wait_for_terminal;
        begin
            timeout = 0;
            while (dut.lifecycle_state != 5'd12 &&
                   dut.lifecycle_state != 5'd13 &&
                   dut.lifecycle_state != 5'd14 &&
                   timeout < 8_000_000) begin
                @(posedge clk_sys);
                timeout = timeout + 1;
            end
            #1;
            if (timeout >= 8_000_000)
                $fatal(1, "profile timeout state=%0d pc=%08x",
                       dut.lifecycle_state, dut.parser_current_pc);
            if (dut.lifecycle_state == 5'd14 || profile_fatal)
                $fatal(1, "profile fatal reject=%02x parser=%02x state=%0d",
                       dut.profile_reject_code, dut.parser_fatal_code,
                       dut.lifecycle_state);
        end
    endtask

    task automatic check_terminal;
        begin
            if (scanner_start_count != 1)
                $fatal(1, "scanner start count=%0d", scanner_start_count);
            if (expect_accept) begin
                if (dut.lifecycle_state != 5'd13 || parser_start_count != 1)
                    $fatal(1, "accepted file lifecycle/start mismatch state=%0d starts=%0d",
                           dut.lifecycle_state, parser_start_count);
                if (dut.parser_command_count != expect_commands ||
                    dut.parser_write_count != expect_writes ||
                    dut.parser_forwarded_fm_count != expect_fm ||
                    dut.parser_forwarded_ssg_count != expect_ssg ||
                    dut.parser_suppressed_a_count != expect_a ||
                    dut.parser_suppressed_b_count != expect_b ||
                    dut.parser_data_block_count != expect_blocks ||
                    dut.parser_trace_hash != expect_hash ||
                    sound_write_count != expect_fm + expect_ssg)
                    $fatal(1, "accepted result mismatch cmd=%0d writes=%0d fm=%0d ssg=%0d A=%0d B=%0d blocks=%0d hash=%016x sound=%0d",
                           dut.parser_command_count, dut.parser_write_count,
                           dut.parser_forwarded_fm_count,
                           dut.parser_forwarded_ssg_count,
                           dut.parser_suppressed_a_count,
                           dut.parser_suppressed_b_count,
                           dut.parser_data_block_count,
                           dut.parser_trace_hash, sound_write_count);
                if ((expect_fm != 0 || expect_ssg != 0) &&
                    playback_nonzero_cycles == 0)
                    $fatal(1, "accepted sound file produced no audio");
                if (expect_audio_hash_valid &&
                    (audio_hash_samples != 512 ||
                     audio_hash != expect_audio_hash))
                    $fatal(1, "parser/direct audio mismatch samples=%0d hash=%016x/%016x",
                           audio_hash_samples, audio_hash,
                           expect_audio_hash);
            end else begin
                if (dut.lifecycle_state != 5'd12 || parser_start_count != 0 ||
                    sound_write_count != 0 || playback_nonzero_cycles != 0)
                    $fatal(1, "reject safety mismatch state=%0d parser=%0d sound=%0d audio=%0d",
                           dut.lifecycle_state, parser_start_count,
                           sound_write_count, playback_nonzero_cycles);
            end
            if (dut.prepared_file != expect_prepared)
                $fatal(1, "prepared detection mismatch actual=%0d expected=%0d",
                       dut.prepared_file, expect_prepared);
            if (audio_l != 0 || audio_r != 0 || audio_sample_valid ||
                file_read_request || dut.adapter_outstanding)
                $fatal(1, "terminal state not quiescent");
        end
    endtask

    initial begin
        if (!$value$plusargs("VGM=%s", filename) ||
            !$value$plusargs("EXPECT_ACCEPT=%d", expect_accept) ||
            !$value$plusargs("EXPECT_PREPARED=%d", expect_prepared) ||
            !$value$plusargs("EXPECT_COMMANDS=%d", expect_commands) ||
            !$value$plusargs("EXPECT_WRITES=%d", expect_writes) ||
            !$value$plusargs("EXPECT_FM=%d", expect_fm) ||
            !$value$plusargs("EXPECT_SSG=%d", expect_ssg) ||
            !$value$plusargs("EXPECT_A=%d", expect_a) ||
            !$value$plusargs("EXPECT_B=%d", expect_b) ||
            !$value$plusargs("EXPECT_BLOCKS=%d", expect_blocks) ||
            !$value$plusargs("EXPECT_HASH=%h", expect_hash))
            $fatal(1, "missing profile lifecycle plusargs");
        reload_test = $test$plusargs("RELOAD");
        different_reload_test = $test$plusargs("DIFFERENT_RELOAD");
        if (different_reload_test &&
            (!$value$plusargs("VGM2=%s", filename2) ||
             !$value$plusargs("EXPECT2_PREPARED=%d", expect2_prepared) ||
             !$value$plusargs("EXPECT2_COMMANDS=%d", expect2_commands) ||
             !$value$plusargs("EXPECT2_WRITES=%d", expect2_writes) ||
             !$value$plusargs("EXPECT2_FM=%d", expect2_fm) ||
             !$value$plusargs("EXPECT2_SSG=%d", expect2_ssg) ||
             !$value$plusargs("EXPECT2_A=%d", expect2_a) ||
             !$value$plusargs("EXPECT2_B=%d", expect2_b) ||
             !$value$plusargs("EXPECT2_BLOCKS=%d", expect2_blocks) ||
             !$value$plusargs("EXPECT2_HASH=%h", expect2_hash)))
            $fatal(1, "missing different-reload plusargs");
        loop_test = $test$plusargs("LOOP_TEST");
        expect_audio_hash_valid =
            $value$plusargs("EXPECT_AUDIO_HASH=%h", expect_audio_hash);
        if (!$value$plusargs("RESET_AT=%d", reset_at)) reset_at = 0;

        fd = $fopen(filename, "rb");
        if (!fd) $fatal(1, "cannot open %s", filename);
        file_size = $fread(memory, fd);
        $fclose(fd);
        uploaded_physical_size = file_size;

        repeat (5) @(posedge clk_sys);
        reset = 1'b0;
        if (reset_at == 1) begin
            upload_complete = 1'b0;
            download_active = 1'b1;
            repeat (2) @(posedge clk_sys);
            pulse_software_reset();
            download_active = 1'b0;
            pulse_load();
        end else if (reset_at != 0) begin
            pulse_load();
            timeout = 0;
            if (reset_at == 2) begin
                while (dut.lifecycle_state != 5'd6 && timeout < 1_000_000) begin
                    @(posedge clk_sys);
                    timeout = timeout + 1;
                end
            end else if (reset_at == 3) begin
                while (dut.lifecycle_state != 5'd8 && timeout < 1_000_000) begin
                    @(posedge clk_sys);
                    timeout = timeout + 1;
                end
            end else if (reset_at == 4) begin
                while ((!playback_active || dut.parser_timeline_sample < 8) &&
                       timeout < 1_000_000) begin
                    @(posedge clk_sys);
                    timeout = timeout + 1;
                end
            end else begin
                while ((!playback_active || playback_nonzero_cycles == 0) &&
                       timeout < 1_000_000) begin
                    @(posedge clk_sys);
                    timeout = timeout + 1;
                end
            end
            if (timeout >= 1_000_000)
                $fatal(1, "reset injection state was not reached mode=%0d state=%0d",
                       reset_at, dut.lifecycle_state);
            pulse_software_reset();
            pulse_load();
        end else begin
            pulse_load();
        end
        if (loop_test) begin
            timeout = 0;
            while (dut.parser_loop_count == 0 && timeout < 8_000_000) begin
                @(posedge clk_sys);
                timeout = timeout + 1;
            end
            #1;
            if (timeout >= 8_000_000 || !playback_active ||
                parser_start_count != 1 || scanner_start_count != 1 ||
                dut.parser_command_count != expect_commands ||
                dut.parser_write_count != expect_writes ||
                dut.parser_trace_hash != expect_hash ||
                dut.parser_loop_count != 1 || dut.sound_core_reset)
                $fatal(1, "loop contract mismatch state=%0d starts=%0d/%0d cmd=%0d writes=%0d loop=%0d hash=%016x core_reset=%0d",
                       dut.lifecycle_state, scanner_start_count,
                       parser_start_count, dut.parser_command_count,
                       dut.parser_write_count, dut.parser_loop_count,
                       dut.parser_trace_hash, dut.sound_core_reset);
            saved_loop_target = dut.scan_loop_target;
            saved_loop_sample = dut.parser_timeline_sample;
            if (saved_loop_target != 32'h000000e0 ||
                saved_loop_sample != 32'd288)
                $fatal(1, "loop target/timeline mismatch target=%08x sample=%0d",
                       saved_loop_target, saved_loop_sample);
            pulse_software_reset();
            if (dut.lifecycle_state != 5'd0 || playback_active ||
                parser_start_count != 0 || scanner_start_count != 0 ||
                audio_l != 0 || audio_r != 0 || audio_sample_valid ||
                file_read_request)
                $fatal(1, "software reset did not return WAIT_LOAD");
            $display("STAGE_C_PROFILE_LOOP PASS target=%08x samples=%0d loop=1 reset=0 scan_restart=0 playback_restart=0 software_reset_safe=1",
                     saved_loop_target, saved_loop_sample);
            $finish;
        end
        wait_for_terminal();
        check_terminal();

        if (reload_test) begin
            playback_nonzero_cycles = 0;
            audio_hash_armed = 1'b0;
            audio_hash_started = 1'b0;
            audio_hash_samples = 0;
            audio_hash = FNV_OFFSET;
            pulse_load();
            wait_for_terminal();
            check_terminal();
        end

        if (different_reload_test) begin
            playback_nonzero_cycles = 0;
            audio_hash_armed = 1'b0;
            audio_hash_started = 1'b0;
            audio_hash_samples = 0;
            audio_hash = FNV_OFFSET;
            fd = $fopen(filename2, "rb");
            if (!fd) $fatal(1, "cannot open second VGM %s", filename2);
            file_size = $fread(memory, fd);
            $fclose(fd);
            uploaded_physical_size = file_size;
            expect_prepared = expect2_prepared;
            expect_commands = expect2_commands;
            expect_writes = expect2_writes;
            expect_fm = expect2_fm;
            expect_ssg = expect2_ssg;
            expect_a = expect2_a;
            expect_b = expect2_b;
            expect_blocks = expect2_blocks;
            expect_hash = expect2_hash;
            expect_audio_hash_valid = 0;
            pulse_load();
            wait_for_terminal();
            check_terminal();
        end

        if (concurrent_cycles != 0 || pcm_cycles != 0 ||
            preplay_audio_cycles != 0 || xz_count != 0 ||
            accepted_reads != responses || pending)
            $fatal(1, "profile contract mismatch concurrent=%0d pcm=%0d preaudio=%0d xz=%0d reads=%0d/%0d pending=%0d",
                   concurrent_cycles, pcm_cycles, preplay_audio_cycles,
                   xz_count, accepted_reads, responses, pending);

        $display("STAGE_C_PROFILE PASS accepted=%0d prepared=%0d reload=%0d different_reload=%0d scanner_start=1 parser_start=%0d commands=%0d writes=%0d sound=%0d audio_nonzero_cycles=%0d concurrency=0 pcm=0 xz=0 reads=%0d",
                 expect_accept, expect_prepared, reload_test,
                 different_reload_test,
                 parser_start_count, dut.parser_command_count,
                 dut.parser_write_count, sound_write_count,
                 playback_nonzero_cycles, accepted_reads);
        $finish;
    end
endmodule
