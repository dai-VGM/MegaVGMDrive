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
    wire ioctl_wait;
    wire vgm_load_busy;
    wire vgm_load_done;
    wire vgm_load_error;
    wire vgm_load_overflow;
    wire vgm_header_valid;
    wire vgm_player_error;
    wire [7:0] vgm_player_error_code;
    wire [31:0] vgm_error_session_id;
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
    logic short_ending_file = 1'b0;
    logic native_loop_file = 1'b0;
    logic short_native_loop = 1'b0;
    logic transition_stress_file = 1'b0;
    wire vgm_loop_taken_debug;
    wire vgm_loop_jump_pulse_debug;
    wire [31:0] vgm_wait_ticks_consumed_debug;
    integer native_loop_count = 0;
    logic [31:0] loop_limit_fade_start_cycles = 32'd0;
    logic enforce_handoff_zero = 1'b0;
    integer handoff_zero_cycles = 0;
`ifdef BASELINE_04910
    wire handoff_audio_valid_observed = 1'b1;
`else
    wire handoff_audio_valid_observed =
        dut.loaded_vgm_mode.mode5_transition_handoff_audio_valid;
`endif

    always @(posedge clk) begin
        if (vgm_loop_jump_pulse_debug)
            native_loop_count <= native_loop_count + 1;
        if (enforce_handoff_zero) begin
            handoff_zero_cycles <= handoff_zero_cycles + 1;
            if (audio_l !== 16'sd0 || audio_r !== 16'sd0) begin
                $display("FAIL transition handoff leaked audio cycle=%0d gain=%0d open=%0b raw_valid=%0b raw_l=%0d raw_r=%0d busy=%0b done=%0b load_busy=%0b reset=%0b session=%0d starts=%0d ends=%0d",
                         handoff_zero_cycles,
                         dut.loaded_vgm_mode.mode5_transition_gain,
                         dut.audio_runtime_open,
                         dut.raw_audio_sample_valid,
                         dut.raw_audio_l,
                         dut.raw_audio_r,
                         player_busy,
                         player_done,
                         vgm_load_busy,
                         mode5_sound_reset_active,
                         mode5_playback_session_id,
                         mode5_player_start_count,
                         mode5_player_end_count);
                $fatal(1);
            end
        end
    end

    wire [127:0] phase1b_status_in;
    wire phase1b_status_set;
    wire [31:0] phase1b_session;
    wire [2:0] phase1b_state;
    wire [7:0] phase1b_error;
    logic [31:0] phase1b_seen_session = 32'd0;
    logic [4:0] phase1b_seen_states = 5'd0;

    megavgm_playlist_status_export phase1b_status (
        .clk(clk),
        .reset(!reset_n),
        .hps_status(128'h0123456789abcdef_fedcba9876543210),
        .playback_session_id(mode5_playback_session_id),
        .vgm_load_busy(vgm_load_busy),
        .player_busy(player_busy),
        .player_done(player_done),
        .done_session_id(mode5_done_session_id),
        .vgm_load_error(vgm_load_error),
        .vgm_load_overflow(vgm_load_overflow),
        .vgm_player_error(vgm_player_error),
        .vgm_player_error_code(vgm_player_error_code),
        .error_session_id(vgm_error_session_id),
        .status_in(phase1b_status_in),
        .status_set(phase1b_status_set),
        .exported_session_id(phase1b_session),
        .exported_state(phase1b_state),
        .exported_error_code(phase1b_error)
    );

    always @(posedge clk) begin
        if (phase1b_status_set) begin
            if (phase1b_status_in[127:120] != 8'h4d ||
                phase1b_status_in[119:112] != 8'd1 ||
                phase1b_status_in[63:0] != 64'hfedcba9876543210) begin
                $display("FAIL Phase 1B record/header/merge %032h",
                         phase1b_status_in);
                $fatal(1);
            end
            if (phase1b_seen_session != phase1b_status_in[111:80]) begin
                phase1b_seen_session <= phase1b_status_in[111:80];
                phase1b_seen_states <=
                    5'b00001 << phase1b_status_in[79:77];
            end else begin
                phase1b_seen_states[phase1b_status_in[79:77]] <= 1'b1;
            end
        end
    end

    localparam int TEST_TIMEOUT_CYCLES = 5_000_000;

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
        .MODE5_AUDIO_UNMUTE_DELAY_CYCLES(32'd8),
        .MODE5_TRACK_FADE_CYCLES        (32'd256),
        .MODE5_LOOP_LIMIT_FADE_SAMPLES  (32'd8)
    ) dut (
        .clk                            (clk),
        .reset_n                        (reset_n),
        .audio_l                        (audio_l),
        .audio_r                        (audio_r),
        .audio_sample_valid             (audio_sample_valid),
        .audio_lpf_mode                 (2'b00),
        .audio_gain_boost               (1'b0),
        .audio_psg_level                (2'b00),
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
        .ioctl_wait                     (ioctl_wait),
        .vgm_load_busy                  (vgm_load_busy),
        .vgm_load_done                  (vgm_load_done),
        .vgm_load_error                 (vgm_load_error),
        .vgm_load_overflow              (vgm_load_overflow),
        .vgm_header_valid               (vgm_header_valid),
        .vgm_player_error               (vgm_player_error),
        .vgm_unsupported_opcode         (),
        .vgm_unsupported_pc             (),
        .vgm_player_error_code          (vgm_player_error_code),
        .vgm_error_pc_debug            (),
        .vgm_error_cmd_debug           (),
        .vgm_error_session_id          (vgm_error_session_id),
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
        .vgm_loop_taken_debug           (vgm_loop_taken_debug),
        .vgm_loop_jump_pulse_debug      (vgm_loop_jump_pulse_debug),
        .vgm_end_command_seen           (),
        .vgm_restarted_from_data_start  (),
        .vgm_pcm_oob                    (),
        .vgm_pcm_oob_count              (),
        .vgm_wait_ticks_consumed_debug  (vgm_wait_ticks_consumed_debug),
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
                'h1c: long_wait_vgm_byte = native_loop_file ? 8'h24 : 8'h00;
                // Deliberately false header loop-sample metadata. Scheduling
                // must still use the measured 16/4-sample parser traversal.
                'h20: long_wait_vgm_byte = native_loop_file ? 8'h78 : 8'h00;
                'h21: long_wait_vgm_byte = native_loop_file ? 8'h56 : 8'h00;
                'h22: long_wait_vgm_byte = native_loop_file ? 8'h34 : 8'h00;
                'h23: long_wait_vgm_byte = native_loop_file ? 8'h12 : 8'h00;
                'h40: long_wait_vgm_byte = native_loop_file ? 8'h61 : 8'h61;
                'h41: long_wait_vgm_byte = native_loop_file ?
                    (short_native_loop ? 8'h04 :
                     (transition_stress_file ? 8'h20 : 8'h10)) :
                    (transition_stress_file ? 8'h20 :
                     (short_ending_file ? 8'h10 : 8'hff));
                'h42: long_wait_vgm_byte = native_loop_file ? 8'h00 :
                    (transition_stress_file ? 8'h00 :
                     (short_ending_file ? 8'h00 : 8'hff));
                'h43: long_wait_vgm_byte = 8'h66;
                default: long_wait_vgm_byte = 8'h00;
            endcase
        end
    endfunction

    task automatic fail_now(input string label);
        begin
            $display("FAIL %s muted=%0b audio_l=%0d audio_r=%0d busy=%0b done=%0b header=%0b load_busy=%0b load_done=%0b load_error=%0b overflow=%0b player_error=%0b reset_active=%0b start_pulse=%0b begin_count=%0d done_count=%0d reset_count=%0d start_count=%0d player_reset_count=%0d session=%0d dup=%0d end=%0d repeat=%0d done_session=%0d done_pc=%02h done_cmd=%02h cycles=%0d ever_open=%0b fade=%0b released=%0b gain=%0d parser_end=%0b",
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
                     mode5_cycles_since_start,
                     dut.loaded_vgm_mode.mode5_audio_ever_open,
                     dut.loaded_vgm_mode.mode5_transition_fade_active,
                     dut.loaded_vgm_mode.mode5_transition_released,
                     dut.loaded_vgm_mode.mode5_transition_gain,
                     dut.loaded_vgm_mode.mode5_parser_done_edge);
            $fatal(1);
        end
    endtask

    task automatic wait_for_handoff_open(input int session_number);
        int i;
        logic [31:0] wait_ticks_before;
        begin
            for (i = 0; i < 20_000; i = i + 1) begin
                @(posedge clk);
                if (handoff_audio_valid_observed &&
                    dut.audio_runtime_open)
                    break;
            end
            if (i == 20_000) begin
                $display("STRESS_STUCK session=%0d busy=%0b done=%0b status=%0d raw_valid=%0b handoff_valid=%0b open=%0b gain=%0d fade=%0b loop_limit=%0b load_busy=%0b wait=%0b reset=%0b loop_count=%0d loop_length=%0d loop_armed=%0b wait_ticks=%0d",
                         session_number,
                         player_busy,
                         player_done,
                         phase1b_state,
                         dut.raw_audio_sample_valid,
                         handoff_audio_valid_observed,
                         dut.audio_runtime_open,
                         dut.loaded_vgm_mode.mode5_transition_gain,
                         dut.loaded_vgm_mode.mode5_transition_fade_active,
                         dut.loaded_vgm_mode.mode5_transition_loop_limit_active,
                         vgm_load_busy,
                         ioctl_wait,
                         mode5_sound_reset_active,
                         native_loop_count,
                         dut.loaded_vgm_mode.mode5_loop_length_samples,
                         dut.loaded_vgm_mode.mode5_loop_second_active,
                         vgm_wait_ticks_consumed_debug);
                fail_now("stress handoff gate permanent mute");
            end
            wait_ticks_before =
                vgm_wait_ticks_consumed_debug;
            repeat (1024) @(posedge clk);
            if (!player_busy || player_done ||
                vgm_wait_ticks_consumed_debug <=
                    wait_ticks_before) begin
                fail_now("stress player/wait counter stopped after PLAYING");
            end
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
            while (ioctl_wait) @(posedge clk);
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

    task automatic set_loop_limit_policy(
        input logic enabled, input logic valid_record);
        logic [7:0] control_byte;
        begin
            @(posedge clk);
            ioctl_index <= 16'd2;
            ioctl_download <= 1'b1;
            for (int i = 0; i < 4; i = i + 1) begin
                unique case (i)
                    0: control_byte = 8'h4d;
                    1: control_byte = 8'h56;
                    2: control_byte = valid_record ? 8'h02 : 8'h7f;
                    default: control_byte = {7'd0, enabled};
                endcase
                @(posedge clk);
                ioctl_addr <= i[26:0];
                ioctl_dout <= control_byte;
                ioctl_wr <= 1'b1;
                @(posedge clk);
                ioctl_wr <= 1'b0;
            end
            @(posedge clk);
            ioctl_download <= 1'b0;
            @(posedge clk);
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
            for (i = 0; i < 100_000; i = i + 1) begin
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
            for (i = 0; i < 100_000; i = i + 1) begin
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
        while (audio_muted) @(posedge clk);

        force dut.raw_audio_l = 16'sd16384;
        force dut.raw_audio_r = -16'sd16384;
        begin_download();
        @(negedge clk);
        if (!ioctl_wait || mode5_load_begin_count != 32'd1 ||
            mode5_playback_session_id != 32'd1 || !player_busy ||
            audio_muted || audio_l != 16'sd16384 ||
            audio_r != -16'sd16384) begin
            fail_now("replacement did not begin with owned fade");
        end
        repeat (128) @(posedge clk);
        if (!ioctl_wait || mode5_load_begin_count != 32'd1 ||
            audio_l >= 16'sd16384 || audio_l <= 16'sd0 ||
            audio_r <= -16'sd16384 || audio_r >= 16'sd0) begin
            fail_now("replacement fade did not ramp");
        end
        while (ioctl_wait) @(posedge clk);
        if (audio_l !== 16'sd0 || audio_r !== 16'sd0) begin
            fail_now("replacement fade did not own zero before load");
        end
        release dut.raw_audio_l;
        release dut.raw_audio_r;
        @(posedge clk);
        @(posedge clk);
        assert_silent("new load begins only after fade");
        if (player_busy || vgm_header_valid) begin
            fail_now("old playback not quiesced after fade");
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

        if (phase1b_seen_session != 32'd2 ||
            !phase1b_seen_states[1] || !phase1b_seen_states[2] ||
            phase1b_state != 3'd2 || phase1b_error != 8'd0) begin
            fail_now("Phase 1B replacement LOADING/PLAYING");
        end

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

        short_ending_file = 1'b1;
        load_long_wait_vgm();
        wait_for_sound_reset_count(32'd3);
        wait_for_player_start_count(32'd3);
        while (audio_muted) @(posedge clk);
        force dut.raw_audio_l = 16'sd12000;
        force dut.raw_audio_r = -16'sd12000;
        wait (dut.loaded_vgm_mode.mode5_parser_done_edge);
        @(posedge clk);
        @(negedge clk);
        if (player_done || audio_muted ||
            !dut.loaded_vgm_mode.mode5_transition_fade_active ||
            audio_l !== 16'sd12000 || audio_r !== -16'sd12000) begin
            fail_now("natural END was published before tail fade");
        end
        repeat (128) @(posedge clk);
        if (player_done || audio_l >= 16'sd12000 || audio_l <= 16'sd0 ||
            audio_r <= -16'sd12000 || audio_r >= 16'sd0) begin
            fail_now("natural END tail did not ramp");
        end
        wait_for_player_end_count(32'd1);
        release dut.raw_audio_l;
        release dut.raw_audio_r;

        if (!player_done || player_busy || !vgm_header_valid) begin
            fail_now("end counter final state");
        end
        if (mode5_done_session_id != 32'd3 ||
            mode5_done_pc_debug != 8'h43 ||
            mode5_done_cmd_debug != 8'h66) begin
            fail_now("end debug fields");
        end
        repeat (8) @(posedge clk);
        if (phase1b_seen_session != 32'd3 ||
            !phase1b_seen_states[1] || !phase1b_seen_states[2] ||
            !phase1b_seen_states[3] || phase1b_state != 3'd3 ||
            phase1b_error != 8'd0) begin
            fail_now("Phase 1B normal 0x66 ENDED");
        end

        repeat (128) @(posedge clk);
        if (mode5_player_start_count != 32'd3 ||
            mode5_sound_reset_start_count != 32'd3 ||
            mode5_repeat_restart_count != 32'd0 ||
            !audio_muted) begin
            fail_now("repeat disabled should stay stopped");
        end

        short_ending_file = 1'b0;
        native_loop_file = 1'b1;

        // A malformed policy record cannot arm the next session.
        set_loop_limit_policy(1'b1, 1'b0);
        repeat (8) @(posedge clk);
        if (dut.loaded_vgm_mode.mode5_loop_limit_policy_pending) begin
            fail_now("invalid LOOP_LIMIT policy accepted");
        end

        // Arm the exact next load. The VGM carries no trusted loop-sample
        // metadata; its 16-sample loop is measured from actual wait ticks.
        set_loop_limit_policy(1'b1, 1'b1);
        load_long_wait_vgm();
        wait_for_sound_reset_count(32'd4);
        wait_for_player_start_count(32'd4);
        wait_for_running("post-done file B running");

        if (phase1b_seen_session != 32'd4 ||
            !phase1b_seen_states[1] || !phase1b_seen_states[2] ||
            phase1b_seen_states[3] || phase1b_seen_states[4] ||
            phase1b_state != 3'd2) begin
            fail_now("Phase 1B stale ENDED cleared");
        end

        // LOOP_LIMIT uses the existing single fade owner. The first loop is
        // measured as 16 samples, so an 8-sample test fade starts halfway
        // through loop 2 and the second 0x66 is the only completion point.
        force dut.raw_audio_l = 16'sd16000;
        force dut.raw_audio_r = -16'sd16000;
        wait (native_loop_count == 1);
        wait (dut.loaded_vgm_mode.mode5_loop_length_samples == 32'd16);
        if (dut.loaded_vgm_mode.mode5_loop_fade_start_samples != 32'd8 ||
            dut.loaded_vgm_mode.mode5_loop_fade_samples != 32'd8 ||
            !dut.loaded_vgm_mode.mode5_loop_second_active) begin
            fail_now("LOOP_LIMIT first-loop measurement");
        end
        wait (dut.loaded_vgm_mode.mode5_transition_fade_active);
        loop_limit_fade_start_cycles = mode5_cycles_since_start;
        wait (dut.loaded_vgm_mode.mode5_transition_gain < 9'd240);
        if (!player_busy || player_done ||
            mode5_playback_session_id != 32'd4 ||
            mode5_load_begin_count != 32'd4 ||
            mode5_sound_reset_start_count != 32'd4 ||
            mode5_player_start_count != 32'd4 ||
            mode5_player_end_count != 32'd1 ||
            !dut.vgm_load_done || audio_l <= 16'sd0 ||
            audio_l >= 16'sd16000 || audio_r >= 16'sd0 ||
            audio_r <= -16'sd16000) begin
            fail_now("LOOP_LIMIT did not preserve audible loop-2 fade");
        end
        wait_for_player_end_count(32'd2);
        if (audio_l !== 16'sd0 || audio_r !== 16'sd0 || !player_done ||
            mode5_load_begin_count != 32'd4 ||
            mode5_playback_session_id != 32'd4 ||
            mode5_sound_reset_start_count != 32'd4 ||
            mode5_player_start_count != 32'd4 || native_loop_count != 1 ||
            dut.loaded_vgm_mode.mode5_transition_gain != 9'd0) begin
            fail_now("LOOP_LIMIT did not publish one zero-gain END");
        end
        // Model a held, non-zero final mixer value immediately when the fade
        // reaches zero. Every cycle from ENDED through the next session's
        // first valid sample is covered by the assertion above.
`ifndef BASELINE_04910
        force dut.raw_audio_sample_valid = 1'b0;
        enforce_handoff_zero = 1'b1;
        handoff_zero_cycles = 0;
