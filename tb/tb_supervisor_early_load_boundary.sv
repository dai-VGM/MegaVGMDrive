`timescale 1ns/1ps

module tb_supervisor_early_load_boundary;
    localparam int FILE_SIZE = 132;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic title_reset = 1'b1;
    logic backend_reset = 1'b1;
    logic ioctl_download = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [31:0] ioctl_addr = 32'd0;
    logic [7:0] ioctl_dout = 8'd0;
    logic [15:0] ioctl_index = 16'd1;
    wire ioctl_wait;

    wire title_valid;
    logic [6:0] title_read_addr = 7'd0;
    wire [7:0] title_read_data;
    wire title_metadata_busy;

    wire load_busy;
    wire load_done;
    wire load_done_pulse;
    wire play_ready_pulse;
    wire load_error;
    wire overflow_error;
    wire [31:0] backend_file_size;
    wire [31:0] backend_magic;

    logic ioctl_download_d = 1'b0;
    logic [31:0] playback_session = 32'd0;
    integer load_begin_count = 0;
    integer backend_accept_count = 0;
    integer play_ready_count = 0;
    integer status_pulse_count = 0;

    wire [127:0] exported_status;
    wire status_set;
    wire [31:0] exported_session;
    wire [2:0] exported_state;
    wire [7:0] exported_error;
    wire exported_loop_valid;
    wire [15:0] exported_loop_count;

    byte file_bytes [0:FILE_SIZE-1];

    megavgm_title_receiver #(.FILE_INDEX(16'd1)) title_receiver (
        .clk(clk),
        .reset(title_reset),
        .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr[26:0]),
        .ioctl_dout(ioctl_dout),
        .ioctl_index(ioctl_index),
        .title_valid(title_valid),
        .directory_length(),
        .basename_length(),
        .title_read_addr(title_read_addr),
        .title_read_data(title_read_data),
        .metadata_busy(title_metadata_busy)
    );

    vgm_ddram_backend #(
        .ADDR_WIDTH(12),
        .FILE_INDEX(8'd1),
        .WRITE_FIFO_DEPTH(64)
    ) ddram_backend (
        .clk(clk),
        .reset(backend_reset),
        .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout),
        .ioctl_index(ioctl_index[7:0]),
        .ioctl_wait(ioctl_wait),
        .mem_rd_req(1'b0),
        .mem_rd_addr('0),
        .mem_rd_ready(),
        .mem_rd_valid(),
        .mem_rd_data(),
        .segapcm_copy_wr_req(1'b0),
        .segapcm_copy_wr_ready(),
        .segapcm_copy_wr_addr('0),
        .segapcm_copy_wr_data('0),
        .segapcm_copy_flush_req(1'b0),
        .segapcm_copy_flush_done(),
        .segapcm_copy_accept_count_debug(),
        .segapcm_copy_write_count_debug(),
        .segapcm_copy_fifo_debug(),
        .segapcm_copy_ready_debug(),
        .segapcm_copy_write_req_debug(),
        .segapcm_copy_word_debug(),
        .segapcm_copy_flush_debug(),
        .segapcm_copy_full_detect_count_debug(),
        .segapcm_copy_push_req_count_debug(),
        .segapcm_copy_push_fire_count_debug(),
        .segapcm_copy_fifo_push_count_debug(),
        .segapcm_copy_pack_ready_debug(),
        .segapcm_copy_post_push_debug(),
        .segapcm_read_gate_debug(),
        .segapcm_read_after_copy_count_debug(),
        .load_busy(load_busy),
        .load_done(load_done),
        .load_done_pulse(load_done_pulse),
        .play_ready_pulse(play_ready_pulse),
        .load_error(load_error),
        .overflow_error(overflow_error),
        .file_size(backend_file_size),
        .magic_debug(backend_magic),
        .ddram_busy(1'b0),
        .ddram_burstcnt(),
        .ddram_addr(),
        .ddram_dout(64'd0),
        .ddram_dout_ready(1'b0),
        .ddram_rd(),
        .ddram_din(),
        .ddram_be(),
        .ddram_we()
    );

    // This is the corrected Supervisor readiness contract: the initial valid
    // status record is held back by the same reset as the playback backend.
    megavgm_playlist_status_export playlist_status_export (
        .clk(clk),
        .reset(backend_reset),
        .hps_status(128'd0),
        .playback_session_id(playback_session),
        .vgm_load_busy(load_busy),
        .player_busy(1'b0),
        .player_done(1'b0),
        .done_session_id(32'd0),
        .vgm_load_error(load_error),
        .vgm_load_overflow(overflow_error),
        .vgm_player_error(1'b0),
        .vgm_player_error_code(8'd0),
        .error_session_id(32'd0),
        .player_loop_valid(1'b0),
        .player_loop_jump_pulse(1'b0),
        .status_in(exported_status),
        .status_set(status_set),
        .exported_session_id(exported_session),
        .exported_state(exported_state),
        .exported_error_code(exported_error),
        .exported_loop_valid(exported_loop_valid),
        .exported_loop_count(exported_loop_count)
    );

    // Exact mode-5 load/session edge contract, with the same extended reset
    // that owns the real md_sound instance.
    always_ff @(posedge clk) begin
        if (backend_reset) begin
            ioctl_download_d <= 1'b0;
            playback_session <= 32'd0;
            load_begin_count <= 0;
        end else begin
            ioctl_download_d <= ioctl_download;
            if (ioctl_download && !ioctl_download_d &&
                (ioctl_index == 16'd1)) begin
                playback_session <= playback_session + 32'd1;
                load_begin_count <= load_begin_count + 1;
            end
        end

        if (!backend_reset && ddram_backend.accept_wr)
            backend_accept_count <= backend_accept_count + 1;
        if (!backend_reset && play_ready_pulse)
            play_ready_count <= play_ready_count + 1;
        if (status_set)
            status_pulse_count <= status_pulse_count + 1;
    end

    task automatic send_file;
        integer i;
        begin
            ioctl_index <= 16'd1;
            ioctl_download <= 1'b1;
            @(posedge clk);
            for (i = 0; i < FILE_SIZE; i = i + 1) begin
                while (ioctl_wait) @(posedge clk);
                ioctl_addr <= i;
                ioctl_dout <= file_bytes[i];
                ioctl_wr <= 1'b1;
                @(posedge clk);
                ioctl_wr <= 1'b0;
                @(posedge clk);
            end
            ioctl_download <= 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic wait_cycles(input integer count);
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) @(posedge clk);
        end
    endtask

    integer i;
    integer early_title;
    initial begin
        for (i = 0; i < FILE_SIZE; i = i + 1) file_bytes[i] = 8'd0;
        file_bytes[0] = "V";
        file_bytes[1] = "g";
        file_bytes[2] = "m";
        file_bytes[3] = " ";
        file_bytes[4] = 8'h4d;
        file_bytes[5] = 8'h56;
        file_bytes[6] = 8'h47;
        file_bytes[7] = 8'h4d;
        file_bytes[8] = 8'h54;
        file_bytes[9] = 8'h54;
        file_bytes[10] = 8'h4c;
        file_bytes[11] = 8'h00;
        file_bytes[12] = 8'd1;
        file_bytes[13] = 8'h02;
        file_bytes[14] = 8'd0;
        file_bytes[15] = 8'd4;
        file_bytes[16] = 8'h80;
        file_bytes[20] = 8'd4;
        file_bytes[68] = "T";
        file_bytes[69] = "e";
        file_bytes[70] = "s";
        file_bytes[71] = "t";

        wait_cycles(4);
        title_reset <= 1'b0;

        // Supervisor path: status/title domain is live, md_sound/backend is
        // still in the 2^24-cycle post-core-load reset hold.
        send_file();
        wait_cycles(150);
        early_title = title_valid;
        if (!early_title || backend_accept_count != 0 || load_begin_count != 0 ||
            play_ready_count != 0 || playback_session != 0 || backend_file_size != 0)
            $fatal(1, "early-load boundary mismatch title=%0d accept=%0d begin=%0d ready=%0d session=%0d size=%0d",
                early_title, backend_accept_count, load_begin_count,
                play_ready_count, playback_session, backend_file_size);
        if (status_pulse_count != 0)
            $fatal(1, "readiness status escaped backend reset count=%0d",
                status_pulse_count);

        // Manual OSD path: the identical stream arrives after the extended
        // backend reset hold has completed.
        backend_reset <= 1'b0;
        wait_cycles(4);
        if (status_pulse_count == 0 || exported_status[127:120] != 8'h4d ||
            exported_status[119:116] != 4'd2 || exported_state != 3'd0)
            $fatal(1, "status readiness missing count=%0d record=%016h state=%0d",
                status_pulse_count, exported_status[127:64], exported_state);
        send_file();
        wait_cycles(200);
		if (!title_valid || backend_accept_count != FILE_SIZE ||
		    load_begin_count != 1 || play_ready_count != 1 ||
		    playback_session != 1 || !load_done ||
		    backend_file_size != FILE_SIZE)
            $fatal(1, "manual-load boundary mismatch title=%0d accept=%0d begin=%0d ready=%0d session=%0d done=%0d size=%0d magic=%08h",
                title_valid, backend_accept_count, load_begin_count,
                play_ready_count, playback_session, load_done,
                backend_file_size, backend_magic);

        $display("SCRIPTED title_bytes_seen=%0d backend_bytes_accepted=%0d load_completion=%0d play_ready_pulse=%0d session_increment=%0d",
            early_title, 0, 0, 0, 0);
        $display("MANUAL title_bytes_seen=%0d backend_bytes_accepted=%0d load_completion=%0d play_ready_pulse=%0d session_increment=%0d",
            title_valid, backend_accept_count, load_done,
            play_ready_count, playback_session);
        $display("READINESS status_during_backend_reset=0 status_after_release=1");
        $display("PASS tb_supervisor_early_load_boundary");
        $finish;
    end
endmodule
