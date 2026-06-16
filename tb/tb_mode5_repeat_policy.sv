`timescale 1ns/1ps

module tb_mode5_repeat_policy;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic ioctl_download = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [26:0] ioctl_addr = 27'd0;
    logic [7:0] ioctl_dout = 8'd0;
    logic [15:0] ioctl_index = 16'd1;

    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire player_busy;
    wire player_done;
    wire audio_muted;
    wire vgm_load_error;
    wire vgm_load_overflow;
    wire vgm_header_valid;
    wire vgm_player_error;
    wire mode5_sound_reset_active;
    wire mode5_player_start_pulse_debug;
    wire [31:0] mode5_sound_reset_start_count;
    wire [31:0] mode5_player_start_count;
    wire [31:0] mode5_player_end_count;
    wire [31:0] mode5_repeat_restart_count;
    wire mode5_done_armed_debug;
    wire [31:0] mode5_playback_session_id;
    wire [31:0] mode5_repeat_session_id;
    wire [31:0] mode5_done_session_id;
    wire [7:0] mode5_done_pc_debug;
    wire [7:0] mode5_done_cmd_debug;

    localparam int TEST_TIMEOUT_CYCLES = 500_000;

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
        .CLK_SYS_HZ                     (32'd88_200),
        .VGM_WAIT_HZ                    (32'd44_100),
        .REPLAY_ENABLE                  (1'b1),
        .PLAYER_RESET_CYCLES            (32'd8),
        .START_ACCEPT_TIMEOUT_CYCLES    (32'd2000),
        .PLAYER_DONE_TIMEOUT_TICKS      (32'd1000),
        .REPLAY_DELAY_TICKS             (32'd8),
        .MODE5_SOUND_RESET_CYCLES       (32'd8),
        .MODE5_AUDIO_UNMUTE_DELAY_CYCLES(32'd8),
        .MODE5_REPEAT_ENABLE            (1'b1)
    ) dut (
        .clk                            (clk),
        .reset_n                        (reset_n),
        .audio_l                        (audio_l),
        .audio_r                        (audio_r),
        .audio_sample_valid             (),
        .audio_lpf_mode                 (2'b00),
        .player_busy                    (player_busy),
        .player_done                    (player_done),
        .player_pc_debug                (),
        .player_last_cmd_debug          (),
        .startup_reset_active           (),
        .startup_waiting                (),
        .startup_done                   (),
        .audio_gate_open                (),
        .audio_muted                    (audio_muted),
        .ioctl_download                 (ioctl_download),
        .ioctl_wr                       (ioctl_wr),
        .ioctl_addr                     (ioctl_addr),
        .ioctl_dout                     (ioctl_dout),
        .ioctl_index                    (ioctl_index),
        .ioctl_wait                     (),
        .vgm_load_busy                  (),
        .vgm_load_done                  (),
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
        .mode5_load_begin_count         (),
        .mode5_load_done_edge_count     (),
        .mode5_sound_reset_start_count  (mode5_sound_reset_start_count),
        .mode5_player_start_count       (mode5_player_start_count),
        .mode5_player_reset_count       (),
        .mode5_playback_session_id      (mode5_playback_session_id),
        .mode5_duplicate_start_blocked_count(),
        .mode5_player_end_count         (mode5_player_end_count),
        .mode5_repeat_restart_count     (mode5_repeat_restart_count),
        .mode5_done_armed_debug         (mode5_done_armed_debug),
        .mode5_repeat_session_id        (mode5_repeat_session_id),
        .mode5_done_session_id          (mode5_done_session_id),
        .mode5_cycles_since_start       (),
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

    function automatic [7:0] short_end_vgm_byte(input int addr);
        begin
            unique case (addr)
                0: short_end_vgm_byte = "V";
                1: short_end_vgm_byte = "g";
                2: short_end_vgm_byte = "m";
                3: short_end_vgm_byte = " ";
                'h18: short_end_vgm_byte = 8'd22;
                'h34: short_end_vgm_byte = 8'h0c;
                'h35: short_end_vgm_byte = 8'h00;
                'h36: short_end_vgm_byte = 8'h00;
                'h37: short_end_vgm_byte = 8'h00;
                'h40: short_end_vgm_byte = 8'h50;
                'h41: short_end_vgm_byte = 8'h80;
                'h42: short_end_vgm_byte = 8'h50;
                'h43: short_end_vgm_byte = 8'h05;
                'h44: short_end_vgm_byte = 8'h50;
                'h45: short_end_vgm_byte = 8'h92;
                'h46: short_end_vgm_byte = 8'h61;
                'h47: short_end_vgm_byte = 8'h08;
                'h48: short_end_vgm_byte = 8'h00;
                'h49: short_end_vgm_byte = 8'h50;
                'h4a: short_end_vgm_byte = 8'h80;
                'h4b: short_end_vgm_byte = 8'h50;
                'h4c: short_end_vgm_byte = 8'h18;
                'h4d: short_end_vgm_byte = 8'h50;
                'h4e: short_end_vgm_byte = 8'h92;
                'h4f: short_end_vgm_byte = 8'h61;
                'h50: short_end_vgm_byte = 8'h0c;
                'h51: short_end_vgm_byte = 8'h00;
                'h52: short_end_vgm_byte = 8'h50;
                'h53: short_end_vgm_byte = 8'h9f;
                'h54: short_end_vgm_byte = 8'h61;
                'h55: short_end_vgm_byte = 8'h02;
                'h56: short_end_vgm_byte = 8'h00;
                'h57: short_end_vgm_byte = 8'h66;
                default: short_end_vgm_byte = 8'h00;
            endcase
        end
    endfunction

    task automatic fail_now(input string label);
        begin
            $display("FAIL %s muted=%0b audio_l=%0d audio_r=%0d busy=%0b done=%0b header=%0b err=%0b overflow=%0b player_error=%0b reset_active=%0b start_pulse=%0b sr=%0d st=%0d end=%0d repeat=%0d armed=%0b session=%0d repeat_session=%0d done_session=%0d done_pc=%02h done_cmd=%02h",
                     label, audio_muted, audio_l, audio_r, player_busy,
                     player_done, vgm_header_valid, vgm_load_error,
                     vgm_load_overflow, vgm_player_error,
                     mode5_sound_reset_active, mode5_player_start_pulse_debug,
                     mode5_sound_reset_start_count, mode5_player_start_count,
                     mode5_player_end_count, mode5_repeat_restart_count,
                     mode5_done_armed_debug, mode5_playback_session_id,
                     mode5_repeat_session_id,
                     mode5_done_session_id, mode5_done_pc_debug,
                     mode5_done_cmd_debug);
            $finish;
        end
    endtask

    task automatic write_download_byte(input int addr);
        begin
            @(posedge clk);
            ioctl_addr <= addr[26:0];
            ioctl_dout <= short_end_vgm_byte(addr);
            ioctl_wr <= 1'b1;
            @(posedge clk);
            ioctl_wr <= 1'b0;
        end
    endtask

    task automatic load_short_end_vgm;
        int i;
        begin
            @(posedge clk);
            ioctl_index <= 16'd1;
            ioctl_download <= 1'b1;
            for (i = 0; i <= 'h57; i = i + 1) begin
                write_download_byte(i);
            end
            @(posedge clk);
            ioctl_download <= 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic wait_count(input string label,
                              input [31:0] expected_st,
                              input [31:0] expected_end,
                              input [31:0] expected_repeat);
        int i;
        begin
            for (i = 0; i < 200000; i = i + 1) begin
                @(posedge clk);
                if (mode5_player_start_count == expected_st &&
                    mode5_player_end_count == expected_end &&
                    mode5_repeat_restart_count == expected_repeat) begin
                    return;
                end
            end
            fail_now(label);
        end
    endtask

    task automatic wait_running(input string label,
                                input [31:0] expected_st,
                                input [31:0] expected_end,
                                input [31:0] expected_repeat,
                                input [31:0] expected_session);
        int i;
        begin
            for (i = 0; i < 200000; i = i + 1) begin
                @(posedge clk);
                if (mode5_player_start_count == expected_st &&
                    mode5_player_end_count == expected_end &&
                    mode5_repeat_restart_count == expected_repeat &&
                    mode5_playback_session_id == expected_session &&
                    player_busy &&
                    !audio_muted &&
                    mode5_done_armed_debug) begin
                    return;
                end
                if (mode5_player_end_count != expected_end) begin
                    fail_now(label);
                end
            end
            fail_now(label);
        end
    endtask

    initial begin : watchdog
        repeat (TEST_TIMEOUT_CYCLES) @(posedge clk);
        fail_now("global watchdog");
    end

    initial begin : test
        force dut.audio_gate_open = 1'b1;
        force dut.loaded_vgm_mode.psg_cmd_ready = 1'b1;
        force dut.loaded_vgm_mode.ym_cmd_ready = 1'b1;

        repeat (4) @(posedge clk);
        reset_n <= 1'b1;
        repeat (16) @(posedge clk);

        load_short_end_vgm();
        wait_count("initial end", 32'd1, 32'd1, 32'd1);
        if (mode5_done_pc_debug != 8'h57 ||
            mode5_done_cmd_debug != 8'h66 ||
            mode5_done_session_id != 32'd1 ||
            mode5_playback_session_id != 32'd2) begin
            fail_now("initial end debug");
        end
        wait_running("first repeat running", 32'd2, 32'd1, 32'd1, 32'd2);
        wait_count("first repeat end", 32'd2, 32'd2, 32'd2);
        if (mode5_done_pc_debug != 8'h57 ||
            mode5_done_cmd_debug != 8'h66 ||
            mode5_done_session_id != 32'd2 ||
            mode5_playback_session_id != 32'd3) begin
            fail_now("repeat end debug");
        end
        wait_running("second repeat running", 32'd3, 32'd2, 32'd2, 32'd3);
        wait_count("second repeat end", 32'd3, 32'd3, 32'd3);
        if (mode5_done_pc_debug != 8'h57 ||
            mode5_done_cmd_debug != 8'h66 ||
            mode5_done_session_id != 32'd3 ||
            mode5_playback_session_id != 32'd4) begin
            fail_now("second repeat end debug");
        end
        wait_running("third repeat running", 32'd4, 32'd3, 32'd3, 32'd4);
        wait_count("third repeat end", 32'd4, 32'd4, 32'd4);
        if (mode5_done_pc_debug != 8'h57 ||
            mode5_done_cmd_debug != 8'h66 ||
            mode5_done_session_id != 32'd4 ||
            mode5_playback_session_id != 32'd5) begin
            fail_now("third repeat end debug");
        end

        if (mode5_sound_reset_start_count < 32'd4 ||
            mode5_done_armed_debug ||
            vgm_load_error || vgm_load_overflow || vgm_player_error) begin
            fail_now("final");
        end

        $display("PASS tb_mode5_repeat_policy");
        $finish;
    end

endmodule
