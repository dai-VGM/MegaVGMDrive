`timescale 1ns/1ps

module tb_golden_player_shell_v1_1_stage_b_olga_upload;
    localparam int MAX_FILE = 1 << 20;
    localparam logic [28:0] DDR_BASE = {4'b0011, 25'd0};
    logic clk = 0;
    logic reset = 1;
    logic ioctl_download = 0, ioctl_wr = 0;
    logic [26:0] ioctl_addr = 0;
    logic [7:0] ioctl_dout = 0;
    logic [15:0] ioctl_index = 1;
    logic ioctl_wait;
    logic file_read_request, file_read_ready, file_read_valid;
    logic [22:0] file_read_address;
    logic [7:0] file_read_data;
    logic pcm_a_read_request, pcm_b_read_request;
    logic [22:0] pcm_a_read_address, pcm_b_read_address;
    logic signed [15:0] profile_audio_l, profile_audio_r;
    logic profile_audio_sample_valid, profile_audio_enable;
    logic playback_active, profile_fatal;
    logic [15:0] profile_status, debug_page_data;
    logic [31:0] parser_start_count, scanner_start_count, sound_write_count;
    logic load_busy, load_done, load_done_pulse, load_error, load_overflow;
    logic [31:0] uploaded_physical_size, upload_magic;
    logic ddram_busy = 0;
    logic [7:0] ddram_burstcnt;
    logic [28:0] ddram_addr;
    logic [63:0] ddram_dout = 0;
    logic ddram_dout_ready = 0;
    logic ddram_rd;
    logic [63:0] ddram_din;
    logic [7:0] ddram_be;
    logic ddram_we;
    logic [7:0] source [0:MAX_FILE-1];
    logic [7:0] ddr_memory [0:MAX_FILE-1];
    logic read_pending;
    logic [28:0] read_word_addr;
    integer read_delay, word_byte, lane, write_bytes, write_words, read_count;
    integer fd, file_size, address, timeout, enable_rises;
    logic profile_audio_enable_d;
    string filename;
    logic title_valid;
    logic [5:0] directory_length, basename_length;
    logic [6:0] title_read_addr = 0;
    logic [7:0] title_read_data;
    logic title_metadata_busy;

    always #5 clk = ~clk;

    function automatic integer popcount8(input logic [7:0] value);
        integer index;
        begin
            popcount8 = 0;
            for (index = 0; index < 8; index = index + 1)
                popcount8 = popcount8 + value[index];
        end
    endfunction

    golden_player_shell_upload upload (
        .clk(clk), .reset(reset), .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout), .ioctl_index(ioctl_index),
        .ioctl_wait(ioctl_wait), .file_read_request(file_read_request),
        .file_read_address(file_read_address),
        .file_read_ready(file_read_ready), .file_read_valid(file_read_valid),
        .file_read_data(file_read_data), .load_busy(load_busy),
        .load_done(load_done), .load_done_pulse(load_done_pulse),
        .load_error(load_error), .load_overflow(load_overflow),
        .uploaded_physical_size(uploaded_physical_size),
        .upload_magic(upload_magic), .ddram_busy(ddram_busy),
        .ddram_burstcnt(ddram_burstcnt), .ddram_addr(ddram_addr),
        .ddram_dout(ddram_dout), .ddram_dout_ready(ddram_dout_ready),
        .ddram_rd(ddram_rd), .ddram_din(ddram_din), .ddram_be(ddram_be),
        .ddram_we(ddram_we)
    );

    golden_player_shell_v1_1_profile profile (
        .clk_sys(clk), .reset(reset), .download_active(ioctl_download),
        .uploaded_physical_size(uploaded_physical_size),
        .upload_complete(load_done), .file_read_ready(file_read_ready),
        .file_read_valid(file_read_valid), .file_read_data(file_read_data),
        .file_read_request(file_read_request),
        .file_read_address(file_read_address),
        .pcm_a_read_request(pcm_a_read_request),
        .pcm_a_read_address(pcm_a_read_address),
        .pcm_b_read_request(pcm_b_read_request),
        .pcm_b_read_address(pcm_b_read_address),
        .osd_audio_lpf_mode(2'd0), .osd_audio_gain_boost(1'b0),
        .osd_audio_psg_level(2'd0), .title_valid(title_valid),
        .title_text_byte(title_read_data), .shell_sample_timing(1'b0),
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

    megavgm_title_receiver title_receiver (
        .clk(clk), .reset(reset), .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout), .ioctl_index(ioctl_index),
        .title_valid(title_valid), .directory_length(directory_length),
        .basename_length(basename_length), .title_read_addr(title_read_addr),
        .title_read_data(title_read_data), .metadata_busy(title_metadata_busy)
    );

    always @(posedge clk) begin
        profile_audio_enable_d <= profile_audio_enable;
        if (!profile_audio_enable_d && profile_audio_enable)
            enable_rises <= enable_rises + 1;
        ddram_dout_ready <= 1'b0;
        if (ddram_we && !ddram_busy) begin
            word_byte = (ddram_addr - DDR_BASE) * 8;
            write_words = write_words + 1;
            write_bytes = write_bytes + popcount8(ddram_be);
            for (lane = 0; lane < 8; lane = lane + 1) begin
                if (ddram_be[lane]) begin
                    ddr_memory[word_byte + lane] <= ddram_din[lane*8 +: 8];
                end
            end
        end
        if (ddram_rd && !ddram_busy) begin
            if (read_pending) $fatal(1, "DDRAM model got two reads");
            read_pending <= 1'b1;
            read_word_addr <= ddram_addr;
            read_delay <= ddram_addr[1:0] + 1;
            read_count = read_count + 1;
        end
        if (read_pending) begin
            if (read_delay == 0) begin
                word_byte = (read_word_addr - DDR_BASE) * 8;
                for (lane = 0; lane < 8; lane = lane + 1)
                    ddram_dout[lane*8 +: 8] <= ddr_memory[word_byte + lane];
                ddram_dout_ready <= 1'b1;
                read_pending <= 1'b0;
            end else read_delay <= read_delay - 1;
        end
        if (!reset) begin
            if (ioctl_download && (file_read_request || ddram_rd))
                $fatal(1, "Stage B read during physical upload");
            if (profile_audio_l != 0 || profile_audio_r != 0 ||
                profile_audio_sample_valid || profile_audio_enable ||
                playback_active || profile_fatal || parser_start_count != 0 ||
                sound_write_count != 0 || pcm_a_read_request || pcm_b_read_request)
                $fatal(1, "playback/audio invariant during Olga upload");
            if (^{ioctl_wait, file_read_request, file_read_address,
                  file_read_ready, file_read_valid, file_read_data,
                  profile_audio_l, profile_audio_r,
                  profile_audio_sample_valid, profile_audio_enable,
                  scanner_start_count, ddram_addr,
                  ddram_rd, ddram_din, ddram_be, ddram_we} === 1'bx)
                $fatal(1, "Olga integration relevant X/Z");
        end
    end

    initial begin
        if (!$value$plusargs("VGM=%s", filename))
            $fatal(1, "use +VGM=/path/file.vgm");
        fd = $fopen(filename, "rb");
        if (!fd) $fatal(1, "cannot open Olga");
        file_size = $fread(source, fd);
        $fclose(fd);
        if (file_size != 934025) $fatal(1, "Olga physical size mismatch");
        read_pending = 0;
        read_word_addr = 0;
        read_delay = 0;
        write_bytes = 0;
        write_words = 0;
        read_count = 0;
        enable_rises = 0;
        profile_audio_enable_d = 0;
        repeat (5) @(posedge clk);
        reset = 0;
        repeat (3) @(posedge clk);

        @(negedge clk);
        ioctl_download = 1;
        @(negedge clk);
        for (address = 0; address < file_size; address = address + 1) begin
            while (ioctl_wait) begin
                ioctl_wr = 0;
                @(negedge clk);
            end
            ioctl_addr = address;
            ioctl_dout = source[address];
            ioctl_wr = 1;
            @(negedge clk);
            ioctl_wr = 0;
        end
        ioctl_download = 0;

        timeout = 0;
        while (!load_done && timeout < 2_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        repeat (2) @(posedge clk);
        if (!load_done || load_error || load_overflow ||
            uploaded_physical_size != 934025 || write_bytes != 934025 ||
            write_words != ((934025 + 7) / 8))
            $fatal(1, "934025-byte completion fence failed size=%0d bytes=%0d words=%0d",
                   uploaded_physical_size, write_bytes, write_words);

        timeout = 0;
        while (profile.stage_b_core.lifecycle_state != 7 && timeout < 20_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (profile.stage_b_core.lifecycle_state != 7 || scanner_start_count != 1 ||
            !profile.stage_b_core.prepared_file ||
            profile.stage_b_core.exact_original_size != 933897 ||
            profile.stage_b_core.scan_classification != 1 ||
            profile.stage_b_core.scan_command_count != 171869 ||
            profile.stage_b_core.scan_total_writes != 81272 ||
            profile.stage_b_core.scan_port0_writes != 38246 ||
            profile.stage_b_core.scan_port1_writes != 43026 ||
            profile.stage_b_core.scan_total_samples != 8372668 ||
            profile.stage_b_core.scan_b_only_writes != 0 ||
            profile.stage_b_core.scan_unknown_writes != 0 ||
            profile.stage_b_core.scan_unsupported_opcodes != 0 ||
            profile.stage_b_core.scan_ssg_writes != 0 ||
            profile.stage_b_core.scan_adpcma_key_on_voices != 793 ||
            profile.stage_b_core.scan_adpcma_key_off_voices != 850 ||
            profile.stage_b_core.scan_adpcmb_start_count != 23 ||
            profile.stage_b_core.scan_adpcmb_reset_count != 27 ||
            profile.stage_b_core.scan_loop_target != 32'h000b6223 ||
            profile.stage_b_core.scan_end_pc != 32'h000e3f24 ||
            !profile.stage_b_core.scan_variant_b ||
            profile.stage_b_core.scan_dual_chip ||
            profile.stage_b_core.scan_trace_hash != 64'h7c3088bd1d4eea6f ||
            profile.stage_b_core.scan_first256_trace_hash != 64'h155cbbc09e7b636b ||
            profile.stage_b_core.scan_descriptor_a_count != 4 ||
            profile.stage_b_core.scan_descriptor_b_count != 3)
            $fatal(1, "Olga upload-to-scan acceptance mismatch");
        if (!title_valid || directory_length != 18 || basename_length != 14)
            $fatal(1, "Olga title metadata mismatch");
        title_read_addr = 0; #1;
        if (title_read_data != "D") $fatal(1, "Olga directory first byte");
        title_read_addr = 32; #1;
        if (title_read_data != "0") $fatal(1, "Olga basename first byte");
        repeat (20) @(posedge clk);
        if (file_read_request || profile.stage_b_core.adapter_outstanding ||
            read_pending ||
            profile.stage_b_core.ddr_accept_count !=
                profile.stage_b_core.ddr_response_count ||
            read_count != profile.stage_b_core.ddr_accept_count ||
            enable_rises != 0)
            $fatal(1, "post-scan DDR quiescence/accounting");
        $display("OLGA_UPLOAD_RESULT PASS physical=%0d original=%0d writes=%0d ddr_reads=%0d commands=%0d trace=%016x",
                 uploaded_physical_size,
                 profile.stage_b_core.exact_original_size,
                 write_bytes, read_count,
                 profile.stage_b_core.scan_command_count,
                 profile.stage_b_core.scan_trace_hash);
        $finish;
    end
endmodule
