// Temporary SegaPCM sound wrapper for YM2151/SegaPCM experimental mode.
//
// This wraps Jotego's GPL-3.0-or-later OutRun SegaPCM core and feeds it from
// the LastWave Seashore preload ROM. VGM type-0x80 blocks are still skipped;
// live 0xC0 writes update the core register/RAM interface.

module segapcm_sound_module #(
    parameter logic [31:0] CLK_SYS_HZ = 32'd20_000_000,
    parameter logic [31:0] SEGAPCM_CLK_HZ = 32'd16_000_000,
    parameter int unsigned ROM_OK_LATENCY_MODE = 1,
    parameter int unsigned ROM_ADDR_MAP_MODE = 34,
    parameter int unsigned C0_ADDR_MAP_MODE = 1,
    parameter bit C0_WRITE_HOLD_FOR_CEN = 1'b0,
    parameter int unsigned PRELOAD_ROM_BYTES = 23040
) (
    input  logic               clk,
    input  logic               reset,

    input  logic               segapcm_cmd_valid,
    input  logic        [15:0] segapcm_cmd_addr,
    input  logic         [7:0] segapcm_cmd_data,
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
    input  logic         [2:0] smoke_variant,
    input  logic               smoke_variant_valid,
    input  logic               smoke_source_loaded,
    input  logic               loaded_payload_clear,
    input  logic               loaded_payload_wr_valid,
    input  logic        [18:0] loaded_payload_wr_addr,
    input  logic         [7:0] loaded_payload_wr_data,
    input  logic               loaded_payload_present,
    input  logic        [18:0] loaded_payload_length,
    input  logic        [15:0] loaded_payload_block_count,
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    input  logic               smoke_ddr_follow_mode,
    input  logic         [2:0] smoke_ddr_follow_offset_sel,
    input  logic         [2:0] smoke_ddr_follow_delta_sel,
    input  logic               smoke_ddr_follow_dest_map,
    input  logic         [1:0] smoke_ddr_follow_dest_basis,
    input  logic               smoke_ddr_follow_dest_loop_wrap,
    input  logic         [1:0] smoke_c0_use_sel,
    input  logic         [2:0] smoke_c0_sample_mode_sel,
    input  logic         [1:0] smoke_c0_delta_speed_sel,
    input  logic         [2:0] smoke_c0_hit_window_sel,
    input  logic         [1:0] smoke_c0_format_sel,
    input  logic         [2:0] smoke_c0_mame_tick_div_sel,
    input  logic         [2:0] smoke_c0_vol_map_sel,
    input  logic         [1:0] smoke_c0_drive_sel,
    input  logic        [15:0] smoke_c0_pm3_audio_mask,
    input  logic         [1:0] smoke_c0_pm3_mix_mode,
    input  logic         [2:0] smoke_c0_pm3_start_policy,
    input  logic               smoke_c0_jt_backend,
    input  logic               smoke_playback_running,
    input  logic               smoke_playback_done,
    input  logic               smoke_vgm_end_seen,
    input  logic        [31:0] loaded_type80_rom_size,
    input  logic        [31:0] loaded_type80_rom_dest,
    output logic               loaded_ddr_rd_req,
    input  logic               loaded_ddr_rd_ready,
    output logic        [18:0] loaded_ddr_rd_addr,
    input  logic               loaded_ddr_rd_valid,
    input  logic         [7:0] loaded_ddr_rd_data,
    input  logic               loaded_ddr_payload_present,
    input  logic        [18:0] loaded_ddr_payload_length,
    input  logic        [15:0] loaded_ddr_write_req_count_debug,
    input  logic        [15:0] loaded_ddr_write_count_debug,
    input  logic        [15:0] loaded_ddr_write_blocked_count_debug,
    input  logic        [15:0] loaded_ddr_write_status_debug,
    input  logic        [15:0] loaded_ddr_header_skip_count_debug,
    input  logic        [15:0] loaded_ddr_last_write_index_debug,
    input  logic        [15:0] loaded_ddr_last_write_addr_debug,
    input  logic        [15:0] loaded_ddr_last_write_lane_debug,
    input  logic         [7:0] loaded_ddr_last_write_data_debug,
    input  logic        [15:0] loaded_ddr_read_count_debug,
    input  logic        [15:0] loaded_ddr_last_read_index_debug,
    input  logic        [15:0] loaded_ddr_last_read_addr_debug,
    input  logic        [15:0] loaded_ddr_last_read_lane_debug,
    input  logic        [15:0] loaded_ddr_last_read_word0_debug,
    input  logic        [15:0] loaded_ddr_last_read_word1_debug,
    input  logic         [7:0] loaded_ddr_last_read_data_debug,
    input  logic        [15:0] loaded_ddr_base_addr_debug,
    input  logic        [15:0] loaded_ddr_probe_write_index_debug,
    input  logic        [15:0] loaded_ddr_probe_write_word_debug,
    input  logic        [15:0] loaded_ddr_probe_write_lane_debug,
    input  logic        [15:0] loaded_ddr_probe_write_addr_debug,
    input  logic        [15:0] loaded_ddr_probe_write_count_debug,
    input  logic        [15:0] loaded_ddr_probe_write_flags_debug,
    input  logic        [15:0] loaded_ddr_probe_write_word0_debug,
    input  logic        [15:0] loaded_ddr_probe_write_word6_debug,
`endif
`endif

    output logic signed [15:0] audio_l,
    output logic signed [15:0] audio_r,
    output logic               audio_sample_valid,

    output logic        [15:0] rom_addr_low_debug,
    output logic        [15:0] rom_addr_raw_high_debug,
    output logic        [15:0] rom_addr_raw_low_debug,
    output logic        [15:0] rom_addr_mapped_high_debug,
    output logic        [15:0] rom_addr_mapped_low_debug,
    output logic        [15:0] rom_addr_min_high_debug,
    output logic        [15:0] rom_addr_min_low_debug,
    output logic        [15:0] rom_addr_max_high_debug,
    output logic        [15:0] rom_addr_max_low_debug,
    output logic        [15:0] rom_audio_active_high_debug,
    output logic        [15:0] rom_audio_active_low_debug,
    output logic        [15:0] rom_first_after_ctrl_high_debug,
    output logic        [15:0] rom_first_after_ctrl_low_debug,
    output logic        [15:0] rom_range_group_debug,
    output logic        [15:0] rom_range_group2_debug,
    output logic        [15:0] rom_early_after_ctrl_high_debug,
    output logic        [15:0] rom_early_after_ctrl_low_debug,
    output logic        [15:0] rom_active_after_ctrl_high_debug,
    output logic        [15:0] rom_active_after_ctrl_low_debug,
    output logic        [15:0] rom_hit_miss_compact_debug,
    output logic        [15:0] rom_range_hit_count_debug,
    output logic        [15:0] rom_range_miss_count_debug,
    output logic        [15:0] rom_activity_count_debug,
    output logic        [15:0] rom_return_mapped_high_debug,
    output logic        [15:0] rom_return_mapped_low_debug,
    output logic        [15:0] rom_return_data_debug,
    output logic        [15:0] rom_return_last01_debug,
    output logic        [15:0] rom_return_last23_debug,
    output logic        [15:0] rom_return_nonzero_count_debug,
    output logic        [15:0] rom_return_change_count_debug,
    output logic        [15:0] rom_return_neutral_count_debug,
    output logic        [15:0] rom_preload_data_debug,
    output logic        [15:0] rom_core_ok_count_debug,
    output logic        [15:0] rom_fallback_count_debug,
    output logic        [15:0] rom_read_valid_count_debug,
    output logic        [15:0] rom_latency_debug,
    output logic        [15:0] rom_payload_len_low_debug,
    output logic        [15:0] rom_payload_len_high_debug,
    output logic        [15:0] pcm_debug_bank_channel,
    output logic        [15:0] pcm_debug_cur_addr_high,
    output logic        [15:0] pcm_debug_cur_addr_low_state,
    output logic        [15:0] known38686_flags_debug,
    output logic        [15:0] known38686_bank_debug,
    output logic        [15:0] known38686_channel_debug,
    output logic        [15:0] known38686_state_debug,
    output logic        [15:0] known38686_cur_high_debug,
    output logic        [15:0] known38686_cur_low_debug,
    output logic        [15:0] known38686_en_addr_debug,
    output logic        [15:0] known38686_en_value_debug,
    output logic        [15:0] known38686_d0_addr_debug,
    output logic        [15:0] known38686_d0_value_debug,
    output logic        [15:0] known38686_d1_addr_debug,
    output logic        [15:0] known38686_d1_value_debug,
    output logic        [15:0] known38686_d2_addr_debug,
    output logic        [15:0] known38686_d2_value_debug,
    output logic        [15:0] known38686_cfg_en_debug,
    output logic        [15:0] known38686_cur_23_debug,
    output logic        [15:0] known38686_cur_15_debug,
    output logic        [15:0] known38686_cur_07_debug,
    output logic        [15:0] c0_capture_write_count_debug,
    output logic        [15:0] c0_capture_last_addr_debug,
    output logic        [15:0] c0_capture_last_data_debug,
    output logic        [15:0] c0_capture_channel_activity_debug,
    output logic        [15:0] c0_capture_selected_channel_debug,
    output logic        [15:0] c0_capture_ch3_ctrl_debug,
    output logic        [15:0] c0_capture_ch3_cur_low_debug,
    output logic        [15:0] c0_capture_ch3_cur_mid_debug,
    output logic        [15:0] c0_capture_ch3_cur_high_debug,
    output logic        [15:0] c0_capture_ch3_delta_debug,
    output logic        [15:0] c0_capture_ch3_vol_l_debug,
    output logic        [15:0] c0_capture_ch3_vol_r_debug,
    output logic        [15:0] c0_capture_ch3_loop_debug,
    output logic        [15:0] c0_capture_ch3_end_debug,
    output logic        [15:0] jt_smoke_vol_l_debug,
    output logic        [15:0] jt_smoke_vol_r_debug,
    output logic        [15:0] jt_smoke_sample_byte_debug,
    output logic        [15:0] jt_smoke_out_l_debug,
    output logic        [15:0] jt_smoke_out_r_debug,
    output logic        [15:0] ch3_evolution_flags_debug,
    output logic        [15:0] ch3_delta_debug,
    output logic        [15:0] ch1_first_high_debug,
    output logic        [15:0] ch1_first_low_debug,
    output logic        [15:0] ch1_first_raw_high_debug,
    output logic        [15:0] ch1_first_raw_low_debug,
    output logic        [15:0] ch3_first_high_debug,
    output logic        [15:0] ch3_first_low_debug,
    output logic        [15:0] ch3_first_raw_high_debug,
    output logic        [15:0] ch3_first_raw_low_debug,
    output logic        [15:0] ch3_r0_high_debug,
    output logic        [15:0] ch3_r0_low_debug,
    output logic        [15:0] ch3_r1_high_debug,
    output logic        [15:0] ch3_r1_low_debug,
    output logic        [15:0] ch3_r2_high_debug,
    output logic        [15:0] ch3_r2_low_debug,
    output logic        [15:0] dbg_ch3_load_after_23,
    output logic        [15:0] dbg_ch3_load_after_15,
    output logic        [15:0] dbg_ch3_load_after_07,
    output logic        [15:0] update_state_channel_debug,
    output logic        [15:0] update_before_23_debug,
    output logic        [15:0] update_before_15_debug,
    output logic        [15:0] update_before_07_debug,
    output logic        [15:0] update_addend_debug,
    output logic        [15:0] update_after_23_debug,
    output logic        [15:0] update_after_15_debug,
    output logic        [15:0] update_after_07_debug,
    output logic        [15:0] update_reason_debug,
    output logic        [15:0] cpu_write_count_debug,
    output logic        [15:0] cpu_cen_write_count_debug,
    output logic        [15:0] cpu_addr_debug,
    output logic        [15:0] shadow_decode_debug,
    output logic        [15:0] shadow_ch0_vol_debug,
    output logic        [15:0] shadow_ch0_end_delta_debug,
    output logic        [15:0] shadow_ch0_start_debug,
    output logic        [15:0] shadow_ch0_ctrl_debug,
    output logic        [15:0] shadow_ch1_vol_debug,
    output logic        [15:0] shadow_ch1_loop_debug,
    output logic        [15:0] shadow_ch1_end_delta_debug,
    output logic        [15:0] shadow_ch1_start_debug,
    output logic        [15:0] shadow_ch1_ctrl_debug,
    output logic        [15:0] shadow_ch3_loop_debug,
    output logic        [15:0] shadow_ch3_end_delta_debug,
    output logic        [15:0] shadow_ch3_start_debug,
    output logic        [15:0] shadow_ch3_ctrl_debug,
    output logic        [15:0] shadow_ch3_l0_debug,
    output logic        [15:0] shadow_ch3_l2_debug,
    output logic        [15:0] shadow_ch3_l4_debug,
    output logic        [15:0] shadow_ch3_l6_debug,
    output logic        [15:0] shadow_ch3_h0_debug,
    output logic        [15:0] shadow_ch3_h2_debug,
    output logic        [15:0] shadow_ch3_h4_debug,
    output logic        [15:0] shadow_ch3_h6_debug,
    output logic        [15:0] audio_nonzero_count_debug,
    output logic        [15:0] audio_abs_peak_debug,
    output logic signed [15:0] last_audio_l_debug,
    output logic signed [15:0] last_audio_r_debug,
    output logic        [15:0] core_status_debug
);

`ifdef MEGAVGMDRIVE_SEGAPCM_C0_PM3_OUTPUT_SHIFT
    localparam int unsigned LAB16_PM3_OUTPUT_SHIFT =
        `MEGAVGMDRIVE_SEGAPCM_C0_PM3_OUTPUT_SHIFT;
`else
    localparam int unsigned LAB16_PM3_OUTPUT_SHIFT = 1;
`endif
    localparam logic [1:0] LAB16_PM3_OUTPUT_SHIFT_SEL =
        (LAB16_PM3_OUTPUT_SHIFT > 3) ? 2'd3 :
        LAB16_PM3_OUTPUT_SHIFT[1:0];

    logic [31:0] cen_accum;
    logic segapcm_cen;

    wire [7:0] cpu_din;
    wire [18:0] core_rom_addr;
    wire [7:0] core_rom_data;
    wire [7:0] preload_rom_data;
    wire preload_rom_ok;
    wire core_rom_ok;
    wire core_rom_cs;
    wire signed [15:0] core_snd_left;
    wire signed [15:0] core_snd_right;
    wire core_sample;
    wire [7:0] core_status_dout;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
    wire [7:0] lab_jt_cpu_din;
    wire [7:0] lab_jt_status_dout;
    wire [18:0] lab_jt_rom_addr;
    wire lab_jt_rom_cs;
    wire signed [15:0] lab_jt_snd_left;
    wire signed [15:0] lab_jt_snd_right;
    wire lab_jt_sample;
    wire lab_jt_ctrl_write;
    wire [7:0] lab_jt_cpu_data;
    logic [15:0] lab_jt_cpu_write_count_i;
    logic [15:0] lab_jt_rom_request_count_i;
    logic [15:0] lab_jt_rom_addr_change_count_i;
    logic [15:0] lab_jt_payload_match_count_i;
    logic [15:0] lab_jt_payload_miss_count_i;
    logic [15:0] lab_jt_rom_ok_count_i;
    logic [15:0] lab_jt_rom_nonzero_count_i;
    logic [15:0] lab_jt_rom_non80_count_i;
    logic [15:0] lab_jt_rom_changed_count_i;
    logic [15:0] lab_jt_rom_ok_while_cs_count_i;
    logic [15:0] lab_jt_sample_strobe_count_i;
    logic [15:0] lab_jt_raw_output_nonzero_count_i;
    logic [15:0] lab_jt_output_nonzero_count_i;
    logic [15:0] lab_jt_last_cpu_write_i;
    logic [18:0] lab_jt_last_rom_addr_i;
    logic [18:0] lab_jt_last_payload_index_i;
	    logic [18:0] lab_jt_first_rom_addr_i;
	    logic [18:0] lab_jt_first_ch3_rom_addr_i;
	    logic [18:0] lab_jt_max_rom_addr_i;
	    logic [7:0] lab_jt_last_rom_data_i;
	    logic [18:0] lab_jt_last_non80_rom_addr_i;
	    logic [18:0] lab_jt_last_non80_payload_index_i;
	    logic [7:0] lab_jt_first_non80_rom_data_i;
	    logic [7:0] lab_jt_last_non80_rom_data_i;
	    logic [15:0] lab_jt_block2_hit_count_i;
	    logic [18:0] lab_jt_first_block2_rom_addr_i;
	    logic [18:0] lab_jt_first_block2_payload_index_i;
	    logic [7:0] lab_jt_first_block2_rom_data_i;
	    logic [2:0] lab_jt_last_payload_block_i;
	    logic lab_jt_last_payload_match_i;
	    logic [2:0] lab_jt_last_non80_payload_block_i;
	    logic lab_jt_last_non80_payload_match_i;
	    logic signed [15:0] lab_jt_first_output_l_i;
	    logic signed [15:0] lab_jt_first_output_r_i;
		    logic signed [15:0] lab_jt_last_output_l_i;
		    logic signed [15:0] lab_jt_last_output_r_i;
	    wire [15:0] lab_jt_dbg_bank_channel_state;
	    wire [15:0] lab_jt_dbg_cur_addr_high;
	    wire [15:0] lab_jt_dbg_cur_addr_low_state;
	    wire [15:0] lab_jt_dbg_cfg_en;
	    wire [15:0] lab_jt_dbg_update_reason;
	    wire [15:0] lab_jt_dbg_pcm_raw_cv;
	    wire [15:0] lab_jt_dbg_mul_data;
	    wire [15:0] lab_jt_dbg_active_cfg;
	    wire [15:0] lab_jt_dbg_vol_lr;
	    wire [15:0] lab_jt_dbg_mul_abs =
	        lab_jt_dbg_mul_data[15] ?
	        (~lab_jt_dbg_mul_data + 16'd1) : lab_jt_dbg_mul_data;
	    logic [7:0] lab_jt_rom_data_hold_i;
	    logic [7:0] lab_jt_rom_data_hold_d_i;
	    logic lab_jt_rom_data_hold_valid_i;
	    logic lab_jt_rom_data_hold_valid_d_i;
	    logic [15:0] lab_jt_rom_data_latch_count_i;
	    logic [15:0] lab_jt_rom_neutral_while_cs_count_i;
	    logic [15:0] lab_jt_rom_repeat_count_i;
	    logic [15:0] lab_jt_rom_hold_cycle_count_i;
	    logic [15:0] lab_jt_sample_nonneutral_count_i;
	    logic [15:0] lab_jt_first_non80_pr_i;
	    logic [15:0] lab_jt_last_non80_pr_i;
	    logic [15:0] lab_jt_first_nonzero_mv_i;
	    logic [15:0] lab_jt_last_nonzero_mv_i;
	    logic [15:0] lab_jt_max_abs_mv_i;
	    logic [15:0] lab_jt_cur_write_count_i;
	    logic [15:0] lab_jt_end_write_count_i;
	    logic [15:0] lab_jt_delta_write_count_i;
	    logic [15:0] lab_jt_vol_write_count_i;
	    logic [15:0] lab_jt_ctrl_write_count_i;
	    logic [15:0] lab_jt_other_write_count_i;
	    logic [15:0] lab_jt_cen_write_count_i;
	    logic [7:0] lab_jt_ch3_cur_mid_i;
	    logic [7:0] lab_jt_ch3_cur_high_i;
	    logic [7:0] lab_jt_ch3_end_i;
	    logic [7:0] lab_jt_ch3_delta_i;
	    logic [7:0] lab_jt_ch3_vol_l_i;
	    logic [7:0] lab_jt_ch3_vol_r_i;
	    logic [7:0] lab_jt_ch3_ctrl_raw_i;
	    logic [7:0] lab_jt_ch3_ctrl_jt_i;
	    logic lab_jt_seen_cpu_write_i;
	    logic lab_jt_seen_rom_cs_i;
	    logic lab_jt_seen_first_rom_i;
	    logic lab_jt_seen_first_ch3_rom_i;
	    logic lab_jt_seen_first_block2_i;
	    logic lab_jt_seen_first_block2_data_i;
	    logic lab_jt_seen_payload_match_i;
	    logic lab_jt_seen_rom_ok_i;
	    logic lab_jt_seen_rom_nonzero_i;
	    logic lab_jt_seen_rom_non80_i;
	    logic lab_jt_seen_first_output_i;
	    logic lab_jt_seen_output_nonzero_i;
	    logic lab_jt_seen_first_non80_pr_i;
	    logic lab_jt_seen_first_nonzero_mv_i;
`endif
    wire [15:0] core_dbg_bank_channel_state;
    wire [15:0] core_dbg_cur_addr_high;
    wire [15:0] core_dbg_cur_addr_low_state;
    wire [15:0] core_dbg_38686_en_addr;
    wire [15:0] core_dbg_38686_en_value;
    wire [15:0] core_dbg_38686_d0_addr;
    wire [15:0] core_dbg_38686_d0_value;
    wire [15:0] core_dbg_38686_d1_addr;
    wire [15:0] core_dbg_38686_d1_value;
    wire [15:0] core_dbg_38686_d2_addr;
    wire [15:0] core_dbg_38686_d2_value;
    wire [15:0] core_dbg_38686_cfg_en;
    wire [15:0] core_dbg_38686_cur_23;
    wire [15:0] core_dbg_38686_cur_15;
    wire [15:0] core_dbg_38686_cur_07;
    wire [15:0] core_dbg_38686_delta;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    wire [15:0] core_dbg_smoke_cur_initialized;
    wire [15:0] core_dbg_smoke_cur_seed_event;
    wire [15:0] core_dbg_smoke_cur_live_low;
    wire [15:0] core_dbg_smoke_cur_live_high;
    wire [15:0] core_dbg_smoke_cur_live_mid;
    wire [15:0] core_dbg_smoke_cur_live_frac;
    wire [15:0] core_dbg_smoke_cur_zero_event;
    wire [15:0] core_dbg_smoke_cur_seed_ref;
    wire [15:0] core_dbg_smoke_seed_reload_req;
    wire [15:0] core_dbg_smoke_seed_commit_count;
    wire [15:0] core_dbg_smoke_seed_commit_addr;
    wire [15:0] core_dbg_smoke_seed_write_value;
    wire [15:0] core_dbg_smoke_seed_overwrite;
    wire [15:0] core_dbg_smoke_request_addr;
    wire [15:0] core_dbg_smoke_playback_addr;
    wire [15:0] core_dbg_smoke_first_addr;
    wire [15:0] core_dbg_smoke_current_input;
    wire [15:0] core_dbg_smoke_loop_input;
    wire [15:0] core_dbg_smoke_end_input;
    wire [15:0] core_dbg_smoke_source_addr;
    wire [15:0] core_dbg_smoke_cur_state;
    wire [15:0] core_dbg_smoke_jt_vol_l;
    wire [15:0] core_dbg_smoke_jt_vol_r;
    wire [15:0] core_dbg_smoke_sample_byte;
    wire core_dbg_smoke_c0_byte_accept;
    wire core_dbg_smoke_c0_mixer_consume;
    wire [15:0] core_dbg_smoke_out_l;
    wire [15:0] core_dbg_smoke_out_r;
    wire [15:0] core_dbg_smoke_end_hit;
    wire [15:0] core_dbg_smoke_loop_wrap;
    wire [15:0] core_dbg_smoke_end_cmp;
    wire [15:0] core_dbg_smoke_end_hit_at;
    wire [15:0] core_dbg_smoke_loop_to;
    wire [15:0] core_dbg_smoke_end_eq;
`endif
    wire [15:0] core_dbg_ch3_evolution_flags;
    wire [15:0] core_dbg_ch3_delta;
    wire [15:0] core_dbg_ch1_first_high;
    wire [15:0] core_dbg_ch1_first_low;
    wire [15:0] core_dbg_ch1_first_raw_high;
    wire [15:0] core_dbg_ch1_first_raw_low;
    wire [15:0] core_dbg_ch3_first_high;
    wire [15:0] core_dbg_ch3_first_low;
    wire [15:0] core_dbg_ch3_first_raw_high;
    wire [15:0] core_dbg_ch3_first_raw_low;
    wire [15:0] core_dbg_ch3_r0_high;
    wire [15:0] core_dbg_ch3_r0_low;
    wire [15:0] core_dbg_ch3_r1_high;
    wire [15:0] core_dbg_ch3_r1_low;
    wire [15:0] core_dbg_ch3_r2_high;
    wire [15:0] core_dbg_ch3_r2_low;
    wire [15:0] core_dbg_update_state_channel;
    wire [15:0] core_dbg_update_before_23;
    wire [15:0] core_dbg_update_before_15;
    wire [15:0] core_dbg_update_before_07;
    wire [15:0] core_dbg_update_addend;
    wire [15:0] core_dbg_update_after_23;
    wire [15:0] core_dbg_update_after_15;
    wire [15:0] core_dbg_update_after_07;
    wire [15:0] core_dbg_ch3_load_after_23;
    wire [15:0] core_dbg_ch3_load_after_15;
    wire [15:0] core_dbg_ch3_load_after_07;
    wire [15:0] core_dbg_update_reason;

    logic core_rom_cs_d;
    logic [18:0] core_rom_addr_d;
    logic [18:0] mapped_rom_addr;
    logic [18:0] effective_rom_addr;
    logic [18:0] base_payload_offset;
    logic [18:0] mapped_rom_addr_d;
    logic [18:0] mapped_rom_addr_d2;
    logic [18:0] request_raw_rom_addr_i;
    logic [18:0] request_mapped_rom_addr_i;
    logic [18:0] request_payload_base_offset;
    logic [18:0] request_mapped_rom_addr_calc;
    logic request_preload_addr_valid_i;
    logic [7:0] mapped_cpu_addr;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifndef MEGAVGMDRIVE_SEGAPCM_SMOKE_VARIANT
`define MEGAVGMDRIVE_SEGAPCM_SMOKE_VARIANT 0
`endif
    localparam logic [3:0] SMOKE_VARIANT_DEFAULT =
        `MEGAVGMDRIVE_SEGAPCM_SMOKE_VARIANT;
    wire [2:0] smoke_variant_active =
        smoke_variant_valid ? smoke_variant : SMOKE_VARIANT_DEFAULT[2:0];
    wire [18:0] smoke_payload_base = 19'h02600;
    wire [18:0] smoke_payload_last =
        (smoke_variant_active == 3'd7) ? 19'h026ff : 19'h02fff;
    wire [2:0] smoke_payload_step =
        (smoke_variant_active == 3'd2) ? 3'd2 :
        (smoke_variant_active == 3'd3) ? 3'd4 :
        3'd1;
    wire [2:0] smoke_step_divider =
        (smoke_variant_active == 3'd1) ? 3'd4 : 3'd1;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    logic [7:0] smoke_ddr_follow_delta_i;
`else
    wire [7:0] smoke_delta = 8'h20;
`endif
    wire [6:0] smoke_vol_l =
        (smoke_variant_active == 3'd4) ? 7'h20 :
        (smoke_variant_active == 3'd6) ? 7'h00 :
        7'h40;
    wire [6:0] smoke_vol_r =
        (smoke_variant_active == 3'd4) ? 7'h20 :
        (smoke_variant_active == 3'd5) ? 7'h00 :
        7'h40;
`ifndef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    wire [15:0] smoke_ap_debug =
        {1'b0, smoke_vol_l, 1'b0, smoke_vol_r};
`endif
    logic [18:0] smoke_payload_addr_i;
    logic [2:0] smoke_payload_div_count_i;
    logic [2:0] smoke_variant_d_i;
    logic smoke_source_loaded_d_i;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    localparam logic [18:0] SMOKE_LOADED_DDR_BYTES_19 = 19'h01000;
    localparam logic [15:0] SMOKE_DDR_READ_DIV_LAST = 16'd0;
    wire smoke_loaded_payload_present_i = loaded_ddr_payload_present;
    wire [18:0] smoke_loaded_payload_length_i = loaded_ddr_payload_length;
    wire smoke_ddr_c0drive_active =
        smoke_source_loaded &&
        loaded_ddr_payload_present &&
        smoke_ddr_follow_mode &&
        (smoke_c0_drive_sel != 2'd0);
    wire smoke_ddr_c0drive_addr_source =
        smoke_ddr_follow_mode && (smoke_c0_drive_sel != 2'd0);
    logic [15:0] c0_capture_write_count_i;
    logic [15:0] c0_capture_last_addr_i;
    logic [15:0] c0_capture_last_data_i;
    logic [15:0] c0_capture_channel_activity_i;
    logic [7:0] c0_capture_ch3_cur_low_i;
    logic [7:0] c0_capture_ch3_cur_mid_i;
    logic [7:0] c0_capture_ch3_cur_high_i;
    logic [7:0] c0_capture_ch3_loop_mid_i;
    logic [7:0] c0_capture_ch3_loop_high_i;
    logic [7:0] c0_capture_ch3_end_i;
    logic [7:0] c0_capture_ch3_delta_i;
    logic [7:0] c0_capture_ch3_vol_l_i;
    logic [7:0] c0_capture_ch3_vol_r_i;
    logic [7:0] c0_capture_ch3_ctrl_i;
    logic [7:0] c0_capture_ch3_ctrl_ext_i;
    logic [15:0] c0_capture_ch3_start_count_i;
    wire c0_capture_ch3_start_pulse_i =
        segapcm_cmd_valid &&
        (mapped_cpu_addr == 8'h9e) &&
        !segapcm_cmd_data[0];
    logic [18:0] smoke_loaded_ddr_usable_bytes;
    always @* begin
        smoke_loaded_ddr_usable_bytes = SMOKE_LOADED_DDR_BYTES_19;
        if (loaded_ddr_payload_length != 19'd0) begin
            smoke_loaded_ddr_usable_bytes = loaded_ddr_payload_length;
        end
    end
    logic [7:0] smoke_ddr_audio_byte_hold_i;
    logic [15:0] smoke_ddr_audio_index_hold_i;
    logic smoke_ddr_audio_valid_seen_i;
    logic smoke_ddr_audio_data_ok_i;
    logic [15:0] smoke_ddr_audio_update_count_i;
    logic [18:0] smoke_ddr_read_index_i;
    logic [15:0] smoke_ddr_read_div_i;
    logic [15:0] smoke_ddr_read_req_count_i;
    logic [15:0] smoke_ddr_read_valid_count_i;
    logic [15:0] smoke_ddr_read_blocked_count_i;
    logic [15:0] smoke_ddr_read_last_index_i;
    logic [15:0] smoke_ddr_read_nonzero_count_i;
    logic [15:0] smoke_ddr_read_change_count_i;
    logic [15:0] smoke_ddr_read_zero_count_i;
    logic [15:0] smoke_ddr_scan_index_i;
    logic [15:0] smoke_ddr_scan_first_nonzero_index_i;
    logic [15:0] smoke_ddr_scan_last_nonzero_index_i;
    logic [7:0] smoke_ddr_scan_data_i;
    logic [7:0] smoke_ddr_scan_first_nonzero_data_i;
    logic [7:0] smoke_ddr_scan_last_nonzero_data_i;
    logic smoke_ddr_scan_done_i;
    logic smoke_ddr_scan_found_nonzero_i;
    logic [7:0] smoke_ddr_read_last_data_i;
    logic [7:0] smoke_ddr_read_prev_data_i;
    logic [7:0] smoke_ddr_read_last_nonzero_data_i;
    logic smoke_ddr_read_valid_seen_i;
    logic smoke_ddr_follow_mode_d_i;
    logic [15:0] smoke_ddr_follow_core_addr_low_i;
    logic [15:0] smoke_ddr_follow_prev_addr_low_i;
    logic [15:0] smoke_ddr_follow_mapped_index_i;
    logic [15:0] smoke_ddr_follow_word_i;
    logic [15:0] smoke_ddr_follow_lane_i;
    logic [15:0] smoke_ddr_follow_flags_i;
    logic [15:0] smoke_ddr_follow_cs_count_i;
    logic [15:0] smoke_ddr_follow_ok_count_i;
    logic [15:0] smoke_ddr_follow_request_count_i;
    logic [15:0] smoke_ddr_follow_addr_change_count_i;
    logic [15:0] smoke_ddr_follow_payload_offset_i;
    logic [15:0] smoke_ddr_follow_norm_core_i;
    logic [15:0] smoke_ddr_follow_norm_dest_i;
    logic [15:0] smoke_ddr_follow_range_flags_i;
    logic [15:0] smoke_ddr_follow_po_min_i;
    logic [15:0] smoke_ddr_follow_po_max_i;
    logic [15:0] smoke_ddr_follow_cr_min_i;
    logic [15:0] smoke_ddr_follow_cr_max_i;
    logic [15:0] smoke_ddr_follow_ir_rise_count_i;
    logic [15:0] smoke_ddr_follow_ir_fall_count_i;
    logic [15:0] smoke_ddr_follow_cr_at_ir_rise_i;
    logic [15:0] smoke_ddr_follow_cr_at_ir_fall_i;
    logic [15:0] smoke_ddr_follow_po_at_ir_rise_i;
    logic [15:0] smoke_ddr_follow_po_at_ir_fall_i;
    logic [15:0] smoke_ddr_follow_raw_po_max_i;
    logic [15:0] smoke_ddr_follow_eff_mi_max_i;
    logic [15:0] smoke_ddr_follow_po_at_fu_rise_i;
    logic [15:0] smoke_ddr_follow_mi_at_fu_rise_i;
    logic [15:0] smoke_ddr_follow_po_at_ic_fall_i;
    logic [15:0] smoke_ddr_follow_mi_at_ic_fall_i;
    logic [15:0] smoke_ddr_follow_wrap_level_i;
    logic smoke_ddr_c0_pending_i;
    logic smoke_ddr_c0_return_valid_i;
    logic smoke_ddr_c0_return_in_range_i;
    logic smoke_ddr_c0_wait_timeout_seen_i;
    logic [15:0] smoke_ddr_follow_accept_count_i;
    logic [15:0] smoke_ddr_follow_top_request_count_i;
    logic [15:0] smoke_ddr_follow_return_count_i;
    logic [15:0] smoke_ddr_follow_jt_seen_count_i;
    logic [15:0] smoke_ddr_follow_mixer_count_i;
    logic [15:0] smoke_ddr_follow_timeout_count_i;
    logic [15:0] smoke_ddr_c0_wait_count_i;
    logic smoke_ddr_follow_addr_in_range_i;
    logic smoke_ddr_follow_read_in_range_i;
    logic smoke_ddr_follow_range_miss_i;
    logic smoke_ddr_follow_range_seen_i;
    logic smoke_ddr_follow_dest_map_d_i;
    logic [1:0] smoke_ddr_follow_dest_basis_d_i;
    logic smoke_ddr_follow_dest_loop_wrap_d_i;
    logic [15:0] smoke_ddr_follow_wrap_count_i;
    logic [11:0] smoke_ddr_follow_offset_i;
    wire [11:0] smoke_ddr_follow_mapped_next =
        core_rom_addr[11:0] + smoke_ddr_follow_offset_i;
    wire [18:0] smoke_ddr_follow_offset_read_index =
        {7'd0, smoke_ddr_follow_mapped_next};
    logic [31:0] smoke_type80_payload_len_32;
    logic [18:0] smoke_type80_payload_len_19;
    wire [18:0] smoke_type80_dest_addr_19 =
        loaded_type80_rom_dest[18:0];

`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
    // C0-only lab keeps a compact ROM map for captured SegaPCM type80 blocks.
    localparam int unsigned SMOKE_TYPE80_TABLE_ENTRIES = 8;
    localparam logic [3:0] SMOKE_TYPE80_TABLE_LIMIT = 4'd8;
`else
    localparam int unsigned SMOKE_TYPE80_TABLE_ENTRIES = 8;
    localparam logic [3:0] SMOKE_TYPE80_TABLE_LIMIT = 4'd8;
`endif
    logic [20:0] smoke_type80_table_dest_i [0:SMOKE_TYPE80_TABLE_ENTRIES-1];
    logic [18:0] smoke_type80_table_base_i [0:SMOKE_TYPE80_TABLE_ENTRIES-1];
    logic [18:0] smoke_type80_table_len_i [0:SMOKE_TYPE80_TABLE_ENTRIES-1];
    logic smoke_type80_table_valid_i [0:SMOKE_TYPE80_TABLE_ENTRIES-1];
    logic [3:0] smoke_type80_table_count_i;
    logic [18:0] smoke_type80_table_next_base_i;
    logic [20:0] smoke_type80_table_last_dest_i;
    logic [18:0] smoke_type80_table_last_len_i;
    logic [3:0] smoke_type80_table_last_write_index_i;
    logic [20:0] smoke_type80_table_last_write_dest_i;
    logic [18:0] smoke_type80_table_last_write_len_i;
    logic [18:0] smoke_type80_table_last_write_base_i;
    logic smoke_type80_table_last_write_valid_i;
    integer smoke_type80_table_loop_i;
    integer smoke_type80_match_loop_i;

    wire smoke_type80_table_new_block =
        loaded_payload_wr_valid &&
        (smoke_type80_payload_len_19 != 19'd0) &&
        (smoke_type80_table_count_i < SMOKE_TYPE80_TABLE_LIMIT) &&
        ((smoke_type80_table_count_i == 4'd0) ||
         (loaded_type80_rom_dest[20:0] != smoke_type80_table_last_dest_i) ||
         (smoke_type80_payload_len_19 != smoke_type80_table_last_len_i));

    logic [20:0] smoke_c0_mame_full_addr_next;
    logic [20:0] smoke_c0_mame_bank_next;
    logic [15:0] smoke_c0_mame_current_addr_next;
    logic [20:0] smoke_c0_mame_match_dest_next;
    logic [20:0] smoke_c0_mame_offset_21_next;
    logic [18:0] smoke_c0_mame_match_base_next;
    logic [18:0] smoke_c0_mame_match_len_next;
    logic [18:0] smoke_c0_mame_payload_offset_next;
    logic [18:0] smoke_c0_mame_read_index_next;
    logic [2:0] smoke_c0_mame_match_index_next;
    logic smoke_c0_mame_match_valid_next;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
    logic [18:0] lab_jt_payload_read_index_next;
    logic [18:0] lab_jt_payload_offset_next;
    logic [18:0] lab_jt_payload_dest_low_next;
    logic [2:0] lab_jt_payload_block_next;
    logic lab_jt_payload_match_valid_next;
    logic [18:0] lab_jt_map_dest_low_tmp;
    logic [19:0] lab_jt_map_limit_tmp;
    integer lab_jt_map_loop_i;

    always_comb begin
        lab_jt_payload_read_index_next = 19'd0;
        lab_jt_payload_offset_next = 19'd0;
        lab_jt_payload_dest_low_next = 19'd0;
        lab_jt_payload_block_next = 3'd0;
        lab_jt_payload_match_valid_next = 1'b0;
        lab_jt_map_dest_low_tmp = 19'd0;
        lab_jt_map_limit_tmp = 20'd0;

        for (lab_jt_map_loop_i = 0;
             lab_jt_map_loop_i < SMOKE_TYPE80_TABLE_ENTRIES;
             lab_jt_map_loop_i = lab_jt_map_loop_i + 1) begin
            lab_jt_map_dest_low_tmp =
                smoke_type80_table_dest_i[lab_jt_map_loop_i][18:0];
            lab_jt_map_limit_tmp =
                {1'b0, lab_jt_map_dest_low_tmp} +
                {1'b0, smoke_type80_table_len_i[lab_jt_map_loop_i]};
            if (!lab_jt_payload_match_valid_next &&
                smoke_type80_table_valid_i[lab_jt_map_loop_i] &&
                (smoke_type80_table_len_i[lab_jt_map_loop_i] != 19'd0) &&
                (lab_jt_rom_addr >= lab_jt_map_dest_low_tmp) &&
                ({1'b0, lab_jt_rom_addr} < lab_jt_map_limit_tmp)) begin
                lab_jt_payload_match_valid_next = 1'b1;
                lab_jt_payload_block_next = lab_jt_map_loop_i[2:0];
                lab_jt_payload_dest_low_next = lab_jt_map_dest_low_tmp;
                lab_jt_payload_offset_next =
                    lab_jt_rom_addr - lab_jt_map_dest_low_tmp;
                lab_jt_payload_read_index_next =
                    smoke_type80_table_base_i[lab_jt_map_loop_i] +
                    (lab_jt_rom_addr - lab_jt_map_dest_low_tmp);
            end
        end

        if (lab_jt_payload_read_index_next >= smoke_loaded_ddr_usable_bytes) begin
            lab_jt_payload_match_valid_next = 1'b0;
        end
    end
    wire [15:0] lab_jt_bringup_status = {
        8'hA5,
        smoke_c0_jt_backend,
        lab_jt_seen_cpu_write_i,
        lab_jt_seen_rom_cs_i,
        lab_jt_seen_payload_match_i,
        lab_jt_seen_rom_ok_i,
        lab_jt_seen_rom_non80_i,
        lab_jt_seen_output_nonzero_i,
        smoke_ddr_audio_data_ok_i
    };
    wire [15:0] lab_jt_error_status = {
        8'hE0,
        smoke_c0_jt_backend && !lab_jt_seen_cpu_write_i,
        smoke_c0_jt_backend && lab_jt_seen_cpu_write_i &&
            !lab_jt_seen_rom_cs_i,
        smoke_c0_jt_backend && lab_jt_seen_rom_cs_i &&
            !lab_jt_seen_payload_match_i,
        smoke_c0_jt_backend && lab_jt_seen_payload_match_i &&
            !lab_jt_seen_rom_ok_i,
        smoke_c0_jt_backend && lab_jt_seen_rom_ok_i &&
            !lab_jt_seen_rom_non80_i,
        smoke_c0_jt_backend && lab_jt_seen_rom_non80_i &&
            !lab_jt_seen_output_nonzero_i,
        lab_jt_payload_miss_count_i != 16'd0,
        lab_jt_payload_read_index_next >= smoke_loaded_ddr_usable_bytes
    };
`endif
`ifndef MEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE
    logic smoke_c0_first_hit_seen_i;
    logic smoke_c0_first_hit_active_i;
    logic [3:0] smoke_c0_first_hit_capture_count_i;
    logic [7:0] smoke_c0_first_hit_byte_i [0:7];
    logic [15:0] smoke_c0_first_hit_pi_i [0:3];
    logic [15:0] smoke_c0_first_hit_cv_i;
    logic [15:0] smoke_c0_first_hit_ad_i;
    logic [15:0] smoke_c0_first_hit_ec_i;
    logic [15:0] smoke_c0_first_hit_act_i;
    logic [15:0] smoke_c0_first_hit_end_seen_i;
    logic [15:0] smoke_c0_first_hit_flags_i;
    logic smoke_c0_first_hit_done_i;
    logic [3:0] smoke_c0_first_hit_close_reason_i;
    logic [3:0] smoke_c0_first_hit_close_reason_next;
`endif
    localparam int SMOKE_C0_PROBE_BYTES = 4;
    localparam logic [3:0] SMOKE_C0_PROBE_LAST = 4'd3;
    localparam logic [18:0] SMOKE_C0_PROBE_BYTES_19 = 19'd4;
    logic [7:0] smoke_c0_probe_byte_i [0:SMOKE_C0_PROBE_BYTES-1];
    logic [3:0] smoke_c0_probe_req_index_i;
    logic [3:0] smoke_c0_probe_return_index_i;
    logic smoke_c0_probe_req_live_i;
    logic smoke_c0_probe_pending_i;
    logic smoke_c0_probe_done_i;
    logic [15:0] smoke_c0_probe_word0_i;
    logic [15:0] smoke_c0_probe_lane0_i;
    logic [15:0] smoke_c0_probe_word7_i;
    logic [15:0] smoke_c0_probe_lane7_i;
    logic [15:0] smoke_c0_probe_raw_word0_i;
    logic [15:0] smoke_c0_probe_raw_word6_i;
    logic [7:0] smoke_c0_write_probe_byte_i [0:SMOKE_C0_PROBE_BYTES-1];
    logic [15:0] smoke_c0_write_probe_seen_i;
    logic signed [8:0] smoke_c0_sample_cv9_next;
    logic [15:0] smoke_c0_sample_cv16_next;
`ifndef MEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE
    integer smoke_c0_first_hit_loop_i;
`endif
    integer smoke_c0_probe_loop_i;
    integer smoke_c0_write_probe_loop_i;

    wire smoke_c0_probe_entry_valid =
        smoke_type80_table_valid_i[2] &&
        (smoke_type80_table_len_i[2] != 19'd0);
    wire smoke_c0_probe_needed =
        smoke_c0_probe_entry_valid && !smoke_c0_probe_done_i;
    wire [18:0] smoke_c0_probe_read_index =
        smoke_type80_table_base_i[2] +
        {15'd0, smoke_c0_probe_req_index_i};
    wire smoke_c0_write_probe_new_entry2 =
        smoke_type80_table_new_block &&
        (smoke_type80_table_count_i == 4'd2);
    wire smoke_c0_write_probe_base_valid =
        smoke_type80_table_valid_i[2] ||
        smoke_c0_write_probe_new_entry2;
    wire [18:0] smoke_c0_write_probe_base =
        smoke_type80_table_valid_i[2] ?
        smoke_type80_table_base_i[2] :
        smoke_type80_table_next_base_i;
    wire [18:0] smoke_c0_write_probe_offset =
        loaded_payload_wr_addr - smoke_c0_write_probe_base;
    wire smoke_c0_write_probe_hit =
        loaded_payload_wr_valid &&
        smoke_c0_write_probe_base_valid &&
        (loaded_payload_wr_addr >= smoke_c0_write_probe_base) &&
        (smoke_c0_write_probe_offset < SMOKE_C0_PROBE_BYTES_19);

`ifndef MEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE
    wire smoke_c0_first_hit_qual =
        (smoke_c0_drive_sel != 2'd0) &&
        ((c0_capture_ch3_vol_l_i[6:0] != 7'd0) ||
         (c0_capture_ch3_vol_r_i[6:0] != 7'd0)) &&
        smoke_c0_mame_match_valid_next &&
        (smoke_c0_mame_match_index_next == 3'd2);
    wire smoke_c0_first_hit_end_changed =
        smoke_c0_first_hit_active_i &&
        (core_dbg_smoke_end_hit != smoke_c0_first_hit_end_seen_i);
    always @* begin
        smoke_c0_first_hit_close_reason_next = 4'd0;
        if (smoke_c0_first_hit_active_i) begin
            if (smoke_c0_first_hit_end_changed) begin
                smoke_c0_first_hit_close_reason_next = 4'd1;
            end else if ((c0_capture_ch3_vol_l_i[6:0] == 7'd0) &&
                         (c0_capture_ch3_vol_r_i[6:0] == 7'd0)) begin
                smoke_c0_first_hit_close_reason_next = 4'd2;
            end else if (smoke_c0_drive_sel == 2'd0) begin
                smoke_c0_first_hit_close_reason_next = 4'd3;
            end else if (!smoke_c0_mame_match_valid_next ||
                         (smoke_c0_mame_match_index_next != 3'd2)) begin
                smoke_c0_first_hit_close_reason_next = 4'd4;
            end else if (c0_capture_ch3_start_pulse_i) begin
                smoke_c0_first_hit_close_reason_next = 4'd5;
            end
        end
    end
    wire smoke_c0_first_hit_stop =
        smoke_c0_first_hit_close_reason_next != 4'd0;
    wire smoke_c0_first_hit_consume =
        core_dbg_smoke_c0_mixer_consume &&
        smoke_c0_first_hit_qual &&
        (!smoke_c0_first_hit_seen_i || smoke_c0_first_hit_active_i) &&
        !smoke_c0_first_hit_stop;
`endif

    logic [18:0] smoke_ddr_follow_norm_core_next;
    logic [18:0] smoke_ddr_follow_norm_dest_next;
    logic [15:0] smoke_ddr_follow_core_low_next;

    always @* begin
        smoke_type80_payload_len_32 = 32'd0;
        if (loaded_type80_rom_size > 32'd8) begin
            smoke_type80_payload_len_32 =
                loaded_type80_rom_size - 32'd8;
        end

        smoke_type80_payload_len_19 = smoke_type80_payload_len_32[18:0];
        if (smoke_type80_payload_len_32 > 32'h0007_ffff) begin
            smoke_type80_payload_len_19 = 19'h7ffff;
        end

        smoke_ddr_follow_core_low_next = core_rom_addr[15:0];
        if (smoke_ddr_c0drive_addr_source) begin
            smoke_ddr_follow_core_low_next = core_dbg_smoke_cur_live_low;
        end

        smoke_ddr_follow_norm_core_next = core_rom_addr;
        smoke_ddr_follow_norm_dest_next = smoke_type80_dest_addr_19;
        case (smoke_ddr_follow_dest_basis)
            2'd1: begin
                smoke_ddr_follow_norm_core_next =
                    {3'd0, smoke_ddr_follow_core_low_next};
                smoke_ddr_follow_norm_dest_next =
                    {3'd0, smoke_type80_dest_addr_19[15:0]};
            end
            2'd2: begin
                // jtoutrun_pcm rom_addr is {bank, cur_addr[23:8]};
                // convert a byte destination such as 0x32600 to 0x30026.
                smoke_ddr_follow_norm_core_next = core_rom_addr;
                smoke_ddr_follow_norm_dest_next = {
                    smoke_type80_dest_addr_19[18:16],
                    8'd0,
                    smoke_type80_dest_addr_19[15:8]
                };
            end
            2'd3: begin
                smoke_ddr_follow_norm_core_next =
                    {3'd0, smoke_ddr_follow_core_low_next};
                smoke_ddr_follow_norm_dest_next =
                    {3'd0, smoke_type80_dest_addr_19[15:0]};
            end
            default: begin
                smoke_ddr_follow_norm_core_next = core_rom_addr;
                smoke_ddr_follow_norm_dest_next = smoke_type80_dest_addr_19;
            end
        endcase
    end

    always @* begin
        smoke_c0_mame_bank_next =
            ({13'd0, (c0_capture_ch3_ctrl_i & 8'hf8)} << 13);
        smoke_c0_mame_current_addr_next = core_dbg_smoke_cur_live_low;
        if ((smoke_c0_drive_sel != 2'd0) &&
            (smoke_c0_mame_current_addr_next == 16'd0) &&
            ({c0_capture_ch3_cur_high_i,
              c0_capture_ch3_cur_mid_i} != 16'd0)) begin
            smoke_c0_mame_current_addr_next = {
                c0_capture_ch3_cur_high_i,
                c0_capture_ch3_cur_mid_i
            };
        end
        smoke_c0_mame_full_addr_next =
            smoke_c0_mame_bank_next + {5'd0, smoke_c0_mame_current_addr_next};

        smoke_c0_mame_match_valid_next = 1'b0;
        smoke_c0_mame_match_index_next = 3'd0;
        smoke_c0_mame_match_dest_next = 21'd0;
        smoke_c0_mame_offset_21_next = 21'd0;
        smoke_c0_mame_match_base_next = 19'd0;
        smoke_c0_mame_match_len_next = 19'd0;
        smoke_c0_mame_payload_offset_next = 19'd0;
        smoke_c0_mame_read_index_next = 19'd0;

        for (smoke_type80_match_loop_i = 0;
             smoke_type80_match_loop_i < SMOKE_TYPE80_TABLE_ENTRIES;
             smoke_type80_match_loop_i = smoke_type80_match_loop_i + 1) begin
            if (!smoke_c0_mame_match_valid_next &&
                smoke_type80_table_valid_i[smoke_type80_match_loop_i] &&
                (smoke_type80_table_len_i[smoke_type80_match_loop_i] != 19'd0) &&
                (smoke_c0_mame_full_addr_next >=
                 smoke_type80_table_dest_i[smoke_type80_match_loop_i]) &&
                (smoke_c0_mame_full_addr_next <
                 (smoke_type80_table_dest_i[smoke_type80_match_loop_i] +
                  {2'd0, smoke_type80_table_len_i[smoke_type80_match_loop_i]}))) begin
                smoke_c0_mame_match_valid_next = 1'b1;
                smoke_c0_mame_match_index_next =
                    smoke_type80_match_loop_i[2:0];
                smoke_c0_mame_match_dest_next =
                    smoke_type80_table_dest_i[smoke_type80_match_loop_i];
                smoke_c0_mame_match_base_next =
                    smoke_type80_table_base_i[smoke_type80_match_loop_i];
                smoke_c0_mame_match_len_next =
                    smoke_type80_table_len_i[smoke_type80_match_loop_i];
                smoke_c0_mame_offset_21_next =
                    smoke_c0_mame_full_addr_next -
                    smoke_type80_table_dest_i[smoke_type80_match_loop_i];
                smoke_c0_mame_payload_offset_next =
                    smoke_c0_mame_offset_21_next[18:0];
                smoke_c0_mame_read_index_next =
                    smoke_type80_table_base_i[smoke_type80_match_loop_i] +
                    smoke_c0_mame_payload_offset_next;
            end
        end

        if (smoke_c0_mame_read_index_next >= smoke_loaded_ddr_usable_bytes) begin
            smoke_c0_mame_match_valid_next = 1'b0;
        end
    end

    always_comb begin
        smoke_c0_sample_cv9_next =
            $signed({1'b0, core_dbg_smoke_sample_byte[7:0]}) - 9'sd128;
        if (smoke_c0_format_sel[0]) begin
            smoke_c0_sample_cv9_next =
                9'sd128 -
                $signed({1'b0, core_dbg_smoke_sample_byte[7:0]});
        end
        smoke_c0_sample_cv16_next =
            {{7{smoke_c0_sample_cv9_next[8]}}, smoke_c0_sample_cv9_next};
    end

    logic [19:0] smoke_type80_dest_end_20;
    logic [19:0] smoke_ddr_follow_dest_wrap_span_20;
    logic [19:0] smoke_ddr_follow_dest_raw_offset_20;
    logic [19:0] smoke_ddr_follow_dest_effective_offset_20;
    logic [3:0] smoke_ddr_follow_dest_wrap_level_next;
    logic smoke_ddr_follow_dest_after_base_next;
    logic smoke_ddr_follow_dest_addr_in_range_next;
    logic [18:0] smoke_ddr_follow_dest_offset_next;
    logic [18:0] smoke_ddr_follow_dest_effective_offset_next;
    logic smoke_ddr_follow_dest_wrap_this_next;
    logic smoke_ddr_follow_dest_read_in_range_next;
    logic [18:0] smoke_ddr_follow_read_index;
    logic smoke_ddr_follow_read_in_range_next;
    always @* begin
        smoke_type80_dest_end_20 =
            {1'b0, smoke_ddr_follow_norm_dest_next} +
            {1'b0, smoke_type80_payload_len_19};
        smoke_ddr_follow_dest_wrap_span_20 = 20'h80000;
        if ((smoke_ddr_follow_dest_basis == 2'd1) ||
            (smoke_ddr_follow_dest_basis == 2'd3)) begin
            smoke_ddr_follow_dest_wrap_span_20 = 20'h10000;
        end

        smoke_ddr_follow_dest_after_base_next = 1'b0;
        if ({1'b0, smoke_ddr_follow_norm_core_next} >=
            {1'b0, smoke_ddr_follow_norm_dest_next}) begin
            smoke_ddr_follow_dest_after_base_next = 1'b1;
        end

        smoke_ddr_follow_dest_raw_offset_20 =
            {1'b0, smoke_ddr_follow_norm_core_next} -
            {1'b0, smoke_ddr_follow_norm_dest_next};
        if (!smoke_ddr_follow_dest_after_base_next &&
            smoke_ddr_follow_dest_loop_wrap &&
            (smoke_type80_payload_len_19 != 19'd0)) begin
            smoke_ddr_follow_dest_raw_offset_20 =
                smoke_ddr_follow_dest_wrap_span_20 -
                {1'b0, smoke_ddr_follow_norm_dest_next} +
                {1'b0, smoke_ddr_follow_norm_core_next};
        end
        smoke_ddr_follow_dest_offset_next =
            smoke_ddr_follow_dest_raw_offset_20[18:0];

        smoke_ddr_follow_dest_addr_in_range_next = 1'b0;
        if (smoke_ddr_follow_dest_after_base_next &&
            (smoke_type80_payload_len_19 != 19'd0) &&
            ({1'b0, smoke_ddr_follow_norm_core_next} <
             smoke_type80_dest_end_20)) begin
            smoke_ddr_follow_dest_addr_in_range_next = 1'b1;
        end

        smoke_ddr_follow_dest_effective_offset_20 =
            smoke_ddr_follow_dest_raw_offset_20;
        smoke_ddr_follow_dest_wrap_level_next = 4'd0;
        smoke_ddr_follow_dest_wrap_this_next = 1'b0;
        if (smoke_ddr_follow_dest_loop_wrap &&
            (smoke_type80_payload_len_19 != 19'd0)) begin
            if (smoke_ddr_follow_dest_effective_offset_20 >=
                {1'b0, smoke_type80_payload_len_19}) begin
                smoke_ddr_follow_dest_effective_offset_20 =
                    smoke_ddr_follow_dest_effective_offset_20 -
                    {1'b0, smoke_type80_payload_len_19};
                smoke_ddr_follow_dest_wrap_level_next =
                    smoke_ddr_follow_dest_wrap_level_next + 4'd1;
            end
            if (smoke_ddr_follow_dest_effective_offset_20 >=
                {1'b0, smoke_type80_payload_len_19}) begin
                smoke_ddr_follow_dest_effective_offset_20 =
                    smoke_ddr_follow_dest_effective_offset_20 -
                    {1'b0, smoke_type80_payload_len_19};
                smoke_ddr_follow_dest_wrap_level_next =
                    smoke_ddr_follow_dest_wrap_level_next + 4'd1;
            end
            if (smoke_ddr_follow_dest_effective_offset_20 >=
                {1'b0, smoke_type80_payload_len_19}) begin
                smoke_ddr_follow_dest_effective_offset_20 =
                    smoke_ddr_follow_dest_effective_offset_20 -
                    {1'b0, smoke_type80_payload_len_19};
                smoke_ddr_follow_dest_wrap_level_next =
                    smoke_ddr_follow_dest_wrap_level_next + 4'd1;
            end
            if (smoke_ddr_follow_dest_effective_offset_20 >=
                {1'b0, smoke_type80_payload_len_19}) begin
                smoke_ddr_follow_dest_effective_offset_20 =
                    smoke_ddr_follow_dest_effective_offset_20 -
                    {1'b0, smoke_type80_payload_len_19};
                smoke_ddr_follow_dest_wrap_level_next =
                    smoke_ddr_follow_dest_wrap_level_next + 4'd1;
            end
            if (smoke_ddr_follow_dest_effective_offset_20 >=
                {1'b0, smoke_type80_payload_len_19}) begin
                smoke_ddr_follow_dest_effective_offset_20 =
                    smoke_ddr_follow_dest_effective_offset_20 -
                    {1'b0, smoke_type80_payload_len_19};
                smoke_ddr_follow_dest_wrap_level_next =
                    smoke_ddr_follow_dest_wrap_level_next + 4'd1;
            end
            if (smoke_ddr_follow_dest_effective_offset_20 >=
                {1'b0, smoke_type80_payload_len_19}) begin
                smoke_ddr_follow_dest_effective_offset_20 =
                    smoke_ddr_follow_dest_effective_offset_20 -
                    {1'b0, smoke_type80_payload_len_19};
                smoke_ddr_follow_dest_wrap_level_next =
                    smoke_ddr_follow_dest_wrap_level_next + 4'd1;
            end
            if (smoke_ddr_follow_dest_effective_offset_20 >=
                {1'b0, smoke_type80_payload_len_19}) begin
                smoke_ddr_follow_dest_effective_offset_20 =
                    smoke_ddr_follow_dest_effective_offset_20 -
                    {1'b0, smoke_type80_payload_len_19};
                smoke_ddr_follow_dest_wrap_level_next =
                    smoke_ddr_follow_dest_wrap_level_next + 4'd1;
            end
            if (smoke_ddr_follow_dest_effective_offset_20 >=
                {1'b0, smoke_type80_payload_len_19}) begin
                smoke_ddr_follow_dest_effective_offset_20 =
                    smoke_ddr_follow_dest_effective_offset_20 -
                    {1'b0, smoke_type80_payload_len_19};
                smoke_ddr_follow_dest_wrap_level_next =
                    smoke_ddr_follow_dest_wrap_level_next + 4'd1;
            end
            if (smoke_ddr_follow_dest_wrap_level_next != 4'd0) begin
                smoke_ddr_follow_dest_wrap_this_next = 1'b1;
            end
        end
        smoke_ddr_follow_dest_effective_offset_next =
            smoke_ddr_follow_dest_effective_offset_20[18:0];

        smoke_ddr_follow_dest_read_in_range_next = 1'b0;
        if ((smoke_type80_payload_len_19 != 19'd0) &&
            (smoke_ddr_follow_dest_effective_offset_next <
             smoke_loaded_ddr_usable_bytes)) begin
            if (smoke_ddr_follow_dest_addr_in_range_next ||
                (smoke_ddr_follow_dest_loop_wrap &&
                 (smoke_ddr_follow_dest_wrap_this_next ||
                  !smoke_ddr_follow_dest_after_base_next))) begin
                smoke_ddr_follow_dest_read_in_range_next = 1'b1;
            end
        end

        smoke_ddr_follow_read_index = smoke_ddr_follow_offset_read_index;
        smoke_ddr_follow_read_in_range_next =
            (smoke_ddr_follow_offset_read_index <
             SMOKE_LOADED_DDR_BYTES_19);
        if (smoke_ddr_follow_dest_map) begin
            smoke_ddr_follow_read_index =
                smoke_ddr_follow_dest_effective_offset_next;
            smoke_ddr_follow_read_in_range_next =
                smoke_ddr_follow_dest_read_in_range_next;
        end
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        if (smoke_c0_jt_backend) begin
            smoke_ddr_follow_read_index = lab_jt_payload_read_index_next;
            smoke_ddr_follow_read_in_range_next =
                lab_jt_payload_match_valid_next;
        end else
`endif
        if (smoke_ddr_c0drive_active) begin
            smoke_ddr_follow_read_index = smoke_c0_mame_read_index_next;
            smoke_ddr_follow_read_in_range_next =
                smoke_c0_mame_match_valid_next;
        end
    end
    wire smoke_ddr_follow_dest_selector_changed =
        (smoke_ddr_follow_dest_map_d_i != smoke_ddr_follow_dest_map) ||
        (smoke_ddr_follow_dest_basis_d_i != smoke_ddr_follow_dest_basis) ||
        (smoke_ddr_follow_dest_loop_wrap_d_i !=
         smoke_ddr_follow_dest_loop_wrap);
    logic [15:0] smoke_ddr_follow_edge_po_next;
    always @* begin
        smoke_ddr_follow_edge_po_next = smoke_ddr_follow_payload_offset_i;
        if (smoke_ddr_follow_dest_addr_in_range_next) begin
            smoke_ddr_follow_edge_po_next =
                smoke_ddr_follow_dest_offset_next[15:0];
        end
    end
    wire [15:0] smoke_ddr_follow_word_next =
        loaded_ddr_base_addr_debug + {3'd0, smoke_ddr_follow_read_index[15:3]};
    wire [15:0] smoke_ddr_follow_lane_next =
        {13'd0, smoke_ddr_follow_read_index[2:0]};
    wire [7:0] smoke_loaded_payload_data_i = smoke_ddr_audio_byte_hold_i;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_4K_TEST
    localparam int unsigned SMOKE_LOADED_RAM_DEPTH_LOG2_CFG = 12;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_2K_TEST
    localparam int unsigned SMOKE_LOADED_RAM_DEPTH_LOG2_CFG = 11;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_1K_TEST
    localparam int unsigned SMOKE_LOADED_RAM_DEPTH_LOG2_CFG = 10;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_512B_TEST
    localparam int unsigned SMOKE_LOADED_RAM_DEPTH_LOG2_CFG = 9;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_RAM_DEPTH_LOG2
    localparam int unsigned SMOKE_LOADED_RAM_DEPTH_LOG2_CFG =
        `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_RAM_DEPTH_LOG2;
`else
    localparam int unsigned SMOKE_LOADED_RAM_DEPTH_LOG2_CFG = 8;
`endif
    localparam int unsigned SMOKE_LOADED_RAM_ADDR_BITS =
        (SMOKE_LOADED_RAM_DEPTH_LOG2_CFG < 8) ? 8 :
        (SMOKE_LOADED_RAM_DEPTH_LOG2_CFG > 12) ? 12 :
        SMOKE_LOADED_RAM_DEPTH_LOG2_CFG;
    localparam int unsigned SMOKE_LOADED_RAM_BYTES =
        (1 << SMOKE_LOADED_RAM_ADDR_BITS);
    localparam logic [18:0] SMOKE_LOADED_RAM_BYTES_19 =
        SMOKE_LOADED_RAM_BYTES[18:0];
    localparam logic [15:0] SMOKE_LOADED_RAM_DEPTH_LOG2_DEBUG =
        SMOKE_LOADED_RAM_ADDR_BITS;
    logic smoke_loaded_payload_seen_write_i;
    logic smoke_loaded_payload_present_i;
    logic [18:0] smoke_loaded_payload_length_i;
    logic [7:0] smoke_loaded_payload_data_i;
    logic [18:0] smoke_loaded_capture_count_i;
    logic [15:0] smoke_loaded_capture_accept_count_i;
    logic [15:0] smoke_loaded_write_count_i;
    logic [18:0] smoke_loaded_last_write_addr_i;
    logic [7:0] smoke_loaded_last_write_data_i;
    (* ramstyle = "MLAB, no_rw_check" *)
    logic [7:0] smoke_loaded_payload_ram [0:SMOKE_LOADED_RAM_BYTES-1];
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST
    logic [18:0] smoke_loaded_capture_count_i;
    logic [15:0] smoke_loaded_capture_accept_count_i;
    logic [18:0] smoke_loaded_last_write_addr_i;
    logic [7:0] smoke_loaded_last_write_data_i;
    wire smoke_loaded_payload_present_i = 1'b0;
    wire [18:0] smoke_loaded_payload_length_i = 19'd0;
    wire [7:0] smoke_loaded_payload_data_i = 8'h80;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST
    localparam int unsigned SMOKE_LOADED_RAM_BYTES = 16384;
    localparam int unsigned SMOKE_LOADED_RAM_ADDR_BITS =
        $clog2(SMOKE_LOADED_RAM_BYTES);
    localparam logic [18:0] SMOKE_LOADED_RAM_BYTES_19 =
        SMOKE_LOADED_RAM_BYTES[18:0];
    logic smoke_loaded_payload_seen_write_i;
    logic smoke_loaded_payload_present_i;
    logic [18:0] smoke_loaded_payload_length_i;
    logic [7:0] smoke_loaded_payload_data_i;
    logic [18:0] smoke_loaded_capture_count_i;
    logic [15:0] smoke_loaded_capture_accept_count_i;
    logic [15:0] smoke_loaded_write_count_i;
    logic [18:0] smoke_loaded_last_write_addr_i;
    logic [7:0] smoke_loaded_last_write_data_i;
    (* ramstyle = "M10K, no_rw_check" *)
    logic [7:0] smoke_loaded_payload_ram [0:SMOKE_LOADED_RAM_BYTES-1];
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SOURCE_TEST
    localparam int unsigned SMOKE_LOADED_RAM_BYTES = PRELOAD_ROM_BYTES;
    localparam int unsigned SMOKE_LOADED_RAM_ADDR_BITS =
        $clog2(SMOKE_LOADED_RAM_BYTES);
    localparam logic [18:0] SMOKE_LOADED_RAM_BYTES_19 =
        SMOKE_LOADED_RAM_BYTES[18:0];
    logic smoke_loaded_payload_seen_write_i;
    logic smoke_loaded_payload_present_i;
    logic [18:0] smoke_loaded_payload_length_i;
    logic [7:0] smoke_loaded_payload_data_i;
    logic [18:0] smoke_loaded_capture_count_i;
    logic [15:0] smoke_loaded_capture_accept_count_i;
    logic [15:0] smoke_loaded_write_count_i;
    logic [18:0] smoke_loaded_last_write_addr_i;
    logic [7:0] smoke_loaded_last_write_data_i;
    (* ramstyle = "M10K, no_rw_check" *)
    logic [7:0] smoke_loaded_payload_ram [0:SMOKE_LOADED_RAM_BYTES-1];
`else
    wire smoke_loaded_payload_present_i = 1'b0;
    wire [18:0] smoke_loaded_payload_length_i = 19'd0;
    wire [7:0] smoke_loaded_payload_data_i = 8'h80;
`endif
    wire [18:0] smoke_payload_step_ext = {16'd0, smoke_payload_step};
    wire [18:0] smoke_payload_next_addr =
        smoke_payload_addr_i + smoke_payload_step_ext;
    wire [18:0] smoke_mapped_rom_addr =
        (smoke_payload_addr_i < PRELOAD_ROM_BYTES[18:0]) ?
        smoke_payload_addr_i : smoke_payload_base;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    wire [18:0] smoke_loaded_payload_rd_addr =
        {7'd0, smoke_mapped_rom_addr[11:0]};
    wire smoke_loaded_payload_addr_in_range =
        loaded_ddr_payload_present &&
        (smoke_loaded_payload_rd_addr < smoke_loaded_ddr_usable_bytes);
    wire smoke_ddr_audio_active =
        smoke_source_loaded && loaded_ddr_payload_present;
    wire smoke_effective_loaded_source =
        smoke_source_loaded &&
        loaded_ddr_payload_present &&
        smoke_ddr_audio_valid_seen_i;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST
    wire [SMOKE_LOADED_RAM_ADDR_BITS-1:0] smoke_loaded_payload_rd_addr =
        smoke_mapped_rom_addr[SMOKE_LOADED_RAM_ADDR_BITS-1:0];
    wire [18:0] smoke_loaded_payload_length_clamped =
        (loaded_payload_length < SMOKE_LOADED_RAM_BYTES_19) ?
        loaded_payload_length : SMOKE_LOADED_RAM_BYTES_19;
    wire smoke_loaded_payload_addr_in_range =
        smoke_loaded_payload_present_i &&
        (smoke_loaded_payload_rd_addr < smoke_loaded_payload_length_i);
    wire smoke_effective_loaded_source =
        smoke_source_loaded &&
        smoke_loaded_payload_present_i &&
        (smoke_loaded_payload_length_i != 19'd0);
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST
    wire smoke_effective_loaded_source = 1'b0;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST
    wire smoke_loaded_payload_ram_addr_in_range =
        smoke_mapped_rom_addr < SMOKE_LOADED_RAM_BYTES_19;
    wire [SMOKE_LOADED_RAM_ADDR_BITS-1:0] smoke_loaded_payload_rd_addr =
        smoke_loaded_payload_ram_addr_in_range ?
        smoke_mapped_rom_addr[SMOKE_LOADED_RAM_ADDR_BITS-1:0] :
        {SMOKE_LOADED_RAM_ADDR_BITS{1'b0}};
    wire [18:0] smoke_loaded_payload_length_clamped =
        (loaded_payload_length < SMOKE_LOADED_RAM_BYTES_19) ?
        loaded_payload_length : SMOKE_LOADED_RAM_BYTES_19;
    wire smoke_loaded_payload_addr_in_range =
        smoke_loaded_payload_ram_addr_in_range &&
        (smoke_mapped_rom_addr < smoke_loaded_payload_length_i);
    wire smoke_effective_loaded_source =
        smoke_source_loaded &&
        smoke_loaded_payload_present_i &&
        (smoke_loaded_payload_length_i != 19'd0);
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SOURCE_TEST
    wire smoke_loaded_payload_ram_addr_in_range =
        smoke_mapped_rom_addr < SMOKE_LOADED_RAM_BYTES_19;
    wire [SMOKE_LOADED_RAM_ADDR_BITS-1:0] smoke_loaded_payload_rd_addr =
        smoke_loaded_payload_ram_addr_in_range ?
        smoke_mapped_rom_addr[SMOKE_LOADED_RAM_ADDR_BITS-1:0] :
        {SMOKE_LOADED_RAM_ADDR_BITS{1'b0}};
    wire [18:0] smoke_loaded_payload_length_clamped =
        (loaded_payload_length < SMOKE_LOADED_RAM_BYTES_19) ?
        loaded_payload_length : SMOKE_LOADED_RAM_BYTES_19;
    wire smoke_loaded_payload_addr_in_range =
        smoke_loaded_payload_ram_addr_in_range &&
        (smoke_mapped_rom_addr < smoke_loaded_payload_length_i);
    wire smoke_effective_loaded_source =
        smoke_source_loaded &&
        smoke_loaded_payload_present_i &&
        (smoke_loaded_payload_length_i != 19'd0);
`else
    wire smoke_effective_loaded_source = 1'b0;
`endif
    wire smoke_effective_addr_in_range;
`endif
    logic core_rom_cs_d2;
    logic [7:0] preload_rom_data_d;
    logic [7:0] preload_rom_data_d2;
    logic preload_rom_addr_valid;
    logic preload_rom_addr_valid_d;
    logic preload_rom_addr_valid_d2;
    wire [7:0] selected_preload_rom_data;
    wire [7:0] selected_rom_data_before_fallback;
    wire selected_preload_addr_valid;
    wire selected_preload_addr_in_range;
    wire preload_rom_data_valid;
    wire fallback_used;
    wire fallback_used_this_cycle;
    logic [7:0] latched_cpu_addr;
    logic [7:0] latched_cpu_data;
    logic [15:0] latched_raw_addr;
    logic cpu_write_pending;
    logic cpu_write_pulse;
    logic core_cpu_cs;
    logic [15:0] core_write_count_i;
    logic [15:0] core_cen_write_count_i;
    logic core_cpu_cs_d;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
    assign lab_jt_ctrl_write =
        latched_cpu_addr[7] && (latched_cpu_addr[2:0] == 3'd6);
	    assign lab_jt_cpu_data =
	        lab_jt_ctrl_write ?
	        {1'b0, latched_cpu_data[5:3], 1'b0, latched_cpu_data[2:0]} :
	        latched_cpu_data;
	    wire [3:0] lab_jt_write_ch = latched_cpu_addr[6:3];
	    wire [2:0] lab_jt_write_off = latched_cpu_addr[2:0];
	    wire lab_jt_write_high = latched_cpu_addr[7];
	    wire lab_jt_write_low = !latched_cpu_addr[7];
	    wire lab_jt_write_cur =
	        lab_jt_write_high &&
	        ((lab_jt_write_off == 3'd4) || (lab_jt_write_off == 3'd5));
	    wire lab_jt_write_end =
	        lab_jt_write_low && (lab_jt_write_off == 3'd6);
	    wire lab_jt_write_delta =
	        lab_jt_write_low && (lab_jt_write_off == 3'd7);
	    wire lab_jt_write_vol =
	        lab_jt_write_low &&
	        ((lab_jt_write_off == 3'd2) || (lab_jt_write_off == 3'd3));
	    wire lab_jt_write_ctrl =
	        lab_jt_write_high && (lab_jt_write_off == 3'd6);
	    wire lab_jt_write_known =
	        lab_jt_write_cur || lab_jt_write_end || lab_jt_write_delta ||
	        lab_jt_write_vol || lab_jt_write_ctrl;
	    wire [15:0] lab_jt_ch3_current_debug = {
	        lab_jt_ch3_cur_high_i,
	        lab_jt_ch3_cur_mid_i
	    };
	    wire [15:0] lab_jt_ch3_ctrl_debug = {
	        lab_jt_ch3_ctrl_jt_i,
	        lab_jt_ch3_ctrl_raw_i
	    };
	    wire [15:0] lab_jt_ch3_end_delta_debug = {
	        lab_jt_ch3_end_i,
	        lab_jt_ch3_delta_i
	    };
	    wire [15:0] lab_jt_ch3_volume_debug = {
	        lab_jt_ch3_vol_l_i,
	        lab_jt_ch3_vol_r_i
	    };
	    wire [18:0] lab_jt_first_debug_rom_addr =
	        lab_jt_seen_first_ch3_rom_i ?
	        lab_jt_first_ch3_rom_addr_i : lab_jt_first_rom_addr_i;
	    wire [15:0] lab_jt_last_non80_block_status = {
	        8'hA5,
	        4'd0,
	        lab_jt_last_non80_payload_block_i,
	        lab_jt_last_non80_payload_match_i
	    };
	    wire [15:0] lab_jt_write_category_status = {
	        8'hC0,
	        lab_jt_write_cur,
	        lab_jt_write_end,
	        lab_jt_write_delta,
	        lab_jt_write_vol,
	        lab_jt_write_ctrl,
	        !lab_jt_write_known,
	        core_cpu_cs && segapcm_cen,
	        lab_jt_dbg_bank_channel_state[0]
		    };
		    wire [1:0] lab_jt_rom_timing_mode =
		        smoke_c0_jt_backend ? smoke_c0_pm3_mix_mode : 2'd0;
	    wire [7:0] lab_jt_rom_data_to_core =
	        (lab_jt_rom_timing_mode == 2'd1) ?
	            lab_jt_rom_data_hold_i :
	        (lab_jt_rom_timing_mode == 2'd2) ?
	            lab_jt_rom_data_hold_d_i :
	            core_rom_data;
	    wire lab_jt_rom_ok_to_core =
	        (lab_jt_rom_timing_mode == 2'd1) ? lab_jt_rom_data_hold_valid_i :
	        (lab_jt_rom_timing_mode == 2'd2) ?
	            lab_jt_rom_data_hold_valid_d_i :
	            core_rom_ok;
	`endif
    logic [15:0] rom_activity_count_i;
    logic [15:0] rom_range_hit_count_i;
    logic [15:0] rom_range_miss_count_i;
    logic [15:0] rom_return_nonzero_count_i;
    logic [15:0] rom_return_change_count_i;
    logic [15:0] rom_return_neutral_count_i;
    logic [15:0] rom_core_ok_count_i;
    logic [15:0] rom_fallback_count_i;
    logic [15:0] rom_read_valid_count_i;
    logic [18:0] raw_rom_min_addr_i;
    logic [18:0] raw_rom_max_addr_i;
    logic [18:0] last_rom_request_addr_i;
    logic [18:0] last_return_mapped_addr_i;
    logic [7:0] last_return_data_i;
    logic [7:0] return_data_history0_i;
    logic [7:0] return_data_history1_i;
    logic [7:0] return_data_history2_i;
    logic [7:0] return_data_history3_i;
    logic [18:0] ch3_raw_rom_min_addr_i;
    logic [18:0] ch3_raw_rom_max_addr_i;
    logic [18:0] ch3_last_rom_request_addr_i;
    logic [18:0] first_after_ch1_ctrl_addr_i;
    logic [18:0] early_after_ch1_ctrl_addr_i;
    logic [18:0] active_after_ch1_ctrl_addr_i;
    logic raw_rom_minmax_seen_i;
    logic ch3_raw_rom_minmax_seen_i;
    logic first_after_ch1_ctrl_pending_i;
    logic first_after_ch1_ctrl_seen_i;
    logic early_after_ch1_ctrl_pending_i;
    logic early_after_ch1_ctrl_seen_i;
    logic active_after_ch1_ctrl_pending_i;
    logic active_after_ch1_ctrl_seen_i;
    logic known38686_exact_seen_i;
    logic known38686_range_seen_i;
    logic known38686_valid_i;
    logic [2:0] known38686_bank_i;
    logic [3:0] known38686_channel_i;
    logic [3:0] known38686_state_i;
    logic [15:0] known38686_cur_high_i;
    logic [7:0] known38686_cur_low_i;
    wire known38686_state8_channel3 = known38686_valid_i &&
                                      (known38686_channel_i == 4'd3) &&
                                      (known38686_state_i == 4'd8);
    wire [23:0] known38686_before_addr = {known38686_cur_high_i, known38686_cur_low_i};
    wire [23:0] known38686_after_addr = known38686_before_addr + {16'd0, core_dbg_38686_delta[7:0]};
    logic ch1_ctrl_write_seen_i;
    logic mode9_overflow_seen_i;
    logic [7:0] rom_range_group_i;
    logic [7:0] rom_range_group2_i;
    logic [7:0] ch3_rom_range_i;
    logic rom_request_event;
    logic ch3_rom_request_event;
    logic rom_return_event;
    logic [18:0] selected_mapped_rom_addr;
    logic [15:0] audio_nonzero_count_i;
    logic [15:0] audio_abs_peak_i;
    logic signed [15:0] last_audio_l_i;
    logic signed [15:0] last_audio_r_i;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
    logic [15:0] lab_c0_sb_debug_i;
    logic signed [15:0] lab_c0_so_debug_i;
    logic signed [15:0] lab_c0_lo_debug_i;
    logic signed [15:0] lab_c0_mo_debug_i;
    logic [15:0] lab_c0_mux_err_i;
`endif
    logic [7:0] shadow_ram [0:255];
    logic [15:0] shadow_decode_i;
    logic [15:0] active_req_start_debug_i;
    logic [15:0] active_req_loop_debug_i;
    logic [15:0] active_req_end_delta_debug_i;
    logic [15:0] active_req_rate_debug_i;
    logic [15:0] active_req_amp_pan_debug_i;
    logic [15:0] active_req_cfg_debug_i;
    logic [15:0] active_req_next_debug_i;
    logic [15:0] active_req_page_debug_i;
    logic [15:0] active_req_flow_debug_i;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    localparam logic [1:0] SMOKE_C0_ENDCMP_PAGE_PLUS1 = 2'd0;
    localparam logic [1:0] SMOKE_C0_LOOPSRC_LOOP00 = 2'd0;
    wire [1:0] smoke_c0_endcmp_sel = SMOKE_C0_ENDCMP_PAGE_PLUS1;
    wire [1:0] smoke_c0_loopsrc_sel = SMOKE_C0_LOOPSRC_LOOP00;
    wire smoke_c0_use_vol_i =
        smoke_ddr_follow_mode &&
        ((smoke_c0_use_sel == 2'd1) || (smoke_c0_use_sel == 2'd3));
    wire smoke_c0_use_delta_i =
        smoke_ddr_follow_mode &&
        ((smoke_c0_use_sel == 2'd2) || (smoke_c0_use_sel == 2'd3));
    wire [7:0] smoke_delta =
        smoke_c0_use_delta_i ? c0_capture_ch3_delta_i :
        smoke_ddr_follow_delta_i;
    wire [23:0] smoke_c0_current_seed_i = {
        c0_capture_ch3_cur_high_i,
        c0_capture_ch3_cur_mid_i,
        8'd0
    };
    wire [23:0] smoke_c0_loop_seed_base_i = {
        c0_capture_ch3_loop_high_i,
        c0_capture_ch3_loop_mid_i,
        8'd0
    };
    wire [23:0] smoke_c0_loop_seed_low_i = {
        c0_capture_ch3_loop_high_i,
        c0_capture_ch3_loop_mid_i,
        c0_capture_ch3_cur_low_i
    };
    logic [23:0] smoke_c0_loop_seed_i;
    always_comb begin
        smoke_c0_loop_seed_i = smoke_c0_loop_seed_base_i;
        unique case (smoke_c0_loopsrc_sel)
            2'd1: smoke_c0_loop_seed_i = smoke_c0_loop_seed_low_i;
            2'd2: smoke_c0_loop_seed_i = smoke_c0_current_seed_i;
            default: smoke_c0_loop_seed_i = smoke_c0_loop_seed_base_i;
        endcase
    end
    wire [6:0] smoke_c0_vol_l_raw = c0_capture_ch3_vol_l_i[6:0];
    wire [6:0] smoke_c0_vol_r_raw = c0_capture_ch3_vol_r_i[6:0];
    wire [6:0] smoke_c0_vol_l_x2 =
        (smoke_c0_vol_l_raw > 7'h3f) ? 7'h7f :
        (smoke_c0_vol_l_raw << 1);
    wire [6:0] smoke_c0_vol_r_x2 =
        (smoke_c0_vol_r_raw > 7'h3f) ? 7'h7f :
        (smoke_c0_vol_r_raw << 1);
    wire [6:0] smoke_c0_vol_l_x4 =
        (smoke_c0_vol_l_raw > 7'h1f) ? 7'h7f :
        (smoke_c0_vol_l_raw << 2);
    wire [6:0] smoke_c0_vol_r_x4 =
        (smoke_c0_vol_r_raw > 7'h1f) ? 7'h7f :
        (smoke_c0_vol_r_raw << 2);
    wire [6:0] smoke_c0_vol_l_minboost =
        (smoke_c0_vol_l_raw == 7'd0) ? 7'd0 :
        (smoke_c0_vol_l_raw < 7'h20) ? 7'h20 :
        smoke_c0_vol_l_raw;
    wire [6:0] smoke_c0_vol_r_minboost =
        (smoke_c0_vol_r_raw == 7'd0) ? 7'd0 :
        (smoke_c0_vol_r_raw < 7'h20) ? 7'h20 :
        smoke_c0_vol_r_raw;
    wire [6:0] smoke_c0_vol_l_mapped =
        (smoke_c0_vol_map_sel == 3'd1) ? smoke_c0_vol_l_x2 :
        (smoke_c0_vol_map_sel == 3'd2) ? smoke_c0_vol_l_x4 :
        (smoke_c0_vol_map_sel == 3'd3) ? smoke_c0_vol_l_minboost :
        (smoke_c0_vol_map_sel == 3'd4) ? (7'h7f - smoke_c0_vol_l_raw) :
        (smoke_c0_vol_map_sel == 3'd5) ? smoke_vol_l :
        smoke_c0_vol_l_raw;
    wire [6:0] smoke_c0_vol_r_mapped =
        (smoke_c0_vol_map_sel == 3'd1) ? smoke_c0_vol_r_x2 :
        (smoke_c0_vol_map_sel == 3'd2) ? smoke_c0_vol_r_x4 :
        (smoke_c0_vol_map_sel == 3'd3) ? smoke_c0_vol_r_minboost :
        (smoke_c0_vol_map_sel == 3'd4) ? (7'h7f - smoke_c0_vol_r_raw) :
        (smoke_c0_vol_map_sel == 3'd5) ? smoke_vol_r :
        smoke_c0_vol_r_raw;
    wire [6:0] smoke_vol_l_selected =
        smoke_c0_use_vol_i ? smoke_c0_vol_l_mapped : smoke_vol_l;
    wire [6:0] smoke_vol_r_selected =
        smoke_c0_use_vol_i ? smoke_c0_vol_r_mapped : smoke_vol_r;
    wire [15:0] smoke_ap_debug =
        {1'b0, smoke_vol_l_selected, 1'b0, smoke_vol_r_selected};
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
    localparam logic [2:0] LAB_C0_PUMP_FORCE_CONST = 3'd0;
    localparam logic [2:0] LAB_C0_PUMP_FIXED_SEQ = 3'd1;
    localparam logic [2:0] LAB_C0_PUMP_LOCAL_SEQ = 3'd2;
    localparam logic [2:0] LAB_C0_PUMP_LOCAL_DELTA = 3'd3;
    localparam logic [2:0] LAB_C0_PUMP_MAME_EXACT = 3'd4;
    localparam logic [2:0] LAB_C0_ST_IDLE = 3'd0;
    localparam logic [2:0] LAB_C0_ST_REQ = 3'd1;
    localparam logic [2:0] LAB_C0_ST_WAIT = 3'd2;
    localparam logic [2:0] LAB_C0_ST_CONSUME = 3'd3;
    logic lab_c0_active_i;
    logic [15:0] lab_c0_seed_i;
    logic [15:0] lab_c0_cur_i;
    logic [2:0] lab_c0_state_i;
    logic [18:0] lab_c0_pi_i;
    logic [18:0] lab_c0_return_pi_i;
    logic [15:0] lab_c0_advance_count_i;
    logic [15:0] lab_c0_stall_count_i;
    logic [15:0] lab_c0_request_count_i;
    logic [15:0] lab_c0_return_count_i;
    logic [7:0] lab_c0_sample_i;
    logic signed [15:0] lab_c0_output_i;
    logic lab_c0_consume_pulse_i;
    logic lab_c0_pending_i;
    logic lab_c0_req_live_i;
    logic lab_c0_need_read_i;
    logic [18:0] lab_c0_req_addr_i;
    logic [2:0] lab_c0_fixed_index_i;
    logic [11:0] lab_c0_fixed_div_i;
    logic [3:0] lab_c0_mame_tick_div_count_i;
    logic [15:0] lab_c0_mame_tick_count_i;
    logic [26:0] lab_c0_phase_i;
    logic [15:0] lab_c0_retrigger_count_i;
    logic [15:0] lab_c0_reseed_count_i;
    logic [15:0] lab_c0_pm4_write_count_i;
    logic [15:0] lab_c0_pm4_reseed_count_i;
    logic [15:0] lab_c0_pm4_reseed_reason_i;
    logic [15:0] lab_c0_event_time_i;
    logic [15:0] lab_c0_event_seed_i;
    logic [18:0] lab_c0_reseed_pi_i;
    logic [15:0] lab_c0_hit_count_i;
    logic        lab_c0_mame_trace_armed_i;
    logic [2:0]  lab_c0_mame_trace_count_i;
    logic [15:0] lab_c0_mame_k0_i;
    logic [15:0] lab_c0_mame_k1_i;
    logic [15:0] lab_c0_mame_k2_i;
    logic [15:0] lab_c0_mame_k3_i;
    logic [15:0] lab_c0_mame_b0_i;
    logic [15:0] lab_c0_mame_b1_i;
    logic [15:0] lab_c0_mame_b2_i;
    logic [15:0] lab_c0_mame_b3_i;
    logic [15:0] lab_c0_mame_c0_i;
    logic [15:0] lab_c0_mame_c1_i;
    logic [15:0] lab_c0_mame_c2_i;
    logic [15:0] lab_c0_mame_c3_i;
    logic        lab_c0_mame_loop_seen_i;
    logic        lab_c0_mame_loud_armed_i;
    logic        lab_c0_mame_loud_active_i;
    logic [2:0]  lab_c0_mame_loud_count_i;
    logic [15:0] lab_c0_mame_loud_p0_i;
    logic [15:0] lab_c0_mame_loud_p1_i;
    logic [15:0] lab_c0_mame_loud_p2_i;
    logic [15:0] lab_c0_mame_loud_p3_i;
    logic [15:0] lab_c0_mame_loud_q0_i;
    logic [15:0] lab_c0_mame_loud_q1_i;
    logic [15:0] lab_c0_mame_loud_q2_i;
    logic [15:0] lab_c0_mame_loud_q3_i;
    logic [15:0] lab_c0_mame_loud_m0_i;
    logic [15:0] lab_c0_mame_loud_m1_i;
    logic [15:0] lab_c0_mame_loud_m2_i;
    logic [15:0] lab_c0_mame_loud_m3_i;
    logic [15:0] lab16_active_i;
    logic [15:0] lab16_strict_seen_i;
    logic [7:0]  lab16_ctrl_i [0:15];
    logic [7:0]  lab16_cur_mid_i [0:15];
    logic [7:0]  lab16_cur_high_i [0:15];
    logic [7:0]  lab16_loop_mid_i [0:15];
    logic [7:0]  lab16_loop_high_i [0:15];
    logic [7:0]  lab16_end_i [0:15];
    logic [7:0]  lab16_delta_i [0:15];
    logic [6:0]  lab16_vol_l_i [0:15];
    logic [6:0]  lab16_vol_r_i [0:15];
    logic [26:0] lab16_phase_i [0:15];
    logic [18:0] lab16_pi_i [0:15];
    logic [18:0] lab16_start_i [0:15];
    logic [18:0] lab16_base_i [0:15];
    logic [18:0] lab16_limit_i [0:15];
    logic [2:0]  lab16_block_i [0:15];
    logic        lab16_map_valid_i [0:15];
    logic [2:0]  lab16_sticky_block_i [0:15];
    logic [15:0] lab16_sticky_map_i;
    logic [7:0]  lab16_sample_i [0:15];
    logic signed [15:0] lab16_out_l_i [0:15];
    logic signed [15:0] lab16_out_r_i [0:15];
    logic        lab16_mix_fresh_i [0:15];
    logic [7:0]  lab16_hold_sample_i [0:15];
    logic signed [8:0] lab16_hold_cv_i [0:15];
    logic [15:0] lab16_start_current_i [0:15];
    logic [15:0] lab16_start_full_low_i [0:15];
    logic [15:0] lab16_start_end_low_i [0:15];
    logic [15:0] lab16_first8_01_i [0:15];
    logic [15:0] lab16_first8_23_i [0:15];
    logic [15:0] lab16_first8_45_i [0:15];
    logic [15:0] lab16_first8_67_i [0:15];
    logic [3:0]  lab16_first8_count_i [0:15];
    logic [3:0] lab16_rr_ch_i;
    logic [3:0] lab16_pending_ch_i;
    logic [11:0] lab16_emit_div_i;
    logic [15:0] lab16_request_count_i;
    logic [15:0] lab16_return_count_i;
    logic [15:0] lab16_clip_count_i;
    logic [15:0] lab16_retrigger_count_i;
    logic [15:0] lab16_reseed_count_i;
    logic [15:0] lab16_ch3_reseed_count_i;
    logic [15:0] lab16_ch3_stop_reason_i;
    logic        lab16_ch3_map_valid_i;
    logic [15:0] lab16_ch3_tick_count_i;
    logic [15:0] lab16_ch3_emit_count_i;
    logic [15:0] lab16_ch3_output_i;
    logic [15:0] lab16_ch3_hold_i;
    logic [15:0] lab16_ch3_sticky_i;
    logic [15:0] lab16_ch3_range_count_i;
    logic [15:0] lab16_ch3_hit_len_i;
    logic [15:0] lab16_ch3_intro_reseed_count_i;
    logic [15:0] lab16_mix_peak_i;
    logic [15:0] lab16_ch3_peak_i;
    logic [15:0] lab16_map_hit_count_i;
    logic [15:0] lab16_map_miss_count_i;
    logic [15:0] lab16_ever_active_i;
    logic [15:0] lab16_ever_nonzero_i;
    logic [4:0]  lab16_max_active_count_i;
    logic [15:0] lab16_start_tuple_count_i;
    logic [15:0] lab16_target_start_count_i;
    logic [15:0] lab16_skipped_start_count_i;
    logic [15:0] lab16_target_current_i;
    logic [15:0] lab16_target_full_low_i;
    logic [7:0]  lab16_target_match_bits_i;
    logic [3:0]  lab16_start_tuple_ch_i;
    logic [2:0]  lab16_start_tuple_block_i;
    logic [15:0] lab16_start_tuple_current_i;
    logic [20:0] lab16_start_tuple_bank_i;
    logic [20:0] lab16_start_tuple_full_addr_i;
    logic [7:0]  lab16_start_tuple_delta_i;
    logic [6:0]  lab16_start_tuple_vol_l_i;
    logic [6:0]  lab16_start_tuple_vol_r_i;
    logic [15:0] lab16_start_tuple_source_i;
    logic        lab16_start_tuple_valid_i;
    logic        lab16_first_samples_valid_i;
    logic        lab16_first_capture_armed_i;
    logic        lab16_first_capture_has_any_i;
    logic        lab16_first_capture_reader_match_i;
    logic        lab16_first_capture_overwrite_i;
    logic        lab16_first_capture_cleared_i;
    logic        lab16_runtime_active_seen_i;
    logic [15:0] lab16_runtime_consume_count_i;
    logic [15:0] lab16_runtime_status_i;
    logic [15:0] lab16_runtime_offset_i;
    logic [15:0] lab16_runtime_addr_i;
    logic [15:0] lab16_runtime_pr_hold_i;
    logic [18:0] lab16_runtime_pi_i;
    logic [15:0] lab16_runtime_phase_hint_i;
    logic [15:0] lab16_runtime_rd_i;
    logic signed [15:0] lab16_runtime_l_i;
    logic signed [15:0] lab16_runtime_r_i;
    logic [15:0] lab16_runtime_stop_i;
    logic [20:0] lab16_start_tuple_end_addr_i;
    logic [18:0] lab16_start_tuple_limit_i;
    logic        lab16_start_tuple_end_limited_i;
    logic [18:0] lab16_last_stop_pi_i;
    logic [15:0] lab16_end_debug_flags_i;
    logic lab16_stop_valid_i;
    logic [15:0] lab16_stop_count_i;
    logic [15:0] lab16_stop_offset_i;
    logic [15:0] lab16_stop_pi_i;
    logic [15:0] lab16_stop_full_i;
    logic [15:0] lab16_stop_phase_i;
    logic [15:0] lab16_stop_flags_i;
    logic [15:0] lab16_first_s0_addr_i;
    logic [15:0] lab16_first_s0_index_i;
    logic [15:0] lab16_first_s0_phase_i;
    logic [15:0] lab16_first_s0_capture_count_i;
    logic [4:0]  lab16_first_sample_count_i;
    logic [15:0] lab16_first_raw01_i;
    logic [15:0] lab16_first_raw23_i;
    logic [15:0] lab16_first_raw45_i;
    logic [15:0] lab16_first_raw67_i;
    logic [15:0] lab16_first_raw89_i;
    logic [15:0] lab16_first_rawab_i;
    logic [15:0] lab16_first_rawcd_i;
    logic [15:0] lab16_first_rawef_i;
    logic [15:0] lab16_first_dec01_i;
    logic [15:0] lab16_first_dec23_i;
    logic [15:0] lab16_first_dec45_i;
    logic [15:0] lab16_first_dec67_i;
    logic [15:0] lab16_first_dec89_i;
    logic [15:0] lab16_first_decab_i;
    logic [15:0] lab16_first_deccd_i;
    logic [15:0] lab16_first_decef_i;
    logic [15:0] lab16_wave_rawcv0_i;
    logic [15:0] lab16_wave_addr0_i;
    logic [15:0] lab16_wave_pi0_i;
    logic [15:0] lab16_wave_out0_i;
    logic [15:0] lab16_wave_rawcv1_i;
    logic [15:0] lab16_wave_addr1_i;
    logic [15:0] lab16_wave_pi1_i;
    logic [15:0] lab16_wave_out1_i;
    logic [15:0] lab16_wave_rawcv2_i;
    logic [15:0] lab16_wave_addr2_i;
    logic [15:0] lab16_wave_pi2_i;
    logic [15:0] lab16_wave_out2_i;
    logic [15:0] lab16_wave_rawcv3_i;
    logic [15:0] lab16_wave_addr3_i;
    logic [15:0] lab16_wave_pi3_i;
    logic [15:0] lab16_wave_out3_i;
    logic [15:0] lab16_wave_vol_i;
    logic [15:0] lab16_ch3_raw_event_count_i;
    logic [15:0] lab16_ch3_block_hit_count_i;
    logic [20:0] lab16_ch3_full_addr_i;
    logic [2:0]  lab16_ch3_block_i;
    logic [20:0] lab16_ch3_block_dest_i;
    logic [18:0] lab16_ch3_block_base_i;
    logic [18:0] lab16_ch3_block_len_i;
    logic [18:0] lab16_ch3_block_offset_i;
    logic [15:0] lab16_ch3_reject_i;
    logic        lab16_ch3_snapshot_valid_i;
    logic [15:0] lab16_ch3_snapshot_count_i;
    logic [7:0]  lab16_ch3_snapshot_ctrl_i;
    logic [6:0]  lab16_ch3_snapshot_vol_l_i;
    logic [6:0]  lab16_ch3_snapshot_vol_r_i;
    logic [7:0]  lab16_ch3_snapshot_delta_i;
    logic [15:0] lab16_ch3_snapshot_current_i;
    logic [20:0] lab16_ch3_snapshot_full_addr_i;
    logic [20:0] lab16_ch3_snapshot_bank_i;
    logic        lab16_ch3_snapshot_hit_i;
    logic [2:0]  lab16_ch3_snapshot_block_i;
    logic [20:0] lab16_ch3_snapshot_dest_i;
    logic [18:0] lab16_ch3_snapshot_base_i;
    logic [18:0] lab16_ch3_snapshot_len_i;
    logic [18:0] lab16_ch3_snapshot_offset_i;
    logic [15:0] lab16_ch3_snapshot_reject_i;
    logic signed [23:0] lab16_mix_l_i;
    logic signed [23:0] lab16_mix_r_i;
    logic signed [15:0] lab16_mix_l_sample_i;
    logic signed [15:0] lab16_mix_r_sample_i;
    logic [3:0] lab16_debug_ch_i;
    logic [3:0] lab16_view_ch;
    logic [15:0] lab16_block_summary_03;
    logic [15:0] lab16_block_summary_47;
    logic [3:0] lab16_loud_ch;
    logic [15:0] lab16_loud_abs;
    logic lab16_loud_valid;
    logic [19:0] lab16_ch3_snapshot_local_start_20;
    logic lab16_loud_snap_valid_i;
    logic [15:0] lab16_loud_snap_abs_i;
    logic [3:0] lab16_loud_snap_ch_i;
    logic [2:0] lab16_loud_snap_block_i;
    logic [18:0] lab16_loud_snap_start_i;
    logic [18:0] lab16_loud_snap_pi_i;
    logic [7:0] lab16_loud_snap_sample_i;
    logic signed [8:0] lab16_loud_snap_cv_i;
    logic signed [15:0] lab16_loud_snap_out_i;
    logic [15:0] lab16_loud_snap_delta_reason_i;
    logic [15:0] lab16_loud_snap_volume_i;
    logic [15:0] lab16_loud_snap_reason_i;
    logic        lab16_expl_valid_i;
    logic [15:0] lab16_expl_count_i;
    logic [15:0] lab16_expl_abs_i;
    logic [3:0]  lab16_expl_ch_i;
    logic [2:0]  lab16_expl_block_i;
    logic [15:0] lab16_expl_current_i;
    logic [15:0] lab16_expl_end_i;
    logic [7:0]  lab16_expl_delta_i;
    logic [15:0] lab16_expl_volume_i;
    logic [15:0] lab16_expl_base_i;
    logic [15:0] lab16_expl_first_index_i;
    logic [15:0] lab16_expl_index_i;
    logic [15:0] lab16_expl_raw_cv_i;
    logic signed [15:0] lab16_expl_l_i;
    logic signed [15:0] lab16_expl_r_i;
    logic [15:0] lab16_expl_mix_i;
    logic [15:0] lab16_expl_active_i;
    logic [15:0] lab16_expl_reason_i;
    logic [15:0] lab16_expl_e0_i;
    logic [15:0] lab16_expl_e1_i;
    logic [15:0] lab16_expl_e2_i;
    logic [15:0] lab16_expl_e3_i;
    logic        lab16_expl_first8_done_i;
    logic [15:0] lab16_ch3_live_count_i;
    logic [15:0] lab16_ch3_live_pi_i;
    logic [15:0] lab16_ch3_live_offset_i;
    logic [15:0] lab16_ch3_live_phase_i;
    logic [15:0] lab16_ch3_live_raw_cv_i;
    logic signed [15:0] lab16_ch3_live_l_i;
    logic [15:0] lab16_ch3_live_reason_i;
    logic [15:0] lab16_ch3_snap_abs_i;
    logic [15:0] lab16_ch3_snap_pi_i;
    logic [15:0] lab16_ch3_snap_offset_i;
    logic [15:0] lab16_ch3_snap_phase_i;
    logic [15:0] lab16_ch3_snap_raw_cv_i;
    logic signed [15:0] lab16_ch3_snap_l_i;
    logic [15:0] lab16_ch3_snap_reason_i;
    logic [15:0] lab16_ch3_snap_base_i;
    logic [15:0] lab16_ch3_snap_limit_i;
    logic [15:0] lab16_ch3_snap_block_i;
    logic [15:0] lab16_ch3_write_count_i;
    logic [15:0] lab16_ch3_current_update_count_i;
    logic [15:0] lab16_ch3_end_delta_update_count_i;
    logic [15:0] lab16_ch3_end_update_count_i;
    logic [15:0] lab16_ch3_delta_update_count_i;
    logic [15:0] lab16_ch3_ctrl_update_count_i;
    logic [15:0] lab16_ch3_volume_update_count_i;
    logic [15:0] lab16_ch3_retrig_write_i;
    logic [15:0] lab16_ch3_active_start_count_i;
    logic [15:0] lab16_ch3_ignored_update_count_i;
    logic [15:0] lab16_ch3_clear_count_i;
    logic [15:0] lab16_ch3_last_retrigger_time_i;
    logic [15:0] lab16_ch3_last_write_time_i;
    logic [15:0] lab16_ch3_last_read_time_i;
    logic [15:0] lab16_ch3_last_clear_time_i;
    logic [15:0] lab16_ch3_last_expl_time_i;
    logic        lab16_ch3_retrig_valid_i;
    logic [15:0] lab16_ch3_retrig_count_i;
    logic [15:0] lab16_ch3_broad_restart_count_i;
    logic [15:0] lab16_ch3_qualified_start_count_i;
    logic [15:0] lab16_ch3_selected_reposition_count_i;
    logic [15:0] lab16_ch3_selected_active_current_count_i;
    logic [15:0] lab16_ch3_qual_duplicate_count_i;
    logic [15:0] lab16_ch3_qual_backward_count_i;
    logic [15:0] lab16_ch3_qual_forward_small_count_i;
    logic [15:0] lab16_ch3_qual_far_count_i;
    logic [15:0] lab16_ch3_qual_end_near_count_i;
    logic [15:0] lab16_ch3_qual_last_flags_i;
    logic [15:0] lab16_ch3_qual_last_old_current_i;
    logic [15:0] lab16_ch3_qual_last_new_current_i;
    logic [15:0] lab16_ch3_qual_last_old_pi_i;
    logic signed [15:0] lab16_ch3_qual_last_old_l_i;
    logic [15:0] lab16_ch3_retrig_time_i;
    logic [15:0] lab16_ch3_retrig_flags_i;
    logic [15:0] lab16_ch3_retrig_old_current_i;
    logic [15:0] lab16_ch3_retrig_old_pi_i;
    logic [15:0] lab16_ch3_retrig_old_offset_i;
    logic [15:0] lab16_ch3_retrig_old_phase_i;
    logic signed [15:0] lab16_ch3_retrig_old_l_i;
    logic [15:0] lab16_ch3_retrig_new_current_i;
    logic [15:0] lab16_ch3_retrig_new_end_i;
    logic [15:0] lab16_ch3_retrig_new_delta_i;
    logic [15:0] lab16_ch3_retrig_new_pi_i;
    logic [15:0] lab16_ch3_retrig_new_offset_i;
    logic [15:0] lab16_ch3_retrig_base_i;
    logic [15:0] lab16_ch3_retrig_limit_i;
    logic [15:0] lab16_ch3_retrig_block_i;
    logic [15:0] lab16_ch3_retrig_first0_i;
    logic [15:0] lab16_ch3_retrig_first1_i;
    logic [15:0] lab16_ch3_retrig_first2_i;
    logic [15:0] lab16_ch3_retrig_first3_i;
    logic signed [15:0] lab16_ch3_retrig_first_l_i;
    logic [15:0] lab16_ch3_retrig_first_pi_i;
    logic [15:0] lab16_ch3_retrig_first_offset_i;
    logic [3:0]  lab16_ch3_retrig_first_count_i;
    logic [15:0] lab16_ch3_worst_abs_i;
    logic [15:0] lab16_ch3_worst_pi_i;
    logic [15:0] lab16_ch3_worst_time_i;
    logic [15:0] lab16_ch3_worst_rc_i;
    logic [15:0] lab16_ch3_worst_offset_i;
    logic [15:0] lab16_ch3_worst_current_i;
    logic [15:0] lab16_ch3_worst_raw_cv_i;
    logic signed [15:0] lab16_ch3_worst_l_i;
    logic [15:0] lab16_ch3_worst_reason_i;
    logic [15:0] lab16_ch3_hold_mix_count_i;
    logic [15:0] lab16_ch3_fresh_read_count_i;
    logic [15:0] lab16_ch3_mix_contrib_count_i;
    logic [15:0] lab16_ch3_output_clear_count_i;
    logic [15:0] lab16_ch3_end_reached_count_i;
    logic [15:0] lab16_ch3_no_read_mix_count_i;
    logic [15:0] lab16_ch3_clear_end_count_i;
    logic [15:0] lab16_ch3_clear_disable_count_i;
    logic [15:0] lab16_ch3_clear_volume_count_i;
    logic [15:0] lab16_ch3_clear_map_count_i;
    localparam logic [1:0] LAB16_PM3_MIX_HOLD  = 2'd0;
    localparam logic [1:0] LAB16_PM3_MIX_FRESH = 2'd1;
    localparam logic [1:0] LAB16_PM3_MIX_GATE  = 2'd2;
    localparam logic [2:0] LAB16_PM3_START_STRICT       = 3'd0;
    localparam logic [2:0] LAB16_PM3_START_QUAL_RESTART = 3'd1;
    localparam logic [2:0] LAB16_PM3_START_QUAL_REPOS   = 3'd2;
    localparam logic [2:0] LAB16_PM3_START_QUAL_IDLE    = 3'd3;
    localparam logic [2:0] LAB16_PM3_START_BROAD        = 3'd4;
    localparam logic [2:0] LAB16_PM3_START_BACK_ONLY    = 3'd5;
    localparam logic [2:0] LAB16_PM3_START_NO_DUP       = 3'd6;
    localparam logic [2:0] LAB16_PM3_START_NEAR_ONLY    = 3'd7;
    logic lab16_snap_view;
    logic [2:0] lab16_selected_block;
    logic [18:0] lab16_selected_start;
    logic [18:0] lab16_selected_pi;
    logic [15:0] lab16_selected_delta_reason;
    logic [15:0] lab16_selected_volume;
    logic [15:0] lab16_selected_reason;
    logic [15:0] lab16_abs_l_tmp;
    logic [15:0] lab16_abs_r_tmp;
    logic [15:0] lab16_abs_tmp;
    logic lab16_comb_mix_ok;
    integer lab16_loop_i;
    wire lab_c0_return_pulse =
        loaded_ddr_rd_valid &&
        smoke_ddr_c0drive_active &&
        lab_c0_pending_i;
    wire lab16_ch3_return_pulse =
        lab_c0_return_pulse &&
        (lab16_pending_ch_i == 4'd3) &&
        smoke_c0_pm3_audio_mask[3];
    wire lab16_ch3_mix_hold_ok =
        smoke_c0_pm3_audio_mask[3] &&
        lab16_active_i[3];
    wire lab16_ch3_mix_gate_ok =
        lab16_ch3_mix_hold_ok &&
        lab16_map_valid_i[3] &&
        (lab16_pi_i[3] >= lab16_base_i[3]) &&
        (lab16_pi_i[3] < lab16_limit_i[3]) &&
        !lab16_ctrl_i[3][0] &&
        ((lab16_vol_l_i[3] != 7'd0) ||
         (lab16_vol_r_i[3] != 7'd0));
    wire lab16_ch3_mix_fresh_ok =
        lab16_ch3_mix_hold_ok &&
        lab16_mix_fresh_i[3];
    wire lab16_ch3_mix_ok_now =
        (smoke_c0_pm3_mix_mode == LAB16_PM3_MIX_FRESH) ?
            lab16_ch3_mix_fresh_ok :
        (smoke_c0_pm3_mix_mode == LAB16_PM3_MIX_GATE) ?
            lab16_ch3_mix_gate_ok :
            lab16_ch3_mix_hold_ok;
    wire lab16_ch3_no_fresh_for_mix =
        !lab16_mix_fresh_i[3] &&
        !lab16_ch3_return_pulse;
    wire [18:0] lab_c0_req_pi_i = lab_c0_pi_i;
    wire lab_c0_raw_audible =
        (c0_capture_ch3_vol_l_i[6:0] != 7'd0) ||
        (c0_capture_ch3_vol_r_i[6:0] != 7'd0);
    wire lab_c0_has_seed =
        ({c0_capture_ch3_cur_high_i, c0_capture_ch3_cur_mid_i} != 16'd0);
    wire lab_c0_pv_match =
        smoke_c0_mame_match_valid_next &&
        (smoke_c0_mame_match_index_next == 3'd2);
    wire lab_c0_playback_gate =
        smoke_playback_running &&
        !smoke_playback_done &&
        !smoke_vgm_end_seen &&
        smoke_ddr_c0drive_active &&
        lab_c0_pv_match &&
        lab_c0_raw_audible;
    wire lab16_run_gate =
        smoke_playback_running &&
        !smoke_playback_done &&
        !smoke_vgm_end_seen &&
        smoke_ddr_c0drive_active;
    wire lab16_retrigger_pulse;
    wire lab_c0_arm =
        lab_c0_playback_gate &&
        lab_c0_has_seed;
    wire lab_c0_should_run =
        lab_c0_playback_gate &&
        (lab_c0_arm || lab_c0_active_i);
    wire lab_c0_pi_in_range =
        smoke_type80_table_valid_i[2] &&
        (lab_c0_pi_i < smoke_type80_table_len_i[2]);
    wire [7:0] lab_c0_sample_byte_next = lab_c0_sample_i;
    wire [7:0] lab_c0_fixed_byte =
        (lab_c0_fixed_index_i == 3'd0) ? 8'h80 :
        (lab_c0_fixed_index_i == 3'd1) ? 8'h80 :
        (lab_c0_fixed_index_i == 3'd2) ? 8'h81 :
        (lab_c0_fixed_index_i == 3'd3) ? 8'h80 :
        (lab_c0_fixed_index_i == 3'd4) ? 8'h81 :
        (lab_c0_fixed_index_i == 3'd5) ? 8'h84 :
        (lab_c0_fixed_index_i == 3'd6) ? 8'h99 :
        8'hA9;
    wire [7:0] lab_c0_local_mux_byte =
        (lab_c0_fixed_index_i == 3'd0) ? 8'h80 :
        (lab_c0_fixed_index_i == 3'd1) ? 8'h80 :
        (lab_c0_fixed_index_i == 3'd2) ? 8'h81 :
        (lab_c0_fixed_index_i == 3'd3) ? 8'h80 :
        (lab_c0_fixed_index_i == 3'd4) ? 8'h81 :
        (lab_c0_fixed_index_i == 3'd5) ? 8'h84 :
        (lab_c0_fixed_index_i == 3'd6) ? 8'h99 :
        8'hA9;
    wire lab_c0_force_mode =
        smoke_c0_sample_mode_sel == LAB_C0_PUMP_FORCE_CONST;
    wire lab_c0_fixed_mode =
        smoke_c0_sample_mode_sel == LAB_C0_PUMP_FIXED_SEQ;
    wire lab_c0_local_seq_mode =
        smoke_c0_sample_mode_sel == LAB_C0_PUMP_LOCAL_SEQ;
    wire lab_c0_local_delta_mode =
        smoke_c0_sample_mode_sel == LAB_C0_PUMP_LOCAL_DELTA;
    wire lab_c0_mame_exact_mode =
        smoke_c0_sample_mode_sel == LAB_C0_PUMP_MAME_EXACT;
    wire lab_c0_pm3_backend_active = !smoke_c0_jt_backend;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_PM3_LEGACY_CH3_BLOCK2
    wire lab_c0_legacy_ch3_block2_mode =
        lab_c0_pm3_backend_active && lab_c0_local_delta_mode;
`else
    wire lab_c0_legacy_ch3_block2_mode =
        lab_c0_pm3_backend_active &&
        lab_c0_local_delta_mode &&
        smoke_c0_vol_map_sel[0];
`endif
    wire lab_c0_multich_delta_mode =
        lab_c0_pm3_backend_active &&
        lab_c0_local_delta_mode &&
        !lab_c0_legacy_ch3_block2_mode;
    wire lab_c0_req_payload_in_range =
        lab_c0_multich_delta_mode ?
            (lab_c0_req_addr_i < smoke_loaded_ddr_usable_bytes) :
            lab_c0_pi_in_range;
    wire lab_c0_request_fire =
        smoke_ddr_follow_mode &&
        lab_c0_req_live_i &&
        !loaded_ddr_rd_req &&
        !smoke_c0_probe_pending_i &&
        !smoke_ddr_c0_return_valid_i &&
        (!lab_c0_need_read_i || lab_c0_req_payload_in_range);
    wire lab16_service_tick =
        lab_c0_multich_delta_mode &&
        lab16_run_gate &&
        segapcm_cen &&
        (lab16_emit_div_i == 12'hfff);
    wire lab_c0_seq_mode =
        lab_c0_fixed_mode ||
        lab_c0_local_seq_mode ||
        lab_c0_local_delta_mode ||
        lab_c0_mame_exact_mode;
    wire lab_c0_local_pcm_mode =
        lab_c0_local_seq_mode ||
        lab_c0_local_delta_mode ||
        lab_c0_mame_exact_mode;
    wire lab_c0_local_mode =
        lab_c0_local_delta_mode || lab_c0_mame_exact_mode;
    wire lab_c0_force_output =
        lab_c0_pm3_backend_active &&
        lab_c0_force_mode && lab_c0_pv_match && lab_c0_raw_audible;
    wire lab_c0_seq_output =
        lab_c0_pm3_backend_active &&
        lab_c0_seq_mode &&
        (lab_c0_multich_delta_mode ?
            (lab16_run_gate &&
             ((lab16_active_i != 16'd0) || lab16_retrigger_pulse)) :
            lab_c0_playback_gate);
    wire lab_c0_fixed_output = lab_c0_seq_output;
    wire lab_c0_local_output =
        lab_c0_pm3_backend_active &&
        (lab_c0_local_delta_mode || lab_c0_mame_exact_mode) &&
        lab_c0_playback_gate;
    wire lab_c0_seq_base_emit_pulse =
        lab_c0_seq_output &&
        segapcm_cen &&
        (lab_c0_fixed_div_i == 12'hfff);
    wire [3:0] lab_c0_mame_tick_div_limit =
        (smoke_c0_mame_tick_div_sel == 3'd0) ? 4'd0 :
        (smoke_c0_mame_tick_div_sel == 3'd1) ? 4'd1 :
        (smoke_c0_mame_tick_div_sel == 3'd2) ? 4'd3 :
        (smoke_c0_mame_tick_div_sel == 3'd3) ? 4'd7 :
        4'd15;
    wire lab_c0_mame_tick_div_due =
        lab_c0_mame_tick_div_count_i >= lab_c0_mame_tick_div_limit;
    wire lab_c0_seq_emit_pulse =
        lab_c0_seq_base_emit_pulse &&
        (!lab_c0_mame_exact_mode || lab_c0_mame_tick_div_due);
    wire lab_c0_fixed_emit_pulse = lab_c0_seq_emit_pulse;
    wire [3:0] lab_c0_pump_branch_debug =
        lab_c0_force_output ? 4'd0 :
        (lab_c0_fixed_mode && lab_c0_seq_output) ? 4'd1 :
        (lab_c0_local_seq_mode && lab_c0_seq_output) ? 4'd2 :
        (lab_c0_local_delta_mode && lab_c0_seq_output) ? 4'd3 :
        (lab_c0_mame_exact_mode && lab_c0_seq_output) ? 4'd4 :
        4'hf;
    wire [15:0] lab_c0_hit_window_limit =
        (smoke_c0_hit_window_sel == 3'd1) ? 16'd256 :
        (smoke_c0_hit_window_sel == 3'd2) ? 16'd512 :
        (smoke_c0_hit_window_sel == 3'd3) ? 16'd768 :
        (smoke_c0_hit_window_sel == 3'd4) ? 16'd1024 :
        16'hffff;
    wire lab_c0_hit_window_limited =
        lab_c0_local_delta_mode &&
        (smoke_c0_hit_window_sel != 3'd0) &&
        (smoke_c0_hit_window_sel < 3'd5);
    wire lab_c0_hit_window_open =
        !lab_c0_hit_window_limited ||
        (lab_c0_hit_count_i < lab_c0_hit_window_limit);
    wire [15:0] lab_c0_hit_window_debug =
        {1'b0, smoke_c0_hit_window_sel, lab_c0_hit_window_limit[11:0]};
    wire [7:0] lab_c0_delta_step =
        (c0_capture_ch3_delta_i != 8'd0) ? c0_capture_ch3_delta_i : 8'hA0;
    wire [10:0] lab_c0_pm3_effective_delta_wide =
        {3'd0, lab_c0_delta_step} << smoke_c0_delta_speed_sel;
    wire [10:0] lab_c0_pm3_effective_delta =
        (|lab_c0_pm3_effective_delta_wide[10:8]) ? 11'h7ff :
        lab_c0_pm3_effective_delta_wide;
    wire [10:0] lab_c0_mame_effective_delta = {3'd0, lab_c0_delta_step};
    wire [10:0] lab_c0_effective_delta =
        lab_c0_mame_exact_mode ?
        lab_c0_mame_effective_delta :
        lab_c0_pm3_effective_delta;
    wire [26:0] lab_c0_phase_increment = {16'd0, lab_c0_effective_delta};
    wire [26:0] lab_c0_phase_next =
        lab_c0_phase_i + lab_c0_phase_increment;
    wire [18:0] lab_c0_delta_pi_next = lab_c0_phase_next[26:8];
    wire [7:0] lab_c0_event_ctrl =
        (mapped_cpu_addr == 8'h9e) ? segapcm_cmd_data : c0_capture_ch3_ctrl_i;
    wire [7:0] lab_c0_event_cur_mid =
        (mapped_cpu_addr == 8'h9c) ? segapcm_cmd_data : c0_capture_ch3_cur_mid_i;
    wire [7:0] lab_c0_event_cur_high =
        (mapped_cpu_addr == 8'h9d) ? segapcm_cmd_data : c0_capture_ch3_cur_high_i;
    wire [7:0] lab_c0_event_vol_l =
        (mapped_cpu_addr == 8'h1a) ? segapcm_cmd_data : c0_capture_ch3_vol_l_i;
    wire [7:0] lab_c0_event_vol_r =
        (mapped_cpu_addr == 8'h1b) ? segapcm_cmd_data : c0_capture_ch3_vol_r_i;
    wire lab_c0_event_audible =
        (lab_c0_event_vol_l[6:0] != 7'd0) ||
        (lab_c0_event_vol_r[6:0] != 7'd0);
    wire [20:0] lab_c0_event_bank =
        ({13'd0, (lab_c0_event_ctrl & 8'hf8)} << 13);
    wire [20:0] lab_c0_event_full_addr =
        lab_c0_event_bank + {5'd0, lab_c0_event_cur_high, lab_c0_event_cur_mid};
    wire lab_c0_event_block2_match =
        smoke_type80_table_valid_i[2] &&
        (lab_c0_event_full_addr >= smoke_type80_table_dest_i[2]) &&
        (lab_c0_event_full_addr <
         (smoke_type80_table_dest_i[2] + {2'd0, smoke_type80_table_len_i[2]}));
    wire [20:0] lab_c0_event_offset_21 =
        lab_c0_event_full_addr - smoke_type80_table_dest_i[2];
    wire [18:0] lab_c0_event_local_pi =
        smoke_type80_table_base_i[2] + lab_c0_event_offset_21[18:0];
    wire [20:0] lab_c0_loop_full_addr =
        ({13'd0, (c0_capture_ch3_ctrl_i & 8'hf8)} << 13) +
        {5'd0, c0_capture_ch3_loop_high_i, c0_capture_ch3_loop_mid_i};
    wire [20:0] lab_c0_loop_offset_21 =
        lab_c0_loop_full_addr - smoke_type80_table_dest_i[2];
    wire [18:0] lab_c0_loop_local_pi =
        smoke_type80_table_base_i[2] + lab_c0_loop_offset_21[18:0];
    wire [15:0] lab_c0_mame_addr16 =
        lab_c0_event_seed_i + (lab_c0_pi_i[15:0] - lab_c0_reseed_pi_i[15:0]);
    wire lab_c0_mame_ctrl_disabled =
        c0_capture_ch3_ctrl_i[0];
    wire lab_c0_mame_end_hit =
        lab_c0_mame_exact_mode &&
        (lab_c0_mame_addr16[15:8] == c0_capture_ch3_end_i);
    wire lab_c0_mame_output_open =
        !lab_c0_mame_exact_mode ||
        (!lab_c0_mame_ctrl_disabled && !lab_c0_mame_end_hit);
    wire lab_c0_selected_event_pulse =
        (lab_c0_local_delta_mode || lab_c0_mame_exact_mode) &&
        segapcm_cmd_valid &&
        (smoke_c0_drive_sel != 2'd0) &&
        lab_c0_event_audible &&
        lab_c0_event_block2_match &&
        ((mapped_cpu_addr == 8'h9e) ||
         (mapped_cpu_addr == 8'h9c) ||
         (mapped_cpu_addr == 8'h9d) ||
         (mapped_cpu_addr == 8'h1a) ||
         (mapped_cpu_addr == 8'h1b));
    wire lab_c0_pm4_ctrl_write =
        lab_c0_mame_exact_mode &&
        (mapped_cpu_addr == 8'h9e);
    wire lab_c0_pm4_ctrl_enable_edge =
        lab_c0_pm4_ctrl_write &&
        c0_capture_ch3_ctrl_i[0] &&
        !lab_c0_event_ctrl[0];
    wire lab_c0_pm4_first_valid_ctrl =
        lab_c0_pm4_ctrl_write &&
        !lab_c0_active_i &&
        !lab_c0_event_ctrl[0];
    wire lab_c0_pm4_reseed_pulse =
        lab_c0_mame_exact_mode &&
        lab_c0_selected_event_pulse &&
        lab_c0_event_audible &&
        lab_c0_event_block2_match &&
        (lab_c0_pm4_ctrl_enable_edge || lab_c0_pm4_first_valid_ctrl);
    wire lab_c0_pm3_reseed_pulse =
        lab_c0_local_delta_mode &&
        lab_c0_selected_event_pulse;
    wire lab_c0_retrigger_pulse =
        lab_c0_pm3_reseed_pulse || lab_c0_pm4_reseed_pulse;
    wire [3:0] lab16_write_ch = mapped_cpu_addr[6:3];
    wire [2:0] lab16_write_off = mapped_cpu_addr[2:0];
    wire lab16_write_low = !mapped_cpu_addr[7];
    wire lab16_write_high = mapped_cpu_addr[7];
    wire [7:0] lab16_event_ctrl =
        (lab16_write_high && (lab16_write_off == 3'd6)) ?
        segapcm_cmd_data : lab16_ctrl_i[lab16_write_ch];
    wire [7:0] lab16_event_cur_mid =
        (lab16_write_high && (lab16_write_off == 3'd4)) ?
        segapcm_cmd_data : lab16_cur_mid_i[lab16_write_ch];
    wire [7:0] lab16_event_cur_high =
        (lab16_write_high && (lab16_write_off == 3'd5)) ?
        segapcm_cmd_data : lab16_cur_high_i[lab16_write_ch];
    wire [6:0] lab16_event_vol_l =
        (lab16_write_low && (lab16_write_off == 3'd2)) ?
        segapcm_cmd_data[6:0] : lab16_vol_l_i[lab16_write_ch];
    wire [6:0] lab16_event_vol_r =
        (lab16_write_low && (lab16_write_off == 3'd3)) ?
        segapcm_cmd_data[6:0] : lab16_vol_r_i[lab16_write_ch];
    wire lab16_event_audible =
        (lab16_event_vol_l != 7'd0) || (lab16_event_vol_r != 7'd0);
    wire lab16_prev_audible =
        (lab16_vol_l_i[lab16_write_ch] != 7'd0) ||
        (lab16_vol_r_i[lab16_write_ch] != 7'd0);
    wire lab16_event_current_nonzero =
        ({lab16_event_cur_high, lab16_event_cur_mid} != 16'd0);
    wire lab16_event_ctrl_enabled = !lab16_event_ctrl[0];
    wire lab16_prev_ctrl_disabled = lab16_ctrl_i[lab16_write_ch][0];
    wire lab16_event_retrigger_reg =
        (lab16_write_high &&
         ((lab16_write_off == 3'd4) ||
          (lab16_write_off == 3'd5) ||
          (lab16_write_off == 3'd6))) ||
        (lab16_write_low &&
         ((lab16_write_off == 3'd2) ||
          (lab16_write_off == 3'd3)));
    wire [20:0] lab16_event_bank =
        ({13'd0, (lab16_event_ctrl & 8'hf8)} << 13);
    wire [20:0] lab16_event_full_addr =
        lab16_event_bank + {5'd0, lab16_event_cur_high, lab16_event_cur_mid};
    wire [7:0] lab16_event_end =
        (lab16_write_low && (lab16_write_off == 3'd6)) ?
        segapcm_cmd_data : lab16_end_i[lab16_write_ch];
    wire [20:0] lab16_event_end_full_addr =
        lab16_event_bank + {5'd0, lab16_event_end, 8'd0};
    logic [15:0] lab16_active_mask;
    logic [4:0] lab16_active_count;
    logic [3:0] lab16_next_ch;
    logic lab16_next_valid;
    logic signed [23:0] lab16_mix_l_next;
    logic signed [23:0] lab16_mix_r_next;
    logic signed [15:0] lab16_mix_l_sample_next;
    logic signed [15:0] lab16_mix_r_sample_next;
    logic [7:0] lab16_selected_sample_byte;
    logic signed [8:0] lab16_selected_cv;
    logic signed [15:0] lab16_selected_out_l;
    logic signed [15:0] lab16_selected_out_r;
    logic lab16_clip_next;
    logic signed [8:0] lab16_return_cv;
    logic signed [16:0] lab16_return_product_l;
    logic signed [16:0] lab16_return_product_r;
    logic signed [16:0] lab16_return_scaled_l;
    logic signed [16:0] lab16_return_scaled_r;
    logic [10:0] lab16_return_delta_x4;
    logic [26:0] lab16_return_phase_next;
    logic lab16_return_read_valid;
    logic lab16_return_next_valid;
    logic lab16_return_output_valid;
    logic [18:0] lab16_return_stop_pi;
    logic lab16_return_read_range_cross;
    logic lab16_return_next_range_cross;
    logic lab16_return_true_cross;
    logic lab16_service_true_cross;
    logic [15:0] lab16_return_abs_l;
    logic [15:0] lab16_return_abs_r;
    logic [15:0] lab16_return_abs_max;
    logic [15:0] lab16_mix_abs_l_next;
    logic [15:0] lab16_mix_abs_r_next;
    logic [15:0] lab16_mix_abs_max_next;
    logic lab16_event_map_valid;
    logic [2:0] lab16_event_map_block;
    logic [18:0] lab16_event_map_base;
    logic [18:0] lab16_event_map_len;
    logic [18:0] lab16_event_map_limit;
    logic [18:0] lab16_event_local_pi;
    logic [20:0] lab16_event_map_offset_21;
    logic [19:0] lab16_event_map_limit_20;
    logic [20:0] lab16_event_end_offset_21;
    logic [19:0] lab16_event_end_limit_20;
    logic [19:0] lab16_event_effective_limit_20;
    logic [19:0] lab16_event_local_pi_20;
    logic        lab16_event_end_limit_valid;
    logic        lab16_event_end_limit_used;
    logic lab16_event_rom_hit;
    logic [2:0] lab16_event_rom_block;
    logic [18:0] lab16_event_rom_base;
    logic [18:0] lab16_event_rom_len;
    logic [18:0] lab16_event_rom_offset;
    integer lab16_comb_i;
    integer lab16_scan_i;
    integer lab16_map_loop_i;
    localparam logic [15:0] LAB16_EXPLOSION_ABS_THRESHOLD = 16'h1800;
    wire lab16_expl_masked_return =
        smoke_c0_pm3_audio_mask[lab16_pending_ch_i];
    wire lab16_expl_loud_return =
        lab16_clip_next ||
        (lab16_mix_abs_max_next >= LAB16_EXPLOSION_ABS_THRESHOLD) ||
        (lab16_return_output_valid &&
         (lab16_return_abs_max >= LAB16_EXPLOSION_ABS_THRESHOLD));
    wire lab16_expl_peak_return =
        lab16_return_output_valid &&
        ((lab16_return_abs_max > lab16_expl_abs_i) ||
         (lab16_mix_abs_max_next > lab16_expl_abs_i));
    wire lab16_expl_fault_return =
        lab16_return_true_cross || !lab16_return_read_valid;
    wire lab16_expl_bootstrap_return =
        lab16_return_read_valid &&
        (!lab16_expl_valid_i || !lab16_expl_reason_i[0]);
    wire lab16_expl_first8_refresh =
        lab16_expl_valid_i &&
        !lab16_expl_first8_done_i &&
        lab16_return_read_valid &&
        (lab16_pending_ch_i == lab16_expl_ch_i) &&
        (lab16_block_i[lab16_pending_ch_i] == lab16_expl_block_i);
    wire [3:0] lab16_block_nib0 =
        lab16_sticky_map_i[0] ? {1'b0, lab16_sticky_block_i[0]} : 4'hf;
    wire [3:0] lab16_block_nib1 =
        lab16_sticky_map_i[1] ? {1'b0, lab16_sticky_block_i[1]} : 4'hf;
    wire [3:0] lab16_block_nib2 =
        lab16_sticky_map_i[2] ? {1'b0, lab16_sticky_block_i[2]} : 4'hf;
    wire [3:0] lab16_block_nib3 =
        lab16_sticky_map_i[3] ? {1'b0, lab16_sticky_block_i[3]} : 4'hf;
    wire [3:0] lab16_block_nib4 =
        lab16_sticky_map_i[4] ? {1'b0, lab16_sticky_block_i[4]} : 4'hf;
    wire [3:0] lab16_block_nib5 =
        lab16_sticky_map_i[5] ? {1'b0, lab16_sticky_block_i[5]} : 4'hf;
    wire [3:0] lab16_block_nib6 =
        lab16_sticky_map_i[6] ? {1'b0, lab16_sticky_block_i[6]} : 4'hf;
    wire [3:0] lab16_block_nib7 =
        lab16_sticky_map_i[7] ? {1'b0, lab16_sticky_block_i[7]} : 4'hf;
    always_comb begin
        lab16_active_mask = lab16_active_i;
        lab16_active_count = 5'd0;
        lab16_mix_l_next = 24'sd0;
        lab16_mix_r_next = 24'sd0;
        lab16_loud_ch = lab16_debug_ch_i;
        lab16_loud_abs = 16'd0;
        lab16_loud_valid = 1'b0;
        lab16_abs_l_tmp = 16'd0;
        lab16_abs_r_tmp = 16'd0;
        lab16_abs_tmp = 16'd0;
        lab16_comb_mix_ok = 1'b0;
        for (lab16_comb_i = 0; lab16_comb_i < 16;
             lab16_comb_i = lab16_comb_i + 1) begin
            if (lab16_active_i[lab16_comb_i]) begin
                lab16_active_count = lab16_active_count + 5'd1;
            end
            unique case (smoke_c0_pm3_mix_mode)
                LAB16_PM3_MIX_FRESH: begin
                    lab16_comb_mix_ok =
                        smoke_c0_pm3_audio_mask[lab16_comb_i] &&
                        lab16_active_i[lab16_comb_i] &&
                        lab16_mix_fresh_i[lab16_comb_i];
                end
                LAB16_PM3_MIX_GATE: begin
                    lab16_comb_mix_ok =
                        smoke_c0_pm3_audio_mask[lab16_comb_i] &&
                        lab16_active_i[lab16_comb_i] &&
                        lab16_map_valid_i[lab16_comb_i] &&
                        (lab16_pi_i[lab16_comb_i] >=
                         lab16_base_i[lab16_comb_i]) &&
                        (lab16_pi_i[lab16_comb_i] <
                         lab16_limit_i[lab16_comb_i]) &&
                        !lab16_ctrl_i[lab16_comb_i][0] &&
                        ((lab16_vol_l_i[lab16_comb_i] != 7'd0) ||
                         (lab16_vol_r_i[lab16_comb_i] != 7'd0));
                end
                default: begin
                    lab16_comb_mix_ok =
                        smoke_c0_pm3_audio_mask[lab16_comb_i] &&
                        lab16_active_i[lab16_comb_i];
                end
            endcase
            if (lab16_comb_mix_ok) begin
                lab16_abs_l_tmp = lab16_out_l_i[lab16_comb_i][15] ?
                    (~lab16_out_l_i[lab16_comb_i] + 16'd1) :
                    lab16_out_l_i[lab16_comb_i];
                lab16_abs_r_tmp = lab16_out_r_i[lab16_comb_i][15] ?
                    (~lab16_out_r_i[lab16_comb_i] + 16'd1) :
                    lab16_out_r_i[lab16_comb_i];
                lab16_abs_tmp =
                    (lab16_abs_l_tmp > lab16_abs_r_tmp) ?
                    lab16_abs_l_tmp : lab16_abs_r_tmp;
                if (lab16_abs_tmp > lab16_loud_abs) begin
                    lab16_loud_abs = lab16_abs_tmp;
                    lab16_loud_ch = lab16_comb_i[3:0];
                    lab16_loud_valid = lab16_abs_tmp != 16'd0;
                end
                lab16_mix_l_next =
                    lab16_mix_l_next +
                    {{8{lab16_out_l_i[lab16_comb_i][15]}},
                     lab16_out_l_i[lab16_comb_i]};
                lab16_mix_r_next =
                    lab16_mix_r_next +
                    {{8{lab16_out_r_i[lab16_comb_i][15]}},
                     lab16_out_r_i[lab16_comb_i]};
            end
        end
        lab16_mix_l_sample_next = lab16_mix_l_next[17:2];
        lab16_mix_r_sample_next = lab16_mix_r_next[17:2];
        lab16_clip_next =
            (lab16_mix_l_next > 24'sd131071) ||
            (lab16_mix_l_next < -24'sd131072) ||
            (lab16_mix_r_next > 24'sd131071) ||
            (lab16_mix_r_next < -24'sd131072);

        lab16_next_ch = lab16_rr_ch_i;
        lab16_next_valid = 1'b0;
        for (lab16_scan_i = 0; lab16_scan_i < 16;
             lab16_scan_i = lab16_scan_i + 1) begin
            if (!lab16_next_valid &&
                lab16_active_i[(lab16_rr_ch_i + lab16_scan_i[3:0]) & 4'hf]) begin
                lab16_next_ch =
                    (lab16_rr_ch_i + lab16_scan_i[3:0]) & 4'hf;
                lab16_next_valid = 1'b1;
            end
        end

        lab16_snap_view = !lab16_loud_valid && lab16_loud_snap_valid_i;
        lab16_view_ch = lab16_loud_valid ? lab16_loud_ch :
            (lab16_loud_snap_valid_i ? lab16_loud_snap_ch_i : lab16_debug_ch_i);
        lab16_selected_block =
            lab16_snap_view ? lab16_loud_snap_block_i :
            lab16_block_i[lab16_view_ch];
        lab16_selected_start =
            lab16_snap_view ? lab16_loud_snap_start_i :
            lab16_start_i[lab16_view_ch];
        lab16_selected_pi =
            lab16_snap_view ? lab16_loud_snap_pi_i :
            lab16_pi_i[lab16_view_ch];
        lab16_selected_sample_byte =
            lab16_snap_view ? lab16_loud_snap_sample_i :
            lab16_hold_sample_i[lab16_view_ch];
        lab16_selected_cv = lab16_snap_view ? lab16_loud_snap_cv_i :
            lab16_hold_cv_i[lab16_view_ch];
        lab16_selected_out_l =
            lab16_snap_view ? lab16_loud_snap_out_i :
            lab16_out_l_i[lab16_view_ch];
        lab16_selected_out_r =
            lab16_snap_view ? lab16_loud_snap_out_i :
            lab16_out_r_i[lab16_view_ch];
        lab16_mix_abs_l_next = lab16_mix_l_sample_next[15] ?
            (~lab16_mix_l_sample_next + 16'd1) :
            lab16_mix_l_sample_next;
        lab16_mix_abs_r_next = lab16_mix_r_sample_next[15] ?
            (~lab16_mix_r_sample_next + 16'd1) :
            lab16_mix_r_sample_next;
        lab16_mix_abs_max_next =
            (lab16_mix_abs_l_next > lab16_mix_abs_r_next) ?
            lab16_mix_abs_l_next : lab16_mix_abs_r_next;
        lab16_return_abs_l = lab16_return_scaled_l[15] ?
            (~lab16_return_scaled_l[15:0] + 16'd1) :
            lab16_return_scaled_l[15:0];
        lab16_return_abs_r = lab16_return_scaled_r[15] ?
            (~lab16_return_scaled_r[15:0] + 16'd1) :
            lab16_return_scaled_r[15:0];
        lab16_return_abs_max =
            (lab16_return_abs_l > lab16_return_abs_r) ?
            lab16_return_abs_l : lab16_return_abs_r;
        lab16_block_summary_03 = {
            lab16_block_nib3,
            lab16_block_nib2,
            lab16_block_nib1,
            lab16_block_nib0
        };
        lab16_block_summary_47 = {
            lab16_block_nib7,
            lab16_block_nib6,
            lab16_block_nib5,
            lab16_block_nib4
        };
        lab16_ch3_snapshot_local_start_20 =
            {1'b0, lab16_ch3_snapshot_base_i} +
            {1'b0, lab16_ch3_snapshot_offset_i};
        lab16_selected_reason = lab16_snap_view ?
            lab16_loud_snap_reason_i : {
            11'd0,
            lab16_pi_i[lab16_view_ch] < lab16_base_i[lab16_view_ch],
            lab16_pi_i[lab16_view_ch] >= lab16_limit_i[lab16_view_ch],
            !lab16_map_valid_i[lab16_view_ch],
            lab16_vol_l_i[lab16_view_ch] == 7'd0 &&
                lab16_vol_r_i[lab16_view_ch] == 7'd0,
            lab16_ctrl_i[lab16_view_ch][0]
        };
        lab16_selected_delta_reason = lab16_snap_view ?
            lab16_loud_snap_delta_reason_i : {
            lab16_selected_reason[7:0],
            lab16_delta_i[lab16_view_ch]
        };
        lab16_selected_volume = lab16_snap_view ?
            lab16_loud_snap_volume_i : {
            1'b0, lab16_vol_l_i[lab16_view_ch],
            1'b0, lab16_vol_r_i[lab16_view_ch]
        };

        lab16_event_map_valid = 1'b0;
        lab16_event_map_block = 3'd0;
        lab16_event_map_base = 19'd0;
        lab16_event_map_len = 19'd0;
        lab16_event_map_limit = 19'd0;
        lab16_event_local_pi = 19'd0;
        lab16_event_map_offset_21 = 21'd0;
        lab16_event_map_limit_20 = 20'd0;
        lab16_event_end_offset_21 = 21'd0;
        lab16_event_end_limit_20 = 20'd0;
        lab16_event_effective_limit_20 = 20'd0;
        lab16_event_local_pi_20 = 20'd0;
        lab16_event_end_limit_valid = 1'b0;
        lab16_event_end_limit_used = 1'b0;
        lab16_event_rom_hit = 1'b0;
        lab16_event_rom_block = 3'd0;
        lab16_event_rom_base = 19'd0;
        lab16_event_rom_len = 19'd0;
        lab16_event_rom_offset = 19'd0;
        for (lab16_map_loop_i = 0;
             lab16_map_loop_i < SMOKE_TYPE80_TABLE_ENTRIES;
             lab16_map_loop_i = lab16_map_loop_i + 1) begin
            if (!lab16_event_rom_hit &&
                smoke_type80_table_valid_i[lab16_map_loop_i] &&
                (smoke_type80_table_len_i[lab16_map_loop_i] != 19'd0) &&
                (lab16_event_full_addr >=
                 smoke_type80_table_dest_i[lab16_map_loop_i]) &&
                (lab16_event_full_addr <
                 (smoke_type80_table_dest_i[lab16_map_loop_i] +
                  {2'd0, smoke_type80_table_len_i[lab16_map_loop_i]}))) begin
                lab16_event_rom_hit = 1'b1;
                lab16_event_rom_block = lab16_map_loop_i[2:0];
                lab16_event_map_offset_21 =
                    lab16_event_full_addr -
                    smoke_type80_table_dest_i[lab16_map_loop_i];
                lab16_event_rom_base =
                    smoke_type80_table_base_i[lab16_map_loop_i];
                lab16_event_rom_len =
                    smoke_type80_table_len_i[lab16_map_loop_i];
                lab16_event_rom_offset = lab16_event_map_offset_21[18:0];
                lab16_event_map_limit_20 =
                    {1'b0, smoke_type80_table_base_i[lab16_map_loop_i]} +
                    {1'b0, smoke_type80_table_len_i[lab16_map_loop_i]};
                lab16_event_end_offset_21 =
                    lab16_event_end_full_addr -
                    smoke_type80_table_dest_i[lab16_map_loop_i];
                lab16_event_end_limit_20 =
                    {1'b0, smoke_type80_table_base_i[lab16_map_loop_i]} +
                    {1'b0, lab16_event_end_offset_21[18:0]};
                lab16_event_local_pi_20 =
                    {1'b0, smoke_type80_table_base_i[lab16_map_loop_i]} +
                    {1'b0, lab16_event_map_offset_21[18:0]};
                lab16_event_effective_limit_20 = lab16_event_map_limit_20;
                lab16_event_end_limit_valid =
                    (lab16_event_end != 8'd0) &&
                    (lab16_event_end_full_addr > lab16_event_full_addr) &&
                    (lab16_event_end_full_addr <=
                     (smoke_type80_table_dest_i[lab16_map_loop_i] +
                      {2'd0, smoke_type80_table_len_i[lab16_map_loop_i]})) &&
                    (lab16_event_end_limit_20 <=
                     {1'b0, smoke_loaded_ddr_usable_bytes});
                if (lab16_event_end_limit_valid) begin
                    lab16_event_effective_limit_20 =
                        lab16_event_end_limit_20;
                end
                if ((lab16_event_effective_limit_20 <=
                     {1'b0, smoke_loaded_ddr_usable_bytes}) &&
                    (lab16_event_local_pi_20 <
                     {1'b0, smoke_loaded_ddr_usable_bytes}) &&
                    (lab16_event_local_pi_20 <
                     lab16_event_effective_limit_20)) begin
                    lab16_event_map_valid = 1'b1;
                    lab16_event_map_block = lab16_map_loop_i[2:0];
                    lab16_event_map_base =
                        smoke_type80_table_base_i[lab16_map_loop_i];
                    lab16_event_map_len =
                        smoke_type80_table_len_i[lab16_map_loop_i];
                    lab16_event_map_limit =
                        lab16_event_effective_limit_20[18:0];
                    lab16_event_local_pi =
                        lab16_event_local_pi_20[18:0];
                    lab16_event_end_limit_used =
                        lab16_event_end_limit_valid;
                end
            end
        end
    end
    wire lab16_event_candidate_pulse =
        lab_c0_multich_delta_mode &&
        segapcm_cmd_valid &&
        (smoke_c0_drive_sel != 2'd0) &&
        lab16_event_retrigger_reg &&
        lab16_event_audible &&
        lab16_event_ctrl_enabled;
    wire lab16_event_valid_play_state =
        lab_c0_multich_delta_mode &&
        segapcm_cmd_valid &&
        (smoke_c0_drive_sel != 2'd0) &&
        lab16_event_audible &&
        lab16_event_ctrl_enabled &&
        lab16_event_current_nonzero &&
        lab16_event_map_valid;
    wire lab16_event_ctrl_enable =
        lab16_write_high &&
        (lab16_write_off == 3'd6) &&
        lab16_prev_ctrl_disabled &&
        lab16_event_ctrl_enabled;
    wire lab16_event_volume_on =
        lab16_write_low &&
        ((lab16_write_off == 3'd2) ||
         (lab16_write_off == 3'd3)) &&
        !lab16_prev_audible &&
        lab16_event_audible;
    wire lab16_event_first_valid_start =
        !lab16_strict_seen_i[lab16_write_ch] &&
        lab16_event_valid_play_state;
    wire lab16_event_strict_start_pulse =
        lab16_event_valid_play_state &&
        (lab16_event_ctrl_enable ||
         lab16_event_volume_on ||
         lab16_event_first_valid_start);
    wire lab16_event_current_commit =
        lab16_write_high &&
        (lab16_write_off == 3'd5);
    wire lab16_event_qualified_current_pulse =
        lab16_event_valid_play_state &&
        lab16_event_current_commit;
    wire lab16_event_qualified_start_pulse =
        lab16_event_strict_start_pulse ||
        lab16_event_qualified_current_pulse;
    wire lab16_event_broad_start_pulse =
        lab16_event_candidate_pulse &&
        lab16_event_map_valid &&
        lab16_event_current_nonzero;
    wire [15:0] lab16_event_current_word = {
        lab16_event_cur_high,
        lab16_event_cur_mid
    };
    wire lab16_event_current_active =
        lab16_event_qualified_current_pulse &&
        lab16_active_i[lab16_write_ch];
    wire lab16_event_current_inactive =
        lab16_event_qualified_current_pulse &&
        !lab16_active_i[lab16_write_ch];
    wire [15:0] lab16_event_runtime_offset =
        (lab16_active_i[lab16_write_ch] &&
         lab16_map_valid_i[lab16_write_ch]) ?
        (lab16_pi_i[lab16_write_ch][15:0] -
         lab16_base_i[lab16_write_ch][15:0]) :
        16'd0;
    wire [15:0] lab16_event_runtime_current =
        (lab16_start_current_i[lab16_write_ch] +
         lab16_event_runtime_offset);
    wire lab16_event_current_duplicate =
        lab16_event_current_word ==
        lab16_start_current_i[lab16_write_ch];
    wire lab16_event_current_backward =
        lab16_event_current_word < lab16_event_runtime_current;
    wire [16:0] lab16_event_current_abs_delta =
        lab16_event_current_backward ?
        ({1'b0, lab16_event_runtime_current} -
         {1'b0, lab16_event_current_word}) :
        ({1'b0, lab16_event_current_word} -
         {1'b0, lab16_event_runtime_current});
    wire lab16_event_current_near =
        lab16_event_current_abs_delta <= 17'h00200;
    wire lab16_event_current_far =
        lab16_event_current_abs_delta > 17'h00200;
    wire lab16_event_current_same_block =
        lab16_map_valid_i[lab16_write_ch] &&
        lab16_event_map_valid &&
        (lab16_block_i[lab16_write_ch] == lab16_event_map_block);
    wire lab16_event_current_block_change =
        lab16_map_valid_i[lab16_write_ch] &&
        lab16_event_map_valid &&
        (lab16_block_i[lab16_write_ch] != lab16_event_map_block);
    wire [15:0] lab16_event_end_gap =
        lab16_event_end_full_addr[15:0] - lab16_event_current_word;
    wire lab16_event_current_end_near =
        (lab16_event_end != 8'd0) &&
        (lab16_event_end_full_addr[15:0] > lab16_event_current_word) &&
        (lab16_event_end_gap <= 16'h0200);
    wire lab16_event_current_back_ok =
        lab16_event_current_active &&
        lab16_event_current_backward;
    wire lab16_event_current_no_dup_ok =
        lab16_event_current_active &&
        !lab16_event_current_duplicate;
    wire lab16_event_current_near_ok =
        lab16_event_current_active &&
        lab16_event_current_near;
    wire lab16_selected_policy_current_pulse =
        lab16_event_qualified_current_pulse &&
        (smoke_c0_pm3_start_policy != LAB16_PM3_START_STRICT);
    wire lab16_selected_policy_active_current_pulse =
        lab16_selected_policy_current_pulse &&
        lab16_active_i[lab16_write_ch];
    wire lab16_reposition_pulse =
        (smoke_c0_pm3_start_policy == LAB16_PM3_START_QUAL_REPOS) &&
        lab16_event_current_active &&
        !lab16_event_strict_start_pulse;
    wire lab16_ch3_raw_event_pulse =
        lab_c0_multich_delta_mode &&
        segapcm_cmd_valid &&
        (smoke_c0_drive_sel != 2'd0) &&
        (lab16_write_ch == 4'd3) &&
        lab16_event_retrigger_reg;
    wire lab16_ch3_snapshot_pulse =
        lab16_ch3_raw_event_pulse &&
        lab16_event_audible &&
        lab16_event_ctrl_enabled &&
        ({lab16_event_cur_high, lab16_event_cur_mid} != 16'd0);
    wire lab16_event_block2_match = lab16_event_map_valid;
    wire lab16_retrigger_masked_pulse =
        lab16_retrigger_pulse &&
        smoke_c0_pm3_audio_mask[lab16_write_ch];
    wire [15:0] lab16_event_full_low = lab16_event_full_addr[15:0];
    wire [7:0] lab16_event_delta_effective =
        (lab16_delta_i[lab16_write_ch] != 8'd0) ?
        lab16_delta_i[lab16_write_ch] : 8'hA0;
    wire lab16_target_ch_ok = lab16_write_ch == 4'd3;
    wire lab16_target_block_ok = lab16_event_map_block == 3'd2;
    wire lab16_target_current_ok = lab16_event_current_word == 16'h7100;
    wire lab16_target_delta_ok = lab16_event_delta_effective == 8'hA0;
    wire lab16_target_map_ok = lab16_event_map_valid;
    wire lab16_target_source_ok =
        lab_c0_multich_delta_mode && !lab_c0_legacy_ch3_block2_mode;
    wire lab16_target_mask_ok = smoke_c0_pm3_audio_mask[4'd3];
    wire lab16_retrigger_target_pulse =
        lab16_retrigger_masked_pulse &&
        lab16_target_ch_ok &&
        lab16_target_block_ok &&
        lab16_target_current_ok &&
        lab16_target_delta_ok &&
        lab16_target_map_ok &&
        lab16_target_source_ok &&
        lab16_target_mask_ok;
    wire [7:0] lab16_target_match_bits = {
        lab16_retrigger_target_pulse,
        lab16_target_mask_ok,
        lab16_target_source_ok,
        lab16_target_map_ok,
        lab16_target_delta_ok,
        lab16_target_current_ok,
        lab16_target_block_ok,
        lab16_target_ch_ok
    };
    wire [7:0] lab16_runtime_pr_flags = {
        lab16_first_capture_cleared_i,
        lab16_first_capture_overwrite_i,
        lab16_first_samples_valid_i,
        lab16_first_capture_reader_match_i,
        lab16_first_capture_has_any_i,
        lab16_first_samples_valid_i,
        lab16_first_capture_armed_i,
        lab16_start_tuple_valid_i
    };
    wire [15:0] lab16_runtime_pr_live = {
        8'hE6,
        lab16_runtime_pr_flags
    };
    wire [15:0] lab16_runtime_pr_debug =
        lab16_first_samples_valid_i ?
        lab16_runtime_pr_hold_i : lab16_runtime_pr_live;
    wire [15:0] lab16_runtime_offset_next =
        lab16_pi_i[lab16_pending_ch_i][15:0] -
        lab16_base_i[lab16_pending_ch_i][15:0];
    wire [16:0] lab16_runtime_addr_next =
        {1'b0, lab16_start_tuple_full_addr_i[15:0]} +
        {1'b0, lab16_runtime_offset_next};
    wire lab16_ch3_known_coord_fail =
        (lab16_write_ch == 4'd3) &&
        (lab16_event_full_addr == 21'h17100) &&
        lab16_event_rom_hit &&
        (smoke_type80_table_dest_i[lab16_event_rom_block] == 21'h17100) &&
        (lab16_event_rom_offset != 19'd0);
    assign lab16_retrigger_pulse =
        (smoke_c0_pm3_start_policy == LAB16_PM3_START_BROAD) ?
            lab16_event_broad_start_pulse :
        (smoke_c0_pm3_start_policy == LAB16_PM3_START_QUAL_RESTART) ?
            lab16_event_qualified_start_pulse :
        (smoke_c0_pm3_start_policy == LAB16_PM3_START_QUAL_REPOS) ?
            (lab16_event_strict_start_pulse || lab16_event_current_inactive) :
        (smoke_c0_pm3_start_policy == LAB16_PM3_START_QUAL_IDLE) ?
            (lab16_event_strict_start_pulse || lab16_event_current_inactive) :
        (smoke_c0_pm3_start_policy == LAB16_PM3_START_BACK_ONLY) ?
            (lab16_event_strict_start_pulse ||
             lab16_event_current_inactive ||
             lab16_event_current_back_ok) :
        (smoke_c0_pm3_start_policy == LAB16_PM3_START_NO_DUP) ?
            (lab16_event_strict_start_pulse ||
             lab16_event_current_inactive ||
             lab16_event_current_no_dup_ok) :
        (smoke_c0_pm3_start_policy == LAB16_PM3_START_NEAR_ONLY) ?
            (lab16_event_strict_start_pulse ||
             lab16_event_current_inactive ||
             lab16_event_current_near_ok) :
            lab16_event_strict_start_pulse;
    wire [15:0] lab_c0_pm4_reseed_reason_next = {
        7'd0,
        lab_c0_selected_event_pulse,
        lab_c0_event_audible,
        lab_c0_event_block2_match,
        lab_c0_pm4_ctrl_write,
        c0_capture_ch3_ctrl_i[0],
        lab_c0_event_ctrl[0],
        lab_c0_pm4_ctrl_enable_edge,
        lab_c0_pm4_first_valid_ctrl,
        lab_c0_pm4_reseed_pulse
    };
    wire [7:0] lab_c0_selected_sample_byte =
        lab_c0_local_pcm_mode ? lab_c0_sample_i : lab_c0_fixed_byte;
    wire signed [8:0] lab_c0_selected_cv =
        smoke_c0_format_sel[0] ?
            (9'sd128 - $signed({1'b0, lab_c0_selected_sample_byte})) :
            ($signed({1'b0, lab_c0_selected_sample_byte}) - 9'sd128);
    wire signed [15:0] lab_c0_selected_direct_sample =
        {{7{lab_c0_selected_cv[8]}}, lab_c0_selected_cv[8:0], 8'd0};
    wire [8:0] lab_c0_selected_abs_cv =
        lab_c0_selected_cv[8] ?
        (~lab_c0_selected_cv + 9'd1) :
        lab_c0_selected_cv;
    localparam logic [8:0] LAB_C0_MAME_LOUD_CV_THRESHOLD = 9'd16;
    wire lab_c0_mame_loud_hit =
        lab_c0_selected_abs_cv >= LAB_C0_MAME_LOUD_CV_THRESHOLD;
    wire signed [8:0] lab_c0_vol_l_signed =
        $signed({2'b00, c0_capture_ch3_vol_l_i[6:0]});
    wire signed [17:0] lab_c0_mame_mv_wide =
        lab_c0_selected_cv * lab_c0_vol_l_signed;
    wire [15:0] lab_c0_mame_cv_debug =
        {{7{lab_c0_selected_cv[8]}}, lab_c0_selected_cv};
    wire [15:0] lab_c0_mame_sb_cv_debug =
        {lab_c0_selected_sample_byte, lab_c0_selected_cv[7:0]};
    wire signed [15:0] lab_c0_windowed_direct_sample =
        lab_c0_hit_window_open ? lab_c0_selected_direct_sample : 16'sd0;
    wire signed [15:0] lab_c0_direct_output_sample =
        lab_c0_mame_output_open ?
        (lab_c0_mame_exact_mode ?
            lab_c0_selected_direct_sample :
            lab_c0_windowed_direct_sample) :
        16'sd0;
    localparam logic signed [15:0] LAB_C0_FORCE_SAMPLE = 16'sh0800;
    wire signed [15:0] lab_c0_legacy_output_sample =
        (lab_c0_legacy_ch3_block2_mode && lab_c0_seq_output) ?
        lab_c0_direct_output_sample : 16'sd0;
    wire signed [15:0] lab_c0_multich_output_l_sample =
        (lab_c0_multich_delta_mode && lab_c0_seq_output) ?
        lab16_mix_l_sample_i : 16'sd0;
    wire signed [15:0] lab_c0_multich_output_r_sample =
        (lab_c0_multich_delta_mode && lab_c0_seq_output) ?
        lab16_mix_r_sample_i : 16'sd0;
    wire signed [15:0] lab_c0_single_output_sample =
        lab_c0_force_output ? LAB_C0_FORCE_SAMPLE :
        (lab_c0_mame_exact_mode && lab_c0_seq_output) ?
        lab_c0_output_i :
        ((lab_c0_fixed_mode || lab_c0_local_seq_mode) &&
         lab_c0_seq_output) ?
        lab_c0_direct_output_sample :
        lab_c0_legacy_ch3_block2_mode ?
        lab_c0_legacy_output_sample :
        lab_c0_consume_pulse_i ?
        lab_c0_output_i : 16'sd0;
    wire signed [15:0] lab_c0_actual_output_sample =
        (lab_c0_multich_delta_mode && lab_c0_seq_output) ?
        lab_c0_multich_output_l_sample : lab_c0_single_output_sample;
    wire signed [15:0] lab_c0_actual_output_r_sample =
        (lab_c0_multich_delta_mode && lab_c0_seq_output) ?
        lab_c0_multich_output_r_sample : lab_c0_single_output_sample;
    wire signed [15:0] lab_c0_snd_left = lab_c0_output_i;
    wire signed [15:0] lab_c0_snd_right = lab_c0_output_i;
    wire signed [8:0] lab_c0_cv =
        $signed({1'b0, lab_c0_sample_byte_next}) - 9'sd128;
    wire signed [15:0] lab_c0_cv_out =
        {lab_c0_cv[8], lab_c0_cv[8], lab_c0_cv[8], lab_c0_cv[8],
         lab_c0_cv[8], lab_c0_cv[8], lab_c0_cv[8:0], 1'b0};
`endif
`endif

    function automatic signed [15:0] lab_scale_sample(
        input logic [7:0] sample,
        input logic [6:0] volume
    );
        logic signed [8:0] centered;
        logic signed [16:0] scaled;
        begin
            centered = $signed({1'b0, sample}) - 9'sd128;
            scaled = centered * $signed({1'b0, volume});
            lab_scale_sample = scaled[15:0];
        end
    endfunction

    function automatic signed [15:0] lab_gain_sample(input logic [7:0] sample);
        logic signed [8:0] centered;
        begin
            centered = $signed({1'b0, sample}) - 9'sd128;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_FIXED_PULSE_TEST
            lab_gain_sample = (sample != 8'h80) ? 16'sh0800 : 16'sd0;
`else
            lab_gain_sample = {{1{centered[8]}}, centered, 6'd0};
`endif
        end
    endfunction

    function automatic [15:0] abs16(input logic signed [15:0] value);
        abs16 = value[15] ? (~value + 16'd1) : value;
    endfunction

    always_comb begin
        unique case (C0_ADDR_MAP_MODE)
            1: mapped_cpu_addr = segapcm_cmd_addr[7:0];
            2: mapped_cpu_addr = segapcm_cmd_addr[8:1];
            3: mapped_cpu_addr = {segapcm_cmd_addr[6:0], 1'b0};
            4: mapped_cpu_addr = {segapcm_cmd_addr[0], segapcm_cmd_addr[7:1]};
            5: mapped_cpu_addr = segapcm_cmd_addr[15:8];
            default: mapped_cpu_addr = segapcm_cmd_addr[7:0];
        endcase
    end

    always_comb begin
        logic [3:0] req_ch;
        logic [2:0] req_bank;
        logic [7:0] low_base;
        logic [7:0] high_base;
        logic [7:0] req_cfg;
        logic [7:0] req_delta;
        logic [23:0] req_cur;
        logic [23:0] req_next;
        logic req_active_bit;

        req_bank = core_dbg_bank_channel_state[10:8];
        req_ch = core_dbg_bank_channel_state[7:4];
        low_base = {1'b0, req_ch, 3'b000};
        high_base = 8'h80 + low_base;
        req_cfg = shadow_ram[high_base + 8'd6];
        req_delta = shadow_ram[low_base + 8'd7];
        req_cur = {core_dbg_cur_addr_high,
                   core_dbg_cur_addr_low_state[15:8]};
        req_next = req_cur + {16'd0, req_delta};
        req_active_bit = req_ch[3] ? 1'b0 : core_status_dout[req_ch[2:0]];

        active_req_start_debug_i = {shadow_ram[high_base + 8'd5],
                                    shadow_ram[high_base + 8'd4]};
        active_req_loop_debug_i = {shadow_ram[low_base + 8'd5],
                                   shadow_ram[low_base + 8'd4]};
        active_req_end_delta_debug_i = {shadow_ram[low_base + 8'd6],
                                        req_delta};
        active_req_rate_debug_i = {8'd0, req_delta};
        active_req_amp_pan_debug_i = {shadow_ram[low_base + 8'd2],
                                      shadow_ram[low_base + 8'd3]};
        active_req_cfg_debug_i = {core_status_dout, req_cfg};
        active_req_next_debug_i = req_next[15:0];
        active_req_page_debug_i = req_cur[23:8];
        active_req_flow_debug_i = {
            8'hAC,
            req_active_bit,
            req_cfg[0],
            req_cfg[1],
            (req_cfg[6:4] == req_bank),
            fallback_used,
            selected_preload_addr_in_range,
            core_rom_ok,
            core_rom_cs
        };
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
        active_req_start_debug_i = 16'h2600;
        active_req_loop_debug_i = 16'h2600;
        active_req_end_delta_debug_i = {13'd0, smoke_step_divider};
        active_req_rate_debug_i = {13'd0, smoke_payload_step};
        active_req_amp_pan_debug_i = smoke_ap_debug;
        active_req_cfg_debug_i = {core_status_dout, 8'h30};
        active_req_next_debug_i = 16'h2600 + {13'd0, smoke_payload_step};
        active_req_page_debug_i = 16'h0026;
`endif
    end

`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
    assign core_cpu_cs = smoke_c0_jt_backend ? cpu_write_pulse : 1'b0;
`else
    assign core_cpu_cs = 1'b0;
`endif
`else
    assign core_cpu_cs = cpu_write_pulse;
`endif

    assign audio_l = core_snd_left;
    assign audio_r = core_snd_right;
    assign audio_sample_valid = core_sample;
    always_comb begin
        request_payload_base_offset = 19'h02600;
        unique case (ROM_ADDR_MAP_MODE)
            22: request_payload_base_offset = 19'h02200;
            23: request_payload_base_offset = 19'h02a00;
            24: request_payload_base_offset = 19'h02e00;
            25: request_payload_base_offset = 19'h02400;
            26: request_payload_base_offset = 19'h02500;
            27: request_payload_base_offset = 19'h02700;
            28: request_payload_base_offset = 19'h02800;
            29: request_payload_base_offset = 19'h02480;
            30: request_payload_base_offset = 19'h02500;
            31: request_payload_base_offset = 19'h02580;
            32: request_payload_base_offset = 19'h02400;
            33: request_payload_base_offset = 19'h02520;
            34: request_payload_base_offset = 19'h02540;
            35: request_payload_base_offset = 19'h02560;
            36: request_payload_base_offset = 19'h02580;
            default: request_payload_base_offset = 19'h02600;
        endcase

        if (request_raw_rom_addr_i >= 19'h30000) begin
            request_mapped_rom_addr_calc =
                request_payload_base_offset +
                (request_raw_rom_addr_i - 19'h30000);
        end else begin
            request_mapped_rom_addr_calc = PRELOAD_ROM_BYTES[18:0];
        end
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
        request_payload_base_offset = smoke_payload_base;
        request_mapped_rom_addr_calc = smoke_mapped_rom_addr;
`endif
    end

    always_comb begin
        mapped_rom_addr = core_rom_addr;
        effective_rom_addr = {core_rom_addr[18:16], shadow_ram[8'h8d],
                              core_rom_addr[7:0]};
        base_payload_offset = 19'h02c86;
        preload_rom_addr_valid = 1'b1;
        unique case (ROM_ADDR_MAP_MODE)
            1: begin
                if (core_rom_addr >= PRELOAD_ROM_BYTES[18:0]) begin
                    mapped_rom_addr = core_rom_addr - PRELOAD_ROM_BYTES[18:0];
                end
            end
            2: begin
                mapped_rom_addr = core_rom_addr & 19'h07fff;
                if (mapped_rom_addr >= PRELOAD_ROM_BYTES[18:0]) begin
                    mapped_rom_addr = mapped_rom_addr - PRELOAD_ROM_BYTES[18:0];
                end
            end
            3: begin
                // LastWave Seashore type-0x80 header places this payload at
                // ROM offset 0x32600 in the 0x80000-byte SegaPCM ROM image.
                if ((core_rom_addr >= 19'h32600) &&
                    (core_rom_addr < 19'h38000)) begin
                    mapped_rom_addr = core_rom_addr - 19'h32600;
                end else begin
                    mapped_rom_addr = 19'd0;
                    preload_rom_addr_valid = 1'b0;
                end
            end
            4: begin
                // Probe for cores/VGM data that expose the same payload window
                // in word-address units: 0x32600 >> 1 through 0x38000 >> 1.
                if ((core_rom_addr >= 19'h19300) &&
                    (core_rom_addr < 19'h1c000)) begin
                    mapped_rom_addr = core_rom_addr - 19'h19300;
                end else begin
                    mapped_rom_addr = 19'd0;
                    preload_rom_addr_valid = 1'b0;
                end
            end
            5: begin
                // Same byte window as mode 3, but swap the low address bit as a
                // quick alternate byte-lane probe.
                if ((core_rom_addr >= 19'h32600) &&
                    (core_rom_addr < 19'h38000)) begin
                    mapped_rom_addr = (core_rom_addr - 19'h32600) ^ 19'd1;
                end else begin
                    mapped_rom_addr = 19'd0;
                    preload_rom_addr_valid = 1'b0;
                end
            end
            6: begin
                mapped_rom_addr = core_rom_addr % PRELOAD_ROM_BYTES[18:0];
            end
            7: begin
                // Page-address probe for jtoutrun_pcm. Its ROM address is
                // {bank, cur_addr[23:8]}, so compare against the LastWave
                // payload placement in 256-byte pages: 0x326..0x37f.
                if ((core_rom_addr >= 19'h00326) &&
                    (core_rom_addr < 19'h00380)) begin
                    mapped_rom_addr = (core_rom_addr - 19'h00326) << 8;
                end else begin
                    mapped_rom_addr = 19'd0;
                    preload_rom_addr_valid = 1'b0;
                end
            end
            8: begin
                // Alternate probe if the high/low current-address register
                // interpretation is reversed: bank 3 plus page 0x0026.
                if ((core_rom_addr >= 19'h30026) &&
                    (core_rom_addr < (19'h30026 + PRELOAD_ROM_BYTES[18:0]))) begin
                    mapped_rom_addr = core_rom_addr - 19'h30026;
                end else begin
                    mapped_rom_addr = 19'd0;
                    preload_rom_addr_valid = 1'b0;
                end
            end
            9: begin
                // Experimental bank-3 window probe. Treat 0x32600..0x386ff
                // as active LastWave payload space and wrap overflow back
                // into the 0x5a00-byte extracted payload.
                if ((core_rom_addr >= 19'h32600) &&
                    (core_rom_addr < 19'h38700)) begin
                    mapped_rom_addr = (core_rom_addr - 19'h32600) %
                                      PRELOAD_ROM_BYTES[18:0];
                end else begin
                    mapped_rom_addr = 19'd0;
                    preload_rom_addr_valid = 1'b0;
                end
            end
            10: begin
                // Observed hardware range probe. LastWave ch1 reads span
                // 0x30000..0x386ff, so treat that whole bank-3 interval as
                // active and wrap it through the extracted 0x5a00-byte payload.
                if ((core_rom_addr >= 19'h30000) &&
                    (core_rom_addr < 19'h38700)) begin
                    mapped_rom_addr = (core_rom_addr - 19'h30000) %
                                      PRELOAD_ROM_BYTES[18:0];
                end else begin
                    mapped_rom_addr = 19'd0;
                    preload_rom_addr_valid = 1'b0;
                end
            end
            12: begin
                // LastWave Seashore ch1 starts at the raw address written in
                // H45: 0x38686. Map only the extracted payload-sized window.
                if ((core_rom_addr >= 19'h38686) &&
                    (core_rom_addr < (19'h38686 + PRELOAD_ROM_BYTES[18:0]))) begin
                    mapped_rom_addr = core_rom_addr - 19'h38686;
                end else begin
                    mapped_rom_addr = 19'd0;
                    preload_rom_addr_valid = 1'b0;
                end
            end
            13, 14, 15, 16, 17: begin
                // Offset sweep around mode 10's effective alignment at raw
                // 0x38686. All variants are no-wrap and return neutral data
                // outside the remaining extracted payload window.
                unique case (ROM_ADDR_MAP_MODE)
                    14: base_payload_offset = 19'h02886;
                    15: base_payload_offset = 19'h02a86;
                    16: base_payload_offset = 19'h02e86;
                    17: base_payload_offset = 19'h03086;
                    default: base_payload_offset = 19'h02c86;
                endcase
                if ((core_rom_addr >= 19'h38686) &&
                    (core_rom_addr < (19'h38686 +
                                      (PRELOAD_ROM_BYTES[18:0] -
                                       base_payload_offset)))) begin
                    mapped_rom_addr = base_payload_offset +
                                      (core_rom_addr - 19'h38686);
                end else begin
                    mapped_rom_addr = 19'd0;
                    preload_rom_addr_valid = 1'b0;
                end
            end
            18: begin
                // Lightweight raw-window probe for the generated dest-image
                // hypothesis, but still backed by the small 0x5a00 payload ROM.
                if ((core_rom_addr >= 19'h32600) &&
                    (core_rom_addr < 19'h38000)) begin
                    mapped_rom_addr = core_rom_addr - 19'h32600;
                end else begin
                    mapped_rom_addr = 19'd0;
                    preload_rom_addr_valid = 1'b0;
                end
            end
            19: begin
                // Probe whether jtoutrun_pcm's raw ROM address needs the
                // channel start/current page from SegaPCM RAM substituted into
                // the middle byte. Example: raw 0x38686 -> effective 0x32686.
                if ((effective_rom_addr >= 19'h32600) &&
                    (effective_rom_addr < 19'h38000)) begin
                    mapped_rom_addr = effective_rom_addr - 19'h32600;
                end else begin
                    mapped_rom_addr = 19'd0;
                    preload_rom_addr_valid = 1'b0;
                end
            end
            20: begin
                // Start-init probe: ch3 forced to cur_addr=0x002600 with bank 3,
                // so raw jtoutrun_pcm ROM addresses should land near 0x30026.
                // Map the extracted LastWave payload at 0x30000 without wrap.
                if ((core_rom_addr >= 19'h30000) &&
                    (core_rom_addr < 19'h35a00)) begin
                    mapped_rom_addr = core_rom_addr - 19'h30000;
                end else begin
                    mapped_rom_addr = 19'd0;
                    preload_rom_addr_valid = 1'b0;
                end
            end
            21, 22, 23, 24, 25, 26, 27, 28,
            29, 30, 31, 32, 33, 34, 35, 36: begin
                // Start-init payload-offset probes. Raw base stays 0x30000;
                // only the payload alignment changes. All variants are no-wrap.
                unique case (ROM_ADDR_MAP_MODE)
                    22: base_payload_offset = 19'h02200;
                    23: base_payload_offset = 19'h02a00;
                    24: base_payload_offset = 19'h02e00;
                    25: base_payload_offset = 19'h02400;
                    26: base_payload_offset = 19'h02500;
                    27: base_payload_offset = 19'h02700;
                    28: base_payload_offset = 19'h02800;
                    29: base_payload_offset = 19'h02480;
                    30: base_payload_offset = 19'h02500;
                    31: base_payload_offset = 19'h02580;
                    32: base_payload_offset = 19'h02400;
                    33: base_payload_offset = 19'h02520;
                    34: base_payload_offset = 19'h02540;
                    35: base_payload_offset = 19'h02560;
                    36: base_payload_offset = 19'h02580;
                    default: base_payload_offset = 19'h02600;
                endcase
                preload_rom_addr_valid = core_rom_cs || core_rom_ok;
                if (core_rom_addr >= 19'h30000) begin
                    mapped_rom_addr = base_payload_offset +
                                      (core_rom_addr - 19'h30000);
                end else begin
                    mapped_rom_addr = PRELOAD_ROM_BYTES[18:0];
                end
            end
            default: begin
                mapped_rom_addr = core_rom_addr;
            end
        endcase
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
        mapped_rom_addr = smoke_mapped_rom_addr;
        base_payload_offset = smoke_payload_base;
        preload_rom_addr_valid = 1'b1;
`endif
    end

    wire core_rom_ok_preload =
        (ROM_OK_LATENCY_MODE == 1) ? core_rom_cs_d :
        (ROM_OK_LATENCY_MODE == 2) ? core_rom_cs_d2 :
        preload_rom_ok;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign core_rom_ok = smoke_ddr_c0drive_active ?
                         (smoke_ddr_c0_return_valid_i &&
                          smoke_ddr_c0_return_in_range_i) :
                         core_rom_ok_preload;
`else
    assign core_rom_ok = core_rom_ok_preload;
`endif
`else
    assign core_rom_ok = core_rom_ok_preload;
`endif
    assign selected_preload_rom_data =
        (ROM_OK_LATENCY_MODE == 1) ? preload_rom_data :
        (ROM_OK_LATENCY_MODE == 2) ? preload_rom_data_d :
        preload_rom_data;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
    assign selected_mapped_rom_addr = smoke_mapped_rom_addr;
    assign selected_preload_addr_valid = 1'b1;
`else
    assign selected_mapped_rom_addr =
        (ROM_OK_LATENCY_MODE == 1) ?
            (((ROM_ADDR_MAP_MODE >= 21) && (ROM_ADDR_MAP_MODE <= 36)) ?
             request_mapped_rom_addr_calc : request_mapped_rom_addr_i) :
        (ROM_OK_LATENCY_MODE == 2) ? mapped_rom_addr_d2 :
        mapped_rom_addr;
    assign selected_preload_addr_valid =
        (ROM_OK_LATENCY_MODE == 1) ? request_preload_addr_valid_i :
        (ROM_OK_LATENCY_MODE == 2) ? preload_rom_addr_valid_d2 :
        preload_rom_addr_valid;
`endif
    assign selected_preload_addr_in_range =
        selected_mapped_rom_addr < PRELOAD_ROM_BYTES[18:0];
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign smoke_effective_addr_in_range =
        smoke_ddr_c0drive_active ?
        (smoke_ddr_c0_return_valid_i && smoke_ddr_c0_return_in_range_i) :
        smoke_effective_loaded_source ?
        smoke_loaded_payload_addr_in_range : selected_preload_addr_in_range;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST
    assign smoke_effective_addr_in_range =
        smoke_effective_loaded_source ?
        smoke_loaded_payload_addr_in_range : selected_preload_addr_in_range;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST
    assign smoke_effective_addr_in_range = selected_preload_addr_in_range;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST
    assign smoke_effective_addr_in_range =
        smoke_effective_loaded_source ?
        smoke_loaded_payload_addr_in_range : selected_preload_addr_in_range;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SOURCE_TEST
    assign smoke_effective_addr_in_range =
        smoke_effective_loaded_source ?
        smoke_loaded_payload_addr_in_range : selected_preload_addr_in_range;
`else
    assign smoke_effective_addr_in_range = selected_preload_addr_in_range;
`endif
    assign selected_rom_data_before_fallback =
        (smoke_ddr_c0drive_active || smoke_effective_loaded_source) ?
        smoke_loaded_payload_data_i : selected_preload_rom_data;
`else
    assign selected_rom_data_before_fallback = selected_preload_rom_data;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
    assign preload_rom_data_valid =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        smoke_c0_jt_backend ? smoke_ddr_audio_data_ok_i :
`endif
        smoke_ddr_c0drive_active ?
        (smoke_ddr_c0_return_valid_i && smoke_ddr_c0_return_in_range_i) :
        (selected_preload_addr_valid && smoke_effective_addr_in_range);
`else
    assign preload_rom_data_valid =
        core_rom_ok && selected_preload_addr_valid &&
        selected_preload_addr_in_range;
`endif
    assign fallback_used = !preload_rom_data_valid;
    assign fallback_used_this_cycle = core_rom_ok && fallback_used;
    assign core_rom_data = preload_rom_data_valid ? selected_rom_data_before_fallback :
                           8'h80;

    assign rom_request_event = core_rom_cs && (!core_rom_cs_d ||
                                               (core_rom_addr != core_rom_addr_d));
    assign ch3_rom_request_event = rom_request_event &&
                                   (core_dbg_bank_channel_state[7:4] == 4'd3) &&
                                   (core_dbg_bank_channel_state[3:0] == 4'd8);
    assign rom_return_event = core_rom_ok;
    assign rom_addr_low_debug = {core_rom_addr[7:0], mapped_rom_addr[7:0]};
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign rom_addr_raw_high_debug = {13'd0, core_rom_addr[18:16]};
    assign rom_addr_raw_low_debug = core_rom_addr[15:0];
`else
    assign rom_addr_raw_high_debug = {15'd0, smoke_source_loaded};
    assign rom_addr_raw_low_debug = {15'd0, smoke_loaded_payload_present_i};
`endif
`else
    assign rom_addr_raw_high_debug = {13'd0, core_rom_addr[18:16]};
    assign rom_addr_raw_low_debug = core_rom_addr[15:0];
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
    assign rom_addr_mapped_high_debug = {13'd0, smoke_variant_active};
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign rom_addr_mapped_low_debug = 16'h0002;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST
    assign rom_addr_mapped_low_debug = 16'h0001;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST
    assign rom_addr_mapped_low_debug = 16'h0001;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST
    assign rom_addr_mapped_low_debug = 16'h0001;
`else
    assign rom_addr_mapped_low_debug = smoke_payload_last[15:0];
`endif
`else
    assign rom_addr_mapped_high_debug = {13'd0, request_raw_rom_addr_i[18:16]};
    assign rom_addr_mapped_low_debug = request_raw_rom_addr_i[15:0];
`endif
    assign rom_addr_min_high_debug = {13'd0, selected_mapped_rom_addr[18:16]};
    assign rom_addr_min_low_debug = selected_mapped_rom_addr[15:0];
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign rom_addr_max_high_debug = loaded_payload_block_count;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST
    assign rom_addr_max_high_debug = loaded_payload_block_count;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST
    assign rom_addr_max_high_debug = loaded_payload_block_count;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST
    assign rom_addr_max_high_debug = loaded_payload_block_count;
`else
    assign rom_addr_max_high_debug = {13'd0, smoke_variant_active};
`endif
`else
    assign rom_addr_max_high_debug =
        (ROM_ADDR_MAP_MODE == 34) ? 16'h0034 :
        {8'd0, ROM_ADDR_MAP_MODE[7:0]};
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign rom_addr_max_low_debug = loaded_payload_length[15:0];
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST
    assign rom_addr_max_low_debug = smoke_loaded_capture_accept_count_i;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST
    assign rom_addr_max_low_debug = smoke_loaded_capture_accept_count_i;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST
    assign rom_addr_max_low_debug = smoke_loaded_capture_accept_count_i;
`else
    assign rom_addr_max_low_debug = request_payload_base_offset[15:0];
`endif
`else
    assign rom_addr_max_low_debug = request_payload_base_offset[15:0];
`endif
    assign rom_audio_active_high_debug = rom_addr_raw_high_debug;
    assign rom_audio_active_low_debug = rom_addr_raw_low_debug;
    assign rom_first_after_ctrl_high_debug = {13'd0, first_after_ch1_ctrl_addr_i[18:16]};
    assign rom_first_after_ctrl_low_debug = first_after_ch1_ctrl_addr_i[15:0];
    assign rom_range_group_debug = {8'hf8, ch3_rom_range_i};
    assign rom_range_group2_debug = {8'hec, rom_range_group2_i};
    assign rom_early_after_ctrl_high_debug = {13'd0, early_after_ch1_ctrl_addr_i[18:16]};
    assign rom_early_after_ctrl_low_debug = early_after_ch1_ctrl_addr_i[15:0];
    assign rom_active_after_ctrl_high_debug = {13'd0, active_after_ch1_ctrl_addr_i[18:16]};
    assign rom_active_after_ctrl_low_debug = active_after_ch1_ctrl_addr_i[15:0];
    assign rom_hit_miss_compact_debug = {rom_range_hit_count_i[7:0],
                                         rom_range_miss_count_i[7:0]};
    assign rom_range_hit_count_debug = rom_range_hit_count_i;
    assign rom_range_miss_count_debug = rom_range_miss_count_i;
    assign rom_activity_count_debug = rom_activity_count_i;
    assign rom_return_mapped_high_debug = {13'd0, last_return_mapped_addr_i[18:16]};
    assign rom_return_mapped_low_debug = last_return_mapped_addr_i[15:0];
    assign rom_return_data_debug = {8'd0, last_return_data_i};
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign rom_return_last01_debug = loaded_ddr_header_skip_count_debug;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST
    assign rom_return_last01_debug = smoke_loaded_capture_count_i[15:0];
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST
    assign rom_return_last01_debug = smoke_loaded_capture_count_i[15:0];
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST
    assign rom_return_last01_debug = smoke_loaded_capture_count_i[15:0];
`else
    assign rom_return_last01_debug = smoke_loaded_payload_length_i[15:0];
`endif
`else
    assign rom_return_last01_debug = mapped_rom_addr[15:0];
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign rom_return_last23_debug = smoke_ddr_follow_wrap_level_i;
`else
    assign rom_return_last23_debug = selected_mapped_rom_addr[15:0];
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign rom_return_nonzero_count_debug = loaded_ddr_write_req_count_debug;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
    assign rom_return_change_count_debug = lab_c0_request_count_i;
`else
    assign rom_return_change_count_debug = smoke_ddr_read_req_count_i;
`endif
`else
    assign rom_return_nonzero_count_debug = {15'd0, core_rom_cs};
    assign rom_return_change_count_debug = {15'd0, core_rom_ok};
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign rom_return_neutral_count_debug =
        {15'd0, loaded_ddr_payload_present};
`else
    assign rom_return_neutral_count_debug = {15'd0, selected_preload_addr_valid};
`endif
    assign rom_preload_data_debug = {8'd0, selected_rom_data_before_fallback};
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
    assign rom_core_ok_count_debug = lab_c0_return_count_i;
`else
    assign rom_core_ok_count_debug = smoke_ddr_read_valid_count_i;
`endif
`else
    assign rom_core_ok_count_debug = {15'd0, smoke_effective_addr_in_range};
`endif
`else
    assign rom_core_ok_count_debug = {15'd0, selected_preload_addr_in_range};
`endif
    assign rom_fallback_count_debug = {15'd0, preload_rom_data_valid};
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign rom_read_valid_count_debug = {15'd0, smoke_ddr_follow_range_miss_i};
`else
    assign rom_read_valid_count_debug = {15'd0, fallback_used_this_cycle};
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    wire rom_latency_ok_debug_bit =
        smoke_ddr_c0drive_active ?
        ((smoke_ddr_follow_accept_count_i != 16'd0) ||
         smoke_ddr_c0_return_valid_i) : core_rom_ok;
`else
    wire rom_latency_ok_debug_bit = core_rom_ok;
`endif
    assign rom_latency_debug = {
        8'hF0,
        2'd0,
        fallback_used_this_cycle,
        preload_rom_data_valid,
        selected_preload_addr_in_range,
        selected_preload_addr_valid,
        rom_latency_ok_debug_bit,
        core_rom_cs
    };
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign rom_payload_len_low_debug = smoke_type80_payload_len_19[15:0];
    assign rom_payload_len_high_debug =
        {13'd0, smoke_type80_payload_len_19[18:16]};
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST
    assign rom_payload_len_low_debug = loaded_payload_length[15:0];
    assign rom_payload_len_high_debug = SMOKE_LOADED_RAM_DEPTH_LOG2_DEBUG;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST
    assign rom_payload_len_low_debug = loaded_payload_length[15:0];
    assign rom_payload_len_high_debug = {13'd0, loaded_payload_length[18:16]};
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST
    assign rom_payload_len_low_debug = loaded_payload_length[15:0];
    assign rom_payload_len_high_debug =
        {13'd0, smoke_loaded_capture_count_i[18:16]};
`else
    assign rom_payload_len_low_debug =
        smoke_effective_loaded_source ?
        smoke_loaded_payload_length_i[15:0] : PRELOAD_ROM_BYTES[15:0];
    assign rom_payload_len_high_debug =
        smoke_effective_loaded_source ?
        {13'd0, smoke_loaded_payload_length_i[18:16]} :
        PRELOAD_ROM_BYTES[31:16];
`endif
`else
    assign rom_payload_len_low_debug = PRELOAD_ROM_BYTES[15:0];
    assign rom_payload_len_high_debug = PRELOAD_ROM_BYTES[31:16];
`endif
    assign pcm_debug_bank_channel = core_dbg_bank_channel_state;
    assign pcm_debug_cur_addr_high = core_dbg_cur_addr_high;
    assign pcm_debug_cur_addr_low_state = core_dbg_cur_addr_low_state;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    always_comb begin
        unique case (smoke_ddr_follow_offset_sel)
            3'd1: smoke_ddr_follow_offset_i = 12'h020;
            3'd2: smoke_ddr_follow_offset_i = 12'h040;
            3'd3: smoke_ddr_follow_offset_i = 12'h080;
            3'd4: smoke_ddr_follow_offset_i = 12'h100;
            3'd5: smoke_ddr_follow_offset_i = 12'h200;
            3'd6: smoke_ddr_follow_offset_i = 12'h600;
            3'd7: smoke_ddr_follow_offset_i = 12'h800;
            default: smoke_ddr_follow_offset_i = 12'h000;
        endcase

        unique case (smoke_ddr_follow_delta_sel)
            3'd1: smoke_ddr_follow_delta_i = 8'h00;
            3'd2: smoke_ddr_follow_delta_i = 8'h01;
            3'd3: smoke_ddr_follow_delta_i = 8'h02;
            3'd4: smoke_ddr_follow_delta_i = 8'h04;
            3'd5: smoke_ddr_follow_delta_i = 8'h10;
            3'd6: smoke_ddr_follow_delta_i = 8'h20;
            3'd7: smoke_ddr_follow_delta_i = 8'h40;
            default: smoke_ddr_follow_delta_i = 8'h08;
        endcase
    end
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign known38686_flags_debug = (smoke_c0_drive_sel != 2'd0) ?
        (smoke_c0_mame_match_valid_next ?
         {13'd0, smoke_c0_mame_match_index_next} : 16'hffff) :
        smoke_ddr_follow_dest_raw_offset_20[15:0];
    assign known38686_bank_debug = (smoke_c0_drive_sel != 2'd0) ?
        {11'd0, smoke_c0_mame_bank_next[20:16]} :
        smoke_ddr_follow_word_next;
    assign known38686_channel_debug = (smoke_c0_drive_sel != 2'd0) ?
        smoke_c0_mame_match_base_next[15:0] :
        smoke_ddr_follow_accept_count_i;
    assign known38686_state_debug = (smoke_c0_drive_sel != 2'd0) ?
        smoke_c0_mame_payload_offset_next[15:0] :
        smoke_ddr_follow_payload_offset_i;
    assign known38686_cur_high_debug = (smoke_c0_drive_sel != 2'd0) ?
        smoke_c0_mame_full_addr_next[15:0] :
        smoke_ddr_follow_norm_core_next[15:0];
    assign known38686_cur_low_debug = (smoke_c0_drive_sel != 2'd0) ?
        smoke_ddr_follow_return_count_i :
        smoke_ddr_follow_norm_dest_next[15:0];
    assign known38686_en_addr_debug = smoke_ddr_follow_lane_next;
    assign known38686_en_value_debug = (smoke_c0_drive_sel != 2'd0) ?
        core_dbg_smoke_cur_live_frac :
        core_dbg_smoke_cur_live_frac;
`else
    assign known38686_flags_debug = active_req_flow_debug_i;
    assign known38686_bank_debug = core_dbg_bank_channel_state;
    assign known38686_channel_debug = {12'd0, core_dbg_bank_channel_state[7:4]};
    assign known38686_state_debug = {12'd0, core_dbg_bank_channel_state[3:0]};
    assign known38686_cur_high_debug = active_req_start_debug_i;
    assign known38686_cur_low_debug = active_req_loop_debug_i;
    assign known38686_en_addr_debug = active_req_next_debug_i;
    assign known38686_en_value_debug = active_req_end_delta_debug_i;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign known38686_d0_addr_debug = (smoke_c0_drive_sel != 2'd0) ?
        smoke_c0_mame_read_index_next[15:0] :
        smoke_ddr_follow_mapped_index_i;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST
    assign known38686_d0_addr_debug = smoke_loaded_write_count_i;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST
    assign known38686_d0_addr_debug = smoke_loaded_last_write_addr_i[15:0];
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST
    assign known38686_d0_addr_debug = smoke_loaded_write_count_i;
`else
    assign known38686_d0_addr_debug = active_req_rate_debug_i;
`endif
`else
    assign known38686_d0_addr_debug = active_req_rate_debug_i;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign known38686_d0_value_debug = {
        11'd0,
        fallback_used_this_cycle ||
        ((smoke_c0_drive_sel != 2'd0) && !smoke_c0_mame_match_valid_next),
        preload_rom_data_valid,
        smoke_ddr_c0_return_in_range_i,
        smoke_ddr_follow_dest_addr_in_range_next,
        !smoke_ddr_follow_read_in_range_next
    };
`else
    assign known38686_d0_value_debug = smoke_ap_debug;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign known38686_d1_addr_debug = (smoke_c0_drive_sel != 2'd0) ?
        smoke_c0_mame_match_dest_next[15:0] :
        smoke_ddr_follow_norm_dest_next[15:0];
`else
    assign known38686_d1_addr_debug = 16'h0030;
`endif
`else
    assign known38686_d0_value_debug = active_req_amp_pan_debug_i;
    assign known38686_d1_addr_debug = active_req_cfg_debug_i;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign known38686_d1_value_debug = (smoke_c0_drive_sel != 2'd0) ?
        smoke_c0_mame_match_len_next[15:0] :
        smoke_type80_payload_len_19[15:0];
    assign known38686_d2_value_debug = (smoke_c0_drive_sel != 2'd0) ?
        smoke_c0_mame_offset_21_next[15:0] :
        smoke_ddr_follow_mi_at_ic_fall_i;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST
    assign known38686_d1_value_debug =
        smoke_loaded_last_write_addr_i[15:0];
    assign known38686_d2_value_debug =
        {8'd0, smoke_loaded_last_write_data_i};
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST
    assign known38686_d1_value_debug =
        {8'd0, smoke_loaded_last_write_data_i};
    assign known38686_d2_value_debug =
        {13'd0, loaded_payload_length[18:16]};
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST
    assign known38686_d1_value_debug =
        smoke_loaded_last_write_addr_i[15:0];
    assign known38686_d2_value_debug =
        {8'd0, smoke_loaded_last_write_data_i};
`else
    assign known38686_d1_value_debug = active_req_flow_debug_i;
    assign known38686_d2_value_debug = {8'd0, core_dbg_cur_addr_low_state[15:8]};
`endif
`else
    assign known38686_d1_value_debug = active_req_flow_debug_i;
    assign known38686_d2_value_debug = {8'd0, core_dbg_cur_addr_low_state[15:8]};
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign known38686_d2_addr_debug = (smoke_c0_drive_sel != 2'd0) ?
        smoke_c0_mame_match_base_next[15:0] :
        smoke_ddr_follow_po_at_ic_fall_i;
`else
    assign known38686_d2_addr_debug = active_req_page_debug_i;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign known38686_cfg_en_debug = (smoke_c0_drive_sel != 2'd0) ?
        smoke_ddr_follow_mixer_count_i :
        smoke_ddr_follow_mixer_count_i;
`else
    assign known38686_cfg_en_debug = 16'h0030;
`endif
`else
    assign known38686_cfg_en_debug = active_req_cfg_debug_i;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign known38686_cur_23_debug = (smoke_c0_drive_sel != 2'd0) ?
        {smoke_c0_probe_byte_i[0], smoke_c0_probe_byte_i[1]} :
        core_dbg_smoke_end_eq;
    assign known38686_cur_15_debug = (smoke_c0_drive_sel != 2'd0) ?
        {smoke_c0_probe_byte_i[2], smoke_c0_probe_byte_i[3]} :
        core_dbg_smoke_loop_wrap;
    assign known38686_cur_07_debug = (smoke_c0_drive_sel != 2'd0) ?
        {smoke_c0_write_probe_byte_i[0],
         smoke_c0_write_probe_byte_i[1]} :
        core_dbg_smoke_end_hit;
`else
    assign known38686_cur_23_debug = {8'd0, core_dbg_cur_addr_high[15:8]};
    assign known38686_cur_15_debug = {8'd0, core_dbg_cur_addr_high[7:0]};
    assign known38686_cur_07_debug = {8'd0, core_dbg_cur_addr_low_state[15:8]};
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign c0_capture_write_count_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0) ?
            (lab_c0_multich_delta_mode ? lab16_clip_count_i :
             (lab_c0_mame_exact_mode ?
                lab_c0_pm4_write_count_i : smoke_c0_write_probe_seen_i)) :
`else
        (smoke_c0_drive_sel != 2'd0) ? smoke_c0_write_probe_seen_i :
`endif
        c0_capture_write_count_i;
    assign c0_capture_last_addr_debug = (smoke_c0_drive_sel != 2'd0) ?
        {smoke_c0_write_probe_byte_i[2],
         smoke_c0_write_probe_byte_i[3]} :
        c0_capture_last_addr_i;
    assign c0_capture_last_data_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0) ?
            (lab_c0_multich_delta_mode ? lab16_reseed_count_i :
             (lab_c0_mame_exact_mode ?
                lab_c0_pm4_reseed_count_i : lab_c0_reseed_count_i)) :
`else
        (smoke_c0_drive_sel != 2'd0) ? loaded_ddr_probe_write_index_debug :
`endif
        c0_capture_last_data_i;
    assign c0_capture_channel_activity_debug = (smoke_c0_drive_sel != 2'd0) ?
        loaded_ddr_probe_write_word_debug :
        c0_capture_channel_activity_i;
    assign c0_capture_selected_channel_debug = (smoke_c0_drive_sel != 2'd0) ?
        16'h0003 :
        16'h0003;
    assign c0_capture_ch3_ctrl_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0) ?
            (lab_c0_multich_delta_mode ?
                lab16_retrigger_count_i : lab_c0_retrigger_count_i) :
`else
        (smoke_c0_drive_sel != 2'd0) ? loaded_ddr_probe_write_lane_debug :
`endif
        {8'd0, c0_capture_ch3_ctrl_i};
    assign c0_capture_ch3_cur_low_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0) ?
            (lab_c0_multich_delta_mode ?
                lab16_ch3_emit_count_i : lab_c0_event_seed_i) :
`else
        (smoke_c0_drive_sel != 2'd0) ? loaded_ddr_probe_write_addr_debug :
`endif
        {8'd0, c0_capture_ch3_cur_low_i};
    assign c0_capture_ch3_cur_mid_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0) ?
            (lab_c0_multich_delta_mode ?
                {{7{lab16_selected_cv[8]}}, lab16_selected_cv} :
                {{7{lab_c0_selected_cv[8]}}, lab_c0_selected_cv}) :
`else
        (smoke_c0_drive_sel != 2'd0) ? loaded_ddr_probe_write_count_debug :
`endif
        {8'd0, c0_capture_ch3_cur_mid_i};
    assign c0_capture_ch3_cur_high_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0) ?
            (lab_c0_multich_delta_mode ?
                lab16_ch3_tick_count_i : lab_c0_mame_tick_count_i) :
`else
        (smoke_c0_drive_sel != 2'd0) ? loaded_ddr_probe_write_flags_debug :
`endif
        {8'd0, c0_capture_ch3_cur_high_i};
    assign c0_capture_ch3_delta_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0 && lab_c0_multich_delta_mode) ?
            lab16_active_mask :
`endif
        {8'd0, c0_capture_ch3_delta_i};
    assign c0_capture_ch3_vol_l_debug = {8'd0, c0_capture_ch3_vol_l_i};
    assign c0_capture_ch3_vol_r_debug = {8'd0, c0_capture_ch3_vol_r_i};
    assign c0_capture_ch3_loop_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0) ?
            (lab_c0_multich_delta_mode ?
                lab16_ch3_output_i : {8'd0, lab_c0_phase_i[7:0]}) :
`else
        (smoke_c0_drive_sel != 2'd0) ? loaded_ddr_probe_write_word0_debug :
`endif
        {c0_capture_ch3_loop_mid_i, c0_capture_ch3_loop_high_i};
    assign c0_capture_ch3_end_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0) ?
        (lab_c0_multich_delta_mode ? lab16_ch3_hold_i : {
            6'd0,
            lab_c0_active_i,
            !lab_c0_pi_in_range,
            lab_c0_mame_end_hit,
            lab_c0_mame_loop_seen_i,
            lab_c0_mame_ctrl_disabled,
            smoke_playback_done,
            smoke_vgm_end_seen,
            lab_c0_mame_loud_active_i,
            lab_c0_mame_loud_count_i == 3'd4,
            lab_c0_mame_trace_count_i == 3'd4,
            lab_c0_pi_in_range,
            smoke_playback_running
        }) :
`else
        (smoke_c0_drive_sel != 2'd0) ? loaded_ddr_probe_write_word6_debug :
`endif
        {8'd0, c0_capture_ch3_end_i};
	`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
	    assign jt_smoke_vol_l_debug = smoke_c0_jt_backend ?
            core_dbg_smoke_jt_vol_l :
            (smoke_c0_drive_sel != 2'd0) ?
	        (lab_c0_multich_delta_mode ? lab16_active_mask : {
	            lab_c0_fixed_mode,
	            lab_c0_local_seq_mode,
            smoke_playback_running,
            !smoke_playback_done,
            !smoke_vgm_end_seen,
            smoke_ddr_c0drive_active,
            lab_c0_pv_match,
            lab_c0_raw_audible,
            lab_c0_seq_output || lab_c0_local_output,
            lab_c0_seq_emit_pulse || lab_c0_return_pulse,
            lab_c0_active_i,
            lab_c0_state_i,
            smoke_c0_drive_sel
        }) :
	        core_dbg_smoke_seed_reload_req;
	    assign jt_smoke_vol_r_debug = smoke_c0_jt_backend ?
            core_dbg_smoke_jt_vol_r :
            (smoke_c0_drive_sel != 2'd0) ?
	        (lab_c0_multich_delta_mode ?
	            lab16_ch3_worst_reason_i :
	            (lab_c0_fixed_mode ? {13'd0, lab_c0_fixed_index_i} :
	                                 lab_c0_pi_i[15:0])) :
        core_dbg_smoke_first_addr;
`else
    assign jt_smoke_vol_l_debug = (smoke_c0_drive_sel != 2'd0) ?
        {11'd0, smoke_c0_mame_full_addr_next[20:16]} :
        core_dbg_smoke_seed_reload_req;
    assign jt_smoke_vol_r_debug = (smoke_c0_drive_sel != 2'd0) ?
        core_dbg_smoke_first_addr :
        core_dbg_smoke_first_addr;
`endif
	    assign jt_smoke_sample_byte_debug =
	`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
	        smoke_c0_jt_backend ? core_dbg_smoke_sample_byte :
	        (smoke_c0_drive_sel != 2'd0 && lab_c0_multich_delta_mode) ?
	            lab16_ch3_worst_raw_cv_i :
	`endif
	        core_dbg_smoke_sample_byte;
	    assign jt_smoke_out_l_debug =
	`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
	        smoke_c0_jt_backend ? core_dbg_smoke_out_l :
	        (smoke_c0_drive_sel != 2'd0 && lab_c0_multich_delta_mode) ?
	            lab16_ch3_worst_l_i :
	`endif
	        core_dbg_smoke_out_l;
	    assign jt_smoke_out_r_debug =
	`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
	        smoke_c0_jt_backend ? core_dbg_smoke_out_r :
	        (smoke_c0_drive_sel != 2'd0) ?
	            (lab_c0_multich_delta_mode ?
	                lab16_ch3_retrig_base_i :
	                lab_c0_mame_mv_wide[15:0]) :
	`endif
        core_dbg_smoke_out_r;
`else
    assign c0_capture_write_count_debug = 16'd0;
    assign c0_capture_last_addr_debug = 16'd0;
    assign c0_capture_last_data_debug = 16'd0;
    assign c0_capture_channel_activity_debug = 16'd0;
    assign c0_capture_selected_channel_debug = 16'd0;
    assign c0_capture_ch3_ctrl_debug = 16'd0;
    assign c0_capture_ch3_cur_low_debug = 16'd0;
    assign c0_capture_ch3_cur_mid_debug = 16'd0;
    assign c0_capture_ch3_cur_high_debug = 16'd0;
    assign c0_capture_ch3_delta_debug = 16'd0;
    assign c0_capture_ch3_vol_l_debug = 16'd0;
    assign c0_capture_ch3_vol_r_debug = 16'd0;
    assign c0_capture_ch3_loop_debug = 16'd0;
    assign c0_capture_ch3_end_debug = 16'd0;
    assign jt_smoke_vol_l_debug = 16'd0;
    assign jt_smoke_vol_r_debug = 16'd0;
    assign jt_smoke_sample_byte_debug = 16'd0;
    assign jt_smoke_out_l_debug = 16'd0;
    assign jt_smoke_out_r_debug = 16'd0;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
    assign ch3_evolution_flags_debug =
        lab_c0_multich_delta_mode ? core_dbg_ch3_evolution_flags :
        (lab_c0_mame_exact_mode) ?
        lab_c0_hit_count_i :
        lab_c0_advance_count_i;
`else
    assign ch3_evolution_flags_debug =
        smoke_ddr_audio_update_count_i;
`endif
    assign ch3_delta_debug =
        lab_c0_multich_delta_mode ? core_dbg_ch3_delta :
        lab_c0_phase_increment[15:0];
`else
    assign ch3_evolution_flags_debug = core_dbg_ch3_evolution_flags;
    assign ch3_delta_debug = core_dbg_ch3_delta;
`endif
    assign ch1_first_high_debug = core_dbg_ch1_first_high;
    assign ch1_first_low_debug = core_dbg_ch1_first_low;
    assign ch1_first_raw_high_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0 && lab_c0_mame_exact_mode) ?
            lab_c0_mame_loud_p0_i :
`endif
        core_dbg_ch1_first_raw_high;
    assign ch1_first_raw_low_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0 && lab_c0_mame_exact_mode) ?
            lab_c0_mame_loud_p1_i :
`endif
        core_dbg_ch1_first_raw_low;
    assign ch3_first_high_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0 && lab_c0_mame_exact_mode) ?
            lab_c0_mame_loud_p2_i :
`endif
        core_dbg_ch3_first_high;
    assign ch3_first_low_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0 && lab_c0_mame_exact_mode) ?
            lab_c0_mame_loud_p3_i :
`endif
        core_dbg_ch3_first_low;
    assign ch3_first_raw_high_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0 && lab_c0_mame_exact_mode) ?
            lab_c0_mame_loud_q0_i :
`endif
        core_dbg_ch3_first_raw_high;
    assign ch3_first_raw_low_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0 && lab_c0_mame_exact_mode) ?
            lab_c0_mame_loud_q1_i :
`endif
        core_dbg_ch3_first_raw_low;
    assign ch3_r0_high_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0 && lab_c0_mame_exact_mode) ?
            lab_c0_mame_loud_q2_i :
`endif
        core_dbg_ch3_r0_high;
    assign ch3_r0_low_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0 && lab_c0_mame_exact_mode) ?
            lab_c0_mame_loud_q3_i :
`endif
        core_dbg_ch3_r0_low;
    assign ch3_r1_high_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0 && lab_c0_mame_exact_mode) ?
            lab_c0_mame_loud_m0_i :
`endif
        core_dbg_ch3_r1_high;
    assign ch3_r1_low_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0 && lab_c0_mame_exact_mode) ?
            lab_c0_mame_loud_m1_i :
`endif
        core_dbg_ch3_r1_low;
    assign ch3_r2_high_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0 && lab_c0_mame_exact_mode) ?
            lab_c0_mame_loud_m2_i :
`endif
        core_dbg_ch3_r2_high;
    assign ch3_r2_low_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        (smoke_c0_drive_sel != 2'd0 && lab_c0_mame_exact_mode) ?
            lab_c0_mame_loud_m3_i :
`endif
        core_dbg_ch3_r2_low;
    assign dbg_ch3_load_after_23 = core_dbg_ch3_load_after_23;
    assign dbg_ch3_load_after_15 = core_dbg_ch3_load_after_15;
    assign dbg_ch3_load_after_07 = core_dbg_ch3_load_after_07;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
    assign update_state_channel_debug = core_dbg_update_state_channel;
    assign update_before_23_debug = core_dbg_update_before_23;
    assign update_before_15_debug = core_dbg_update_before_15;
    assign update_before_07_debug = core_dbg_update_before_07;
    assign update_addend_debug = core_dbg_update_addend;
    assign update_after_23_debug = core_dbg_update_after_23;
    assign update_after_15_debug = core_dbg_update_after_15;
    assign update_after_07_debug = core_dbg_update_after_07;
    assign update_reason_debug = core_dbg_update_reason;
`else
    assign update_state_channel_debug = (smoke_c0_drive_sel != 2'd0) ?
        {12'd0, smoke_type80_table_count_i} :
        core_dbg_smoke_end_input;
    assign update_before_23_debug = (smoke_c0_drive_sel != 2'd0) ?
        core_dbg_smoke_loop_input :
        core_dbg_smoke_loop_input;
    assign update_before_15_debug = (smoke_c0_drive_sel != 2'd0) ?
        {11'd0, smoke_c0_mame_full_addr_next[20:16]} :
        core_dbg_smoke_source_addr;
    assign update_before_07_debug = (smoke_c0_drive_sel != 2'd0) ?
        smoke_c0_mame_current_addr_next :
        core_dbg_smoke_cur_live_low;
    assign update_addend_debug = (smoke_c0_drive_sel != 2'd0) ?
        {8'd0, smoke_delta} :
        {8'd0, smoke_delta};
    assign update_after_23_debug = (smoke_c0_drive_sel != 2'd0) ?
        smoke_c0_mame_match_base_next[15:0] :
        core_dbg_smoke_request_addr;
    assign update_after_15_debug = (smoke_c0_drive_sel != 2'd0) ?
        core_dbg_smoke_playback_addr :
        core_dbg_smoke_playback_addr;
    assign update_after_07_debug = (smoke_c0_drive_sel != 2'd0) ?
        core_dbg_smoke_seed_commit_addr :
        core_dbg_smoke_seed_commit_addr;
    assign update_reason_debug = (smoke_c0_drive_sel != 2'd0) ?
        core_dbg_smoke_current_input :
        core_dbg_smoke_current_input;
`endif
`else
    assign update_state_channel_debug = known38686_state8_channel3 ?
                                        {8'd0, known38686_state_i, known38686_channel_i} :
                                        16'd0;
    assign update_before_23_debug = core_dbg_38686_d0_addr;
    assign update_before_15_debug = core_dbg_38686_d1_addr;
    assign update_before_07_debug = core_dbg_38686_d2_addr;
    assign update_addend_debug = known38686_state8_channel3 ? core_dbg_38686_delta : 16'd0;
    assign update_after_23_debug = core_dbg_update_after_23;
    assign update_after_15_debug = core_dbg_update_after_15;
    assign update_after_07_debug = core_dbg_update_after_07;
    assign update_reason_debug = known38686_state8_channel3 ? 16'hEE20 : 16'd0;
`endif
    assign cpu_write_count_debug = core_write_count_i;
    assign cpu_cen_write_count_debug = core_cen_write_count_i;
    assign cpu_addr_debug = {latched_raw_addr[7:0], latched_cpu_addr};
    assign shadow_decode_debug =
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
        smoke_c0_jt_backend ? lab_jt_last_cpu_write_i :
`endif
        shadow_decode_i;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
	    assign shadow_ch0_vol_debug = lab16_ch3_write_count_i;
	    assign shadow_ch0_end_delta_debug =
	        lab16_ch3_current_update_count_i;
	    assign shadow_ch0_start_debug = lab16_ch3_end_update_count_i;
	    assign shadow_ch0_ctrl_debug = lab16_ch3_delta_update_count_i;
	    assign shadow_ch1_vol_debug = lab16_ch3_volume_update_count_i;
	    assign shadow_ch1_loop_debug = lab16_ch3_ctrl_update_count_i;
	    assign shadow_ch1_end_delta_debug = lab16_ch3_reseed_count_i;
	    assign shadow_ch1_start_debug = lab16_ch3_qualified_start_count_i;
	    assign shadow_ch1_ctrl_debug = lab16_ch3_ignored_update_count_i;
`else
    assign shadow_ch0_vol_debug = {shadow_ram[8'h02], shadow_ram[8'h03]};
    assign shadow_ch0_end_delta_debug = {shadow_ram[8'h06], shadow_ram[8'h07]};
    assign shadow_ch0_start_debug = {shadow_ram[8'h84], shadow_ram[8'h85]};
    assign shadow_ch0_ctrl_debug = {shadow_ram[8'h86], shadow_ram[8'h87]};
    assign shadow_ch1_vol_debug = {shadow_ram[8'h0a], shadow_ram[8'h0b]};
    assign shadow_ch1_loop_debug = {shadow_ram[8'h0c], shadow_ram[8'h0d]};
    assign shadow_ch1_end_delta_debug = {shadow_ram[8'h0e], shadow_ram[8'h0f]};
    assign shadow_ch1_start_debug = {shadow_ram[8'h8c], shadow_ram[8'h8d]};
    assign shadow_ch1_ctrl_debug = {shadow_ram[8'h8e], shadow_ram[8'h8f]};
`endif
    assign shadow_ch3_loop_debug = {shadow_ram[8'h1c], shadow_ram[8'h1d]};
    assign shadow_ch3_end_delta_debug = {shadow_ram[8'h1e], shadow_ram[8'h1f]};
    assign shadow_ch3_start_debug = {shadow_ram[8'h9c], shadow_ram[8'h9d]};
    assign shadow_ch3_ctrl_debug = {shadow_ram[8'h9e], shadow_ram[8'h9f]};
    assign shadow_ch3_l0_debug = {shadow_ram[8'h18], shadow_ram[8'h19]};
    assign shadow_ch3_l2_debug = {shadow_ram[8'h1a], shadow_ram[8'h1b]};
    assign shadow_ch3_l4_debug = {shadow_ram[8'h1c], shadow_ram[8'h1d]};
    assign shadow_ch3_l6_debug = {shadow_ram[8'h1e], shadow_ram[8'h1f]};
    assign shadow_ch3_h0_debug = {shadow_ram[8'h98], shadow_ram[8'h99]};
    assign shadow_ch3_h2_debug = {shadow_ram[8'h9a], shadow_ram[8'h9b]};
    assign shadow_ch3_h4_debug = {shadow_ram[8'h9c], shadow_ram[8'h9d]};
    assign shadow_ch3_h6_debug = {shadow_ram[8'h9e], shadow_ram[8'h9f]};
    assign audio_nonzero_count_debug = audio_nonzero_count_i;
    assign audio_abs_peak_debug = audio_abs_peak_i;
    assign last_audio_l_debug = last_audio_l_i;
    assign last_audio_r_debug = last_audio_r_i;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
    assign core_status_debug =
        smoke_c0_jt_backend ? lab_jt_bringup_status :
        {12'd0, lab_c0_pump_branch_debug};
`else
    assign core_status_debug = {
        core_status_dout[7:4],
        preload_rom_addr_valid,
        preload_rom_data_valid,
        ROM_ADDR_MAP_MODE[2:0],
        core_sample,
        (core_snd_left != 16'sd0) || (core_snd_right != 16'sd0),
        core_rom_ok,
        core_rom_cs,
        core_cpu_cs,
        C0_WRITE_HOLD_FOR_CEN,
        C0_ADDR_MAP_MODE[0]
    };
`endif

    always_ff @(posedge clk) begin
        if (reset) begin
            cen_accum <= 32'd0;
            segapcm_cen <= 1'b0;
        end else if (cen_accum >= (CLK_SYS_HZ - SEGAPCM_CLK_HZ)) begin
            cen_accum <= cen_accum + SEGAPCM_CLK_HZ - CLK_SYS_HZ;
            segapcm_cen <= 1'b1;
        end else begin
            cen_accum <= cen_accum + SEGAPCM_CLK_HZ;
            segapcm_cen <= 1'b0;
        end
    end

`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    always_ff @(posedge clk) begin
        if (reset || loaded_payload_clear) begin
            lab_c0_active_i <= 1'b0;
            lab_c0_seed_i <= 16'd0;
            lab_c0_cur_i <= 16'd0;
            lab_c0_state_i <= LAB_C0_ST_IDLE;
            lab_c0_pi_i <= 19'd0;
            lab_c0_return_pi_i <= 19'd0;
            lab_c0_advance_count_i <= 16'd0;
            lab_c0_stall_count_i <= 16'd0;
            lab_c0_request_count_i <= 16'd0;
            lab_c0_return_count_i <= 16'd0;
            lab_c0_sample_i <= 8'h80;
            lab_c0_output_i <= 16'sd0;
            lab_c0_consume_pulse_i <= 1'b0;
            lab_c0_pending_i <= 1'b0;
            lab_c0_req_live_i <= 1'b0;
            lab_c0_need_read_i <= 1'b0;
            lab_c0_req_addr_i <= 19'd0;
            lab_c0_fixed_index_i <= 3'd0;
            lab_c0_fixed_div_i <= 12'd0;
            lab_c0_mame_tick_div_count_i <= 4'd0;
            lab_c0_mame_tick_count_i <= 16'd0;
            lab_c0_phase_i <= 27'd0;
            lab_c0_retrigger_count_i <= 16'd0;
            lab_c0_reseed_count_i <= 16'd0;
            lab_c0_pm4_write_count_i <= 16'd0;
            lab_c0_pm4_reseed_count_i <= 16'd0;
            lab_c0_pm4_reseed_reason_i <= 16'd0;
            lab_c0_event_time_i <= 16'd0;
            lab_c0_event_seed_i <= 16'd0;
            lab_c0_reseed_pi_i <= 19'd0;
            lab_c0_hit_count_i <= 16'd0;
            lab_c0_mame_trace_armed_i <= 1'b0;
            lab_c0_mame_trace_count_i <= 3'd0;
            lab_c0_mame_k0_i <= 16'd0;
            lab_c0_mame_k1_i <= 16'd0;
            lab_c0_mame_k2_i <= 16'd0;
            lab_c0_mame_k3_i <= 16'd0;
            lab_c0_mame_b0_i <= 16'd0;
            lab_c0_mame_b1_i <= 16'd0;
            lab_c0_mame_b2_i <= 16'd0;
            lab_c0_mame_b3_i <= 16'd0;
            lab_c0_mame_c0_i <= 16'd0;
            lab_c0_mame_c1_i <= 16'd0;
            lab_c0_mame_c2_i <= 16'd0;
            lab_c0_mame_c3_i <= 16'd0;
            lab_c0_mame_loop_seen_i <= 1'b0;
            lab_c0_mame_loud_armed_i <= 1'b0;
            lab_c0_mame_loud_active_i <= 1'b0;
            lab_c0_mame_loud_count_i <= 3'd0;
            lab_c0_mame_loud_p0_i <= 16'd0;
            lab_c0_mame_loud_p1_i <= 16'd0;
            lab_c0_mame_loud_p2_i <= 16'd0;
            lab_c0_mame_loud_p3_i <= 16'd0;
            lab_c0_mame_loud_q0_i <= 16'd0;
            lab_c0_mame_loud_q1_i <= 16'd0;
            lab_c0_mame_loud_q2_i <= 16'd0;
            lab_c0_mame_loud_q3_i <= 16'd0;
            lab_c0_mame_loud_m0_i <= 16'd0;
            lab_c0_mame_loud_m1_i <= 16'd0;
            lab_c0_mame_loud_m2_i <= 16'd0;
            lab_c0_mame_loud_m3_i <= 16'd0;
            lab16_active_i <= 16'd0;
            lab16_strict_seen_i <= 16'd0;
            lab16_rr_ch_i <= 4'd0;
            lab16_pending_ch_i <= 4'd0;
            lab16_emit_div_i <= 12'd0;
            lab16_request_count_i <= 16'd0;
            lab16_return_count_i <= 16'd0;
            lab16_clip_count_i <= 16'd0;
            lab16_retrigger_count_i <= 16'd0;
            lab16_reseed_count_i <= 16'd0;
            lab16_ch3_reseed_count_i <= 16'd0;
            lab16_ch3_stop_reason_i <= 16'd0;
            lab16_ch3_map_valid_i <= 1'b0;
            lab16_ch3_tick_count_i <= 16'd0;
            lab16_ch3_emit_count_i <= 16'd0;
            lab16_ch3_output_i <= 16'd0;
            lab16_ch3_hold_i <= 16'd0;
            lab16_ch3_sticky_i <= 16'd0;
            lab16_ch3_range_count_i <= 16'd0;
            lab16_ch3_hit_len_i <= 16'd0;
            lab16_ch3_intro_reseed_count_i <= 16'd0;
            lab16_mix_peak_i <= 16'd0;
            lab16_ch3_peak_i <= 16'd0;
            lab16_map_hit_count_i <= 16'd0;
            lab16_map_miss_count_i <= 16'd0;
            lab16_ever_active_i <= 16'd0;
            lab16_ever_nonzero_i <= 16'd0;
            lab16_sticky_map_i <= 16'd0;
            lab16_max_active_count_i <= 5'd0;
            lab16_start_tuple_count_i <= 16'd0;
            lab16_target_start_count_i <= 16'd0;
            lab16_skipped_start_count_i <= 16'd0;
            lab16_target_current_i <= 16'd0;
            lab16_target_full_low_i <= 16'd0;
            lab16_target_match_bits_i <= 8'd0;
            lab16_start_tuple_ch_i <= 4'd0;
            lab16_start_tuple_block_i <= 3'd0;
            lab16_start_tuple_current_i <= 16'd0;
            lab16_start_tuple_bank_i <= 21'd0;
            lab16_start_tuple_full_addr_i <= 21'd0;
            lab16_start_tuple_delta_i <= 8'd0;
            lab16_start_tuple_vol_l_i <= 7'd0;
            lab16_start_tuple_vol_r_i <= 7'd0;
            lab16_start_tuple_source_i <= 16'd0;
            lab16_start_tuple_valid_i <= 1'b0;
            lab16_first_samples_valid_i <= 1'b0;
            lab16_first_capture_armed_i <= 1'b0;
            lab16_first_capture_has_any_i <= 1'b0;
            lab16_first_capture_reader_match_i <= 1'b0;
            lab16_first_capture_overwrite_i <= 1'b0;
            lab16_first_capture_cleared_i <= 1'b1;
            lab16_runtime_active_seen_i <= 1'b0;
            lab16_runtime_consume_count_i <= 16'd0;
            lab16_runtime_status_i <= 16'hE500;
            lab16_runtime_offset_i <= 16'd0;
            lab16_runtime_addr_i <= 16'd0;
            lab16_runtime_pr_hold_i <= 16'hE600;
            lab16_runtime_pi_i <= 19'd0;
            lab16_runtime_phase_hint_i <= 16'd0;
            lab16_runtime_rd_i <= 16'd0;
            lab16_runtime_l_i <= 16'sd0;
            lab16_runtime_r_i <= 16'sd0;
            lab16_runtime_stop_i <= 16'hE500;
            lab16_start_tuple_end_addr_i <= 21'd0;
            lab16_start_tuple_limit_i <= 19'd0;
            lab16_start_tuple_end_limited_i <= 1'b0;
            lab16_last_stop_pi_i <= 19'd0;
            lab16_end_debug_flags_i <= 16'hE900;
            lab16_stop_valid_i <= 1'b0;
            lab16_stop_count_i <= 16'd0;
            lab16_stop_offset_i <= 16'd0;
            lab16_stop_pi_i <= 16'd0;
            lab16_stop_full_i <= 16'd0;
            lab16_stop_phase_i <= 16'd0;
            lab16_stop_flags_i <= 16'hEA00;
            lab16_first_s0_addr_i <= 16'd0;
            lab16_first_s0_index_i <= 16'd0;
            lab16_first_s0_phase_i <= 16'd0;
            lab16_first_s0_capture_count_i <= 16'd0;
            lab16_first_sample_count_i <= 5'd0;
            lab16_first_raw01_i <= 16'd0;
            lab16_first_raw23_i <= 16'd0;
            lab16_first_raw45_i <= 16'd0;
            lab16_first_raw67_i <= 16'd0;
            lab16_first_raw89_i <= 16'd0;
            lab16_first_rawab_i <= 16'd0;
            lab16_first_rawcd_i <= 16'd0;
            lab16_first_rawef_i <= 16'd0;
            lab16_first_dec01_i <= 16'd0;
            lab16_first_dec23_i <= 16'd0;
            lab16_first_dec45_i <= 16'd0;
            lab16_first_dec67_i <= 16'd0;
            lab16_first_dec89_i <= 16'd0;
            lab16_first_decab_i <= 16'd0;
            lab16_first_deccd_i <= 16'd0;
            lab16_first_decef_i <= 16'd0;
            lab16_wave_rawcv0_i <= 16'd0;
            lab16_wave_addr0_i <= 16'd0;
            lab16_wave_pi0_i <= 16'd0;
            lab16_wave_out0_i <= 16'd0;
            lab16_wave_rawcv1_i <= 16'd0;
            lab16_wave_addr1_i <= 16'd0;
            lab16_wave_pi1_i <= 16'd0;
            lab16_wave_out1_i <= 16'd0;
            lab16_wave_rawcv2_i <= 16'd0;
            lab16_wave_addr2_i <= 16'd0;
            lab16_wave_pi2_i <= 16'd0;
            lab16_wave_out2_i <= 16'd0;
            lab16_wave_rawcv3_i <= 16'd0;
            lab16_wave_addr3_i <= 16'd0;
            lab16_wave_pi3_i <= 16'd0;
            lab16_wave_out3_i <= 16'd0;
            lab16_wave_vol_i <= 16'd0;
            lab16_ch3_raw_event_count_i <= 16'd0;
            lab16_ch3_block_hit_count_i <= 16'd0;
            lab16_ch3_full_addr_i <= 21'd0;
            lab16_ch3_block_i <= 3'd0;
            lab16_ch3_block_dest_i <= 21'd0;
            lab16_ch3_block_base_i <= 19'd0;
            lab16_ch3_block_len_i <= 19'd0;
            lab16_ch3_block_offset_i <= 19'd0;
            lab16_ch3_reject_i <= 16'd0;
            lab16_ch3_snapshot_valid_i <= 1'b0;
            lab16_ch3_snapshot_count_i <= 16'd0;
            lab16_ch3_snapshot_ctrl_i <= 8'd0;
            lab16_ch3_snapshot_vol_l_i <= 7'd0;
            lab16_ch3_snapshot_vol_r_i <= 7'd0;
            lab16_ch3_snapshot_delta_i <= 8'd0;
            lab16_ch3_snapshot_current_i <= 16'd0;
            lab16_ch3_snapshot_full_addr_i <= 21'd0;
            lab16_ch3_snapshot_bank_i <= 21'd0;
            lab16_ch3_snapshot_hit_i <= 1'b0;
            lab16_ch3_snapshot_block_i <= 3'd0;
            lab16_ch3_snapshot_dest_i <= 21'd0;
            lab16_ch3_snapshot_base_i <= 19'd0;
            lab16_ch3_snapshot_len_i <= 19'd0;
            lab16_ch3_snapshot_offset_i <= 19'd0;
            lab16_ch3_snapshot_reject_i <= 16'd0;
            lab16_loud_snap_valid_i <= 1'b0;
            lab16_loud_snap_abs_i <= 16'd0;
            lab16_loud_snap_ch_i <= 4'd0;
            lab16_loud_snap_block_i <= 3'd0;
            lab16_loud_snap_start_i <= 19'd0;
            lab16_loud_snap_pi_i <= 19'd0;
            lab16_loud_snap_sample_i <= 8'h80;
            lab16_loud_snap_cv_i <= 9'sd0;
            lab16_loud_snap_out_i <= 16'sd0;
            lab16_loud_snap_delta_reason_i <= 16'd0;
            lab16_loud_snap_volume_i <= 16'd0;
            lab16_loud_snap_reason_i <= 16'd0;
            lab16_expl_valid_i <= 1'b0;
            lab16_expl_count_i <= 16'd0;
            lab16_expl_abs_i <= 16'd0;
            lab16_expl_ch_i <= 4'd0;
            lab16_expl_block_i <= 3'd0;
            lab16_expl_current_i <= 16'd0;
            lab16_expl_end_i <= 16'd0;
            lab16_expl_delta_i <= 8'd0;
            lab16_expl_volume_i <= 16'd0;
            lab16_expl_base_i <= 16'd0;
            lab16_expl_first_index_i <= 16'd0;
            lab16_expl_index_i <= 16'd0;
            lab16_expl_raw_cv_i <= 16'd0;
            lab16_expl_l_i <= 16'sd0;
            lab16_expl_r_i <= 16'sd0;
            lab16_expl_mix_i <= 16'd0;
            lab16_expl_active_i <= 16'd0;
            lab16_expl_reason_i <= 16'hEC00;
            lab16_expl_e0_i <= 16'd0;
            lab16_expl_e1_i <= 16'd0;
            lab16_expl_e2_i <= 16'd0;
            lab16_expl_e3_i <= 16'd0;
            lab16_expl_first8_done_i <= 1'b0;
            lab16_ch3_live_count_i <= 16'd0;
            lab16_ch3_live_pi_i <= 16'd0;
            lab16_ch3_live_offset_i <= 16'd0;
            lab16_ch3_live_phase_i <= 16'd0;
            lab16_ch3_live_raw_cv_i <= 16'd0;
            lab16_ch3_live_l_i <= 16'sd0;
            lab16_ch3_live_reason_i <= 16'hC300;
            lab16_ch3_snap_abs_i <= 16'd0;
            lab16_ch3_snap_pi_i <= 16'd0;
            lab16_ch3_snap_offset_i <= 16'd0;
            lab16_ch3_snap_phase_i <= 16'd0;
            lab16_ch3_snap_raw_cv_i <= 16'd0;
            lab16_ch3_snap_l_i <= 16'sd0;
            lab16_ch3_snap_reason_i <= 16'hC300;
            lab16_ch3_snap_base_i <= 16'd0;
            lab16_ch3_snap_limit_i <= 16'd0;
            lab16_ch3_snap_block_i <= 16'hC300;
            lab16_ch3_write_count_i <= 16'd0;
            lab16_ch3_current_update_count_i <= 16'd0;
            lab16_ch3_end_delta_update_count_i <= 16'd0;
            lab16_ch3_end_update_count_i <= 16'd0;
            lab16_ch3_delta_update_count_i <= 16'd0;
            lab16_ch3_ctrl_update_count_i <= 16'd0;
            lab16_ch3_volume_update_count_i <= 16'd0;
            lab16_ch3_retrig_write_i <= 16'd0;
            lab16_ch3_active_start_count_i <= 16'd0;
            lab16_ch3_ignored_update_count_i <= 16'd0;
            lab16_ch3_clear_count_i <= 16'd0;
            lab16_ch3_last_retrigger_time_i <= 16'd0;
            lab16_ch3_last_write_time_i <= 16'd0;
            lab16_ch3_last_read_time_i <= 16'd0;
            lab16_ch3_last_clear_time_i <= 16'd0;
            lab16_ch3_last_expl_time_i <= 16'd0;
            lab16_ch3_retrig_valid_i <= 1'b0;
            lab16_ch3_retrig_count_i <= 16'd0;
            lab16_ch3_broad_restart_count_i <= 16'd0;
            lab16_ch3_qualified_start_count_i <= 16'd0;
            lab16_ch3_selected_reposition_count_i <= 16'd0;
            lab16_ch3_selected_active_current_count_i <= 16'd0;
            lab16_ch3_qual_duplicate_count_i <= 16'd0;
            lab16_ch3_qual_backward_count_i <= 16'd0;
            lab16_ch3_qual_forward_small_count_i <= 16'd0;
            lab16_ch3_qual_far_count_i <= 16'd0;
            lab16_ch3_qual_end_near_count_i <= 16'd0;
            lab16_ch3_qual_last_flags_i <= 16'd0;
            lab16_ch3_qual_last_old_current_i <= 16'd0;
            lab16_ch3_qual_last_new_current_i <= 16'd0;
            lab16_ch3_qual_last_old_pi_i <= 16'd0;
            lab16_ch3_qual_last_old_l_i <= 16'sd0;
            lab16_ch3_retrig_time_i <= 16'd0;
            lab16_ch3_retrig_flags_i <= 16'hF700;
            lab16_ch3_retrig_old_current_i <= 16'd0;
            lab16_ch3_retrig_old_pi_i <= 16'd0;
            lab16_ch3_retrig_old_offset_i <= 16'd0;
            lab16_ch3_retrig_old_phase_i <= 16'd0;
            lab16_ch3_retrig_old_l_i <= 16'sd0;
            lab16_ch3_retrig_new_current_i <= 16'd0;
            lab16_ch3_retrig_new_end_i <= 16'd0;
            lab16_ch3_retrig_new_delta_i <= 16'd0;
            lab16_ch3_retrig_new_pi_i <= 16'd0;
            lab16_ch3_retrig_new_offset_i <= 16'd0;
            lab16_ch3_retrig_base_i <= 16'd0;
            lab16_ch3_retrig_limit_i <= 16'd0;
            lab16_ch3_retrig_block_i <= 16'hC300;
            lab16_ch3_retrig_first0_i <= 16'd0;
            lab16_ch3_retrig_first1_i <= 16'd0;
            lab16_ch3_retrig_first2_i <= 16'd0;
            lab16_ch3_retrig_first3_i <= 16'd0;
            lab16_ch3_retrig_first_l_i <= 16'sd0;
            lab16_ch3_retrig_first_pi_i <= 16'd0;
            lab16_ch3_retrig_first_offset_i <= 16'd0;
            lab16_ch3_retrig_first_count_i <= 4'd0;
            lab16_ch3_worst_abs_i <= 16'd0;
            lab16_ch3_worst_pi_i <= 16'd0;
            lab16_ch3_worst_time_i <= 16'd0;
            lab16_ch3_worst_rc_i <= 16'd0;
            lab16_ch3_worst_offset_i <= 16'd0;
            lab16_ch3_worst_current_i <= 16'd0;
            lab16_ch3_worst_raw_cv_i <= 16'd0;
            lab16_ch3_worst_l_i <= 16'sd0;
            lab16_ch3_worst_reason_i <= 16'hC300;
            lab16_ch3_hold_mix_count_i <= 16'd0;
            lab16_ch3_fresh_read_count_i <= 16'd0;
            lab16_ch3_mix_contrib_count_i <= 16'd0;
            lab16_ch3_output_clear_count_i <= 16'd0;
            lab16_ch3_end_reached_count_i <= 16'd0;
            lab16_ch3_no_read_mix_count_i <= 16'd0;
            lab16_ch3_clear_end_count_i <= 16'd0;
            lab16_ch3_clear_disable_count_i <= 16'd0;
            lab16_ch3_clear_volume_count_i <= 16'd0;
            lab16_ch3_clear_map_count_i <= 16'd0;
            lab16_return_cv <= 9'sd0;
            lab16_return_product_l <= 17'sd0;
            lab16_return_product_r <= 17'sd0;
            lab16_return_scaled_l <= 17'sd0;
            lab16_return_scaled_r <= 17'sd0;
            lab16_return_delta_x4 <= 11'd0;
            lab16_return_phase_next <= 27'd0;
            lab16_return_read_valid <= 1'b0;
            lab16_return_next_valid <= 1'b0;
            lab16_return_output_valid <= 1'b0;
            lab16_return_stop_pi <= 19'd0;
            lab16_return_read_range_cross <= 1'b0;
            lab16_return_next_range_cross <= 1'b0;
            lab16_return_true_cross <= 1'b0;
            lab16_service_true_cross <= 1'b0;
            lab16_mix_l_i <= 24'sd0;
            lab16_mix_r_i <= 24'sd0;
            lab16_mix_l_sample_i <= 16'sd0;
            lab16_mix_r_sample_i <= 16'sd0;
            lab16_debug_ch_i <= 4'd3;
            for (lab16_loop_i = 0; lab16_loop_i < 16;
                 lab16_loop_i = lab16_loop_i + 1) begin
                lab16_ctrl_i[lab16_loop_i] <= 8'd0;
                lab16_cur_mid_i[lab16_loop_i] <= 8'd0;
                lab16_cur_high_i[lab16_loop_i] <= 8'd0;
                lab16_loop_mid_i[lab16_loop_i] <= 8'd0;
                lab16_loop_high_i[lab16_loop_i] <= 8'd0;
                lab16_end_i[lab16_loop_i] <= 8'd0;
                lab16_delta_i[lab16_loop_i] <= 8'd0;
                lab16_vol_l_i[lab16_loop_i] <= 7'd0;
                lab16_vol_r_i[lab16_loop_i] <= 7'd0;
                lab16_phase_i[lab16_loop_i] <= 27'd0;
                lab16_pi_i[lab16_loop_i] <= 19'd0;
                lab16_start_i[lab16_loop_i] <= 19'd0;
                lab16_base_i[lab16_loop_i] <= 19'd0;
                lab16_limit_i[lab16_loop_i] <= 19'd0;
                lab16_block_i[lab16_loop_i] <= 3'd0;
                lab16_map_valid_i[lab16_loop_i] <= 1'b0;
                lab16_sticky_block_i[lab16_loop_i] <= 3'd0;
                lab16_sample_i[lab16_loop_i] <= 8'h80;
                lab16_out_l_i[lab16_loop_i] <= 16'sd0;
                lab16_out_r_i[lab16_loop_i] <= 16'sd0;
                lab16_mix_fresh_i[lab16_loop_i] <= 1'b0;
                lab16_hold_sample_i[lab16_loop_i] <= 8'h80;
                lab16_hold_cv_i[lab16_loop_i] <= 9'sd0;
                lab16_start_current_i[lab16_loop_i] <= 16'd0;
                lab16_start_full_low_i[lab16_loop_i] <= 16'd0;
                lab16_start_end_low_i[lab16_loop_i] <= 16'd0;
                lab16_first8_01_i[lab16_loop_i] <= 16'd0;
                lab16_first8_23_i[lab16_loop_i] <= 16'd0;
                lab16_first8_45_i[lab16_loop_i] <= 16'd0;
                lab16_first8_67_i[lab16_loop_i] <= 16'd0;
                lab16_first8_count_i[lab16_loop_i] <= 4'd0;
            end
        end else begin
            lab_c0_consume_pulse_i <= 1'b0;
            lab_c0_req_live_i <= 1'b0;
            if (lab_c0_multich_delta_mode) begin
                lab_c0_state_i <= lab16_run_gate ?
                    LAB_C0_ST_CONSUME : LAB_C0_ST_IDLE;
                lab_c0_seed_i <= lab16_event_cur_high;
                lab_c0_cur_i <= {lab16_cur_high_i[lab16_view_ch],
                                 lab16_cur_mid_i[lab16_view_ch]};
                lab_c0_pi_i <= lab16_pi_i[lab16_view_ch];
                lab_c0_return_pi_i <= {15'd0, lab16_pending_ch_i};
                lab_c0_sample_i <= lab16_sample_i[lab16_view_ch];
                lab_c0_output_i <= lab16_selected_out_l;
                lab_c0_phase_i <= lab16_phase_i[lab16_view_ch];
                lab_c0_hit_count_i <= lab16_return_count_i;
                lab_c0_active_i <= lab16_run_gate &&
                    ((lab16_active_i != 16'd0) || lab16_retrigger_pulse);
                lab16_mix_l_i <= lab16_mix_l_next;
                lab16_mix_r_i <= lab16_mix_r_next;
                lab16_mix_l_sample_i <= lab16_mix_l_sample_next;
                lab16_mix_r_sample_i <= lab16_mix_r_sample_next;
                if (lab16_clip_next && (lab16_clip_count_i != 16'hffff)) begin
                    lab16_clip_count_i <= lab16_clip_count_i + 16'd1;
                end
                if (lab16_active_count > lab16_max_active_count_i) begin
                    lab16_max_active_count_i <= lab16_active_count;
                end
                if (lab16_mix_abs_l_next > lab16_mix_peak_i) begin
                    lab16_mix_peak_i <= lab16_mix_abs_l_next;
                end

	                if (!lab16_run_gate) begin
	                    if (lab16_active_i[3]) begin
	                        lab16_ch3_stop_reason_i <= 16'h8001;
	                        if (lab16_ch3_clear_count_i != 16'hffff) begin
	                                lab16_ch3_clear_count_i <=
	                                    lab16_ch3_clear_count_i + 16'd1;
	                        end
	                        lab16_ch3_last_clear_time_i <=
	                            lab16_return_count_i;
	                    end
                    lab_c0_pending_i <= 1'b0;
                    lab_c0_need_read_i <= 1'b0;
                    lab_c0_req_addr_i <= 19'd0;
                    lab16_emit_div_i <= 12'd0;
                        lab16_active_i <= 16'd0;
                        lab16_ch3_hit_len_i <= 16'd0;
                        for (lab16_loop_i = 0; lab16_loop_i < 16;
                             lab16_loop_i = lab16_loop_i + 1) begin
                            lab16_out_l_i[lab16_loop_i] <= 16'sd0;
                            lab16_out_r_i[lab16_loop_i] <= 16'sd0;
                            lab16_mix_fresh_i[lab16_loop_i] <= 1'b0;
                            lab16_hold_sample_i[lab16_loop_i] <= 8'h80;
                            lab16_hold_cv_i[lab16_loop_i] <= 9'sd0;
                            lab16_map_valid_i[lab16_loop_i] <= 1'b0;
                        end
                end else begin
                    if (segapcm_cen) begin
                        for (lab16_loop_i = 0; lab16_loop_i < 16;
                             lab16_loop_i = lab16_loop_i + 1) begin
                            lab16_mix_fresh_i[lab16_loop_i] <= 1'b0;
                        end
                        lab16_emit_div_i <= lab16_emit_div_i + 12'd1;
                        if (lab16_ch3_mix_ok_now &&
                            (lab16_out_l_i[3] != 16'sd0)) begin
                            if (lab16_ch3_hold_mix_count_i != 16'hffff) begin
                                lab16_ch3_hold_mix_count_i <=
                                    lab16_ch3_hold_mix_count_i + 16'd1;
                            end
                            if (lab16_ch3_mix_contrib_count_i !=
                                16'hffff) begin
                                lab16_ch3_mix_contrib_count_i <=
                                    lab16_ch3_mix_contrib_count_i + 16'd1;
                            end
                            if (lab16_ch3_no_fresh_for_mix) begin
                                if (lab16_ch3_no_read_mix_count_i !=
                                    16'hffff) begin
                                    lab16_ch3_no_read_mix_count_i <=
                                        lab16_ch3_no_read_mix_count_i +
                                        16'd1;
                                end
                            end
                        end
                    end
                    if (segapcm_cmd_valid) begin
                        if (lab16_write_low) begin
                            unique case (lab16_write_off)
                                3'd2: lab16_vol_l_i[lab16_write_ch] <=
                                    segapcm_cmd_data[6:0];
                                3'd3: lab16_vol_r_i[lab16_write_ch] <=
                                    segapcm_cmd_data[6:0];
                                3'd4: lab16_loop_mid_i[lab16_write_ch] <=
                                    segapcm_cmd_data;
                                3'd5: lab16_loop_high_i[lab16_write_ch] <=
                                    segapcm_cmd_data;
                                3'd6: lab16_end_i[lab16_write_ch] <=
                                    segapcm_cmd_data;
                                3'd7: lab16_delta_i[lab16_write_ch] <=
                                    segapcm_cmd_data;
                                default: begin end
                            endcase
                        end else begin
                            unique case (lab16_write_off)
                                3'd4: lab16_cur_mid_i[lab16_write_ch] <=
                                    segapcm_cmd_data;
                                3'd5: lab16_cur_high_i[lab16_write_ch] <=
                                    segapcm_cmd_data;
                                3'd6: lab16_ctrl_i[lab16_write_ch] <=
                                    segapcm_cmd_data;
                                default: begin end
	                            endcase
	                        end
	                        if (lab16_write_ch == 4'd3) begin
	                            if (lab16_ch3_write_count_i != 16'hffff) begin
	                                lab16_ch3_write_count_i <=
	                                    lab16_ch3_write_count_i + 16'd1;
	                            end
	                            lab16_ch3_last_write_time_i <=
	                                lab16_return_count_i;
	                            if (!lab16_write_low &&
	                                ((lab16_write_off == 3'd4) ||
	                                 (lab16_write_off == 3'd5))) begin
	                                if (lab16_ch3_current_update_count_i !=
	                                    16'hffff) begin
	                                    lab16_ch3_current_update_count_i <=
	                                        lab16_ch3_current_update_count_i +
	                                        16'd1;
	                                end
	                            end
	                            if (lab16_write_low &&
	                                ((lab16_write_off == 3'd6) ||
	                                 (lab16_write_off == 3'd7))) begin
	                                if (lab16_ch3_end_delta_update_count_i !=
	                                    16'hffff) begin
	                                    lab16_ch3_end_delta_update_count_i <=
	                                        lab16_ch3_end_delta_update_count_i +
	                                        16'd1;
	                                end
	                            end
	                            if (lab16_write_low &&
	                                (lab16_write_off == 3'd6)) begin
	                                if (lab16_ch3_end_update_count_i !=
	                                    16'hffff) begin
	                                    lab16_ch3_end_update_count_i <=
	                                        lab16_ch3_end_update_count_i +
	                                        16'd1;
	                                end
	                            end
	                            if (lab16_write_low &&
	                                (lab16_write_off == 3'd7)) begin
	                                if (lab16_ch3_delta_update_count_i !=
	                                    16'hffff) begin
	                                    lab16_ch3_delta_update_count_i <=
	                                        lab16_ch3_delta_update_count_i +
	                                        16'd1;
	                                end
	                            end
	                            if (!lab16_write_low &&
	                                (lab16_write_off == 3'd6)) begin
	                                if (lab16_ch3_ctrl_update_count_i !=
	                                    16'hffff) begin
	                                    lab16_ch3_ctrl_update_count_i <=
	                                        lab16_ch3_ctrl_update_count_i +
	                                        16'd1;
	                                end
	                            end
		                            if (lab16_write_low &&
		                                ((lab16_write_off == 3'd2) ||
		                                 (lab16_write_off == 3'd3))) begin
		                                if (lab16_ch3_volume_update_count_i !=
		                                    16'hffff) begin
		                                    lab16_ch3_volume_update_count_i <=
		                                        lab16_ch3_volume_update_count_i +
		                                        16'd1;
		                                end
		                            end
		                            if (lab16_event_strict_start_pulse &&
		                                (lab16_ch3_reseed_count_i !=
		                                 16'hffff)) begin
		                                lab16_ch3_reseed_count_i <=
		                                    lab16_ch3_reseed_count_i + 16'd1;
		                            end
		                            if (lab16_event_qualified_start_pulse &&
		                                (lab16_ch3_qualified_start_count_i !=
		                                 16'hffff)) begin
		                                lab16_ch3_qualified_start_count_i <=
		                                    lab16_ch3_qualified_start_count_i +
		                                    16'd1;
		                            end
		                            if (lab16_event_qualified_current_pulse) begin
		                                lab16_ch3_qual_last_flags_i <= {
		                                    8'hD0,
		                                    lab16_event_current_duplicate,
		                                    lab16_event_current_backward,
		                                    lab16_event_current_near,
		                                    lab16_event_current_far,
		                                    lab16_event_current_same_block,
		                                    lab16_event_current_block_change,
		                                    lab16_event_current_end_near,
		                                    lab16_event_current_active
		                                };
		                                lab16_ch3_qual_last_old_current_i <=
		                                    lab16_event_runtime_current;
		                                lab16_ch3_qual_last_new_current_i <=
		                                    lab16_event_current_word;
		                                lab16_ch3_qual_last_old_pi_i <=
		                                    lab16_pi_i[3][15:0];
		                                lab16_ch3_qual_last_old_l_i <=
		                                    lab16_out_l_i[3];
		                                if (lab16_event_current_duplicate &&
		                                    (lab16_ch3_qual_duplicate_count_i !=
		                                     16'hffff)) begin
		                                    lab16_ch3_qual_duplicate_count_i <=
		                                        lab16_ch3_qual_duplicate_count_i +
		                                        16'd1;
		                                end
		                                if (lab16_event_current_backward &&
		                                    (lab16_ch3_qual_backward_count_i !=
		                                     16'hffff)) begin
		                                    lab16_ch3_qual_backward_count_i <=
		                                        lab16_ch3_qual_backward_count_i +
		                                        16'd1;
		                                end
		                                if (!lab16_event_current_backward &&
		                                    lab16_event_current_near &&
		                                    (lab16_ch3_qual_forward_small_count_i !=
		                                     16'hffff)) begin
		                                    lab16_ch3_qual_forward_small_count_i <=
		                                        lab16_ch3_qual_forward_small_count_i +
		                                        16'd1;
		                                end
		                                if (lab16_event_current_far &&
		                                    (lab16_ch3_qual_far_count_i !=
		                                     16'hffff)) begin
		                                    lab16_ch3_qual_far_count_i <=
		                                        lab16_ch3_qual_far_count_i +
		                                        16'd1;
		                                end
		                                if (lab16_event_current_end_near &&
		                                    (lab16_ch3_qual_end_near_count_i !=
		                                     16'hffff)) begin
		                                    lab16_ch3_qual_end_near_count_i <=
		                                        lab16_ch3_qual_end_near_count_i +
		                                        16'd1;
		                                end
		                            end
		                            if (lab16_selected_policy_active_current_pulse &&
		                                (lab16_ch3_selected_active_current_count_i !=
		                                 16'hffff)) begin
		                                lab16_ch3_selected_active_current_count_i <=
		                                    lab16_ch3_selected_active_current_count_i +
		                                    16'd1;
		                            end
		                            if (!lab16_retrigger_pulse &&
		                                !lab16_reposition_pulse &&
		                                (lab16_ch3_ignored_update_count_i !=
		                                 16'hffff)) begin
	                                lab16_ch3_ignored_update_count_i <=
	                                    lab16_ch3_ignored_update_count_i +
	                                    16'd1;
	                            end
	                        end
	                    end

	                    if (lab16_event_candidate_pulse) begin
                        if ((lab16_write_ch == 4'd3) &&
                            lab16_event_map_valid &&
                            (lab16_ch3_broad_restart_count_i !=
                             16'hffff)) begin
                            lab16_ch3_broad_restart_count_i <=
                                lab16_ch3_broad_restart_count_i + 16'd1;
                        end
                        if (lab16_event_map_valid) begin
                            if (lab16_map_hit_count_i != 16'hffff) begin
                                lab16_map_hit_count_i <=
                                    lab16_map_hit_count_i + 16'd1;
                            end
                        end else if (lab16_map_miss_count_i != 16'hffff) begin
                            lab16_map_miss_count_i <=
                                lab16_map_miss_count_i + 16'd1;
                        end
                    end

                    if (lab16_ch3_raw_event_pulse) begin
                        if (lab16_ch3_raw_event_count_i != 16'hffff) begin
                            lab16_ch3_raw_event_count_i <=
                                lab16_ch3_raw_event_count_i + 16'd1;
                        end
                        lab16_ch3_full_addr_i <= lab16_event_full_addr;
                        lab16_ch3_reject_i <= {
                            lab16_ch3_known_coord_fail,
                            8'd0,
                            lab16_event_rom_hit && !lab16_event_map_valid,
                            smoke_type80_table_count_i == 4'd0,
                            !lab16_event_rom_hit,
                            lab16_event_ctrl[0],
                            !lab16_event_audible,
                            !lab16_event_retrigger_reg,
                            1'b0
                        };
                        if (lab16_event_rom_hit) begin
                            if (lab16_ch3_block_hit_count_i != 16'hffff) begin
                                lab16_ch3_block_hit_count_i <=
                                    lab16_ch3_block_hit_count_i + 16'd1;
                            end
                            lab16_ch3_block_i <= lab16_event_rom_block;
                            lab16_ch3_block_dest_i <=
                                smoke_type80_table_dest_i[lab16_event_rom_block];
                            lab16_ch3_block_base_i <= lab16_event_rom_base;
                            lab16_ch3_block_len_i <= lab16_event_rom_len;
                            lab16_ch3_block_offset_i <=
                                lab16_event_rom_offset;
                        end
                        if ((!lab16_ch3_snapshot_valid_i ||
                             (!lab16_ch3_snapshot_hit_i &&
                              lab16_event_rom_hit)) &&
                            lab16_ch3_snapshot_pulse) begin
                            lab16_ch3_snapshot_valid_i <= 1'b1;
                            lab16_ch3_snapshot_count_i <=
                                lab16_ch3_raw_event_count_i + 16'd1;
                            lab16_ch3_snapshot_ctrl_i <= lab16_event_ctrl;
                            lab16_ch3_snapshot_vol_l_i <= lab16_event_vol_l;
                            lab16_ch3_snapshot_vol_r_i <= lab16_event_vol_r;
                            lab16_ch3_snapshot_delta_i <=
                                (lab16_delta_i[3] != 8'd0) ?
                                lab16_delta_i[3] : 8'hA0;
                            lab16_ch3_snapshot_current_i <= {
                                lab16_event_cur_high,
                                lab16_event_cur_mid
                            };
                            lab16_ch3_snapshot_full_addr_i <=
                                lab16_event_full_addr;
                            lab16_ch3_snapshot_bank_i <= lab16_event_bank;
                            lab16_ch3_snapshot_hit_i <= lab16_event_rom_hit;
                            lab16_ch3_snapshot_block_i <= lab16_event_rom_block;
                            lab16_ch3_snapshot_base_i <= lab16_event_rom_base;
                            lab16_ch3_snapshot_len_i <= lab16_event_rom_len;
                            lab16_ch3_snapshot_offset_i <=
                            lab16_event_rom_offset;
                            lab16_ch3_snapshot_reject_i <= {
                                lab16_ch3_known_coord_fail,
                                8'd0,
                                lab16_event_rom_hit && !lab16_event_map_valid,
                                smoke_type80_table_count_i == 4'd0,
                                !lab16_event_rom_hit,
                                lab16_event_ctrl[0],
                                !lab16_event_audible,
                                !lab16_event_retrigger_reg,
                                1'b0
                            };
                            if (lab16_event_rom_hit) begin
                                lab16_ch3_snapshot_dest_i <=
                                    smoke_type80_table_dest_i[
                                        lab16_event_rom_block
                                    ];
                            end else begin
                                lab16_ch3_snapshot_dest_i <= 21'd0;
                            end
                        end
                    end

	                    if (lab16_retrigger_pulse) begin
	                        lab16_debug_ch_i <= lab16_write_ch;
	                        if (lab16_event_strict_start_pulse) begin
	                            lab16_strict_seen_i[lab16_write_ch] <= 1'b1;
	                        end
	                        lab16_active_i[lab16_write_ch] <= 1'b1;
                        lab16_phase_i[lab16_write_ch] <=
                            {lab16_event_local_pi, 8'd0};
                        lab16_pi_i[lab16_write_ch] <= lab16_event_local_pi;
                        lab16_start_i[lab16_write_ch] <= lab16_event_local_pi;
                        lab16_base_i[lab16_write_ch] <= lab16_event_map_base;
                        lab16_limit_i[lab16_write_ch] <= lab16_event_map_limit;
                        lab16_block_i[lab16_write_ch] <= lab16_event_map_block;
                        lab16_map_valid_i[lab16_write_ch] <= 1'b1;
                        lab16_sticky_block_i[lab16_write_ch] <=
                            lab16_event_map_block;
                        lab16_sticky_map_i[lab16_write_ch] <= 1'b1;
                        lab16_sample_i[lab16_write_ch] <= 8'h80;
                        lab16_out_l_i[lab16_write_ch] <= 16'sd0;
                        lab16_out_r_i[lab16_write_ch] <= 16'sd0;
                        lab16_mix_fresh_i[lab16_write_ch] <= 1'b0;
                        lab16_hold_sample_i[lab16_write_ch] <= 8'h80;
                        lab16_hold_cv_i[lab16_write_ch] <= 9'sd0;
                        lab16_start_current_i[lab16_write_ch] <=
                            lab16_event_current_word;
                        lab16_start_full_low_i[lab16_write_ch] <=
                            lab16_event_full_low;
                        lab16_start_end_low_i[lab16_write_ch] <=
                            lab16_event_end_full_addr[15:0];
                        lab16_first8_01_i[lab16_write_ch] <= 16'd0;
                        lab16_first8_23_i[lab16_write_ch] <= 16'd0;
                        lab16_first8_45_i[lab16_write_ch] <= 16'd0;
                        lab16_first8_67_i[lab16_write_ch] <= 16'd0;
                        lab16_first8_count_i[lab16_write_ch] <= 4'd0;
                        lab16_ever_active_i[lab16_write_ch] <= 1'b1;
                        if (lab16_retrigger_masked_pulse) begin
                            if (!lab16_start_tuple_valid_i) begin
                                lab16_target_current_i <=
                                    lab16_event_current_word;
                                lab16_target_full_low_i <=
                                    lab16_event_full_low;
                                lab16_target_match_bits_i <=
                                    lab16_target_match_bits;
                            end
                            if (lab16_start_tuple_count_i != 16'hffff) begin
                                lab16_start_tuple_count_i <=
                                    lab16_start_tuple_count_i + 16'd1;
                            end
                            if (lab16_retrigger_target_pulse) begin
                                if (lab16_target_start_count_i != 16'hffff) begin
                                    lab16_target_start_count_i <=
                                        lab16_target_start_count_i + 16'd1;
                                end
                            end else if (!lab16_start_tuple_valid_i) begin
                                if (lab16_skipped_start_count_i != 16'hffff) begin
                                    lab16_skipped_start_count_i <=
                                        lab16_skipped_start_count_i + 16'd1;
                                end
                            end
                            if (lab16_retrigger_target_pulse &&
                                !lab16_start_tuple_valid_i) begin
                                lab16_start_tuple_ch_i <= lab16_write_ch;
                                lab16_start_tuple_block_i <= lab16_event_map_block;
                                lab16_start_tuple_current_i <=
                                    lab16_event_current_word;
                                lab16_start_tuple_bank_i <= lab16_event_bank;
                                lab16_start_tuple_full_addr_i <= lab16_event_full_addr;
                                lab16_start_tuple_delta_i <=
                                    lab16_event_delta_effective;
                                lab16_start_tuple_vol_l_i <= lab16_event_vol_l;
                                lab16_start_tuple_vol_r_i <= lab16_event_vol_r;
                                lab16_start_tuple_end_addr_i <=
                                    lab16_event_end_full_addr;
                                lab16_start_tuple_limit_i <=
                                    lab16_event_map_limit;
                                lab16_start_tuple_end_limited_i <=
                                    lab16_event_end_limit_used;
                                lab16_start_tuple_valid_i <= 1'b1;
                                lab16_first_samples_valid_i <= 1'b0;
                                lab16_first_capture_armed_i <= 1'b1;
                                lab16_first_capture_has_any_i <= 1'b0;
                                lab16_first_capture_reader_match_i <= 1'b0;
                                lab16_runtime_active_seen_i <= 1'b0;
                                lab16_runtime_consume_count_i <= 16'd0;
                                lab16_runtime_pr_hold_i <= 16'hE600;
                                lab16_start_tuple_source_i <= {
                                    5'd0,
                                    smoke_c0_pm3_audio_mask[lab16_write_ch],
                                    smoke_c0_format_sel[0],
                                    lab16_event_map_valid,
                                    lab16_retrigger_pulse,
                                    lab16_write_high &&
                                        ((lab16_write_off == 3'd4) ||
                                         (lab16_write_off == 3'd5)),
                                    (lab16_write_high &&
                                     (lab16_write_off == 3'd6)) ||
                                        (lab16_write_low &&
                                         ((lab16_write_off == 3'd2) ||
                                          (lab16_write_off == 3'd3))),
                                    lab_c0_legacy_ch3_block2_mode,
                                    lab_c0_multich_delta_mode,
                                    1'b0,
                                    1'b1
                                };
                                lab16_runtime_status_i <= 16'hE600;
                                lab16_runtime_offset_i <=
                                    lab16_event_local_pi - lab16_event_map_base;
                                lab16_runtime_addr_i <= lab16_event_full_low;
                                lab16_runtime_pi_i <= lab16_event_local_pi;
                                lab16_runtime_phase_hint_i <=
                                    lab16_event_local_pi[15:0];
                                lab16_runtime_rd_i <= 16'h8000;
                                lab16_runtime_l_i <= 16'sd0;
                                lab16_runtime_r_i <= 16'sd0;
                                lab16_runtime_stop_i <= 16'hE510;
                                lab16_last_stop_pi_i <= 19'd0;
                                lab16_stop_valid_i <= 1'b0;
                                lab16_stop_count_i <= 16'd0;
                                lab16_stop_offset_i <= 16'd0;
                                lab16_stop_pi_i <= 16'd0;
                                lab16_stop_full_i <= 16'd0;
                                lab16_stop_phase_i <= 16'd0;
                                lab16_stop_flags_i <= 16'hEA00;
                                lab16_end_debug_flags_i <= {
                                    8'hE9,
                                    1'b0,
                                    lab16_event_end_limit_used,
                                    lab16_event_end_limit_valid,
                                    lab16_event_end != 8'd0,
                                    lab16_event_end_full_addr >
                                        lab16_event_full_addr,
                                    lab16_event_map_valid,
                                    lab16_event_rom_hit,
                                    lab16_event_map_limit !=
                                        lab16_event_map_limit_20[18:0]
                                };
                                lab16_first_s0_addr_i <= 16'd0;
                                lab16_first_s0_index_i <= 16'd0;
                                lab16_first_s0_phase_i <= 16'd0;
                                lab16_first_s0_capture_count_i <= 16'd0;
                                lab16_first_sample_count_i <= 5'd0;
                                lab16_first_raw01_i <= 16'd0;
                                lab16_first_raw23_i <= 16'd0;
                                lab16_first_raw45_i <= 16'd0;
                                lab16_first_raw67_i <= 16'd0;
                                lab16_first_raw89_i <= 16'd0;
                                lab16_first_rawab_i <= 16'd0;
                                lab16_first_rawcd_i <= 16'd0;
                                lab16_first_rawef_i <= 16'd0;
                                lab16_first_dec01_i <= 16'd0;
                                lab16_first_dec23_i <= 16'd0;
                                lab16_first_dec45_i <= 16'd0;
                                lab16_first_dec67_i <= 16'd0;
                                lab16_first_dec89_i <= 16'd0;
                                lab16_first_decab_i <= 16'd0;
                                lab16_first_deccd_i <= 16'd0;
                                lab16_first_decef_i <= 16'd0;
                                lab16_wave_rawcv0_i <= 16'd0;
                                lab16_wave_addr0_i <= 16'd0;
                                lab16_wave_pi0_i <= 16'd0;
                                lab16_wave_out0_i <= 16'd0;
                                lab16_wave_rawcv1_i <= 16'd0;
                                lab16_wave_addr1_i <= 16'd0;
                                lab16_wave_pi1_i <= 16'd0;
                                lab16_wave_out1_i <= 16'd0;
                                lab16_wave_rawcv2_i <= 16'd0;
                                lab16_wave_addr2_i <= 16'd0;
                                lab16_wave_pi2_i <= 16'd0;
                                lab16_wave_out2_i <= 16'd0;
                                lab16_wave_rawcv3_i <= 16'd0;
                                lab16_wave_addr3_i <= 16'd0;
                                lab16_wave_pi3_i <= 16'd0;
                                lab16_wave_out3_i <= 16'd0;
                                lab16_wave_vol_i <= {
                                    1'b0, lab16_event_vol_l[6:0],
                                    1'b0, lab16_event_vol_r[6:0]
                                };
                            end else if (lab16_retrigger_target_pulse) begin
                                lab16_first_capture_overwrite_i <= 1'b1;
                            end
                        end
                        if (lab16_retrigger_count_i != 16'hffff) begin
                            lab16_retrigger_count_i <=
                                lab16_retrigger_count_i + 16'd1;
                        end
                        if (lab16_reseed_count_i != 16'hffff) begin
                            lab16_reseed_count_i <= lab16_reseed_count_i + 16'd1;
                        end
                        lab_c0_event_time_i <= lab16_return_count_i;
                        lab_c0_event_seed_i <= {
                            lab16_event_cur_high,
                            lab16_event_cur_mid
                        };
	                        lab_c0_reseed_pi_i <= lab16_event_local_pi;
	                        if (lab16_write_ch == 4'd3) begin
		                            lab16_ch3_last_retrigger_time_i <=
		                                lab16_return_count_i;
	                            lab16_ch3_retrig_valid_i <= 1'b1;
	                            if (lab16_ch3_retrig_count_i != 16'hffff) begin
	                                lab16_ch3_retrig_count_i <=
	                                    lab16_ch3_retrig_count_i + 16'd1;
	                            end
	                            if (lab16_active_i[3] &&
	                                (lab16_ch3_active_start_count_i !=
	                                 16'hffff)) begin
	                                lab16_ch3_active_start_count_i <=
	                                    lab16_ch3_active_start_count_i + 16'd1;
	                            end
	                            lab16_ch3_retrig_time_i <=
	                                lab16_return_count_i;
	                            lab16_ch3_retrig_write_i <= {
	                                mapped_cpu_addr,
	                                segapcm_cmd_data
	                            };
	                            lab16_ch3_retrig_flags_i <= {
	                                4'hF,
	                                lab16_active_i[3],
	                                lab16_strict_seen_i[3],
	                                lab16_event_first_valid_start,
	                                lab16_event_ctrl_enable,
	                                lab16_event_volume_on,
	                                lab16_event_map_valid,
	                                lab16_event_map_block == 3'd2,
	                                lab16_event_current_word == 16'h7100,
	                                lab16_event_delta_effective == 8'hA0,
	                                lab16_write_high &&
	                                    ((lab16_write_off == 3'd4) ||
	                                     (lab16_write_off == 3'd5)),
	                                lab16_write_high &&
	                                    (lab16_write_off == 3'd6),
	                                lab16_write_low &&
	                                    ((lab16_write_off == 3'd2) ||
	                                     (lab16_write_off == 3'd3))
	                            };
	                            lab16_ch3_retrig_old_offset_i <=
	                                lab16_pi_i[3][15:0] -
	                                lab16_base_i[3][15:0];
	                            lab16_ch3_retrig_old_current_i <=
	                                lab16_start_current_i[3] +
	                                (lab16_pi_i[3][15:0] -
	                                 lab16_base_i[3][15:0]);
	                            lab16_ch3_retrig_old_pi_i <=
	                                lab16_pi_i[3][15:0];
	                            lab16_ch3_retrig_old_phase_i <=
	                                lab16_phase_i[3][23:8];
	                            lab16_ch3_retrig_old_l_i <=
	                                lab16_out_l_i[3];
	                            lab16_ch3_retrig_new_current_i <=
	                                lab16_event_current_word;
	                            lab16_ch3_retrig_new_end_i <=
	                                lab16_event_end_full_addr[15:0];
	                            lab16_ch3_retrig_new_delta_i <=
	                                {8'd0, lab16_event_delta_effective};
	                            lab16_ch3_retrig_new_pi_i <=
	                                lab16_event_local_pi[15:0];
	                            lab16_ch3_retrig_new_offset_i <=
	                                lab16_event_local_pi[15:0] -
	                                lab16_event_map_base[15:0];
	                            lab16_ch3_retrig_base_i <=
	                                lab16_event_map_base[15:0];
	                            lab16_ch3_retrig_limit_i <=
	                                lab16_event_map_limit[15:0];
	                            lab16_ch3_retrig_block_i <= {
	                                8'hC3,
	                                lab16_active_i[3],
	                                lab16_map_valid_i[3],
	                                smoke_c0_pm3_audio_mask[3],
	                                lab16_event_map_valid,
	                                lab16_event_map_block,
	                                lab16_event_end_limit_used
	                            };
	                            lab16_ch3_retrig_first0_i <= 16'd0;
	                            lab16_ch3_retrig_first1_i <= 16'd0;
	                            lab16_ch3_retrig_first2_i <= 16'd0;
	                            lab16_ch3_retrig_first3_i <= 16'd0;
	                            lab16_ch3_retrig_first_l_i <= 16'sd0;
	                            lab16_ch3_retrig_first_pi_i <= 16'd0;
	                            lab16_ch3_retrig_first_offset_i <= 16'd0;
	                            lab16_ch3_retrig_first_count_i <= 4'd0;
	                            lab16_ch3_stop_reason_i <= 16'd0;
	                            lab16_ch3_map_valid_i <= lab16_event_map_valid;
	                            lab16_ch3_sticky_i[0] <= 1'b1;
                            lab16_ch3_hit_len_i <= 16'd0;
                            if ((lab16_return_count_i < 16'h0800) &&
                                (lab16_ch3_intro_reseed_count_i != 16'hffff)) begin
                                lab16_ch3_intro_reseed_count_i <=
                                    lab16_ch3_intro_reseed_count_i + 16'd1;
	                            end
	                        end
	                    end

	                    if (lab16_reposition_pulse) begin
	                        lab16_debug_ch_i <= lab16_write_ch;
	                        lab16_active_i[lab16_write_ch] <= 1'b1;
	                        lab16_phase_i[lab16_write_ch] <=
	                            {lab16_event_local_pi, 8'd0};
	                        lab16_pi_i[lab16_write_ch] <= lab16_event_local_pi;
	                        lab16_start_i[lab16_write_ch] <= lab16_event_local_pi;
	                        lab16_base_i[lab16_write_ch] <= lab16_event_map_base;
	                        lab16_limit_i[lab16_write_ch] <= lab16_event_map_limit;
	                        lab16_block_i[lab16_write_ch] <= lab16_event_map_block;
	                        lab16_map_valid_i[lab16_write_ch] <= 1'b1;
	                        lab16_sticky_block_i[lab16_write_ch] <=
	                            lab16_event_map_block;
	                        lab16_sticky_map_i[lab16_write_ch] <= 1'b1;
	                        lab16_start_current_i[lab16_write_ch] <=
	                            lab16_event_current_word;
	                        lab16_start_full_low_i[lab16_write_ch] <=
	                            lab16_event_full_low;
	                        lab16_start_end_low_i[lab16_write_ch] <=
	                            lab16_event_end_full_addr[15:0];
	                        lab16_ever_active_i[lab16_write_ch] <= 1'b1;
	                        lab_c0_event_time_i <= lab16_return_count_i;
	                        lab_c0_event_seed_i <= {
	                            lab16_event_cur_high,
	                            lab16_event_cur_mid
	                        };
	                        lab_c0_reseed_pi_i <= lab16_event_local_pi;
	                        if (lab16_write_ch == 4'd3) begin
	                            if (lab16_ch3_selected_reposition_count_i !=
	                                16'hffff) begin
	                                lab16_ch3_selected_reposition_count_i <=
	                                    lab16_ch3_selected_reposition_count_i +
	                                    16'd1;
	                            end
	                            lab16_ch3_last_retrigger_time_i <=
	                                lab16_return_count_i;
	                            lab16_ch3_retrig_valid_i <= 1'b1;
	                            lab16_ch3_retrig_time_i <=
	                                lab16_return_count_i;
	                            lab16_ch3_retrig_write_i <= {
	                                mapped_cpu_addr,
	                                segapcm_cmd_data
	                            };
	                            lab16_ch3_retrig_flags_i <= {
	                                4'hE,
	                                lab16_active_i[3],
	                                lab16_strict_seen_i[3],
	                                lab16_event_first_valid_start,
	                                lab16_event_ctrl_enable,
	                                lab16_event_volume_on,
	                                lab16_event_map_valid,
	                                lab16_event_map_block == 3'd2,
	                                lab16_event_current_word == 16'h7100,
	                                lab16_event_delta_effective == 8'hA0,
	                                lab16_event_current_commit,
	                                lab16_write_high &&
	                                    (lab16_write_off == 3'd6),
	                                lab16_write_low &&
	                                    ((lab16_write_off == 3'd2) ||
	                                     (lab16_write_off == 3'd3))
	                            };
	                            lab16_ch3_retrig_old_offset_i <=
	                                lab16_pi_i[3][15:0] -
	                                lab16_base_i[3][15:0];
	                            lab16_ch3_retrig_old_current_i <=
	                                lab16_start_current_i[3] +
	                                (lab16_pi_i[3][15:0] -
	                                 lab16_base_i[3][15:0]);
	                            lab16_ch3_retrig_old_pi_i <=
	                                lab16_pi_i[3][15:0];
	                            lab16_ch3_retrig_old_phase_i <=
	                                lab16_phase_i[3][23:8];
	                            lab16_ch3_retrig_old_l_i <=
	                                lab16_out_l_i[3];
	                            lab16_ch3_retrig_new_current_i <=
	                                lab16_event_current_word;
	                            lab16_ch3_retrig_new_end_i <=
	                                lab16_event_end_full_addr[15:0];
	                            lab16_ch3_retrig_new_delta_i <=
	                                {8'd0, lab16_event_delta_effective};
	                            lab16_ch3_retrig_new_pi_i <=
	                                lab16_event_local_pi[15:0];
	                            lab16_ch3_retrig_new_offset_i <=
	                                lab16_event_local_pi[15:0] -
	                                lab16_event_map_base[15:0];
	                            lab16_ch3_retrig_base_i <=
	                                lab16_event_map_base[15:0];
	                            lab16_ch3_retrig_limit_i <=
	                                lab16_event_map_limit[15:0];
	                            lab16_ch3_retrig_block_i <= {
	                                8'hC3,
	                                lab16_active_i[3],
	                                lab16_map_valid_i[3],
	                                smoke_c0_pm3_audio_mask[3],
	                                lab16_event_map_valid,
	                                lab16_event_map_block,
	                                lab16_event_end_limit_used
	                            };
	                        end
	                    end

	                    if (lab_c0_return_pulse) begin
                        lab16_debug_ch_i <= lab16_pending_ch_i;
                        lab_c0_pending_i <= 1'b0;
                        lab_c0_need_read_i <= 1'b0;
                        lab16_return_cv = smoke_c0_format_sel[0] ?
                            (9'sd128 -
                             $signed({1'b0, loaded_ddr_rd_data})) :
                            ($signed({1'b0, loaded_ddr_rd_data}) - 9'sd128);
                        lab16_return_product_l =
                            lab16_return_cv *
                            $signed({2'b00, lab16_vol_l_i[lab16_pending_ch_i]});
                        lab16_return_product_r =
                            lab16_return_cv *
                            $signed({2'b00, lab16_vol_r_i[lab16_pending_ch_i]});
                        unique case (LAB16_PM3_OUTPUT_SHIFT_SEL)
                            2'd1: begin
                                lab16_return_scaled_l =
                                    lab16_return_product_l >>> 1;
                                lab16_return_scaled_r =
                                    lab16_return_product_r >>> 1;
                            end
                            2'd2: begin
                                lab16_return_scaled_l =
                                    lab16_return_product_l >>> 2;
                                lab16_return_scaled_r =
                                    lab16_return_product_r >>> 2;
                            end
                            2'd3: begin
                                lab16_return_scaled_l =
                                    lab16_return_product_l >>> 3;
                                lab16_return_scaled_r =
                                    lab16_return_product_r >>> 3;
                            end
                            default: begin
                                lab16_return_scaled_l =
                                    lab16_return_product_l;
                                lab16_return_scaled_r =
                                    lab16_return_product_r;
                            end
                        endcase
                        lab16_return_delta_x4 =
                            {3'd0,
                             (lab16_delta_i[lab16_pending_ch_i] != 8'd0) ?
                             lab16_delta_i[lab16_pending_ch_i] : 8'hA0} << 2;
                        lab16_return_phase_next =
                            lab16_phase_i[lab16_pending_ch_i] +
                            {16'd0, lab16_return_delta_x4};
                        lab16_return_read_valid =
                            lab16_map_valid_i[lab16_pending_ch_i] &&
                            (lab16_pi_i[lab16_pending_ch_i] >=
                             lab16_base_i[lab16_pending_ch_i]) &&
                            (lab16_pi_i[lab16_pending_ch_i] <
                             lab16_limit_i[lab16_pending_ch_i]) &&
                            !(lab16_vol_l_i[lab16_pending_ch_i] == 7'd0 &&
                              lab16_vol_r_i[lab16_pending_ch_i] == 7'd0) &&
                            !lab16_ctrl_i[lab16_pending_ch_i][0];
                        lab16_return_next_valid =
                            lab16_map_valid_i[lab16_pending_ch_i] &&
                            (lab16_return_phase_next[26:8] >=
                             lab16_base_i[lab16_pending_ch_i]) &&
                            (lab16_return_phase_next[26:8] <
                             lab16_limit_i[lab16_pending_ch_i]) &&
                            !(lab16_vol_l_i[lab16_pending_ch_i] == 7'd0 &&
                              lab16_vol_r_i[lab16_pending_ch_i] == 7'd0) &&
                            !lab16_ctrl_i[lab16_pending_ch_i][0];
                        lab16_return_output_valid =
                            lab16_return_read_valid &&
                            lab16_return_next_valid;
                        lab16_return_stop_pi =
                            lab16_return_read_valid ?
                            lab16_return_phase_next[26:8] :
                            lab16_pi_i[lab16_pending_ch_i];
                        lab16_return_read_range_cross =
                            lab16_map_valid_i[lab16_pending_ch_i] &&
                            ((lab16_pi_i[lab16_pending_ch_i] <
                              lab16_base_i[lab16_pending_ch_i]) ||
                             (lab16_pi_i[lab16_pending_ch_i] >=
                              lab16_limit_i[lab16_pending_ch_i]));
                        lab16_return_next_range_cross =
                            lab16_map_valid_i[lab16_pending_ch_i] &&
                            ((lab16_return_phase_next[26:8] <
                              lab16_base_i[lab16_pending_ch_i]) ||
                             (lab16_return_phase_next[26:8] >=
                              lab16_limit_i[lab16_pending_ch_i]));
                        lab16_return_true_cross =
                            lab16_return_read_range_cross ||
                            lab16_return_next_range_cross;
                        if ((lab16_pending_ch_i == 4'd3) &&
                            smoke_c0_pm3_audio_mask[3]) begin
                            if (lab16_ch3_live_count_i != 16'hffff) begin
                                lab16_ch3_live_count_i <=
                                    lab16_ch3_live_count_i + 16'd1;
                            end
                            if (lab16_ch3_fresh_read_count_i !=
                                16'hffff) begin
                                lab16_ch3_fresh_read_count_i <=
                                    lab16_ch3_fresh_read_count_i + 16'd1;
                            end
	                            lab16_ch3_live_pi_i <=
	                                lab16_pi_i[lab16_pending_ch_i][15:0];
	                            lab16_ch3_last_read_time_i <=
	                                lab16_return_count_i;
	                            lab16_ch3_live_offset_i <=
                                lab16_runtime_offset_next;
                            lab16_ch3_live_phase_i <=
                                lab16_phase_i[lab16_pending_ch_i][23:8];
                            lab16_ch3_live_raw_cv_i <= {
                                loaded_ddr_rd_data,
                                lab16_return_cv[7:0]
                            };
                            lab16_ch3_live_l_i <=
                                lab16_return_scaled_l[15:0];
		                            lab16_ch3_live_reason_i <= {
		                                4'hC,
		                                lab16_return_true_cross,
	                                lab16_return_next_range_cross,
	                                lab16_return_read_range_cross,
                                lab16_return_read_valid,
                                lab16_return_output_valid,
                                lab16_active_i[3],
                                lab16_map_valid_i[3],
                                smoke_c0_pm3_audio_mask[3],
                                lab16_pi_i[3] < lab16_base_i[3],
                                lab16_pi_i[3] >= lab16_limit_i[3],
                                lab16_ctrl_i[3][0],
		                                lab16_vol_l_i[3] == 7'd0 &&
		                                    lab16_vol_r_i[3] == 7'd0
		                            };
                            if (!lab16_return_output_valid &&
                                (lab16_ch3_output_clear_count_i !=
                                 16'hffff)) begin
                                lab16_ch3_output_clear_count_i <=
                                    lab16_ch3_output_clear_count_i + 16'd1;
                            end
                            if (!lab16_return_output_valid) begin
                                if (lab16_return_true_cross &&
                                    (lab16_ch3_clear_end_count_i !=
                                     16'hffff)) begin
                                    lab16_ch3_clear_end_count_i <=
                                        lab16_ch3_clear_end_count_i + 16'd1;
                                end
                                if (lab16_ctrl_i[3][0] &&
                                    (lab16_ch3_clear_disable_count_i !=
                                     16'hffff)) begin
                                    lab16_ch3_clear_disable_count_i <=
                                        lab16_ch3_clear_disable_count_i +
                                        16'd1;
                                end
                                if ((lab16_vol_l_i[3] == 7'd0 &&
                                     lab16_vol_r_i[3] == 7'd0) &&
                                    (lab16_ch3_clear_volume_count_i !=
                                     16'hffff)) begin
                                    lab16_ch3_clear_volume_count_i <=
                                        lab16_ch3_clear_volume_count_i +
                                        16'd1;
                                end
                                if (!lab16_map_valid_i[3] &&
                                    (lab16_ch3_clear_map_count_i !=
                                     16'hffff)) begin
                                    lab16_ch3_clear_map_count_i <=
                                        lab16_ch3_clear_map_count_i + 16'd1;
                                end
                            end
                            if (lab16_return_true_cross &&
                                (lab16_ch3_end_reached_count_i !=
                                 16'hffff)) begin
                                lab16_ch3_end_reached_count_i <=
                                    lab16_ch3_end_reached_count_i + 16'd1;
                            end
	                            if (lab16_ch3_retrig_valid_i &&
	                                (lab16_ch3_retrig_first_count_i < 4'd4)) begin
	                                unique case (lab16_ch3_retrig_first_count_i)
	                                    4'd0: lab16_ch3_retrig_first0_i <= {
	                                        loaded_ddr_rd_data,
	                                        lab16_return_cv[7:0]
	                                    };
	                                    4'd1: lab16_ch3_retrig_first1_i <= {
	                                        loaded_ddr_rd_data,
	                                        lab16_return_cv[7:0]
	                                    };
	                                    4'd2: lab16_ch3_retrig_first2_i <= {
	                                        loaded_ddr_rd_data,
	                                        lab16_return_cv[7:0]
	                                    };
	                                    default: lab16_ch3_retrig_first3_i <= {
	                                        loaded_ddr_rd_data,
	                                        lab16_return_cv[7:0]
	                                    };
	                                endcase
	                                if (lab16_ch3_retrig_first_count_i == 4'd0) begin
	                                    lab16_ch3_retrig_first_l_i <=
	                                        lab16_return_scaled_l[15:0];
	                                    lab16_ch3_retrig_first_pi_i <=
	                                        lab16_pi_i[lab16_pending_ch_i][15:0];
	                                    lab16_ch3_retrig_first_offset_i <=
	                                        lab16_runtime_offset_next;
	                                end
	                                lab16_ch3_retrig_first_count_i <=
	                                    lab16_ch3_retrig_first_count_i + 4'd1;
	                            end
	                            if (lab16_return_read_valid &&
	                                ((lab16_return_abs_max >
	                                  lab16_ch3_snap_abs_i) ||
	                                 lab16_return_true_cross ||
	                                 !lab16_return_output_valid ||
	                                 (lab16_ch3_snap_abs_i == 16'd0))) begin
	                                lab16_ch3_snap_abs_i <=
	                                    lab16_return_abs_max;
	                                lab16_ch3_snap_pi_i <=
	                                    lab16_pi_i[lab16_pending_ch_i][15:0];
	                                lab16_ch3_snap_offset_i <=
	                                    lab16_runtime_offset_next;
	                                lab16_ch3_snap_phase_i <=
	                                    lab16_phase_i[
	                                        lab16_pending_ch_i][23:8];
	                                lab16_ch3_snap_raw_cv_i <= {
	                                    loaded_ddr_rd_data,
	                                    lab16_return_cv[7:0]
	                                };
	                                lab16_ch3_snap_l_i <=
	                                    lab16_return_scaled_l[15:0];
	                                lab16_ch3_snap_reason_i <= {
	                                    4'hC,
	                                    lab16_return_true_cross,
	                                    lab16_return_next_range_cross,
	                                    lab16_return_read_range_cross,
	                                    lab16_return_read_valid,
	                                    lab16_return_output_valid,
	                                    lab16_active_i[3],
	                                    lab16_map_valid_i[3],
	                                    smoke_c0_pm3_audio_mask[3],
	                                    lab16_pi_i[3] < lab16_base_i[3],
	                                    lab16_pi_i[3] >= lab16_limit_i[3],
	                                    lab16_ctrl_i[3][0],
	                                    lab16_vol_l_i[3] == 7'd0 &&
	                                        lab16_vol_r_i[3] == 7'd0
	                                };
	                                lab16_ch3_snap_base_i <=
	                                    lab16_base_i[3][15:0];
	                                lab16_ch3_snap_limit_i <=
	                                    lab16_limit_i[3][15:0];
	                                lab16_ch3_snap_block_i <= {
	                                    8'hC3,
	                                    lab16_active_i[3],
	                                    lab16_map_valid_i[3],
	                                    smoke_c0_pm3_audio_mask[3],
	                                    1'b0,
	                                    lab16_block_i[3],
	                                    1'b0
	                                };
	                            end
	                            if (lab16_return_abs_max > lab16_ch3_worst_abs_i) begin
                                lab16_ch3_worst_abs_i <= lab16_return_abs_max;
                                lab16_ch3_worst_pi_i <=
                                    lab16_pi_i[lab16_pending_ch_i][15:0];
                                lab16_ch3_worst_time_i <=
                                    lab16_return_count_i;
                                lab16_ch3_worst_rc_i <=
                                    lab16_ch3_retrig_count_i;
                                lab16_ch3_worst_offset_i <=
                                    lab16_runtime_offset_next;
                                lab16_ch3_worst_current_i <=
                                    lab16_start_current_i[3] +
                                    lab16_runtime_offset_next;
                                lab16_ch3_worst_raw_cv_i <= {
                                    loaded_ddr_rd_data,
                                    lab16_return_cv[7:0]
                                };
                                lab16_ch3_worst_l_i <=
                                    lab16_return_scaled_l[15:0];
                                lab16_ch3_worst_reason_i <= {
                                    4'hC,
                                    lab16_return_true_cross,
                                    lab16_return_next_range_cross,
                                    lab16_return_read_range_cross,
                                    lab16_return_read_valid,
                                    lab16_return_output_valid,
                                    lab16_active_i[3],
                                    lab16_map_valid_i[3],
                                    smoke_c0_pm3_audio_mask[3],
                                    1'b1,
                                    lab16_ch3_hold_mix_count_i >
                                        lab16_ch3_emit_count_i,
                                    lab16_ctrl_i[3][0],
                                    lab16_vol_l_i[3] == 7'd0 &&
                                        lab16_vol_r_i[3] == 7'd0
                                };
                            end
                        end
                        if (lab16_start_tuple_valid_i &&
                            (lab16_pending_ch_i == lab16_start_tuple_ch_i)) begin
                            lab16_runtime_status_i <= 16'hE600;
                            lab16_runtime_active_seen_i <= 1'b1;
                            lab16_first_capture_reader_match_i <= 1'b1;
                            if (lab16_runtime_consume_count_i != 16'hffff) begin
                                lab16_runtime_consume_count_i <=
                                    lab16_runtime_consume_count_i + 16'd1;
                            end
                            lab16_runtime_offset_i <=
                                lab16_runtime_offset_next;
                            lab16_runtime_addr_i <=
                                lab16_runtime_addr_next[15:0];
                            lab16_runtime_pi_i <= lab16_pi_i[lab16_pending_ch_i];
                            lab16_runtime_phase_hint_i <= {
                                lab16_phase_i[lab16_pending_ch_i][15:8],
                                lab16_phase_i[lab16_pending_ch_i][7:0]
                            };
                            lab16_runtime_rd_i <= {
                                loaded_ddr_rd_data,
                                lab16_return_cv[7:0]
                            };
                            lab16_runtime_l_i <= lab16_return_scaled_l[15:0];
                            lab16_runtime_r_i <= lab16_return_scaled_r[15:0];
                            lab16_runtime_stop_i <= {
                                11'd0,
                                lab16_return_phase_next[26:8] <
                                    lab16_base_i[lab16_pending_ch_i],
                                lab16_return_phase_next[26:8] >=
                                    lab16_limit_i[lab16_pending_ch_i],
                                !lab16_map_valid_i[lab16_pending_ch_i],
                                lab16_vol_l_i[lab16_pending_ch_i] == 7'd0 &&
                                    lab16_vol_r_i[lab16_pending_ch_i] == 7'd0,
                                lab16_ctrl_i[lab16_pending_ch_i][0]
                            };
                            if (lab16_return_read_valid &&
                                lab16_first_capture_armed_i &&
                                !lab16_first_samples_valid_i &&
                                (lab16_first_sample_count_i < 5'd16)) begin
                                lab16_first_capture_has_any_i <= 1'b1;
                                if (lab16_first_sample_count_i == 5'd0) begin
                                    lab16_first_s0_addr_i <=
                                        lab16_runtime_addr_next[15:0];
                                    lab16_first_s0_index_i <=
                                        lab16_pi_i[lab16_pending_ch_i][15:0];
                                    lab16_first_s0_phase_i <=
                                        lab16_phase_i[lab16_pending_ch_i][23:8];
                                    lab16_first_s0_capture_count_i <=
                                        (lab16_runtime_consume_count_i ==
                                         16'hffff) ?
                                        16'hffff :
                                        (lab16_runtime_consume_count_i +
                                         16'd1);
                                end
                                unique case (lab16_first_sample_count_i[3:0])
                                    4'd0: begin
                                        lab16_first_raw01_i[15:8] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_dec01_i[15:8] <=
                                            lab16_return_cv[7:0];
                                        lab16_wave_rawcv0_i <= {
                                            loaded_ddr_rd_data,
                                            lab16_return_cv[7:0]
                                        };
                                        lab16_wave_addr0_i <=
                                            lab16_runtime_addr_next[15:0];
                                        lab16_wave_pi0_i <=
                                            lab16_pi_i[
                                                lab16_pending_ch_i][15:0];
                                        lab16_wave_out0_i <=
                                            lab16_return_scaled_l[15:0];
                                    end
                                    4'd1: begin
                                        lab16_first_raw01_i[7:0] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_dec01_i[7:0] <=
                                            lab16_return_cv[7:0];
                                        lab16_wave_rawcv1_i <= {
                                            loaded_ddr_rd_data,
                                            lab16_return_cv[7:0]
                                        };
                                        lab16_wave_addr1_i <=
                                            lab16_runtime_addr_next[15:0];
                                        lab16_wave_pi1_i <=
                                            lab16_pi_i[
                                                lab16_pending_ch_i][15:0];
                                        lab16_wave_out1_i <=
                                            lab16_return_scaled_l[15:0];
                                    end
                                    4'd2: begin
                                        lab16_first_raw23_i[15:8] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_dec23_i[15:8] <=
                                            lab16_return_cv[7:0];
                                        lab16_wave_rawcv2_i <= {
                                            loaded_ddr_rd_data,
                                            lab16_return_cv[7:0]
                                        };
                                        lab16_wave_addr2_i <=
                                            lab16_runtime_addr_next[15:0];
                                        lab16_wave_pi2_i <=
                                            lab16_pi_i[
                                                lab16_pending_ch_i][15:0];
                                        lab16_wave_out2_i <=
                                            lab16_return_scaled_l[15:0];
                                    end
                                    4'd3: begin
                                        lab16_first_raw23_i[7:0] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_dec23_i[7:0] <=
                                            lab16_return_cv[7:0];
                                        lab16_wave_rawcv3_i <= {
                                            loaded_ddr_rd_data,
                                            lab16_return_cv[7:0]
                                        };
                                        lab16_wave_addr3_i <=
                                            lab16_runtime_addr_next[15:0];
                                        lab16_wave_pi3_i <=
                                            lab16_pi_i[
                                                lab16_pending_ch_i][15:0];
                                        lab16_wave_out3_i <=
                                            lab16_return_scaled_l[15:0];
                                    end
                                    4'd4: begin
                                        lab16_first_raw45_i[15:8] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_dec45_i[15:8] <=
                                            lab16_return_cv[7:0];
                                    end
                                    4'd5: begin
                                        lab16_first_raw45_i[7:0] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_dec45_i[7:0] <=
                                            lab16_return_cv[7:0];
                                    end
                                    4'd6: begin
                                        lab16_first_raw67_i[15:8] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_dec67_i[15:8] <=
                                            lab16_return_cv[7:0];
                                    end
                                    4'd7: begin
                                        lab16_first_raw67_i[7:0] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_dec67_i[7:0] <=
                                            lab16_return_cv[7:0];
                                    end
                                    4'd8: begin
                                        lab16_first_raw89_i[15:8] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_dec89_i[15:8] <=
                                            lab16_return_cv[7:0];
                                    end
                                    4'd9: begin
                                        lab16_first_raw89_i[7:0] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_dec89_i[7:0] <=
                                            lab16_return_cv[7:0];
                                    end
                                    4'd10: begin
                                        lab16_first_rawab_i[15:8] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_decab_i[15:8] <=
                                            lab16_return_cv[7:0];
                                    end
                                    4'd11: begin
                                        lab16_first_rawab_i[7:0] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_decab_i[7:0] <=
                                            lab16_return_cv[7:0];
                                    end
                                    4'd12: begin
                                        lab16_first_rawcd_i[15:8] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_deccd_i[15:8] <=
                                            lab16_return_cv[7:0];
                                    end
                                    4'd13: begin
                                        lab16_first_rawcd_i[7:0] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_deccd_i[7:0] <=
                                            lab16_return_cv[7:0];
                                    end
                                    4'd14: begin
                                        lab16_first_rawef_i[15:8] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_decef_i[15:8] <=
                                            lab16_return_cv[7:0];
                                    end
                                    default: begin
                                        lab16_first_rawef_i[7:0] <=
                                            loaded_ddr_rd_data;
                                        lab16_first_decef_i[7:0] <=
                                            lab16_return_cv[7:0];
                                    end
                                endcase
                                if (lab16_first_sample_count_i == 5'd15) begin
                                    lab16_first_sample_count_i <= 5'd16;
                                    lab16_first_samples_valid_i <= 1'b1;
                                    lab16_first_capture_armed_i <= 1'b0;
                                    lab16_runtime_pr_hold_i <= {
                                        8'hE6,
                                        lab16_first_capture_cleared_i,
                                        lab16_first_capture_overwrite_i,
                                        1'b1,
                                        lab16_first_capture_reader_match_i,
                                        1'b1,
                                        1'b1,
                                        1'b0,
                                        lab16_start_tuple_valid_i
                                    };
                                end else begin
                                    lab16_first_sample_count_i <=
                                        lab16_first_sample_count_i + 5'd1;
                                end
                            end
                        end
                        if (lab16_return_read_valid &&
                            (lab16_first8_count_i[lab16_pending_ch_i] <
                             4'd8)) begin
                            unique case (lab16_first8_count_i[
                                             lab16_pending_ch_i])
                                4'd0: lab16_first8_01_i[
                                    lab16_pending_ch_i][15:8] <=
                                    loaded_ddr_rd_data;
                                4'd1: lab16_first8_01_i[
                                    lab16_pending_ch_i][7:0] <=
                                    loaded_ddr_rd_data;
                                4'd2: lab16_first8_23_i[
                                    lab16_pending_ch_i][15:8] <=
                                    loaded_ddr_rd_data;
                                4'd3: lab16_first8_23_i[
                                    lab16_pending_ch_i][7:0] <=
                                    loaded_ddr_rd_data;
                                4'd4: lab16_first8_45_i[
                                    lab16_pending_ch_i][15:8] <=
                                    loaded_ddr_rd_data;
                                4'd5: lab16_first8_45_i[
                                    lab16_pending_ch_i][7:0] <=
                                    loaded_ddr_rd_data;
                                4'd6: lab16_first8_67_i[
                                    lab16_pending_ch_i][15:8] <=
                                    loaded_ddr_rd_data;
                                default: lab16_first8_67_i[
                                    lab16_pending_ch_i][7:0] <=
                                    loaded_ddr_rd_data;
                            endcase
                            lab16_first8_count_i[lab16_pending_ch_i] <=
                                lab16_first8_count_i[lab16_pending_ch_i] +
                                4'd1;
                        end
                        if (lab16_return_read_valid) begin
                            lab16_sample_i[lab16_pending_ch_i] <=
                                loaded_ddr_rd_data;
                            lab16_hold_sample_i[lab16_pending_ch_i] <=
                                loaded_ddr_rd_data;
                            lab16_hold_cv_i[lab16_pending_ch_i] <=
                                lab16_return_cv;
                        end else begin
                            lab16_sample_i[lab16_pending_ch_i] <= 8'h80;
                            lab16_hold_sample_i[lab16_pending_ch_i] <= 8'h80;
                            lab16_hold_cv_i[lab16_pending_ch_i] <= 9'sd0;
                        end
                        if (lab16_return_output_valid) begin
                            lab16_out_l_i[lab16_pending_ch_i] <=
                                lab16_return_scaled_l[15:0];
                            lab16_out_r_i[lab16_pending_ch_i] <=
                                lab16_return_scaled_r[15:0];
                            lab16_mix_fresh_i[lab16_pending_ch_i] <= 1'b1;
                        end else begin
                            lab16_out_l_i[lab16_pending_ch_i] <= 16'sd0;
                            lab16_out_r_i[lab16_pending_ch_i] <= 16'sd0;
                            lab16_mix_fresh_i[lab16_pending_ch_i] <= 1'b0;
                        end
                        if (lab16_return_output_valid &&
                            smoke_c0_pm3_audio_mask[lab16_pending_ch_i] &&
                            ((lab16_return_scaled_l[15:0] != 16'sd0) ||
                             (lab16_return_scaled_r[15:0] != 16'sd0))) begin
                            lab16_ever_nonzero_i[lab16_pending_ch_i] <= 1'b1;
                        end
                        if (lab16_return_output_valid &&
                            (lab16_return_abs_l > lab16_loud_snap_abs_i)) begin
                            lab16_loud_snap_valid_i <= 1'b1;
                            lab16_loud_snap_abs_i <= lab16_return_abs_l;
                            lab16_loud_snap_ch_i <= lab16_pending_ch_i;
                            lab16_loud_snap_block_i <=
                                lab16_block_i[lab16_pending_ch_i];
                            lab16_loud_snap_start_i <=
                                lab16_start_i[lab16_pending_ch_i];
                            lab16_loud_snap_pi_i <=
                                lab16_pi_i[lab16_pending_ch_i];
                            lab16_loud_snap_sample_i <= loaded_ddr_rd_data;
                            lab16_loud_snap_cv_i <= lab16_return_cv;
                            lab16_loud_snap_out_i <=
                                lab16_return_scaled_l[15:0];
                            lab16_loud_snap_delta_reason_i <= {
                                3'd0,
                                lab16_pi_i[lab16_pending_ch_i] <
                                    lab16_base_i[lab16_pending_ch_i],
                                lab16_pi_i[lab16_pending_ch_i] >=
                                    lab16_limit_i[lab16_pending_ch_i],
                                !lab16_map_valid_i[lab16_pending_ch_i],
                                lab16_vol_l_i[lab16_pending_ch_i] == 7'd0 &&
                                    lab16_vol_r_i[lab16_pending_ch_i] == 7'd0,
                                lab16_ctrl_i[lab16_pending_ch_i][0],
                                lab16_delta_i[lab16_pending_ch_i]
                            };
                            lab16_loud_snap_volume_i <= {
                                1'b0, lab16_vol_l_i[lab16_pending_ch_i],
                                1'b0, lab16_vol_r_i[lab16_pending_ch_i]
                            };
                            lab16_loud_snap_reason_i <= {
                                11'd0,
                                lab16_pi_i[lab16_pending_ch_i] <
                                    lab16_base_i[lab16_pending_ch_i],
                                lab16_pi_i[lab16_pending_ch_i] >=
                                    lab16_limit_i[lab16_pending_ch_i],
                                !lab16_map_valid_i[lab16_pending_ch_i],
                                lab16_vol_l_i[lab16_pending_ch_i] == 7'd0 &&
                                    lab16_vol_r_i[lab16_pending_ch_i] == 7'd0,
                                lab16_ctrl_i[lab16_pending_ch_i][0]
                            };
                        end
                        if (lab16_expl_masked_return &&
                            (lab16_expl_loud_return ||
                             lab16_expl_peak_return ||
                             lab16_expl_fault_return ||
                             ((lab16_return_true_cross ||
                             !lab16_return_read_valid) &&
                              !lab16_expl_valid_i) ||
                             lab16_expl_bootstrap_return ||
                             lab16_expl_first8_refresh)) begin
                            if (lab16_expl_count_i != 16'hffff) begin
                                lab16_expl_count_i <=
                                    lab16_expl_count_i + 16'd1;
                            end
	                            if (!lab16_expl_valid_i ||
	                                lab16_expl_loud_return ||
                                lab16_expl_peak_return ||
                                lab16_expl_fault_return ||
                                lab16_expl_first8_refresh ||
                                (lab16_mix_abs_max_next >=
                                 lab16_expl_abs_i) ||
	                                (lab16_return_abs_max >=
	                                 lab16_expl_abs_i)) begin
	                                lab16_expl_valid_i <= 1'b1;
	                                lab16_ch3_last_expl_time_i <=
	                                    lab16_return_count_i;
	                                lab16_expl_first8_done_i <=
                                    lab16_first8_count_i[
                                        lab16_pending_ch_i] >= 4'd8;
                                if (lab16_return_output_valid &&
                                    ((lab16_return_abs_max >
                                      lab16_expl_abs_i) ||
                                     (lab16_mix_abs_max_next >
                                      lab16_expl_abs_i))) begin
                                    lab16_expl_abs_i <=
                                        (lab16_return_abs_max >
                                         lab16_mix_abs_max_next) ?
                                        lab16_return_abs_max :
                                        lab16_mix_abs_max_next;
                                end
                                lab16_expl_ch_i <= lab16_pending_ch_i;
                                lab16_expl_block_i <=
                                    lab16_block_i[lab16_pending_ch_i];
                                lab16_expl_current_i <=
                                    lab16_start_current_i[lab16_pending_ch_i];
                                lab16_expl_end_i <=
                                    lab16_start_end_low_i[lab16_pending_ch_i];
                                lab16_expl_delta_i <=
                                    lab16_delta_i[lab16_pending_ch_i];
                                lab16_expl_volume_i <= {
                                    1'b0, lab16_vol_l_i[lab16_pending_ch_i],
                                    1'b0, lab16_vol_r_i[lab16_pending_ch_i]
                                };
                                lab16_expl_base_i <=
                                    lab16_base_i[lab16_pending_ch_i][15:0];
                                lab16_expl_first_index_i <=
                                    lab16_start_i[lab16_pending_ch_i][15:0];
                                lab16_expl_index_i <=
                                    lab16_pi_i[lab16_pending_ch_i][15:0];
                                lab16_expl_raw_cv_i <= {
                                    loaded_ddr_rd_data,
                                    lab16_return_cv[7:0]
                                };
                                lab16_expl_l_i <=
                                    lab16_return_scaled_l[15:0];
                                lab16_expl_r_i <=
                                    lab16_return_scaled_r[15:0];
                                lab16_expl_mix_i <=
                                    lab16_mix_abs_max_next;
                                lab16_expl_active_i <= lab16_active_i;
                                lab16_expl_reason_i <= {
                                    8'hEC,
                                    lab16_expl_loud_return,
                                    lab16_return_true_cross,
                                    lab16_return_next_range_cross,
                                    lab16_return_read_range_cross,
                                    !lab16_return_read_valid,
                                    !lab16_return_output_valid,
                                    smoke_c0_pm3_audio_mask[
                                        lab16_pending_ch_i],
                                    lab16_return_read_valid
                                };
                                lab16_expl_e0_i <=
                                    lab16_first8_01_i[lab16_pending_ch_i];
                                lab16_expl_e1_i <=
                                    lab16_first8_23_i[lab16_pending_ch_i];
                                lab16_expl_e2_i <=
                                    lab16_first8_45_i[lab16_pending_ch_i];
                                lab16_expl_e3_i <=
                                    lab16_first8_67_i[lab16_pending_ch_i];
                            end
                        end
                        lab16_phase_i[lab16_pending_ch_i] <=
                            lab16_return_phase_next;
                        lab16_pi_i[lab16_pending_ch_i] <=
                            lab16_return_phase_next[26:8];
                        if (!lab16_return_next_valid) begin
                            if (lab16_start_tuple_valid_i &&
                                (lab16_pending_ch_i == lab16_start_tuple_ch_i)) begin
                                lab16_last_stop_pi_i <= lab16_return_stop_pi;
                                if (lab16_return_true_cross &&
                                    (lab16_stop_count_i != 16'hffff)) begin
                                    lab16_stop_count_i <=
                                        lab16_stop_count_i + 16'd1;
                                end
                                if (lab16_return_true_cross &&
                                    !lab16_stop_valid_i) begin
                                    lab16_stop_valid_i <= 1'b1;
                                    lab16_stop_pi_i <=
                                        lab16_return_stop_pi[15:0];
                                    lab16_stop_offset_i <=
                                        lab16_return_stop_pi[15:0] -
                                        lab16_start_i[lab16_pending_ch_i][15:0];
                                    lab16_stop_full_i <=
                                        lab16_start_tuple_full_addr_i[15:0] +
                                        (lab16_return_stop_pi[15:0] -
                                         lab16_start_i[lab16_pending_ch_i][15:0]);
                                    lab16_stop_phase_i <= {
                                        lab16_return_phase_next[15:8],
                                        lab16_return_phase_next[7:0]
                                    };
                                    lab16_stop_flags_i <= {
                                        8'hEA,
                                        2'd0,
                                        1'b0,
                                        1'b1,
                                        1'b1,
                                        !lab16_return_read_valid,
                                        lab16_start_tuple_end_limited_i &&
                                            (lab16_return_stop_pi >=
                                             lab16_limit_i[lab16_pending_ch_i]),
                                        lab16_return_stop_pi >=
                                            lab16_limit_i[lab16_pending_ch_i]
                                    };
                                end else if (lab16_return_true_cross) begin
                                    lab16_stop_flags_i[5] <= 1'b1;
                                end
                                lab16_end_debug_flags_i <= {
                                    8'hE9,
                                    1'b1,
                                    lab16_start_tuple_end_limited_i,
                                    lab16_return_phase_next[26:8] <
                                        lab16_base_i[lab16_pending_ch_i],
                                    lab16_return_phase_next[26:8] >=
                                        lab16_limit_i[lab16_pending_ch_i],
                                    !lab16_map_valid_i[lab16_pending_ch_i],
                                    lab16_vol_l_i[lab16_pending_ch_i] == 7'd0 &&
                                        lab16_vol_r_i[lab16_pending_ch_i] == 7'd0,
                                    lab16_ctrl_i[lab16_pending_ch_i][0],
                                    1'b0
                                };
                            end
                            lab16_active_i[lab16_pending_ch_i] <= 1'b0;
                            lab16_map_valid_i[lab16_pending_ch_i] <= 1'b0;
                            lab16_out_l_i[lab16_pending_ch_i] <= 16'sd0;
                            lab16_out_r_i[lab16_pending_ch_i] <= 16'sd0;
                            lab16_mix_fresh_i[lab16_pending_ch_i] <= 1'b0;
                            lab16_hold_sample_i[lab16_pending_ch_i] <= 8'h80;
                            lab16_hold_cv_i[lab16_pending_ch_i] <= 9'sd0;
	                            if (lab16_pending_ch_i == 4'd3) begin
	                                lab16_ch3_stop_reason_i <= 16'h0004;
	                                if (lab16_ch3_clear_count_i != 16'hffff) begin
	                                    lab16_ch3_clear_count_i <=
	                                        lab16_ch3_clear_count_i + 16'd1;
	                                end
	                                lab16_ch3_last_clear_time_i <=
	                                    lab16_return_count_i;
	                                if (lab16_ch3_range_count_i != 16'hffff) begin
                                    lab16_ch3_range_count_i <=
                                        lab16_ch3_range_count_i + 16'd1;
                                end
                            end
                        end
                        if (lab16_pending_ch_i == 4'd3) begin
                            if (lab16_ch3_tick_count_i != 16'hffff) begin
                                lab16_ch3_tick_count_i <=
                                    lab16_ch3_tick_count_i + 16'd1;
                            end
                            if (!lab16_return_output_valid) begin
                                lab16_ch3_output_i <= 16'd0;
                                lab16_ch3_hold_i <= 16'd0;
                            end else begin
                                lab16_ch3_output_i <= lab16_return_scaled_l[15:0];
                                lab16_ch3_hold_i <= lab16_return_scaled_l[15:0];
                                if (lab16_ch3_hit_len_i != 16'hffff) begin
                                    lab16_ch3_hit_len_i <= lab16_ch3_hit_len_i + 16'd1;
                                end
                            end
                            if ((lab16_return_scaled_l[15:0] != 16'd0) &&
                                lab16_return_output_valid) begin
                                lab16_ch3_sticky_i[1] <= 1'b1;
                                if (lab16_ch3_emit_count_i != 16'hffff) begin
                                    lab16_ch3_emit_count_i <=
                                        lab16_ch3_emit_count_i + 16'd1;
                                end
                            end
                            if ((lab16_return_abs_l > lab16_ch3_peak_i) &&
                                lab16_return_output_valid) begin
                                lab16_ch3_peak_i <= lab16_return_abs_l;
                            end
                        end
                        if (lab16_return_count_i != 16'hffff) begin
                            lab16_return_count_i <= lab16_return_count_i + 16'd1;
                        end
                        if (lab_c0_advance_count_i != 16'hffff) begin
                            lab_c0_advance_count_i <=
                                lab_c0_advance_count_i + 16'd1;
                        end
                    end

                    if (lab16_service_tick && !lab_c0_pending_i &&
                        !lab_c0_req_live_i && lab16_next_valid) begin
                        if ((lab16_ctrl_i[lab16_next_ch][0]) ||
                            (lab16_vol_l_i[lab16_next_ch] == 7'd0 &&
                             lab16_vol_r_i[lab16_next_ch] == 7'd0) ||
                            !lab16_map_valid_i[lab16_next_ch] ||
                            (lab16_pi_i[lab16_next_ch] <
                             lab16_base_i[lab16_next_ch]) ||
                            (lab16_pi_i[lab16_next_ch] >=
                             lab16_limit_i[lab16_next_ch])) begin
                            lab16_service_true_cross =
                                lab16_map_valid_i[lab16_next_ch] &&
                                ((lab16_pi_i[lab16_next_ch] <
                                  lab16_base_i[lab16_next_ch]) ||
                                 (lab16_pi_i[lab16_next_ch] >=
                                  lab16_limit_i[lab16_next_ch]));
                            if (lab16_start_tuple_valid_i &&
                                (lab16_next_ch == lab16_start_tuple_ch_i)) begin
                                lab16_last_stop_pi_i <= lab16_pi_i[lab16_next_ch];
                                if (lab16_service_true_cross &&
                                    (lab16_stop_count_i != 16'hffff)) begin
                                    lab16_stop_count_i <=
                                        lab16_stop_count_i + 16'd1;
                                end
                                if (lab16_service_true_cross &&
                                    !lab16_stop_valid_i) begin
                                    lab16_stop_valid_i <= 1'b1;
                                    lab16_stop_pi_i <=
                                        lab16_pi_i[lab16_next_ch][15:0];
                                    lab16_stop_offset_i <=
                                        lab16_pi_i[lab16_next_ch][15:0] -
                                        lab16_start_i[lab16_next_ch][15:0];
                                    lab16_stop_full_i <=
                                        lab16_start_tuple_full_addr_i[15:0] +
                                        (lab16_pi_i[lab16_next_ch][15:0] -
                                         lab16_start_i[lab16_next_ch][15:0]);
                                    lab16_stop_phase_i <= {
                                        lab16_phase_i[lab16_next_ch][15:8],
                                        lab16_phase_i[lab16_next_ch][7:0]
                                    };
                                    lab16_stop_flags_i <= {
                                        8'hEA,
                                        2'd0,
                                        1'b0,
                                        1'b1,
                                        1'b1,
                                        lab16_pi_i[lab16_next_ch] >=
                                            lab16_limit_i[lab16_next_ch],
                                        lab16_start_tuple_end_limited_i &&
                                            (lab16_pi_i[lab16_next_ch] >=
                                             lab16_limit_i[lab16_next_ch]),
                                        lab16_pi_i[lab16_next_ch] >=
                                            lab16_limit_i[lab16_next_ch]
                                    };
                                end else if (lab16_service_true_cross) begin
                                    lab16_stop_flags_i[5] <= 1'b1;
                                end
                                lab16_end_debug_flags_i <= {
                                    8'hE9,
                                    1'b1,
                                    lab16_start_tuple_end_limited_i,
                                    lab16_pi_i[lab16_next_ch] <
                                        lab16_base_i[lab16_next_ch],
                                    lab16_pi_i[lab16_next_ch] >=
                                        lab16_limit_i[lab16_next_ch],
                                    !lab16_map_valid_i[lab16_next_ch],
                                    lab16_vol_l_i[lab16_next_ch] == 7'd0 &&
                                        lab16_vol_r_i[lab16_next_ch] == 7'd0,
                                    lab16_ctrl_i[lab16_next_ch][0],
                                    1'b1
                                };
                            end
                            lab16_active_i[lab16_next_ch] <= 1'b0;
                            lab16_map_valid_i[lab16_next_ch] <= 1'b0;
                            lab16_out_l_i[lab16_next_ch] <= 16'sd0;
                            lab16_out_r_i[lab16_next_ch] <= 16'sd0;
                            lab16_mix_fresh_i[lab16_next_ch] <= 1'b0;
	                            if (lab16_next_ch == 4'd3) begin
	                                lab16_ch3_stop_reason_i <= {
                                    11'd0,
                                    lab16_pi_i[lab16_next_ch] <
                                        lab16_base_i[lab16_next_ch],
                                    lab16_pi_i[lab16_next_ch] >=
                                        lab16_limit_i[lab16_next_ch],
                                    !lab16_map_valid_i[lab16_next_ch],
                                    lab16_vol_l_i[lab16_next_ch] == 7'd0 &&
                                        lab16_vol_r_i[lab16_next_ch] == 7'd0,
	                                    lab16_ctrl_i[lab16_next_ch][0]
	                                };
	                                if (lab16_ch3_clear_count_i != 16'hffff) begin
	                                    lab16_ch3_clear_count_i <=
	                                        lab16_ch3_clear_count_i + 16'd1;
	                                end
                                    if (lab16_ch3_output_clear_count_i !=
                                        16'hffff) begin
                                        lab16_ch3_output_clear_count_i <=
                                            lab16_ch3_output_clear_count_i +
                                            16'd1;
                                    end
                                    if (lab16_service_true_cross &&
                                        (lab16_ch3_end_reached_count_i !=
                                         16'hffff)) begin
                                        lab16_ch3_end_reached_count_i <=
                                            lab16_ch3_end_reached_count_i +
                                            16'd1;
                                    end
                                    if (lab16_service_true_cross &&
                                        (lab16_ch3_clear_end_count_i !=
                                         16'hffff)) begin
                                        lab16_ch3_clear_end_count_i <=
                                            lab16_ch3_clear_end_count_i +
                                            16'd1;
                                    end
                                    if (lab16_ctrl_i[lab16_next_ch][0] &&
                                        (lab16_ch3_clear_disable_count_i !=
                                         16'hffff)) begin
                                        lab16_ch3_clear_disable_count_i <=
                                            lab16_ch3_clear_disable_count_i +
                                            16'd1;
                                    end
                                    if ((lab16_vol_l_i[lab16_next_ch] == 7'd0 &&
                                         lab16_vol_r_i[lab16_next_ch] == 7'd0) &&
                                        (lab16_ch3_clear_volume_count_i !=
                                         16'hffff)) begin
                                        lab16_ch3_clear_volume_count_i <=
                                            lab16_ch3_clear_volume_count_i +
                                            16'd1;
                                    end
                                    if (!lab16_map_valid_i[lab16_next_ch] &&
                                        (lab16_ch3_clear_map_count_i !=
                                         16'hffff)) begin
                                        lab16_ch3_clear_map_count_i <=
                                            lab16_ch3_clear_map_count_i +
                                            16'd1;
                                    end
	                                lab16_ch3_last_clear_time_i <=
	                                    lab16_return_count_i;
	                            end
                            lab16_rr_ch_i <= lab16_next_ch + 4'd1;
                        end else begin
                            lab_c0_req_addr_i <= lab16_pi_i[lab16_next_ch];
                            lab_c0_req_live_i <= 1'b1;
                            lab_c0_need_read_i <= 1'b1;
                            lab_c0_pending_i <= 1'b1;
                            lab16_pending_ch_i <= lab16_next_ch;
                            lab16_rr_ch_i <= lab16_next_ch + 4'd1;
                            if (lab16_request_count_i != 16'hffff) begin
                                lab16_request_count_i <=
                                    lab16_request_count_i + 16'd1;
                            end
                            if (lab_c0_request_count_i != 16'hffff) begin
                                lab_c0_request_count_i <=
                                    lab_c0_request_count_i + 16'd1;
                            end
                        end
                    end
                end
            end else if (lab_c0_seq_mode) begin
                lab_c0_active_i <= lab_c0_seq_output;
                lab_c0_state_i <= lab_c0_seq_output ?
                    LAB_C0_ST_CONSUME : LAB_C0_ST_IDLE;
                if (!lab_c0_local_pcm_mode) begin
                    lab_c0_pending_i <= 1'b0;
                    lab_c0_need_read_i <= 1'b0;
                end
                lab_c0_stall_count_i <= 16'd0;
                lab_c0_seed_i <= smoke_c0_current_seed_i[15:0];
                lab_c0_cur_i <= smoke_c0_current_seed_i[15:0];
                if (!lab_c0_seq_output) begin
                    lab_c0_fixed_div_i <= 12'd0;
                    lab_c0_pi_i <= 19'd0;
                    lab_c0_return_pi_i <= 19'd0;
                    lab_c0_pending_i <= 1'b0;
                    lab_c0_need_read_i <= 1'b0;
                    lab_c0_req_addr_i <= 19'd0;
                    lab_c0_sample_i <= 8'h80;
                    lab_c0_output_i <= 16'sd0;
                    lab_c0_phase_i <= 27'd0;
                    lab_c0_mame_tick_div_count_i <= 4'd0;
                    if (lab_c0_selected_event_pulse) begin
                        if (lab_c0_retrigger_count_i != 16'hffff) begin
                            lab_c0_retrigger_count_i <=
                                lab_c0_retrigger_count_i + 16'd1;
                        end
                        if (lab_c0_mame_exact_mode) begin
                            lab_c0_pm4_reseed_reason_i <=
                                lab_c0_pm4_reseed_reason_next;
                            if (lab_c0_pm4_write_count_i != 16'hffff) begin
                                lab_c0_pm4_write_count_i <=
                                    lab_c0_pm4_write_count_i + 16'd1;
                            end
                        end
                    end
                    if (lab_c0_retrigger_pulse) begin
                        if (lab_c0_reseed_count_i != 16'hffff) begin
                            lab_c0_reseed_count_i <= lab_c0_reseed_count_i + 16'd1;
                        end
                        if (lab_c0_mame_exact_mode &&
                            (lab_c0_pm4_reseed_count_i != 16'hffff)) begin
                            lab_c0_pm4_reseed_count_i <=
                                lab_c0_pm4_reseed_count_i + 16'd1;
                        end
                        lab_c0_event_time_i <= lab_c0_advance_count_i;
                        lab_c0_event_seed_i <= {
                            lab_c0_event_cur_high,
                            lab_c0_event_cur_mid
                        };
                        lab_c0_reseed_pi_i <= lab_c0_event_local_pi;
                        lab_c0_phase_i <= {lab_c0_event_local_pi, 8'd0};
                        lab_c0_pi_i <= lab_c0_event_local_pi;
                        lab_c0_req_addr_i <= lab_c0_event_local_pi;
                        lab_c0_hit_count_i <= 16'd0;
                        lab_c0_mame_tick_count_i <= 16'd0;
                        if (lab_c0_mame_exact_mode &&
                            !lab_c0_mame_trace_armed_i) begin
                            lab_c0_mame_trace_armed_i <= 1'b1;
                            lab_c0_mame_trace_count_i <= 3'd0;
                            lab_c0_mame_loop_seen_i <= 1'b0;
                            lab_c0_mame_k0_i <= 16'd0;
                            lab_c0_mame_k1_i <= 16'd0;
                            lab_c0_mame_k2_i <= 16'd0;
                            lab_c0_mame_k3_i <= 16'd0;
                            lab_c0_mame_b0_i <= 16'd0;
                            lab_c0_mame_b1_i <= 16'd0;
                            lab_c0_mame_b2_i <= 16'd0;
                            lab_c0_mame_b3_i <= 16'd0;
                            lab_c0_mame_c0_i <= 16'd0;
                            lab_c0_mame_c1_i <= 16'd0;
                            lab_c0_mame_c2_i <= 16'd0;
                            lab_c0_mame_c3_i <= 16'd0;
                            lab_c0_mame_loud_armed_i <= 1'b1;
                            lab_c0_mame_loud_active_i <= 1'b0;
                            lab_c0_mame_loud_count_i <= 3'd0;
                            lab_c0_mame_loud_p0_i <= 16'd0;
                            lab_c0_mame_loud_p1_i <= 16'd0;
                            lab_c0_mame_loud_p2_i <= 16'd0;
                            lab_c0_mame_loud_p3_i <= 16'd0;
                            lab_c0_mame_loud_q0_i <= 16'd0;
                            lab_c0_mame_loud_q1_i <= 16'd0;
                            lab_c0_mame_loud_q2_i <= 16'd0;
                            lab_c0_mame_loud_q3_i <= 16'd0;
                            lab_c0_mame_loud_m0_i <= 16'd0;
                            lab_c0_mame_loud_m1_i <= 16'd0;
                            lab_c0_mame_loud_m2_i <= 16'd0;
                            lab_c0_mame_loud_m3_i <= 16'd0;
                        end
                    end
                end else begin
                    if (lab_c0_selected_event_pulse) begin
                        if (lab_c0_retrigger_count_i != 16'hffff) begin
                            lab_c0_retrigger_count_i <=
                                lab_c0_retrigger_count_i + 16'd1;
                        end
                        if (lab_c0_mame_exact_mode) begin
                            lab_c0_pm4_reseed_reason_i <=
                                lab_c0_pm4_reseed_reason_next;
                            if (lab_c0_pm4_write_count_i != 16'hffff) begin
                                lab_c0_pm4_write_count_i <=
                                    lab_c0_pm4_write_count_i + 16'd1;
                            end
                        end
                    end
                    if (lab_c0_retrigger_pulse) begin
                        if (lab_c0_reseed_count_i != 16'hffff) begin
                            lab_c0_reseed_count_i <= lab_c0_reseed_count_i + 16'd1;
                        end
                        if (lab_c0_mame_exact_mode &&
                            (lab_c0_pm4_reseed_count_i != 16'hffff)) begin
                            lab_c0_pm4_reseed_count_i <=
                                lab_c0_pm4_reseed_count_i + 16'd1;
                        end
                        lab_c0_event_time_i <= lab_c0_advance_count_i;
                        lab_c0_event_seed_i <= {
                            lab_c0_event_cur_high,
                            lab_c0_event_cur_mid
                        };
                        lab_c0_reseed_pi_i <= lab_c0_event_local_pi;
                        lab_c0_phase_i <= {lab_c0_event_local_pi, 8'd0};
                        lab_c0_pi_i <= lab_c0_event_local_pi;
                        lab_c0_req_addr_i <= lab_c0_event_local_pi;
                        lab_c0_pending_i <= 1'b0;
                        lab_c0_need_read_i <= 1'b0;
                        lab_c0_sample_i <= 8'h80;
                        lab_c0_hit_count_i <= 16'd0;
                        lab_c0_mame_tick_div_count_i <= 4'd0;
                        lab_c0_mame_tick_count_i <= 16'd0;
                        if (lab_c0_mame_exact_mode &&
                            !lab_c0_mame_trace_armed_i) begin
                            lab_c0_mame_trace_armed_i <= 1'b1;
                            lab_c0_mame_trace_count_i <= 3'd0;
                            lab_c0_mame_loop_seen_i <= 1'b0;
                            lab_c0_mame_k0_i <= 16'd0;
                            lab_c0_mame_k1_i <= 16'd0;
                            lab_c0_mame_k2_i <= 16'd0;
                            lab_c0_mame_k3_i <= 16'd0;
                            lab_c0_mame_b0_i <= 16'd0;
                            lab_c0_mame_b1_i <= 16'd0;
                            lab_c0_mame_b2_i <= 16'd0;
                            lab_c0_mame_b3_i <= 16'd0;
                            lab_c0_mame_c0_i <= 16'd0;
                            lab_c0_mame_c1_i <= 16'd0;
                            lab_c0_mame_c2_i <= 16'd0;
                            lab_c0_mame_c3_i <= 16'd0;
                            lab_c0_mame_loud_armed_i <= 1'b1;
                            lab_c0_mame_loud_active_i <= 1'b0;
                            lab_c0_mame_loud_count_i <= 3'd0;
                            lab_c0_mame_loud_p0_i <= 16'd0;
                            lab_c0_mame_loud_p1_i <= 16'd0;
                            lab_c0_mame_loud_p2_i <= 16'd0;
                            lab_c0_mame_loud_p3_i <= 16'd0;
                            lab_c0_mame_loud_q0_i <= 16'd0;
                            lab_c0_mame_loud_q1_i <= 16'd0;
                            lab_c0_mame_loud_q2_i <= 16'd0;
                            lab_c0_mame_loud_q3_i <= 16'd0;
                            lab_c0_mame_loud_m0_i <= 16'd0;
                            lab_c0_mame_loud_m1_i <= 16'd0;
                            lab_c0_mame_loud_m2_i <= 16'd0;
                            lab_c0_mame_loud_m3_i <= 16'd0;
                        end
                    end
                    if (lab_c0_return_pulse) begin
                        lab_c0_pending_i <= 1'b0;
                        lab_c0_need_read_i <= 1'b0;
                        lab_c0_return_pi_i <= lab_c0_req_addr_i;
                        lab_c0_sample_i <= loaded_ddr_rd_data;
                        if (lab_c0_return_count_i != 16'hffff) begin
                            lab_c0_return_count_i <=
                                lab_c0_return_count_i + 16'd1;
                        end
                    end
                    if (segapcm_cen) begin
                        lab_c0_fixed_div_i <= lab_c0_fixed_div_i + 12'd1;
                        if (lab_c0_seq_base_emit_pulse) begin
                            if (lab_c0_mame_exact_mode) begin
                                lab_c0_mame_tick_div_count_i <=
                                    lab_c0_mame_tick_div_due ? 4'd0 :
                                    lab_c0_mame_tick_div_count_i + 4'd1;
                            end else begin
                                lab_c0_mame_tick_div_count_i <= 4'd0;
                            end
                        end
                    if (lab_c0_local_pcm_mode &&
                        !lab_c0_pending_i &&
                        !lab_c0_req_live_i &&
                        lab_c0_pi_in_range) begin
                        lab_c0_req_addr_i <= lab_c0_pi_i;
                        lab_c0_req_live_i <= 1'b1;
                        lab_c0_need_read_i <= 1'b1;
                        lab_c0_pending_i <= 1'b1;
                        if (lab_c0_request_count_i != 16'hffff) begin
                            lab_c0_request_count_i <=
                                lab_c0_request_count_i + 16'd1;
                        end
                    end
                    if (lab_c0_seq_emit_pulse) begin
                        if (!lab_c0_local_pcm_mode) begin
                            lab_c0_sample_i <= lab_c0_selected_sample_byte;
                        end
                        lab_c0_output_i <= lab_c0_mame_exact_mode ?
                            lab_c0_direct_output_sample :
                            lab_c0_selected_direct_sample;
                        lab_c0_consume_pulse_i <= 1'b1;
                        lab_c0_fixed_index_i <= lab_c0_fixed_index_i + 3'd1;
                        if (lab_c0_advance_count_i != 16'hffff) begin
                            lab_c0_advance_count_i <=
                                lab_c0_advance_count_i + 16'd1;
                        end
                        if (lab_c0_mame_exact_mode &&
                            (lab_c0_mame_tick_count_i != 16'hffff)) begin
                            lab_c0_mame_tick_count_i <=
                                lab_c0_mame_tick_count_i + 16'd1;
                        end
                        if ((lab_c0_local_delta_mode || lab_c0_mame_exact_mode) &&
                            (lab_c0_hit_window_open || lab_c0_mame_exact_mode) &&
                            (lab_c0_hit_count_i != 16'hffff)) begin
                            lab_c0_hit_count_i <= lab_c0_hit_count_i + 16'd1;
                        end
                        if (lab_c0_mame_exact_mode &&
                            lab_c0_mame_trace_armed_i &&
                            (lab_c0_mame_trace_count_i < 3'd4)) begin
                            unique case (lab_c0_mame_trace_count_i)
                                3'd0: begin
                                    lab_c0_mame_k0_i <= lab_c0_pi_i[15:0];
                                    lab_c0_mame_b0_i <= lab_c0_mame_sb_cv_debug;
                                    lab_c0_mame_c0_i <= lab_c0_mame_cv_debug;
                                end
                                3'd1: begin
                                    lab_c0_mame_k1_i <= lab_c0_pi_i[15:0];
                                    lab_c0_mame_b1_i <= lab_c0_mame_sb_cv_debug;
                                    lab_c0_mame_c1_i <= lab_c0_mame_cv_debug;
                                end
                                3'd2: begin
                                    lab_c0_mame_k2_i <= lab_c0_pi_i[15:0];
                                    lab_c0_mame_b2_i <= lab_c0_mame_sb_cv_debug;
                                    lab_c0_mame_c2_i <= lab_c0_mame_cv_debug;
                                end
                                default: begin
                                    lab_c0_mame_k3_i <= lab_c0_pi_i[15:0];
                                    lab_c0_mame_b3_i <= lab_c0_mame_sb_cv_debug;
                                    lab_c0_mame_c3_i <= lab_c0_mame_cv_debug;
                                end
                            endcase
                            lab_c0_mame_trace_count_i <=
                                lab_c0_mame_trace_count_i + 3'd1;
                        end
                        if (lab_c0_mame_exact_mode &&
                            lab_c0_mame_loud_armed_i &&
                            (lab_c0_mame_loud_count_i < 3'd4) &&
                            (lab_c0_mame_loud_active_i ||
                             lab_c0_mame_loud_hit)) begin
                            lab_c0_mame_loud_active_i <= 1'b1;
                            unique case (lab_c0_mame_loud_count_i)
                                3'd0: begin
                                    lab_c0_mame_loud_p0_i <= lab_c0_pi_i[15:0];
                                    lab_c0_mame_loud_q0_i <= lab_c0_mame_sb_cv_debug;
                                    lab_c0_mame_loud_m0_i <= lab_c0_direct_output_sample;
                                end
                                3'd1: begin
                                    lab_c0_mame_loud_p1_i <= lab_c0_pi_i[15:0];
                                    lab_c0_mame_loud_q1_i <= lab_c0_mame_sb_cv_debug;
                                    lab_c0_mame_loud_m1_i <= lab_c0_direct_output_sample;
                                end
                                3'd2: begin
                                    lab_c0_mame_loud_p2_i <= lab_c0_pi_i[15:0];
                                    lab_c0_mame_loud_q2_i <= lab_c0_mame_sb_cv_debug;
                                    lab_c0_mame_loud_m2_i <= lab_c0_direct_output_sample;
                                end
                                default: begin
                                    lab_c0_mame_loud_p3_i <= lab_c0_pi_i[15:0];
                                    lab_c0_mame_loud_q3_i <= lab_c0_mame_sb_cv_debug;
                                    lab_c0_mame_loud_m3_i <= lab_c0_direct_output_sample;
                                end
                            endcase
                            lab_c0_mame_loud_count_i <=
                                lab_c0_mame_loud_count_i + 3'd1;
                        end
                        if (lab_c0_local_seq_mode) begin
                            if (lab_c0_pi_i != 19'h7ffff) begin
                                lab_c0_pi_i <= lab_c0_pi_i + 19'd1;
                            end
                        end else if (lab_c0_local_delta_mode ||
                                     lab_c0_mame_exact_mode) begin
                            if (!lab_c0_retrigger_pulse) begin
                                if (lab_c0_mame_exact_mode &&
                                    lab_c0_mame_ctrl_disabled) begin
                                    lab_c0_phase_i <=
                                        {lab_c0_phase_i[26:8], 8'd0};
                                end else if (lab_c0_mame_exact_mode &&
                                             lab_c0_mame_end_hit) begin
                                    if (!c0_capture_ch3_ctrl_i[1]) begin
                                        lab_c0_phase_i <=
                                            {lab_c0_loop_local_pi, 8'd0};
                                        lab_c0_pi_i <= lab_c0_loop_local_pi;
                                        lab_c0_mame_loop_seen_i <= 1'b1;
                                    end else begin
                                        lab_c0_phase_i <=
                                            {lab_c0_phase_i[26:8], 8'd0};
                                    end
                                end else begin
                                    lab_c0_phase_i <= lab_c0_phase_next;
                                    lab_c0_pi_i <= lab_c0_delta_pi_next;
                                end
                            end
                        end else begin
                            lab_c0_pi_i <= {16'd0, lab_c0_fixed_index_i};
                            lab_c0_return_pi_i <= {16'd0, lab_c0_fixed_index_i};
                        end
                    end
                    end
                end
            end else if (lab_c0_local_mode) begin
                lab_c0_active_i <= lab_c0_local_output;
                lab_c0_state_i <= lab_c0_local_output ?
                    LAB_C0_ST_CONSUME : LAB_C0_ST_IDLE;
                lab_c0_pending_i <= 1'b0;
                lab_c0_need_read_i <= 1'b0;
                lab_c0_req_live_i <= 1'b0;
                lab_c0_stall_count_i <= 16'd0;
                lab_c0_seed_i <= smoke_c0_current_seed_i[15:0];
                lab_c0_cur_i <= smoke_c0_current_seed_i[15:0] +
                    lab_c0_pi_i[15:0];
                if (!lab_c0_local_output) begin
                    lab_c0_pi_i <= 19'd0;
                    lab_c0_return_pi_i <= 19'd0;
                    lab_c0_advance_count_i <= 16'd0;
                    lab_c0_request_count_i <= 16'd0;
                    lab_c0_return_count_i <= 16'd0;
                    lab_c0_sample_i <= 8'h80;
                    lab_c0_output_i <= 16'sd0;
                    lab_c0_fixed_index_i <= 3'd0;
                    lab_c0_hit_count_i <= 16'd0;
                end else if (segapcm_cen) begin
                    lab_c0_sample_i <= lab_c0_selected_sample_byte;
                    lab_c0_output_i <= lab_c0_selected_direct_sample;
                    lab_c0_consume_pulse_i <= 1'b1;
                    lab_c0_return_pi_i <= lab_c0_pi_i;
                    lab_c0_fixed_index_i <= lab_c0_fixed_index_i + 3'd1;
                    if (lab_c0_advance_count_i != 16'hffff) begin
                        lab_c0_advance_count_i <=
                            lab_c0_advance_count_i + 16'd1;
                    end
                    if ((lab_c0_local_delta_mode || lab_c0_mame_exact_mode) &&
                        (lab_c0_hit_window_open || lab_c0_mame_exact_mode) &&
                        (lab_c0_hit_count_i != 16'hffff)) begin
                        lab_c0_hit_count_i <= lab_c0_hit_count_i + 16'd1;
                    end
                    if (lab_c0_pi_i != 19'h7ffff) begin
                        lab_c0_pi_i <= lab_c0_pi_i + 19'd1;
                    end
                end
            end else if (!lab_c0_should_run) begin
                lab_c0_active_i <= 1'b0;
                lab_c0_seed_i <= smoke_c0_current_seed_i[15:0];
                lab_c0_cur_i <= 16'd0;
                lab_c0_state_i <= LAB_C0_ST_IDLE;
                lab_c0_pi_i <= 19'd0;
                lab_c0_stall_count_i <= 16'd0;
                lab_c0_pending_i <= 1'b0;
                lab_c0_need_read_i <= 1'b0;
            end else begin
                unique case (lab_c0_state_i)
                    LAB_C0_ST_IDLE: begin
                        if (lab_c0_arm) begin
                            lab_c0_active_i <= 1'b1;
                            lab_c0_seed_i <= smoke_c0_current_seed_i[15:0];
                            lab_c0_cur_i <= smoke_c0_current_seed_i[15:0];
                            lab_c0_pi_i <= 19'd0;
                            lab_c0_return_pi_i <= 19'd0;
                            lab_c0_advance_count_i <= 16'd0;
                            lab_c0_stall_count_i <= 16'd0;
                            lab_c0_request_count_i <= 16'd0;
                            lab_c0_return_count_i <= 16'd0;
                            lab_c0_sample_i <= 8'h80;
                            lab_c0_output_i <= 16'sd0;
                            lab_c0_pending_i <= 1'b0;
                            lab_c0_need_read_i <= 1'b0;
                            lab_c0_fixed_index_i <= 3'd0;
                            lab_c0_hit_count_i <= 16'd0;
                            lab_c0_state_i <= LAB_C0_ST_REQ;
                        end
                    end
                    LAB_C0_ST_REQ: begin
                        if (segapcm_cen) begin
                            if (lab_c0_force_mode) begin
                                lab_c0_sample_i <= 8'h80;
                                lab_c0_output_i <= LAB_C0_FORCE_SAMPLE;
                                lab_c0_need_read_i <= 1'b0;
                                lab_c0_state_i <= LAB_C0_ST_CONSUME;
                            end else if (lab_c0_fixed_mode) begin
                                lab_c0_sample_i <= lab_c0_fixed_byte;
                                lab_c0_output_i <= lab_gain_sample(lab_c0_fixed_byte);
                                lab_c0_need_read_i <= 1'b0;
                                lab_c0_state_i <= LAB_C0_ST_CONSUME;
                            end else if (lab_c0_pi_in_range &&
                                         !loaded_ddr_rd_req &&
                                         !smoke_c0_probe_pending_i &&
                                         !smoke_ddr_c0_pending_i &&
                                         !smoke_ddr_c0_return_valid_i) begin
                                lab_c0_req_addr_i <= lab_c0_pi_i;
                                lab_c0_req_live_i <= 1'b1;
                                lab_c0_need_read_i <= 1'b1;
                                lab_c0_pending_i <= 1'b1;
                                lab_c0_state_i <= LAB_C0_ST_WAIT;
                                if (lab_c0_request_count_i != 16'hffff) begin
                                    lab_c0_request_count_i <=
                                        lab_c0_request_count_i + 16'd1;
                                end
                            end else if (lab_c0_stall_count_i != 16'hffff) begin
                                lab_c0_stall_count_i <= lab_c0_stall_count_i + 16'd1;
                            end
                        end
                    end
                    LAB_C0_ST_WAIT: begin
                        if (lab_c0_return_pulse) begin
                            lab_c0_pending_i <= 1'b0;
                            lab_c0_return_pi_i <= lab_c0_req_addr_i;
                            lab_c0_sample_i <= loaded_ddr_rd_data;
                            lab_c0_output_i <= lab_gain_sample(loaded_ddr_rd_data);
                            lab_c0_state_i <= LAB_C0_ST_CONSUME;
                            if (lab_c0_return_count_i != 16'hffff) begin
                                lab_c0_return_count_i <=
                                    lab_c0_return_count_i + 16'd1;
                            end
                        end else if (segapcm_cen &&
                                     (lab_c0_stall_count_i != 16'hffff)) begin
                            lab_c0_stall_count_i <= lab_c0_stall_count_i + 16'd1;
                        end
                    end
                    LAB_C0_ST_CONSUME: begin
                        lab_c0_consume_pulse_i <= 1'b1;
                        if (!lab_c0_fixed_mode &&
                            (lab_c0_advance_count_i != 16'hffff)) begin
                            lab_c0_advance_count_i <=
                                lab_c0_advance_count_i + 16'd1;
                        end
                        if (!lab_c0_force_mode) begin
                            if (lab_c0_fixed_mode) begin
                                lab_c0_fixed_index_i <= lab_c0_fixed_index_i + 3'd1;
                            end else if (lab_c0_pi_i != 19'h7ffff) begin
                                lab_c0_pi_i <= lab_c0_pi_i +
                                    ((smoke_c0_sample_mode_sel == LAB_C0_PUMP_LOCAL_DELTA) ?
                                     {11'd0, c0_capture_ch3_delta_i} : 19'd1);
                                lab_c0_cur_i <= lab_c0_seed_i + lab_c0_pi_i[15:0] + 16'd1;
                            end
                        end
                        lab_c0_state_i <= LAB_C0_ST_REQ;
                    end
                    default: begin
                        lab_c0_state_i <= LAB_C0_ST_IDLE;
                    end
                endcase
            end
        end
    end
`endif
`endif

    always_ff @(posedge clk) begin
        if (reset) begin
            core_rom_cs_d <= 1'b0;
            core_rom_cs_d2 <= 1'b0;
            core_rom_addr_d <= 19'd0;
            mapped_rom_addr_d <= 19'd0;
            mapped_rom_addr_d2 <= 19'd0;
            request_raw_rom_addr_i <= 19'd0;
            request_mapped_rom_addr_i <= 19'd0;
            request_preload_addr_valid_i <= 1'b0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
            smoke_payload_addr_i <= smoke_payload_base;
            smoke_payload_div_count_i <= 3'd0;
            smoke_variant_d_i <= smoke_variant_active;
            smoke_source_loaded_d_i <= smoke_source_loaded;
`endif
            preload_rom_data_d <= 8'd0;
            preload_rom_data_d2 <= 8'd0;
            preload_rom_addr_valid_d <= 1'b0;
            preload_rom_addr_valid_d2 <= 1'b0;
            latched_cpu_addr <= 8'd0;
            latched_cpu_data <= 8'd0;
            latched_raw_addr <= 16'd0;
            cpu_write_pending <= 1'b0;
            cpu_write_pulse <= 1'b0;
            core_cpu_cs_d <= 1'b0;
            core_write_count_i <= 16'd0;
            core_cen_write_count_i <= 16'd0;
            rom_activity_count_i <= 16'd0;
            rom_range_hit_count_i <= 16'd0;
            rom_range_miss_count_i <= 16'd0;
            rom_return_nonzero_count_i <= 16'd0;
            rom_return_change_count_i <= 16'd0;
            rom_return_neutral_count_i <= 16'd0;
            rom_core_ok_count_i <= 16'd0;
            rom_fallback_count_i <= 16'd0;
            rom_read_valid_count_i <= 16'd0;
            raw_rom_min_addr_i <= 19'd0;
            raw_rom_max_addr_i <= 19'd0;
            last_rom_request_addr_i <= 19'd0;
            last_return_mapped_addr_i <= 19'd0;
            last_return_data_i <= 8'd0;
            return_data_history0_i <= 8'd0;
            return_data_history1_i <= 8'd0;
            return_data_history2_i <= 8'd0;
            return_data_history3_i <= 8'd0;
            ch3_raw_rom_min_addr_i <= 19'd0;
            ch3_raw_rom_max_addr_i <= 19'd0;
            ch3_last_rom_request_addr_i <= 19'd0;
            first_after_ch1_ctrl_addr_i <= 19'd0;
            early_after_ch1_ctrl_addr_i <= 19'd0;
            active_after_ch1_ctrl_addr_i <= 19'd0;
            raw_rom_minmax_seen_i <= 1'b0;
            ch3_raw_rom_minmax_seen_i <= 1'b0;
            first_after_ch1_ctrl_pending_i <= 1'b0;
            first_after_ch1_ctrl_seen_i <= 1'b0;
            early_after_ch1_ctrl_pending_i <= 1'b0;
            early_after_ch1_ctrl_seen_i <= 1'b0;
            active_after_ch1_ctrl_pending_i <= 1'b0;
            active_after_ch1_ctrl_seen_i <= 1'b0;
            known38686_exact_seen_i <= 1'b0;
            known38686_range_seen_i <= 1'b0;
            known38686_valid_i <= 1'b0;
            known38686_bank_i <= 3'd0;
            known38686_channel_i <= 4'd0;
            known38686_state_i <= 4'd0;
            known38686_cur_high_i <= 16'd0;
            known38686_cur_low_i <= 8'd0;
            ch1_ctrl_write_seen_i <= 1'b0;
            mode9_overflow_seen_i <= 1'b0;
            rom_range_group_i <= 8'd0;
            rom_range_group2_i <= 8'd0;
            ch3_rom_range_i <= 8'd0;
            audio_nonzero_count_i <= 16'd0;
            audio_abs_peak_i <= 16'd0;
            last_audio_l_i <= 16'sd0;
            last_audio_r_i <= 16'sd0;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
            lab_c0_sb_debug_i <= 16'd0;
            lab_c0_so_debug_i <= 16'sd0;
            lab_c0_lo_debug_i <= 16'sd0;
            lab_c0_mo_debug_i <= 16'sd0;
            lab_c0_mux_err_i <= 16'd0;
            lab_jt_cpu_write_count_i <= 16'd0;
            lab_jt_rom_request_count_i <= 16'd0;
            lab_jt_rom_addr_change_count_i <= 16'd0;
            lab_jt_payload_match_count_i <= 16'd0;
            lab_jt_payload_miss_count_i <= 16'd0;
            lab_jt_rom_ok_count_i <= 16'd0;
	            lab_jt_rom_nonzero_count_i <= 16'd0;
	            lab_jt_rom_non80_count_i <= 16'd0;
	            lab_jt_rom_changed_count_i <= 16'd0;
	            lab_jt_rom_ok_while_cs_count_i <= 16'd0;
	            lab_jt_sample_strobe_count_i <= 16'd0;
	            lab_jt_raw_output_nonzero_count_i <= 16'd0;
	            lab_jt_output_nonzero_count_i <= 16'd0;
		            lab_jt_last_cpu_write_i <= 16'd0;
		            lab_jt_last_rom_addr_i <= 19'd0;
		            lab_jt_last_payload_index_i <= 19'd0;
		            lab_jt_first_rom_addr_i <= 19'd0;
		            lab_jt_first_ch3_rom_addr_i <= 19'd0;
		            lab_jt_max_rom_addr_i <= 19'd0;
		            lab_jt_last_rom_data_i <= 8'd0;
		            lab_jt_last_non80_rom_addr_i <= 19'd0;
		            lab_jt_last_non80_payload_index_i <= 19'd0;
		            lab_jt_first_non80_rom_data_i <= 8'h80;
		            lab_jt_last_non80_rom_data_i <= 8'h80;
		            lab_jt_block2_hit_count_i <= 16'd0;
		            lab_jt_first_block2_rom_addr_i <= 19'd0;
		            lab_jt_first_block2_payload_index_i <= 19'd0;
		            lab_jt_first_block2_rom_data_i <= 8'd0;
		            lab_jt_last_payload_block_i <= 3'd0;
		            lab_jt_last_payload_match_i <= 1'b0;
		            lab_jt_last_non80_payload_block_i <= 3'd0;
		            lab_jt_last_non80_payload_match_i <= 1'b0;
		            lab_jt_first_output_l_i <= 16'sd0;
		            lab_jt_first_output_r_i <= 16'sd0;
		            lab_jt_last_output_l_i <= 16'sd0;
		            lab_jt_last_output_r_i <= 16'sd0;
	            lab_jt_cur_write_count_i <= 16'd0;
	            lab_jt_end_write_count_i <= 16'd0;
	            lab_jt_delta_write_count_i <= 16'd0;
	            lab_jt_vol_write_count_i <= 16'd0;
	            lab_jt_ctrl_write_count_i <= 16'd0;
	            lab_jt_other_write_count_i <= 16'd0;
	            lab_jt_cen_write_count_i <= 16'd0;
	            lab_jt_ch3_cur_mid_i <= 8'd0;
	            lab_jt_ch3_cur_high_i <= 8'd0;
	            lab_jt_ch3_end_i <= 8'd0;
	            lab_jt_ch3_delta_i <= 8'd0;
	            lab_jt_ch3_vol_l_i <= 8'd0;
	            lab_jt_ch3_vol_r_i <= 8'd0;
	            lab_jt_ch3_ctrl_raw_i <= 8'd0;
	            lab_jt_ch3_ctrl_jt_i <= 8'd0;
		            lab_jt_seen_cpu_write_i <= 1'b0;
	            lab_jt_seen_rom_cs_i <= 1'b0;
	            lab_jt_seen_first_rom_i <= 1'b0;
	            lab_jt_seen_first_ch3_rom_i <= 1'b0;
	            lab_jt_seen_first_block2_i <= 1'b0;
	            lab_jt_seen_first_block2_data_i <= 1'b0;
	            lab_jt_seen_payload_match_i <= 1'b0;
	            lab_jt_seen_rom_ok_i <= 1'b0;
	            lab_jt_seen_rom_nonzero_i <= 1'b0;
		            lab_jt_seen_rom_non80_i <= 1'b0;
		            lab_jt_seen_first_output_i <= 1'b0;
		            lab_jt_seen_output_nonzero_i <= 1'b0;
		            lab_jt_seen_first_non80_pr_i <= 1'b0;
		            lab_jt_seen_first_nonzero_mv_i <= 1'b0;
		            lab_jt_rom_data_hold_i <= 8'h80;
		            lab_jt_rom_data_hold_d_i <= 8'h80;
		            lab_jt_rom_data_hold_valid_i <= 1'b0;
		            lab_jt_rom_data_hold_valid_d_i <= 1'b0;
		            lab_jt_rom_data_latch_count_i <= 16'd0;
		            lab_jt_rom_neutral_while_cs_count_i <= 16'd0;
		            lab_jt_rom_repeat_count_i <= 16'd0;
		            lab_jt_rom_hold_cycle_count_i <= 16'd0;
		            lab_jt_sample_nonneutral_count_i <= 16'd0;
		            lab_jt_first_non80_pr_i <= 16'h8000;
		            lab_jt_last_non80_pr_i <= 16'h8000;
		            lab_jt_first_nonzero_mv_i <= 16'd0;
		            lab_jt_last_nonzero_mv_i <= 16'd0;
		            lab_jt_max_abs_mv_i <= 16'd0;
`endif
            shadow_decode_i <= 16'd0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
            c0_capture_write_count_i <= 16'd0;
            c0_capture_last_addr_i <= 16'd0;
            c0_capture_last_data_i <= 16'd0;
            c0_capture_channel_activity_i <= 16'd0;
            c0_capture_ch3_cur_low_i <= 8'd0;
            c0_capture_ch3_cur_mid_i <= 8'd0;
            c0_capture_ch3_cur_high_i <= 8'd0;
            c0_capture_ch3_loop_mid_i <= 8'd0;
            c0_capture_ch3_loop_high_i <= 8'd0;
            c0_capture_ch3_end_i <= 8'd0;
            c0_capture_ch3_delta_i <= 8'd0;
            c0_capture_ch3_vol_l_i <= 8'd0;
            c0_capture_ch3_vol_r_i <= 8'd0;
            c0_capture_ch3_ctrl_i <= 8'd0;
            c0_capture_ch3_ctrl_ext_i <= 8'd0;
            c0_capture_ch3_start_count_i <= 16'd0;
`endif
            for (int unsigned i = 0; i < 256; i = i + 1) begin
                shadow_ram[i] <= 8'd0;
            end
        end else begin
            core_rom_cs_d <= core_rom_cs;
            core_rom_cs_d2 <= core_rom_cs_d;
            core_rom_addr_d <= core_rom_addr;
            mapped_rom_addr_d <= mapped_rom_addr;
            mapped_rom_addr_d2 <= mapped_rom_addr_d;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
            if ((smoke_variant_d_i != smoke_variant_active) ||
                (smoke_source_loaded_d_i != smoke_source_loaded)) begin
                smoke_payload_addr_i <= smoke_payload_base;
                smoke_payload_div_count_i <= 3'd0;
                smoke_variant_d_i <= smoke_variant_active;
                smoke_source_loaded_d_i <= smoke_source_loaded;
            end else if (ch3_rom_request_event) begin
                if ((smoke_step_divider <= 3'd1) ||
                    (smoke_payload_div_count_i >= (smoke_step_divider - 3'd1))) begin
                    smoke_payload_div_count_i <= 3'd0;
                    if ((smoke_payload_addr_i >= smoke_payload_last) ||
                        (smoke_payload_next_addr > smoke_payload_last)) begin
                        smoke_payload_addr_i <= smoke_payload_base;
                    end else begin
                        smoke_payload_addr_i <= smoke_payload_next_addr;
                    end
                end else begin
                    smoke_payload_div_count_i <= smoke_payload_div_count_i + 3'd1;
                end
            end
`endif
            if (core_rom_cs && (core_rom_addr >= 19'h30000)) begin
                request_raw_rom_addr_i <= core_rom_addr;
                request_mapped_rom_addr_i <= mapped_rom_addr;
                request_preload_addr_valid_i <= preload_rom_addr_valid;
            end
            preload_rom_data_d <= preload_rom_data;
            preload_rom_data_d2 <= preload_rom_data_d;
            preload_rom_addr_valid_d <= preload_rom_addr_valid;
            preload_rom_addr_valid_d2 <= preload_rom_addr_valid_d;
            core_cpu_cs_d <= core_cpu_cs;
            cpu_write_pulse <= 1'b0;
            if (cpu_write_pending) begin
                cpu_write_pulse <= 1'b1;
                cpu_write_pending <= 1'b0;
            end
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
            if (loaded_payload_clear) begin
                c0_capture_write_count_i <= 16'd0;
                c0_capture_last_addr_i <= 16'd0;
                c0_capture_last_data_i <= 16'd0;
                c0_capture_channel_activity_i <= 16'd0;
                c0_capture_ch3_cur_low_i <= 8'd0;
                c0_capture_ch3_cur_mid_i <= 8'd0;
                c0_capture_ch3_cur_high_i <= 8'd0;
                c0_capture_ch3_loop_mid_i <= 8'd0;
                c0_capture_ch3_loop_high_i <= 8'd0;
                c0_capture_ch3_end_i <= 8'd0;
                c0_capture_ch3_delta_i <= 8'd0;
                c0_capture_ch3_vol_l_i <= 8'd0;
                c0_capture_ch3_vol_r_i <= 8'd0;
                c0_capture_ch3_ctrl_i <= 8'd0;
                c0_capture_ch3_ctrl_ext_i <= 8'd0;
                c0_capture_ch3_start_count_i <= 16'd0;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                lab_jt_cpu_write_count_i <= 16'd0;
                lab_jt_rom_request_count_i <= 16'd0;
                lab_jt_rom_addr_change_count_i <= 16'd0;
                lab_jt_payload_match_count_i <= 16'd0;
                lab_jt_payload_miss_count_i <= 16'd0;
                lab_jt_rom_ok_count_i <= 16'd0;
	                lab_jt_rom_nonzero_count_i <= 16'd0;
	                lab_jt_rom_non80_count_i <= 16'd0;
	                lab_jt_rom_changed_count_i <= 16'd0;
	                lab_jt_rom_ok_while_cs_count_i <= 16'd0;
	                lab_jt_sample_strobe_count_i <= 16'd0;
	                lab_jt_raw_output_nonzero_count_i <= 16'd0;
	                lab_jt_output_nonzero_count_i <= 16'd0;
		                lab_jt_last_cpu_write_i <= 16'd0;
		                lab_jt_last_rom_addr_i <= 19'd0;
		                lab_jt_last_payload_index_i <= 19'd0;
		                lab_jt_first_rom_addr_i <= 19'd0;
		                lab_jt_first_ch3_rom_addr_i <= 19'd0;
		                lab_jt_max_rom_addr_i <= 19'd0;
		                lab_jt_last_rom_data_i <= 8'd0;
		                lab_jt_last_non80_rom_addr_i <= 19'd0;
		                lab_jt_last_non80_payload_index_i <= 19'd0;
		                lab_jt_first_non80_rom_data_i <= 8'h80;
		                lab_jt_last_non80_rom_data_i <= 8'h80;
		                lab_jt_block2_hit_count_i <= 16'd0;
		                lab_jt_first_block2_rom_addr_i <= 19'd0;
		                lab_jt_first_block2_payload_index_i <= 19'd0;
		                lab_jt_first_block2_rom_data_i <= 8'd0;
		                lab_jt_last_payload_block_i <= 3'd0;
		                lab_jt_last_payload_match_i <= 1'b0;
		                lab_jt_last_non80_payload_block_i <= 3'd0;
		                lab_jt_last_non80_payload_match_i <= 1'b0;
		                lab_jt_first_output_l_i <= 16'sd0;
		                lab_jt_first_output_r_i <= 16'sd0;
		                lab_jt_last_output_l_i <= 16'sd0;
		                lab_jt_last_output_r_i <= 16'sd0;
	                lab_jt_cur_write_count_i <= 16'd0;
	                lab_jt_end_write_count_i <= 16'd0;
	                lab_jt_delta_write_count_i <= 16'd0;
	                lab_jt_vol_write_count_i <= 16'd0;
	                lab_jt_ctrl_write_count_i <= 16'd0;
	                lab_jt_other_write_count_i <= 16'd0;
	                lab_jt_cen_write_count_i <= 16'd0;
	                lab_jt_ch3_cur_mid_i <= 8'd0;
	                lab_jt_ch3_cur_high_i <= 8'd0;
	                lab_jt_ch3_end_i <= 8'd0;
	                lab_jt_ch3_delta_i <= 8'd0;
	                lab_jt_ch3_vol_l_i <= 8'd0;
	                lab_jt_ch3_vol_r_i <= 8'd0;
	                lab_jt_ch3_ctrl_raw_i <= 8'd0;
		                lab_jt_ch3_ctrl_jt_i <= 8'd0;
		                lab_jt_seen_cpu_write_i <= 1'b0;
		                lab_jt_seen_rom_cs_i <= 1'b0;
		                lab_jt_seen_first_rom_i <= 1'b0;
		                lab_jt_seen_first_ch3_rom_i <= 1'b0;
		                lab_jt_seen_first_block2_i <= 1'b0;
		                lab_jt_seen_first_block2_data_i <= 1'b0;
		                lab_jt_seen_payload_match_i <= 1'b0;
		                lab_jt_seen_rom_ok_i <= 1'b0;
		                lab_jt_seen_rom_nonzero_i <= 1'b0;
				                lab_jt_seen_rom_non80_i <= 1'b0;
				                lab_jt_seen_first_output_i <= 1'b0;
				                lab_jt_seen_output_nonzero_i <= 1'b0;
				                lab_jt_seen_first_non80_pr_i <= 1'b0;
				                lab_jt_seen_first_nonzero_mv_i <= 1'b0;
			                lab_jt_rom_data_hold_i <= 8'h80;
			                lab_jt_rom_data_hold_d_i <= 8'h80;
			                lab_jt_rom_data_hold_valid_i <= 1'b0;
			                lab_jt_rom_data_hold_valid_d_i <= 1'b0;
			                lab_jt_rom_data_latch_count_i <= 16'd0;
			                lab_jt_rom_neutral_while_cs_count_i <= 16'd0;
			                lab_jt_rom_repeat_count_i <= 16'd0;
			                lab_jt_rom_hold_cycle_count_i <= 16'd0;
			                lab_jt_sample_nonneutral_count_i <= 16'd0;
			                lab_jt_first_non80_pr_i <= 16'h8000;
			                lab_jt_last_non80_pr_i <= 16'h8000;
			                lab_jt_first_nonzero_mv_i <= 16'd0;
			                lab_jt_last_nonzero_mv_i <= 16'd0;
			                lab_jt_max_abs_mv_i <= 16'd0;
`endif
            end else if (segapcm_cmd_valid) begin
                if (c0_capture_write_count_i != 16'hffff) begin
                    c0_capture_write_count_i <=
                        c0_capture_write_count_i + 16'd1;
                end
                c0_capture_last_addr_i <= {8'd0, mapped_cpu_addr};
                c0_capture_last_data_i <= {8'd0, segapcm_cmd_data};
                c0_capture_channel_activity_i[mapped_cpu_addr[6:3]] <= 1'b1;
                if (c0_capture_ch3_start_pulse_i &&
                    (c0_capture_ch3_start_count_i != 16'hffff)) begin
                    c0_capture_ch3_start_count_i <=
                        c0_capture_ch3_start_count_i + 16'd1;
                end
                unique case (mapped_cpu_addr)
                    8'h18: c0_capture_ch3_cur_low_i <= segapcm_cmd_data;
                    8'h1a: c0_capture_ch3_vol_l_i <= segapcm_cmd_data;
                    8'h1b: c0_capture_ch3_vol_r_i <= segapcm_cmd_data;
                    8'h1c: c0_capture_ch3_loop_mid_i <= segapcm_cmd_data;
                    8'h1d: c0_capture_ch3_loop_high_i <= segapcm_cmd_data;
                    8'h1e: c0_capture_ch3_end_i <= segapcm_cmd_data;
                    8'h1f: c0_capture_ch3_delta_i <= segapcm_cmd_data;
                    8'h9c: c0_capture_ch3_cur_mid_i <= segapcm_cmd_data;
                    8'h9d: c0_capture_ch3_cur_high_i <= segapcm_cmd_data;
                    8'h9e: c0_capture_ch3_ctrl_i <= segapcm_cmd_data;
                    8'h9f: c0_capture_ch3_ctrl_ext_i <= segapcm_cmd_data;
                    default: begin end
                endcase
            end
`endif
            if (segapcm_cmd_valid) begin
                latched_cpu_addr <= mapped_cpu_addr;
                latched_cpu_data <= segapcm_cmd_data;
                latched_raw_addr <= segapcm_cmd_addr;
                cpu_write_pending <= 1'b1;
            end
            if (core_cpu_cs) begin
                if (latched_cpu_addr == 8'h8e) begin
                    ch1_ctrl_write_seen_i <= 1'b1;
                    first_after_ch1_ctrl_pending_i <= 1'b1;
                    early_after_ch1_ctrl_pending_i <= 1'b1;
                    if (!latched_cpu_data[0]) begin
                        active_after_ch1_ctrl_pending_i <= 1'b1;
                    end
                    rom_range_group_i[5] <= 1'b1;
                end
                shadow_ram[latched_cpu_addr] <= latched_cpu_data;
                shadow_decode_i <= {
                    4'he,
                    latched_cpu_addr[7],
                    latched_cpu_addr[6:3],
                    latched_cpu_addr[2:0],
                    latched_cpu_data[3:0]
                };
                if (core_write_count_i != 16'hffff) begin
                    core_write_count_i <= core_write_count_i + 16'd1;
                end
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                if (smoke_c0_jt_backend) begin
                    lab_jt_seen_cpu_write_i <= 1'b1;
                    lab_jt_last_cpu_write_i <= {latched_cpu_addr, lab_jt_cpu_data};
	                    if (lab_jt_cpu_write_count_i != 16'hffff) begin
	                        lab_jt_cpu_write_count_i <=
	                            lab_jt_cpu_write_count_i + 16'd1;
	                    end
	                    if (core_cpu_cs && segapcm_cen &&
	                        (lab_jt_cen_write_count_i != 16'hffff)) begin
	                        lab_jt_cen_write_count_i <=
	                            lab_jt_cen_write_count_i + 16'd1;
	                    end
	                    if (lab_jt_write_cur) begin
	                        if (lab_jt_cur_write_count_i != 16'hffff) begin
	                            lab_jt_cur_write_count_i <=
	                                lab_jt_cur_write_count_i + 16'd1;
	                        end
	                    end else if (lab_jt_write_end) begin
	                        if (lab_jt_end_write_count_i != 16'hffff) begin
	                            lab_jt_end_write_count_i <=
	                                lab_jt_end_write_count_i + 16'd1;
	                        end
	                    end else if (lab_jt_write_delta) begin
	                        if (lab_jt_delta_write_count_i != 16'hffff) begin
	                            lab_jt_delta_write_count_i <=
	                                lab_jt_delta_write_count_i + 16'd1;
	                        end
	                    end else if (lab_jt_write_vol) begin
	                        if (lab_jt_vol_write_count_i != 16'hffff) begin
	                            lab_jt_vol_write_count_i <=
	                                lab_jt_vol_write_count_i + 16'd1;
	                        end
	                    end else if (lab_jt_write_ctrl) begin
	                        if (lab_jt_ctrl_write_count_i != 16'hffff) begin
	                            lab_jt_ctrl_write_count_i <=
	                                lab_jt_ctrl_write_count_i + 16'd1;
	                        end
	                    end else if (lab_jt_other_write_count_i != 16'hffff) begin
	                        lab_jt_other_write_count_i <=
	                            lab_jt_other_write_count_i + 16'd1;
	                    end
	                    if (lab_jt_write_ch == 4'd3) begin
	                        unique case (latched_cpu_addr)
	                            8'h1a: lab_jt_ch3_vol_l_i <= lab_jt_cpu_data;
	                            8'h1b: lab_jt_ch3_vol_r_i <= lab_jt_cpu_data;
	                            8'h1e: lab_jt_ch3_end_i <= lab_jt_cpu_data;
	                            8'h1f: lab_jt_ch3_delta_i <= lab_jt_cpu_data;
	                            8'h9c: lab_jt_ch3_cur_mid_i <= lab_jt_cpu_data;
	                            8'h9d: lab_jt_ch3_cur_high_i <= lab_jt_cpu_data;
	                            8'h9e: begin
	                                lab_jt_ch3_ctrl_raw_i <= latched_cpu_data;
	                                lab_jt_ch3_ctrl_jt_i <= lab_jt_cpu_data;
	                            end
	                            default: begin end
	                        endcase
	                    end
	                end
`endif
            end
            if (core_cpu_cs && segapcm_cen) begin
                if (core_cen_write_count_i != 16'hffff) begin
                    core_cen_write_count_i <= core_cen_write_count_i + 16'd1;
                end
            end
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
	            if (smoke_c0_jt_backend) begin
	                lab_jt_rom_data_hold_d_i <= lab_jt_rom_data_hold_i;
	                lab_jt_rom_data_hold_valid_d_i <= lab_jt_rom_data_hold_valid_i;
	                if (lab_jt_rom_data_hold_valid_i &&
	                    (lab_jt_rom_hold_cycle_count_i != 16'hffff)) begin
	                    lab_jt_rom_hold_cycle_count_i <=
	                        lab_jt_rom_hold_cycle_count_i + 16'd1;
	                end
	                if (lab_jt_rom_cs &&
	                    (lab_jt_rom_data_to_core == 8'h80) &&
	                    (lab_jt_rom_neutral_while_cs_count_i != 16'hffff)) begin
	                    lab_jt_rom_neutral_while_cs_count_i <=
	                        lab_jt_rom_neutral_while_cs_count_i + 16'd1;
	                end
	            end
`endif
            if (rom_request_event) begin
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
	                if (smoke_c0_jt_backend) begin
	                    lab_jt_seen_rom_cs_i <= 1'b1;
	                    lab_jt_last_rom_addr_i <= lab_jt_rom_addr;
	                    lab_jt_last_payload_index_i <= lab_jt_payload_read_index_next;
	                    lab_jt_last_payload_block_i <= lab_jt_payload_block_next;
	                    lab_jt_last_payload_match_i <=
	                        lab_jt_payload_match_valid_next;
	                    if (!lab_jt_seen_first_rom_i) begin
	                        lab_jt_seen_first_rom_i <= 1'b1;
	                        lab_jt_first_rom_addr_i <= lab_jt_rom_addr;
	                    end
	                    if (!lab_jt_seen_first_ch3_rom_i &&
	                        (lab_jt_dbg_bank_channel_state[7:4] == 4'd3)) begin
	                        lab_jt_seen_first_ch3_rom_i <= 1'b1;
	                        lab_jt_first_ch3_rom_addr_i <= lab_jt_rom_addr;
	                    end
	                    if (lab_jt_rom_addr > lab_jt_max_rom_addr_i) begin
	                        lab_jt_max_rom_addr_i <= lab_jt_rom_addr;
	                    end
	                    if (lab_jt_payload_match_valid_next &&
	                        (lab_jt_payload_block_next == 3'd2)) begin
	                        if (lab_jt_block2_hit_count_i != 16'hffff) begin
	                            lab_jt_block2_hit_count_i <=
	                                lab_jt_block2_hit_count_i + 16'd1;
	                        end
	                        if (!lab_jt_seen_first_block2_i) begin
	                            lab_jt_seen_first_block2_i <= 1'b1;
	                            lab_jt_first_block2_rom_addr_i <= lab_jt_rom_addr;
	                            lab_jt_first_block2_payload_index_i <=
	                                lab_jt_payload_read_index_next;
	                        end
	                    end
	                    if (lab_jt_rom_request_count_i != 16'hffff) begin
                        lab_jt_rom_request_count_i <=
                            lab_jt_rom_request_count_i + 16'd1;
                    end
                    if ((lab_jt_rom_addr != lab_jt_last_rom_addr_i) &&
                        (lab_jt_rom_addr_change_count_i != 16'hffff)) begin
                        lab_jt_rom_addr_change_count_i <=
                            lab_jt_rom_addr_change_count_i + 16'd1;
                    end
                    if (lab_jt_payload_match_valid_next) begin
                        lab_jt_seen_payload_match_i <= 1'b1;
                        if (lab_jt_payload_match_count_i != 16'hffff) begin
                            lab_jt_payload_match_count_i <=
                                lab_jt_payload_match_count_i + 16'd1;
                        end
                    end else if (lab_jt_payload_miss_count_i != 16'hffff) begin
                        lab_jt_payload_miss_count_i <=
                            lab_jt_payload_miss_count_i + 16'd1;
                    end
                end else begin
`endif
                last_rom_request_addr_i <= core_rom_addr;
                rom_range_group_i[7] <= 1'b1;
                if ((core_rom_addr >= 19'h38600) &&
                    (core_rom_addr < 19'h38700)) begin
                    known38686_range_seen_i <= 1'b1;
                end
                if (core_rom_addr == 19'h38686) begin
                    known38686_exact_seen_i <= 1'b1;
                    known38686_valid_i <= 1'b1;
                    known38686_bank_i <= core_dbg_bank_channel_state[10:8];
                    known38686_channel_i <= core_dbg_bank_channel_state[7:4];
                    known38686_state_i <= core_dbg_bank_channel_state[3:0];
                    known38686_cur_high_i <= core_dbg_cur_addr_high;
                    known38686_cur_low_i <= core_dbg_cur_addr_low_state[15:8];
                end
                if ((core_rom_addr >= 19'h30020) &&
                    (core_rom_addr < 19'h30040)) begin
                    rom_range_group2_i[0] <= 1'b1;
                end
                if ((core_rom_addr >= 19'h30026) &&
                    (core_rom_addr < 19'h30030)) begin
                    rom_range_group2_i[1] <= 1'b1;
                end
                if ((core_rom_addr >= 19'h30000) &&
                    (core_rom_addr < 19'h30100)) begin
                    rom_range_group2_i[2] <= 1'b1;
                end
                if ((core_rom_addr >= 19'h38600) &&
                    (core_rom_addr < 19'h38700)) begin
                    rom_range_group2_i[3] <= 1'b1;
                end
                if ((core_rom_addr >= 19'h38000) &&
                    (core_rom_addr < 19'h39000)) begin
                    rom_range_group2_i[4] <= 1'b1;
                end
                if ((core_rom_addr >= 19'h30000) &&
                    (core_rom_addr < 19'h32600)) begin
                    rom_range_group2_i[5] <= 1'b1;
                end
                if ((core_rom_addr >= 19'h32600) &&
                    (core_rom_addr < 19'h38000)) begin
                    rom_range_group_i[0] <= 1'b1;
                end
                if ((core_rom_addr >= 19'h38000) &&
                    (core_rom_addr < 19'h39000)) begin
                    rom_range_group_i[1] <= 1'b1;
                end
                if ((core_rom_addr >= 19'h30000) &&
                    (core_rom_addr < 19'h32600)) begin
                    rom_range_group_i[2] <= 1'b1;
                end
                if ((core_rom_addr >= 19'h38600) &&
                    (core_rom_addr < 19'h38700)) begin
                    rom_range_group_i[3] <= 1'b1;
                end
                if (ROM_ADDR_MAP_MODE == 9 &&
                    (core_rom_addr >= 19'h38000) &&
                    (core_rom_addr < 19'h38700)) begin
                    mode9_overflow_seen_i <= 1'b1;
                    rom_range_group_i[6] <= 1'b1;
                end
                if (early_after_ch1_ctrl_pending_i) begin
                    early_after_ch1_ctrl_addr_i <= core_rom_addr;
                    early_after_ch1_ctrl_pending_i <= 1'b0;
                    early_after_ch1_ctrl_seen_i <= 1'b1;
                    if ((core_rom_addr >= 19'h30000) &&
                        (core_rom_addr < 19'h30100)) begin
                        rom_range_group2_i[6] <= 1'b1;
                    end
                    if ((core_rom_addr >= 19'h38600) &&
                        (core_rom_addr < 19'h38700)) begin
                        rom_range_group2_i[7] <= 1'b1;
                    end
                end
                if (active_after_ch1_ctrl_pending_i) begin
                    active_after_ch1_ctrl_addr_i <= core_rom_addr;
                    active_after_ch1_ctrl_pending_i <= 1'b0;
                    active_after_ch1_ctrl_seen_i <= 1'b1;
                end
                if (first_after_ch1_ctrl_pending_i &&
                    (core_rom_addr != 19'd0)) begin
                    first_after_ch1_ctrl_addr_i <= core_rom_addr;
                    first_after_ch1_ctrl_pending_i <= 1'b0;
                    first_after_ch1_ctrl_seen_i <= 1'b1;
                    rom_range_group_i[4] <= 1'b1;
                end
                if (rom_activity_count_i != 16'hffff) begin
                    rom_activity_count_i <= rom_activity_count_i + 16'd1;
                end
                if (!raw_rom_minmax_seen_i) begin
                    raw_rom_min_addr_i <= core_rom_addr;
                    raw_rom_max_addr_i <= core_rom_addr;
                    raw_rom_minmax_seen_i <= 1'b1;
                end else begin
                    if (core_rom_addr < raw_rom_min_addr_i) begin
                        raw_rom_min_addr_i <= core_rom_addr;
                    end
                    if (core_rom_addr > raw_rom_max_addr_i) begin
                        raw_rom_max_addr_i <= core_rom_addr;
                    end
                end
                if (ch3_rom_request_event) begin
                    ch3_last_rom_request_addr_i <= core_rom_addr;
                    ch3_rom_range_i[0] <= 1'b1;
                    if (!ch3_raw_rom_minmax_seen_i) begin
                        ch3_raw_rom_min_addr_i <= core_rom_addr;
                        ch3_raw_rom_max_addr_i <= core_rom_addr;
                        ch3_raw_rom_minmax_seen_i <= 1'b1;
                    end else begin
                        if (core_rom_addr < ch3_raw_rom_min_addr_i) begin
                            ch3_raw_rom_min_addr_i <= core_rom_addr;
                        end
                        if (core_rom_addr > ch3_raw_rom_max_addr_i) begin
                            ch3_raw_rom_max_addr_i <= core_rom_addr;
                        end
                    end
                    if ((core_rom_addr >= 19'h30000) &&
                        (core_rom_addr < 19'h35a00)) begin
                        ch3_rom_range_i[1] <= 1'b1;
                    end
                    if ((core_rom_addr >= 19'h32600) &&
                        (core_rom_addr < 19'h38000)) begin
                        ch3_rom_range_i[2] <= 1'b1;
                    end
                    if ((core_rom_addr >= 19'h30020) &&
                        (core_rom_addr < 19'h30040)) begin
                        ch3_rom_range_i[3] <= 1'b1;
                    end
                    if ((core_rom_addr >= 19'h32600) &&
                        (core_rom_addr < 19'h32700)) begin
                        ch3_rom_range_i[4] <= 1'b1;
                    end
                    if ((core_rom_addr >= 19'h30026) &&
                        (core_rom_addr < 19'h30030)) begin
                        ch3_rom_range_i[5] <= 1'b1;
                    end
                    if ((core_rom_addr >= 19'h32600) &&
                        (core_rom_addr < 19'h32610)) begin
                        ch3_rom_range_i[6] <= 1'b1;
                    end
                end
                if (preload_rom_addr_valid) begin
                    if (rom_range_hit_count_i != 16'hffff) begin
                        rom_range_hit_count_i <= rom_range_hit_count_i + 16'd1;
                    end
                end else begin
                    if (rom_range_miss_count_i != 16'hffff) begin
                        rom_range_miss_count_i <= rom_range_miss_count_i + 16'd1;
                    end
                end
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                end
`endif
            end
            if (rom_return_event) begin
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
	                if (smoke_c0_jt_backend) begin
	                    lab_jt_seen_rom_ok_i <= 1'b1;
	                    if ((core_rom_data == lab_jt_last_rom_data_i) &&
	                        (lab_jt_rom_repeat_count_i != 16'hffff)) begin
	                        lab_jt_rom_repeat_count_i <=
	                            lab_jt_rom_repeat_count_i + 16'd1;
	                    end
	                    lab_jt_last_rom_data_i <= core_rom_data;
	                    lab_jt_rom_data_hold_i <= core_rom_data;
	                    lab_jt_rom_data_hold_valid_i <= 1'b1;
                    if (lab_jt_rom_data_latch_count_i != 16'hffff) begin
                        lab_jt_rom_data_latch_count_i <=
                            lab_jt_rom_data_latch_count_i + 16'd1;
                    end
                    if (lab_jt_rom_ok_count_i != 16'hffff) begin
                        lab_jt_rom_ok_count_i <= lab_jt_rom_ok_count_i + 16'd1;
                    end
                    if ((core_rom_cs || core_rom_cs_d || core_rom_cs_d2) &&
                        (lab_jt_rom_ok_while_cs_count_i != 16'hffff)) begin
                        lab_jt_rom_ok_while_cs_count_i <=
                            lab_jt_rom_ok_while_cs_count_i + 16'd1;
                    end
	                    if (core_rom_data != 8'd0) begin
	                        lab_jt_seen_rom_nonzero_i <= 1'b1;
	                        if (lab_jt_rom_nonzero_count_i != 16'hffff) begin
	                            lab_jt_rom_nonzero_count_i <=
	                                lab_jt_rom_nonzero_count_i + 16'd1;
	                        end
	                    end
	                    if (lab_jt_last_payload_match_i &&
	                        (lab_jt_last_payload_block_i == 3'd2) &&
	                        !lab_jt_seen_first_block2_data_i) begin
	                        lab_jt_seen_first_block2_data_i <= 1'b1;
	                        lab_jt_first_block2_rom_data_i <= core_rom_data;
	                    end
		                    if (core_rom_data != 8'h80) begin
	                        lab_jt_seen_rom_non80_i <= 1'b1;
	                        lab_jt_last_non80_rom_addr_i <= lab_jt_last_rom_addr_i;
	                        lab_jt_last_non80_payload_index_i <=
	                            lab_jt_last_payload_index_i;
	                        lab_jt_last_non80_payload_block_i <=
	                            lab_jt_last_payload_block_i;
	                        lab_jt_last_non80_payload_match_i <=
	                            lab_jt_last_payload_match_i;
	                        lab_jt_last_non80_rom_data_i <= core_rom_data;
                        if (!lab_jt_seen_rom_non80_i) begin
                            lab_jt_first_non80_rom_data_i <= core_rom_data;
                        end
                        if (lab_jt_rom_non80_count_i != 16'hffff) begin
                            lab_jt_rom_non80_count_i <=
                                lab_jt_rom_non80_count_i + 16'd1;
                        end
                    end
                    if ((core_rom_data != lab_jt_last_rom_data_i) &&
                        (lab_jt_rom_changed_count_i != 16'hffff)) begin
                        lab_jt_rom_changed_count_i <=
                            lab_jt_rom_changed_count_i + 16'd1;
                    end
                end else begin
`endif
                if (rom_core_ok_count_i != 16'hffff) begin
                    rom_core_ok_count_i <= rom_core_ok_count_i + 16'd1;
                end
                if (preload_rom_ok && (rom_read_valid_count_i != 16'hffff)) begin
                    rom_read_valid_count_i <= rom_read_valid_count_i + 16'd1;
                end
                if (fallback_used && (rom_fallback_count_i != 16'hffff)) begin
                    rom_fallback_count_i <= rom_fallback_count_i + 16'd1;
                end
                last_return_mapped_addr_i <= selected_mapped_rom_addr;
                last_return_data_i <= core_rom_data;
                return_data_history3_i <= return_data_history2_i;
                return_data_history2_i <= return_data_history1_i;
                return_data_history1_i <= return_data_history0_i;
                return_data_history0_i <= core_rom_data;
                if (core_rom_data != 8'd0) begin
                    if (rom_return_nonzero_count_i != 16'hffff) begin
                        rom_return_nonzero_count_i <=
                            rom_return_nonzero_count_i + 16'd1;
                    end
                end
                if (core_rom_data == 8'h80) begin
                    if (rom_return_neutral_count_i != 16'hffff) begin
                        rom_return_neutral_count_i <=
                            rom_return_neutral_count_i + 16'd1;
                    end
                end
                if (core_rom_data != last_return_data_i) begin
                    if (rom_return_change_count_i != 16'hffff) begin
                        rom_return_change_count_i <=
                            rom_return_change_count_i + 16'd1;
                    end
                end
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                end
`endif
            end
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
	            if (smoke_c0_jt_backend) begin
	                lab_jt_last_output_l_i <= lab_jt_snd_left;
	                lab_jt_last_output_r_i <= lab_jt_snd_right;
	                if (lab_jt_dbg_pcm_raw_cv[15:8] != 8'h80) begin
	                    if (!lab_jt_seen_first_non80_pr_i) begin
	                        lab_jt_seen_first_non80_pr_i <= 1'b1;
	                        lab_jt_first_non80_pr_i <= lab_jt_dbg_pcm_raw_cv;
	                    end
	                    lab_jt_last_non80_pr_i <= lab_jt_dbg_pcm_raw_cv;
	                end
	                if (lab_jt_dbg_mul_data != 16'd0) begin
	                    if (!lab_jt_seen_first_nonzero_mv_i) begin
	                        lab_jt_seen_first_nonzero_mv_i <= 1'b1;
	                        lab_jt_first_nonzero_mv_i <= lab_jt_dbg_mul_data;
	                    end
	                    lab_jt_last_nonzero_mv_i <= lab_jt_dbg_mul_data;
	                end
	                if (lab_jt_dbg_mul_abs > lab_jt_max_abs_mv_i) begin
	                    lab_jt_max_abs_mv_i <= lab_jt_dbg_mul_abs;
	                end
	                if (lab_jt_sample &&
	                    (lab_jt_sample_strobe_count_i != 16'hffff)) begin
	                    lab_jt_sample_strobe_count_i <=
	                        lab_jt_sample_strobe_count_i + 16'd1;
	                end
	                if (lab_jt_sample &&
	                    (lab_jt_dbg_pcm_raw_cv[15:8] != 8'h80) &&
	                    (lab_jt_sample_nonneutral_count_i != 16'hffff)) begin
	                    lab_jt_sample_nonneutral_count_i <=
	                        lab_jt_sample_nonneutral_count_i + 16'd1;
	                end
		                if (((lab_jt_snd_left != 16'sd0) ||
		                     (lab_jt_snd_right != 16'sd0)) &&
	                    (lab_jt_raw_output_nonzero_count_i != 16'hffff)) begin
	                    lab_jt_seen_output_nonzero_i <= 1'b1;
	                    if (!lab_jt_seen_first_output_i) begin
	                        lab_jt_seen_first_output_i <= 1'b1;
	                        lab_jt_first_output_l_i <= lab_jt_snd_left;
	                        lab_jt_first_output_r_i <= lab_jt_snd_right;
	                    end
	                    lab_jt_raw_output_nonzero_count_i <=
	                        lab_jt_raw_output_nonzero_count_i + 16'd1;
                end
            end
`endif
            if (core_sample) begin
                logic [15:0] abs_l;
                logic [15:0] abs_r;
                logic [15:0] abs_now;

                last_audio_l_i <= core_snd_left;
                last_audio_r_i <= core_snd_right;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                if (smoke_c0_jt_backend) begin
                    lab_jt_last_output_l_i <= core_snd_left;
                    lab_jt_last_output_r_i <= core_snd_right;
                end
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                lab_c0_sb_debug_i <=
                    lab_c0_multich_delta_mode ?
                    {lab16_selected_sample_byte, lab16_selected_cv[7:0]} :
                    lab_c0_legacy_ch3_block2_mode ?
                    lab_c0_mame_sb_cv_debug :
                    {8'd0, lab_c0_selected_sample_byte};
                lab_c0_so_debug_i <= lab_c0_actual_output_sample;
                lab_c0_lo_debug_i <= lab_c0_legacy_output_sample;
                lab_c0_mo_debug_i <= lab_c0_multich_output_l_sample;
                if (lab_c0_local_delta_mode &&
                    (lab_c0_actual_output_sample != 16'sd0) &&
                    (lab_c0_legacy_output_sample == 16'sd0) &&
                    (lab_c0_multich_output_l_sample == 16'sd0)) begin
                    lab_c0_mux_err_i[0] <= 1'b1;
                end
                if (lab_c0_legacy_ch3_block2_mode &&
                    (lab_c0_multich_output_l_sample != 16'sd0)) begin
                    lab_c0_mux_err_i[1] <= 1'b1;
                end
                if (lab_c0_multich_delta_mode &&
                    (lab_c0_legacy_output_sample != 16'sd0)) begin
                    lab_c0_mux_err_i[2] <= 1'b1;
                end
`endif
                abs_l = abs16(core_snd_left);
                abs_r = abs16(core_snd_right);
                abs_now = (abs_l > abs_r) ? abs_l : abs_r;
                if (abs_now > audio_abs_peak_i) begin
                    audio_abs_peak_i <= abs_now;
                end
                if (abs_now != 16'd0) begin
                    ch3_rom_range_i[7] <= 1'b1;
                end
                if ((core_snd_left != 16'sd0) ||
                    (core_snd_right != 16'sd0)) begin
                    if (audio_nonzero_count_i != 16'hffff) begin
                        audio_nonzero_count_i <= audio_nonzero_count_i + 16'd1;
                    end
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                    if (smoke_c0_jt_backend) begin
                        lab_jt_seen_output_nonzero_i <= 1'b1;
                        if (lab_jt_output_nonzero_count_i != 16'hffff) begin
                            lab_jt_output_nonzero_count_i <=
                                lab_jt_output_nonzero_count_i + 16'd1;
                        end
                    end
`endif
                end
            end
        end
    end

`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    always_ff @(posedge clk) begin
        if (reset || loaded_payload_clear) begin
            loaded_ddr_rd_req <= 1'b0;
            loaded_ddr_rd_addr <= 19'd0;
            smoke_ddr_audio_byte_hold_i <= 8'h80;
            smoke_ddr_audio_index_hold_i <= 16'd0;
            smoke_ddr_audio_valid_seen_i <= 1'b0;
            smoke_ddr_audio_data_ok_i <= 1'b0;
            smoke_ddr_audio_update_count_i <= 16'd0;
            smoke_ddr_read_index_i <= 19'd0;
            smoke_ddr_read_div_i <= 16'd0;
            smoke_ddr_read_req_count_i <= 16'd0;
            smoke_ddr_read_valid_count_i <= 16'd0;
            smoke_ddr_read_blocked_count_i <= 16'd0;
            smoke_ddr_read_last_index_i <= 16'd0;
            smoke_ddr_read_nonzero_count_i <= 16'd0;
            smoke_ddr_read_change_count_i <= 16'd0;
            smoke_ddr_read_zero_count_i <= 16'd0;
            smoke_ddr_scan_index_i <= 16'd0;
            smoke_ddr_scan_first_nonzero_index_i <= 16'd0;
            smoke_ddr_scan_last_nonzero_index_i <= 16'd0;
            smoke_ddr_scan_data_i <= 8'd0;
            smoke_ddr_scan_first_nonzero_data_i <= 8'd0;
            smoke_ddr_scan_last_nonzero_data_i <= 8'd0;
            smoke_ddr_scan_done_i <= 1'b0;
            smoke_ddr_scan_found_nonzero_i <= 1'b0;
            smoke_ddr_read_last_data_i <= 8'd0;
            smoke_ddr_read_prev_data_i <= 8'd0;
            smoke_ddr_read_last_nonzero_data_i <= 8'd0;
            smoke_ddr_read_valid_seen_i <= 1'b0;
            smoke_ddr_follow_mode_d_i <= 1'b0;
            smoke_ddr_follow_core_addr_low_i <= 16'd0;
            smoke_ddr_follow_prev_addr_low_i <= 16'd0;
            smoke_ddr_follow_mapped_index_i <= 16'd0;
            smoke_ddr_follow_word_i <= 16'd0;
            smoke_ddr_follow_lane_i <= 16'd0;
            smoke_ddr_follow_flags_i <= 16'hC000;
            smoke_ddr_follow_cs_count_i <= 16'd0;
            smoke_ddr_follow_ok_count_i <= 16'd0;
            smoke_ddr_follow_request_count_i <= 16'd0;
            smoke_ddr_follow_addr_change_count_i <= 16'd0;
            smoke_ddr_follow_payload_offset_i <= 16'd0;
            smoke_ddr_follow_norm_core_i <= 16'd0;
            smoke_ddr_follow_norm_dest_i <= 16'd0;
            smoke_ddr_follow_range_flags_i <= 16'hD000;
            smoke_ddr_follow_po_min_i <= 16'hffff;
            smoke_ddr_follow_po_max_i <= 16'd0;
            smoke_ddr_follow_cr_min_i <= 16'hffff;
            smoke_ddr_follow_cr_max_i <= 16'd0;
            smoke_ddr_follow_ir_rise_count_i <= 16'd0;
            smoke_ddr_follow_ir_fall_count_i <= 16'd0;
            smoke_ddr_follow_cr_at_ir_rise_i <= 16'd0;
            smoke_ddr_follow_cr_at_ir_fall_i <= 16'd0;
            smoke_ddr_follow_po_at_ir_rise_i <= 16'd0;
            smoke_ddr_follow_po_at_ir_fall_i <= 16'd0;
            smoke_ddr_follow_raw_po_max_i <= 16'd0;
            smoke_ddr_follow_eff_mi_max_i <= 16'd0;
            smoke_ddr_follow_po_at_fu_rise_i <= 16'd0;
            smoke_ddr_follow_mi_at_fu_rise_i <= 16'd0;
            smoke_ddr_follow_po_at_ic_fall_i <= 16'd0;
            smoke_ddr_follow_mi_at_ic_fall_i <= 16'd0;
            smoke_ddr_follow_wrap_level_i <= 16'd0;
            smoke_ddr_follow_addr_in_range_i <= 1'b0;
            smoke_ddr_follow_read_in_range_i <= 1'b0;
            smoke_ddr_follow_range_miss_i <= 1'b0;
            smoke_ddr_follow_range_seen_i <= 1'b0;
            smoke_ddr_follow_dest_map_d_i <= 1'b0;
            smoke_ddr_follow_dest_basis_d_i <= 2'd0;
            smoke_ddr_follow_dest_loop_wrap_d_i <= 1'b0;
            smoke_ddr_follow_wrap_count_i <= 16'd0;
            smoke_ddr_c0_pending_i <= 1'b0;
            smoke_ddr_c0_return_valid_i <= 1'b0;
            smoke_ddr_c0_return_in_range_i <= 1'b0;
            smoke_ddr_c0_wait_timeout_seen_i <= 1'b0;
            smoke_ddr_follow_accept_count_i <= 16'd0;
            smoke_ddr_follow_top_request_count_i <= 16'd0;
            smoke_ddr_follow_return_count_i <= 16'd0;
	            smoke_ddr_follow_jt_seen_count_i <= 16'd0;
	            smoke_ddr_follow_mixer_count_i <= 16'd0;
	            smoke_ddr_follow_timeout_count_i <= 16'd0;
	            smoke_ddr_c0_wait_count_i <= 16'd0;
`ifndef MEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE
	            smoke_c0_first_hit_seen_i <= 1'b0;
	            smoke_c0_first_hit_active_i <= 1'b0;
	            smoke_c0_first_hit_capture_count_i <= 4'd0;
	            smoke_c0_first_hit_cv_i <= 16'd0;
	            smoke_c0_first_hit_ad_i <= 16'd0;
	            smoke_c0_first_hit_ec_i <= 16'd0;
	            smoke_c0_first_hit_act_i <= 16'd0;
	            smoke_c0_first_hit_end_seen_i <= 16'd0;
	            smoke_c0_first_hit_flags_i <= 16'd0;
	            smoke_c0_first_hit_done_i <= 1'b0;
	            smoke_c0_first_hit_close_reason_i <= 4'd0;
`endif
	            smoke_c0_probe_req_index_i <= 4'd0;
	            smoke_c0_probe_return_index_i <= 4'd0;
	            smoke_c0_probe_req_live_i <= 1'b0;
	            smoke_c0_probe_pending_i <= 1'b0;
	            smoke_c0_probe_done_i <= 1'b0;
	            smoke_c0_probe_word0_i <= 16'd0;
	            smoke_c0_probe_lane0_i <= 16'd0;
	            smoke_c0_probe_word7_i <= 16'd0;
	            smoke_c0_probe_lane7_i <= 16'd0;
	            smoke_c0_probe_raw_word0_i <= 16'd0;
	            smoke_c0_probe_raw_word6_i <= 16'd0;
	            smoke_c0_write_probe_seen_i <= 16'd0;
`ifndef MEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE
	            for (smoke_c0_first_hit_loop_i = 0;
	                 smoke_c0_first_hit_loop_i < 8;
	                 smoke_c0_first_hit_loop_i = smoke_c0_first_hit_loop_i + 1) begin
	                smoke_c0_first_hit_byte_i[smoke_c0_first_hit_loop_i] <=
	                    8'd0;
	            end
`endif
	            for (smoke_c0_probe_loop_i = 0;
	                 smoke_c0_probe_loop_i < SMOKE_C0_PROBE_BYTES;
	                 smoke_c0_probe_loop_i = smoke_c0_probe_loop_i + 1) begin
	                smoke_c0_probe_byte_i[smoke_c0_probe_loop_i] <= 8'd0;
	            end
	            for (smoke_c0_write_probe_loop_i = 0;
	                 smoke_c0_write_probe_loop_i < SMOKE_C0_PROBE_BYTES;
	                 smoke_c0_write_probe_loop_i =
	                     smoke_c0_write_probe_loop_i + 1) begin
	                smoke_c0_write_probe_byte_i[
	                    smoke_c0_write_probe_loop_i
	                ] <= 8'd0;
	            end
`ifndef MEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE
	            for (smoke_c0_first_hit_loop_i = 0;
	                 smoke_c0_first_hit_loop_i < 4;
	                 smoke_c0_first_hit_loop_i = smoke_c0_first_hit_loop_i + 1) begin
	                smoke_c0_first_hit_pi_i[smoke_c0_first_hit_loop_i] <=
	                    16'd0;
	            end
`endif
	            smoke_type80_table_count_i <= 4'd0;
	            smoke_type80_table_next_base_i <= 19'd0;
            smoke_type80_table_last_dest_i <= 21'd0;
            smoke_type80_table_last_len_i <= 19'd0;
            smoke_type80_table_last_write_index_i <= 4'd0;
            smoke_type80_table_last_write_dest_i <= 21'd0;
            smoke_type80_table_last_write_len_i <= 19'd0;
            smoke_type80_table_last_write_base_i <= 19'd0;
            smoke_type80_table_last_write_valid_i <= 1'b0;
            for (smoke_type80_table_loop_i = 0;
                 smoke_type80_table_loop_i < SMOKE_TYPE80_TABLE_ENTRIES;
                 smoke_type80_table_loop_i = smoke_type80_table_loop_i + 1) begin
                smoke_type80_table_valid_i[smoke_type80_table_loop_i] <= 1'b0;
                smoke_type80_table_dest_i[smoke_type80_table_loop_i] <= 21'd0;
                smoke_type80_table_base_i[smoke_type80_table_loop_i] <= 19'd0;
                smoke_type80_table_len_i[smoke_type80_table_loop_i] <= 19'd0;
            end
        end else begin
            smoke_ddr_audio_data_ok_i <= 1'b0;
            smoke_type80_table_last_write_valid_i <= 1'b0;
            if (smoke_type80_table_new_block) begin
                smoke_type80_table_valid_i[smoke_type80_table_count_i[2:0]] <= 1'b1;
                smoke_type80_table_dest_i[smoke_type80_table_count_i[2:0]] <=
                    loaded_type80_rom_dest[20:0];
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                smoke_type80_table_base_i[smoke_type80_table_count_i[2:0]] <=
                    loaded_payload_wr_addr;
`else
                smoke_type80_table_base_i[smoke_type80_table_count_i[2:0]] <=
                    smoke_type80_table_next_base_i;
`endif
                smoke_type80_table_len_i[smoke_type80_table_count_i[2:0]] <=
                    smoke_type80_payload_len_19;
                smoke_type80_table_next_base_i <=
                    smoke_type80_table_next_base_i + smoke_type80_payload_len_19;
                smoke_type80_table_last_dest_i <= loaded_type80_rom_dest[20:0];
                smoke_type80_table_last_len_i <= smoke_type80_payload_len_19;
                smoke_type80_table_last_write_index_i <= smoke_type80_table_count_i;
                smoke_type80_table_last_write_dest_i <= loaded_type80_rom_dest[20:0];
                smoke_type80_table_last_write_len_i <= smoke_type80_payload_len_19;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                smoke_type80_table_last_write_base_i <= loaded_payload_wr_addr;
`else
                smoke_type80_table_last_write_base_i <= smoke_type80_table_next_base_i;
`endif
                smoke_type80_table_last_write_valid_i <= 1'b1;
                smoke_type80_table_count_i <= smoke_type80_table_count_i + 4'd1;
            end
            if (smoke_c0_write_probe_hit) begin
                smoke_c0_write_probe_byte_i[
                    smoke_c0_write_probe_offset[3:0]
                ] <= loaded_payload_wr_data;
                smoke_c0_write_probe_seen_i[
                    smoke_c0_write_probe_offset[3:0]
                ] <= 1'b1;
            end
            smoke_ddr_follow_mode_d_i <= smoke_ddr_follow_mode;
            smoke_ddr_follow_dest_map_d_i <= smoke_ddr_follow_dest_map;
            smoke_ddr_follow_dest_basis_d_i <= smoke_ddr_follow_dest_basis;
            smoke_ddr_follow_dest_loop_wrap_d_i <=
                smoke_ddr_follow_dest_loop_wrap;
            smoke_ddr_follow_flags_i <= {
                8'hC0,
                smoke_ddr_follow_dest_map,
                smoke_ddr_follow_mode,
                smoke_ddr_audio_active,
                smoke_ddr_follow_range_miss_i,
                smoke_ddr_follow_read_in_range_i,
                loaded_ddr_rd_ready,
                loaded_ddr_rd_valid,
                core_rom_cs,
                core_rom_ok
            };
            smoke_ddr_follow_range_flags_i <= {
                8'hD0,
                smoke_ddr_follow_dest_loop_wrap,
                smoke_ddr_follow_dest_wrap_this_next,
                smoke_ddr_follow_dest_map,
                smoke_ddr_follow_dest_basis,
                smoke_ddr_follow_range_miss_i,
                smoke_ddr_follow_read_in_range_i,
                smoke_ddr_follow_addr_in_range_i
            };
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
            if (smoke_c0_jt_backend && smoke_ddr_c0_return_valid_i) begin
                smoke_ddr_c0_return_valid_i <= 1'b0;
                smoke_ddr_c0_return_in_range_i <= 1'b0;
                if (smoke_ddr_follow_accept_count_i != 16'hffff) begin
                    smoke_ddr_follow_accept_count_i <=
                        smoke_ddr_follow_accept_count_i + 16'd1;
                end
            end else
`endif
            if (core_dbg_smoke_c0_byte_accept) begin
                smoke_ddr_c0_pending_i <= 1'b0;
                smoke_ddr_c0_return_valid_i <= 1'b0;
                smoke_ddr_c0_return_in_range_i <= 1'b0;
                smoke_ddr_c0_wait_count_i <= 16'd0;
                smoke_ddr_c0_wait_timeout_seen_i <= 1'b0;
                if (smoke_ddr_follow_accept_count_i != 16'hffff) begin
                    smoke_ddr_follow_accept_count_i <=
                        smoke_ddr_follow_accept_count_i + 16'd1;
                end
                if (smoke_ddr_follow_jt_seen_count_i != 16'hffff) begin
                    smoke_ddr_follow_jt_seen_count_i <=
                        smoke_ddr_follow_jt_seen_count_i + 16'd1;
                end
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
            end else if (core_sample && smoke_ddr_c0drive_active) begin
                // The lab stub consumes one returned byte per sample tick.
                smoke_ddr_c0_return_valid_i <= 1'b0;
                smoke_ddr_c0_return_in_range_i <= 1'b0;
`endif
            end
`ifndef MEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE
            if (smoke_c0_first_hit_stop) begin
                smoke_c0_first_hit_active_i <= 1'b0;
                smoke_c0_first_hit_done_i <= 1'b1;
                if (smoke_c0_first_hit_close_reason_i == 4'd0) begin
                    smoke_c0_first_hit_close_reason_i <=
                        smoke_c0_first_hit_close_reason_next;
                end
            end
            if (smoke_c0_first_hit_end_changed) begin
                smoke_c0_first_hit_end_seen_i <= core_dbg_smoke_end_hit;
                if (smoke_c0_first_hit_ec_i != 16'hffff) begin
                    smoke_c0_first_hit_ec_i <=
                        smoke_c0_first_hit_ec_i + 16'd1;
                end
            end
            if (core_dbg_smoke_c0_mixer_consume) begin
                if (smoke_ddr_follow_mixer_count_i != 16'hffff) begin
                    smoke_ddr_follow_mixer_count_i <=
                        smoke_ddr_follow_mixer_count_i + 16'd1;
                end
            end
            if (smoke_c0_first_hit_consume) begin
                if (!smoke_c0_first_hit_seen_i) begin
                    smoke_c0_first_hit_seen_i <= 1'b1;
                    smoke_c0_first_hit_active_i <= 1'b1;
                    smoke_c0_first_hit_end_seen_i <=
                        core_dbg_smoke_end_hit;
                end
                if (smoke_c0_first_hit_ad_i != 16'hffff) begin
                    smoke_c0_first_hit_ad_i <=
                        smoke_c0_first_hit_ad_i + 16'd1;
                end
                if (smoke_c0_first_hit_act_i != 16'hffff) begin
                    smoke_c0_first_hit_act_i <=
                        smoke_c0_first_hit_act_i + 16'd1;
                end
                if (smoke_c0_first_hit_capture_count_i < 4'd8) begin
                    smoke_c0_first_hit_byte_i[
                        smoke_c0_first_hit_capture_count_i[2:0]
                    ] <= core_dbg_smoke_sample_byte[7:0];
                    if (smoke_c0_first_hit_capture_count_i < 4'd4) begin
                        smoke_c0_first_hit_pi_i[
                            smoke_c0_first_hit_capture_count_i[1:0]
                        ] <= smoke_ddr_follow_payload_offset_i;
                    end
                    if (smoke_c0_first_hit_capture_count_i == 4'd0) begin
                        smoke_c0_first_hit_cv_i <=
                            smoke_c0_sample_cv16_next;
                    end
                    smoke_c0_first_hit_capture_count_i <=
                        smoke_c0_first_hit_capture_count_i + 4'd1;
                end
            end
            smoke_c0_first_hit_flags_i <= {
                4'hF,
                smoke_c0_first_hit_close_reason_i,
                smoke_c0_first_hit_seen_i,
                smoke_c0_first_hit_active_i,
                smoke_c0_first_hit_done_i,
                (smoke_c0_first_hit_ec_i != 16'd0),
                smoke_c0_first_hit_capture_count_i
            };
`endif
	            if (smoke_ddr_c0_pending_i &&
                !smoke_ddr_c0_return_valid_i &&
                !core_dbg_smoke_c0_byte_accept) begin
                if (smoke_ddr_c0_wait_count_i != 16'hffff) begin
                    smoke_ddr_c0_wait_count_i <=
                        smoke_ddr_c0_wait_count_i + 16'd1;
                end
                if ((smoke_ddr_c0_wait_count_i == 16'h0fff) &&
                    !smoke_ddr_c0_wait_timeout_seen_i) begin
                    smoke_ddr_c0_wait_timeout_seen_i <= 1'b1;
                    if (smoke_ddr_follow_timeout_count_i != 16'hffff) begin
                        smoke_ddr_follow_timeout_count_i <=
                            smoke_ddr_follow_timeout_count_i + 16'd1;
                    end
                end
            end
            if (smoke_ddr_follow_mode && smoke_ddr_audio_active) begin
                if (core_rom_cs &&
                    (smoke_ddr_follow_cs_count_i != 16'hffff)) begin
                    smoke_ddr_follow_cs_count_i <=
                        smoke_ddr_follow_cs_count_i + 16'd1;
                end
                if (core_rom_ok &&
                    (smoke_ddr_follow_ok_count_i != 16'hffff)) begin
                    smoke_ddr_follow_ok_count_i <=
                        smoke_ddr_follow_ok_count_i + 16'd1;
                end
            end
            if (!loaded_ddr_payload_present) begin
                loaded_ddr_rd_req <= 1'b0;
                loaded_ddr_rd_addr <= 19'd0;
                smoke_ddr_audio_byte_hold_i <= 8'h80;
                smoke_ddr_audio_index_hold_i <= 16'd0;
                smoke_ddr_audio_valid_seen_i <= 1'b0;
                smoke_ddr_audio_data_ok_i <= 1'b0;
                smoke_ddr_read_index_i <= 19'd0;
                smoke_ddr_read_div_i <= 16'd0;
                smoke_ddr_scan_index_i <= 16'd0;
                smoke_ddr_scan_done_i <= 1'b0;
                smoke_ddr_scan_found_nonzero_i <= 1'b0;
                smoke_ddr_follow_core_addr_low_i <= 16'd0;
                smoke_ddr_follow_prev_addr_low_i <= 16'd0;
                smoke_ddr_follow_mapped_index_i <= 16'd0;
                smoke_ddr_follow_word_i <= 16'd0;
                smoke_ddr_follow_lane_i <= 16'd0;
                smoke_ddr_follow_payload_offset_i <= 16'd0;
                smoke_ddr_follow_norm_core_i <= 16'd0;
                smoke_ddr_follow_norm_dest_i <= 16'd0;
                smoke_ddr_follow_range_flags_i <= 16'hD000;
                smoke_ddr_follow_po_min_i <= 16'hffff;
                smoke_ddr_follow_po_max_i <= 16'd0;
                smoke_ddr_follow_cr_min_i <= 16'hffff;
                smoke_ddr_follow_cr_max_i <= 16'd0;
                smoke_ddr_follow_ir_rise_count_i <= 16'd0;
                smoke_ddr_follow_ir_fall_count_i <= 16'd0;
                smoke_ddr_follow_cr_at_ir_rise_i <= 16'd0;
                smoke_ddr_follow_cr_at_ir_fall_i <= 16'd0;
                smoke_ddr_follow_po_at_ir_rise_i <= 16'd0;
                smoke_ddr_follow_po_at_ir_fall_i <= 16'd0;
                smoke_ddr_follow_raw_po_max_i <= 16'd0;
                smoke_ddr_follow_eff_mi_max_i <= 16'd0;
                smoke_ddr_follow_po_at_fu_rise_i <= 16'd0;
                smoke_ddr_follow_mi_at_fu_rise_i <= 16'd0;
                smoke_ddr_follow_po_at_ic_fall_i <= 16'd0;
                smoke_ddr_follow_mi_at_ic_fall_i <= 16'd0;
                smoke_ddr_follow_wrap_level_i <= 16'd0;
                smoke_ddr_follow_addr_in_range_i <= 1'b0;
                smoke_ddr_follow_read_in_range_i <= 1'b0;
                smoke_ddr_follow_range_miss_i <= 1'b0;
                smoke_ddr_follow_range_seen_i <= 1'b0;
                smoke_ddr_follow_wrap_count_i <= 16'd0;
                smoke_ddr_c0_pending_i <= 1'b0;
                smoke_ddr_c0_return_valid_i <= 1'b0;
                smoke_ddr_c0_return_in_range_i <= 1'b0;
                smoke_ddr_c0_wait_count_i <= 16'd0;
                smoke_ddr_c0_wait_timeout_seen_i <= 1'b0;
                smoke_ddr_follow_accept_count_i <= 16'd0;
                smoke_ddr_follow_top_request_count_i <= 16'd0;
                smoke_ddr_follow_return_count_i <= 16'd0;
                smoke_ddr_follow_jt_seen_count_i <= 16'd0;
                smoke_ddr_follow_mixer_count_i <= 16'd0;
                smoke_ddr_follow_timeout_count_i <= 16'd0;
            end else if (!smoke_ddr_audio_active) begin
                loaded_ddr_rd_req <= 1'b0;
                smoke_ddr_read_div_i <= 16'd0;
                smoke_ddr_c0_pending_i <= 1'b0;
                smoke_ddr_c0_return_valid_i <= 1'b0;
                smoke_ddr_c0_return_in_range_i <= 1'b0;
                smoke_ddr_c0_wait_count_i <= 16'd0;
                smoke_ddr_c0_wait_timeout_seen_i <= 1'b0;
                smoke_c0_probe_req_live_i <= 1'b0;
                smoke_c0_probe_pending_i <= 1'b0;
            end else if (smoke_ddr_follow_mode_d_i != smoke_ddr_follow_mode) begin
                loaded_ddr_rd_req <= 1'b0;
                smoke_ddr_read_div_i <= 16'd0;
                smoke_ddr_read_index_i <= 19'd0;
                smoke_ddr_audio_byte_hold_i <= 8'h80;
                smoke_ddr_audio_index_hold_i <= 16'd0;
                smoke_ddr_audio_valid_seen_i <= 1'b0;
                smoke_ddr_audio_data_ok_i <= 1'b0;
                smoke_ddr_follow_prev_addr_low_i <=
                    smoke_ddr_follow_core_addr_low_i;
                smoke_ddr_follow_payload_offset_i <= 16'd0;
                smoke_ddr_follow_norm_core_i <= 16'd0;
                smoke_ddr_follow_norm_dest_i <= 16'd0;
                smoke_ddr_follow_range_flags_i <= 16'hD000;
                smoke_ddr_follow_po_min_i <= 16'hffff;
                smoke_ddr_follow_po_max_i <= 16'd0;
                smoke_ddr_follow_cr_min_i <= 16'hffff;
                smoke_ddr_follow_cr_max_i <= 16'd0;
                smoke_ddr_follow_ir_rise_count_i <= 16'd0;
                smoke_ddr_follow_ir_fall_count_i <= 16'd0;
                smoke_ddr_follow_cr_at_ir_rise_i <= 16'd0;
                smoke_ddr_follow_cr_at_ir_fall_i <= 16'd0;
                smoke_ddr_follow_po_at_ir_rise_i <= 16'd0;
                smoke_ddr_follow_po_at_ir_fall_i <= 16'd0;
                smoke_ddr_follow_raw_po_max_i <= 16'd0;
                smoke_ddr_follow_eff_mi_max_i <= 16'd0;
                smoke_ddr_follow_po_at_fu_rise_i <= 16'd0;
                smoke_ddr_follow_mi_at_fu_rise_i <= 16'd0;
                smoke_ddr_follow_po_at_ic_fall_i <= 16'd0;
                smoke_ddr_follow_mi_at_ic_fall_i <= 16'd0;
                smoke_ddr_follow_wrap_level_i <= 16'd0;
                smoke_ddr_follow_addr_in_range_i <= 1'b0;
                smoke_ddr_follow_read_in_range_i <= 1'b0;
                smoke_ddr_follow_range_miss_i <= 1'b0;
                smoke_ddr_follow_range_seen_i <= 1'b0;
                smoke_ddr_follow_wrap_count_i <= 16'd0;
                smoke_ddr_c0_pending_i <= 1'b0;
                smoke_ddr_c0_return_valid_i <= 1'b0;
                smoke_ddr_c0_return_in_range_i <= 1'b0;
                smoke_ddr_c0_wait_count_i <= 16'd0;
                smoke_ddr_c0_wait_timeout_seen_i <= 1'b0;
                smoke_c0_probe_req_live_i <= 1'b0;
                smoke_c0_probe_pending_i <= 1'b0;
                smoke_ddr_follow_accept_count_i <= 16'd0;
                smoke_ddr_follow_top_request_count_i <= 16'd0;
                smoke_ddr_follow_return_count_i <= 16'd0;
                smoke_ddr_follow_jt_seen_count_i <= 16'd0;
                smoke_ddr_follow_mixer_count_i <= 16'd0;
                smoke_ddr_follow_timeout_count_i <= 16'd0;
            end else if (loaded_ddr_rd_req) begin
                if (loaded_ddr_rd_ready) begin
                    loaded_ddr_rd_req <= 1'b0;
                    if (smoke_c0_probe_req_live_i) begin
                        smoke_c0_probe_req_live_i <= 1'b0;
                        smoke_c0_probe_pending_i <= 1'b1;
                        if (smoke_c0_probe_req_index_i == 4'd0) begin
                            smoke_c0_probe_word0_i <=
                                loaded_ddr_base_addr_debug +
                                loaded_ddr_rd_addr[18:3];
                            smoke_c0_probe_lane0_i <=
                                {13'd0, loaded_ddr_rd_addr[2:0]};
                        end
                        if (smoke_c0_probe_req_index_i == 4'd7) begin
                            smoke_c0_probe_word7_i <=
                                loaded_ddr_base_addr_debug +
                                loaded_ddr_rd_addr[18:3];
                            smoke_c0_probe_lane7_i <=
                                {13'd0, loaded_ddr_rd_addr[2:0]};
                        end
                    end
                    smoke_ddr_read_last_index_i <= loaded_ddr_rd_addr[15:0];
                    if (!smoke_ddr_follow_mode) begin
                        if (smoke_ddr_read_index_i ==
                            (SMOKE_LOADED_DDR_BYTES_19 - 19'd1)) begin
                            smoke_ddr_read_index_i <= 19'd0;
                        end else begin
                            smoke_ddr_read_index_i <=
                                smoke_ddr_read_index_i + 19'd1;
                        end
                    end
                end else if (smoke_ddr_read_blocked_count_i != 16'hffff) begin
                    smoke_ddr_read_blocked_count_i <=
                        smoke_ddr_read_blocked_count_i + 16'd1;
                end
            end else if (smoke_c0_probe_needed &&
                         !smoke_c0_probe_pending_i
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                         && !lab_c0_active_i
`endif
                         ) begin
                smoke_ddr_read_div_i <= 16'd0;
                loaded_ddr_rd_req <= 1'b1;
                loaded_ddr_rd_addr <= smoke_c0_probe_read_index;
                smoke_c0_probe_req_live_i <= 1'b1;
                if (smoke_ddr_read_req_count_i != 16'hffff) begin
                    smoke_ddr_read_req_count_i <=
                        smoke_ddr_read_req_count_i + 16'd1;
                end
            end else if (smoke_ddr_follow_mode) begin
                smoke_ddr_read_div_i <= 16'd0;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                if (lab_c0_active_i) begin
                    if (lab_c0_request_fire) begin
                        loaded_ddr_rd_req <= 1'b1;
                        loaded_ddr_rd_addr <= lab_c0_req_addr_i;
                        if (smoke_ddr_read_req_count_i != 16'hffff) begin
                            smoke_ddr_read_req_count_i <=
                                smoke_ddr_read_req_count_i + 16'd1;
                        end
                        if (smoke_ddr_follow_top_request_count_i != 16'hffff) begin
                            smoke_ddr_follow_top_request_count_i <=
                                smoke_ddr_follow_top_request_count_i + 16'd1;
                        end
                        smoke_ddr_c0_pending_i <= 1'b1;
                        smoke_ddr_c0_return_valid_i <= 1'b0;
                        smoke_ddr_c0_return_in_range_i <= 1'b0;
                        smoke_ddr_c0_wait_count_i <= 16'd0;
                        smoke_ddr_c0_wait_timeout_seen_i <= 1'b0;
                    end else begin
                        loaded_ddr_rd_req <= 1'b0;
                    end
                end else
`endif
                if (rom_request_event) begin
                    if (smoke_ddr_c0drive_active &&
                        (smoke_ddr_follow_top_request_count_i != 16'hffff)) begin
                        smoke_ddr_follow_top_request_count_i <=
                            smoke_ddr_follow_top_request_count_i + 16'd1;
                    end
                    if (smoke_ddr_c0drive_active &&
                        (smoke_ddr_c0_pending_i ||
                         smoke_ddr_c0_return_valid_i)) begin
                        loaded_ddr_rd_req <= 1'b0;
                        if (smoke_ddr_read_blocked_count_i != 16'hffff) begin
                            smoke_ddr_read_blocked_count_i <=
                                smoke_ddr_read_blocked_count_i + 16'd1;
                        end
                    end else if (smoke_ddr_follow_read_in_range_next) begin
                        loaded_ddr_rd_req <= 1'b1;
                        loaded_ddr_rd_addr <= smoke_ddr_follow_read_index;
                        if (smoke_ddr_read_req_count_i != 16'hffff) begin
                            smoke_ddr_read_req_count_i <=
                                smoke_ddr_read_req_count_i + 16'd1;
                        end
                        if (smoke_ddr_c0drive_active) begin
                            smoke_ddr_c0_pending_i <= 1'b1;
                            smoke_ddr_c0_return_valid_i <= 1'b0;
                            smoke_ddr_c0_return_in_range_i <= 1'b0;
                            smoke_ddr_c0_wait_count_i <= 16'd0;
                            smoke_ddr_c0_wait_timeout_seen_i <= 1'b0;
                        end
                    end else begin
                        loaded_ddr_rd_req <= 1'b0;
                        if (smoke_ddr_read_blocked_count_i != 16'hffff) begin
                            smoke_ddr_read_blocked_count_i <=
                                smoke_ddr_read_blocked_count_i + 16'd1;
                        end
                    end
                    smoke_ddr_follow_prev_addr_low_i <=
                        smoke_ddr_follow_core_addr_low_i;
                    if ((core_rom_addr[15:0] !=
                         smoke_ddr_follow_core_addr_low_i) &&
                        (smoke_ddr_follow_addr_change_count_i != 16'hffff)) begin
                        smoke_ddr_follow_addr_change_count_i <=
                            smoke_ddr_follow_addr_change_count_i + 16'd1;
                    end
                    smoke_ddr_follow_core_addr_low_i <= core_rom_addr[15:0];
                    smoke_ddr_follow_mapped_index_i <=
                        smoke_ddr_follow_read_index[15:0];
                    smoke_ddr_follow_word_i <= smoke_ddr_follow_word_next;
                    smoke_ddr_follow_lane_i <= smoke_ddr_follow_lane_next;
                    if (smoke_ddr_c0drive_active) begin
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                        if (smoke_c0_jt_backend) begin
                            smoke_ddr_follow_payload_offset_i <=
                                lab_jt_payload_offset_next[15:0];
                            smoke_ddr_follow_norm_core_i <= core_rom_addr[15:0];
                            smoke_ddr_follow_norm_dest_i <=
                                lab_jt_payload_dest_low_next[15:0];
                            smoke_ddr_follow_addr_in_range_i <=
                                lab_jt_payload_match_valid_next;
                        end else begin
`endif
                        smoke_ddr_follow_payload_offset_i <=
                            smoke_c0_mame_payload_offset_next[15:0];
                        smoke_ddr_follow_norm_core_i <=
                            smoke_c0_mame_full_addr_next[15:0];
                        smoke_ddr_follow_norm_dest_i <=
                            smoke_c0_mame_match_dest_next[15:0];
                        smoke_ddr_follow_addr_in_range_i <=
                            smoke_c0_mame_match_valid_next;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                        end
`endif
                    end else begin
                        smoke_ddr_follow_payload_offset_i <=
                            smoke_ddr_follow_dest_offset_next[15:0];
                        smoke_ddr_follow_norm_core_i <=
                            smoke_ddr_follow_norm_core_next[15:0];
                        smoke_ddr_follow_norm_dest_i <=
                            smoke_ddr_follow_norm_dest_next[15:0];
                        smoke_ddr_follow_addr_in_range_i <=
                            smoke_ddr_follow_dest_addr_in_range_next;
                    end
                    smoke_ddr_follow_read_in_range_i <=
                        smoke_ddr_follow_read_in_range_next;
                    smoke_ddr_follow_range_miss_i <=
                        !smoke_ddr_follow_read_in_range_next;
                    if (smoke_ddr_follow_dest_selector_changed) begin
                        smoke_ddr_follow_po_min_i <= 16'hffff;
                        smoke_ddr_follow_po_max_i <= 16'd0;
                        smoke_ddr_follow_cr_min_i <= 16'hffff;
                        smoke_ddr_follow_cr_max_i <= 16'd0;
                        smoke_ddr_follow_ir_rise_count_i <= 16'd0;
                        smoke_ddr_follow_ir_fall_count_i <= 16'd0;
                        smoke_ddr_follow_cr_at_ir_rise_i <= 16'd0;
                        smoke_ddr_follow_cr_at_ir_fall_i <= 16'd0;
                        smoke_ddr_follow_po_at_ir_rise_i <= 16'd0;
                        smoke_ddr_follow_po_at_ir_fall_i <= 16'd0;
                        smoke_ddr_follow_raw_po_max_i <= 16'd0;
                        smoke_ddr_follow_eff_mi_max_i <= 16'd0;
                        smoke_ddr_follow_po_at_fu_rise_i <= 16'd0;
                        smoke_ddr_follow_mi_at_fu_rise_i <= 16'd0;
                        smoke_ddr_follow_po_at_ic_fall_i <= 16'd0;
                        smoke_ddr_follow_mi_at_ic_fall_i <= 16'd0;
                        smoke_ddr_follow_wrap_level_i <= 16'd0;
                        smoke_ddr_follow_range_seen_i <= 1'b0;
                        smoke_ddr_follow_wrap_count_i <= 16'd0;
                    end else if (smoke_ddr_follow_dest_map) begin
                        smoke_ddr_follow_wrap_level_i <= {
                            12'd0,
                            smoke_ddr_follow_dest_wrap_level_next
                        };
                        if (smoke_ddr_follow_dest_wrap_this_next &&
                            (smoke_ddr_follow_wrap_count_i != 16'hffff)) begin
                            smoke_ddr_follow_wrap_count_i <=
                                smoke_ddr_follow_wrap_count_i + 16'd1;
                        end
                        if (smoke_ddr_follow_dest_after_base_next &&
                            (smoke_ddr_follow_dest_offset_next[15:0] >
                             smoke_ddr_follow_raw_po_max_i)) begin
                            smoke_ddr_follow_raw_po_max_i <=
                                smoke_ddr_follow_dest_offset_next[15:0];
                        end
                        if (smoke_ddr_follow_read_index[15:0] >
                            smoke_ddr_follow_eff_mi_max_i) begin
                            smoke_ddr_follow_eff_mi_max_i <=
                                smoke_ddr_follow_read_index[15:0];
                        end
                        if (!smoke_ddr_follow_read_in_range_next &&
                            !smoke_ddr_follow_range_miss_i) begin
                            smoke_ddr_follow_po_at_fu_rise_i <=
                                smoke_ddr_follow_dest_offset_next[15:0];
                            smoke_ddr_follow_mi_at_fu_rise_i <=
                                smoke_ddr_follow_read_index[15:0];
                        end
                        if (!smoke_ddr_follow_read_in_range_next &&
                            smoke_ddr_follow_read_in_range_i) begin
                            smoke_ddr_follow_po_at_ic_fall_i <=
                                smoke_ddr_follow_dest_offset_next[15:0];
                            smoke_ddr_follow_mi_at_ic_fall_i <=
                                smoke_ddr_follow_read_index[15:0];
                        end
                        if (smoke_ddr_follow_dest_addr_in_range_next) begin
                            if (!smoke_ddr_follow_range_seen_i) begin
                                smoke_ddr_follow_po_min_i <=
                                    smoke_ddr_follow_dest_offset_next[15:0];
                                smoke_ddr_follow_po_max_i <=
                                    smoke_ddr_follow_dest_offset_next[15:0];
                                smoke_ddr_follow_cr_min_i <=
                                    smoke_ddr_follow_norm_core_next[15:0];
                                smoke_ddr_follow_cr_max_i <=
                                    smoke_ddr_follow_norm_core_next[15:0];
                                smoke_ddr_follow_range_seen_i <= 1'b1;
                            end else begin
                                if (smoke_ddr_follow_dest_offset_next[15:0] <
                                    smoke_ddr_follow_po_min_i) begin
                                    smoke_ddr_follow_po_min_i <=
                                        smoke_ddr_follow_dest_offset_next[15:0];
                                end
                                if (smoke_ddr_follow_dest_offset_next[15:0] >
                                    smoke_ddr_follow_po_max_i) begin
                                    smoke_ddr_follow_po_max_i <=
                                        smoke_ddr_follow_dest_offset_next[15:0];
                                end
                                if (smoke_ddr_follow_norm_core_next[15:0] <
                                    smoke_ddr_follow_cr_min_i) begin
                                    smoke_ddr_follow_cr_min_i <=
                                        smoke_ddr_follow_norm_core_next[15:0];
                                end
                                if (smoke_ddr_follow_norm_core_next[15:0] >
                                    smoke_ddr_follow_cr_max_i) begin
                                    smoke_ddr_follow_cr_max_i <=
                                        smoke_ddr_follow_norm_core_next[15:0];
                                end
                            end
                        end
                        if (smoke_ddr_follow_read_in_range_next &&
                            !smoke_ddr_follow_read_in_range_i) begin
                            smoke_ddr_follow_cr_at_ir_rise_i <=
                                smoke_ddr_follow_norm_core_next[15:0];
                            smoke_ddr_follow_po_at_ir_rise_i <=
                                smoke_ddr_follow_edge_po_next;
                            if (smoke_ddr_follow_ir_rise_count_i !=
                                16'hffff) begin
                                smoke_ddr_follow_ir_rise_count_i <=
                                    smoke_ddr_follow_ir_rise_count_i + 16'd1;
                            end
                        end
                        if (!smoke_ddr_follow_read_in_range_next &&
                            smoke_ddr_follow_read_in_range_i) begin
                            smoke_ddr_follow_cr_at_ir_fall_i <=
                                smoke_ddr_follow_norm_core_next[15:0];
                            smoke_ddr_follow_po_at_ir_fall_i <=
                                smoke_ddr_follow_edge_po_next;
                            if (smoke_ddr_follow_ir_fall_count_i !=
                                16'hffff) begin
                                smoke_ddr_follow_ir_fall_count_i <=
                                    smoke_ddr_follow_ir_fall_count_i + 16'd1;
                            end
                        end
                    end
                    if (smoke_ddr_follow_request_count_i != 16'hffff) begin
                        smoke_ddr_follow_request_count_i <=
                            smoke_ddr_follow_request_count_i + 16'd1;
                    end
                end
            end else if (smoke_ddr_read_div_i == SMOKE_DDR_READ_DIV_LAST) begin
                smoke_ddr_read_div_i <= 16'd0;
                loaded_ddr_rd_req <= 1'b1;
                loaded_ddr_rd_addr <= smoke_ddr_read_index_i;
                if (smoke_ddr_read_req_count_i != 16'hffff) begin
                    smoke_ddr_read_req_count_i <=
                        smoke_ddr_read_req_count_i + 16'd1;
                end
            end else begin
                smoke_ddr_read_div_i <= smoke_ddr_read_div_i + 16'd1;
            end

            if (loaded_ddr_payload_present && loaded_ddr_rd_valid) begin
                // C0Drive consumes only a DDR return that matches a pending
                // request. Sequential smoke keeps its previous hold behavior.
                if (smoke_c0_probe_pending_i) begin
                    smoke_c0_probe_byte_i[
                        smoke_c0_probe_return_index_i
                    ] <= loaded_ddr_rd_data;
                    if (smoke_c0_probe_return_index_i == 4'd0) begin
                        smoke_c0_probe_raw_word0_i <=
                            loaded_ddr_last_read_word0_debug;
                        smoke_c0_probe_raw_word6_i <=
                            loaded_ddr_last_read_word1_debug;
                    end
                    smoke_c0_probe_pending_i <= 1'b0;
                    if (smoke_c0_probe_return_index_i ==
                        SMOKE_C0_PROBE_LAST[3:0]) begin
                        smoke_c0_probe_done_i <= 1'b1;
                    end else begin
                        smoke_c0_probe_return_index_i <=
                            smoke_c0_probe_return_index_i + 4'd1;
                        smoke_c0_probe_req_index_i <=
                            smoke_c0_probe_return_index_i + 4'd1;
                    end
                    if (smoke_ddr_read_valid_count_i != 16'hffff) begin
                        smoke_ddr_read_valid_count_i <=
                            smoke_ddr_read_valid_count_i + 16'd1;
                    end
                end else if (smoke_ddr_c0drive_active) begin
                    if (smoke_ddr_c0_pending_i &&
                        !smoke_ddr_c0_return_valid_i) begin
                        smoke_ddr_audio_byte_hold_i <= loaded_ddr_rd_data;
                        smoke_ddr_audio_index_hold_i <=
                            loaded_ddr_last_read_index_debug;
                        smoke_ddr_audio_data_ok_i <= 1'b1;
                        smoke_ddr_audio_valid_seen_i <= 1'b1;
                        smoke_ddr_c0_pending_i <= 1'b0;
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                        smoke_ddr_c0_return_valid_i <= smoke_c0_jt_backend;
                        smoke_ddr_c0_return_in_range_i <= 1'b1;
`else
                        smoke_ddr_c0_return_valid_i <= 1'b1;
                        smoke_ddr_c0_return_in_range_i <=
                            smoke_ddr_follow_read_in_range_i;
`endif
                        smoke_ddr_c0_wait_count_i <= 16'd0;
                        smoke_ddr_c0_wait_timeout_seen_i <= 1'b0;
                        if (smoke_ddr_follow_return_count_i != 16'hffff) begin
                            smoke_ddr_follow_return_count_i <=
                                smoke_ddr_follow_return_count_i + 16'd1;
                        end
                        if (smoke_ddr_audio_update_count_i != 16'hffff) begin
                            smoke_ddr_audio_update_count_i <=
                                smoke_ddr_audio_update_count_i + 16'd1;
                        end
                        if (smoke_ddr_read_valid_count_i != 16'hffff) begin
                            smoke_ddr_read_valid_count_i <=
                                smoke_ddr_read_valid_count_i + 16'd1;
                        end
                    end
                end else begin
                    // Keep the smoke audio feed from collapsing back to zero
                    // between sparse useful DDR bytes; RD still shows raw readback.
                    if ((loaded_ddr_rd_data != 8'd0) ||
                        !smoke_ddr_audio_valid_seen_i) begin
                        smoke_ddr_audio_byte_hold_i <= loaded_ddr_rd_data;
                        smoke_ddr_audio_index_hold_i <=
                            loaded_ddr_last_read_index_debug;
                    end
                    smoke_ddr_audio_data_ok_i <= 1'b1;
                    smoke_ddr_audio_valid_seen_i <= 1'b1;
                    if (smoke_ddr_audio_update_count_i != 16'hffff) begin
                        smoke_ddr_audio_update_count_i <=
                            smoke_ddr_audio_update_count_i + 16'd1;
                    end
                end
                smoke_ddr_read_valid_seen_i <= 1'b1;
                if (!smoke_ddr_scan_done_i) begin
                    smoke_ddr_scan_index_i <= loaded_ddr_last_read_index_debug;
                    smoke_ddr_scan_data_i <= loaded_ddr_rd_data;
                    if ((loaded_ddr_rd_data != 8'd0) &&
                        (smoke_ddr_read_nonzero_count_i != 16'hffff)) begin
                        smoke_ddr_read_nonzero_count_i <=
                            smoke_ddr_read_nonzero_count_i + 16'd1;
                    end
                    if (loaded_ddr_rd_data == 8'd0) begin
                        if (smoke_ddr_read_zero_count_i != 16'hffff) begin
                            smoke_ddr_read_zero_count_i <=
                                smoke_ddr_read_zero_count_i + 16'd1;
                        end
                    end else begin
                        smoke_ddr_read_last_nonzero_data_i <= loaded_ddr_rd_data;
                        smoke_ddr_scan_last_nonzero_index_i <=
                            loaded_ddr_last_read_index_debug;
                        smoke_ddr_scan_last_nonzero_data_i <= loaded_ddr_rd_data;
                        if (!smoke_ddr_scan_found_nonzero_i) begin
                            smoke_ddr_scan_found_nonzero_i <= 1'b1;
                            smoke_ddr_scan_first_nonzero_index_i <=
                                loaded_ddr_last_read_index_debug;
                            smoke_ddr_scan_first_nonzero_data_i <=
                                loaded_ddr_rd_data;
                        end
                    end
                    if ((loaded_ddr_rd_data != smoke_ddr_read_last_data_i) &&
                        (smoke_ddr_read_change_count_i != 16'hffff)) begin
                        smoke_ddr_read_change_count_i <=
                            smoke_ddr_read_change_count_i + 16'd1;
                    end
                    if (loaded_ddr_last_read_index_debug ==
                        (SMOKE_LOADED_DDR_BYTES_19[15:0] - 16'd1)) begin
                        smoke_ddr_scan_done_i <= 1'b1;
                    end
                end
                smoke_ddr_read_prev_data_i <= smoke_ddr_read_last_data_i;
                smoke_ddr_read_last_data_i <= loaded_ddr_rd_data;
                if (smoke_ddr_read_valid_count_i != 16'hffff) begin
                    smoke_ddr_read_valid_count_i <=
                        smoke_ddr_read_valid_count_i + 16'd1;
                end
            end
        end
    end
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST
    always_ff @(posedge clk) begin
        if (reset || loaded_payload_clear) begin
            smoke_loaded_payload_seen_write_i <= 1'b0;
            smoke_loaded_payload_present_i <= 1'b0;
            smoke_loaded_payload_length_i <= 19'd0;
            smoke_loaded_payload_data_i <= 8'h80;
            smoke_loaded_capture_count_i <= 19'd0;
            smoke_loaded_capture_accept_count_i <= 16'd0;
            smoke_loaded_write_count_i <= 16'd0;
            smoke_loaded_last_write_addr_i <= 19'd0;
            smoke_loaded_last_write_data_i <= 8'd0;
        end else begin
            smoke_loaded_payload_data_i <=
                smoke_loaded_payload_ram[smoke_loaded_payload_rd_addr];

            if (loaded_payload_wr_valid) begin
                if (smoke_loaded_capture_accept_count_i != 16'hffff) begin
                    smoke_loaded_capture_accept_count_i <=
                        smoke_loaded_capture_accept_count_i + 16'd1;
                end
            end

            if (loaded_payload_wr_valid &&
                (loaded_payload_wr_addr < SMOKE_LOADED_RAM_BYTES_19)) begin
                smoke_loaded_payload_ram[
                    loaded_payload_wr_addr[SMOKE_LOADED_RAM_ADDR_BITS-1:0]
                ] <= loaded_payload_wr_data;
                smoke_loaded_payload_seen_write_i <= 1'b1;
                smoke_loaded_last_write_addr_i <= loaded_payload_wr_addr;
                smoke_loaded_last_write_data_i <= loaded_payload_wr_data;
                if (smoke_loaded_capture_count_i < SMOKE_LOADED_RAM_BYTES_19) begin
                    smoke_loaded_capture_count_i <=
                        smoke_loaded_capture_count_i + 19'd1;
                end
                if (smoke_loaded_write_count_i != 16'hffff) begin
                    smoke_loaded_write_count_i <=
                        smoke_loaded_write_count_i + 16'd1;
                end
                if (smoke_loaded_capture_count_i >=
                    (SMOKE_LOADED_RAM_BYTES_19 - 19'd1)) begin
                    smoke_loaded_payload_present_i <= 1'b1;
                    smoke_loaded_payload_length_i <= SMOKE_LOADED_RAM_BYTES_19;
                end
            end
        end
    end
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST
    always_ff @(posedge clk) begin
        if (reset || loaded_payload_clear) begin
            smoke_loaded_capture_count_i <= 19'd0;
            smoke_loaded_capture_accept_count_i <= 16'd0;
            smoke_loaded_last_write_addr_i <= 19'd0;
            smoke_loaded_last_write_data_i <= 8'd0;
        end else if (loaded_payload_wr_valid) begin
            smoke_loaded_last_write_addr_i <= loaded_payload_wr_addr;
            smoke_loaded_last_write_data_i <= loaded_payload_wr_data;
            if (smoke_loaded_capture_count_i != 19'h7ffff) begin
                smoke_loaded_capture_count_i <=
                    smoke_loaded_capture_count_i + 19'd1;
            end
            if (smoke_loaded_capture_accept_count_i != 16'hffff) begin
                smoke_loaded_capture_accept_count_i <=
                    smoke_loaded_capture_accept_count_i + 16'd1;
            end
        end
    end
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST
    always_ff @(posedge clk) begin
        if (reset || loaded_payload_clear) begin
            smoke_loaded_payload_seen_write_i <= 1'b0;
            smoke_loaded_payload_present_i <= 1'b0;
            smoke_loaded_payload_length_i <= 19'd0;
            smoke_loaded_payload_data_i <= 8'h80;
            smoke_loaded_capture_count_i <= 19'd0;
            smoke_loaded_capture_accept_count_i <= 16'd0;
            smoke_loaded_write_count_i <= 16'd0;
            smoke_loaded_last_write_addr_i <= 19'd0;
            smoke_loaded_last_write_data_i <= 8'd0;
        end else begin
            smoke_loaded_payload_data_i <=
                smoke_loaded_payload_ram[smoke_loaded_payload_rd_addr];

            if (loaded_payload_wr_valid) begin
                if (smoke_loaded_capture_accept_count_i != 16'hffff) begin
                    smoke_loaded_capture_accept_count_i <=
                        smoke_loaded_capture_accept_count_i + 16'd1;
                end
            end

            if (loaded_payload_wr_valid &&
                (loaded_payload_wr_addr < SMOKE_LOADED_RAM_BYTES_19)) begin
                smoke_loaded_payload_ram[
                    loaded_payload_wr_addr[SMOKE_LOADED_RAM_ADDR_BITS-1:0]
                ] <= loaded_payload_wr_data;
                smoke_loaded_payload_seen_write_i <= 1'b1;
                smoke_loaded_last_write_addr_i <= loaded_payload_wr_addr;
                smoke_loaded_last_write_data_i <= loaded_payload_wr_data;
                if (smoke_loaded_capture_count_i < SMOKE_LOADED_RAM_BYTES_19) begin
                    smoke_loaded_capture_count_i <=
                        smoke_loaded_capture_count_i + 19'd1;
                end
                if (smoke_loaded_write_count_i != 16'hffff) begin
                    smoke_loaded_write_count_i <=
                        smoke_loaded_write_count_i + 16'd1;
                end
            end

            if (loaded_payload_present &&
                smoke_loaded_payload_seen_write_i &&
                (smoke_loaded_payload_length_clamped != 19'd0)) begin
                smoke_loaded_payload_present_i <= 1'b1;
                smoke_loaded_payload_length_i <=
                    smoke_loaded_payload_length_clamped;
            end
        end
    end
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SOURCE_TEST
    always_ff @(posedge clk) begin
        if (reset || loaded_payload_clear) begin
            smoke_loaded_payload_seen_write_i <= 1'b0;
            smoke_loaded_payload_present_i <= 1'b0;
            smoke_loaded_payload_length_i <= 19'd0;
            smoke_loaded_payload_data_i <= 8'h80;
            smoke_loaded_capture_count_i <= 19'd0;
            smoke_loaded_capture_accept_count_i <= 16'd0;
            smoke_loaded_write_count_i <= 16'd0;
            smoke_loaded_last_write_addr_i <= 19'd0;
            smoke_loaded_last_write_data_i <= 8'd0;
        end else begin
            smoke_loaded_payload_data_i <=
                smoke_loaded_payload_ram[smoke_loaded_payload_rd_addr];

            if (loaded_payload_wr_valid) begin
                if (smoke_loaded_capture_accept_count_i != 16'hffff) begin
                    smoke_loaded_capture_accept_count_i <=
                        smoke_loaded_capture_accept_count_i + 16'd1;
                end
            end

            if (loaded_payload_wr_valid &&
                (loaded_payload_wr_addr < SMOKE_LOADED_RAM_BYTES_19)) begin
                smoke_loaded_payload_ram[
                    loaded_payload_wr_addr[SMOKE_LOADED_RAM_ADDR_BITS-1:0]
                ] <= loaded_payload_wr_data;
                smoke_loaded_payload_seen_write_i <= 1'b1;
                smoke_loaded_last_write_addr_i <= loaded_payload_wr_addr;
                smoke_loaded_last_write_data_i <= loaded_payload_wr_data;
                if (smoke_loaded_capture_count_i < SMOKE_LOADED_RAM_BYTES_19) begin
                    smoke_loaded_capture_count_i <=
                        smoke_loaded_capture_count_i + 19'd1;
                end
                if (smoke_loaded_write_count_i != 16'hffff) begin
                    smoke_loaded_write_count_i <=
                        smoke_loaded_write_count_i + 16'd1;
                end
            end

            if (loaded_payload_present &&
                smoke_loaded_payload_seen_write_i &&
                (smoke_loaded_payload_length_clamped != 19'd0)) begin
                smoke_loaded_payload_present_i <= 1'b1;
                smoke_loaded_payload_length_i <=
                    smoke_loaded_payload_length_clamped;
            end
        end
    end
`endif
`endif

`ifdef SEGA_PCM_EMBED_ROM
    segapcm_preload_rom #(
        .ROM_BYTES(PRELOAD_ROM_BYTES)
    ) preload_rom (
        .clk  (clk),
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
        .req  (1'b1),
`else
        .req  (core_rom_cs),
`endif
        .addr (mapped_rom_addr),
        .ok   (preload_rom_ok),
        .data (preload_rom_data)
    );
`else
    assign preload_rom_ok = 1'b0;
    assign preload_rom_data = 8'd0;
`endif

`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
	    jtoutrun_pcm lab_jt_pcm_core (
        .rst       (reset),
        .clk       (clk),
        .cen       (segapcm_cen),
        .debug_bus (8'd0),
        .st_dout   (lab_jt_status_dout),
        .cpu_addr  (latched_cpu_addr),
        .cpu_dout  (lab_jt_cpu_data),
        .cpu_din   (lab_jt_cpu_din),
        .cpu_rnw   (1'b0),
        .cpu_cs    (smoke_c0_jt_backend ? core_cpu_cs : 1'b0),
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
        .smoke_variant(3'd0),
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
        .smoke_ddr_follow_mode(1'b0),
        .smoke_ddr_follow_init_enable(1'b0),
        .smoke_ddr_follow_delta_sel(3'd0),
        .smoke_c0_use_sel(2'd0),
        .smoke_c0_sample_mode(2'd0),
        .smoke_c0_delta(8'd0),
        .smoke_c0_vol_l(7'd0),
        .smoke_c0_vol_r(7'd0),
        .smoke_c0_raw_audible(1'b0),
        .smoke_c0_drive_sel(2'd0),
        .smoke_c0_seed_pulse(1'b0),
        .smoke_c0_endcmp_sel(2'd0),
        .smoke_c0_loopsrc_sel(2'd0),
        .smoke_c0_current_seed(24'd0),
        .smoke_c0_loop_seed(24'd0),
        .smoke_c0_end_addr(8'd0),
        .smoke_c0_ctrl(8'd0),
        .smoke_jt_vol_l_debug(),
        .smoke_jt_vol_r_debug(),
        .smoke_sample_byte_debug(),
        .smoke_c0_byte_accept_debug(),
        .smoke_c0_mixer_consume_debug(),
        .smoke_out_l_debug(),
        .smoke_out_r_debug(),
        .smoke_end_hit_debug(),
        .smoke_loop_wrap_debug(),
        .smoke_end_cmp_debug(),
        .smoke_end_hit_at_debug(),
        .smoke_loop_to_debug(),
        .smoke_end_eq_debug(),
        .smoke_cur_initialized_debug(),
        .smoke_cur_seed_event_debug(),
        .smoke_cur_live_low_debug(),
        .smoke_cur_live_high_debug(),
        .smoke_cur_live_mid_debug(),
        .smoke_cur_live_frac_debug(),
        .smoke_cur_zero_event_debug(),
        .smoke_cur_seed_ref_debug(),
        .smoke_seed_reload_req_debug(),
        .smoke_seed_commit_count_debug(),
        .smoke_seed_commit_addr_debug(),
        .smoke_seed_write_value_debug(),
        .smoke_seed_overwrite_debug(),
        .smoke_request_addr_debug(),
        .smoke_playback_addr_debug(),
        .smoke_first_addr_debug(),
        .smoke_current_input_debug(),
        .smoke_loop_input_debug(),
        .smoke_end_input_debug(),
        .smoke_source_addr_debug(),
        .smoke_cur_state_debug(),
`endif
`endif
        .rom_addr  (lab_jt_rom_addr),
        .rom_data  (lab_jt_rom_data_to_core),
        .rom_ok    (lab_jt_rom_ok_to_core),
	        .rom_cs    (lab_jt_rom_cs),
	        .snd_left  (lab_jt_snd_left),
	        .snd_right (lab_jt_snd_right),
	        .sample    (lab_jt_sample),
	        .dbg_bank_channel_state(lab_jt_dbg_bank_channel_state),
	        .dbg_cur_addr_high(lab_jt_dbg_cur_addr_high),
	        .dbg_cur_addr_low_state(lab_jt_dbg_cur_addr_low_state),
	        .dbg_38686_en_addr(),
	        .dbg_38686_en_value(),
	        .dbg_38686_d0_addr(),
        .dbg_38686_d0_value(),
        .dbg_38686_d1_addr(),
        .dbg_38686_d1_value(),
        .dbg_38686_d2_addr(),
        .dbg_38686_d2_value(),
	        .dbg_38686_cfg_en(lab_jt_dbg_cfg_en),
	        .dbg_38686_cur_23(),
	        .dbg_38686_cur_15(),
	        .dbg_38686_cur_07(),
        .dbg_38686_delta(),
        .dbg_ch3_evolution_flags(),
        .dbg_ch3_delta(),
        .dbg_ch1_first_high(),
        .dbg_ch1_first_low(),
        .dbg_ch1_first_raw_high(),
        .dbg_ch1_first_raw_low(),
        .dbg_ch3_first_high(),
        .dbg_ch3_first_low(),
        .dbg_ch3_first_raw_high(),
        .dbg_ch3_first_raw_low(),
        .dbg_ch3_r0_high(),
        .dbg_ch3_r0_low(),
        .dbg_ch3_r1_high(),
        .dbg_ch3_r1_low(),
        .dbg_ch3_r2_high(),
        .dbg_ch3_r2_low(),
        .dbg_update_state_channel(),
        .dbg_update_before_23(),
        .dbg_update_before_15(),
        .dbg_update_before_07(),
        .dbg_update_addend(),
        .dbg_update_after_23(),
        .dbg_update_after_15(),
        .dbg_update_after_07(),
        .dbg_ch3_load_after_23(),
        .dbg_ch3_load_after_15(),
        .dbg_ch3_load_after_07(),
        .dbg_pcm_raw_cv(lab_jt_dbg_pcm_raw_cv),
        .dbg_mul_data(lab_jt_dbg_mul_data),
        .dbg_active_cfg(lab_jt_dbg_active_cfg),
        .dbg_vol_lr(lab_jt_dbg_vol_lr),
	        .dbg_update_reason(lab_jt_dbg_update_reason)
	    );

    assign cpu_din = smoke_c0_jt_backend ? lab_jt_cpu_din : 8'd0;
    assign core_rom_addr =
        smoke_c0_jt_backend ? lab_jt_rom_addr : {3'd0, lab_c0_cur_i};
    assign core_rom_cs =
        smoke_c0_jt_backend ? lab_jt_rom_cs :
        (lab_c0_active_i && smoke_ddr_c0drive_active) ||
        lab_c0_force_output ||
        lab_c0_seq_output ||
        lab_c0_local_output;
    assign core_snd_left =
        smoke_c0_jt_backend ? lab_jt_snd_left : lab_c0_actual_output_sample;
    assign core_snd_right =
        smoke_c0_jt_backend ? lab_jt_snd_right : lab_c0_actual_output_r_sample;
    assign core_sample =
        smoke_c0_jt_backend ? lab_jt_sample :
        lab_c0_consume_pulse_i ||
        (segapcm_cen && lab_c0_force_output) ||
        (lab_c0_mame_exact_mode ? lab_c0_seq_emit_pulse :
         (segapcm_cen && (lab_c0_seq_output || lab_c0_local_output)));
    assign core_status_dout = smoke_c0_jt_backend ? lab_jt_status_dout : 8'd0;
	    assign core_dbg_bank_channel_state =
	        smoke_c0_jt_backend ? lab_jt_dbg_bank_channel_state : 16'd0;
	    assign core_dbg_cur_addr_high =
	        smoke_c0_jt_backend ? lab_jt_dbg_cur_addr_high :
	        {8'd0, lab_c0_cur_i[15:8]};
	    assign core_dbg_cur_addr_low_state =
	        smoke_c0_jt_backend ? lab_jt_dbg_cur_addr_low_state :
	        {lab_c0_cur_i[7:0], 8'd8};
    assign core_dbg_38686_en_addr = 16'd0;
    assign core_dbg_38686_en_value = 16'd0;
    assign core_dbg_38686_d0_addr = 16'd0;
    assign core_dbg_38686_d0_value = 16'd0;
    assign core_dbg_38686_d1_addr = 16'd0;
    assign core_dbg_38686_d1_value = 16'd0;
    assign core_dbg_38686_d2_addr = 16'd0;
    assign core_dbg_38686_d2_value = 16'd0;
	    assign core_dbg_38686_cfg_en =
	        smoke_c0_jt_backend ? lab_jt_dbg_cfg_en : 16'd0;
    assign core_dbg_38686_cur_23 = 16'd0;
    assign core_dbg_38686_cur_15 = 16'd0;
    assign core_dbg_38686_cur_07 = 16'd0;
    assign core_dbg_38686_delta = 16'd0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
		    assign core_dbg_smoke_jt_vol_l =
		        smoke_c0_jt_backend ? lab_jt_last_non80_pr_i :
		        lab_c0_multich_delta_mode ?
		        lab16_runtime_rd_i : {9'd0, smoke_c0_vol_l_mapped};
		    assign core_dbg_smoke_jt_vol_r =
		        smoke_c0_jt_backend ? lab_jt_last_nonzero_mv_i :
		        lab_c0_multich_delta_mode ?
		        lab16_runtime_l_i[15:0] : {9'd0, smoke_c0_vol_r_mapped};
		    assign core_dbg_smoke_sample_byte =
		        smoke_c0_jt_backend ? lab_jt_max_abs_mv_i :
		        lab_c0_multich_delta_mode ?
		        lab16_runtime_addr_i : lab_c0_sb_debug_i;
    assign core_dbg_smoke_c0_byte_accept = 1'b0;
    assign core_dbg_smoke_c0_mixer_consume = lab_c0_return_pulse;
    assign core_dbg_smoke_out_l =
        smoke_c0_jt_backend ? lab_jt_snd_left :
        lab_c0_multich_delta_mode ?
        lab16_runtime_pi_i[15:0] : lab_c0_so_debug_i;
    assign core_dbg_smoke_out_r =
        smoke_c0_jt_backend ? lab_jt_snd_right :
        lab_c0_multich_delta_mode ?
        lab16_runtime_phase_hint_i : lab_c0_mo_debug_i;
    assign core_dbg_smoke_end_hit = 16'd0;
    assign core_dbg_smoke_loop_wrap = 16'd0;
    assign core_dbg_smoke_end_cmp = 16'd0;
    assign core_dbg_smoke_end_hit_at = 16'd0;
    assign core_dbg_smoke_loop_to = 16'd0;
    assign core_dbg_smoke_end_eq = 16'd0;
    assign core_dbg_smoke_cur_initialized = {15'd0, lab_c0_active_i};
    assign core_dbg_smoke_cur_seed_event = {15'd0, c0_capture_ch3_start_pulse_i};
    assign core_dbg_smoke_cur_live_low = lab_c0_cur_i;
    assign core_dbg_smoke_cur_live_high = {8'd0, lab_c0_cur_i[15:8]};
    assign core_dbg_smoke_cur_live_mid = {8'd0, lab_c0_cur_i[7:0]};
    assign core_dbg_smoke_cur_live_frac = 16'd0;
    assign core_dbg_smoke_cur_zero_event = 16'd0;
    assign core_dbg_smoke_cur_seed_ref = smoke_c0_current_seed_i[15:0];
    assign core_dbg_smoke_seed_reload_req = 16'd0;
    assign core_dbg_smoke_seed_commit_count = 16'd0;
    assign core_dbg_smoke_seed_commit_addr = 16'd0;
    assign core_dbg_smoke_seed_write_value = 16'd0;
    assign core_dbg_smoke_seed_overwrite = 16'd0;
    assign core_dbg_smoke_request_addr = lab_c0_pi_i[15:0];
    assign core_dbg_smoke_playback_addr = lab_c0_return_pi_i[15:0];
    assign core_dbg_smoke_first_addr = smoke_c0_current_seed_i[15:0];
    assign core_dbg_smoke_current_input = smoke_c0_current_seed_i[15:0];
    assign core_dbg_smoke_loop_input = 16'd0;
    assign core_dbg_smoke_end_input = 16'd0;
    assign core_dbg_smoke_source_addr = lab_c0_stall_count_i;
    assign core_dbg_smoke_cur_state = {
        8'hC0,
        smoke_c0_jt_backend,
        lab_c0_active_i,
        lab_c0_force_output,
        lab_c0_pv_match,
        smoke_ddr_c0_pending_i,
        smoke_ddr_c0_return_valid_i,
        smoke_ddr_audio_data_ok_i,
        core_sample
    };
`endif
    assign core_dbg_ch3_evolution_flags = {
        4'hE,
        lab_c0_force_output,
        lab_c0_fixed_mode && lab_c0_seq_output,
        lab_c0_local_seq_mode && lab_c0_seq_output,
        lab_c0_local_delta_mode && lab_c0_seq_output,
        lab_c0_mame_exact_mode && lab_c0_seq_output,
        lab_c0_force_output || lab_c0_seq_output || lab_c0_local_output,
        core_sample,
        lab_c0_mame_exact_mode && lab_c0_seq_output,
        lab_c0_mame_output_open,
        lab_c0_hit_window_open,
        lab_c0_pi_in_range,
        lab_c0_actual_output_sample != 16'sd0
    };
    assign core_dbg_ch3_delta =
        smoke_c0_jt_backend ? lab_jt_error_status :
        lab_c0_multich_delta_mode ?
        lab16_wave_vol_i :
        lab_c0_legacy_ch3_block2_mode ?
        {15'd0, lab_c0_seq_output} :
        {5'd0, lab_c0_effective_delta};
	    assign core_dbg_ch1_first_high =
	        smoke_c0_jt_backend ? lab_jt_sample_strobe_count_i :
	        lab_c0_multich_delta_mode ?
	        lab16_wave_rawcv1_i : smoke_c0_pm3_audio_mask;
	    assign core_dbg_ch1_first_low =
	        smoke_c0_jt_backend ? {13'd0, lab_jt_max_rom_addr_i[18:16]} :
	        lab_c0_multich_delta_mode ?
	        lab16_wave_addr1_i : loaded_ddr_write_count_debug;
	    assign core_dbg_ch1_first_raw_high =
	        smoke_c0_jt_backend ? lab_jt_rom_ok_while_cs_count_i :
	        lab_c0_multich_delta_mode ?
	        lab16_wave_pi1_i : loaded_ddr_last_write_addr_debug;
	    assign core_dbg_ch1_first_raw_low =
	        smoke_c0_jt_backend ? lab_jt_rom_non80_count_i :
	        lab_c0_multich_delta_mode ?
	        lab16_wave_out1_i :
	        {8'd0, loaded_ddr_last_write_data_debug};
	    assign core_dbg_ch3_first_high =
	        smoke_c0_jt_backend ? lab_jt_rom_request_count_i :
	        lab_c0_multich_delta_mode ?
	        lab16_wave_rawcv0_i : lab16_ch3_retrig_first0_i;
	    assign core_dbg_ch3_first_low =
	        smoke_c0_jt_backend ? lab_jt_block2_hit_count_i :
	        lab_c0_multich_delta_mode ?
	        lab16_wave_addr0_i : lab16_ch3_retrig_first1_i;
	    assign core_dbg_ch3_first_raw_high =
	        smoke_c0_jt_backend ? {13'd0, lab_jt_first_block2_rom_addr_i[18:16]} :
	        lab_c0_multich_delta_mode ?
	        lab16_wave_pi0_i :
	        lab16_ch3_retrig_first2_i;
	    assign core_dbg_ch3_first_raw_low =
	        smoke_c0_jt_backend ? lab_jt_first_block2_rom_addr_i[15:0] :
	        lab_c0_multich_delta_mode ?
	        lab16_wave_out0_i : lab16_ch3_retrig_first3_i;
		    assign core_dbg_ch3_r0_high =
		        smoke_c0_jt_backend ? lab_jt_dbg_active_cfg :
		        lab16_ch3_retrig_old_current_i;
	    assign core_dbg_ch3_r0_low =
	        smoke_c0_jt_backend ? lab_jt_cpu_write_count_i :
	        lab16_ch3_no_read_mix_count_i;
	    assign core_dbg_ch3_r1_high =
	        smoke_c0_jt_backend ? lab_jt_error_status :
	        lab16_ch3_broad_restart_count_i;
	    assign core_dbg_ch3_r1_low =
	        smoke_c0_jt_backend ? lab_jt_last_cpu_write_i :
	        lab16_ch3_retrig_old_offset_i;
	    assign core_dbg_ch3_r2_high =
	        smoke_c0_jt_backend ? {14'd0, lab_jt_rom_timing_mode} :
	        lab16_ch3_retrig_old_phase_i;
	    assign core_dbg_ch3_r2_low =
	        smoke_c0_jt_backend ? lab_jt_rom_data_latch_count_i :
	        lab16_ch3_retrig_flags_i;
		    assign core_dbg_update_state_channel =
		        smoke_c0_jt_backend ? lab_jt_first_block2_payload_index_i[15:0] :
		        lab16_wave_pi3_i;
		    assign core_dbg_update_before_23 =
		        smoke_c0_jt_backend ? {8'hB2, lab_jt_first_block2_rom_data_i} :
		        lab16_ch3_hold_mix_count_i;
		    assign core_dbg_update_before_15 =
		        smoke_c0_jt_backend ? lab_jt_ch3_current_debug : {
		        11'd0,
		        lab16_first_sample_count_i
		    };
		    assign core_dbg_update_before_07 =
		        smoke_c0_jt_backend ? lab_jt_ch3_ctrl_debug : {
		        11'd0,
		        lab16_active_count
		    };
		    assign core_dbg_update_addend =
		        smoke_c0_jt_backend ? lab_jt_ch3_end_delta_debug :
		        lab_c0_multich_delta_mode ?
		        lab16_wave_out3_i : lab16_ch3_retrig_write_i;
	    assign core_dbg_update_after_23 =
	        smoke_c0_jt_backend ? lab_jt_raw_output_nonzero_count_i :
	        lab_c0_multich_delta_mode ?
	        lab16_wave_rawcv2_i : lab16_ch3_worst_abs_i;
	    assign core_dbg_update_after_15 =
		        smoke_c0_jt_backend ? lab_jt_rom_changed_count_i :
		        lab_c0_multich_delta_mode ?
		        lab16_wave_addr2_i : lab16_ch3_worst_time_i;
	    assign core_dbg_update_after_07 =
		        smoke_c0_jt_backend ? lab_jt_rom_neutral_while_cs_count_i :
		        lab_c0_multich_delta_mode ?
		        lab16_wave_pi2_i : lab16_ch3_worst_rc_i;
		    assign core_dbg_ch3_load_after_23 =
			        smoke_c0_jt_backend ? lab_jt_sample_nonneutral_count_i :
			        lab_c0_multich_delta_mode ?
			        lab16_wave_out2_i : lab16_ch3_worst_pi_i;
		    assign core_dbg_ch3_load_after_15 =
			        smoke_c0_jt_backend ? lab_jt_rom_repeat_count_i :
			        lab_c0_multich_delta_mode ?
			        lab16_wave_rawcv3_i : lab16_ch3_worst_offset_i;
		    assign core_dbg_ch3_load_after_07 =
		        smoke_c0_jt_backend ?
		        lab_jt_output_nonzero_count_i :
		        lab_c0_multich_delta_mode ?
		        lab16_wave_addr3_i : lab16_ch3_worst_current_i;
		    assign core_dbg_update_reason =
		        smoke_c0_jt_backend ? lab_jt_ch3_volume_debug :
		        (lab_c0_multich_delta_mode ?
		         lab16_runtime_pr_hold_i :
		         lab16_ch3_retrig_first_l_i[15:0]);
`else
    jtoutrun_pcm pcm_core (
        .rst       (reset),
        .clk       (clk),
        .cen       (segapcm_cen),
        .debug_bus (8'd0),
        .st_dout   (core_status_dout),
        .cpu_addr  (latched_cpu_addr),
        .cpu_dout  (latched_cpu_data),
        .cpu_din   (cpu_din),
        .cpu_rnw   (1'b0),
        .cpu_cs    (core_cpu_cs),
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
        .smoke_variant(smoke_variant_active),
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
        .smoke_ddr_follow_mode(smoke_ddr_follow_mode),
        .smoke_ddr_follow_init_enable(smoke_ddr_audio_active),
        .smoke_ddr_follow_delta_sel(smoke_ddr_follow_delta_sel),
        .smoke_c0_use_sel(smoke_c0_use_sel),
        .smoke_c0_sample_mode(smoke_c0_sample_mode_sel),
        .smoke_c0_delta(c0_capture_ch3_delta_i),
        .smoke_c0_vol_l(smoke_c0_vol_l_mapped),
        .smoke_c0_vol_r(smoke_c0_vol_r_mapped),
        .smoke_c0_raw_audible((c0_capture_ch3_vol_l_i[6:0] != 7'd0) ||
                              (c0_capture_ch3_vol_r_i[6:0] != 7'd0)),
        .smoke_c0_drive_sel(smoke_c0_drive_sel),
        .smoke_c0_seed_pulse(c0_capture_ch3_start_pulse_i),
        .smoke_c0_endcmp_sel(smoke_c0_endcmp_sel),
        .smoke_c0_loopsrc_sel(smoke_c0_loopsrc_sel),
        .smoke_c0_current_seed(smoke_c0_current_seed_i),
        .smoke_c0_loop_seed(smoke_c0_loop_seed_i),
        .smoke_c0_end_addr(c0_capture_ch3_end_i),
        .smoke_c0_ctrl(c0_capture_ch3_ctrl_i),
        .smoke_jt_vol_l_debug(core_dbg_smoke_jt_vol_l),
        .smoke_jt_vol_r_debug(core_dbg_smoke_jt_vol_r),
        .smoke_sample_byte_debug(core_dbg_smoke_sample_byte),
        .smoke_c0_byte_accept_debug(core_dbg_smoke_c0_byte_accept),
        .smoke_c0_mixer_consume_debug(core_dbg_smoke_c0_mixer_consume),
        .smoke_out_l_debug(core_dbg_smoke_out_l),
        .smoke_out_r_debug(core_dbg_smoke_out_r),
        .smoke_end_hit_debug(core_dbg_smoke_end_hit),
        .smoke_loop_wrap_debug(core_dbg_smoke_loop_wrap),
        .smoke_end_cmp_debug(core_dbg_smoke_end_cmp),
        .smoke_end_hit_at_debug(core_dbg_smoke_end_hit_at),
        .smoke_loop_to_debug(core_dbg_smoke_loop_to),
        .smoke_end_eq_debug(core_dbg_smoke_end_eq),
        .smoke_cur_initialized_debug(core_dbg_smoke_cur_initialized),
        .smoke_cur_seed_event_debug(core_dbg_smoke_cur_seed_event),
        .smoke_cur_live_low_debug(core_dbg_smoke_cur_live_low),
        .smoke_cur_live_high_debug(core_dbg_smoke_cur_live_high),
        .smoke_cur_live_mid_debug(core_dbg_smoke_cur_live_mid),
        .smoke_cur_live_frac_debug(core_dbg_smoke_cur_live_frac),
        .smoke_cur_zero_event_debug(core_dbg_smoke_cur_zero_event),
        .smoke_cur_seed_ref_debug(core_dbg_smoke_cur_seed_ref),
        .smoke_seed_reload_req_debug(core_dbg_smoke_seed_reload_req),
        .smoke_seed_commit_count_debug(core_dbg_smoke_seed_commit_count),
        .smoke_seed_commit_addr_debug(core_dbg_smoke_seed_commit_addr),
        .smoke_seed_write_value_debug(core_dbg_smoke_seed_write_value),
        .smoke_seed_overwrite_debug(core_dbg_smoke_seed_overwrite),
        .smoke_request_addr_debug(core_dbg_smoke_request_addr),
        .smoke_playback_addr_debug(core_dbg_smoke_playback_addr),
        .smoke_first_addr_debug(core_dbg_smoke_first_addr),
        .smoke_current_input_debug(core_dbg_smoke_current_input),
        .smoke_loop_input_debug(core_dbg_smoke_loop_input),
        .smoke_end_input_debug(core_dbg_smoke_end_input),
        .smoke_source_addr_debug(core_dbg_smoke_source_addr),
        .smoke_cur_state_debug(core_dbg_smoke_cur_state),
`endif
`endif
        .rom_addr  (core_rom_addr),
        .rom_data  (core_rom_data),
        .rom_ok    (core_rom_ok),
        .rom_cs    (core_rom_cs),
        .snd_left  (core_snd_left),
        .snd_right (core_snd_right),
        .sample    (core_sample),
        .dbg_bank_channel_state(core_dbg_bank_channel_state),
        .dbg_cur_addr_high     (core_dbg_cur_addr_high),
        .dbg_cur_addr_low_state(core_dbg_cur_addr_low_state),
        .dbg_38686_en_addr     (core_dbg_38686_en_addr),
        .dbg_38686_en_value    (core_dbg_38686_en_value),
        .dbg_38686_d0_addr     (core_dbg_38686_d0_addr),
        .dbg_38686_d0_value    (core_dbg_38686_d0_value),
        .dbg_38686_d1_addr     (core_dbg_38686_d1_addr),
        .dbg_38686_d1_value    (core_dbg_38686_d1_value),
        .dbg_38686_d2_addr     (core_dbg_38686_d2_addr),
        .dbg_38686_d2_value    (core_dbg_38686_d2_value),
        .dbg_38686_cfg_en      (core_dbg_38686_cfg_en),
        .dbg_38686_cur_23      (core_dbg_38686_cur_23),
        .dbg_38686_cur_15      (core_dbg_38686_cur_15),
        .dbg_38686_cur_07      (core_dbg_38686_cur_07),
        .dbg_38686_delta       (core_dbg_38686_delta),
        .dbg_ch3_evolution_flags(core_dbg_ch3_evolution_flags),
        .dbg_ch3_delta         (core_dbg_ch3_delta),
        .dbg_ch1_first_high    (core_dbg_ch1_first_high),
        .dbg_ch1_first_low     (core_dbg_ch1_first_low),
        .dbg_ch1_first_raw_high(core_dbg_ch1_first_raw_high),
        .dbg_ch1_first_raw_low (core_dbg_ch1_first_raw_low),
        .dbg_ch3_first_high    (core_dbg_ch3_first_high),
        .dbg_ch3_first_low     (core_dbg_ch3_first_low),
        .dbg_ch3_first_raw_high(core_dbg_ch3_first_raw_high),
        .dbg_ch3_first_raw_low (core_dbg_ch3_first_raw_low),
        .dbg_ch3_r0_high       (core_dbg_ch3_r0_high),
        .dbg_ch3_r0_low        (core_dbg_ch3_r0_low),
        .dbg_ch3_r1_high       (core_dbg_ch3_r1_high),
        .dbg_ch3_r1_low        (core_dbg_ch3_r1_low),
        .dbg_ch3_r2_high       (core_dbg_ch3_r2_high),
        .dbg_ch3_r2_low        (core_dbg_ch3_r2_low),
        .dbg_update_state_channel(core_dbg_update_state_channel),
        .dbg_update_before_23  (core_dbg_update_before_23),
        .dbg_update_before_15  (core_dbg_update_before_15),
        .dbg_update_before_07  (core_dbg_update_before_07),
        .dbg_update_addend     (core_dbg_update_addend),
        .dbg_update_after_23   (core_dbg_update_after_23),
        .dbg_update_after_15   (core_dbg_update_after_15),
        .dbg_update_after_07   (core_dbg_update_after_07),
        .dbg_ch3_load_after_23 (core_dbg_ch3_load_after_23),
        .dbg_ch3_load_after_15 (core_dbg_ch3_load_after_15),
        .dbg_ch3_load_after_07 (core_dbg_ch3_load_after_07),
        .dbg_pcm_raw_cv        (),
        .dbg_mul_data          (),
        .dbg_active_cfg        (),
        .dbg_vol_lr            (),
        .dbg_update_reason     (core_dbg_update_reason)
    );
`endif

endmodule