`endif
        repeat (32) @(posedge clk);
        if (mode5_player_end_count != 32'd2 ||
            mode5_load_begin_count != 32'd4 ||
            mode5_playback_session_id != 32'd4) begin
            fail_now("duplicate LOOP_LIMIT END/load/session");
        end

        // A loop shorter than the requested fade clamps to L and begins its
        // fade at loop-2 entry, still stopping at exactly the second boundary.
        // Hold a deliberately stale non-zero mixer sample across the complete
        // ENDED/load/reset/session handoff while suppressing the new session's
        // first valid strobe. Post-gain output must remain exactly zero until
        // that authoritative new sample arrives.
        short_native_loop = 1'b1;
        load_long_wait_vgm();
        wait_for_player_start_count(32'd5);
        wait_for_running("short-loop file running");
        repeat (16) @(posedge clk);
`ifndef BASELINE_04910
        if (!audio_muted || handoff_zero_cycles == 0) begin
            fail_now("transition handoff opened before next valid sample");
        end
        force dut.raw_audio_sample_valid = 1'b1;
        @(posedge clk);
        #1;
        if (!handoff_audio_valid_observed) begin
            fail_now("transition handoff did not capture first valid sample");
        end
        $display("HANDOFF_ZERO cycles=%0d session=%0d load_begin=%0d reset_start=%0d player_start=%0d gain=%0d open=%0b first_l=%0d first_r=%0d",
                 handoff_zero_cycles,
                 mode5_playback_session_id,
                 mode5_load_begin_count,
                 mode5_sound_reset_start_count,
                 mode5_player_start_count,
                 dut.loaded_vgm_mode.mode5_transition_gain,
                 dut.audio_runtime_open,
                 audio_l,
                 audio_r);
        enforce_handoff_zero = 1'b0;
        release dut.raw_audio_sample_valid;
        while (audio_muted) @(posedge clk);
        if (audio_l !== 16'sd16000 || audio_r !== -16'sd16000) begin
            fail_now("transition handoff lost first valid sample");
        end
