`timescale 1ns/1ps

// Full mode-5 integration trace for the first block-6 phrase in Final Take
// Off.  Unlike tb_segapcm_backend_ab, this test keeps the loaded VGM player
// and its normal-DDR file reads active while SegaPCM payload reads run.
module tb_final_takeoff_block6_top;
`ifndef FINAL_TAKEOFF_BYTES
`define FINAL_TAKEOFF_BYTES 900000
`endif
    localparam integer FILE_BYTES = `FINAL_TAKEOFF_BYTES;
`ifndef C0_SCOREBOARD_CLK_HZ
`define C0_SCOREBOARD_CLK_HZ 8_053_974
`endif
    localparam integer CLK_HZ = `C0_SCOREBOARD_CLK_HZ;
    localparam [28:0] DDR_BASE = {4'b0011, 25'd0};
    localparam integer SEGA_WORD_BASE = 21'h100000;
    localparam integer PAYLOAD_WORDS = (153600 + 7) / 8;
    localparam integer DDR_WORDS = SEGA_WORD_BASE + PAYLOAD_WORDS + 16;

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg ioctl_download = 1'b0;
    reg ioctl_wr = 1'b0;
    reg [26:0] ioctl_addr = 27'd0;
    reg [7:0] ioctl_dout = 8'd0;
    wire ioctl_wait;
    wire player_busy;
    wire player_done;
    wire audio_sample_valid;
    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire [28:0] ddram_addr;
    reg [63:0] ddram_dout = 64'd0;
    reg ddram_dout_ready = 1'b0;
    reg ddram_busy = 1'b0;
    wire [63:0] ddram_din;
    wire [7:0] ddram_be;
    wire ddram_rd;
    wire ddram_we;

    reg [7:0] vgm_mem [0:FILE_BYTES-1];
    reg [63:0] ddram_mem [0:DDR_WORDS-1];
    reg [28:0] read_addr_q = 29'd0;
    integer read_delay = 0;
    integer ddram_busy_timer = 0;
    integer ddram_busy_cycles = 0;
    integer handoff_only = 0;
    integer consume_limit = 0;
    integer generic_consume_count = 0;
    integer vgm_fd;
    integer vgm_read;
    integer vgm_size;
    integer i;
    integer timeout;
    integer block6_timeout = 180_000_000;
    integer block6_request_count = 0;
    integer block6_response_count = 0;
    integer block6_consume_count = 0;
    integer block6_nonzero_output_count = 0;
    integer block6_tap_count = 0;
    integer block6_write_count = 0;
    integer scan_restart_count = 0;
    integer player_start_count = 0;
    integer player_reset_count = 0;
    integer header_entry_count = 0;
    integer preplay_scan_start_count = 0;
    integer preplay_scan_finish_count = 0;
    integer c0_accept_count = 0;
    integer block6_stall_count = 0;
    integer last_table_count = -1;
    reg block6_seen = 1'b0;
    reg first_block6_response_seen = 1'b0;
    reg first_block6_consume_seen = 1'b0;
    reg first_start_snapshot_seen = 1'b0;
    reg first_c0_snapshot_seen = 1'b0;
    reg first_stall_seen = 1'b0;
    reg loaded_player_start_d = 1'b0;
    reg loaded_player_reset_d = 1'b1;
    reg header_valid_d = 1'b0;
    reg preplay_scan_busy_d = 1'b0;
    reg preplay_scan_done_d = 1'b0;
    reg [7:0] first_block6_response = 8'h80;
    reg [7:0] first_block6_consume = 8'h80;
    reg [1023:0] vgm_file;
    reg [1023:0] c0_trace_file;
    reg [1023:0] lifecycle_trace_file;
    localparam integer C0_SCOREBOARD_DEPTH = 131072;
    reg [22:0] c0_expected_pc [0:C0_SCOREBOARD_DEPTH-1];
    reg [15:0] c0_expected_addr [0:C0_SCOREBOARD_DEPTH-1];
    reg [7:0] c0_expected_data [0:C0_SCOREBOARD_DEPTH-1];
    reg [7:0] c0_oracle_ram [0:255];
    reg [7:0] c0_applied_ram [0:255];
    integer c0_decoded_count = 0;
    integer c0_downstream_accept_count = 0;
    integer c0_applied_count = 0;
    integer c0_duplicate_count = 0;
    integer c0_drop_count = 0;
    integer c0_reorder_count = 0;
    integer c0_overwrite_while_pending_count = 0;
    integer c0_back_to_back_drain_count = 0;
    integer c0_during_sound_reset_count = 0;
    integer c0_cpu_internal_collision_count = 0;
    integer c0_scoreboard_error_count = 0;
    integer c0_trace_fd = 0;
    integer lifecycle_trace_fd = 0;
    integer stop_vgm_samples = 0;
    integer stop_after_c0 = 0;
    integer scoreboard_only = 0;
    integer c0_init_i;
    integer lifecycle_start_accepted [0:15];
    integer lifecycle_start_suppressed [0:15];
    integer lifecycle_retrigger_accepted [0:15];
    integer lifecycle_retrigger_suppressed [0:15];
    integer lifecycle_current_reset [0:15];
    integer lifecycle_frac_reset [0:15];
    integer lifecycle_active_set [0:15];
    integer lifecycle_active_clear [0:15];
    integer lifecycle_end_stop [0:15];
    integer lifecycle_control_stop [0:15];
    integer lifecycle_prefetch_invalid [0:15];
    integer lifecycle_pending_start_seq [0:15];
    integer lifecycle_pending_current_seq [0:15];
    reg [15:0] lifecycle_active_d = 16'd0;
    reg [15:0] lifecycle_control_seen = 16'd0;
    reg [15:0] lifecycle_current_mid_seen = 16'd0;
    reg [15:0] lifecycle_current_high_seen = 16'd0;
    reg [15:0] lifecycle_current_pair_pending = 16'd0;
    reg [15:0] lifecycle_start_waiting = 16'd0;
    reg [15:0] lifecycle_retrigger_waiting = 16'd0;
    reg [15:0] lifecycle_first_mismatch_seen = 16'd0;
    integer lifecycle_ch_tmp;
    integer lifecycle_off_tmp;
    integer lifecycle_seq_tmp;
    reg [15:0] lifecycle_scan_active = 16'd0;
    reg [15:0] lifecycle_current_pair_ready = 16'd0;
    reg startup_window_active = 1'b0;
    reg startup_window_check_enable = 1'b0;
    reg [15:0] startup_fault_flags = 16'd0;
    reg [15:0] startup_first_active_mask = 16'd0;
    reg [15:0] startup_first_hold_mask = 16'd0;
    reg [15:0] startup_first_prefetch_mask = 16'd0;
    integer startup_window_cycles = 0;
    integer startup_first_start_sample = -1;
    wire [15:0] descriptor_valid_mask;
    genvar descriptor_i;
    generate
        for (descriptor_i = 0; descriptor_i < 16;
             descriptor_i = descriptor_i + 1) begin : descriptor_mask_gen
            assign descriptor_valid_mask[descriptor_i] =
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    smoke_type80_table_valid_i[descriptor_i];
        end
    endgenerate

    always #5 clk = ~clk;

    function [7:0] expected_jt_control;
        input [7:0] raw_control;
        reg [7:0] bank_mask;
        reg [3:0] bank_shift;
        reg [20:0] full_bank;
        begin
            bank_mask = 8'h70 |
                (dut.loaded_vgm_mode.segapcm_interface[23:16] & 8'hfc);
            bank_shift = dut.loaded_vgm_mode.segapcm_interface[3:0];
            if (dut.loaded_vgm_mode.segapcm_interface == 32'd0) begin
                bank_mask = 8'h70;
                bank_shift = 4'hc;
            end
            full_bank = ({13'd0, (raw_control & bank_mask)} << bank_shift);
            expected_jt_control = {
                1'b0, full_bank[18:16], 1'b0, raw_control[2:0]
            };
        end
    endfunction

    mister_vgm_md_top #(
        .REGION_MODE                     (5),
        .VGM_LOAD_ADDR_WIDTH             (23),
        .MODE5_VGM_BACKEND               (1),
        .CLK_SYS_HZ                      (CLK_HZ),
        .POWER_ON_RESET_CYCLES           (32'd0),
        .START_DELAY_CYCLES              (32'd0),
        .INIT_AUDIO_SAMPLE_EDGES          (16'd0),
        .AUDIO_WARMUP_SAMPLES            (16'd0),
        .GATE_TO_START_CYCLES             (16'd0),
        .MODE5_SOUND_RESET_CYCLES        (32'd0),
        .MODE5_AUDIO_UNMUTE_DELAY_CYCLES (32'd0),
        .REPLAY_ENABLE                   (1'b0)
    ) dut (
        .clk                            (clk),
        .reset_n                        (reset_n),
        .audio_l                        (audio_l),
        .audio_r                        (audio_r),
        .audio_sample_valid             (audio_sample_valid),
        .audio_lpf_mode                 (2'b00),
        .audio_gain_boost               (1'b0),
        .audio_psg_level                (2'b00),
        .segapcm_smoke_variant          (3'd0),
        .segapcm_smoke_variant_valid    (1'b0),
        .segapcm_smoke_source_loaded    (player_busy),
        .segapcm_smoke_ddr_follow       (player_busy),
        .segapcm_smoke_ddr_offset       (3'd0),
        .segapcm_smoke_ddr_delta        (3'd0),
        .segapcm_smoke_c0_use           (2'd3),
        .segapcm_smoke_c0_sample_mode   (3'd3),
        .segapcm_smoke_c0_delta_speed   (2'd2),
        .segapcm_smoke_c0_hit_window    (3'd0),
        .segapcm_smoke_c0_format        (2'd0),
        .segapcm_smoke_c0_mame_tick_div (3'd0),
        .segapcm_smoke_c0_vol_map       (3'd0),
        .segapcm_smoke_c0_drive         (2'd2),
        .segapcm_c0_pm3_audio_mask      (16'h0008),
        .segapcm_c0_top_audio_test      (2'd0),
        // Match the hardware Hold feed used for compatibility listening.
        // Fresh (0) is a separately known diagnostic failure mode.
        .segapcm_c0_pm3_mix_mode        (2'd1),
        .segapcm_c0_pm3_start_policy    (3'd0),
        .segapcm_c0_jt_backend          (1'b1),
        .segapcm_smoke_ddr_dest_map     (1'b1),
        .segapcm_smoke_ddr_dest_basis   (2'd1),
        .segapcm_smoke_ddr_full_capture (1'b1),
        .segapcm_smoke_ddr_dest_loop_wrap(1'b0),
        .player_busy                    (player_busy),
        .player_done                    (player_done),
        .ioctl_download                 (ioctl_download),
        .ioctl_wr                       (ioctl_wr),
        .ioctl_addr                     (ioctl_addr),
        .ioctl_dout                     (ioctl_dout),
        .ioctl_index                    (16'd1),
        .ioctl_wait                     (ioctl_wait),
        .ddram_busy                     (ddram_busy),
        .ddram_addr                     (ddram_addr),
        .ddram_dout                     (ddram_dout),
        .ddram_dout_ready               (ddram_dout_ready),
        .ddram_din                      (ddram_din),
        .ddram_be                       (ddram_be),
        .ddram_rd                       (ddram_rd),
        .ddram_we                       (ddram_we)
    );

    always @(posedge clk) begin
        // New-load startup window: arm at the accepted file-load edge, begin
        // checking on the following cycle (after synchronous clear has had
        // one edge), and close only when JT accepts the first explicitly
        // controlled active channel scan.
        if (dut.loaded_vgm_mode.mode5_load_begin_pulse) begin
            startup_window_active <= 1'b1;
            startup_window_check_enable <= 1'b0;
            startup_fault_flags <= 16'd0;
            startup_first_active_mask <= 16'd0;
            startup_first_hold_mask <= 16'd0;
            startup_first_prefetch_mask <= 16'd0;
            startup_window_cycles <= 0;
            startup_first_start_sample <= -1;
        end else if (startup_window_active) begin
            startup_window_check_enable <= 1'b1;
            startup_window_cycles <= startup_window_cycles + 1;
            if (startup_window_check_enable) begin
                if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.active != 16'd0) begin
                    startup_fault_flags[0] <= 1'b1;
                    if (startup_first_active_mask == 16'd0)
                        startup_first_active_mask <=
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.active;
                end
                if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_sample) startup_fault_flags[1] <= 1'b1;
                if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_sample &&
                    ((dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_snd_left != 16'sd0) ||
                     (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_snd_right != 16'sd0)))
                    startup_fault_flags[2] <= 1'b1;
                if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_sample_hold_valid_i != 16'd0) begin
                    startup_fault_flags[3] <= 1'b1;
                    if (startup_first_hold_mask == 16'd0)
                        startup_first_hold_mask <=
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_sample_hold_valid_i;
                end
                if ((dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_prefetch_valid_i |
                     dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_prefetch_alt_valid_i) != 16'd0) begin
                    startup_fault_flags[4] <= 1'b1;
                    if (startup_first_prefetch_mask == 16'd0)
                        startup_first_prefetch_mask <=
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_prefetch_valid_i |
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_prefetch_alt_valid_i;
                end
                if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_req_fifo_count_i != 0)
                    startup_fault_flags[5] <= 1'b1;
                if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_ddr_owner_valid_i)
                    startup_fault_flags[6] <= 1'b1;
                if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_synthetic_response_pending_i)
                    startup_fault_flags[7] <= 1'b1;
                if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        cpu_write_pending)
                    startup_fault_flags[8] <= 1'b1;
            end
            if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    lab_jt_pcm_core.cen &&
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    lab_jt_pcm_core.st == 4'd1 &&
                !dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    lab_jt_pcm_core.cfg_en[0] &&
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    lab_jt_pcm_core.c0_control_written_i[
                        dut.loaded_vgm_mode.ym2151_sound_enabled.
                            segapcm_sound.lab_jt_pcm_core.cur_ch]) begin
                startup_window_active <= 1'b0;
                startup_first_start_sample <=
                    dut.vgm_wait_ticks_consumed_debug;
                $display("STARTUP_WINDOW_CLOSE sample=%0d cycles=%0d ch=%0d flags=%04h active=%04h hold=%04h prefetch=%04h",
                    dut.vgm_wait_ticks_consumed_debug,
                    startup_window_cycles,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.cur_ch,
                    startup_fault_flags, startup_first_active_mask,
                    startup_first_hold_mask, startup_first_prefetch_mask);
            end
        end

        // End-to-end C0 sequence scoreboard.  The loaded player has no C0
        // ready input, so a valid pulse is accepted when the wrapper samples
        // it into its one-entry pending register.  The later core_cpu_cs pulse
        // is the actual JT config-RAM port-0 write.
        if (dut.loaded_vgm_mode.segapcm_cmd_valid) begin
            if (c0_decoded_count >= C0_SCOREBOARD_DEPTH)
                $fatal(1, "C0 scoreboard overflow");
            c0_expected_pc[c0_decoded_count] <=
                dut.vgm_current_pc_debug[22:0] - 23'd4;
            c0_expected_addr[c0_decoded_count] <=
                dut.loaded_vgm_mode.segapcm_cmd_addr;
            c0_expected_data[c0_decoded_count] <=
                dut.loaded_vgm_mode.segapcm_cmd_data;
            c0_oracle_ram[dut.loaded_vgm_mode.segapcm_cmd_addr[7:0]] <=
                dut.loaded_vgm_mode.segapcm_cmd_data;
            if (!dut.loaded_vgm_mode.mode5_sound_core_reset &&
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    cpu_write_pending) begin
                // The old entry is converted to cpu_write_pulse on this same
                // edge before the new entry becomes pending.  This is a legal
                // one-per-cycle drain+refill, not an overwrite.
                c0_back_to_back_drain_count <=
                    c0_back_to_back_drain_count + 1;
            end
            if (c0_trace_fd != 0)
                $fwrite(c0_trace_fd,
                    "D,%0d,%0t,%06h,%04h,%02h,%0d,%0d\n",
                    c0_decoded_count, $time,
                    dut.vgm_current_pc_debug[22:0] - 23'd4,
                    dut.loaded_vgm_mode.segapcm_cmd_addr,
                    dut.loaded_vgm_mode.segapcm_cmd_data,
                    dut.loaded_vgm_mode.segapcm_cmd_addr[6:3],
                    dut.loaded_vgm_mode.segapcm_cmd_addr[2:0]);
            c0_decoded_count <= c0_decoded_count + 1;
            if (dut.loaded_vgm_mode.mode5_sound_core_reset) begin
                c0_during_sound_reset_count <= c0_during_sound_reset_count + 1;
                $display("C0_DROPPED_DURING_SOUND_RESET seq=%0d time=%0t sample=%0d pc=%06h addr=%04h data=%02h load_session=%0b scan=%0b/%0b",
                    c0_decoded_count, $time,
                    dut.vgm_wait_ticks_consumed_debug,
                    dut.vgm_current_pc_debug[22:0] - 23'd4,
                    dut.loaded_vgm_mode.segapcm_cmd_addr,
                    dut.loaded_vgm_mode.segapcm_cmd_data,
                    dut.loaded_vgm_mode.mode5_load_session_active,
                    dut.segapcm_rom_scan_busy,
                    dut.segapcm_rom_scan_done);
            end else begin
                c0_downstream_accept_count <=
                    c0_downstream_accept_count + 1;
            end
        end

        if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.core_cpu_cs) begin
            if (c0_applied_count >= c0_decoded_count) begin
                c0_duplicate_count <= c0_duplicate_count + 1;
                c0_scoreboard_error_count <= c0_scoreboard_error_count + 1;
                $error("C0 apply without decoded entry apply=%0d decoded=%0d",
                    c0_applied_count, c0_decoded_count);
            end else begin
                if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        latched_raw_addr !== c0_expected_addr[c0_applied_count] ||
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        latched_cpu_data !== c0_expected_data[c0_applied_count]) begin
                    c0_reorder_count <= c0_reorder_count + 1;
                    c0_scoreboard_error_count <= c0_scoreboard_error_count + 1;
                    $error("C0 sequence mismatch seq=%0d expected=%04h/%02h applied=%04h/%02h",
                        c0_applied_count,
                        c0_expected_addr[c0_applied_count],
                        c0_expected_data[c0_applied_count],
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            latched_raw_addr,
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            latched_cpu_data);
                end
                if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        latched_cpu_addr !==
                    c0_expected_addr[c0_applied_count][7:0]) begin
                    c0_scoreboard_error_count <= c0_scoreboard_error_count + 1;
                    $error("C0 mapped address mismatch seq=%0d expected=%02h applied=%02h",
                        c0_applied_count,
                        c0_expected_addr[c0_applied_count][7:0],
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            latched_cpu_addr);
                end
                if (c0_expected_addr[c0_applied_count][7] &&
                    c0_expected_addr[c0_applied_count][2:0] == 3'd6) begin
                    if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            lab_jt_cpu_data !==
                        expected_jt_control(c0_expected_data[c0_applied_count])) begin
                        c0_scoreboard_error_count <= c0_scoreboard_error_count + 1;
                        $error("C0 control map mismatch seq=%0d raw=%02h expected_jt=%02h applied_jt=%02h",
                            c0_applied_count,
                            c0_expected_data[c0_applied_count],
                            expected_jt_control(c0_expected_data[c0_applied_count]),
                            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                                lab_jt_cpu_data);
                    end
                    c0_applied_ram[c0_expected_addr[c0_applied_count][7:0]] <=
                        expected_jt_control(c0_expected_data[c0_applied_count]);
                end else begin
                    c0_applied_ram[c0_expected_addr[c0_applied_count][7:0]] <=
                        c0_expected_data[c0_applied_count];
                end
                if (c0_trace_fd != 0)
                    $fwrite(c0_trace_fd,
                        "A,%0d,%0t,%06h,%04h,%02h,%02h,%0d,%0d\n",
                        c0_applied_count, $time,
                        c0_expected_pc[c0_applied_count],
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            latched_raw_addr,
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            latched_cpu_data,
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            lab_jt_cpu_data,
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            lab_jt_write_ch,
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            lab_jt_write_off);
            end
            if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    lab_jt_pcm_core.cpu_internal_ram_write_collision)
                c0_cpu_internal_collision_count <=
                    c0_cpu_internal_collision_count + 1;

            // Lifecycle intent is derived only from an actually applied C0
            // write.  Current mid/high completion can retrigger an already
            // active voice; an active-low control write starts an inactive
            // voice or confirms a pending current-pair retrigger.
            lifecycle_ch_tmp =
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    lab_jt_write_ch;
            lifecycle_off_tmp =
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    lab_jt_write_off;
            lifecycle_seq_tmp = c0_applied_count;
            if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    latched_cpu_addr[7] &&
                (lifecycle_off_tmp == 4 || lifecycle_off_tmp == 5)) begin
                if (lifecycle_off_tmp == 4)
                    lifecycle_current_mid_seen[lifecycle_ch_tmp] <= 1'b1;
                else
                    lifecycle_current_high_seen[lifecycle_ch_tmp] <= 1'b1;
                if ((lifecycle_off_tmp == 4 &&
                     lifecycle_current_high_seen[lifecycle_ch_tmp]) ||
                    (lifecycle_off_tmp == 5 &&
                     lifecycle_current_mid_seen[lifecycle_ch_tmp])) begin
                    lifecycle_current_pair_pending[lifecycle_ch_tmp] <= 1'b1;
                    lifecycle_current_pair_ready[lifecycle_ch_tmp] <= 1'b1;
                    lifecycle_pending_current_seq[lifecycle_ch_tmp] <=
                        lifecycle_seq_tmp;
                    lifecycle_current_mid_seen[lifecycle_ch_tmp] <= 1'b0;
                    lifecycle_current_high_seen[lifecycle_ch_tmp] <= 1'b0;
                    if (dut.loaded_vgm_mode.ym2151_sound_enabled.
                            segapcm_sound.lab_jt_pcm_core.active[
                                lifecycle_ch_tmp]) begin
                        lifecycle_retrigger_waiting[lifecycle_ch_tmp] <= 1'b1;
                    end
                end
            end
            if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    latched_cpu_addr[7] && lifecycle_off_tmp == 6) begin
                lifecycle_control_seen[lifecycle_ch_tmp] <= 1'b1;
                if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        latched_cpu_data[0]) begin
                    lifecycle_control_stop[lifecycle_ch_tmp] <=
                        lifecycle_control_stop[lifecycle_ch_tmp] + 1;
                    lifecycle_start_waiting[lifecycle_ch_tmp] <= 1'b0;
                    lifecycle_retrigger_waiting[lifecycle_ch_tmp] <= 1'b0;
                    if (lifecycle_trace_fd != 0)
                        $fwrite(lifecycle_trace_fd,
                            "CONTROL_STOP,%0d,%0t,%0d,%0d,-1,control_bit0,%02h,%02h,%04h,%04h,%02h,%02h,%02h,%02h,%0b,%0b,%02h,%0b,%05h,%02h\n",
                            lifecycle_seq_tmp, $time,
                            dut.vgm_wait_ticks_consumed_debug,
                            lifecycle_ch_tmp,
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.latched_cpu_addr,
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.latched_cpu_data,
                            {c0_applied_ram[8'h85 + lifecycle_ch_tmp*8],
                             c0_applied_ram[8'h84 + lifecycle_ch_tmp*8]},
                            {c0_applied_ram[8'h05 + lifecycle_ch_tmp*8],
                             c0_applied_ram[8'h04 + lifecycle_ch_tmp*8]},
                            c0_applied_ram[8'h06 + lifecycle_ch_tmp*8],
                            c0_applied_ram[8'h07 + lifecycle_ch_tmp*8],
                            c0_applied_ram[8'h02 + lifecycle_ch_tmp*8],
                            c0_applied_ram[8'h03 + lifecycle_ch_tmp*8],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.active[
                                    lifecycle_ch_tmp],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.
                                    c0_control_written_i[lifecycle_ch_tmp],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.cur_addr[7:0],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.
                                    c0_rom_prefetch_cpu_invalid_i[
                                        lifecycle_ch_tmp],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.rom_addr,
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.
                                    c0_effective_rom_data);
                end else begin
                    lifecycle_pending_start_seq[lifecycle_ch_tmp] <=
                        lifecycle_seq_tmp;
                    if (dut.loaded_vgm_mode.ym2151_sound_enabled.
                            segapcm_sound.lab_jt_pcm_core.active[
                                lifecycle_ch_tmp]) begin
                        if (lifecycle_current_pair_pending[lifecycle_ch_tmp])
                            lifecycle_retrigger_waiting[lifecycle_ch_tmp] <= 1'b1;
                    end else begin
                        lifecycle_start_waiting[lifecycle_ch_tmp] <= 1'b1;
                    end
                end
            end
            c0_applied_count <= c0_applied_count + 1;
        end

        // State 0 has just loaded cfg_en/was_enb when the observed state is 1.
        // This is the first point at which strict-start acceptance versus
        // suppression is known without guessing from the CPU write timing.
        if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                lab_jt_pcm_core.cen &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                lab_jt_pcm_core.st == 4'd1) begin
            lifecycle_ch_tmp =
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    lab_jt_pcm_core.cur_ch;
            if (lifecycle_start_waiting[lifecycle_ch_tmp]) begin
                if (!dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.cfg_en[0]) begin
                    lifecycle_start_accepted[lifecycle_ch_tmp] <=
                        lifecycle_start_accepted[lifecycle_ch_tmp] + 1;
                    lifecycle_scan_active[lifecycle_ch_tmp] <= 1'b1;
                    if (lifecycle_trace_fd != 0)
                        $fwrite(lifecycle_trace_fd,
                            "START_ACCEPT,%0d,%0t,%0d,%0d,1,active_control,00,00,%04h,%04h,%02h,%02h,%02h,%02h,%0b,%0b,%02h,%0b,%05h,%02h\n",
                            lifecycle_pending_start_seq[lifecycle_ch_tmp],
                            $time, dut.vgm_wait_ticks_consumed_debug,
                            lifecycle_ch_tmp,
                            {c0_applied_ram[8'h85 + lifecycle_ch_tmp*8],
                             c0_applied_ram[8'h84 + lifecycle_ch_tmp*8]},
                            {c0_applied_ram[8'h05 + lifecycle_ch_tmp*8],
                             c0_applied_ram[8'h04 + lifecycle_ch_tmp*8]},
                            c0_applied_ram[8'h06 + lifecycle_ch_tmp*8],
                            c0_applied_ram[8'h07 + lifecycle_ch_tmp*8],
                            c0_applied_ram[8'h02 + lifecycle_ch_tmp*8],
                            c0_applied_ram[8'h03 + lifecycle_ch_tmp*8],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.active[
                                    lifecycle_ch_tmp],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.
                                    c0_control_written_i[lifecycle_ch_tmp],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.cur_addr[7:0],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.
                                    c0_rom_prefetch_cpu_invalid_i[
                                        lifecycle_ch_tmp],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.rom_addr,
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.
                                    c0_effective_rom_data);
                end else begin
                    lifecycle_start_suppressed[lifecycle_ch_tmp] <=
                        lifecycle_start_suppressed[lifecycle_ch_tmp] + 1;
                    if (lifecycle_trace_fd != 0)
                        $fwrite(lifecycle_trace_fd,
                            "START_SUPPRESS,%0d,%0t,%0d,%0d,1,%s,00,00,%04h,%04h,%02h,%02h,%02h,%02h,%0b,%0b,%02h,%0b,%05h,%02h\n",
                            lifecycle_pending_start_seq[lifecycle_ch_tmp],
                            $time, dut.vgm_wait_ticks_consumed_debug,
                            lifecycle_ch_tmp,
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.
                                    c0_control_written_i[lifecycle_ch_tmp] ?
                                "control_disabled" : "strict_no_control",
                            {c0_applied_ram[8'h85 + lifecycle_ch_tmp*8],
                             c0_applied_ram[8'h84 + lifecycle_ch_tmp*8]},
                            {c0_applied_ram[8'h05 + lifecycle_ch_tmp*8],
                             c0_applied_ram[8'h04 + lifecycle_ch_tmp*8]},
                            c0_applied_ram[8'h06 + lifecycle_ch_tmp*8],
                            c0_applied_ram[8'h07 + lifecycle_ch_tmp*8],
                            c0_applied_ram[8'h02 + lifecycle_ch_tmp*8],
                            c0_applied_ram[8'h03 + lifecycle_ch_tmp*8],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.active[
                                    lifecycle_ch_tmp],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.
                                    c0_control_written_i[lifecycle_ch_tmp],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.cur_addr[7:0],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.
                                    c0_rom_prefetch_cpu_invalid_i[
                                        lifecycle_ch_tmp],
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.rom_addr,
                            dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.
                                    c0_effective_rom_data);
                end
                lifecycle_start_waiting[lifecycle_ch_tmp] <= 1'b0;
            end
            if (lifecycle_retrigger_waiting[lifecycle_ch_tmp]) begin
                if (!dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.cfg_en[0]) begin
                    lifecycle_retrigger_accepted[lifecycle_ch_tmp] <=
                        lifecycle_retrigger_accepted[lifecycle_ch_tmp] + 1;
                    lifecycle_current_reset[lifecycle_ch_tmp] <=
                        lifecycle_current_reset[lifecycle_ch_tmp] + 1;
                end else begin
                    lifecycle_retrigger_suppressed[lifecycle_ch_tmp] <=
                        lifecycle_retrigger_suppressed[lifecycle_ch_tmp] + 1;
                end
                if (lifecycle_trace_fd != 0)
                    $fwrite(lifecycle_trace_fd,
                        "%s,%0d,%0t,%0d,%0d,1,%s,00,00,%04h,%04h,%02h,%02h,%02h,%02h,%0b,%0b,%02h,%0b,%05h,%02h\n",
                        !dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            lab_jt_pcm_core.cfg_en[0] ?
                            "RETRIGGER_ACCEPT" : "RETRIGGER_SUPPRESS",
                        lifecycle_pending_current_seq[lifecycle_ch_tmp],
                        $time, dut.vgm_wait_ticks_consumed_debug,
                        lifecycle_ch_tmp,
                        !dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            lab_jt_pcm_core.cfg_en[0] ?
                            "active_control" :
                            (dut.loaded_vgm_mode.ym2151_sound_enabled.
                                segapcm_sound.lab_jt_pcm_core.
                                    c0_control_written_i[lifecycle_ch_tmp] ?
                                "control_disabled" : "strict_no_control"),
                        {c0_applied_ram[8'h85 + lifecycle_ch_tmp*8],
                         c0_applied_ram[8'h84 + lifecycle_ch_tmp*8]},
                        {c0_applied_ram[8'h05 + lifecycle_ch_tmp*8],
                         c0_applied_ram[8'h04 + lifecycle_ch_tmp*8]},
                        c0_applied_ram[8'h06 + lifecycle_ch_tmp*8],
                        c0_applied_ram[8'h07 + lifecycle_ch_tmp*8],
                        c0_applied_ram[8'h02 + lifecycle_ch_tmp*8],
                        c0_applied_ram[8'h03 + lifecycle_ch_tmp*8],
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            lab_jt_pcm_core.active[lifecycle_ch_tmp],
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            lab_jt_pcm_core.c0_control_written_i[
                                lifecycle_ch_tmp],
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            lab_jt_pcm_core.cur_addr[7:0],
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            lab_jt_pcm_core.c0_rom_prefetch_cpu_invalid_i[
                                lifecycle_ch_tmp],
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            lab_jt_pcm_core.rom_addr,
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                            lab_jt_pcm_core.c0_effective_rom_data);
                lifecycle_retrigger_waiting[lifecycle_ch_tmp] <= 1'b0;
                lifecycle_current_pair_pending[lifecycle_ch_tmp] <= 1'b0;
            end
        end

        if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                lab_jt_pcm_core.cen &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                lab_jt_pcm_core.st == 4'd7 &&
            !dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                lab_jt_pcm_core.cfg_en[0] &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                lab_jt_pcm_core.normal_end_match) begin
            lifecycle_ch_tmp =
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    lab_jt_pcm_core.cur_ch;
            if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    lab_jt_pcm_core.cfg_en[1])
                lifecycle_end_stop[lifecycle_ch_tmp] <=
                    lifecycle_end_stop[lifecycle_ch_tmp] + 1;
            if (lifecycle_trace_fd != 0)
                $fwrite(lifecycle_trace_fd,
                    "%s,-1,%0t,%0d,%0d,7,end_match,00,00,%04h,%04h,%02h,%02h,%02h,%02h,%0b,%0b,%02h,%0b,%05h,%02h\n",
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.cfg_en[1] ? "END_STOP" : "LOOP",
                    $time, dut.vgm_wait_ticks_consumed_debug,
                    lifecycle_ch_tmp,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.cur_addr[23:8],
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.loop_addr,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.end_addr,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.delta,
                    c0_applied_ram[8'h02 + lifecycle_ch_tmp*8],
                    c0_applied_ram[8'h03 + lifecycle_ch_tmp*8],
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.active[lifecycle_ch_tmp],
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.c0_control_written_i[
                            lifecycle_ch_tmp],
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.cur_addr[7:0],
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.c0_rom_prefetch_cpu_invalid_i[
                            lifecycle_ch_tmp],
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.rom_addr,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.c0_effective_rom_data);
        end

        if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                lab_jt_pcm_core.active != lifecycle_active_d) begin
            for (lifecycle_ch_tmp = 0; lifecycle_ch_tmp < 16;
                 lifecycle_ch_tmp = lifecycle_ch_tmp + 1) begin
                if (!lifecycle_active_d[lifecycle_ch_tmp] &&
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.active[lifecycle_ch_tmp])
                    lifecycle_active_set[lifecycle_ch_tmp] <=
                        lifecycle_active_set[lifecycle_ch_tmp] + 1;
                if (lifecycle_active_d[lifecycle_ch_tmp] &&
                    !dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                        lab_jt_pcm_core.active[lifecycle_ch_tmp])
                    lifecycle_active_clear[lifecycle_ch_tmp] <=
                        lifecycle_active_clear[lifecycle_ch_tmp] + 1;
            end
            lifecycle_active_d <=
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.
                    lab_jt_pcm_core.active;
        end

        loaded_player_start_d <= dut.loaded_vgm_mode.loaded_player_start_input_live;
        loaded_player_reset_d <= dut.loaded_vgm_mode.mode5_loaded_player_reset;
        header_valid_d <= dut.vgm_header_valid;
        preplay_scan_busy_d <= dut.segapcm_rom_scan_busy;
        preplay_scan_done_d <= dut.segapcm_rom_scan_done;

        if (dut.loaded_vgm_mode.mode5_loaded_player_reset &&
            !loaded_player_reset_d)
            player_reset_count <= player_reset_count + 1;

        if (dut.loaded_vgm_mode.loaded_player_start_input_live &&
            !loaded_player_start_d) begin
            player_start_count <= player_start_count + 1;
            if (!first_start_snapshot_seen) begin
                first_start_snapshot_seen <= 1'b1;
                $display("HANDOFF_PLAY_START time=%0t starts=%0d reset=%0b pc=%06h state=%0d wait=%0d scan=%0b/%0b descriptors=%0d valid=%04h payload_expected=%05h accepted=%05h committed=%05h main_pack=%0b smoke_pack=%0b fifo=%0d write_pending=%0b ddram_busy=%0b",
                    $time, player_start_count + 1,
                    dut.loaded_vgm_mode.mode5_loaded_player_reset,
                    dut.vgm_current_pc_debug,
                    dut.vgm_player_state_debug,
                    dut.loaded_vgm_mode.loaded_player.wait_remaining,
                    dut.segapcm_rom_scan_busy,
                    dut.segapcm_rom_scan_done,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.smoke_type80_table_count_i,
                    descriptor_valid_mask,
                    dut.loaded_vgm_mode.segapcm_payload_tap_byte_count[18:0],
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_count_i,
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_commit_count_i,
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.pack_valid,
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_pack_valid,
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.fifo_count,
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.write_pending,
                    ddram_busy);
            end
        end

        if (dut.vgm_header_valid && !header_valid_d)
            header_entry_count <= header_entry_count + 1;
        if (dut.segapcm_rom_scan_busy && !preplay_scan_busy_d)
            preplay_scan_start_count <= preplay_scan_start_count + 1;
        if (dut.segapcm_rom_scan_done && !preplay_scan_done_d)
            preplay_scan_finish_count <= preplay_scan_finish_count + 1;

        if (dut.loaded_vgm_mode.segapcm_cmd_valid) begin
            c0_accept_count <= c0_accept_count + 1;
            if (!first_c0_snapshot_seen) begin
                first_c0_snapshot_seen <= 1'b1;
                $display("HANDOFF_FIRST_C0 time=%0t pc=%06h state=%0d addr=%03h data=%02h sound_reset=%0b load_session=%0b descriptors=%0d valid=%04h payload_expected=%05h accepted=%05h committed=%05h main_pack=%0b smoke_pack=%0b fifo=%0d write_pending=%0b ddram_busy=%0b",
                    $time,
                    dut.vgm_current_pc_debug,
                    dut.vgm_player_state_debug,
                    dut.loaded_vgm_mode.segapcm_cmd_addr,
                    dut.loaded_vgm_mode.segapcm_cmd_data,
                    dut.loaded_vgm_mode.mode5_sound_core_reset,
                    dut.loaded_vgm_mode.mode5_load_session_active,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.smoke_type80_table_count_i,
                    descriptor_valid_mask,
                    dut.loaded_vgm_mode.segapcm_payload_tap_byte_count[18:0],
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_count_i,
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_commit_count_i,
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.pack_valid,
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_pack_valid,
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.fifo_count,
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.write_pending,
                    ddram_busy);
                if (dut.loaded_vgm_mode.segapcm_payload_tap_byte_count[18:0] !=
                        dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_count_i ||
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_count_i !=
                        dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_commit_count_i)
                    $fatal(1,
                        "first C0 before payload commit expected=%05h accepted=%05h committed=%05h",
                        dut.loaded_vgm_mode.segapcm_payload_tap_byte_count[18:0],
                        dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_count_i,
                        dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_commit_count_i);
                if (dut.loaded_vgm_mode.backend_ddram.ddram_backend.pack_valid ||
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_pack_valid ||
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.fifo_count != 0 ||
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.write_pending ||
                    ddram_busy)
                    $fatal(1,
                        "first C0 before DDR drain main_pack=%0b smoke_pack=%0b fifo=%0d pending=%0b busy=%0b",
                        dut.loaded_vgm_mode.backend_ddram.ddram_backend.pack_valid,
                        dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_pack_valid,
                        dut.loaded_vgm_mode.backend_ddram.ddram_backend.fifo_count,
                        dut.loaded_vgm_mode.backend_ddram.ddram_backend.write_pending,
                        ddram_busy);
                if (dut.segapcm_rom_scan_busy)
                    $fatal(1, "first C0 while SegaPCM scanner is active");
                if (handoff_only != 0) begin
                    $display("HANDOFF_EARLY_SUMMARY starts=%0d resets=%0d headers=%0d preplay_start=%0d preplay_finish=%0d payload_capture_passes=%0d",
                        player_start_count, player_reset_count,
                        header_entry_count, preplay_scan_start_count,
                        preplay_scan_finish_count, scan_restart_count);
                    $finish;
                end
            end
        end

        ddram_dout_ready <= 1'b0;
        if (ddram_busy_timer != 0) begin
            ddram_busy_timer <= ddram_busy_timer - 1;
            if (ddram_busy_timer == 1)
                ddram_busy <= 1'b0;
        end
        if (ddram_we) begin
            if (ddram_busy_cycles != 0) begin
                ddram_busy <= 1'b1;
                ddram_busy_timer <= ddram_busy_cycles;
            end
            if (ddram_be[0]) ddram_mem[ddram_addr-DDR_BASE][7:0] <= ddram_din[7:0];
            if (ddram_be[1]) ddram_mem[ddram_addr-DDR_BASE][15:8] <= ddram_din[15:8];
            if (ddram_be[2]) ddram_mem[ddram_addr-DDR_BASE][23:16] <= ddram_din[23:16];
            if (ddram_be[3]) ddram_mem[ddram_addr-DDR_BASE][31:24] <= ddram_din[31:24];
            if (ddram_be[4]) ddram_mem[ddram_addr-DDR_BASE][39:32] <= ddram_din[39:32];
            if (ddram_be[5]) ddram_mem[ddram_addr-DDR_BASE][47:40] <= ddram_din[47:40];
            if (ddram_be[6]) ddram_mem[ddram_addr-DDR_BASE][55:48] <= ddram_din[55:48];
            if (ddram_be[7]) ddram_mem[ddram_addr-DDR_BASE][63:56] <= ddram_din[63:56];
            if (ddram_addr == DDR_BASE + SEGA_WORD_BASE + (19'h21800 >> 3)) begin
                block6_write_count <= block6_write_count + 1;
                if (block6_write_count < 8)
                    $display("TOP_B6_WRITE time=%0t addr=%08h be=%02h data=%016h",
                        $time, ddram_addr, ddram_be, ddram_din);
            end
        end
        if (ddram_rd && read_delay == 0) begin
            if (ddram_busy_cycles != 0) begin
                ddram_busy <= 1'b1;
                ddram_busy_timer <= ddram_busy_cycles;
            end
            read_addr_q <= ddram_addr;
            read_delay <= 6;
        end else if (read_delay != 0) begin
            read_delay <= read_delay - 1;
            if (read_delay == 1) begin
                ddram_dout <= ddram_mem[read_addr_q-DDR_BASE];
                ddram_dout_ready <= 1'b1;
            end
        end

        if (dut.loaded_vgm_mode.segapcm_payload_tap_valid &&
            dut.loaded_vgm_mode.segapcm_payload_tap_addr == 19'h21800) begin
            block6_tap_count <= block6_tap_count + 1;
            if (block6_tap_count < 8)
                $display("TOP_B6_TAP time=%0t data=%02h copy=%0b/%0b/%05h/%02h capture=%05h count=%05h",
                    $time,
                    dut.loaded_vgm_mode.segapcm_payload_tap_data,
                    dut.loaded_vgm_mode.segapcm_copy_wr_req,
                    dut.loaded_vgm_mode.segapcm_copy_wr_ready,
                    dut.loaded_vgm_mode.segapcm_copy_wr_addr,
                    dut.loaded_vgm_mode.segapcm_copy_wr_data,
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_capture_index,
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_count_i);
        end

        if (dut.loaded_vgm_mode.segapcm_payload_tap_valid &&
            dut.loaded_vgm_mode.segapcm_payload_tap_addr == 19'd0) begin
            scan_restart_count <= scan_restart_count + 1;
            if (scan_restart_count < 16)
                $display("TOP_SCAN_START time=%0t scan=%0d count=%05h len=%05h table=%0d pc=%06h",
                    $time, scan_restart_count,
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_count_i,
                    dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_payload_length,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.smoke_type80_table_count_i,
                    dut.vgm_current_pc_debug);
        end
        if (last_table_count <
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.smoke_type80_table_count_i) begin
            last_table_count <=
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.smoke_type80_table_count_i;
            $display("TOP_TABLE time=%0t table=%0d count=%05h len=%05h pc=%06h",
                $time,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.smoke_type80_table_count_i,
                dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_count_i,
                dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_payload_length,
                dut.vgm_current_pc_debug);
        end

        if (!block6_seen &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.rom_request_event &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_rom_addr >= 19'h59600 &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_rom_addr < 19'h5d600) begin
            block6_seen <= 1'b1;
            $display("TOP_B6_STORAGE accepts=%0d commits=%0d blocked=%0d payload_len=%05h tap_count=%0d word=%016h",
                dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_count_i,
                dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_commit_count_i,
                dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_blocked_count_debug,
                dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_payload_length,
                dut.loaded_vgm_mode.segapcm_payload_tap_byte_count,
                ddram_mem[SEGA_WORD_BASE + (19'h21800 >> 3)]);
            $display("TOP_B6_FIRST_REQ time=%0t ch=%0d rom=%05h cur=%06h ctrl=%02h gen=%0d table=%0d map=%0b block=%0d rel=%05h payload=%05h range=%0b fifo_push=%0b",
                $time,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_req_src_ch,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_rom_addr,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cur_addr,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cfg_en,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_request_generation,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.smoke_type80_table_count_i,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_payload_match_valid_next,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_payload_block_next,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_payload_offset_next,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_payload_read_index_next,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_payload_index_in_range_next,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_ddr_request_queue_push);
        end
        if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.rom_request_event &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_rom_addr >= 19'h59600 &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_rom_addr < 19'h5d600)
            block6_request_count <= block6_request_count + 1;
        if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_ddr_payload_return_event &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_ddr_owner_valid_i &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_ddr_owner_addr_i >= 19'h59600 &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_ddr_owner_addr_i < 19'h5d600) begin
            block6_response_count <= block6_response_count + 1;
            if (!first_block6_response_seen) begin
                first_block6_response_seen <= 1'b1;
                first_block6_response <=
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_response_data;
            end
            if (block6_response_count < 8)
                $display("TOP_B6_RSP time=%0t ch=%0d rom=%05h payload=%05h byte=%02h gen=%0d",
                    $time,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_ddr_owner_ch_i,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_ddr_owner_addr_i,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_ddr_owner_index_i,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_response_data,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_ddr_owner_generation_i);
        end
        if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.segapcm_cen &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.st == 4'd12 &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.c0_normal_rom_wait_hold &&
            !first_stall_seen) begin
            first_stall_seen <= 1'b1;
            $display("TOP_FIRST_STALL time=%0t ch=%0d rom=%05h cur=%06h gen=%0d invalid=%0b prefetch=%0b/%05h/%0d req=%0b fifo=%0d owner=%0b/%0d/%05h rd=%0b/%0b player_mem=%0b pc=%06h pstate=%0d c0=%0b/%03h/%02h",
                $time,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cur_ch,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.rom_addr,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cur_addr,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_channel_generation_i[
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cur_ch],
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.c0_rom_prefetch_cpu_invalid_i[
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cur_ch],
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_prefetch_valid_i[
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cur_ch],
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_prefetch_addr_i[
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cur_ch],
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_prefetch_generation_i[
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cur_ch],
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_request_seen_pulse,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_req_fifo_count_i,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_ddr_owner_valid_i,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_ddr_owner_ch_i,
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_ddr_owner_addr_i,
                dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_rd_req,
                dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_rd_ready,
                dut.loaded_vgm_mode.loaded_player.mem_rd_req,
                dut.vgm_current_pc_debug,
                dut.vgm_player_state_debug,
                dut.loaded_vgm_mode.segapcm_cmd_valid,
                dut.loaded_vgm_mode.segapcm_cmd_addr,
                dut.loaded_vgm_mode.segapcm_cmd_data);
        end
        if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.segapcm_cen &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.st == 4'd12 &&
            !dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cfg_en[0] &&
            !dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.c0_normal_rom_wait_hold) begin
            if (generic_consume_count < consume_limit)
                $display("TOP_CONSUME slot=%0d time=%0t ch=%0d cur=%06h rom=%05h byte=%02h ok=%0b invalid=%0b match=%0b gen=%0d c0=%0b/%03h/%02h jt_l=%04h jt_r=%04h",
                    generic_consume_count,
                    $time,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cur_ch,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cur_addr,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.rom_addr,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.c0_effective_rom_data,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.c0_effective_rom_ok,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.c0_rom_prefetch_cpu_invalid_i[
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cur_ch],
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_prefetch_match,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_channel_generation_i[
                        dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cur_ch],
                    dut.loaded_vgm_mode.segapcm_cmd_valid,
                    dut.loaded_vgm_mode.segapcm_cmd_addr,
                    dut.loaded_vgm_mode.segapcm_cmd_data,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.snd_left,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.snd_right);
            generic_consume_count <= generic_consume_count + 1;
        end
        if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.segapcm_cen &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.st == 4'd12 &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.rom_addr >= 19'h59600 &&
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.rom_addr < 19'h5d600) begin
            block6_consume_count <= block6_consume_count + 1;
            if (!first_block6_consume_seen) begin
                first_block6_consume_seen <= 1'b1;
                first_block6_consume <=
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.c0_effective_rom_data;
            end
            if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.c0_normal_rom_wait_hold)
                block6_stall_count <= block6_stall_count + 1;
            if (block6_consume_count < 8)
                $display("TOP_B6_CONSUME time=%0t ch=%0d cur=%06h rom=%05h byte=%02h ok=%0b stall=%0b",
                    $time,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cur_ch,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.cur_addr,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.rom_addr,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.c0_effective_rom_data,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.c0_effective_rom_ok,
                    dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_pcm_core.c0_normal_rom_wait_hold);
        end
        if (block6_seen && audio_sample_valid &&
            ((audio_l != 16'sd0) || (audio_r != 16'sd0)))
            block6_nonzero_output_count <= block6_nonzero_output_count + 1;
    end

    initial begin
        if ($value$plusargs("BLOCK6_TIMEOUT=%d", block6_timeout)) begin end
        if ($value$plusargs("DDR_BUSY_CYCLES=%d", ddram_busy_cycles)) begin end
        if ($value$plusargs("CONSUME_LIMIT=%d", consume_limit)) begin end
        if ($value$plusargs("STOP_VGM_SAMPLES=%d", stop_vgm_samples)) begin end
        if ($value$plusargs("STOP_AFTER_C0=%d", stop_after_c0)) begin end
        if ($test$plusargs("SCOREBOARD_ONLY")) scoreboard_only = 1;
        if ($value$plusargs("C0_TRACE=%s", c0_trace_file)) begin
            c0_trace_fd = $fopen(c0_trace_file, "w");
            if (c0_trace_fd == 0) $fatal(1, "cannot open C0 trace");
            $fwrite(c0_trace_fd,
                "stage,sequence,sim_time,parser_pc,raw_addr,raw_data,jt_data,channel,register\n");
        end
        if ($value$plusargs("LIFECYCLE_TRACE=%s", lifecycle_trace_file)) begin
            lifecycle_trace_fd = $fopen(lifecycle_trace_file, "w");
            if (lifecycle_trace_fd == 0)
                $fatal(1, "cannot open lifecycle trace");
            $fwrite(lifecycle_trace_fd,
                "event,sequence,sim_time,vgm_sample,channel,state,reason,raw_addr,raw_data,current,loop,end,delta,vol_l,vol_r,active,control_written,fraction,prefetch_invalid,rom_addr,rom_data\n");
        end
        // Initialize only the TB oracle/shadow.  The DUT RAM is intentionally
        // left untouched so runtime-initialization assumptions remain visible.
        for (c0_init_i = 0; c0_init_i < 256; c0_init_i = c0_init_i + 1) begin
            c0_oracle_ram[c0_init_i] = 8'hff;
            c0_applied_ram[c0_init_i] = 8'hff;
        end
        for (c0_init_i = 0; c0_init_i < 16; c0_init_i = c0_init_i + 1) begin
            lifecycle_start_accepted[c0_init_i] = 0;
            lifecycle_start_suppressed[c0_init_i] = 0;
            lifecycle_retrigger_accepted[c0_init_i] = 0;
            lifecycle_retrigger_suppressed[c0_init_i] = 0;
            lifecycle_current_reset[c0_init_i] = 0;
            lifecycle_frac_reset[c0_init_i] = 0;
            lifecycle_active_set[c0_init_i] = 0;
            lifecycle_active_clear[c0_init_i] = 0;
            lifecycle_end_stop[c0_init_i] = 0;
            lifecycle_control_stop[c0_init_i] = 0;
            lifecycle_prefetch_invalid[c0_init_i] = 0;
            lifecycle_pending_start_seq[c0_init_i] = -1;
            lifecycle_pending_current_seq[c0_init_i] = -1;
        end
        if ($test$plusargs("HANDOFF_ONLY")) handoff_only = 1;
        if (!$value$plusargs("VGM=%s", vgm_file))
            $fatal(1, "VGM plusarg is required");
        vgm_fd = $fopen(vgm_file, "rb");
        if (vgm_fd == 0) $fatal(1, "cannot open VGM");
        vgm_read = $fread(vgm_mem, vgm_fd);
        $fclose(vgm_fd);
        if (vgm_read <= 0 || vgm_read > FILE_BYTES)
            $fatal(1, "VGM bytes %0d outside capacity %0d", vgm_read,
                   FILE_BYTES);
        vgm_size = vgm_read;
        for (i = 0; i < DDR_WORDS; i = i + 1) ddram_mem[i] = 64'd0;

        repeat (8) @(posedge clk);
        reset_n = 1'b1;
        repeat (8) @(posedge clk);
        ioctl_download = 1'b1;
        i = 0;
        while (i < vgm_size) begin
            @(negedge clk);
            ioctl_addr = i[26:0];
            ioctl_dout = vgm_mem[i];
            ioctl_wr = !ioctl_wait;
            @(posedge clk);
            if (ioctl_wr && !ioctl_wait) i = i + 1;
        end
        @(negedge clk);
        ioctl_wr = 1'b0;
        ioctl_download = 1'b0;

        if (scoreboard_only != 0 || stop_vgm_samples != 0) begin
            timeout = 0;
            while (!player_done &&
                   (stop_after_c0 == 0 ||
                    c0_decoded_count < stop_after_c0) &&
                   (stop_vgm_samples == 0 ||
                    dut.vgm_wait_ticks_consumed_debug < stop_vgm_samples) &&
                   timeout < block6_timeout) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            repeat (8) @(posedge clk);
            if (c0_applied_count < c0_decoded_count)
                c0_drop_count = c0_decoded_count - c0_applied_count;
            $display("C0_SCOREBOARD decoded=%0d accepted=%0d applied=%0d duplicate=%0d drop=%0d reorder=%0d pending_overwrite=%0d back_to_back_drain=%0d during_sound_reset=%0d cpu_internal_collision=%0d errors=%0d samples=%0d done=%0b",
                c0_decoded_count, c0_downstream_accept_count,
                c0_applied_count, c0_duplicate_count, c0_drop_count,
                c0_reorder_count, c0_overwrite_while_pending_count,
                c0_back_to_back_drain_count,
                c0_during_sound_reset_count,
                c0_cpu_internal_collision_count, c0_scoreboard_error_count,
                dut.vgm_wait_ticks_consumed_debug, player_done);
            if (c0_decoded_count != c0_downstream_accept_count ||
                c0_decoded_count != c0_applied_count ||
                c0_duplicate_count != 0 || c0_drop_count != 0 ||
                c0_reorder_count != 0 ||
                c0_overwrite_while_pending_count != 0 ||
                c0_scoreboard_error_count != 0)
                $fatal(1, "C0 end-to-end scoreboard failed");
            if (c0_trace_fd != 0) $fclose(c0_trace_fd);
            if (lifecycle_trace_fd != 0) $fclose(lifecycle_trace_fd);
            $display("PASS tb_segapcm_c0_scoreboard");
            $finish;
        end

        if (consume_limit != 0) begin
            timeout = 0;
            while (generic_consume_count < consume_limit &&
                   timeout < block6_timeout) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (generic_consume_count < consume_limit)
                $fatal(1, "consume limit timeout got=%0d expected=%0d",
                    generic_consume_count, consume_limit);
            $display("PASS tb_segapcm_preplay_handoff consumes=%0d",
                generic_consume_count);
            $finish;
        end

        timeout = 0;
        while (!block6_seen && timeout < block6_timeout) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!block6_seen)
            $fatal(1, "no block6 request table=%0d pc=%0h count=%05h len=%05h commits=%05h scans=%0d tap=%05h",
                dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.smoke_type80_table_count_i,
                dut.vgm_current_pc_debug,
                dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_count_i,
                dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_payload_length,
                dut.loaded_vgm_mode.backend_ddram.ddram_backend.smoke_ddr_write_commit_count_i,
                scan_restart_count,
                dut.loaded_vgm_mode.segapcm_payload_tap_addr);
        repeat (500_000) @(posedge clk);
        $display("TOP_B6_SUMMARY table=%0d req=%0d rsp=%0d consume=%0d nonzero_out=%0d drop=%0d stall=%0d wrong_ch=%0d wrong_addr=%0d backlog=%0d",
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.smoke_type80_table_count_i,
            block6_request_count, block6_response_count,
            block6_consume_count, block6_nonzero_output_count,
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_adapter_request_dropped_count_i,
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_adapter_unexpected_stall_count_i,
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_prefetch_wrong_channel_count_i,
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_prefetch_wrong_address_count_i,
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_adapter_final_backlog_i);
        $display("HANDOFF_SUMMARY starts=%0d resets=%0d headers=%0d preplay_start=%0d preplay_finish=%0d payload_capture_passes=%0d c0=%0d",
            player_start_count, player_reset_count, header_entry_count,
            preplay_scan_start_count, preplay_scan_finish_count,
            scan_restart_count, c0_accept_count);
        if (scan_restart_count != 1)
            $fatal(1, "payload scan restarted %0d times", scan_restart_count);
        if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.smoke_type80_table_count_i != 7)
            $fatal(1, "descriptor count is not 7");
        if (ddram_mem[SEGA_WORD_BASE + (19'h21800 >> 3)][7:0] != 8'h7a)
            $fatal(1, "block6 physical DDR byte mismatch");
        if (!first_block6_response_seen || first_block6_response != 8'h7a)
            $fatal(1, "first block6 response=%02h", first_block6_response);
        if (!first_block6_consume_seen || first_block6_consume != 8'h7a)
            $fatal(1, "first block6 consume=%02h", first_block6_consume);
        if (block6_stall_count != 0)
            $fatal(1, "block6 unexpected stalls=%0d", block6_stall_count);
        if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_adapter_request_dropped_count_i != 0)
            $fatal(1, "request drops detected");
        if (dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_prefetch_wrong_channel_count_i != 0 ||
            dut.loaded_vgm_mode.ym2151_sound_enabled.segapcm_sound.lab_jt_prefetch_wrong_address_count_i != 0)
            $fatal(1, "wrong channel/address detected");
        $display("PASS tb_final_takeoff_block6_top");
        $finish;
    end
endmodule
