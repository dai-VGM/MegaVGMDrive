`timescale 1ns/1ps

module tb_mode5_load_while_playing_session;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic ioctl_download = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [26:0] ioctl_addr = 27'd0;
    logic [7:0] ioctl_dout = 8'd0;
    logic [15:0] ioctl_index = 16'd1;

    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire audio_sample_valid;
    wire player_busy;
    wire player_done;
    wire startup_reset_active;
    wire startup_waiting;
    wire startup_done;
    wire audio_gate_open;
    wire audio_muted;
    wire vgm_load_busy;
    wire vgm_load_done;
    wire vgm_load_error;
    wire vgm_load_overflow;
    wire vgm_header_valid;
    wire vgm_player_error;
    wire mode5_sound_reset_active;
    wire mode5_player_start_pulse_debug;
    wire [31:0] mode5_load_begin_count;
    wire [31:0] mode5_load_done_edge_count;
    wire [31:0] mode5_sound_reset_start_count;
    wire [31:0] mode5_player_start_count;
    wire [31:0] mode5_player_reset_count;
    wire [31:0] mode5_playback_session_id;
    wire [31:0] mode5_duplicate_start_blocked_count;
    wire [31:0] mode5_player_end_count;
    wire [31:0] mode5_repeat_restart_count;
    wire [31:0] mode5_done_session_id;
    wire [31:0] mode5_cycles_since_start;
    wire [7:0] mode5_done_pc_debug;
    wire [7:0] mode5_done_cmd_debug;
    logic end_only_file = 1'b0;

    localparam int TEST_TIMEOUT_CYCLES = 100_000;

    always #5 clk = ~clk;

    mister_vgm_md_top #(
        .REGION_MODE                    (5),
        .VGM_LOAD_ADDR_WIDTH            (8),
        .VGM_LOAD_FILE_INDEX            (16'd1),
        .POWER_ON_RESET_CYCLES          (32'd4),
        .START_DELAY_CYCLES             (32'd4),
        .INIT_AUDIO_SAMPLE_EDGES        (16'd0),
        .AUDIO_WARMUP_SAMPLES           (16'd0),
        .GATE_TO_START_CYCLES           (16'd1),
        .CLK_SYS_HZ                     (32'd20_000_000),
        .VGM_WAIT_HZ                    (32'd44_100),
        .REPLAY_ENABLE                  (1'b0),
        .PLAYER_RESET_CYCLES            (32'd8),
        .START_ACCEPT_TIMEOUT_CYCLES    (32'd2000),
        .PLAYER_DONE_TIMEOUT_TICKS      (32'd1000),
        .REPLAY_DELAY_TICKS             (32'd8),
        .MODE5_SOUND_RESET_CYCLES       (32'd8),
        .MODE5_AUDIO_UNMUTE_DELAY_CYCLES(32'd8)
    ) dut (
        .clk                            (clk),
        .reset_n                        (reset_n),
        .audio_l                        (audio_l),
        .audio_r                        (audio_r),
        .audio_sample_valid             (audio_sample_valid),
        .player_busy                    (player_busy),
        .player_done                    (player_done),
        .player_pc_debug                (),
        .player_last_cmd_debug          (),
        .startup_reset_active           (startup_reset_active),
        .startup_waiting                (startup_waiting),
        .startup_done                   (startup_done),
        .audio_gate_open                (audio_gate_open),
        .audio_muted                    (audio_muted),
        .ioctl_download                 (ioctl_download),
        .ioctl_wr                       (ioctl_wr),
        .ioctl_addr                     (ioctl_addr),
        .ioctl_dout                     (ioctl_dout),
        .ioctl_index                    (ioctl_index),
        .vgm_load_busy                  (vgm_load_busy),
        .vgm_load_done                  (vgm_load_done),
        .vgm_load_error                 (vgm_load_error),
        .vgm_load_overflow              (vgm_load_overflow),
        .vgm_header_valid               (vgm_header_valid),
        .vgm_player_error               (vgm_player_error),
        .vgm_unsupported_opcode         (),
        .vgm_unsupported_pc             (),
        .vgm_player_error_code          (),
        .vgm_error_pc_debug            (),
        .vgm_error_cmd_debug           (),
        .vgm_error_session_id          (),
        .vgm_player_state_debug        (),
        .vgm_mem_rd_req_debug          (),
        .vgm_mem_rd_ready_debug        (),
        .vgm_mem_rd_valid_debug        (),
        .vgm_mem_rd_addr_debug         (),
        .vgm_load_size                  (),
        .vgm_load_magic                 (),
        .vgm_data_start_debug           (),
        .vgm_current_pc_debug           (),
        .vgm_loop_pc_debug              (),
        .vgm_loop_valid_debug           (),
        .vgm_loop_taken_debug           (),
        .vgm_end_command_seen           (),
        .vgm_restarted_from_data_start  (),
        .vgm_pcm_oob                    (),
        .vgm_pcm_oob_count              (),
        .vgm_wait_ticks_consumed_debug  (),
        .mode5_sound_reset_active       (mode5_sound_reset_active),
        .mode5_player_start_pulse_debug (mode5_player_start_pulse_debug),
        .mode5_load_begin_count         (mode5_load_begin_count),
        .mode5_load_done_edge_count     (mode5_load_done_edge_count),
        .mode5_sound_reset_start_count  (mode5_sound_reset_start_count),
        .mode5_player_start_count       (mode5_player_start_count),
        .mode5_player_reset_count       (mode5_player_reset_count),
        .mode5_playback_session_id      (mode5_playback_session_id),
        .mode5_duplicate_start_blocked_count(mode5_duplicate_start_blocked_count),
        .mode5_player_end_count         (mode5_player_end_count),
        .mode5_repeat_restart_count     (mode5_repeat_restart_count),
        .mode5_done_session_id          (mode5_done_session_id),
        .mode5_cycles_since_start       (mode5_cycles_since_start),
        .mode5_done_pc_debug            (mode5_done_pc_debug),
        .mode5_done_cmd_debug           (mode5_done_cmd_debug),
        .fm_adjust_clip_count_l         (),
        .fm_adjust_clip_count_r         (),
        .genmix_wrap_count_l            (),
        .genmix_wrap_count_r            (),
        .ym_write_requested_count       (),
        .ym_write_accepted_count        (),
        .ym_write_dropped_or_busy_count (),
        .ym_port0_count                 (),
        .ym_port1_count                 (),
        .last_ym_port                   (),
        .last_ym_addr                   (),
        .last_ym_data                   (),
        .jt12_cen_interval_1_count      (),
        .jt12_cen_interval_2_count      (),
        .jt12_cen_interval_3_count      (),
        .jt12_cen_interval_4_count      (),
        .jt12_cen_interval_ge5_count    (),
        .jt12_cen_interval_min          (),
        .jt12_cen_interval_max          (),
        .jt12_cen_interval_last         (),
        .fm_raw_abs_peak                (),
        .fm_adjust_abs_peak             (),
        .fm_lpf_abs_peak                (),
        .genmix_abs_peak                (),
        .md_final_audio_abs_peak        ()
    );

    function automatic [7:0] long_wait_vgm_byte(input int addr);
        begin
            unique case (addr)
                0: long_wait_vgm_byte = "V";
                1: long_wait_vgm_byte = "g";
                2: long_wait_vgm_byte = "m";
                3: long_wait_vgm_byte = " ";
                'h34: long_wait_vgm_byte = 8'h0c;
                'h35: long_wait_vgm_byte = 8'h00;
                'h36: long_wait_vgm_byte = 8'h00;
                'h37: long_wait_vgm_byte = 8'h00;
                'h40: long_wait_vgm_byte = end_only_file ? 8'h66 : 8'h61;
                'h41: long_wait_vgm_byte = 8'hff;
                'h42: long_wait_vgm_byte = 8'hff;
                'h43: long_wait_vgm_byte = 8'h66;
                default: long_wait_vgm_byte = 8'h00;
            endcase
        end
    endfunction

    task automatic fail_now(input string label);
        begin
            $display("FAIL %s muted=%0b audio_l=%0d audio_r=%0d busy=%0b done=%0b header=%0b load_busy=%0b load_done=%0b load_error=%0b overflow=%0b player_error=%0b reset_active=%0b start_pulse=%0b begin_count=%0d done_count=%0d reset_count=%0d start_count=%0d player_reset_count=%0d session=%0d dup=%0d end=%0d repeat=%0d done_session=%0d done_pc=%02h done_cmd=%02h cycles=%0d",
                     label, audio_muted, audio_l, audio_r, player_busy,
                     player_done, vgm_header_valid, vgm_load_busy,
                     vgm_load_done, vgm_load_error, vgm_load_overflow,
                     vgm_player_error, mode5_sound_reset_active,
                     mode5_player_start_pulse_debug, mode5_load_begin_count,
                     mode5_load_done_edge_count, mode5_sound_reset_start_count,
                     mode5_player_start_count, mode5_player_reset_count,
                     mode5_playback_session_id,
                     mode5_duplicate_start_blocked_count,
                     mode5_player_end_count,
                     mode5_repeat_restart_count,
                     mode5_done_session_id,
                     mode5_done_pc_debug,
                     mode5_done_cmd_debug,
                     mode5_cycles_since_start);
            $finish;
        end
    endtask

    task automatic assert_silent(input string label);
        begin
            if (!audio_muted || audio_l !== 16'sd0 || audio_r !== 16'sd0) begin
                fail_now(label);
            end
        end
    endtask

    task automatic write_download_byte(input int addr);
        begin
            @(posedge clk);
            ioctl_addr <= addr[26:0];
            ioctl_dout <= long_wait_vgm_byte(addr);
            ioctl_wr <= 1'b1;
            @(posedge clk);
            ioctl_wr <= 1'b0;
        end
    endtask

    task automatic begin_download;
        begin
            @(posedge clk);
            ioctl_index <= 16'd1;
            ioctl_download <= 1'b1;
        end
    endtask

    task automatic finish_download;
        begin
            @(posedge clk);
            ioctl_download <= 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic load_long_wait_vgm;
        int i;
        begin
            begin_download();
            for (i = 0; i <= 'h43; i = i + 1) begin
                write_download_byte(i);
            end
            finish_download();
        end
    endtask

    task automatic wait_for_running(input string label);
        int i;
        begin
            for (i = 0; i < 4096; i = i + 1) begin
                @(posedge clk);
                if (player_busy && vgm_header_valid && !vgm_player_error) begin
                    return;
                end
            end
            fail_now(label);
        end
    endtask

    task automatic wait_for_sound_reset_count(input [31:0] expected);
        int i;
        begin
            for (i = 0; i < 2048; i = i + 1) begin
                @(posedge clk);
                if (mode5_sound_reset_start_count == expected) begin
                    return;
                end
            end
            fail_now("sound reset count");
        end
    endtask

    task automatic wait_for_player_start_count(input [31:0] expected);
        int i;
        begin
            for (i = 0; i < 2048; i = i + 1) begin
                @(posedge clk);
                if (mode5_player_start_count == expected) begin
                    return;
                end
            end
            fail_now("player start count");
        end
    endtask

    task automatic wait_for_player_end_count(input [31:0] expected);
        int i;
        begin
            for (i = 0; i < 4096; i = i + 1) begin
                @(posedge clk);
                if (mode5_player_end_count == expected) begin
                    return;
                end
            end
            fail_now("player end count");
        end
    endtask

    initial begin : watchdog
        repeat (TEST_TIMEOUT_CYCLES) @(posedge clk);
        fail_now("global watchdog");
    end

    initial begin : test
        force dut.audio_gate_open = 1'b1;

        repeat (4) @(posedge clk);
        assert_silent("reset asserted");
        reset_n <= 1'b1;
        repeat (16) @(posedge clk);
        assert_silent("before first load");

        load_long_wait_vgm();
        wait_for_player_start_count(32'd1);
        wait_for_running("first file running");
        if (!player_busy || !vgm_header_valid) begin
            fail_now("first player did not stay busy");
        end

        begin_download();
        @(posedge clk);
        assert_silent("new load begin mutes immediately");
        repeat (4) @(posedge clk);
        if (player_busy || vgm_header_valid) begin
            fail_now("old playback not quiesced");
        end
        if (vgm_player_error) begin
            fail_now("load begin caused player error");
        end
        if (mode5_load_begin_count != 32'd2 ||
            mode5_playback_session_id != 32'd2 ||
            mode5_player_reset_count < 32'd2) begin
            fail_now("load begin counters");
        end

        for (int i = 0; i <= 'h43; i = i + 1) begin
            write_download_byte(i);
            if (vgm_player_error) begin
                fail_now("second load caused player error");
            end
            assert_silent("during second load");
        end
        finish_download();

        wait_for_sound_reset_count(32'd2);
        wait_for_player_start_count(32'd2);
        wait_for_running("second file running");

        repeat (512) begin
            @(posedge clk);
            if (mode5_player_start_count != 32'd2 ||
                mode5_sound_reset_start_count != 32'd2) begin
                fail_now("duplicate start/reset");
            end
        end

        if (vgm_load_error || vgm_load_overflow || vgm_player_error ||
            !player_busy || !vgm_header_valid) begin
            fail_now("final state");
        end

        end_only_file = 1'b1;
        load_long_wait_vgm();
        wait_for_sound_reset_count(32'd3);
        wait_for_player_start_count(32'd3);
        wait_for_player_end_count(32'd1);

        if (!player_done || player_busy || !vgm_header_valid) begin
            fail_now("end counter final state");
        end
        if (mode5_done_session_id != 32'd3 ||
            mode5_done_pc_debug != 8'h40 ||
            mode5_done_cmd_debug != 8'h66) begin
            fail_now("end debug fields");
        end

        repeat (128) @(posedge clk);
        if (mode5_player_start_count != 32'd3 ||
            mode5_sound_reset_start_count != 32'd3 ||
            mode5_repeat_restart_count != 32'd0 ||
            !audio_muted) begin
            fail_now("repeat disabled should stay stopped");
        end

        end_only_file = 1'b0;
        load_long_wait_vgm();
        wait_for_sound_reset_count(32'd4);
        wait_for_player_start_count(32'd4);
        wait_for_running("post-done file B running");

        repeat (2048) begin
            @(posedge clk);
            if (mode5_player_end_count != 32'd1 ||
                mode5_done_session_id != 32'd3 ||
                player_done ||
                !player_busy ||
                mode5_cycles_since_start == 32'd0) begin
                fail_now("stale done terminated file B");
            end
        end

        $display("PASS tb_mode5_load_while_playing_session");
        $finish;
    end

endmodule
