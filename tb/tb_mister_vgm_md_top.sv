`timescale 1ns/1ps

module tb_mister_vgm_md_top;

`ifdef TEST_MISTER_TOP_MODE3_120K
    localparam int AUDIO_DUMP_SAMPLE_COUNT = 120000;
`elsif TEST_MISTER_TOP_MODE3_10K
    localparam int AUDIO_DUMP_SAMPLE_COUNT = 10000;
`elsif TEST_MISTER_TOP_MODE3_5K
    localparam int AUDIO_DUMP_SAMPLE_COUNT = 5000;
`else
    localparam int AUDIO_DUMP_SAMPLE_COUNT = 5000;
`endif
    localparam logic [31:0] TB_POWER_ON_RESET_CYCLES = 32'd2048;
    localparam logic [31:0] TB_START_DELAY_CYCLES = 32'd1024;
    localparam logic [15:0] TB_AUDIO_WARMUP_SAMPLES = 16'd64;
    localparam logic [31:0] TB_PLAYER_RESET_CYCLES = 32'd128;
    localparam logic [31:0] TB_START_ACCEPT_TIMEOUT_CYCLES = 32'd10000;
    localparam logic [31:0] TB_PLAYER_DONE_TIMEOUT_TICKS = 32'd100000;
    localparam logic [31:0] TB_REPLAY_DELAY_TICKS = 32'd1024;

    logic clk = 1'b0;
    logic reset_n = 1'b1;

    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire               audio_sample_valid;

    wire        player_busy;
    wire        player_done;
    wire  [9:0] player_pc_debug;
    wire  [7:0] player_last_cmd_debug;
    wire        startup_reset_active;
    wire        startup_waiting;
    wire        startup_done;
    wire        audio_gate_open;

    integer audio_file = 0;
    integer audio_dump_count = 0;
    integer audio_sample_valid_edges = 0;
    integer watchdog_clk_count = 0;
    integer total_clk_count = 0;
    bit     audio_sample_valid_prev = 1'b0;
    bit     first_audio_edge_seen = 1'b0;

    mister_vgm_md_top #(
        .POWER_ON_RESET_CYCLES       (TB_POWER_ON_RESET_CYCLES),
        .START_DELAY_CYCLES          (TB_START_DELAY_CYCLES),
        .AUDIO_WARMUP_SAMPLES        (TB_AUDIO_WARMUP_SAMPLES),
        .PLAYER_RESET_CYCLES         (TB_PLAYER_RESET_CYCLES),
        .START_ACCEPT_TIMEOUT_CYCLES (TB_START_ACCEPT_TIMEOUT_CYCLES),
        .PLAYER_DONE_TIMEOUT_TICKS   (TB_PLAYER_DONE_TIMEOUT_TICKS),
        .REPLAY_DELAY_TICKS          (TB_REPLAY_DELAY_TICKS)
    ) dut (
        .clk                   (clk),
        .reset_n               (reset_n),
        .audio_l               (audio_l),
        .audio_r               (audio_r),
        .audio_sample_valid    (audio_sample_valid),
        .player_busy           (player_busy),
        .player_done           (player_done),
        .player_pc_debug       (player_pc_debug),
        .player_last_cmd_debug (player_last_cmd_debug),
        .startup_reset_active  (startup_reset_active),
        .startup_waiting       (startup_waiting),
        .startup_done          (startup_done),
        .audio_gate_open       (audio_gate_open),
        .ioctl_download        (1'b0),
        .ioctl_wr              (1'b0),
        .ioctl_addr            (27'd0),
        .ioctl_dout            (8'd0),
        .ioctl_index           (16'd0),
        .vgm_load_busy         (),
        .vgm_load_done         (),
        .vgm_load_error        (),
        .vgm_load_overflow     (),
        .vgm_header_valid      (),
        .vgm_player_error      (),
        .vgm_unsupported_opcode(),
        .vgm_unsupported_pc    (),
        .vgm_player_error_code (),
        .vgm_load_size         (),
        .vgm_load_magic        (),
        .vgm_data_start_debug  (),
        .vgm_current_pc_debug  (),
        .vgm_loop_pc_debug     (),
        .vgm_loop_valid_debug  (),
        .vgm_loop_taken_debug  (),
        .vgm_end_command_seen  (),
        .vgm_restarted_from_data_start(),
        .vgm_wait_ticks_consumed_debug(),
        .mode5_sound_reset_active(),
        .mode5_player_start_pulse_debug(),
        .fm_adjust_clip_count_l(),
        .fm_adjust_clip_count_r(),
        .genmix_wrap_count_l(),
        .genmix_wrap_count_r(),
        .ym_write_requested_count(),
        .ym_write_accepted_count(),
        .ym_write_dropped_or_busy_count(),
        .ym_port0_count(),
        .ym_port1_count(),
        .last_ym_port(),
        .last_ym_addr(),
        .last_ym_data(),
        .jt12_cen_interval_1_count(),
        .jt12_cen_interval_2_count(),
        .jt12_cen_interval_3_count(),
        .jt12_cen_interval_4_count(),
        .jt12_cen_interval_ge5_count(),
        .jt12_cen_interval_min(),
        .jt12_cen_interval_max(),
        .jt12_cen_interval_last(),
        .fm_raw_abs_peak(),
        .fm_adjust_abs_peak(),
        .fm_lpf_abs_peak(),
        .genmix_abs_peak(),
        .md_final_audio_abs_peak()
    );

    // Simple simulation clock. The exact frequency is not important for this
    // smoke test; md_sound_module derives its internal enables from this clock.
    always #5 clk = ~clk;

    initial begin
`ifdef TEST_MISTER_TOP_MODE3_120K
        audio_file = $fopen("/tmp/mister_vgm_md_top_mode3_top_path_120k.txt", "w");
        if (audio_file == 0) begin
            $display("ERROR: failed to open /tmp/mister_vgm_md_top_mode3_top_path_120k.txt");
            $finish;
        end
`elsif TEST_MISTER_TOP_MODE3_10K
        audio_file = $fopen("/tmp/mister_vgm_md_top_mode3_top_path_10k.txt", "w");
        if (audio_file == 0) begin
            $display("ERROR: failed to open /tmp/mister_vgm_md_top_mode3_top_path_10k.txt");
            $finish;
        end
`elsif TEST_MISTER_TOP_MODE3_5K
        audio_file = $fopen("/tmp/mister_vgm_md_top_mode3_top_path_5k.txt", "w");
        if (audio_file == 0) begin
            $display("ERROR: failed to open /tmp/mister_vgm_md_top_mode3_top_path_5k.txt");
            $finish;
        end
`else
        audio_file = $fopen("/tmp/mister_vgm_md_top_5k.txt", "w");
        if (audio_file == 0) begin
            $display("ERROR: failed to open /tmp/mister_vgm_md_top_5k.txt");
            $finish;
        end
`endif

        repeat (64) @(posedge clk);

        $display("MISTER_VGM_MD_TOP_TEST_START cold_start_reset_n_initial_high=1 samples=%0d power_on_reset_cycles=%0d start_delay_cycles=%0d audio_warmup_samples=%0d startup_state=%0d",
                 AUDIO_DUMP_SAMPLE_COUNT,
                 TB_POWER_ON_RESET_CYCLES,
                 TB_START_DELAY_CYCLES,
                 TB_AUDIO_WARMUP_SAMPLES,
                 dut.startup_state);

        while (audio_dump_count < AUDIO_DUMP_SAMPLE_COUNT) begin
            @(posedge clk);
            watchdog_clk_count++;
            total_clk_count++;

            if (audio_sample_valid && !audio_sample_valid_prev) begin
                $fdisplay(audio_file, "%0d %0d", audio_l, audio_r);
                if (!first_audio_edge_seen) begin
                    first_audio_edge_seen = 1'b1;
                    $display("MISTER_VGM_MD_TOP_FIRST_AUDIO_EDGE total_clk=%0d pc=%0d last_cmd=%02h busy=%0b done=%0b audio_l=%0d audio_r=%0d startup_state=%0d startup_reset=%0b startup_waiting=%0b startup_done=%0b audio_gate_open=%0b start_pulse=%0b player_reset_active=%0b vgm_wait_tick=%0b",
                             total_clk_count,
                             player_pc_debug,
                             player_last_cmd_debug,
                             player_busy,
                             player_done,
                             audio_l,
                             audio_r,
                             dut.startup_state,
                             startup_reset_active,
                             startup_waiting,
                             startup_done,
                             audio_gate_open,
                             dut.start_pulse,
                             dut.player_reset_active,
                             dut.vgm_wait_tick);
                    $fflush(audio_file);
                end
                audio_dump_count++;
                audio_sample_valid_edges++;
                watchdog_clk_count = 0;

                if ((audio_dump_count % 1024) == 0) begin
                    $fflush(audio_file);
                end

                if ((audio_dump_count % 10000) == 0) begin
                    $display("MISTER_VGM_MD_TOP_DUMP_PROGRESS samples=%0d edges=%0d pc=%0d last_cmd=%02h busy=%0b done=%0b startup_state=%0d audio_gate_open=%0b",
                             audio_dump_count,
                             audio_sample_valid_edges,
                             player_pc_debug,
                             player_last_cmd_debug,
                             player_busy,
                             player_done,
                             dut.startup_state,
                             audio_gate_open);
                end
            end else if (!first_audio_edge_seen && ((watchdog_clk_count % 250000) == 0)) begin
                $display("MISTER_VGM_MD_TOP_WAITING_FOR_AUDIO_EDGE total_clk=%0d idle_clk=%0d pc=%0d last_cmd=%02h busy=%0b done=%0b audio_sample_valid=%0b audio_l=%0d audio_r=%0d startup_state=%0d startup_reset=%0b startup_waiting=%0b startup_done=%0b audio_gate_open=%0b start_pulse=%0b player_reset_active=%0b vgm_wait_tick=%0b",
                         total_clk_count,
                         watchdog_clk_count,
                         player_pc_debug,
                         player_last_cmd_debug,
                         player_busy,
                         player_done,
                         audio_sample_valid,
                         audio_l,
                         audio_r,
                         dut.startup_state,
                         startup_reset_active,
                         startup_waiting,
                         startup_done,
                         audio_gate_open,
                         dut.start_pulse,
                         dut.player_reset_active,
                         dut.vgm_wait_tick);
            end
            audio_sample_valid_prev = audio_sample_valid;

            if (watchdog_clk_count >= 1000000) begin
                $display("MISTER_VGM_MD_TOP_WATCHDOG_TIMEOUT total_clk=%0d dump_count=%0d edges=%0d pc=%0d last_cmd=%02h busy=%0b done=%0b audio_sample_valid=%0b audio_l=%0d audio_r=%0d reset_n=%0b startup_state=%0d startup_reset=%0b startup_waiting=%0b startup_done=%0b audio_gate_open=%0b start_pulse=%0b player_reset_active=%0b vgm_wait_tick=%0b",
                         total_clk_count,
                         audio_dump_count,
                         audio_sample_valid_edges,
                         player_pc_debug,
                         player_last_cmd_debug,
                         player_busy,
                         player_done,
                         audio_sample_valid,
                         audio_l,
                         audio_r,
                         reset_n,
                         dut.startup_state,
                         startup_reset_active,
                         startup_waiting,
                         startup_done,
                         audio_gate_open,
                         dut.start_pulse,
                         dut.player_reset_active,
                         dut.vgm_wait_tick);
                $fclose(audio_file);
                $finish;
            end
        end

        $fclose(audio_file);

`ifdef TEST_MISTER_TOP_MODE3_120K
        $display("MISTER_VGM_MD_TOP_TEST_DONE file=/tmp/mister_vgm_md_top_mode3_top_path_120k.txt wav_written_samples=%0d audio_sample_valid_edges=%0d pc=%0d last_cmd=%02h busy=%0b done=%0b startup_reset=%0b startup_waiting=%0b startup_done=%0b audio_gate_open=%0b",
`elsif TEST_MISTER_TOP_MODE3_10K
        $display("MISTER_VGM_MD_TOP_TEST_DONE file=/tmp/mister_vgm_md_top_mode3_top_path_10k.txt wav_written_samples=%0d audio_sample_valid_edges=%0d pc=%0d last_cmd=%02h busy=%0b done=%0b startup_reset=%0b startup_waiting=%0b startup_done=%0b audio_gate_open=%0b",
`elsif TEST_MISTER_TOP_MODE3_5K
        $display("MISTER_VGM_MD_TOP_TEST_DONE file=/tmp/mister_vgm_md_top_mode3_top_path_5k.txt wav_written_samples=%0d audio_sample_valid_edges=%0d pc=%0d last_cmd=%02h busy=%0b done=%0b startup_reset=%0b startup_waiting=%0b startup_done=%0b audio_gate_open=%0b",
`else
        $display("MISTER_VGM_MD_TOP_TEST_DONE file=/tmp/mister_vgm_md_top_5k.txt wav_written_samples=%0d audio_sample_valid_edges=%0d pc=%0d last_cmd=%02h busy=%0b done=%0b startup_reset=%0b startup_waiting=%0b startup_done=%0b audio_gate_open=%0b",
`endif
                 audio_dump_count,
                 audio_sample_valid_edges,
                 player_pc_debug,
                 player_last_cmd_debug,
                 player_busy,
                 player_done,
                 startup_reset_active,
                 startup_waiting,
                 startup_done,
                 audio_gate_open);

        repeat (1024) @(posedge clk);
        $finish;
    end

endmodule