`else
        while (audio_muted) @(posedge clk);
`endif
        wait (dut.loaded_vgm_mode.mode5_loop_length_samples == 32'd4);
        if (dut.loaded_vgm_mode.mode5_loop_fade_start_samples != 32'd0 ||
            dut.loaded_vgm_mode.mode5_loop_fade_samples != 32'd4) begin
            fail_now("short LOOP_LIMIT clamp");
        end
        wait_for_player_end_count(32'd3);
        if (native_loop_count != 2 || mode5_playback_session_id != 32'd5 ||
            mode5_load_begin_count != 32'd5 ||
            mode5_sound_reset_start_count != 32'd5 ||
            mode5_player_start_count != 32'd5 ||
            dut.loaded_vgm_mode.mode5_transition_gain != 9'd0) begin
            fail_now("short LOOP_LIMIT boundary completion");
        end
        repeat (32) @(posedge clk);
        if (mode5_player_end_count != 32'd3 || native_loop_count != 2) begin
            fail_now("short LOOP_LIMIT duplicate completion");
        end

        // A runtime switch to Repeat One can cancel the loop-limit owner even
        // after its fade began. The same parser then crosses the boundary by
        // its normal native-loop redirect instead of stopping.
        short_native_loop = 1'b0;
        load_long_wait_vgm();
        wait_for_player_start_count(32'd6);
        wait_for_running("repeat-one cancellation file running");
        wait (dut.loaded_vgm_mode.mode5_transition_fade_active);
        set_loop_limit_policy(1'b0, 1'b1);
        wait (!dut.loaded_vgm_mode.mode5_transition_fade_active);
        if (dut.loaded_vgm_mode.mode5_transition_gain != 9'd256) begin
            fail_now("Repeat One did not restore full gain");
        end
        wait (native_loop_count >= 4);
        if (player_done || !player_busy || mode5_player_end_count != 32'd3 ||
            dut.loaded_vgm_mode.mode5_loop_limit_policy_active ||
            mode5_playback_session_id != 32'd6) begin
            fail_now("disabled LOOP_LIMIT changed native repeat");
        end

        // A manual replacement arriving during the scheduled loop fade joins
        // the existing owner and changes it to the established short ramp. It
        // must release index 1 before the second native boundary.
        set_loop_limit_policy(1'b1, 1'b1);
        load_long_wait_vgm();
        wait_for_player_start_count(32'd7);
        wait_for_running("manual-preemption loop running");
        wait (dut.loaded_vgm_mode.mode5_transition_fade_active);
        begin
            integer manual_fade_cycles;
            manual_fade_cycles = 0;
            begin_download();
            wait (ioctl_wait);
            while (ioctl_wait) begin
                @(posedge clk);
                manual_fade_cycles = manual_fade_cycles + 1;
            end
            repeat (3) @(posedge clk);
            if (mode5_load_begin_count != 32'd8 ||
                mode5_playback_session_id != 32'd8 ||
                mode5_player_end_count != 32'd3 ||
                manual_fade_cycles > 300) begin
                fail_now("manual load did not preempt LOOP_LIMIT with short fade");
            end
        end
        for (int i = 0; i <= 'h43; i = i + 1)
            write_download_byte(i);
        finish_download();
        release dut.raw_audio_l;
        release dut.raw_audio_r;

        wait_for_player_start_count(32'd8);
        wait_for_running("manual-preemption replacement running");

        // Production-lifetime stress: 50 total sessions in one RBF. Mix
        // loop-limit automatic END, natural EOF, manual replacement, policy
        // changes (Repeat One/All ownership), and rapid replacement. Each new
        // load must clear all measured-loop prediction state and must acquire
        // an authoritative mixer-valid edge without leaving PLAYING muted.
        transition_stress_file = 1'b1;
        short_ending_file = 1'b0;
        short_native_loop = 1'b0;
        for (int stress_session = 9;
             stress_session <= 50;
             stress_session = stress_session + 1) begin
            logic stress_loop;
            logic manual_replace;
            integer end_before;
            stress_loop = ((stress_session % 3) != 0);
            manual_replace = ((stress_session % 7) == 0);
            native_loop_file = stress_loop;
            set_loop_limit_policy(stress_loop, 1'b1);

            begin_download();
            wait (mode5_load_begin_count == stress_session);
            #1;
            if (mode5_playback_session_id != stress_session ||
                dut.loaded_vgm_mode.mode5_loop_region_started ||
                dut.loaded_vgm_mode.mode5_loop_first_boundary_seen ||
                dut.loaded_vgm_mode.mode5_loop_second_active ||
                dut.loaded_vgm_mode.mode5_loop_start_wait_ticks != 32'd0 ||
                dut.loaded_vgm_mode.mode5_loop_second_start_wait_ticks != 32'd0 ||
                dut.loaded_vgm_mode.mode5_loop_length_samples != 32'd0 ||
                dut.loaded_vgm_mode.mode5_loop_fade_start_samples != 32'd0 ||
                dut.loaded_vgm_mode.mode5_loop_fade_samples != 32'd0) begin
                fail_now("stress stale loop predictor at load begin");
            end
            for (int i = 0; i <= 'h43; i = i + 1)
                write_download_byte(i);
            finish_download();
            wait_for_player_start_count(stress_session);
            wait_for_running("stress session running");
            if (mode5_sound_reset_start_count != stress_session ||
                mode5_player_reset_count < stress_session ||
                mode5_playback_session_id != stress_session ||
                phase1b_state != 3'd2 || vgm_player_error ||
                vgm_load_error || vgm_load_overflow) begin
                fail_now("stress one load/reset/start/session contract");
            end
            wait_for_handoff_open(stress_session);

            end_before = mode5_player_end_count;
            if (!manual_replace) begin
                wait_for_player_end_count(end_before + 1);
                repeat (32) @(posedge clk);
                if (mode5_player_end_count != end_before + 1 ||
                    !player_done || player_busy ||
                    mode5_done_session_id != stress_session) begin
                    fail_now("stress duplicate/missing ENDED");
                end
            end
            if ((stress_session % 10) == 0)
                $display("STRESS_PROGRESS session=%0d loads=%0d resets=%0d starts=%0d ends=%0d",
                         stress_session,
                         mode5_load_begin_count,
                         mode5_sound_reset_start_count,
                         mode5_player_start_count,
                         mode5_player_end_count);
        end

        $display("STRESS_PASS sessions=%0d loads=%0d resets=%0d starts=%0d ends=%0d session=%0d",
                 50,
                 mode5_load_begin_count,
                 mode5_sound_reset_start_count,
                 mode5_player_start_count,
                 mode5_player_end_count,
                 mode5_playback_session_id);
`ifdef MEGAVGMDRIVE_MODE5_STOP_DIAGNOSTIC
        if (dut.mode5_stop_diag_bus[329]) begin
            fail_now("diagnostic observer false-triggered during 50-session stress");
        end
`endif

        $display("PASS tb_mode5_load_while_playing_session");
        $finish;
    end

endmodule
