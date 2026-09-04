`timescale 1ns/1ps

module tb_supervisor_actual_load_ready;
    localparam int FILE_SIZE = 132;
    localparam int POR_CYCLES = 1000;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic vgm_reset = 1'b1;
    logic ioctl_download = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [26:0] ioctl_addr = 27'd0;
    logic [7:0] ioctl_dout = 8'd0;
    logic [15:0] ioctl_index = 16'd1;
    wire ioctl_wait;

    wire mode5_load_ready;
    wire player_busy;
    wire player_done;
    wire vgm_load_busy;
    wire vgm_load_done;
    wire vgm_load_error;
    wire vgm_load_overflow;
    wire [31:0] playback_session;
    wire [31:0] load_begin_count;
    wire [28:0] ddram_addr;
    wire [63:0] ddram_din;
    wire [7:0] ddram_be;
    wire ddram_we;

    wire title_valid;
    wire title_metadata_busy;

    wire [127:0] old_status_record;
    wire old_status_set;
    wire [127:0] fixed_status_record;
    wire fixed_status_set;

    byte file_bytes [0:FILE_SIZE-1];
    integer cycle = 0;
    integer old_status_cycle = -1;
    integer fixed_status_cycle = -1;
    integer load_ready_cycle = -1;
    integer first_start_cycle = -1;
    integer second_start_cycle = -1;
    integer backend_accept_count = 0;
    integer play_ready_count = 0;
    integer first_ready_at_enable = -1;
    integer first_internal_reset_at_enable = -1;
    integer first_wait_at_enable = -1;
    integer first_download_active_after_enable = -1;
    integer second_ready_at_enable = -1;
    integer second_internal_reset_at_enable = -1;
    integer second_wait_at_enable = -1;
    integer second_download_active_after_enable = -1;
    logic [6:0] title_read_addr = 7'd0;

    mister_vgm_md_top #(
        .REGION_MODE(5),
        .VGM_LOAD_ADDR_WIDTH(12),
        .MODE5_VGM_BACKEND(1),
        .POWER_ON_RESET_CYCLES(POR_CYCLES),
        .START_DELAY_CYCLES(0),
        .INIT_AUDIO_SAMPLE_EDGES(0),
        .AUDIO_WARMUP_SAMPLES(0),
        .GATE_TO_START_CYCLES(0),
        .MODE5_SOUND_RESET_CYCLES(0),
        .MODE5_AUDIO_UNMUTE_DELAY_CYCLES(0)
    ) md_sound (
        .clk(clk),
        .reset_n(!vgm_reset),
        .audio_lpf_mode(2'd0),
        .audio_gain_boost(1'b0),
        .audio_psg_level(2'd0),
        .player_busy(player_busy),
        .player_done(player_done),
        .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout),
        .ioctl_index(ioctl_index),
        .ioctl_wait(ioctl_wait),
        .mode5_load_ready(mode5_load_ready),
        .vgm_load_busy(vgm_load_busy),
        .vgm_load_done(vgm_load_done),
        .vgm_load_error(vgm_load_error),
        .vgm_load_overflow(vgm_load_overflow),
        .mode5_playback_session_id(playback_session),
        .mode5_load_begin_count(load_begin_count),
        .ddram_busy(1'b0),
        .ddram_addr(ddram_addr),
        .ddram_dout(64'd0),
        .ddram_dout_ready(1'b0),
        .ddram_din(ddram_din),
        .ddram_be(ddram_be),
        .ddram_we(ddram_we)
    );

    megavgm_title_receiver #(.FILE_INDEX(16'd1)) title_receiver (
        .clk(clk),
        .reset(vgm_reset),
        .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout),
        .ioctl_index(ioctl_index),
        .title_valid(title_valid),
        .directory_length(),
        .basename_length(),
        .title_read_addr(title_read_addr),
        .title_read_data(),
        .metadata_busy(title_metadata_busy)
    );

    // d3f53b6 contract: outer VGM reset only.
    megavgm_playlist_status_export old_status_export (
        .clk(clk), .reset(vgm_reset), .hps_status(128'd0),
        .playback_session_id(playback_session),
        .vgm_load_busy(vgm_load_busy), .player_busy(player_busy),
        .player_done(player_done), .done_session_id(32'd0),
        .vgm_load_error(vgm_load_error),
        .vgm_load_overflow(vgm_load_overflow),
        .vgm_player_error(1'b0), .vgm_player_error_code(8'd0),
        .error_session_id(32'd0), .player_loop_valid(1'b0),
        .player_loop_boundary_pulse(1'b0), .status_in(old_status_record),
        .status_set(old_status_set), .exported_session_id(),
        .exported_state(), .exported_error_code(),
        .exported_loop_valid(), .exported_loop_count()
    );

    // Correct contract: status remains invalid until the actual mode-5
    // acceptance logic and selected backend have left their internal reset.
    megavgm_playlist_status_export fixed_status_export (
        .clk(clk), .reset(vgm_reset | !mode5_load_ready),
        .hps_status(128'd0), .playback_session_id(playback_session),
        .vgm_load_busy(vgm_load_busy), .player_busy(player_busy),
        .player_done(player_done), .done_session_id(32'd0),
        .vgm_load_error(vgm_load_error),
        .vgm_load_overflow(vgm_load_overflow),
        .vgm_player_error(1'b0), .vgm_player_error_code(8'd0),
        .error_session_id(32'd0), .player_loop_valid(1'b0),
        .player_loop_boundary_pulse(1'b0), .status_in(fixed_status_record),
        .status_set(fixed_status_set), .exported_session_id(),
        .exported_state(), .exported_error_code(),
        .exported_loop_valid(), .exported_loop_count()
    );

    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (old_status_set && old_status_cycle < 0)
            old_status_cycle <= cycle;
        if (fixed_status_set && fixed_status_cycle < 0)
            fixed_status_cycle <= cycle;
        if (mode5_load_ready && load_ready_cycle < 0)
            load_ready_cycle <= cycle;
        if (md_sound.loaded_vgm_mode.backend_ddram.ddram_backend.accept_wr)
            backend_accept_count <= backend_accept_count + 1;
        if (md_sound.loaded_vgm_mode.play_ready_pulse)
            play_ready_count <= play_ready_count + 1;
    end

    task automatic send_file(input bit first_transfer);
        integer i;
        begin
            @(negedge clk);
            if (first_transfer)
                first_start_cycle = cycle;
            else
                second_start_cycle = cycle;
            ioctl_download = 1'b1;
            // FIO_FILE_TX(enable) is a separate SPI command from the first
            // FIO_FILE_TX_DAT byte.
            @(posedge clk);
            @(negedge clk);
            if (first_transfer) begin
                first_ready_at_enable = mode5_load_ready;
                first_internal_reset_at_enable = md_sound.reset;
                first_wait_at_enable = ioctl_wait;
                first_download_active_after_enable =
                    md_sound.loaded_vgm_mode.backend_ddram.ddram_backend.download_active;
            end else begin
                second_ready_at_enable = mode5_load_ready;
                second_internal_reset_at_enable = md_sound.reset;
                second_wait_at_enable = ioctl_wait;
                second_download_active_after_enable =
                    md_sound.loaded_vgm_mode.backend_ddram.ddram_backend.download_active;
            end
            for (i = 0; i < FILE_SIZE; i = i + 1) begin
                while (ioctl_wait) @(negedge clk);
                ioctl_addr = i;
                ioctl_dout = file_bytes[i];
                ioctl_wr = 1'b1;
                @(posedge clk);
                @(negedge clk);
                ioctl_wr = 1'b0;
                @(posedge clk);
            end
            @(negedge clk);
            ioctl_download = 1'b0;
            @(posedge clk);
        end
    endtask

    integer i;
    integer timeout;
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
        file_bytes[15] = 8'd4;
        file_bytes[16] = 8'h80;
        file_bytes[20] = 8'd4;
        file_bytes[68] = "T";
        file_bytes[69] = "e";
        file_bytes[70] = "s";
        file_bytes[71] = "t";

        repeat (4) @(posedge clk);
        vgm_reset = 1'b0;

        wait (old_status_set);
        @(posedge clk); // hps_io captures status_in on this rising edge.
        send_file(1'b1);
        wait (!title_metadata_busy);
        repeat (140) @(posedge clk);

        if (!title_valid || mode5_load_ready || backend_accept_count != 0 ||
            load_begin_count != 0 || playback_session != 0 ||
            play_ready_count != 0 || vgm_load_done)
            $fatal(1, "old readiness did not reproduce first-load loss title=%0d ready=%0d accept=%0d begin=%0d session=%0d play_ready=%0d done=%0d",
                title_valid, mode5_load_ready, backend_accept_count,
                load_begin_count, playback_session, play_ready_count,
                vgm_load_done);

        wait (mode5_load_ready);
        wait (fixed_status_set);
        @(posedge clk); // hps_io captures status_in on this rising edge.
        send_file(1'b0);

        timeout = 0;
        while (!vgm_load_done && timeout < 2000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        repeat (2) @(posedge clk);

        if (!vgm_load_done || backend_accept_count != FILE_SIZE ||
            load_begin_count != 1 || playback_session != 1 ||
            play_ready_count != 1 || vgm_load_error || vgm_load_overflow)
            $fatal(1, "actual readiness load failed accept=%0d begin=%0d session=%0d play_ready=%0d done=%0d error=%0d overflow=%0d",
                backend_accept_count, load_begin_count, playback_session,
                play_ready_count, vgm_load_done, vgm_load_error,
                vgm_load_overflow);

        $display("OLD status_publish_cycle=%0d external_valid_cycle=%0d fio_enable_cycle=%0d delta=%0d ready=%0d internal_reset=%0d ioctl_wait=%0d download_active=%0d accepted=0 blocking=internal_reset",
            old_status_cycle, old_status_cycle + 1, first_start_cycle,
            first_start_cycle - (old_status_cycle + 1),
            first_ready_at_enable, first_internal_reset_at_enable,
            first_wait_at_enable, first_download_active_after_enable);
        $display("ACTUAL load_ready_cycle=%0d status_publish_cycle=%0d external_valid_cycle=%0d fio_enable_cycle=%0d ready=%0d internal_reset=%0d ioctl_wait=%0d download_active=%0d accepted=%0d",
            load_ready_cycle, fixed_status_cycle, fixed_status_cycle + 1,
            second_start_cycle, second_ready_at_enable,
            second_internal_reset_at_enable, second_wait_at_enable,
            second_download_active_after_enable, backend_accept_count);
        $display("PASS tb_supervisor_actual_load_ready");
        $finish;
    end
endmodule
