// SPDX-License-Identifier: GPL-2.0-or-later
//
// Golden Player Shell v1.1 compatibility shim.
//
// The module declaration below is the public port/parameter shape of
// mister_vgm_md_top from stable MegaVGMPlayer v1.0.1 (5ecce555...).  No
// production parser or sound-top implementation is copied. The body preserves
// the v1.0 non-audio contract while replacing only the profile boundary with
// the versioned v1.1 audio ABI. Stable emu remains the final audio-gate owner;
// this shim maps its existing polarity from one profile enable signal.

`timescale 1ns/1ps

`include "rtl/fixed_region_mode.vh"

module mister_vgm_md_top #(
    parameter int REGION_MODE = `FIXED_REGION_MODE,
    parameter int VGM_LOAD_ADDR_WIDTH = 18,
    parameter logic [15:0] VGM_LOAD_FILE_INDEX = 16'd1,
    parameter int MODE5_VGM_BACKEND = 0,

    // Internal reset hold after FPGA configuration or external core reset.
    // The current MiSTer shell PLL drives clk_sys at 20 MHz
    // (rtl/pll/pll_0002.v output_clock_frequency0).
    parameter logic [31:0] POWER_ON_RESET_CYCLES = 32'd25_000_000,

    // Hardware bring-up delay before the fixed VGM region starts.
    parameter logic [31:0] START_DELAY_CYCLES = 32'd25_000_000,

    // After reset is released, wait for a few audio sample strobes before
    // opening the external audio gate and starting the fixed region. This lets
    // JT12/JT89/mixer output settle while the board output is still muted.
    parameter logic [15:0] INIT_AUDIO_SAMPLE_EDGES = 16'd64,

    // Additional output warmup before starting the snippet. During this period
    // md_sound_module is running and producing sample strobes, but emu.sv still
    // keeps AUDIO_L/R at zero. 22050 samples is about 0.5 seconds at 44.1 kHz.
    parameter logic [15:0] AUDIO_WARMUP_SAMPLES = 16'd22050,
    parameter logic [15:0] GATE_TO_START_CYCLES = 16'd1024,

    // VGM waits are specified in 44100 Hz sample units. The active PLL output
    // feeding emu.clk_sys is 20 MHz, so this must match that hardware clock.
    // A stale 12.5 MHz value makes VGM playback about 20/12.5 = 1.6x fast.
    parameter logic [31:0] CLK_SYS_HZ = 32'd20_000_000,
    parameter logic [31:0] VGM_WAIT_HZ = 32'd44_100,

    // REGION_MODE=5 reload hygiene. After a valid OSD file download finishes,
    // hold the MD sound core in reset before starting the loaded player so
    // stale YM2612/JT12 and PSG state cannot bleed into the next VGM.
    parameter logic [31:0] MODE5_SOUND_RESET_CYCLES = 32'd32_768,

    // REGION_MODE=5 final-output mute release delay. This keeps the MiSTer
    // audio pins silent while the loaded player and sound core settle after a
    // completed OSD load. 1,000,000 cycles is about 50 ms at 20 MHz.
    parameter logic [31:0] MODE5_AUDIO_UNMUTE_DELAY_CYCLES = 32'd1_000_000,

    // REGION_MODE=5 explicit END repeat policy. This is intentionally separate
    // from the one-shot load-session start path: disabled means END stays
    // stopped/muted, enabled means a player_done edge schedules one reset/start
    // through the dedicated repeat path.
    parameter bit          MODE5_REPEAT_ENABLE = 1'b0,

    // Bring-up replay/retry support. If the fixed-region player misses the
    // first start or stalls before END, reset only the player wrapper and try
    // again without disturbing the JT12/JT89 audio path.
    // YM2151/SegaPCM diagnostic mix mode, active only in YM2151 experimental
    // builds: 0=mix SegaPCM>>3, 1=SegaPCM solo, 2=mix SegaPCM>>2,
    // 3=mix SegaPCM>>1, 4=mix full-scale SegaPCM.
    parameter int          SEGAPCM_EXPERIMENTAL_MIX_MODE = 1,

    parameter bit          REPLAY_ENABLE = 1'b1,
    parameter logic [31:0] PLAYER_RESET_CYCLES = 32'd4096,
    parameter logic [31:0] START_ACCEPT_TIMEOUT_CYCLES = 32'd1_000_000,
    parameter logic [31:0] PLAYER_DONE_TIMEOUT_TICKS = 32'd264_600,
    parameter logic [31:0] REPLAY_DELAY_TICKS = 32'd88_200
) (
    input  logic              clk,

    // Active-low reset is convenient for many board/top-level wrappers. It is
    // synchronized locally and converted to the active-high reset expected by
    // md_sound_fixed_region_test / md_sound_module.
    input  logic              reset_n,

    // Signed stereo PCM from md_sound_module. A future MiSTer core skeleton
    // should route these to the platform AUDIO_L/AUDIO_R path with the expected
    // width/sign convention.
    output logic signed [15:0] audio_l,
    output logic signed [15:0] audio_r,
    output logic              audio_sample_valid,
    input  logic        [1:0] audio_lpf_mode,
    input  logic              audio_gain_boost,
    input  logic        [1:0] audio_psg_level,
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
    input  logic        [2:0] segapcm_smoke_variant,
    input  logic              segapcm_smoke_variant_valid,
    input  logic              segapcm_smoke_source_loaded,
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    input  logic              segapcm_smoke_ddr_follow,
    input  logic        [2:0] segapcm_smoke_ddr_offset,
    input  logic        [2:0] segapcm_smoke_ddr_delta,
    input  logic        [1:0] segapcm_smoke_c0_use,
    input  logic        [2:0] segapcm_smoke_c0_sample_mode,
    input  logic        [1:0] segapcm_smoke_c0_delta_speed,
    input  logic        [2:0] segapcm_smoke_c0_hit_window,
    input  logic        [1:0] segapcm_smoke_c0_format,
    input  logic        [2:0] segapcm_smoke_c0_mame_tick_div,
    input  logic        [2:0] segapcm_smoke_c0_vol_map,
    input  logic        [1:0] segapcm_smoke_c0_drive,
    input  logic       [15:0] segapcm_c0_pm3_audio_mask,
    input  logic        [1:0] segapcm_c0_top_audio_test,
    input  logic        [1:0] segapcm_c0_pm3_mix_mode,
    input  logic        [2:0] segapcm_c0_pm3_start_policy,
    input  logic              segapcm_c0_jt_backend,
    input  logic              segapcm_smoke_ddr_dest_map,
    input  logic        [1:0] segapcm_smoke_ddr_dest_basis,
    input  logic              segapcm_smoke_ddr_full_capture,
    input  logic              segapcm_smoke_ddr_dest_loop_wrap,
`endif
`endif

    // Optional debug/status pins for early bring-up.
    output logic              player_busy,
    output logic              player_done,
    output logic        [9:0] player_pc_debug,
    output logic        [7:0] player_last_cmd_debug,

    // Startup/debug status for MiSTer bring-up color checks.
    output logic              startup_reset_active,
    output logic              startup_waiting,
    output logic              startup_done,
    output logic              audio_gate_open,
    output logic              audio_muted,

    // MiSTer file download bus. Used only by REGION_MODE=5.
    input  logic              ioctl_download,
    input  logic              ioctl_wr,
    input  logic [26:0]       ioctl_addr,
    input  logic [7:0]        ioctl_dout,
    input  logic [15:0]       ioctl_index,
    output logic              ioctl_wait,

    // REGION_MODE=5 loader/player status for hardware debug colors.
    output logic              vgm_load_busy,
    output logic              vgm_load_done,
    output logic              vgm_load_error,
    output logic              vgm_load_overflow,
    output logic              vgm_header_valid,
    output logic              vgm_player_error,
    output logic        [7:0] vgm_unsupported_opcode,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_unsupported_pc,
    output logic        [7:0] vgm_player_error_code,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_error_pc_debug,
    output logic        [7:0] vgm_error_cmd_debug,
    output logic        [31:0] vgm_error_session_id,
    output logic        [6:0] vgm_player_state_debug,
    output logic              vgm_mem_rd_req_debug,
    output logic              vgm_mem_rd_ready_debug,
    output logic              vgm_mem_rd_valid_debug,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_mem_rd_addr_debug,
    output logic [15:0]       vgm_player_core_debug,
    output logic [15:0]       vgm_player_lifecycle_debug,
    output logic [7:0]        vgm_player_last_read_byte_debug,
    output logic [31:0]       vgm_header_magic_read_debug,
    output logic [3:0]        vgm_header_magic_fail_index_debug,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_read_request_addr_debug,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_read_response_addr_debug,
    output logic              vgm_read_pending_debug,
    output logic              vgm_read_valid_consumed_debug,
    output logic [6:0]        vgm_final_state_debug,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_final_pc_debug,
    output logic [7:0]        vgm_final_cmd_debug,
    output logic [7:0]        vgm_final_error_code_debug,
    output logic [15:0]       vgm_final_flags_debug,
    output logic [3:0]        vgm_final_reason_debug,
    output logic [15:0]       vgm_final_progress_debug,
    output logic [7:0]        vgm_first_playback_cmd_after_scan_debug,
    output logic [31:0]       vgm_first_playback_cmds_after_scan_debug,
    output logic [6:0]        vgm_scan_state_debug,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_scan_pc_debug,
    output logic [7:0]        vgm_scan_last_cmd_debug,
    output logic [7:0]        vgm_scan_block_type_debug,
    output logic [15:0]       vgm_scan_block_size_low_debug,
    output logic [15:0]       vgm_scan_remaining_low_debug,
    output logic [15:0]       vgm_scan_wait_debug,
    output logic [7:0]        vgm_scan_abort_reason_debug,
    output logic [15:0]       vgm_scan_copy_last_index_low_debug,
    output logic [15:0]       vgm_scan_copy_req_count_debug,
    output logic [15:0]       vgm_scan_copy_ready_count_debug,
    output logic [15:0]       vgm_scan_copy_tail_debug,
    output logic [15:0]       vgm_scan_player_accept_count_debug,
    output logic [15:0]       vgm_scan_player_remaining_debug,
    output logic [15:0]       vgm_scan_payload_len_low_debug,
    output logic              vgm_scan_remaining_zero_before_expected_accept_debug,
    output logic [15:0]       vgm_scan_zero_state_debug,
    output logic [15:0]       vgm_scan_zero_pc_debug,
    output logic [15:0]       vgm_scan_zero_cmd_debug,
    output logic [15:0]       vgm_scan_copy_accept_fire_count_debug,
    output logic [15:0]       vgm_scan_noncopy_advance_count_debug,
    output logic              vgm_scan_used_noncopy_advance_debug,
    output logic [15:0]       vgm_scan_raw_copy_byte_count_debug,
    output logic [15:0]       vgm_scan_raw_event_debug,
    output logic [15:0]       vgm_scan_copy_exit_debug,
    output logic [15:0]       vgm_scan_copy_exit_pc_debug,
    output logic [15:0]       vgm_scan_copy_exit_count_debug,
    output logic [15:0]       vgm_scan_copy_phase_debug,
    output logic [15:0]       vgm_scan_copy_read_req_count_debug,
    output logic [15:0]       vgm_scan_copy_read_accept_count_debug,
    output logic [15:0]       vgm_scan_copy_read_accept_internal_debug,
    output logic [15:0]       vgm_scan_copy_read_valid_count_debug,
    output logic [15:0]       vgm_scan_copy_mem_req_cycle_count_debug,
    output logic [15:0]       vgm_scan_copy_mem_req_ready_cycle_count_debug,
    output logic [15:0]       vgm_scan_copy_request_state_debug,
    output logic [15:0]       vgm_scan_copy_state_lifetime_debug,
    output logic [15:0]       vgm_scan_copy_clear_reason_debug,
    output logic [15:0]       vgm_scan_copy_payload_pc_debug,
    output logic [15:0]       vgm_scan_copy_first01_debug,
    output logic [15:0]       vgm_scan_copy_first23_debug,
    output logic [15:0]       vgm_scan_copy_first45_debug,
    output logic [15:0]       vgm_scan_copy_first67_debug,
    output logic [15:0]       vgm_scan_copy_first8_phase_debug,
    output logic [15:0]       vgm_scan_copy_read_raw_valid_count_debug,
    output logic [15:0]       vgm_scan_copy_read_ignored_valid_count_debug,
    output logic [15:0]       vgm_scan_copy_read_handshake_debug,
    output logic [15:0]       vgm_scan_payload_o0_debug,
    output logic [15:0]       vgm_scan_payload_oh_debug,
    output logic [15:0]       vgm_scan_payload_bd_debug,
    output logic [15:0]       vgm_scan_payload_af_debug,
    output logic [15:0]       vgm_scan_payload_ah_debug,
    output logic [15:0]       vgm_scan_payload_oh2_debug,
    output logic [15:0]       vgm_scan_payload_as_debug,
    output logic [15:0]       vgm_scan_payload_vd_debug,
    output logic [15:0]       vgm_scan_payload_vh_debug,
    output logic [15:0]       vgm_scan_payload_vs_debug,
    output logic [15:0]       vgm_scan_payload_cp_debug,
    output logic [15:0]       vgm_scan_payload_ch_debug,
    output logic [15:0]       vgm_scan_payload_cs_debug,
    output logic [15:0]       vgm_scan_raw_player_accept_count_debug,
    output logic [15:0]       vgm_scan_raw_copy_accept_count_debug,
    output logic [15:0]       vgm_scan_raw_read_accept_count_debug,
    output logic [15:0]       vgm_scan_raw_read_valid_count_debug,
    output logic [15:0]       vgm_scan_max_player_accept_count_debug,
    output logic [15:0]       vgm_scan_max_copy_accept_count_debug,
    output logic [15:0]       vgm_scan_max_read_accept_count_debug,
    output logic [15:0]       vgm_scan_max_read_valid_count_debug,
    output logic [15:0]       vgm_scan_counter_latch_accept_debug,
    output logic [15:0]       vgm_scan_counter_latch_read_debug,
    output logic [15:0]       vgm_scan_counter_anomaly_debug,
    output logic [15:0]       vgm_scan_counter_reset_source_debug,
    output logic [15:0]       vgm_scan_stop_source_debug,
    output logic [15:0]       vgm_scan_term_pl_debug,
    output logic [15:0]       vgm_scan_term_rm_debug,
    output logic [15:0]       vgm_scan_term_cc_debug,
    output logic [15:0]       vgm_scan_term_nx_debug,
    output logic [15:0]       vgm_scan_term_be_debug,
    output logic [15:0]       vgm_scan_guard_debug,
    output logic [15:0]       vgm_scan_sticky_guard_debug,
    output logic [15:0]       vgm_scan_payload_qg_debug,
    output logic [15:0]       vgm_scan_payload_sf_debug,
    output logic [15:0]       mode5_backend_copy_accept_count_debug,
    output logic [15:0]       mode5_backend_copy_write_count_debug,
    output logic [15:0]       mode5_backend_copy_fifo_debug,
    output logic [15:0]       mode5_backend_copy_ready_debug,
    output logic [15:0]       mode5_backend_copy_write_req_debug,
    output logic [15:0]       mode5_backend_copy_word_debug,
    output logic [15:0]       mode5_backend_copy_flush_debug,
    output logic [15:0]       mode5_backend_copy_full_detect_count_debug,
    output logic [15:0]       mode5_backend_copy_push_req_count_debug,
    output logic [15:0]       mode5_backend_copy_push_fire_count_debug,
    output logic [15:0]       mode5_backend_copy_fifo_push_count_debug,
    output logic [15:0]       mode5_backend_copy_pack_ready_debug,
    output logic [15:0]       mode5_backend_copy_post_push_debug,
    output logic [15:0]       mode5_backend_read_gate_debug,
    output logic [15:0]       mode5_backend_read_after_copy_count_debug,
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    output logic [15:0]       smoke_ddr_payload_tap_count_debug,
    output logic [15:0]       smoke_ddr_last_read_index_debug,
    output logic [7:0]        smoke_ddr_last_read_data_debug,
    output logic [15:0]       smoke_ddr_last_read_word0_debug,
    output logic [15:0]       smoke_ddr_last_read_word1_debug,
    output logic [15:0]       smoke_ddr_probe_write_index_debug,
    output logic [15:0]       smoke_ddr_probe_write_word_debug,
    output logic [15:0]       smoke_ddr_probe_write_lane_debug,
    output logic [15:0]       smoke_ddr_probe_write_addr_debug,
    output logic [15:0]       smoke_ddr_probe_write_count_debug,
    output logic [15:0]       smoke_ddr_probe_write_flags_debug,
    output logic [15:0]       smoke_ddr_probe_write_word0_debug,
    output logic [15:0]       smoke_ddr_probe_write_word6_debug,
`endif
    output logic [15:0]       mode5_read_mux_debug,
    output logic [15:0]       mode5_read_ready_compare_debug,
    output logic [15:0]       mode5_read_ready_blocker_debug,
    output logic [15:0]       mode5_copy_mismatch_debug,
    output logic [15:0]       mode5_copy_max_ready_count_debug,
    output logic [15:0]       mode5_copy_min_remaining_debug,
    output logic [15:0]       mode5_restart_after_load_count_debug,
    output logic [15:0]       mode5_scan_start_count_debug,
    output logic [15:0]       mode5_direct_start_debug,
    output logic [15:0]       mode5_top_stop_snapshot_debug,
    output logic [VGM_LOAD_ADDR_WIDTH:0] vgm_load_size,
    output logic [31:0]       vgm_load_magic,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_data_start_debug,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_current_pc_debug,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_loop_pc_debug,
    output logic              vgm_loop_valid_debug,
    output logic              vgm_loop_taken_debug,
    output logic              vgm_end_command_seen,
    output logic              vgm_restarted_from_data_start,
    output logic              vgm_pcm_oob,
    output logic [31:0]       vgm_pcm_oob_count,
    output logic [31:0]       vgm_wait_ticks_consumed_debug,
    output logic [31:0]       dac_stream_cmd_count,
    output logic [31:0]       dac_stream_wait_samples_total,
    output logic [31:0]       dac_stream_clk_cycles_total,
    output logic [31:0]       dac_stream_overhead_cycles_total,
    output logic [31:0]       max_dac_stream_cmd_cycles,
    output logic [31:0]       count_wait0_dac_stream_cmd,
    output logic [31:0]       count_wait0_overhead_nonzero,
    output logic [31:0]       segapcm_write_count,
    output logic [15:0]       segapcm_last_addr,
    output logic [7:0]        segapcm_last_data,
    output logic [15:0]       segapcm_core_rom_addr_low,
    output logic [15:0]       segapcm_core_rom_addr_raw_high,
    output logic [15:0]       segapcm_core_rom_addr_raw_low,
    output logic [15:0]       segapcm_core_rom_addr_mapped_high,
    output logic [15:0]       segapcm_core_rom_addr_mapped_low,
    output logic [15:0]       segapcm_core_rom_addr_min_high,
    output logic [15:0]       segapcm_core_rom_addr_min_low,
    output logic [15:0]       segapcm_core_rom_addr_max_high,
    output logic [15:0]       segapcm_core_rom_addr_max_low,
    output logic [15:0]       segapcm_core_rom_audio_active_high,
    output logic [15:0]       segapcm_core_rom_audio_active_low,
    output logic [15:0]       segapcm_core_rom_first_after_ctrl_high,
    output logic [15:0]       segapcm_core_rom_first_after_ctrl_low,
    output logic [15:0]       segapcm_core_rom_range_group,
    output logic [15:0]       segapcm_core_rom_range_group2,
    output logic [15:0]       segapcm_core_rom_early_after_ctrl_high,
    output logic [15:0]       segapcm_core_rom_early_after_ctrl_low,
    output logic [15:0]       segapcm_core_rom_active_after_ctrl_high,
    output logic [15:0]       segapcm_core_rom_active_after_ctrl_low,
    output logic [15:0]       segapcm_core_rom_hit_miss_compact,
    output logic [15:0]       segapcm_core_rom_range_hit_count,
    output logic [15:0]       segapcm_core_rom_range_miss_count,
    output logic [15:0]       segapcm_core_rom_activity_count,
    output logic [15:0]       segapcm_core_rom_return_mapped_high,
    output logic [15:0]       segapcm_core_rom_return_mapped_low,
    output logic [15:0]       segapcm_core_rom_return_data,
    output logic [15:0]       segapcm_core_rom_return_last01,
    output logic [15:0]       segapcm_core_rom_return_last23,
    output logic [15:0]       segapcm_core_rom_return_nonzero_count,
    output logic [15:0]       segapcm_core_rom_return_change_count,
    output logic [15:0]       segapcm_core_rom_return_neutral_count,
    output logic [15:0]       segapcm_core_rom_preload_data,
    output logic [15:0]       segapcm_core_rom_core_ok_count,
    output logic [15:0]       segapcm_core_rom_fallback_count,
    output logic [15:0]       segapcm_core_rom_read_valid_count,
    output logic [15:0]       segapcm_core_rom_latency_debug,
    output logic [15:0]       segapcm_core_rom_payload_len_low,
    output logic [15:0]       segapcm_core_rom_payload_len_high,
    output logic [15:0]       segapcm_core_pcm_debug_bk,
    output logic [15:0]       segapcm_core_pcm_debug_cuh,
    output logic [15:0]       segapcm_core_pcm_debug_cul,
    output logic [15:0]       segapcm_core_known38686_flags,
    output logic [15:0]       segapcm_core_known38686_bank,
    output logic [15:0]       segapcm_core_known38686_channel,
    output logic [15:0]       segapcm_core_known38686_state,
    output logic [15:0]       segapcm_core_known38686_cur_high,
    output logic [15:0]       segapcm_core_known38686_cur_low,
    output logic [15:0]       segapcm_core_known38686_en_addr,
    output logic [15:0]       segapcm_core_known38686_en_value,
    output logic [15:0]       segapcm_core_known38686_d0_addr,
    output logic [15:0]       segapcm_core_known38686_d0_value,
    output logic [15:0]       segapcm_core_known38686_d1_addr,
    output logic [15:0]       segapcm_core_known38686_d1_value,
    output logic [15:0]       segapcm_core_known38686_d2_addr,
    output logic [15:0]       segapcm_core_known38686_d2_value,
    output logic [15:0]       segapcm_core_known38686_cfg_en,
    output logic [15:0]       segapcm_core_known38686_cur_23,
    output logic [15:0]       segapcm_core_known38686_cur_15,
    output logic [15:0]       segapcm_core_known38686_cur_07,
    output logic [15:0]       segapcm_core_c0_capture_write_count,
    output logic [15:0]       segapcm_core_c0_capture_last_addr,
    output logic [15:0]       segapcm_core_c0_capture_last_data,
    output logic [15:0]       segapcm_core_c0_capture_channel_activity,
    output logic [15:0]       segapcm_core_c0_capture_selected_channel,
    output logic [15:0]       segapcm_core_c0_capture_ch3_ctrl,
    output logic [15:0]       segapcm_core_c0_capture_ch3_cur_low,
    output logic [15:0]       segapcm_core_c0_capture_ch3_cur_mid,
    output logic [15:0]       segapcm_core_c0_capture_ch3_cur_high,
    output logic [15:0]       segapcm_core_c0_capture_ch3_delta,
    output logic [15:0]       segapcm_core_c0_capture_ch3_vol_l,
    output logic [15:0]       segapcm_core_c0_capture_ch3_vol_r,
    output logic [15:0]       segapcm_core_c0_capture_ch3_loop,
    output logic [15:0]       segapcm_core_c0_capture_ch3_end,
    output logic [15:0]       segapcm_core_jt_smoke_vol_l,
    output logic [15:0]       segapcm_core_jt_smoke_vol_r,
    output logic [15:0]       segapcm_core_jt_smoke_sample_byte,
    output logic [15:0]       segapcm_core_jt_smoke_out_l,
    output logic [15:0]       segapcm_core_jt_smoke_out_r,
    output logic [15:0]       segapcm_core_ch3_evolution_flags,
    output logic [15:0]       segapcm_core_ch3_delta,
    output logic [15:0]       segapcm_core_ch1_first_high,
    output logic [15:0]       segapcm_core_ch1_first_low,
    output logic [15:0]       segapcm_core_ch1_first_raw_high,
    output logic [15:0]       segapcm_core_ch1_first_raw_low,
    output logic [15:0]       segapcm_core_ch3_first_high,
    output logic [15:0]       segapcm_core_ch3_first_low,
    output logic [15:0]       segapcm_core_ch3_first_raw_high,
    output logic [15:0]       segapcm_core_ch3_first_raw_low,
    output logic [15:0]       segapcm_core_ch3_r0_high,
    output logic [15:0]       segapcm_core_ch3_r0_low,
    output logic [15:0]       segapcm_core_ch3_r1_high,
    output logic [15:0]       segapcm_core_ch3_r1_low,
    output logic [15:0]       segapcm_core_ch3_r2_high,
    output logic [15:0]       segapcm_core_ch3_r2_low,
    output logic [15:0]       segapcm_core_ch3_load_after_23,
    output logic [15:0]       segapcm_core_ch3_load_after_15,
    output logic [15:0]       segapcm_core_ch3_load_after_07,
    output logic [15:0]       segapcm_core_update_state_channel,
    output logic [15:0]       segapcm_core_update_before_23,
    output logic [15:0]       segapcm_core_update_before_15,
    output logic [15:0]       segapcm_core_update_before_07,
    output logic [15:0]       segapcm_core_update_addend,
    output logic [15:0]       segapcm_core_update_after_23,
    output logic [15:0]       segapcm_core_update_after_15,
    output logic [15:0]       segapcm_core_update_after_07,
    output logic [15:0]       segapcm_core_update_reason,
    output logic [415:0]      segapcm_jt_rv60_debug_bus,
    output logic [63:0]       segapcm_rv61_signature_bus,
    output logic [15:0]       segapcm_core_cpu_write_count,
    output logic [15:0]       segapcm_core_cpu_cen_write_count,
    output logic [15:0]       segapcm_core_cpu_addr_debug,
    output logic [15:0]       segapcm_core_shadow_decode_debug,
    output logic [15:0]       segapcm_core_shadow_ch0_vol_debug,
    output logic [15:0]       segapcm_core_shadow_ch0_end_delta_debug,
    output logic [15:0]       segapcm_core_shadow_ch0_start_debug,
    output logic [15:0]       segapcm_core_shadow_ch0_ctrl_debug,
    output logic [15:0]       segapcm_core_shadow_ch1_vol_debug,
    output logic [15:0]       segapcm_core_shadow_ch1_loop_debug,
    output logic [15:0]       segapcm_core_shadow_ch1_end_delta_debug,
    output logic [15:0]       segapcm_core_shadow_ch1_start_debug,
    output logic [15:0]       segapcm_core_shadow_ch1_ctrl_debug,
    output logic [15:0]       segapcm_core_shadow_ch3_loop_debug,
    output logic [15:0]       segapcm_core_shadow_ch3_end_delta_debug,
    output logic [15:0]       segapcm_core_shadow_ch3_start_debug,
    output logic [15:0]       segapcm_core_shadow_ch3_ctrl_debug,
    output logic [15:0]       segapcm_core_shadow_ch3_l0_debug,
    output logic [15:0]       segapcm_core_shadow_ch3_l2_debug,
    output logic [15:0]       segapcm_core_shadow_ch3_l4_debug,
    output logic [15:0]       segapcm_core_shadow_ch3_l6_debug,
    output logic [15:0]       segapcm_core_shadow_ch3_h0_debug,
    output logic [15:0]       segapcm_core_shadow_ch3_h2_debug,
    output logic [15:0]       segapcm_core_shadow_ch3_h4_debug,
    output logic [15:0]       segapcm_core_shadow_ch3_h6_debug,
    output logic [15:0]       segapcm_core_audio_nonzero_count,
    output logic [15:0]       segapcm_core_audio_abs_peak,
    output logic signed [15:0] segapcm_core_last_audio_l,
    output logic signed [15:0] segapcm_core_last_audio_r,
    output logic [15:0]       segapcm_core_status_debug,
    output logic [31:0]       segapcm_block6_probe_b6_debug,
    output logic [31:0]       segapcm_block6_probe_r6_debug,
    output logic [31:0]       segapcm_block6_probe_h6_debug,
    output logic [31:0]       segapcm_block6_probe_c6_debug,
    output logic [31:0]       segapcm_block6_probe_m6_debug,
    output logic [31:0]       data_block_count,
    output logic [7:0]        last_data_block_type,
    output logic [15:0]       last_data_block_size_low,
    output logic [31:0]       parser_command_count_debug,
    output logic [31:0]       parser_data_block_count_debug,
    output logic [7:0]        parser_last_block_type_debug,
    output logic [31:0]       parser_type00_block_count_debug,
    output logic [31:0]       parser_type80_block_count_debug,
    output logic [31:0]       segapcm_rom_block_count,
    output logic [31:0]       segapcm_last_rom_size,
    output logic [31:0]       segapcm_last_rom_start,
    output logic [31:0]       pcm_ram_write_skip_count,
    output logic              segapcm_rom_scan_busy,
    output logic              segapcm_rom_scan_done,
    output logic              segapcm_rom_scan_overflow,
    output logic [31:0]       segapcm_rom_scan_block_count,
    output logic [31:0]       segapcm_rom_scan_byte_count,
    output logic [31:0]       segapcm_rom_scan_checksum32,
    output logic [31:0]       segapcm_rom_scan_total_size,
    output logic [31:0]       segapcm_rom_scan_last_start,
    output logic [31:0]       segapcm_rom_copy_byte_count,
    output logic              segapcm_rom_copy_overflow,
    output logic              segapcm_rom_copy_flush_done,
    output logic              segapcm_copy_flush_req_debug,
    output logic              mode5_sound_reset_active,
    output logic              mode5_player_start_pulse_debug,
    output logic [15:0]       mode5_start_hold_debug,
    output logic [31:0]       mode5_load_begin_count,
    output logic [31:0]       mode5_load_done_edge_count,
    output logic [31:0]       mode5_sound_reset_start_count,
    output logic [31:0]       mode5_player_start_count,
    output logic [31:0]       mode5_player_reset_count,
    output logic [31:0]       mode5_playback_session_id,
    output logic [31:0]       mode5_duplicate_start_blocked_count,
    output logic [31:0]       mode5_player_end_count,
    output logic [31:0]       mode5_repeat_restart_count,
    output logic              mode5_done_armed_debug,
    output logic [31:0]       mode5_repeat_session_id,
    output logic [31:0]       mode5_done_session_id,
    output logic [31:0]       mode5_cycles_since_start,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] mode5_done_pc_debug,
    output logic [7:0]        mode5_done_cmd_debug,
    output logic [15:0]       fm_adjust_clip_count_l,
    output logic [15:0]       fm_adjust_clip_count_r,
    output logic [15:0]       genmix_wrap_count_l,
    output logic [15:0]       genmix_wrap_count_r,
    output logic [31:0]       ym_write_requested_count,
    output logic [31:0]       ym_write_accepted_count,
    output logic [31:0]       ym_write_dropped_or_busy_count,
    output logic [31:0]       ym_port0_count,
    output logic [31:0]       ym_port1_count,
    output logic              last_ym_port,
    output logic [7:0]        last_ym_addr,
    output logic [7:0]        last_ym_data,
    output logic [15:0]       jt12_cen_interval_1_count,
    output logic [15:0]       jt12_cen_interval_2_count,
    output logic [15:0]       jt12_cen_interval_3_count,
    output logic [15:0]       jt12_cen_interval_4_count,
    output logic [15:0]       jt12_cen_interval_ge5_count,
    output logic [7:0]        jt12_cen_interval_min,
    output logic [7:0]        jt12_cen_interval_max,
    output logic [7:0]        jt12_cen_interval_last,
    output logic [15:0]       fm_raw_abs_peak,
    output logic [15:0]       fm_adjust_abs_peak,
    output logic [15:0]       fm_lpf_abs_peak,
    output logic [15:0]       genmix_abs_peak,
    output logic [15:0]       md_final_audio_abs_peak,
    output logic [15:0]       c0_top_dbg_tp,
    output logic [15:0]       c0_top_dbg_sl,
    output logic [15:0]       c0_top_dbg_sr,
    output logic [15:0]       c0_top_dbg_ml,
    output logic [15:0]       c0_top_dbg_mr,
    output logic [15:0]       c0_top_dbg_fl,
    output logic [15:0]       c0_top_dbg_fr,
    output logic [15:0]       c0_top_dbg_ol,
    output logic [15:0]       c0_top_dbg_or,
    output logic [15:0]       c0_top_dbg_tm,

    // DDRAM interface for future mode5 backend.
    // Backend 0 (BRAM) keeps these inactive.
    input  logic              ddram_busy,
    output logic [7:0]        ddram_burstcnt,
    output logic [28:0]       ddram_addr,
    input  logic [63:0]       ddram_dout,
    input  logic              ddram_dout_ready,
    output logic              ddram_rd,
    output logic [63:0]       ddram_din,
    output logic [7:0]        ddram_be,
    output logic              ddram_we
);

    wire reset = !reset_n;

    wire                      profile_file_read_request;
    wire [VGM_LOAD_ADDR_WIDTH-1:0] profile_file_read_address;
    wire                      profile_file_read_ready;
    wire                      profile_file_read_valid;
    wire [7:0]                profile_file_read_data;
    wire                      profile_pcm_a_read_request;
    wire [VGM_LOAD_ADDR_WIDTH-1:0] profile_pcm_a_read_address;
    wire                      profile_pcm_b_read_request;
    wire [VGM_LOAD_ADDR_WIDTH-1:0] profile_pcm_b_read_address;
    wire signed [15:0]        profile_audio_l;
    wire signed [15:0]        profile_audio_r;
    wire                      profile_audio_sample_valid;
    wire                      profile_audio_enable;
    wire                      profile_playback_active;
    wire                      profile_fatal;
    wire [15:0]               profile_status;
    wire [15:0]               profile_debug_page_data;
    wire [31:0]               parser_start_count;
    wire [31:0]               scanner_start_count;
    wire [31:0]               sound_write_count;

    wire                      upload_load_busy;
    wire                      upload_load_done;
    wire                      upload_load_done_pulse;
    wire                      upload_load_error;
    wire                      upload_load_overflow;
    wire [31:0]               uploaded_physical_size;
    wire [31:0]               upload_magic;

    golden_player_shell_v1_1_profile #(
        .VGM_ADDR_WIDTH(VGM_LOAD_ADDR_WIDTH),
        .CLK_SYS_HZ(CLK_SYS_HZ)
    ) v1_1_profile (
        .clk_sys(clk),
        .reset(reset),
        .download_active(ioctl_download),
        .uploaded_physical_size(uploaded_physical_size),
        .upload_complete(upload_load_done),
        .file_read_ready(profile_file_read_ready),
        .file_read_valid(profile_file_read_valid),
        .file_read_data(profile_file_read_data),
        .file_read_request(profile_file_read_request),
        .file_read_address(profile_file_read_address),
        .pcm_a_read_request(profile_pcm_a_read_request),
        .pcm_a_read_address(profile_pcm_a_read_address),
        .pcm_b_read_request(profile_pcm_b_read_request),
        .pcm_b_read_address(profile_pcm_b_read_address),
        .osd_audio_lpf_mode(audio_lpf_mode),
        .osd_audio_gain_boost(audio_gain_boost),
        .osd_audio_psg_level(audio_psg_level),
        .title_valid(1'b0),
        .title_text_byte(8'd0),
        .shell_sample_timing(1'b0),
        .profile_audio_l(profile_audio_l),
        .profile_audio_r(profile_audio_r),
        .profile_audio_sample_valid(profile_audio_sample_valid),
        .profile_audio_enable(profile_audio_enable),
        .playback_active(profile_playback_active),
        .profile_fatal(profile_fatal),
        .profile_status(profile_status),
        .debug_page_data(profile_debug_page_data),
        .parser_start_count(parser_start_count),
        .scanner_start_count(scanner_start_count),
        .sound_write_count(sound_write_count)
    );

    golden_player_shell_upload #(
        .VGM_ADDR_WIDTH(VGM_LOAD_ADDR_WIDTH),
        .FILE_INDEX(VGM_LOAD_FILE_INDEX)
    ) physical_upload (
        .clk(clk),
        .reset(reset),
        .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout),
        .ioctl_index(ioctl_index),
        .ioctl_wait(ioctl_wait),
        .file_read_request(profile_file_read_request),
        .file_read_address(profile_file_read_address),
        .file_read_ready(profile_file_read_ready),
        .file_read_valid(profile_file_read_valid),
        .file_read_data(profile_file_read_data),
        .load_busy(upload_load_busy),
        .load_done(upload_load_done),
        .load_done_pulse(upload_load_done_pulse),
        .load_error(upload_load_error),
        .load_overflow(upload_load_overflow),
        .uploaded_physical_size(uploaded_physical_size),
        .upload_magic(upload_magic),
        .ddram_busy(ddram_busy),
        .ddram_burstcnt(ddram_burstcnt),
        .ddram_addr(ddram_addr),
        .ddram_dout(ddram_dout),
        .ddram_dout_ready(ddram_dout_ready),
        .ddram_rd(ddram_rd),
        .ddram_din(ddram_din),
        .ddram_be(ddram_be),
        .ddram_we(ddram_we)
    );

    // v1.1 audio ABI: profile_audio_enable is the sole gate authority. The
    // explicit local zeroing keeps the shim-facing contract known before
    // stable emu applies its unchanged final gate.
    assign audio_l = profile_audio_enable ? profile_audio_l : 16'sd0;
    assign audio_r = profile_audio_enable ? profile_audio_r : 16'sd0;
    assign audio_sample_valid =
        profile_audio_enable ? profile_audio_sample_valid : 1'b0;
    assign player_busy = profile_playback_active;
    assign player_done = 1'b0;
    assign startup_reset_active = 1'b0;
    assign startup_waiting = 1'b0;
    assign startup_done = 1'b1;
    assign audio_gate_open = profile_audio_enable;
    assign audio_muted = !profile_audio_enable;

    assign vgm_load_busy = upload_load_busy;
    assign vgm_load_done = upload_load_done;
    assign vgm_load_error = upload_load_error;
    assign vgm_load_overflow = upload_load_overflow;
    assign vgm_header_valid = 1'b0;
    assign vgm_player_error = profile_fatal;
    assign vgm_mem_rd_req_debug = profile_file_read_request;
    assign vgm_mem_rd_ready_debug = profile_file_read_ready;
    assign vgm_mem_rd_valid_debug = profile_file_read_valid;
    assign vgm_mem_rd_addr_debug = profile_file_read_address;
    assign vgm_load_size = uploaded_physical_size[VGM_LOAD_ADDR_WIDTH:0];
    assign vgm_load_magic = upload_magic;
    assign mode5_scan_start_count_debug = scanner_start_count[15:0];
    assign parser_command_count_debug = parser_start_count;

`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
`endif
`endif
    assign player_pc_debug = '0;
    assign player_last_cmd_debug = '0;
    assign vgm_unsupported_opcode = '0;
    assign vgm_unsupported_pc = '0;
`ifdef YM2610B_METAL_SLUG_REJECT_UART_LAB
    // Lab-only passive conduit from the profile observer to the existing
    // top-level UART pin. It has no functional-shell fanout.
    assign vgm_player_error_code = {7'd0, profile_debug_page_data[0]};
`else
    assign vgm_player_error_code = '0;
`endif
    assign vgm_error_pc_debug = '0;
    assign vgm_error_cmd_debug = '0;
    assign vgm_error_session_id = '0;
    assign vgm_player_state_debug = '0;
    assign vgm_player_core_debug = '0;
    assign vgm_player_lifecycle_debug = '0;
    assign vgm_player_last_read_byte_debug = '0;
    assign vgm_header_magic_read_debug = '0;
    assign vgm_header_magic_fail_index_debug = '0;
    assign vgm_read_request_addr_debug = '0;
    assign vgm_read_response_addr_debug = '0;
    assign vgm_read_pending_debug = '0;
    assign vgm_read_valid_consumed_debug = '0;
    assign vgm_final_state_debug = '0;
    assign vgm_final_pc_debug = '0;
    assign vgm_final_cmd_debug = '0;
    assign vgm_final_error_code_debug = '0;
    assign vgm_final_flags_debug = '0;
    assign vgm_final_reason_debug = '0;
    assign vgm_final_progress_debug = '0;
    assign vgm_first_playback_cmd_after_scan_debug = '0;
    assign vgm_first_playback_cmds_after_scan_debug = '0;
    assign vgm_scan_state_debug = '0;
    assign vgm_scan_pc_debug = '0;
    assign vgm_scan_last_cmd_debug = '0;
    assign vgm_scan_block_type_debug = '0;
    assign vgm_scan_block_size_low_debug = '0;
    assign vgm_scan_remaining_low_debug = '0;
    assign vgm_scan_wait_debug = '0;
    assign vgm_scan_abort_reason_debug = '0;
    assign vgm_scan_copy_last_index_low_debug = '0;
    assign vgm_scan_copy_req_count_debug = '0;
    assign vgm_scan_copy_ready_count_debug = '0;
    assign vgm_scan_copy_tail_debug = '0;
    assign vgm_scan_player_accept_count_debug = '0;
    assign vgm_scan_player_remaining_debug = '0;
    assign vgm_scan_payload_len_low_debug = '0;
    assign vgm_scan_remaining_zero_before_expected_accept_debug = '0;
    assign vgm_scan_zero_state_debug = '0;
    assign vgm_scan_zero_pc_debug = '0;
    assign vgm_scan_zero_cmd_debug = '0;
    assign vgm_scan_copy_accept_fire_count_debug = '0;
    assign vgm_scan_noncopy_advance_count_debug = '0;
    assign vgm_scan_used_noncopy_advance_debug = '0;
    assign vgm_scan_raw_copy_byte_count_debug = '0;
    assign vgm_scan_raw_event_debug = '0;
    assign vgm_scan_copy_exit_debug = '0;
    assign vgm_scan_copy_exit_pc_debug = '0;
    assign vgm_scan_copy_exit_count_debug = '0;
    assign vgm_scan_copy_phase_debug = '0;
    assign vgm_scan_copy_read_req_count_debug = '0;
    assign vgm_scan_copy_read_accept_count_debug = '0;
    assign vgm_scan_copy_read_accept_internal_debug = '0;
    assign vgm_scan_copy_read_valid_count_debug = '0;
    assign vgm_scan_copy_mem_req_cycle_count_debug = '0;
    assign vgm_scan_copy_mem_req_ready_cycle_count_debug = '0;
    assign vgm_scan_copy_request_state_debug = '0;
    assign vgm_scan_copy_state_lifetime_debug = '0;
    assign vgm_scan_copy_clear_reason_debug = '0;
    assign vgm_scan_copy_payload_pc_debug = '0;
    assign vgm_scan_copy_first01_debug = '0;
    assign vgm_scan_copy_first23_debug = '0;
    assign vgm_scan_copy_first45_debug = '0;
    assign vgm_scan_copy_first67_debug = '0;
    assign vgm_scan_copy_first8_phase_debug = '0;
    assign vgm_scan_copy_read_raw_valid_count_debug = '0;
    assign vgm_scan_copy_read_ignored_valid_count_debug = '0;
    assign vgm_scan_copy_read_handshake_debug = '0;
    assign vgm_scan_payload_o0_debug = '0;
    assign vgm_scan_payload_oh_debug = '0;
    assign vgm_scan_payload_bd_debug = '0;
    assign vgm_scan_payload_af_debug = '0;
    assign vgm_scan_payload_ah_debug = '0;
    assign vgm_scan_payload_oh2_debug = '0;
    assign vgm_scan_payload_as_debug = '0;
    assign vgm_scan_payload_vd_debug = '0;
    assign vgm_scan_payload_vh_debug = '0;
    assign vgm_scan_payload_vs_debug = '0;
    assign vgm_scan_payload_cp_debug = '0;
    assign vgm_scan_payload_ch_debug = '0;
    assign vgm_scan_payload_cs_debug = '0;
    assign vgm_scan_raw_player_accept_count_debug = '0;
    assign vgm_scan_raw_copy_accept_count_debug = '0;
    assign vgm_scan_raw_read_accept_count_debug = '0;
    assign vgm_scan_raw_read_valid_count_debug = '0;
    assign vgm_scan_max_player_accept_count_debug = '0;
    assign vgm_scan_max_copy_accept_count_debug = '0;
    assign vgm_scan_max_read_accept_count_debug = '0;
    assign vgm_scan_max_read_valid_count_debug = '0;
    assign vgm_scan_counter_latch_accept_debug = '0;
    assign vgm_scan_counter_latch_read_debug = '0;
    assign vgm_scan_counter_anomaly_debug = '0;
    assign vgm_scan_counter_reset_source_debug = '0;
    assign vgm_scan_stop_source_debug = '0;
    assign vgm_scan_term_pl_debug = '0;
    assign vgm_scan_term_rm_debug = '0;
    assign vgm_scan_term_cc_debug = '0;
    assign vgm_scan_term_nx_debug = '0;
    assign vgm_scan_term_be_debug = '0;
    assign vgm_scan_guard_debug = '0;
    assign vgm_scan_sticky_guard_debug = '0;
    assign vgm_scan_payload_qg_debug = '0;
    assign vgm_scan_payload_sf_debug = '0;
    assign mode5_backend_copy_accept_count_debug = '0;
    assign mode5_backend_copy_write_count_debug = '0;
    assign mode5_backend_copy_fifo_debug = '0;
    assign mode5_backend_copy_ready_debug = '0;
    assign mode5_backend_copy_write_req_debug = '0;
    assign mode5_backend_copy_word_debug = '0;
    assign mode5_backend_copy_flush_debug = '0;
    assign mode5_backend_copy_full_detect_count_debug = '0;
    assign mode5_backend_copy_push_req_count_debug = '0;
    assign mode5_backend_copy_push_fire_count_debug = '0;
    assign mode5_backend_copy_fifo_push_count_debug = '0;
    assign mode5_backend_copy_pack_ready_debug = '0;
    assign mode5_backend_copy_post_push_debug = '0;
    assign mode5_backend_read_gate_debug = '0;
    assign mode5_backend_read_after_copy_count_debug = '0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign smoke_ddr_payload_tap_count_debug = '0;
    assign smoke_ddr_last_read_index_debug = '0;
    assign smoke_ddr_last_read_data_debug = '0;
    assign smoke_ddr_last_read_word0_debug = '0;
    assign smoke_ddr_last_read_word1_debug = '0;
    assign smoke_ddr_probe_write_index_debug = '0;
    assign smoke_ddr_probe_write_word_debug = '0;
    assign smoke_ddr_probe_write_lane_debug = '0;
    assign smoke_ddr_probe_write_addr_debug = '0;
    assign smoke_ddr_probe_write_count_debug = '0;
    assign smoke_ddr_probe_write_flags_debug = '0;
    assign smoke_ddr_probe_write_word0_debug = '0;
    assign smoke_ddr_probe_write_word6_debug = '0;
`endif
    assign mode5_read_mux_debug = '0;
    assign mode5_read_ready_compare_debug = '0;
    assign mode5_read_ready_blocker_debug = '0;
    assign mode5_copy_mismatch_debug = '0;
    assign mode5_copy_max_ready_count_debug = '0;
    assign mode5_copy_min_remaining_debug = '0;
    assign mode5_restart_after_load_count_debug = '0;
    assign mode5_direct_start_debug = '0;
    assign mode5_top_stop_snapshot_debug = '0;
    assign vgm_data_start_debug = '0;
    assign vgm_current_pc_debug = '0;
    assign vgm_loop_pc_debug = '0;
    assign vgm_loop_valid_debug = '0;
    assign vgm_loop_taken_debug = '0;
    assign vgm_end_command_seen = '0;
    assign vgm_restarted_from_data_start = '0;
    assign vgm_pcm_oob = '0;
    assign vgm_pcm_oob_count = '0;
    assign vgm_wait_ticks_consumed_debug = '0;
    assign dac_stream_cmd_count = '0;
    assign dac_stream_wait_samples_total = '0;
    assign dac_stream_clk_cycles_total = '0;
    assign dac_stream_overhead_cycles_total = '0;
    assign max_dac_stream_cmd_cycles = '0;
    assign count_wait0_dac_stream_cmd = '0;
    assign count_wait0_overhead_nonzero = '0;
    assign segapcm_write_count = '0;
    assign segapcm_last_addr = '0;
    assign segapcm_last_data = '0;
    assign segapcm_core_rom_addr_low = '0;
    assign segapcm_core_rom_addr_raw_high = '0;
    assign segapcm_core_rom_addr_raw_low = '0;
    assign segapcm_core_rom_addr_mapped_high = '0;
    assign segapcm_core_rom_addr_mapped_low = '0;
    assign segapcm_core_rom_addr_min_high = '0;
    assign segapcm_core_rom_addr_min_low = '0;
    assign segapcm_core_rom_addr_max_high = '0;
    assign segapcm_core_rom_addr_max_low = '0;
    assign segapcm_core_rom_audio_active_high = '0;
    assign segapcm_core_rom_audio_active_low = '0;
    assign segapcm_core_rom_first_after_ctrl_high = '0;
    assign segapcm_core_rom_first_after_ctrl_low = '0;
    assign segapcm_core_rom_range_group = '0;
    assign segapcm_core_rom_range_group2 = '0;
    assign segapcm_core_rom_early_after_ctrl_high = '0;
    assign segapcm_core_rom_early_after_ctrl_low = '0;
    assign segapcm_core_rom_active_after_ctrl_high = '0;
    assign segapcm_core_rom_active_after_ctrl_low = '0;
    assign segapcm_core_rom_hit_miss_compact = '0;
    assign segapcm_core_rom_range_hit_count = '0;
    assign segapcm_core_rom_range_miss_count = '0;
    assign segapcm_core_rom_activity_count = '0;
    assign segapcm_core_rom_return_mapped_high = '0;
    assign segapcm_core_rom_return_mapped_low = '0;
    assign segapcm_core_rom_return_data = '0;
    assign segapcm_core_rom_return_last01 = '0;
    assign segapcm_core_rom_return_last23 = '0;
    assign segapcm_core_rom_return_nonzero_count = '0;
    assign segapcm_core_rom_return_change_count = '0;
    assign segapcm_core_rom_return_neutral_count = '0;
    assign segapcm_core_rom_preload_data = '0;
    assign segapcm_core_rom_core_ok_count = '0;
    assign segapcm_core_rom_fallback_count = '0;
    assign segapcm_core_rom_read_valid_count = '0;
    assign segapcm_core_rom_latency_debug = '0;
    assign segapcm_core_rom_payload_len_low = '0;
    assign segapcm_core_rom_payload_len_high = '0;
    assign segapcm_core_pcm_debug_bk = '0;
    assign segapcm_core_pcm_debug_cuh = '0;
    assign segapcm_core_pcm_debug_cul = '0;
    assign segapcm_core_known38686_flags = '0;
    assign segapcm_core_known38686_bank = '0;
    assign segapcm_core_known38686_channel = '0;
    assign segapcm_core_known38686_state = '0;
    assign segapcm_core_known38686_cur_high = '0;
    assign segapcm_core_known38686_cur_low = '0;
    assign segapcm_core_known38686_en_addr = '0;
    assign segapcm_core_known38686_en_value = '0;
    assign segapcm_core_known38686_d0_addr = '0;
    assign segapcm_core_known38686_d0_value = '0;
    assign segapcm_core_known38686_d1_addr = '0;
    assign segapcm_core_known38686_d1_value = '0;
    assign segapcm_core_known38686_d2_addr = '0;
    assign segapcm_core_known38686_d2_value = '0;
    assign segapcm_core_known38686_cfg_en = '0;
    assign segapcm_core_known38686_cur_23 = '0;
    assign segapcm_core_known38686_cur_15 = '0;
    assign segapcm_core_known38686_cur_07 = '0;
    assign segapcm_core_c0_capture_write_count = '0;
    assign segapcm_core_c0_capture_last_addr = '0;
    assign segapcm_core_c0_capture_last_data = '0;
    assign segapcm_core_c0_capture_channel_activity = '0;
    assign segapcm_core_c0_capture_selected_channel = '0;
    assign segapcm_core_c0_capture_ch3_ctrl = '0;
    assign segapcm_core_c0_capture_ch3_cur_low = '0;
    assign segapcm_core_c0_capture_ch3_cur_mid = '0;
    assign segapcm_core_c0_capture_ch3_cur_high = '0;
    assign segapcm_core_c0_capture_ch3_delta = '0;
    assign segapcm_core_c0_capture_ch3_vol_l = '0;
    assign segapcm_core_c0_capture_ch3_vol_r = '0;
    assign segapcm_core_c0_capture_ch3_loop = '0;
    assign segapcm_core_c0_capture_ch3_end = '0;
    assign segapcm_core_jt_smoke_vol_l = '0;
    assign segapcm_core_jt_smoke_vol_r = '0;
    assign segapcm_core_jt_smoke_sample_byte = '0;
    assign segapcm_core_jt_smoke_out_l = '0;
    assign segapcm_core_jt_smoke_out_r = '0;
    assign segapcm_core_ch3_evolution_flags = '0;
    assign segapcm_core_ch3_delta = '0;
    assign segapcm_core_ch1_first_high = '0;
    assign segapcm_core_ch1_first_low = '0;
    assign segapcm_core_ch1_first_raw_high = '0;
    assign segapcm_core_ch1_first_raw_low = '0;
    assign segapcm_core_ch3_first_high = '0;
    assign segapcm_core_ch3_first_low = '0;
    assign segapcm_core_ch3_first_raw_high = '0;
    assign segapcm_core_ch3_first_raw_low = '0;
    assign segapcm_core_ch3_r0_high = '0;
    assign segapcm_core_ch3_r0_low = '0;
    assign segapcm_core_ch3_r1_high = '0;
    assign segapcm_core_ch3_r1_low = '0;
    assign segapcm_core_ch3_r2_high = '0;
    assign segapcm_core_ch3_r2_low = '0;
    assign segapcm_core_ch3_load_after_23 = '0;
    assign segapcm_core_ch3_load_after_15 = '0;
    assign segapcm_core_ch3_load_after_07 = '0;
    assign segapcm_core_update_state_channel = '0;
    assign segapcm_core_update_before_23 = '0;
    assign segapcm_core_update_before_15 = '0;
    assign segapcm_core_update_before_07 = '0;
    assign segapcm_core_update_addend = '0;
    assign segapcm_core_update_after_23 = '0;
    assign segapcm_core_update_after_15 = '0;
    assign segapcm_core_update_after_07 = '0;
    assign segapcm_core_update_reason = '0;
    assign segapcm_jt_rv60_debug_bus = '0;
    assign segapcm_rv61_signature_bus = '0;
    assign segapcm_core_cpu_write_count = '0;
    assign segapcm_core_cpu_cen_write_count = '0;
    assign segapcm_core_cpu_addr_debug = '0;
    assign segapcm_core_shadow_decode_debug = '0;
    assign segapcm_core_shadow_ch0_vol_debug = '0;
    assign segapcm_core_shadow_ch0_end_delta_debug = '0;
    assign segapcm_core_shadow_ch0_start_debug = '0;
    assign segapcm_core_shadow_ch0_ctrl_debug = '0;
    assign segapcm_core_shadow_ch1_vol_debug = '0;
    assign segapcm_core_shadow_ch1_loop_debug = '0;
    assign segapcm_core_shadow_ch1_end_delta_debug = '0;
    assign segapcm_core_shadow_ch1_start_debug = '0;
    assign segapcm_core_shadow_ch1_ctrl_debug = '0;
    assign segapcm_core_shadow_ch3_loop_debug = '0;
    assign segapcm_core_shadow_ch3_end_delta_debug = '0;
    assign segapcm_core_shadow_ch3_start_debug = '0;
    assign segapcm_core_shadow_ch3_ctrl_debug = '0;
    assign segapcm_core_shadow_ch3_l0_debug = '0;
    assign segapcm_core_shadow_ch3_l2_debug = '0;
    assign segapcm_core_shadow_ch3_l4_debug = '0;
    assign segapcm_core_shadow_ch3_l6_debug = '0;
    assign segapcm_core_shadow_ch3_h0_debug = '0;
    assign segapcm_core_shadow_ch3_h2_debug = '0;
    assign segapcm_core_shadow_ch3_h4_debug = '0;
    assign segapcm_core_shadow_ch3_h6_debug = '0;
    assign segapcm_core_audio_nonzero_count = '0;
    assign segapcm_core_audio_abs_peak = '0;
    assign segapcm_core_last_audio_l = '0;
    assign segapcm_core_last_audio_r = '0;
    assign segapcm_core_status_debug = '0;
    assign segapcm_block6_probe_b6_debug = '0;
    assign segapcm_block6_probe_r6_debug = '0;
    assign segapcm_block6_probe_h6_debug = '0;
    assign segapcm_block6_probe_c6_debug = '0;
    assign segapcm_block6_probe_m6_debug = '0;
    assign data_block_count = '0;
    assign last_data_block_type = '0;
    assign last_data_block_size_low = '0;
    assign parser_data_block_count_debug = '0;
    assign parser_last_block_type_debug = '0;
    assign parser_type00_block_count_debug = '0;
    assign parser_type80_block_count_debug = '0;
    assign segapcm_rom_block_count = '0;
    assign segapcm_last_rom_size = '0;
    assign segapcm_last_rom_start = '0;
    assign pcm_ram_write_skip_count = '0;
    assign segapcm_rom_scan_busy = '0;
    assign segapcm_rom_scan_done = '0;
    assign segapcm_rom_scan_overflow = '0;
    assign segapcm_rom_scan_block_count = '0;
    assign segapcm_rom_scan_byte_count = '0;
    assign segapcm_rom_scan_checksum32 = '0;
    assign segapcm_rom_scan_total_size = '0;
    assign segapcm_rom_scan_last_start = '0;
    assign segapcm_rom_copy_byte_count = '0;
    assign segapcm_rom_copy_overflow = '0;
    assign segapcm_rom_copy_flush_done = '0;
    assign segapcm_copy_flush_req_debug = '0;
    assign mode5_sound_reset_active = '0;
    assign mode5_player_start_pulse_debug = '0;
    assign mode5_start_hold_debug = '0;
    assign mode5_load_begin_count = '0;
    assign mode5_load_done_edge_count = '0;
    assign mode5_sound_reset_start_count = '0;
    assign mode5_player_start_count = '0;
    assign mode5_player_reset_count = '0;
    assign mode5_playback_session_id = '0;
    assign mode5_duplicate_start_blocked_count = '0;
    assign mode5_player_end_count = '0;
    assign mode5_repeat_restart_count = '0;
    assign mode5_done_armed_debug = '0;
    assign mode5_repeat_session_id = '0;
    assign mode5_done_session_id = '0;
    assign mode5_cycles_since_start = '0;
    assign mode5_done_pc_debug = '0;
    assign mode5_done_cmd_debug = '0;
    assign fm_adjust_clip_count_l = '0;
    assign fm_adjust_clip_count_r = '0;
    assign genmix_wrap_count_l = '0;
    assign genmix_wrap_count_r = '0;
    assign ym_write_requested_count = '0;
    assign ym_write_accepted_count = '0;
    assign ym_write_dropped_or_busy_count = '0;
    assign ym_port0_count = '0;
    assign ym_port1_count = '0;
    assign last_ym_port = '0;
    assign last_ym_addr = '0;
    assign last_ym_data = '0;
    assign jt12_cen_interval_1_count = '0;
    assign jt12_cen_interval_2_count = '0;
    assign jt12_cen_interval_3_count = '0;
    assign jt12_cen_interval_4_count = '0;
    assign jt12_cen_interval_ge5_count = '0;
    assign jt12_cen_interval_min = '0;
    assign jt12_cen_interval_max = '0;
    assign jt12_cen_interval_last = '0;
    assign fm_raw_abs_peak = '0;
    assign fm_adjust_abs_peak = '0;
    assign fm_lpf_abs_peak = '0;
    assign genmix_abs_peak = '0;
    assign md_final_audio_abs_peak = '0;
    assign c0_top_dbg_tp = '0;
    assign c0_top_dbg_sl = '0;
    assign c0_top_dbg_sr = '0;
    assign c0_top_dbg_ml = '0;
    assign c0_top_dbg_mr = '0;
    assign c0_top_dbg_fl = '0;
    assign c0_top_dbg_fr = '0;
    assign c0_top_dbg_ol = '0;
    assign c0_top_dbg_or = '0;
    assign c0_top_dbg_tm = '0;

    wire unused_stage_a = ^{
        REGION_MODE,
        MODE5_VGM_BACKEND,
        POWER_ON_RESET_CYCLES,
        START_DELAY_CYCLES,
        INIT_AUDIO_SAMPLE_EDGES,
        AUDIO_WARMUP_SAMPLES,
        GATE_TO_START_CYCLES,
        CLK_SYS_HZ,
        VGM_WAIT_HZ,
        MODE5_SOUND_RESET_CYCLES,
        MODE5_AUDIO_UNMUTE_DELAY_CYCLES,
        MODE5_REPEAT_ENABLE,
        SEGAPCM_EXPERIMENTAL_MIX_MODE,
        REPLAY_ENABLE,
        PLAYER_RESET_CYCLES,
        START_ACCEPT_TIMEOUT_CYCLES,
        PLAYER_DONE_TIMEOUT_TICKS,
        REPLAY_DELAY_TICKS,
        upload_load_done_pulse,
        profile_pcm_a_read_request,
        profile_pcm_a_read_address,
        profile_pcm_b_read_request,
        profile_pcm_b_read_address,
        profile_status,
        profile_debug_page_data,
        sound_write_count
    };

endmodule
