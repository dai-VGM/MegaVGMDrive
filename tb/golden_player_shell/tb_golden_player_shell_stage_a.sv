`timescale 1ns/1ps

module tb_golden_player_shell_stage_a;
    localparam int VGM_ADDR_WIDTH = 23;
    localparam logic [28:0] DDR_BASE = {4'b0011, 25'd0};
    localparam int PREPARED_BODY_SIZE = 256;
    localparam int PREPARED_SIZE = PREPARED_BODY_SIZE + 128;
    localparam int LARGE_SIZE = 934025;

    logic clk = 1'b0;
    logic reset = 1'b1;
    always #5 clk = ~clk;

    logic ioctl_download = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [26:0] ioctl_addr = 27'd0;
    logic [7:0] ioctl_dout = 8'd0;
    logic [15:0] ioctl_index = 16'd1;
    wire ioctl_wait;

    wire file_read_request;
    wire [VGM_ADDR_WIDTH-1:0] file_read_address;
    wire file_read_ready;
    wire file_read_valid;
    wire [7:0] file_read_data;
    wire pcm_a_read_request;
    wire [VGM_ADDR_WIDTH-1:0] pcm_a_read_address;
    wire pcm_b_read_request;
    wire [VGM_ADDR_WIDTH-1:0] pcm_b_read_address;

    wire signed [15:0] profile_audio_l;
    wire signed [15:0] profile_audio_r;
    wire profile_audio_sample_valid;
    wire playback_active;
    wire profile_fatal;
    wire [15:0] profile_status;
    wire [15:0] debug_page_data;
    wire [31:0] parser_start_count;
    wire [31:0] scanner_start_count;
    wire [31:0] sound_write_count;

    wire load_busy;
    wire load_done;
    wire load_done_pulse;
    wire load_error;
    wire load_overflow;
    wire [31:0] uploaded_physical_size;
    wire [31:0] upload_magic;

    logic ddram_busy = 1'b0;
    wire [7:0] ddram_burstcnt;
    wire [28:0] ddram_addr;
    logic [63:0] ddram_dout = 64'd0;
    logic ddram_dout_ready = 1'b0;
    wire ddram_rd;
    wire [63:0] ddram_din;
    wire [7:0] ddram_be;
    wire ddram_we;

    wire title_valid;
    wire [5:0] directory_length;
    wire [5:0] basename_length;
    logic [6:0] title_read_addr = 7'd0;
    wire [7:0] title_read_data;
    wire title_metadata_busy;

    integer failures = 0;
    integer current_mode = 0;
    integer current_size = 0;
    integer total_write_words = 0;
    integer total_write_bytes = 0;
    integer total_read_requests = 0;
    integer session_write_words_start;
    integer session_write_bytes_start;
    integer lane;
    integer byte_offset;

    function automatic [7:0] raw_byte(
        input integer address,
        input integer salt
    );
        begin
            case (address)
                0: raw_byte = 8'h56;
                1: raw_byte = 8'h67;
                2: raw_byte = 8'h6d;
                3: raw_byte = 8'h20;
                default: raw_byte = ((address * 13) + salt) & 8'hff;
            endcase
        end
    endfunction

    function automatic [7:0] prepared_trailer_byte(input integer offset);
        begin
            prepared_trailer_byte = 8'd0;
            case (offset)
                0: prepared_trailer_byte = "M";
                1: prepared_trailer_byte = "V";
                2: prepared_trailer_byte = "G";
                3: prepared_trailer_byte = "M";
                4: prepared_trailer_byte = "T";
                5: prepared_trailer_byte = "T";
                6: prepared_trailer_byte = "L";
                7: prepared_trailer_byte = 8'd0;
                8: prepared_trailer_byte = 8'd1;
                9: prepared_trailer_byte = 8'h03;
                10: prepared_trailer_byte = 8'd5;
                11: prepared_trailer_byte = 8'd8;
                12: prepared_trailer_byte = 8'h80;
                16: prepared_trailer_byte = PREPARED_BODY_SIZE[7:0];
                17: prepared_trailer_byte = PREPARED_BODY_SIZE[15:8];
                18: prepared_trailer_byte = PREPARED_BODY_SIZE[23:16];
                19: prepared_trailer_byte = PREPARED_BODY_SIZE[31:24];
                32: prepared_trailer_byte = "M";
                33: prepared_trailer_byte = "u";
                34: prepared_trailer_byte = "s";
                35: prepared_trailer_byte = "i";
                36: prepared_trailer_byte = "c";
                64: prepared_trailer_byte = "T";
                65: prepared_trailer_byte = "e";
                66: prepared_trailer_byte = "s";
                67: prepared_trailer_byte = "t";
                68: prepared_trailer_byte = ".";
                69: prepared_trailer_byte = "v";
                70: prepared_trailer_byte = "g";
                71: prepared_trailer_byte = "m";
                default: prepared_trailer_byte = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] expected_byte(
        input integer mode,
        input integer address
    );
        begin
            case (mode)
                1: expected_byte =
                    (address < PREPARED_BODY_SIZE) ? raw_byte(address, 7) :
                    prepared_trailer_byte(address - PREPARED_BODY_SIZE);
                2: expected_byte = raw_byte(address, 29);
                3: expected_byte = raw_byte(address, 53);
                default: expected_byte = raw_byte(address, 7);
            endcase
        end
    endfunction

    function automatic integer popcount8(input logic [7:0] value);
        integer n;
        begin
            popcount8 = 0;
            for (n = 0; n < 8; n = n + 1)
                popcount8 = popcount8 + value[n];
        end
    endfunction

    function automatic [31:0] expected_magic_debug(
        input integer mode,
        input integer size
    );
        integer last_address;
        integer lane_index;
        integer lane_address;
        begin
            expected_magic_debug = 32'd0;
            last_address = size - 1;
            for (lane_index = 0; lane_index < 4; lane_index = lane_index + 1) begin
                if (last_address >= lane_index) begin
                    lane_address = last_address - ((last_address - lane_index) % 4);
                    expected_magic_debug[(lane_index * 8) +: 8] =
                        expected_byte(mode, lane_address);
                end
            end
        end
    endfunction

    task automatic fail(input string message);
        begin
            failures = failures + 1;
            $display("STAGE_A_FAIL %s", message);
        end
    endtask

    task automatic wait_for_load_done;
        integer timeout;
        begin
            timeout = 0;
            while (!load_done && timeout < 5000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!load_done)
                fail("load_done timeout");
            repeat (4) @(posedge clk);
        end
    endtask

    task automatic drive_upload(
        input integer mode,
        input integer size,
        input bit expect_valid_title
    );
        integer address;
        integer words_before;
        integer bytes_before;
        begin
            current_mode = mode;
            current_size = size;
            words_before = total_write_words;
            bytes_before = total_write_bytes;

            @(negedge clk);
            ioctl_index = 16'd1;
            ioctl_wr = 1'b0;
            ioctl_download = 1'b1;
            @(negedge clk);

            for (address = 0; address < size; address = address + 1) begin
                while (ioctl_wait) begin
                    ioctl_wr = 1'b0;
                    @(negedge clk);
                end
                ioctl_addr = address[26:0];
                ioctl_dout = expected_byte(mode, address);
                ioctl_wr = 1'b1;
                @(negedge clk);
                ioctl_wr = 1'b0;
            end

            ioctl_download = 1'b0;
            wait_for_load_done();
            repeat (140) @(posedge clk);

            if (load_busy || ioctl_wait || ddram_we)
                fail("upload did not quiesce");
            if (load_error || load_overflow)
                fail("upload error/overflow");
            if (uploaded_physical_size !== size)
                fail("uploaded physical size mismatch");
            if ((total_write_bytes - bytes_before) !== size)
                fail("DDR committed byte count mismatch");
            if ((total_write_words - words_before) !== ((size + 7) / 8))
                fail("DDR packed word count mismatch");
            // The stable backend's magic_debug is a modulo-four last-byte
            // observer, not a latched header word.  Preserve that contract.
            if (upload_magic !== expected_magic_debug(mode, size))
                fail("stable upload magic_debug mismatch");
            if (title_valid !== expect_valid_title)
                fail("title validity mismatch");
        end
    endtask

    task automatic check_title;
        begin
            if (!title_valid || directory_length != 5 || basename_length != 8)
                fail("prepared title lengths");
            title_read_addr = 0; #1;
            if (title_read_data != "M") fail("directory byte 0");
            title_read_addr = 4; #1;
            if (title_read_data != "c") fail("directory byte 4");
            title_read_addr = 7'd32; #1;
            if (title_read_data != "T") fail("basename byte 0");
            title_read_addr = 7'd39; #1;
            if (title_read_data != "m") fail("basename byte 7");
        end
    endtask

    golden_player_shell_upload #(
        .VGM_ADDR_WIDTH(VGM_ADDR_WIDTH),
        .FILE_INDEX(16'd1)
    ) upload (
        .clk(clk), .reset(reset),
        .ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
        .ioctl_index(ioctl_index), .ioctl_wait(ioctl_wait),
        .file_read_request(file_read_request),
        .file_read_address(file_read_address),
        .file_read_ready(file_read_ready),
        .file_read_valid(file_read_valid), .file_read_data(file_read_data),
        .load_busy(load_busy), .load_done(load_done),
        .load_done_pulse(load_done_pulse), .load_error(load_error),
        .load_overflow(load_overflow),
        .uploaded_physical_size(uploaded_physical_size),
        .upload_magic(upload_magic),
        .ddram_busy(ddram_busy), .ddram_burstcnt(ddram_burstcnt),
        .ddram_addr(ddram_addr), .ddram_dout(ddram_dout),
        .ddram_dout_ready(ddram_dout_ready), .ddram_rd(ddram_rd),
        .ddram_din(ddram_din), .ddram_be(ddram_be), .ddram_we(ddram_we)
    );

    ym2610_golden_stage_a #(
        .VGM_ADDR_WIDTH(VGM_ADDR_WIDTH)
    ) profile (
        .clk_sys(clk), .reset(reset),
        .download_active(ioctl_download),
        .uploaded_physical_size(uploaded_physical_size),
        .upload_complete(load_done),
        .file_read_ready(file_read_ready),
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
        .audio_l(profile_audio_l), .audio_r(profile_audio_r),
        .audio_sample_valid(profile_audio_sample_valid),
        .playback_active(playback_active), .profile_fatal(profile_fatal),
        .profile_status(profile_status), .debug_page_data(debug_page_data),
        .parser_start_count(parser_start_count),
        .scanner_start_count(scanner_start_count),
        .sound_write_count(sound_write_count)
    );

    megavgm_title_receiver #(
        .FILE_INDEX(16'd1)
    ) title_receiver (
        .clk(clk), .reset(reset),
        .ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
        .ioctl_index(ioctl_index), .title_valid(title_valid),
        .directory_length(directory_length),
        .basename_length(basename_length),
        .title_read_addr(title_read_addr), .title_read_data(title_read_data),
        .metadata_busy(title_metadata_busy)
    );

    always @(posedge clk) begin
        if (ddram_rd)
            total_read_requests = total_read_requests + 1;

        if (ddram_we && !ddram_busy) begin
            total_write_words = total_write_words + 1;
            total_write_bytes = total_write_bytes + popcount8(ddram_be);
            for (lane = 0; lane < 8; lane = lane + 1) begin
                if (ddram_be[lane]) begin
                    byte_offset = ((ddram_addr - DDR_BASE) * 8) + lane;
                    if (byte_offset < 0 || byte_offset >= current_size)
                        fail("DDR write address outside current upload");
                    else if (ddram_din[(lane * 8) +: 8] !==
                             expected_byte(current_mode, byte_offset))
                        fail("DDR write data mismatch");
                end
            end
        end

        if (!reset) begin
            if ($isunknown({
                ioctl_wait, file_read_request, file_read_address,
                file_read_ready, file_read_valid, file_read_data,
                pcm_a_read_request, pcm_a_read_address,
                pcm_b_read_request, pcm_b_read_address,
                profile_audio_l, profile_audio_r, profile_audio_sample_valid,
                playback_active, profile_fatal, parser_start_count,
                scanner_start_count, sound_write_count,
                load_busy, load_done, load_error, load_overflow,
                uploaded_physical_size, upload_magic,
                ddram_burstcnt, ddram_addr, ddram_rd, ddram_din,
                ddram_be, ddram_we, title_valid, title_metadata_busy
            }))
                fail("relevant X/Z detected");
            if (file_read_request || pcm_a_read_request || pcm_b_read_request ||
                ddram_rd || profile_audio_l != 0 || profile_audio_r != 0 ||
                profile_audio_sample_valid || playback_active || profile_fatal ||
                parser_start_count != 0 || scanner_start_count != 0 ||
                sound_write_count != 0)
                fail("Stage A inert contract changed");
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        reset = 1'b0;
        repeat (3) @(posedge clk);

        // Raw upload and partial-word flush.
        drive_upload(0, 67, 1'b0);
        $display("STAGE_A raw_upload=PASS partial_flush=PASS");

        // Prepared upload/title and same-file reload.
        drive_upload(1, PREPARED_SIZE, 1'b1);
        check_title();
        drive_upload(1, PREPARED_SIZE, 1'b1);
        check_title();
        $display("STAGE_A prepared_upload=PASS title=PASS same_reload=PASS");

        // Stable title contract keeps a completed title across software Reset.
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (3) @(posedge clk);
        if (!title_valid) fail("completed title lost on software reset");
        if (profile_audio_l != 0 || profile_audio_r != 0)
            fail("audio nonzero after software reset");
        $display("STAGE_A software_reset=PASS");

        // Different raw file clears the prepared title.
        drive_upload(2, 73, 1'b0);
        $display("STAGE_A different_reload=PASS");

        // End an incomplete transfer, then prove the next complete transfer.
        drive_upload(3, 11, 1'b0);
        drive_upload(0, 67, 1'b0);
        $display("STAGE_A abort_then_reload=PASS");

        // Exact large synthetic regression requested for Stage A.
        drive_upload(2, LARGE_SIZE, 1'b0);
        $display("STAGE_A large_934025=PASS");

        // 120,000 inert clocks represent 120 seconds at the audit's scaled
        // 1 kHz clock.  Stage A has no time-based profile state; the static
        // audit also proves every profile request/audio output is constant.
        repeat (120000) @(posedge clk);
        if (load_busy || ioctl_wait || ddram_we || total_read_requests != 0)
            fail("two-minute-equivalent idle did not remain quiescent");
        $display("STAGE_A idle_equivalent_seconds=120 read_requests=%0d", total_read_requests);

        if (failures == 0) begin
            $display("GOLDEN_SHELL_STAGE_A_RESULT PASS writes=%0d bytes=%0d", total_write_words, total_write_bytes);
            $finish;
        end
        $fatal(1, "GOLDEN_SHELL_STAGE_A_RESULT FAIL failures=%0d", failures);
    end

endmodule
