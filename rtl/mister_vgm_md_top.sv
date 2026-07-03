// Minimal MiSTer-facing top wrapper for the fixed-region MD sound test.
//
// This is not a complete MiSTer "emu" core yet. It is a small bridge intended
// to be instantiated from a future MiSTer core skeleton:
//
//   MiSTer/core clock + reset
//       -> mister_vgm_md_top
//       -> md_sound_fixed_region_test
//       -> audio_l/audio_r
//
// REGION_MODE=0..4 keep the fixed-region path. REGION_MODE=5 adds the first
// small BRAM-backed HPS/OSD-loaded VGM path.
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
    input  logic        [1:0] segapcm_smoke_c0_sample_mode,
    input  logic        [2:0] segapcm_smoke_c0_vol_map,
    input  logic        [1:0] segapcm_smoke_c0_drive,
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
    output logic [15:0]       segapcm_core_update_state_channel,
    output logic [15:0]       segapcm_core_update_before_23,
    output logic [15:0]       segapcm_core_update_before_15,
    output logic [15:0]       segapcm_core_update_before_07,
    output logic [15:0]       segapcm_core_update_addend,
    output logic [15:0]       segapcm_core_update_after_23,
    output logic [15:0]       segapcm_core_update_after_15,
    output logic [15:0]       segapcm_core_update_after_07,
    output logic [15:0]       segapcm_core_update_reason,
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

`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
`ifndef MEGAVGMDRIVE_SEGAPCM_AUDIO_STUB_BUILD
`define MEGAVGMDRIVE_SEGAPCM_AUDIO_STUB_BUILD
`endif
`elsif MEGAVGMDRIVE_SEGAPCM_ONLY_DEBUG_BUILD
`ifndef MEGAVGMDRIVE_SEGAPCM_AUDIO_STUB_BUILD
`define MEGAVGMDRIVE_SEGAPCM_AUDIO_STUB_BUILD
`endif
`endif

`ifdef MEGAVGMDRIVE_SEGAPCM_AUDIO_STUB_BUILD
    localparam bit YM2151_EXPERIMENTAL_MODE = 1'b1;
`elsif MEGAVGMDRIVE_YM2151_MODE_TEST
    localparam bit YM2151_EXPERIMENTAL_MODE = 1'b1;
`else
    localparam bit YM2151_EXPERIMENTAL_MODE = 1'b0;
`endif
`ifdef MEGAVGMDRIVE_START_HOLD_NO_BUSY_CLEAR
    localparam bit START_HOLD_NO_BUSY_CLEAR = 1'b1;
`else
    localparam bit START_HOLD_NO_BUSY_CLEAR = 1'b0;
`endif
`ifdef MEGAVGMDRIVE_DIRECT_PLAYER_START_DEBUG
    localparam bit DIRECT_PLAYER_START_DEBUG = 1'b1;
`else
    localparam bit DIRECT_PLAYER_START_DEBUG = 1'b0;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_PARSER_RUN_TEST
    localparam bit SEGAPCM_SMOKE_PARSER_RUN_TEST = 1'b1;
`else
    localparam bit SEGAPCM_SMOKE_PARSER_RUN_TEST = 1'b0;
`endif

    localparam int MODE5_BACKEND_BRAM  = 0;
    localparam int MODE5_BACKEND_DDRAM = 1;

    logic        reset;
    logic [2:0]  reset_sync = 3'b111;
    logic        external_reset;

    // These initialization values are intentional for hardware bring-up:
    // when reset_n is already high at FPGA configuration completion, the
    // startup sequence still begins from a known "POR not done / not started"
    // state without waiting for a reset_n edge.
    logic [31:0] por_counter = 32'd0;
    logic        por_done = 1'b0;
    logic [31:0] start_delay_counter = 32'd0;
    logic [15:0] init_audio_edge_count = 16'd0;
    logic [15:0] audio_warmup_count = 16'd0;
    logic [15:0] gate_to_start_count = 16'd0;
    logic        start_sent = 1'b0;
    logic        start_pulse = 1'b0;
    logic        audio_sample_valid_d = 1'b0;
    logic [31:0] vgm_wait_accum = 32'd0;
    logic        vgm_wait_tick = 1'b0;
    logic        player_reset_active = 1'b0;
    logic [31:0] player_reset_counter = 32'd0;
    logic [31:0] start_accept_counter = 32'd0;
    logic [31:0] player_done_timeout_ticks = 32'd0;
    logic [31:0] replay_delay_ticks = 32'd0;
    logic signed [15:0] raw_audio_l;
    logic signed [15:0] raw_audio_r;
    logic               raw_audio_sample_valid;
    logic               audio_runtime_open;

    typedef enum logic [3:0] {
        STARTUP_RESET,
        STARTUP_AUDIO_MUTED,
        STARTUP_SOUND_INIT_WAIT,
        STARTUP_AUDIO_WARMUP,
        STARTUP_GATE_OPEN_WAIT,
        STARTUP_WAIT_PLAYER_BUSY,
        STARTUP_PLAYING,
        STARTUP_REPLAY_WAIT,
        STARTUP_RETRY_RESET
    } startup_state_t;

    startup_state_t startup_state = STARTUP_RESET;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            reset_sync <= 3'b111;
        end else begin
            reset_sync <= {reset_sync[1:0], 1'b0};
        end
    end

    assign external_reset = reset_sync[2];

    assign reset = external_reset | !por_done;

    assign startup_reset_active = !por_done ||
                                  player_reset_active ||
                                  (startup_state == STARTUP_RESET) ||
                                  (startup_state == STARTUP_RETRY_RESET);
    assign startup_waiting = (startup_state == STARTUP_AUDIO_MUTED) ||
                             (startup_state == STARTUP_SOUND_INIT_WAIT) ||
                             (startup_state == STARTUP_AUDIO_WARMUP) ||
                             (startup_state == STARTUP_GATE_OPEN_WAIT) ||
                             (startup_state == STARTUP_WAIT_PLAYER_BUSY) ||
                             (startup_state == STARTUP_REPLAY_WAIT);
    assign startup_done = (startup_state == STARTUP_PLAYING) ||
                          (startup_state == STARTUP_REPLAY_WAIT);

    assign audio_sample_valid = raw_audio_sample_valid;
    assign audio_muted = !audio_runtime_open;
    assign audio_l = audio_runtime_open ? raw_audio_l : 16'sd0;
    assign audio_r = audio_runtime_open ? raw_audio_r : 16'sd0;

    always_ff @(posedge clk) begin
        if (reset) begin
            vgm_wait_accum <= 32'd0;
            vgm_wait_tick  <= 1'b0;
        end else begin
            if (vgm_wait_accum >= (CLK_SYS_HZ - VGM_WAIT_HZ)) begin
                vgm_wait_accum <= vgm_wait_accum + VGM_WAIT_HZ - CLK_SYS_HZ;
                vgm_wait_tick  <= 1'b1;
            end else begin
                vgm_wait_accum <= vgm_wait_accum + VGM_WAIT_HZ;
                vgm_wait_tick  <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (external_reset) begin
            por_counter <= 32'd0;
            por_done <= 1'b0;
            start_delay_counter <= 32'd0;
            init_audio_edge_count <= 16'd0;
            audio_warmup_count <= 16'd0;
            gate_to_start_count <= 16'd0;
            start_sent <= 1'b0;
            start_pulse <= 1'b0;
            audio_gate_open <= 1'b0;
            audio_sample_valid_d <= 1'b0;
            player_reset_active <= 1'b0;
            player_reset_counter <= 32'd0;
            start_accept_counter <= 32'd0;
            player_done_timeout_ticks <= 32'd0;
            replay_delay_ticks <= 32'd0;
            startup_state <= STARTUP_RESET;
        end else begin
            start_pulse <= 1'b0;
            audio_sample_valid_d <= audio_sample_valid;

            unique case (startup_state)
                STARTUP_RESET: begin
                    audio_gate_open <= 1'b0;
                    start_delay_counter <= 32'd0;
                    init_audio_edge_count <= 16'd0;
                    audio_warmup_count <= 16'd0;
                    gate_to_start_count <= 16'd0;
                    player_reset_active <= 1'b0;
                    player_reset_counter <= 32'd0;
                    start_accept_counter <= 32'd0;
                    player_done_timeout_ticks <= 32'd0;
                    replay_delay_ticks <= 32'd0;
                    start_sent <= 1'b0;

                    if (!por_done) begin
                        if (por_counter >= POWER_ON_RESET_CYCLES) begin
                            por_done <= 1'b1;
                        end else begin
                            por_counter <= por_counter + 32'd1;
                        end
                    end else begin
                        startup_state <= STARTUP_AUDIO_MUTED;
                    end
                end

                STARTUP_AUDIO_MUTED: begin
                    audio_gate_open <= 1'b0;
                    if (start_delay_counter >= START_DELAY_CYCLES) begin
                        startup_state <= STARTUP_SOUND_INIT_WAIT;
                    end else begin
                        start_delay_counter <= start_delay_counter + 32'd1;
                    end
                end

                STARTUP_SOUND_INIT_WAIT: begin
                    audio_gate_open <= 1'b0;
                    if (audio_sample_valid && !audio_sample_valid_d) begin
                        if (init_audio_edge_count >= INIT_AUDIO_SAMPLE_EDGES) begin
                            startup_state <= STARTUP_AUDIO_WARMUP;
                        end else begin
                            init_audio_edge_count <= init_audio_edge_count + 16'd1;
                        end
                    end
                end

                STARTUP_AUDIO_WARMUP: begin
                    audio_gate_open <= 1'b0;
                    if (audio_sample_valid && !audio_sample_valid_d) begin
                        if (audio_warmup_count >= AUDIO_WARMUP_SAMPLES) begin
                            startup_state <= STARTUP_GATE_OPEN_WAIT;
                        end else begin
                            audio_warmup_count <= audio_warmup_count + 16'd1;
                        end
                    end
                end

                STARTUP_GATE_OPEN_WAIT: begin
                    audio_gate_open <= 1'b1;
                    if (gate_to_start_count >= GATE_TO_START_CYCLES) begin
                        start_pulse <= 1'b1;
                        start_sent <= 1'b1;
                        start_accept_counter <= 32'd0;
                        player_done_timeout_ticks <= 32'd0;
                        startup_state <= STARTUP_WAIT_PLAYER_BUSY;
                    end else begin
                        gate_to_start_count <= gate_to_start_count + 16'd1;
                    end
                end

                STARTUP_WAIT_PLAYER_BUSY: begin
                    audio_gate_open <= 1'b1;

                    if (player_busy) begin
                        player_done_timeout_ticks <= 32'd0;
                        startup_state <= STARTUP_PLAYING;
                    end else if (start_accept_counter >= START_ACCEPT_TIMEOUT_CYCLES) begin
                        player_reset_active <= 1'b1;
                        player_reset_counter <= 32'd0;
                        startup_state <= STARTUP_RETRY_RESET;
                    end else begin
                        start_accept_counter <= start_accept_counter + 32'd1;
                    end
                end

                STARTUP_PLAYING: begin
                    audio_gate_open <= 1'b1;

                    if ((REGION_MODE != 5) && player_done) begin
                        if (REPLAY_ENABLE) begin
                            replay_delay_ticks <= 32'd0;
                            startup_state <= STARTUP_REPLAY_WAIT;
                        end
                    end else if ((REGION_MODE != 5) && vgm_wait_tick) begin
                        if (player_done_timeout_ticks >= PLAYER_DONE_TIMEOUT_TICKS) begin
                            player_reset_active <= 1'b1;
                            player_reset_counter <= 32'd0;
                            startup_state <= STARTUP_RETRY_RESET;
                        end else begin
                            player_done_timeout_ticks <= player_done_timeout_ticks + 32'd1;
                        end
                    end
                end

                STARTUP_REPLAY_WAIT: begin
                    audio_gate_open <= 1'b1;

                    if (!REPLAY_ENABLE) begin
                        startup_state <= STARTUP_REPLAY_WAIT;
                    end else if (vgm_wait_tick) begin
                        if (replay_delay_ticks >= REPLAY_DELAY_TICKS) begin
                            player_reset_active <= 1'b1;
                            player_reset_counter <= 32'd0;
                            startup_state <= STARTUP_RETRY_RESET;
                        end else begin
                            replay_delay_ticks <= replay_delay_ticks + 32'd1;
                        end
                    end
                end

                STARTUP_RETRY_RESET: begin
                    audio_gate_open <= 1'b0;
                    player_reset_active <= 1'b1;
                    start_sent <= 1'b0;
                    start_accept_counter <= 32'd0;
                    player_done_timeout_ticks <= 32'd0;
                    replay_delay_ticks <= 32'd0;
                    gate_to_start_count <= 16'd0;

                    if (player_reset_counter >= PLAYER_RESET_CYCLES) begin
                        player_reset_active <= 1'b0;
                        player_reset_counter <= 32'd0;
                        startup_state <= STARTUP_GATE_OPEN_WAIT;
                    end else begin
                        player_reset_counter <= player_reset_counter + 32'd1;
                    end
                end

                default: begin
                    audio_gate_open <= 1'b0;
                    startup_state <= STARTUP_RESET;
                end
            endcase
        end
    end

    generate
        if (REGION_MODE == 5) begin : loaded_vgm_mode
            logic [VGM_LOAD_ADDR_WIDTH-1:0] ram_rd_addr;
            logic [7:0] ram_rd_data;
            logic mem_rd_req;
            logic [VGM_LOAD_ADDR_WIDTH-1:0] mem_rd_addr;
            logic mem_rd_ready;
            logic mem_rd_valid;
            logic [7:0] mem_rd_data;
            logic segapcm_copy_wr_req;
            logic segapcm_copy_wr_ready;
            logic [18:0] segapcm_copy_wr_addr;
            logic [7:0] segapcm_copy_wr_data;
            logic segapcm_copy_flush_req;
            logic segapcm_copy_flush_done;
            logic segapcm_payload_tap_valid;
            logic [18:0] segapcm_payload_tap_addr;
            logic [7:0] segapcm_payload_tap_data;
            logic [31:0] segapcm_payload_tap_byte_count;
            logic [31:0] segapcm_tap_block_size;
            logic [31:0] segapcm_tap_block_start;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
            logic smoke_ddr_rd_req;
            logic smoke_ddr_rd_ready;
            logic [18:0] smoke_ddr_rd_addr;
            logic smoke_ddr_rd_valid;
            logic [7:0] smoke_ddr_rd_data;
            logic smoke_ddr_payload_present;
            logic [18:0] smoke_ddr_payload_length;
            logic [15:0] smoke_ddr_write_req_count_debug;
            logic [15:0] smoke_ddr_write_count_debug;
            logic [15:0] smoke_ddr_write_blocked_count_debug;
            logic [15:0] smoke_ddr_write_status_debug;
            logic [15:0] smoke_ddr_header_skip_count_debug;
            logic [15:0] smoke_ddr_last_write_index_debug;
            logic [15:0] smoke_ddr_last_write_addr_debug;
            logic [15:0] smoke_ddr_last_write_lane_debug;
            logic [7:0] smoke_ddr_last_write_data_debug;
            logic [15:0] smoke_ddr_read_count_debug;
            logic [15:0] smoke_ddr_last_read_index_i;
            logic [15:0] smoke_ddr_last_read_addr_debug;
            logic [15:0] smoke_ddr_last_read_lane_debug;
            logic [15:0] smoke_ddr_last_read_word0_i;
            logic [15:0] smoke_ddr_last_read_word1_i;
            logic [7:0] smoke_ddr_last_read_data_i;
            logic [15:0] smoke_ddr_base_addr_debug;
            logic [15:0] smoke_ddr_probe_write_index_i;
            logic [15:0] smoke_ddr_probe_write_word_i;
            logic [15:0] smoke_ddr_probe_write_lane_i;
            logic [15:0] smoke_ddr_probe_write_addr_i;
            logic [15:0] smoke_ddr_probe_write_count_i;
            logic [15:0] smoke_ddr_probe_write_flags_i;
            logic [15:0] smoke_ddr_probe_write_word0_i;
            logic [15:0] smoke_ddr_probe_write_word6_i;
            logic [31:0] smoke_ddr_type80_payload_len_32;
            logic [18:0] smoke_ddr_type80_payload_len_19;
            logic [31:0] smoke_ddr_type80_dest_addr;
            logic [31:0] smoke_ddr_type80_block_size;
            logic [18:0] smoke_ddr_capture_limit;
            always @* begin
                smoke_ddr_type80_block_size = segapcm_tap_block_size;
                if (smoke_ddr_type80_block_size == 32'd0) begin
                    smoke_ddr_type80_block_size = segapcm_last_rom_size;
                end

                smoke_ddr_type80_payload_len_32 = 32'd0;
                if (smoke_ddr_type80_block_size > 32'd8) begin
                    smoke_ddr_type80_payload_len_32 =
                        smoke_ddr_type80_block_size - 32'd8;
                end

                smoke_ddr_type80_payload_len_19 =
                    smoke_ddr_type80_payload_len_32[18:0];
                if (smoke_ddr_type80_payload_len_32 >
                    32'h0007_ffff) begin
                    smoke_ddr_type80_payload_len_19 = 19'h7ffff;
                end

                smoke_ddr_capture_limit = 19'h01000;
                if (segapcm_smoke_ddr_full_capture) begin
                    smoke_ddr_capture_limit = 19'h7ffff;
                end

                smoke_ddr_type80_dest_addr = 32'd0;
                if (segapcm_tap_block_size != 32'd0) begin
                    smoke_ddr_type80_dest_addr = segapcm_tap_block_start;
                end else begin
                    if (segapcm_rom_scan_last_start != 32'd0) begin
                        smoke_ddr_type80_dest_addr = segapcm_rom_scan_last_start;
                    end
                    if (segapcm_last_rom_start != 32'd0) begin
                        smoke_ddr_type80_dest_addr = segapcm_last_rom_start;
                    end
                end
            end
            assign smoke_ddr_payload_tap_count_debug = smoke_ddr_write_req_count_debug;
            assign smoke_ddr_last_read_index_debug = smoke_ddr_last_read_index_i;
            assign smoke_ddr_last_read_data_debug = smoke_ddr_last_read_data_i;
            assign smoke_ddr_last_read_word0_debug = smoke_ddr_last_read_word0_i;
            assign smoke_ddr_last_read_word1_debug = smoke_ddr_last_read_word1_i;
            assign smoke_ddr_probe_write_index_debug = smoke_ddr_probe_write_index_i;
            assign smoke_ddr_probe_write_word_debug = smoke_ddr_probe_write_word_i;
            assign smoke_ddr_probe_write_lane_debug = smoke_ddr_probe_write_lane_i;
            assign smoke_ddr_probe_write_addr_debug = smoke_ddr_probe_write_addr_i;
            assign smoke_ddr_probe_write_count_debug = smoke_ddr_probe_write_count_i;
            assign smoke_ddr_probe_write_flags_debug = smoke_ddr_probe_write_flags_i;
            assign smoke_ddr_probe_write_word0_debug = smoke_ddr_probe_write_word0_i;
            assign smoke_ddr_probe_write_word6_debug = smoke_ddr_probe_write_word6_i;
`endif
            logic load_done_pulse;
            logic play_ready_pulse;
            logic ym_cmd_valid;
            logic ym_cmd_port;
            logic [7:0] ym_cmd_reg;
            logic [7:0] ym_cmd_data;
            logic psg_cmd_valid;
            logic [7:0] psg_cmd_data;
            logic ym_cmd_ready;
            logic psg_cmd_ready;
            logic ym2151_cmd_valid;
            logic ym2151_cmd_ready;
            logic [7:0] ym2151_cmd_reg;
            logic [7:0] ym2151_cmd_data;
            logic [31:0] ym2151_write_count;
            logic [7:0] ym2151_last_reg;
            logic [7:0] ym2151_last_data;
            logic [31:0] ym2151_unsupported_command_count;
            logic segapcm_cmd_valid;
            logic [15:0] segapcm_cmd_addr;
            logic [7:0] segapcm_cmd_data;
            logic [31:0] md_ym_write_requested_count;
            logic [31:0] md_ym_write_accepted_count;
            logic [31:0] md_ym_write_dropped_or_busy_count;
            logic [31:0] md_ym_port0_count;
            logic [31:0] md_ym_port1_count;
            logic md_last_ym_port;
            logic [7:0] md_last_ym_addr;
            logic [7:0] md_last_ym_data;
            logic signed [15:0] md_audio_l;
            logic signed [15:0] md_audio_r;
            logic md_audio_sample_valid;
            logic signed [15:0] ym2151_audio_l;
            logic signed [15:0] ym2151_audio_r;
            logic ym2151_audio_sample_valid;
            logic signed [15:0] segapcm_audio_l;
            logic signed [15:0] segapcm_audio_r;
            logic segapcm_audio_sample_valid;
            logic signed [15:0] segapcm_audio_l_mix;
            logic signed [15:0] segapcm_audio_r_mix;
            logic signed [16:0] ym2151_segapcm_l_sum;
            logic signed [16:0] ym2151_segapcm_r_sum;
            logic signed [15:0] ym2151_segapcm_audio_l;
            logic signed [15:0] ym2151_segapcm_audio_r;
            logic signed [15:0] ym2151_segapcm_selected_l;
            logic signed [15:0] ym2151_segapcm_selected_r;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef SEGA_PCM_STARTUP_SMOKE
            wire segapcm_smoke_output_enabled = 1'b1;
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
            wire segapcm_smoke_output_enabled =
                segapcm_smoke_source_loaded && smoke_ddr_payload_present;
`else
            wire segapcm_smoke_output_enabled = 1'b0;
`endif
`endif
            logic mode5_sound_reset_active_i = 1'b0;
            logic mode5_sound_core_reset;
            logic mode5_continue_reset_block;
            logic mode5_player_start_pulse = 1'b0;
            logic mode5_player_start_hold = 1'b0;
            logic mode5_player_start_to_player;
            logic mode5_direct_player_start_hold = 1'b0;
            logic smoke_parser_start_hold = 1'b0;
            logic smoke_parser_start_used = 1'b0;
            logic loaded_player_start_input_live;
            logic loaded_player_start_input_normal;
            logic smoke_parser_run_enable;
            logic smoke_parser_start_to_player;
            logic smoke_parser_loaded_player_reset;
            logic mode5_loaded_player_reset;
            logic loaded_player_busy;
            logic mode5_player_start_hold_seen = 1'b0;
            logic mode5_start_hold_clear_by_busy = 1'b0;
            logic mode5_start_hold_clear_by_done = 1'b0;
            logic mode5_start_hold_clear_by_error = 1'b0;
            logic mode5_start_hold_clear_by_load_reset = 1'b0;
            logic mode5_start_hold_clear_by_other = 1'b0;
            logic mode5_start_hold_clear_by_start_seen = 1'b0;
            logic mode5_start_hold_clear_by_header_request = 1'b0;
            logic mode5_start_hold_clear_by_header_valid = 1'b0;
            logic mode5_start_hold_lost_without_accept = 1'b0;
            logic mode5_start_hold_prev = 1'b0;
            logic [31:0] mode5_sound_reset_counter = 32'd0;
            logic ioctl_download_d = 1'b0;
            logic mode5_load_begin_pulse;
            logic mode5_load_session_active = 1'b0;
            logic mode5_playback_armed = 1'b0;
            logic mode5_playback_started = 1'b0;
            logic mode5_player_session_reset = 1'b0;
            logic [31:0] mode5_audio_unmute_counter = 32'd0;
            logic mode5_audio_unmute_ready = 1'b0;
            logic mode5_audio_pre_unmute;
            logic [31:0] mode5_load_begin_count_i = 32'd0;
            logic [31:0] mode5_load_done_edge_count_i = 32'd0;
            logic [31:0] mode5_sound_reset_start_count_i = 32'd0;
            logic [31:0] mode5_player_start_count_i = 32'd0;
            logic [31:0] mode5_player_reset_count_i = 32'd0;
            logic [31:0] mode5_playback_session_id_i = 32'd0;
            logic [31:0] mode5_duplicate_start_blocked_count_i = 32'd0;
            logic [31:0] mode5_player_end_count_i = 32'd0;
            logic [31:0] mode5_repeat_restart_count_i = 32'd0;
            logic mode5_done_armed_i = 1'b0;
            logic [31:0] mode5_done_armed_session_id_i = 32'd0;
            logic [31:0] mode5_repeat_session_id_i = 32'd0;
            logic [31:0] mode5_done_session_id_i = 32'd0;
            logic [31:0] mode5_cycles_since_start_i = 32'd0;
            logic [VGM_LOAD_ADDR_WIDTH-1:0] mode5_done_pc_debug_i = '0;
            logic [7:0] mode5_done_cmd_debug_i = 8'd0;
            logic [15:0] mode5_top_stop_snapshot_debug_i = 16'd0;
            logic [VGM_LOAD_ADDR_WIDTH-1:0] player_done_pc_debug;
            logic [7:0] player_done_cmd_debug;
            logic loaded_player_done;
            logic player_done_d = 1'b0;
            logic mode5_player_done_latched = 1'b0;
            logic vgm_player_error_d = 1'b0;
            logic [31:0] mode5_error_session_id_i = 32'd0;
            logic mode5_done_edge;
            logic mode5_player_error_edge;
            logic mode5_load_ready_level;
            logic mode5_top_file_ok;
            logic mode5_direct_start_used = 1'b0;
            logic loaded_player_start_input_live_d = 1'b0;
            logic segapcm_rom_scan_busy_d = 1'b0;
            logic [15:0] mode5_copy_max_ready_count_i = 16'd0;
            logic [15:0] mode5_copy_min_remaining_i = 16'hffff;
            logic [15:0] mode5_backend_copy_accept_max_i = 16'd0;
            logic [15:0] mode5_backend_copy_write_max_i = 16'd0;
            logic [15:0] mode5_payload_len_low_i = 16'd0;
            logic mode5_remaining_zero_early_seen_i = 1'b0;
            logic [15:0] mode5_zero_state_debug_i = 16'd0;
            logic [15:0] mode5_zero_pc_debug_i = 16'd0;
            logic [15:0] mode5_zero_cmd_debug_i = 16'd0;
            logic [15:0] mode5_raw_event_seen_i = 16'd0;
            logic [15:0] mode5_raw_copy_byte_max_i = 16'd0;
            logic [15:0] mode5_restart_after_load_count_i = 16'd0;
            logic [15:0] mode5_start_attempt_count_i = 16'd0;
            logic [15:0] mode5_scan_start_count_i = 16'd0;
            logic mode5_copy_fifo_full_seen_i = 1'b0;
            logic mode5_copy_ready_low_seen_i = 1'b0;
            logic mode5_freeze_active = 1'b0;
            logic mode5_freeze_play_seen = 1'b0;
            logic mode5_freeze_event;
            logic [6:0] mode5_freeze_final_state = 7'd0;
            logic [VGM_LOAD_ADDR_WIDTH-1:0] mode5_freeze_final_pc = '0;
            logic [7:0] mode5_freeze_final_cmd = 8'd0;
            logic [7:0] mode5_freeze_final_error_code = 8'd0;
            logic [15:0] mode5_freeze_final_flags = 16'd0;
            logic [3:0] mode5_freeze_final_reason = 4'd0;
            logic [15:0] mode5_freeze_final_progress = 16'd0;
            logic [7:0] mode5_freeze_first_playback_cmd = 8'd0;
            logic [31:0] mode5_freeze_first_playback_cmds = 32'd0;
            logic [6:0] mode5_freeze_scan_state = 7'd0;
            logic [VGM_LOAD_ADDR_WIDTH-1:0] mode5_freeze_scan_pc = '0;
            logic [7:0] mode5_freeze_scan_last_cmd = 8'd0;
            logic [7:0] mode5_freeze_scan_block_type = 8'd0;
            logic [15:0] mode5_freeze_scan_block_size_low = 16'd0;
            logic [15:0] mode5_freeze_scan_remaining_low = 16'd0;
            logic [15:0] mode5_freeze_scan_wait = 16'd0;
            logic [7:0] mode5_freeze_scan_abort_reason = 8'd0;
            logic [15:0] mode5_freeze_scan_copy_last_index_low = 16'd0;
            logic [15:0] mode5_freeze_scan_copy_req_count = 16'd0;
            logic [15:0] mode5_freeze_scan_copy_ready_count = 16'd0;
            logic [15:0] mode5_freeze_scan_copy_tail = 16'd0;
            logic [6:0] vgm_final_state_debug_live;
            logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_final_pc_debug_live;
            logic [7:0] vgm_final_cmd_debug_live;
            logic [7:0] vgm_final_error_code_debug_live;
            logic [15:0] vgm_final_flags_debug_live;
            logic [3:0] vgm_final_reason_debug_live;
            logic [15:0] vgm_final_progress_debug_live;
            logic [7:0] vgm_first_playback_cmd_after_scan_debug_live;
            logic [31:0] vgm_first_playback_cmds_after_scan_debug_live;
            logic [6:0] vgm_scan_state_debug_live;
            logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_scan_pc_debug_live;
            logic [7:0] vgm_scan_last_cmd_debug_live;
            logic [7:0] vgm_scan_block_type_debug_live;
            logic [15:0] vgm_scan_block_size_low_debug_live;
            logic [15:0] vgm_scan_remaining_low_debug_live;
            logic [15:0] vgm_scan_wait_debug_live;
            logic [7:0] vgm_scan_abort_reason_debug_live;
            logic [15:0] vgm_scan_copy_last_index_low_debug_live;
            logic [15:0] vgm_scan_copy_req_count_debug_live;
            logic [15:0] vgm_scan_copy_ready_count_debug_live;
            logic [15:0] vgm_scan_copy_tail_debug_live;
            logic [15:0] vgm_scan_player_accept_count_debug_live;
            logic [15:0] vgm_scan_player_remaining_debug_live;
            logic [15:0] vgm_scan_payload_len_low_debug_live;
            logic [15:0] vgm_scan_copy_accept_fire_count_debug_live;
            logic [15:0] vgm_scan_noncopy_advance_count_debug_live;
            logic vgm_scan_used_noncopy_advance_debug_live;
            logic [15:0] vgm_scan_raw_copy_byte_count_debug_live;
            logic [15:0] vgm_scan_raw_event_debug_live;
            logic [15:0] vgm_scan_copy_exit_debug_live;
            logic [15:0] vgm_scan_copy_exit_pc_debug_live;
            logic [15:0] vgm_scan_copy_exit_count_debug_live;
            logic [15:0] vgm_scan_copy_phase_debug_live;
            logic [15:0] vgm_scan_copy_read_req_count_debug_live;
            logic [15:0] vgm_scan_copy_read_accept_count_debug_live;
            logic [15:0] vgm_scan_copy_read_valid_count_debug_live;
            logic [15:0] vgm_scan_copy_mem_req_cycle_count_debug_live;
            logic [15:0] vgm_scan_copy_mem_req_ready_cycle_count_debug_live;
            logic [15:0] vgm_scan_copy_request_state_debug_live;
            logic [15:0] vgm_scan_copy_state_lifetime_debug_live;
            logic [15:0] vgm_scan_copy_clear_reason_debug_live;
            logic [15:0] vgm_scan_copy_payload_pc_debug_live;
            logic [15:0] vgm_scan_copy_first01_debug_live;
            logic [15:0] vgm_scan_copy_first23_debug_live;
            logic [15:0] vgm_scan_copy_first45_debug_live;
            logic [15:0] vgm_scan_copy_first67_debug_live;
            logic [15:0] vgm_scan_copy_first8_phase_debug_live;
            logic [15:0] vgm_scan_copy_read_raw_valid_count_debug_live;
            logic [15:0] vgm_scan_copy_read_ignored_valid_count_debug_live;
            logic [15:0] vgm_scan_copy_read_handshake_debug_live;
            logic [15:0] vgm_scan_payload_o0_debug_live;
            logic [15:0] vgm_scan_payload_af_debug_live;
            logic [15:0] vgm_scan_payload_vd_debug_live;
            logic [15:0] vgm_scan_payload_cp_debug_live;
            logic [15:0] vgm_scan_term_pl_debug_live;
            logic [15:0] vgm_scan_term_rm_debug_live;
            logic [15:0] vgm_scan_term_cc_debug_live;
            logic [15:0] vgm_scan_term_nx_debug_live;
            logic [15:0] vgm_scan_term_be_debug_live;
            logic [15:0] vgm_scan_sticky_guard_debug_live;
            logic [15:0] vgm_scan_payload_qg_debug_live;
            logic [15:0] vgm_scan_payload_sf_debug_live;
            logic vgm_scan_payload_continue_guard_active_live;
            logic [15:0] mode5_payload_oh_i = 16'd0;
            logic [15:0] mode5_payload_ah_i = 16'd0;
            logic [15:0] mode5_payload_oh2_i = 16'd0;
            logic [15:0] mode5_payload_vh_i = 16'd0;
            logic [15:0] mode5_payload_ch_i = 16'd0;
            logic [15:0] mode5_payload_bd_i = 16'd0;
            logic [7:0] mode5_payload_sf_i = 8'd0;
            logic [2:0] mode5_payload_as_i = 3'd0;
            logic [4:0] mode5_payload_vs_i = 5'd0;
            logic [5:0] mode5_payload_cs_i = 6'd0;
            logic [15:0] mode5_counter_latch_accept_i = 16'd0;
            logic [15:0] mode5_counter_latch_read_i = 16'd0;
            logic [15:0] mode5_term_pl_i = 16'd0;
            logic [15:0] mode5_term_rm_i = 16'd0;
            logic [15:0] mode5_term_cc_i = 16'd0;
            logic [15:0] mode5_term_nx_i = 16'd0;
            logic [15:0] mode5_term_be_i = 16'hBE00;
            logic [7:0] mode5_guard_debug_i = 8'd0;
            logic [7:0] mode5_sticky_guard_debug_i = 8'd0;
            logic mode5_term_valid_i = 1'b0;
            logic [15:0] mode5_prev_raw_player_accept_i = 16'd0;
            logic [15:0] mode5_prev_raw_copy_accept_i = 16'd0;
            logic [15:0] mode5_prev_raw_read_accept_i = 16'd0;
            logic [15:0] mode5_prev_raw_read_valid_i = 16'd0;
            logic [3:0] mode5_counter_increment_seen_i = 4'd0;
            logic mode5_counter_latch_valid_i = 1'b0;
            logic mode5_counter_update_overwritten_i = 1'b0;
            logic mode5_counter_reset_after_increment_i = 1'b0;
            logic [5:0] mode5_counter_reset_reason_i = 6'd0;
            logic [7:0] mode5_counter_reset_source_i = 8'd0;
            logic [7:0] mode5_stop_source_i = 8'd0;
            logic [15:0] mode5_prev_max_player_accept_i = 16'd0;
            logic [15:0] mode5_prev_max_copy_accept_i = 16'd0;
            logic [15:0] mode5_prev_max_read_accept_i = 16'd0;
            logic [15:0] mode5_prev_max_read_valid_i = 16'd0;
            logic mode5_payload_oh_valid_i = 1'b0;
            logic mode5_payload_oh2_valid_i = 1'b0;
            logic mode5_payload_vh_valid_i = 1'b0;
            logic mode5_payload_ch_valid_i = 1'b0;
            logic [15:0] mode5_copy_read_req_max_i = 16'd0;
            logic [15:0] mode5_copy_read_accept_max_i = 16'd0;
            logic [15:0] mode5_copy_read_valid_max_i = 16'd0;
            logic [15:0] mode5_copy_mem_req_cycle_max_i = 16'd0;
            logic [15:0] mode5_copy_mem_req_ready_cycle_max_i = 16'd0;
            logic [15:0] mode5_copy_read_raw_valid_max_i = 16'd0;
            logic [15:0] mode5_copy_read_ignored_valid_max_i = 16'd0;
            logic [15:0] mode5_copy_read_handshake_seen_i = 16'd0;
            logic [15:0] mode5_copy_state_lifetime_i = 16'd0;
            logic [15:0] mode5_copy_clear_reason_i = 16'd0;
            logic [15:0] mode5_copy_payload_pc_i = 16'd0;
            logic vgm_scan_remaining_zero_before_expected_accept_debug_live;
            logic [15:0] backend_copy_accept_count_debug;
            logic [15:0] backend_copy_write_count_debug;
            logic [15:0] backend_copy_fifo_debug;
            logic [15:0] backend_copy_ready_debug;
            logic [15:0] backend_copy_write_req_debug;
            logic [15:0] backend_copy_word_debug;
            logic [15:0] backend_copy_flush_debug;
            logic [15:0] backend_copy_full_detect_count_debug;
            logic [15:0] backend_copy_push_req_count_debug;
            logic [15:0] backend_copy_push_fire_count_debug;
            logic [15:0] backend_copy_fifo_push_count_debug;
            logic [15:0] backend_copy_pack_ready_debug;
            logic [15:0] backend_copy_post_push_debug;
            logic [15:0] backend_read_gate_debug;
            logic [15:0] backend_read_after_copy_count_debug;
            wire [15:0] mode5_expected_copy_write_words =
                {3'd0, mode5_payload_len_low_i[15:3]} +
                {15'd0, |mode5_payload_len_low_i[2:0]};
            wire [15:0] mode5_visible_read_req_count =
                (vgm_scan_copy_read_req_count_debug_live >
                 mode5_copy_read_req_max_i) ?
                vgm_scan_copy_read_req_count_debug_live :
                mode5_copy_read_req_max_i;
            wire [15:0] mode5_visible_read_accept_count =
                (vgm_scan_copy_read_accept_count_debug_live >
                 mode5_copy_read_accept_max_i) ?
                vgm_scan_copy_read_accept_count_debug_live :
                mode5_copy_read_accept_max_i;
            wire mode5_visible_rq_gt_rr =
                mode5_visible_read_req_count >
                mode5_visible_read_accept_count;
            wire [15:0] mode5_copy_remaining_from_count =
                (mode5_payload_len_low_i > mode5_copy_max_ready_count_i) ?
                (mode5_payload_len_low_i - mode5_copy_max_ready_count_i) :
                16'd0;
            wire [15:0] mode5_copy_read_handshake_mapped = {
                8'd0,
                (vgm_scan_copy_tail_debug_live[6] |
                 vgm_scan_copy_tail_debug_live[4]),
                ddram_busy,
                (vgm_read_pending_debug &&
                 vgm_scan_copy_read_handshake_debug_live[1] &&
                 !vgm_mem_rd_valid_debug),
                vgm_mem_rd_valid_debug,
                vgm_scan_copy_read_handshake_debug_live[1],
                vgm_read_pending_debug,
                vgm_mem_rd_ready_debug,
                vgm_mem_rd_req_debug
            };
            wire mode5_player_waiting_for_valid =
                vgm_read_pending_debug &&
                vgm_scan_copy_read_handshake_debug_live[1] &&
                !vgm_mem_rd_valid_debug;
            wire [15:0] mode5_read_mux_live = {
                8'd0,
                ddram_busy,
                mode5_backend_read_gate_debug[2],
                mode5_backend_read_gate_debug[0],
                mode5_player_waiting_for_valid,
                vgm_read_pending_debug,
                (vgm_mem_rd_req_debug && vgm_mem_rd_ready_debug),
                mem_rd_req,
                vgm_mem_rd_req_debug
            };
            wire [15:0] mode5_read_ready_compare_live = {
                8'd0,
                (mode5_backend_read_gate_debug[0] ^ vgm_mem_rd_ready_debug),
                (mode5_backend_read_gate_debug[0] ^ mem_rd_ready),
                (mem_rd_ready ^ vgm_mem_rd_ready_debug),
                (vgm_mem_rd_req_debug && !vgm_mem_rd_ready_debug),
                (vgm_mem_rd_req_debug && mode5_backend_read_gate_debug[0]),
                mode5_backend_read_gate_debug[0],
                mem_rd_ready,
                vgm_mem_rd_ready_debug
            };
            wire [15:0] mode5_read_ready_blocker_live = {
                8'd0,
                mode5_backend_read_gate_debug[7],
                mode5_backend_read_gate_debug[6],
                mode5_backend_read_gate_debug[5],
                mode5_backend_read_gate_debug[4],
                mode5_backend_read_gate_debug[3],
                mode5_backend_read_gate_debug[2],
                mode5_backend_read_gate_debug[1],
                mode5_backend_read_gate_debug[0]
            };
            localparam logic [1:0] MODE5_REPEAT_IDLE       = 2'd0;
            localparam logic [1:0] MODE5_REPEAT_RESET      = 2'd1;
            localparam logic [1:0] MODE5_REPEAT_WAIT_CLEAR = 2'd2;
            logic [1:0] mode5_repeat_state = MODE5_REPEAT_IDLE;

            assign mode5_load_begin_pulse =
                ioctl_download && !ioctl_download_d &&
                (ioctl_index == VGM_LOAD_FILE_INDEX);
            assign mode5_done_edge =
                loaded_player_done &&
                !player_done_d &&
                mode5_playback_started &&
                mode5_done_armed_i &&
                (mode5_done_armed_session_id_i == mode5_playback_session_id_i) &&
                !mode5_load_session_active &&
                !vgm_load_busy &&
                !vgm_load_error &&
                !vgm_load_overflow &&
                !vgm_player_error;
            assign mode5_player_error_edge =
                vgm_player_error && !vgm_player_error_d;
            assign mode5_top_file_ok =
                vgm_load_done &&
                !vgm_load_busy &&
                !vgm_load_error &&
                !vgm_load_overflow &&
                (vgm_load_size > 19'd64);
            wire mode5_continue_payload_loop_live =
                vgm_scan_term_be_debug_live[4] &&
                !vgm_scan_term_be_debug_live[3];
            wire mode5_continue_payload_loop_sticky =
                mode5_term_valid_i &&
                mode5_term_be_i[4] &&
                !mode5_term_be_i[3];
            wire mode5_continue_payload_loop_taken =
                mode5_continue_payload_loop_live ||
                mode5_continue_payload_loop_sticky;
            wire mode5_term_capture_live =
                (mode5_payload_oh_valid_i || mode5_visible_rq_gt_rr) &&
                (vgm_scan_payload_cp_debug_live[4] ||
                 vgm_scan_payload_cp_debug_live[5] ||
                 vgm_scan_term_be_debug_live[0]) &&
                !mode5_term_valid_i;
            wire mode5_term_capture_continue_live =
                mode5_term_capture_live && mode5_continue_payload_loop_live;
            wire mode5_be_continue_guard =
                mode5_term_capture_continue_live ||
                mode5_sticky_guard_debug_i[0] ||
                mode5_continue_payload_loop_sticky;
            wire mode5_block_clear_raw_live =
                vgm_scan_copy_tail_debug_live[1] ||
                vgm_scan_copy_tail_debug_live[2] ||
                vgm_scan_copy_tail_debug_live[0];
            wire mode5_segapcm_copy_continue_guard =
                vgm_scan_payload_continue_guard_active_live ||
                mode5_be_continue_guard ||
                ((vgm_scan_payload_len_low_debug_live != 16'd0) &&
                 ((vgm_scan_remaining_low_debug_live != 16'd0) ||
                  (vgm_scan_copy_read_req_count_debug_live >
                   vgm_scan_copy_read_accept_count_debug_live) ||
                  (vgm_scan_copy_read_accept_count_debug_live >
                   vgm_scan_copy_read_valid_count_debug_live) ||
                  mode5_continue_payload_loop_live)) ||
                (mode5_continue_payload_loop_sticky &&
                 ((mode5_term_pl_i != 16'd0) ||
                  (mode5_term_rm_i != 16'd0) ||
                  (mode5_term_nx_i != 16'd0)));
            assign player_busy = loaded_player_busy || mode5_be_continue_guard;

            wire mode5_idle_fallthrough_raw_live =
                mode5_playback_started &&
                !player_busy &&
                !loaded_player_done &&
                !vgm_player_error &&
                !vgm_load_busy &&
                !vgm_load_error &&
                !vgm_load_overflow;
            wire mode5_idle_fallthrough_live =
                mode5_idle_fallthrough_raw_live &&
                !mode5_be_continue_guard &&
                !mode5_continue_payload_loop_taken &&
                !mode5_segapcm_copy_continue_guard;
            wire mode5_block_clear_after_guard =
                mode5_block_clear_raw_live &&
                !mode5_continue_payload_loop_taken &&
                !mode5_segapcm_copy_continue_guard;
            wire [7:0] mode5_guard_debug_live = {
                mode5_block_clear_after_guard,
                mode5_idle_fallthrough_live,
                mode5_block_clear_raw_live,
                mode5_idle_fallthrough_raw_live,
                (mode5_continue_payload_loop_taken &&
                 mode5_block_clear_raw_live),
                (mode5_continue_payload_loop_taken &&
                 mode5_idle_fallthrough_raw_live),
                mode5_segapcm_copy_continue_guard,
                mode5_continue_payload_loop_taken
            };
            wire mode5_counter_update_overwrite_live =
                !mode5_be_continue_guard &&
                ((vgm_scan_payload_cp_debug_live[4] &&
                  (vgm_scan_player_accept_count_debug_live <=
                   mode5_prev_raw_player_accept_i)) ||
                 (vgm_scan_payload_cp_debug_live[5] &&
                  (vgm_scan_copy_accept_fire_count_debug_live <=
                   mode5_prev_raw_copy_accept_i)) ||
                 (vgm_scan_payload_af_debug_live[5] &&
                  (vgm_scan_copy_read_accept_count_debug_live <=
                   mode5_prev_raw_read_accept_i)) ||
                 (vgm_scan_payload_vd_debug_live[3] &&
                  (vgm_scan_copy_read_valid_count_debug_live <=
                   mode5_prev_raw_read_valid_i)));
            wire mode5_counter_raw_drop_live =
                !mode5_be_continue_guard &&
                ((mode5_counter_increment_seen_i[0] &&
                  (vgm_scan_player_accept_count_debug_live <
                   mode5_prev_raw_player_accept_i)) ||
                 (mode5_counter_increment_seen_i[1] &&
                  (vgm_scan_copy_accept_fire_count_debug_live <
                   mode5_prev_raw_copy_accept_i)) ||
                 (mode5_counter_increment_seen_i[2] &&
                  (vgm_scan_copy_read_accept_count_debug_live <
                   mode5_prev_raw_read_accept_i)) ||
                 (mode5_counter_increment_seen_i[3] &&
                  (vgm_scan_copy_read_valid_count_debug_live <
                   mode5_prev_raw_read_valid_i)));
            wire mode5_debug_max_drop_live =
                (mode5_copy_max_ready_count_i < mode5_prev_max_player_accept_i) ||
                (mode5_copy_max_ready_count_i < mode5_prev_max_copy_accept_i) ||
                (mode5_copy_read_accept_max_i < mode5_prev_max_read_accept_i) ||
                (mode5_copy_read_valid_max_i < mode5_prev_max_read_valid_i);
            wire mode5_scan_restart_live =
                (loaded_player_start_input_live &&
                 !loaded_player_start_input_live_d) ||
                (segapcm_rom_scan_busy && !segapcm_rom_scan_busy_d);
            wire mode5_replay_restart_live =
                !mode5_segapcm_copy_continue_guard &&
                mode5_done_edge &&
                MODE5_REPEAT_ENABLE &&
                vgm_load_done &&
                vgm_header_valid &&
                !vgm_load_busy &&
                !vgm_load_error &&
                !vgm_load_overflow &&
                !vgm_player_error &&
                !mode5_load_session_active;
            wire mode5_session_reset_request_live =
                mode5_load_begin_pulse ||
                (vgm_load_error || vgm_load_overflow) ||
                (!mode5_segapcm_copy_continue_guard &&
                 (mode5_repeat_state == MODE5_REPEAT_RESET));
            wire mode5_counter_diag_active =
                (mode5_counter_increment_seen_i != 4'd0) ||
                (mode5_payload_cs_i != 6'd0) ||
                mode5_term_valid_i ||
                (mode5_copy_max_ready_count_i != 16'd0) ||
                (mode5_copy_read_accept_max_i != 16'd0) ||
                (mode5_copy_read_valid_max_i != 16'd0);
            wire mode5_play_stop_raw_live =
                mode5_done_edge ||
                loaded_player_done ||
                (mode5_playback_started && !player_busy);
            wire mode5_play_stop_live =
                mode5_play_stop_raw_live &&
                !mode5_be_continue_guard &&
                !mode5_segapcm_copy_continue_guard;
            wire mode5_scan_done_live =
                segapcm_rom_scan_done || vgm_final_progress_debug_live[2];
            wire mode5_copy_done_live =
                segapcm_rom_copy_flush_done || vgm_final_progress_debug_live[3];
            wire [7:0] mode5_counter_reset_source_live = {
                mode5_debug_max_drop_live,
                mode5_copy_done_live,
                mode5_scan_restart_live,
                mode5_play_stop_live,
                mode5_load_begin_pulse,
                mode5_session_reset_request_live,
                (mode5_counter_diag_active &&
                 mode5_session_reset_request_live),
                (mode5_counter_raw_drop_live ||
                 mode5_counter_update_overwrite_live)
            };
            wire [7:0] mode5_stop_source_live = {
                mode5_idle_fallthrough_live,
                (vgm_player_error || mode5_player_error_edge),
                mode5_copy_done_live,
                mode5_scan_done_live,
                mode5_replay_restart_live,
                (mode5_session_reset_request_live ||
                 mode5_player_session_reset ||
                 mode5_sound_reset_active_i),
                (vgm_load_error || vgm_load_overflow),
                mode5_play_stop_live
            };
            assign mode5_freeze_event =
                !mode5_freeze_active &&
                !mode5_segapcm_copy_continue_guard &&
                vgm_final_progress_debug_live[0] &&
                ((loaded_player_start_input_live &&
                  !loaded_player_start_input_live_d &&
                  (mode5_start_attempt_count_i != 16'd0)) ||
                 vgm_player_error ||
                 loaded_player_done ||
                 (mode5_freeze_play_seen &&
                  !player_busy &&
                  !segapcm_rom_scan_busy &&
                  !loaded_player_start_input_live &&
                  mode5_playback_started));
            assign mode5_load_ready_level =
                mode5_load_session_active &&
                vgm_load_done &&
                !vgm_load_busy &&
                !vgm_load_error &&
                !vgm_load_overflow &&
                !mode5_playback_armed &&
                !mode5_playback_started;
            assign ym_write_requested_count =
                YM2151_EXPERIMENTAL_MODE ? ym2151_write_count :
                md_ym_write_requested_count;
            assign ym_write_accepted_count =
                YM2151_EXPERIMENTAL_MODE ? ym2151_write_count :
                md_ym_write_accepted_count;
            assign ym_write_dropped_or_busy_count =
                YM2151_EXPERIMENTAL_MODE ? ym2151_unsupported_command_count :
                md_ym_write_dropped_or_busy_count;
            assign ym_port0_count =
                YM2151_EXPERIMENTAL_MODE ? ym2151_write_count :
                md_ym_port0_count;
            assign ym_port1_count =
                YM2151_EXPERIMENTAL_MODE ? 32'd0 :
                md_ym_port1_count;
            assign last_ym_port =
                YM2151_EXPERIMENTAL_MODE ? 1'b0 : md_last_ym_port;
            assign last_ym_addr =
                YM2151_EXPERIMENTAL_MODE ? ym2151_last_reg : md_last_ym_addr;
            assign last_ym_data =
                YM2151_EXPERIMENTAL_MODE ? ym2151_last_data : md_last_ym_data;
`ifdef MEGAVGMDRIVE_SEGAPCM_AUDIO_STUB_BUILD
            assign segapcm_audio_l_mix = 16'sd0;
            assign segapcm_audio_r_mix = 16'sd0;
            assign ym2151_segapcm_l_sum = 17'sd0;
            assign ym2151_segapcm_r_sum = 17'sd0;
            assign ym2151_segapcm_audio_l = 16'sd0;
            assign ym2151_segapcm_audio_r = 16'sd0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
            assign ym2151_segapcm_selected_l =
                segapcm_smoke_output_enabled ? segapcm_audio_l : 16'sd0;
            assign ym2151_segapcm_selected_r =
                segapcm_smoke_output_enabled ? segapcm_audio_r : 16'sd0;
`else
            assign ym2151_segapcm_selected_l = segapcm_audio_l;
            assign ym2151_segapcm_selected_r = segapcm_audio_r;
`endif
            assign raw_audio_l = ym2151_segapcm_selected_l;
            assign raw_audio_r = ym2151_segapcm_selected_r;
            assign raw_audio_sample_valid = segapcm_audio_sample_valid;
`else
            assign segapcm_audio_l_mix =
                (SEGAPCM_EXPERIMENTAL_MIX_MODE == 2) ?
                (segapcm_audio_l >>> 2) :
                (SEGAPCM_EXPERIMENTAL_MIX_MODE == 3) ?
                (segapcm_audio_l >>> 1) :
                (SEGAPCM_EXPERIMENTAL_MIX_MODE == 4) ?
                segapcm_audio_l :
                (segapcm_audio_l >>> 3);
            assign segapcm_audio_r_mix =
                (SEGAPCM_EXPERIMENTAL_MIX_MODE == 2) ?
                (segapcm_audio_r >>> 2) :
                (SEGAPCM_EXPERIMENTAL_MIX_MODE == 3) ?
                (segapcm_audio_r >>> 1) :
                (SEGAPCM_EXPERIMENTAL_MIX_MODE == 4) ?
                segapcm_audio_r :
                (segapcm_audio_r >>> 3);
            assign ym2151_segapcm_l_sum =
                {ym2151_audio_l[15], ym2151_audio_l} +
                {segapcm_audio_l_mix[15], segapcm_audio_l_mix};
            assign ym2151_segapcm_r_sum =
                {ym2151_audio_r[15], ym2151_audio_r} +
                {segapcm_audio_r_mix[15], segapcm_audio_r_mix};
            assign ym2151_segapcm_audio_l =
                (ym2151_segapcm_l_sum[16] != ym2151_segapcm_l_sum[15]) ?
                (ym2151_segapcm_l_sum[16] ? 16'sh8000 : 16'sh7fff) :
                ym2151_segapcm_l_sum[15:0];
            assign ym2151_segapcm_audio_r =
                (ym2151_segapcm_r_sum[16] != ym2151_segapcm_r_sum[15]) ?
                (ym2151_segapcm_r_sum[16] ? 16'sh8000 : 16'sh7fff) :
                ym2151_segapcm_r_sum[15:0];
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
            assign ym2151_segapcm_selected_l =
                segapcm_smoke_output_enabled ? segapcm_audio_l : 16'sd0;
            assign ym2151_segapcm_selected_r =
                segapcm_smoke_output_enabled ? segapcm_audio_r : 16'sd0;
`else
            assign ym2151_segapcm_selected_l =
                (SEGAPCM_EXPERIMENTAL_MIX_MODE == 1) ?
                segapcm_audio_l : ym2151_segapcm_audio_l;
            assign ym2151_segapcm_selected_r =
                (SEGAPCM_EXPERIMENTAL_MIX_MODE == 1) ?
                segapcm_audio_r : ym2151_segapcm_audio_r;
`endif
            assign raw_audio_l =
                YM2151_EXPERIMENTAL_MODE ? ym2151_segapcm_selected_l :
                md_audio_l;
            assign raw_audio_r =
                YM2151_EXPERIMENTAL_MODE ? ym2151_segapcm_selected_r :
                md_audio_r;
            assign raw_audio_sample_valid =
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                YM2151_EXPERIMENTAL_MODE ? segapcm_audio_sample_valid :
`else
                YM2151_EXPERIMENTAL_MODE ? ym2151_audio_sample_valid :
`endif
                md_audio_sample_valid;
`endif

            always_ff @(posedge clk) begin
                if (reset) begin
                    ioctl_download_d <= 1'b0;
                    mode5_sound_reset_active_i <= 1'b0;
                    mode5_player_start_pulse <= 1'b0;
                    mode5_player_start_hold <= 1'b0;
                    mode5_direct_player_start_hold <= 1'b0;
                    smoke_parser_start_hold <= 1'b0;
                    smoke_parser_start_used <= 1'b0;
                    mode5_player_start_hold_seen <= 1'b0;
                    mode5_start_hold_clear_by_busy <= 1'b0;
                    mode5_start_hold_clear_by_done <= 1'b0;
                    mode5_start_hold_clear_by_error <= 1'b0;
                    mode5_start_hold_clear_by_load_reset <= 1'b0;
                    mode5_start_hold_clear_by_other <= 1'b0;
                    mode5_start_hold_clear_by_start_seen <= 1'b0;
                    mode5_start_hold_clear_by_header_request <= 1'b0;
                    mode5_start_hold_clear_by_header_valid <= 1'b0;
                    mode5_start_hold_lost_without_accept <= 1'b0;
                    mode5_start_hold_prev <= 1'b0;
                    mode5_sound_reset_counter <= 32'd0;
                    mode5_load_session_active <= 1'b0;
                    mode5_playback_armed <= 1'b0;
                    mode5_playback_started <= 1'b0;
                    mode5_player_session_reset <= 1'b0;
                    mode5_load_begin_count_i <= 32'd0;
                    mode5_load_done_edge_count_i <= 32'd0;
                    mode5_sound_reset_start_count_i <= 32'd0;
                    mode5_player_start_count_i <= 32'd0;
                    mode5_player_reset_count_i <= 32'd0;
                    mode5_playback_session_id_i <= 32'd0;
                    mode5_duplicate_start_blocked_count_i <= 32'd0;
                    mode5_player_end_count_i <= 32'd0;
                    mode5_repeat_restart_count_i <= 32'd0;
                    mode5_done_armed_i <= 1'b0;
                    mode5_done_armed_session_id_i <= 32'd0;
                    mode5_repeat_session_id_i <= 32'd0;
                    mode5_done_session_id_i <= 32'd0;
                    mode5_cycles_since_start_i <= 32'd0;
                    mode5_done_pc_debug_i <= '0;
                    mode5_done_cmd_debug_i <= 8'd0;
                    mode5_top_stop_snapshot_debug_i <= 16'd0;
                    mode5_direct_start_used <= 1'b0;
                    loaded_player_start_input_live_d <= 1'b0;
                    segapcm_rom_scan_busy_d <= 1'b0;
                    mode5_copy_max_ready_count_i <= 16'd0;
                    mode5_copy_min_remaining_i <= 16'hffff;
                    mode5_backend_copy_accept_max_i <= 16'd0;
                    mode5_backend_copy_write_max_i <= 16'd0;
                    mode5_payload_len_low_i <= 16'd0;
                    mode5_remaining_zero_early_seen_i <= 1'b0;
                    mode5_zero_state_debug_i <= 16'd0;
                    mode5_zero_pc_debug_i <= 16'd0;
                    mode5_zero_cmd_debug_i <= 16'd0;
                    mode5_raw_event_seen_i <= 16'd0;
                    mode5_raw_copy_byte_max_i <= 16'd0;
                    mode5_copy_read_req_max_i <= 16'd0;
                    mode5_copy_read_accept_max_i <= 16'd0;
                    mode5_copy_read_valid_max_i <= 16'd0;
                    mode5_copy_mem_req_cycle_max_i <= 16'd0;
                    mode5_copy_mem_req_ready_cycle_max_i <= 16'd0;
                    mode5_copy_read_raw_valid_max_i <= 16'd0;
                    mode5_copy_read_ignored_valid_max_i <= 16'd0;
                    mode5_copy_read_handshake_seen_i <= 16'd0;
                    mode5_copy_state_lifetime_i <= 16'd0;
                    mode5_copy_clear_reason_i <= 16'd0;
                    mode5_copy_payload_pc_i <= 16'd0;
                    mode5_payload_oh_i <= 16'd0;
                    mode5_payload_ah_i <= 16'd0;
                    mode5_payload_oh2_i <= 16'd0;
                    mode5_payload_vh_i <= 16'd0;
                    mode5_payload_sf_i <= 8'd0;
                    mode5_payload_ch_i <= 16'd0;
                    mode5_payload_bd_i <= 16'd0;
                    mode5_payload_as_i <= 3'd0;
                    mode5_payload_vs_i <= 5'd0;
                    mode5_payload_cs_i <= 6'd0;
                    mode5_counter_latch_accept_i <= 16'd0;
                    mode5_counter_latch_read_i <= 16'd0;
                    mode5_term_pl_i <= 16'd0;
                    mode5_term_rm_i <= 16'd0;
                    mode5_term_cc_i <= 16'd0;
                    mode5_term_nx_i <= 16'd0;
                    mode5_term_be_i <= 16'hBE00;
                    mode5_guard_debug_i <= 8'd0;
                    mode5_sticky_guard_debug_i <= 8'd0;
                    mode5_term_valid_i <= 1'b0;
                    mode5_prev_raw_player_accept_i <= 16'd0;
                    mode5_prev_raw_copy_accept_i <= 16'd0;
                    mode5_prev_raw_read_accept_i <= 16'd0;
                    mode5_prev_raw_read_valid_i <= 16'd0;
                    mode5_counter_increment_seen_i <= 4'd0;
                    mode5_counter_latch_valid_i <= 1'b0;
                    mode5_counter_update_overwritten_i <= 1'b0;
                    mode5_counter_reset_after_increment_i <= 1'b0;
                    mode5_counter_reset_reason_i <= 6'd0;
                    mode5_counter_reset_source_i <= 8'd0;
                    mode5_stop_source_i <= 8'd0;
                    mode5_prev_max_player_accept_i <= 16'd0;
                    mode5_prev_max_copy_accept_i <= 16'd0;
                    mode5_prev_max_read_accept_i <= 16'd0;
                    mode5_prev_max_read_valid_i <= 16'd0;
                    mode5_payload_oh_valid_i <= 1'b0;
                    mode5_payload_oh2_valid_i <= 1'b0;
                    mode5_payload_vh_valid_i <= 1'b0;
                    mode5_payload_ch_valid_i <= 1'b0;
                    mode5_restart_after_load_count_i <= 16'd0;
                    mode5_start_attempt_count_i <= 16'd0;
                    mode5_scan_start_count_i <= 16'd0;
                    mode5_copy_fifo_full_seen_i <= 1'b0;
                    mode5_copy_ready_low_seen_i <= 1'b0;
                    mode5_freeze_active <= 1'b0;
                    mode5_freeze_play_seen <= 1'b0;
                    mode5_freeze_final_state <= 7'd0;
                    mode5_freeze_final_pc <= '0;
                    mode5_freeze_final_cmd <= 8'd0;
                    mode5_freeze_final_error_code <= 8'd0;
                    mode5_freeze_final_flags <= 16'd0;
                    mode5_freeze_final_reason <= 4'd0;
                    mode5_freeze_final_progress <= 16'd0;
                    mode5_freeze_first_playback_cmd <= 8'd0;
                    mode5_freeze_first_playback_cmds <= 32'd0;
                    mode5_freeze_scan_state <= 7'd0;
                    mode5_freeze_scan_pc <= '0;
                    mode5_freeze_scan_last_cmd <= 8'd0;
                    mode5_freeze_scan_block_type <= 8'd0;
                    mode5_freeze_scan_block_size_low <= 16'd0;
                    mode5_freeze_scan_remaining_low <= 16'd0;
                    mode5_freeze_scan_wait <= 16'd0;
                    mode5_freeze_scan_abort_reason <= 8'd0;
                    mode5_freeze_scan_copy_last_index_low <= 16'd0;
                    mode5_freeze_scan_copy_req_count <= 16'd0;
                    mode5_freeze_scan_copy_ready_count <= 16'd0;
                    mode5_freeze_scan_copy_tail <= 16'd0;
                    mode5_player_done_latched <= 1'b0;
                    player_done_d <= 1'b0;
                    vgm_player_error_d <= 1'b0;
                    mode5_error_session_id_i <= 32'd0;
                    mode5_repeat_state <= MODE5_REPEAT_IDLE;
                end else begin
                    ioctl_download_d <= ioctl_download;
                    player_done_d <= loaded_player_done;
                    vgm_player_error_d <= vgm_player_error;
                    mode5_player_start_pulse <= 1'b0;
                    mode5_player_session_reset <= 1'b0;
                    mode5_start_hold_prev <= mode5_player_start_hold;
                    loaded_player_start_input_live_d <= loaded_player_start_input_live;
                    segapcm_rom_scan_busy_d <= segapcm_rom_scan_busy;

                    if (DIRECT_PLAYER_START_DEBUG && YM2151_EXPERIMENTAL_MODE) begin
                        if (mode5_load_begin_pulse || reset) begin
                            mode5_direct_player_start_hold <= 1'b0;
                            mode5_direct_start_used <= 1'b0;
                        end else if (vgm_player_lifecycle_debug[11] ||
                                     vgm_player_lifecycle_debug[7]) begin
                            mode5_direct_player_start_hold <= 1'b0;
                        end else if (mode5_top_file_ok &&
                                     !mode5_loaded_player_reset &&
                                     !mode5_direct_start_used) begin
                            mode5_direct_player_start_hold <= 1'b1;
                            mode5_direct_start_used <= 1'b1;
                        end
                    end else begin
                        mode5_direct_player_start_hold <= 1'b0;
                        mode5_direct_start_used <= 1'b0;
                    end

                    if (smoke_parser_run_enable) begin
                        if (mode5_load_begin_pulse ||
                            vgm_load_busy ||
                            vgm_load_error ||
                            vgm_load_overflow ||
                            !mode5_top_file_ok) begin
                            smoke_parser_start_hold <= 1'b0;
                            smoke_parser_start_used <= 1'b0;
                        end else if (loaded_player_busy ||
                                     vgm_player_core_debug[15] ||
                                     vgm_player_core_debug[12] ||
                                     vgm_player_lifecycle_debug[11] ||
                                     vgm_player_lifecycle_debug[7]) begin
                            smoke_parser_start_hold <= 1'b0;
                        end else if (!smoke_parser_start_used &&
                                     !mode5_loaded_player_reset &&
                                     !loaded_player_done &&
                                     !vgm_player_error) begin
                            smoke_parser_start_hold <= 1'b1;
                            smoke_parser_start_used <= 1'b1;
                        end
                    end else begin
                        smoke_parser_start_hold <= 1'b0;
                        smoke_parser_start_used <= 1'b0;
                    end

                    if (loaded_player_start_input_live &&
                        !loaded_player_start_input_live_d) begin
                        if (mode5_start_attempt_count_i != 16'hffff) begin
                            mode5_start_attempt_count_i <=
                                mode5_start_attempt_count_i + 16'd1;
                        end
                        if (mode5_start_attempt_count_i != 16'd0 &&
                            mode5_restart_after_load_count_i != 16'hffff) begin
                            mode5_restart_after_load_count_i <=
                                mode5_restart_after_load_count_i + 16'd1;
                        end
                    end

                    if (segapcm_rom_scan_busy && !segapcm_rom_scan_busy_d) begin
                        if (mode5_scan_start_count_i != 16'hffff) begin
                            mode5_scan_start_count_i <=
                                mode5_scan_start_count_i + 16'd1;
                        end
                    end

                    if (vgm_scan_copy_accept_fire_count_debug_live >
                        mode5_copy_max_ready_count_i) begin
                        mode5_copy_max_ready_count_i <=
                            vgm_scan_copy_accept_fire_count_debug_live;
                    end

                    if ((mode5_payload_len_low_i != 16'd0) &&
                        (segapcm_rom_scan_busy ||
                         (vgm_final_progress_debug_live[1] &&
                          !vgm_final_progress_debug_live[2])) &&
                        (vgm_scan_player_remaining_debug_live <
                         mode5_copy_min_remaining_i)) begin
                        mode5_copy_min_remaining_i <=
                            vgm_scan_player_remaining_debug_live;
                    end

                    if (backend_copy_accept_count_debug >
                        mode5_backend_copy_accept_max_i) begin
                        mode5_backend_copy_accept_max_i <=
                            backend_copy_accept_count_debug;
                    end

                    if (backend_copy_write_count_debug >
                        mode5_backend_copy_write_max_i) begin
                        mode5_backend_copy_write_max_i <=
                            backend_copy_write_count_debug;
                    end

                    if (vgm_scan_payload_len_low_debug_live != 16'd0) begin
                        mode5_payload_len_low_i <=
                            vgm_scan_payload_len_low_debug_live;
                    end

                    mode5_raw_event_seen_i <=
                        mode5_raw_event_seen_i | vgm_scan_raw_event_debug_live;

                    if (vgm_scan_raw_copy_byte_count_debug_live >
                        mode5_raw_copy_byte_max_i) begin
                        mode5_raw_copy_byte_max_i <=
                            vgm_scan_raw_copy_byte_count_debug_live;
                    end

                    if (vgm_scan_copy_read_req_count_debug_live >
                        mode5_copy_read_req_max_i) begin
                        mode5_copy_read_req_max_i <=
                            vgm_scan_copy_read_req_count_debug_live;
                    end

                    mode5_payload_sf_i <=
                        mode5_payload_sf_i | vgm_scan_payload_sf_debug_live[7:0];

                    if (vgm_scan_copy_read_accept_count_debug_live >
                        mode5_copy_read_accept_max_i) begin
                        mode5_copy_read_accept_max_i <=
                            vgm_scan_copy_read_accept_count_debug_live;
                    end

                    if (vgm_scan_copy_read_valid_count_debug_live >
                        mode5_copy_read_valid_max_i) begin
                        mode5_copy_read_valid_max_i <=
                            vgm_scan_copy_read_valid_count_debug_live;
                    end

                    if (vgm_scan_copy_mem_req_cycle_count_debug_live >
                        mode5_copy_mem_req_cycle_max_i) begin
                        mode5_copy_mem_req_cycle_max_i <=
                            vgm_scan_copy_mem_req_cycle_count_debug_live;
                    end

                    if (vgm_scan_copy_mem_req_ready_cycle_count_debug_live >
                        mode5_copy_mem_req_ready_cycle_max_i) begin
                        mode5_copy_mem_req_ready_cycle_max_i <=
                            vgm_scan_copy_mem_req_ready_cycle_count_debug_live;
                    end

                    if (vgm_scan_copy_read_raw_valid_count_debug_live >
                        mode5_copy_read_raw_valid_max_i) begin
                        mode5_copy_read_raw_valid_max_i <=
                            vgm_scan_copy_read_raw_valid_count_debug_live;
                    end

                    if (vgm_scan_copy_read_ignored_valid_count_debug_live >
                        mode5_copy_read_ignored_valid_max_i) begin
                        mode5_copy_read_ignored_valid_max_i <=
                            vgm_scan_copy_read_ignored_valid_count_debug_live;
                    end

                    mode5_copy_read_handshake_seen_i <=
                        mode5_copy_read_handshake_seen_i |
                        mode5_copy_read_handshake_mapped;

                    if (vgm_scan_copy_state_lifetime_debug_live != 16'd0) begin
                        mode5_copy_state_lifetime_i <=
                            vgm_scan_copy_state_lifetime_debug_live;
                    end

                    mode5_copy_clear_reason_i <=
                        mode5_copy_clear_reason_i |
                        vgm_scan_copy_clear_reason_debug_live;

                    if (mode5_visible_rq_gt_rr) begin
                        if (!mode5_payload_oh_valid_i) begin
                            mode5_payload_oh_i <=
                                vgm_scan_payload_o0_debug_live;
                            mode5_payload_ah_i <=
                                vgm_scan_payload_af_debug_live;
                            mode5_payload_oh_valid_i <= 1'b1;
                        end
                        mode5_payload_bd_i <=
                            mode5_payload_bd_i | {
                                8'hB0,
                                vgm_scan_payload_o0_debug_live[7:0]
                            };
                    end

                    mode5_payload_as_i <=
                        mode5_payload_as_i | {
                            vgm_scan_payload_af_debug_live[6],
                            vgm_scan_payload_af_debug_live[5],
                            vgm_scan_payload_af_debug_live[4]
                        };

                    mode5_payload_vs_i <=
                        mode5_payload_vs_i | {
                            vgm_scan_payload_vd_debug_live[5],
                            vgm_scan_payload_vd_debug_live[4],
                            vgm_scan_payload_vd_debug_live[3],
                            vgm_scan_payload_vd_debug_live[2],
                            vgm_scan_payload_vd_debug_live[1]
                        };

                    mode5_payload_cs_i <=
                        mode5_payload_cs_i | {
                            vgm_scan_payload_cp_debug_live[5],
                            vgm_scan_payload_cp_debug_live[4],
                            vgm_scan_payload_cp_debug_live[7],
                            vgm_scan_payload_cp_debug_live[2],
                            vgm_scan_payload_cp_debug_live[1],
                            vgm_scan_payload_cp_debug_live[0]
                        };

                    if (mode5_be_continue_guard) begin
                        mode5_counter_update_overwritten_i <= 1'b0;
                    end else if (mode5_counter_update_overwrite_live) begin
                        mode5_counter_update_overwritten_i <= 1'b1;
                    end

                    if (mode5_counter_raw_drop_live) begin
                        mode5_counter_reset_after_increment_i <= 1'b1;
                        mode5_counter_reset_reason_i <=
                            mode5_counter_reset_reason_i | {
                                mode5_block_clear_after_guard,
                                mode5_idle_fallthrough_live,
                                (vgm_player_error ||
                                 vgm_load_error ||
                                 vgm_load_overflow),
                                vgm_final_progress_debug_live[8],
                                mode5_load_begin_pulse,
                                1'b0
                            };
                    end

                    if (mode5_be_continue_guard) begin
                        mode5_counter_reset_source_i <=
                            mode5_counter_reset_source_i & 8'b1111_1110;
                    end else if (mode5_counter_diag_active ||
                                 mode5_counter_raw_drop_live ||
                                 mode5_counter_update_overwrite_live ||
                                 mode5_debug_max_drop_live) begin
                        mode5_counter_reset_source_i <=
                            mode5_counter_reset_source_i |
                            mode5_counter_reset_source_live;
                    end

                    if (mode5_be_continue_guard) begin
                        mode5_stop_source_i <=
                            (mode5_stop_source_i | mode5_stop_source_live) &
                            8'b0111_1110;
                    end else begin
                        mode5_stop_source_i <=
                            mode5_stop_source_i | mode5_stop_source_live;
                    end

                    mode5_counter_increment_seen_i <=
                        mode5_counter_increment_seen_i | {
                            vgm_scan_payload_vd_debug_live[3],
                            vgm_scan_payload_af_debug_live[5],
                            vgm_scan_payload_cp_debug_live[5],
                            vgm_scan_payload_cp_debug_live[4]
                        };

                    if (mode5_payload_oh_valid_i &&
                        vgm_scan_payload_cp_debug_live[4] &&
                        !mode5_counter_latch_valid_i) begin
                        mode5_counter_latch_accept_i <= {
                            vgm_scan_player_accept_count_debug_live[7:0],
                            vgm_scan_copy_accept_fire_count_debug_live[7:0]
                        };
                        mode5_counter_latch_read_i <= {
                            vgm_scan_copy_read_accept_count_debug_live[7:0],
                            vgm_scan_copy_read_valid_count_debug_live[7:0]
                        };
                        mode5_counter_latch_valid_i <= 1'b1;
                    end

                    if (mode5_term_capture_live) begin
                        mode5_term_pl_i <= vgm_scan_term_pl_debug_live;
                        mode5_term_rm_i <= vgm_scan_term_rm_debug_live;
                        mode5_term_cc_i <= vgm_scan_term_cc_debug_live;
                        mode5_term_nx_i <= vgm_scan_term_nx_debug_live;
                        mode5_term_be_i <= {
                            8'hBE,
                            vgm_scan_term_be_debug_live[7],
                            mode5_continue_payload_loop_live ?
                                1'b0 :
                                (vgm_scan_term_be_debug_live[6] ||
                                 mode5_block_clear_after_guard),
                            mode5_continue_payload_loop_live ?
                                1'b0 :
                                (vgm_scan_term_be_debug_live[5] ||
                                 mode5_idle_fallthrough_live),
                            vgm_scan_term_be_debug_live[4:0]
                        };
                        mode5_term_valid_i <= 1'b1;
                    end else if (mode5_term_valid_i) begin
                        mode5_term_be_i <= {
                            8'hBE,
                            mode5_term_be_i[7] ||
                                vgm_final_progress_debug_live[8],
                            mode5_continue_payload_loop_sticky ?
                                1'b0 :
                                (mode5_term_be_i[6] ||
                                 mode5_block_clear_after_guard),
                            mode5_continue_payload_loop_sticky ?
                                1'b0 :
                                (mode5_term_be_i[5] ||
                                 mode5_idle_fallthrough_live),
                            mode5_term_be_i[4:0]
                        };
                    end

                    if (mode5_term_capture_continue_live) begin
                        mode5_sticky_guard_debug_i[0] <= 1'b1;
                    end

                    mode5_guard_debug_i <=
                        mode5_guard_debug_i | mode5_guard_debug_live;

                    mode5_prev_raw_player_accept_i <=
                        vgm_scan_player_accept_count_debug_live;
                    mode5_prev_raw_copy_accept_i <=
                        vgm_scan_copy_accept_fire_count_debug_live;
                    mode5_prev_raw_read_accept_i <=
                        vgm_scan_copy_read_accept_count_debug_live;
                    mode5_prev_raw_read_valid_i <=
                        vgm_scan_copy_read_valid_count_debug_live;
                    mode5_prev_max_player_accept_i <=
                        mode5_copy_max_ready_count_i;
                    mode5_prev_max_copy_accept_i <=
                        mode5_copy_max_ready_count_i;
                    mode5_prev_max_read_accept_i <=
                        mode5_copy_read_accept_max_i;
                    mode5_prev_max_read_valid_i <=
                        mode5_copy_read_valid_max_i;

                    if (vgm_scan_payload_af_debug_live[3] &&
                        vgm_scan_payload_af_debug_live[2] &&
                        !mode5_payload_oh2_valid_i) begin
                        mode5_payload_oh2_i <=
                            vgm_scan_payload_af_debug_live;
                        mode5_payload_oh2_valid_i <= 1'b1;
                    end

                    if ((vgm_scan_copy_read_accept_count_debug_live >=
                         16'd9) &&
                        vgm_scan_payload_vd_debug_live[0] &&
                        !mode5_payload_vh_valid_i) begin
                        mode5_payload_vh_i <=
                            vgm_scan_payload_vd_debug_live;
                        mode5_payload_vh_valid_i <= 1'b1;
                    end

                    if ((vgm_scan_copy_read_accept_count_debug_live >=
                         16'd9) &&
                        vgm_scan_payload_cp_debug_live[0] &&
                        !mode5_payload_ch_valid_i) begin
                        mode5_payload_ch_i <=
                            vgm_scan_payload_cp_debug_live;
                        mode5_payload_ch_valid_i <= 1'b1;
                    end

                    if (vgm_scan_copy_payload_pc_debug_live != 16'd0) begin
                        mode5_copy_payload_pc_i <=
                            vgm_scan_copy_payload_pc_debug_live;
                    end

                    if (!mode5_remaining_zero_early_seen_i &&
                        (vgm_scan_remaining_zero_before_expected_accept_debug_live ||
                         (mode5_freeze_active && mode5_freeze_scan_copy_tail[7]) ||
                         ((mode5_payload_len_low_i != 16'd0) &&
                          (mode5_copy_min_remaining_i != 16'hffff) &&
                          (mode5_copy_min_remaining_i == 16'd0) &&
                          (mode5_copy_max_ready_count_i != mode5_payload_len_low_i)) ||
                         vgm_scan_used_noncopy_advance_debug_live)) begin
                        mode5_remaining_zero_early_seen_i <= 1'b1;
                        mode5_zero_state_debug_i <=
                            {9'd0, vgm_scan_state_debug_live};
                        mode5_zero_pc_debug_i <= vgm_scan_pc_debug_live[15:0];
                        mode5_zero_cmd_debug_i <= {
                            vgm_scan_copy_tail_debug_live[7:0],
                            vgm_scan_last_cmd_debug_live
                        };
                    end

                    if (vgm_scan_copy_tail_debug_live[4]) begin
                        mode5_copy_ready_low_seen_i <= 1'b1;
                    end

                    if (vgm_scan_copy_tail_debug_live[6]) begin
                        mode5_copy_fifo_full_seen_i <= 1'b1;
                    end

                    if (!mode5_freeze_active &&
                        (player_busy || segapcm_rom_scan_busy)) begin
                        mode5_freeze_play_seen <= 1'b1;
                    end

                    if (mode5_freeze_event) begin
                        mode5_freeze_active <= 1'b1;
                        mode5_freeze_final_state <= vgm_final_state_debug_live;
                        mode5_freeze_final_pc <= vgm_final_pc_debug_live;
                        mode5_freeze_final_cmd <= vgm_final_cmd_debug_live;
                        mode5_freeze_final_error_code <=
                            vgm_final_error_code_debug_live;
                        mode5_freeze_final_flags <= vgm_final_flags_debug_live;
                        mode5_freeze_final_reason <= vgm_final_reason_debug_live;
                        mode5_freeze_final_progress <=
                            vgm_final_progress_debug_live;
                        mode5_freeze_first_playback_cmd <=
                            vgm_first_playback_cmd_after_scan_debug_live;
                        mode5_freeze_first_playback_cmds <=
                            vgm_first_playback_cmds_after_scan_debug_live;
                        mode5_freeze_scan_state <= vgm_scan_state_debug_live;
                        mode5_freeze_scan_pc <= vgm_scan_pc_debug_live;
                        mode5_freeze_scan_last_cmd <=
                            vgm_scan_last_cmd_debug_live;
                        mode5_freeze_scan_block_type <=
                            vgm_scan_block_type_debug_live;
                        mode5_freeze_scan_block_size_low <=
                            vgm_scan_block_size_low_debug_live;
                        mode5_freeze_scan_remaining_low <=
                            vgm_scan_remaining_low_debug_live;
                        mode5_freeze_scan_wait <= vgm_scan_wait_debug_live;
                        mode5_freeze_scan_abort_reason <=
                            vgm_scan_abort_reason_debug_live;
                        mode5_freeze_scan_copy_last_index_low <=
                            vgm_scan_copy_last_index_low_debug_live;
                        mode5_freeze_scan_copy_req_count <=
                            vgm_scan_copy_req_count_debug_live;
                        mode5_freeze_scan_copy_ready_count <=
                            vgm_scan_copy_ready_count_debug_live;
                        mode5_freeze_scan_copy_tail <= {
                            vgm_scan_copy_tail_debug_live[15:10],
                            mode5_copy_fifo_full_seen_i |
                                vgm_scan_copy_tail_debug_live[6],
                            mode5_copy_ready_low_seen_i |
                                vgm_scan_copy_tail_debug_live[4],
                            vgm_scan_copy_tail_debug_live[7:0]
                        };
                    end

                    if (mode5_player_start_to_player) begin
                        mode5_player_start_hold_seen <= 1'b1;
                    end

                    if (mode5_start_hold_prev &&
                        !mode5_player_start_hold &&
                        !vgm_player_core_debug[15] &&
                        !vgm_player_core_debug[12]) begin
                        mode5_start_hold_lost_without_accept <= 1'b1;
                    end

                    if (mode5_player_start_hold &&
                        vgm_player_core_debug[15]) begin
                        mode5_player_start_hold <= 1'b0;
                        mode5_start_hold_clear_by_start_seen <= 1'b1;
                    end else if (mode5_player_start_hold &&
                                 vgm_player_core_debug[12]) begin
                        mode5_player_start_hold <= 1'b0;
                        mode5_start_hold_clear_by_header_request <= 1'b1;
                    end else if (mode5_player_start_hold &&
                                 !START_HOLD_NO_BUSY_CLEAR &&
                                 player_busy) begin
                        mode5_player_start_hold <= 1'b0;
                        mode5_start_hold_clear_by_busy <= 1'b1;
                    end else if (mode5_player_start_hold &&
                                 (vgm_load_busy ||
                                  vgm_load_error ||
                                  vgm_load_overflow ||
                                  (!START_HOLD_NO_BUSY_CLEAR &&
                                   mode5_load_session_active))) begin
                        mode5_player_start_hold <= 1'b0;
                        mode5_start_hold_clear_by_load_reset <= 1'b1;
                    end

                    if (mode5_player_start_hold && vgm_header_valid) begin
                        mode5_start_hold_clear_by_header_valid <= 1'b1;
                    end

                    if (mode5_player_start_hold && loaded_player_done) begin
                        mode5_start_hold_clear_by_done <= 1'b1;
                    end

                    if (mode5_player_start_hold && vgm_player_error) begin
                        mode5_start_hold_clear_by_error <= 1'b1;
                    end

                    if (mode5_playback_started && player_busy && !loaded_player_done) begin
                        mode5_done_armed_i <= 1'b1;
                        mode5_done_armed_session_id_i <= mode5_playback_session_id_i;
                    end

                    if (mode5_playback_started && !loaded_player_done) begin
                        mode5_cycles_since_start_i <=
                            mode5_cycles_since_start_i + 32'd1;
                    end

                    if (mode5_idle_fallthrough_live) begin
                        mode5_top_stop_snapshot_debug_i <= {
                            4'ha,
                            (vgm_final_reason_debug == 4'd0),
                            vgm_final_progress_debug[5],
                            vgm_final_progress_debug[4],
                            vgm_final_progress_debug[3],
                            vgm_final_progress_debug[2],
                            vgm_header_valid,
                            mode5_playback_armed,
                            mode5_playback_started,
                            vgm_load_done,
                            !vgm_player_error,
                            !loaded_player_done,
                            !player_busy,
                            1'b1
                        };
                    end

                    if (mode5_done_edge) begin
                        mode5_player_end_count_i <=
                            mode5_player_end_count_i + 32'd1;
                        mode5_done_armed_i <= 1'b0;
                        mode5_done_armed_session_id_i <= 32'd0;
                        mode5_done_session_id_i <= mode5_playback_session_id_i;
                        mode5_done_pc_debug_i <= player_done_pc_debug;
                        mode5_done_cmd_debug_i <= player_done_cmd_debug;
                        mode5_player_done_latched <= 1'b1;
                    end

                    if (mode5_player_error_edge) begin
                        mode5_error_session_id_i <= mode5_playback_session_id_i;
                        mode5_playback_armed <= 1'b0;
                        mode5_playback_started <= 1'b0;
                        mode5_done_armed_i <= 1'b0;
                        mode5_done_armed_session_id_i <= 32'd0;
                        mode5_player_done_latched <= 1'b0;
                        mode5_repeat_state <= MODE5_REPEAT_IDLE;
                        mode5_sound_reset_active_i <= 1'b0;
                        mode5_sound_reset_counter <= 32'd0;
                    end

                    if (mode5_load_begin_pulse) begin
                        mode5_load_begin_count_i <= mode5_load_begin_count_i + 32'd1;
                        mode5_playback_session_id_i <= mode5_playback_session_id_i + 32'd1;
                        mode5_load_session_active <= 1'b1;
                        mode5_playback_armed <= 1'b0;
                        mode5_playback_started <= 1'b0;
                        mode5_done_armed_i <= 1'b0;
                        mode5_done_armed_session_id_i <= 32'd0;
                        mode5_player_done_latched <= 1'b0;
                        mode5_repeat_state <= MODE5_REPEAT_IDLE;
                        player_done_d <= loaded_player_done;
                        mode5_cycles_since_start_i <= 32'd0;
                        mode5_player_session_reset <= 1'b1;
                        mode5_player_start_hold <= 1'b0;
                        mode5_direct_player_start_hold <= 1'b0;
                        mode5_direct_start_used <= 1'b0;
                        smoke_parser_start_hold <= 1'b0;
                        smoke_parser_start_used <= 1'b0;
                        mode5_top_stop_snapshot_debug_i <= 16'd0;
                        loaded_player_start_input_live_d <= 1'b0;
                        segapcm_rom_scan_busy_d <= 1'b0;
                        mode5_copy_max_ready_count_i <= 16'd0;
                        mode5_copy_min_remaining_i <= 16'hffff;
                        mode5_backend_copy_accept_max_i <= 16'd0;
                        mode5_backend_copy_write_max_i <= 16'd0;
                        mode5_payload_len_low_i <= 16'd0;
                        mode5_remaining_zero_early_seen_i <= 1'b0;
                        mode5_zero_state_debug_i <= 16'd0;
                        mode5_zero_pc_debug_i <= 16'd0;
                        mode5_zero_cmd_debug_i <= 16'd0;
                        mode5_raw_event_seen_i <= 16'd0;
                        mode5_raw_copy_byte_max_i <= 16'd0;
                        mode5_copy_read_req_max_i <= 16'd0;
                        mode5_copy_read_accept_max_i <= 16'd0;
                        mode5_copy_read_valid_max_i <= 16'd0;
                        mode5_copy_mem_req_cycle_max_i <= 16'd0;
                        mode5_copy_mem_req_ready_cycle_max_i <= 16'd0;
                        mode5_copy_read_raw_valid_max_i <= 16'd0;
                        mode5_copy_read_ignored_valid_max_i <= 16'd0;
                        mode5_payload_sf_i <= 8'd0;
                        mode5_copy_read_handshake_seen_i <= 16'd0;
                        mode5_copy_payload_pc_i <= 16'd0;
                        mode5_payload_oh_i <= 16'd0;
                        mode5_payload_ah_i <= 16'd0;
                        mode5_payload_oh2_i <= 16'd0;
                        mode5_payload_vh_i <= 16'd0;
                        mode5_payload_ch_i <= 16'd0;
                        mode5_payload_bd_i <= 16'd0;
                        mode5_payload_as_i <= 3'd0;
                        mode5_payload_vs_i <= 5'd0;
                        mode5_payload_cs_i <= 6'd0;
                        mode5_counter_latch_accept_i <= 16'd0;
                        mode5_counter_latch_read_i <= 16'd0;
                        mode5_term_pl_i <= 16'd0;
                        mode5_term_rm_i <= 16'd0;
                        mode5_term_cc_i <= 16'd0;
                        mode5_term_nx_i <= 16'd0;
                        mode5_term_be_i <= 16'hBE00;
                        mode5_guard_debug_i <= 8'd0;
                        mode5_sticky_guard_debug_i <= 8'd0;
                        mode5_term_valid_i <= 1'b0;
                        mode5_prev_raw_player_accept_i <= 16'd0;
                        mode5_prev_raw_copy_accept_i <= 16'd0;
                        mode5_prev_raw_read_accept_i <= 16'd0;
                        mode5_prev_raw_read_valid_i <= 16'd0;
                        mode5_counter_increment_seen_i <= 4'd0;
                        mode5_counter_latch_valid_i <= 1'b0;
                        mode5_counter_update_overwritten_i <= 1'b0;
                        mode5_counter_reset_after_increment_i <= 1'b0;
                        mode5_counter_reset_reason_i <= 6'd0;
                        mode5_counter_reset_source_i <= 8'd0;
                        mode5_stop_source_i <= 8'd0;
                        mode5_payload_oh_valid_i <= 1'b0;
                        mode5_payload_oh2_valid_i <= 1'b0;
                        mode5_payload_vh_valid_i <= 1'b0;
                        mode5_payload_ch_valid_i <= 1'b0;
                        mode5_restart_after_load_count_i <= 16'd0;
                        mode5_start_attempt_count_i <= 16'd0;
                        mode5_scan_start_count_i <= 16'd0;
                        mode5_copy_fifo_full_seen_i <= 1'b0;
                        mode5_copy_ready_low_seen_i <= 1'b0;
                        mode5_freeze_active <= 1'b0;
                        mode5_freeze_play_seen <= 1'b0;
                        mode5_freeze_final_state <= 7'd0;
                        mode5_freeze_final_pc <= '0;
                        mode5_freeze_final_cmd <= 8'd0;
                        mode5_freeze_final_error_code <= 8'd0;
                        mode5_freeze_final_flags <= 16'd0;
                        mode5_freeze_final_reason <= 4'd0;
                        mode5_freeze_final_progress <= 16'd0;
                        mode5_freeze_first_playback_cmd <= 8'd0;
                        mode5_freeze_first_playback_cmds <= 32'd0;
                        mode5_freeze_scan_state <= 7'd0;
                        mode5_freeze_scan_pc <= '0;
                        mode5_freeze_scan_last_cmd <= 8'd0;
                        mode5_freeze_scan_block_type <= 8'd0;
                        mode5_freeze_scan_block_size_low <= 16'd0;
                        mode5_freeze_scan_remaining_low <= 16'd0;
                        mode5_freeze_scan_wait <= 16'd0;
                        mode5_freeze_scan_abort_reason <= 8'd0;
                        mode5_freeze_scan_copy_last_index_low <= 16'd0;
                        mode5_freeze_scan_copy_req_count <= 16'd0;
                        mode5_freeze_scan_copy_ready_count <= 16'd0;
                        mode5_freeze_scan_copy_tail <= 16'd0;
                        mode5_player_start_hold_seen <= 1'b0;
                        mode5_start_hold_clear_by_busy <= 1'b0;
                        mode5_start_hold_clear_by_done <= 1'b0;
                        mode5_start_hold_clear_by_error <= 1'b0;
                        mode5_start_hold_clear_by_load_reset <= 1'b0;
                        mode5_start_hold_clear_by_other <= 1'b0;
                        mode5_start_hold_clear_by_start_seen <= 1'b0;
                        mode5_start_hold_clear_by_header_request <= 1'b0;
                        mode5_start_hold_clear_by_header_valid <= 1'b0;
                        mode5_start_hold_lost_without_accept <= 1'b0;
                        mode5_start_hold_prev <= 1'b0;
                        mode5_player_reset_count_i <= mode5_player_reset_count_i + 32'd1;
                        mode5_sound_reset_active_i <= 1'b0;
                        mode5_sound_reset_counter <= 32'd0;
                    end else if (!mode5_segapcm_copy_continue_guard &&
                                 mode5_done_edge &&
                                 MODE5_REPEAT_ENABLE &&
                                 vgm_load_done &&
                                 vgm_header_valid &&
                                 !vgm_load_busy &&
                                 !vgm_load_error &&
                                 !vgm_load_overflow &&
                                 !vgm_player_error &&
                                 !mode5_load_session_active) begin
                        mode5_playback_armed <= 1'b0;
                        mode5_playback_started <= 1'b0;
                        mode5_done_armed_i <= 1'b0;
                        mode5_done_armed_session_id_i <= 32'd0;
                        mode5_player_done_latched <= 1'b0;
                        mode5_cycles_since_start_i <= 32'd0;
                        mode5_repeat_restart_count_i <=
                            mode5_repeat_restart_count_i + 32'd1;
                        mode5_playback_session_id_i <=
                            mode5_playback_session_id_i + 32'd1;
                        mode5_repeat_session_id_i <=
                            mode5_playback_session_id_i + 32'd1;
                        mode5_player_reset_count_i <=
                            mode5_player_reset_count_i + 32'd1;
                        mode5_sound_reset_counter <= 32'd0;
                        mode5_sound_reset_active_i <= 1'b0;
                        mode5_repeat_state <= MODE5_REPEAT_RESET;
                    end else if (!mode5_segapcm_copy_continue_guard &&
                                 (play_ready_pulse || mode5_load_ready_level)) begin
                        mode5_load_done_edge_count_i <= mode5_load_done_edge_count_i + 32'd1;
                        mode5_load_session_active <= 1'b0;
                        mode5_playback_armed <= 1'b1;
                        mode5_playback_started <= 1'b0;
                        mode5_done_armed_i <= 1'b0;
                        mode5_done_armed_session_id_i <= 32'd0;
                        mode5_player_done_latched <= 1'b0;
                        mode5_repeat_state <= MODE5_REPEAT_IDLE;
                        mode5_repeat_session_id_i <= mode5_playback_session_id_i;
                        player_done_d <= loaded_player_done;
                        mode5_cycles_since_start_i <= 32'd0;
                        mode5_sound_reset_counter <= 32'd0;

                        if (MODE5_SOUND_RESET_CYCLES == 32'd0) begin
                            mode5_sound_reset_active_i <= 1'b0;
                            mode5_player_start_pulse <= 1'b1;
                            mode5_player_start_hold <= 1'b1;
                            mode5_playback_started <= 1'b1;
                            mode5_done_armed_i <= 1'b0;
                            mode5_done_armed_session_id_i <= 32'd0;
                            mode5_cycles_since_start_i <= 32'd0;
                            mode5_player_start_count_i <= mode5_player_start_count_i + 32'd1;
                        end else begin
                            mode5_sound_reset_active_i <= 1'b1;
                            mode5_sound_reset_start_count_i <=
                                mode5_sound_reset_start_count_i + 32'd1;
                        end
                    end else if (vgm_load_busy || vgm_load_error || vgm_load_overflow) begin
                        mode5_sound_reset_active_i <= 1'b0;
                        mode5_sound_reset_counter <= 32'd0;
                        if (vgm_load_error || vgm_load_overflow) begin
                            mode5_load_session_active <= 1'b0;
                            mode5_playback_armed <= 1'b0;
                            mode5_playback_started <= 1'b0;
                            mode5_done_armed_i <= 1'b0;
                            mode5_done_armed_session_id_i <= 32'd0;
                            mode5_repeat_state <= MODE5_REPEAT_IDLE;
                            mode5_player_session_reset <= 1'b1;
                            mode5_player_start_hold <= 1'b0;
                            mode5_start_hold_clear_by_load_reset <= 1'b1;
                            mode5_player_reset_count_i <= mode5_player_reset_count_i + 32'd1;
                        end
                    end else if (!mode5_segapcm_copy_continue_guard &&
                                 (mode5_repeat_state == MODE5_REPEAT_RESET)) begin
                        mode5_player_session_reset <= 1'b1;
                        mode5_player_start_hold <= 1'b0;
                        mode5_start_hold_clear_by_other <= 1'b1;
                        mode5_sound_reset_active_i <= 1'b0;
                        mode5_sound_reset_counter <= 32'd0;
                        mode5_repeat_state <= MODE5_REPEAT_WAIT_CLEAR;
                    end else if (!mode5_segapcm_copy_continue_guard &&
                                 (mode5_repeat_state == MODE5_REPEAT_WAIT_CLEAR)) begin
                        if (!loaded_player_done && !player_busy) begin
                            mode5_playback_armed <= 1'b1;
                            mode5_playback_started <= 1'b0;
                            mode5_cycles_since_start_i <= 32'd0;
                            if (MODE5_SOUND_RESET_CYCLES == 32'd0) begin
                                mode5_sound_reset_active_i <= 1'b0;
                                mode5_player_start_pulse <= 1'b1;
                                mode5_player_start_hold <= 1'b1;
                                mode5_playback_started <= 1'b1;
                                mode5_done_armed_i <= 1'b0;
                                mode5_done_armed_session_id_i <= 32'd0;
                                mode5_player_start_count_i <=
                                    mode5_player_start_count_i + 32'd1;
                            end else begin
                                mode5_sound_reset_active_i <= 1'b1;
                                mode5_sound_reset_start_count_i <=
                                    mode5_sound_reset_start_count_i + 32'd1;
                            end
                            mode5_repeat_state <= MODE5_REPEAT_IDLE;
                        end
                    end else if (mode5_sound_reset_active_i) begin
                        if (mode5_sound_reset_counter >= (MODE5_SOUND_RESET_CYCLES - 32'd1)) begin
                            mode5_sound_reset_active_i <= 1'b0;
                            mode5_sound_reset_counter <= 32'd0;
                            if (mode5_playback_armed &&
                                !mode5_playback_started &&
                                vgm_load_done &&
                                !vgm_load_error &&
                                !vgm_load_overflow) begin
                                mode5_player_start_pulse <= 1'b1;
                                mode5_player_start_hold <= 1'b1;
                                mode5_playback_started <= 1'b1;
                                mode5_done_armed_i <= 1'b0;
                                mode5_done_armed_session_id_i <= 32'd0;
                                mode5_cycles_since_start_i <= 32'd0;
                                mode5_player_start_count_i <=
                                    mode5_player_start_count_i + 32'd1;
                            end else if (mode5_playback_started) begin
                                mode5_duplicate_start_blocked_count_i <=
                                    mode5_duplicate_start_blocked_count_i + 32'd1;
                            end
                        end else begin
                            mode5_sound_reset_counter <= mode5_sound_reset_counter + 32'd1;
                        end
                    end else if (!mode5_segapcm_copy_continue_guard &&
                                 mode5_playback_armed &&
                                 mode5_playback_started &&
                                 vgm_load_done &&
                                 vgm_header_valid &&
                                 !player_busy &&
                                 !loaded_player_done) begin
                        mode5_duplicate_start_blocked_count_i <=
                            mode5_duplicate_start_blocked_count_i + 32'd1;
                    end
                end
            end

            assign mode5_continue_reset_block =
                mode5_be_continue_guard &&
                !mode5_load_begin_pulse &&
                !vgm_load_busy &&
                !vgm_load_error &&
                !vgm_load_overflow;
            assign mode5_sound_core_reset =
                vgm_load_busy |
                vgm_load_error |
                vgm_load_overflow |
                (!mode5_continue_reset_block &&
                 (mode5_sound_reset_active_i |
                  mode5_load_session_active |
                  mode5_player_session_reset));
            assign mode5_player_start_to_player =
                mode5_player_start_pulse | mode5_player_start_hold;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
            assign smoke_parser_run_enable =
                SEGAPCM_SMOKE_PARSER_RUN_TEST && YM2151_EXPERIMENTAL_MODE;
`else
            assign smoke_parser_run_enable = 1'b0;
`endif
            assign smoke_parser_start_to_player =
                smoke_parser_run_enable && smoke_parser_start_hold;
            assign loaded_player_start_input_normal =
                (DIRECT_PLAYER_START_DEBUG && YM2151_EXPERIMENTAL_MODE) ?
                mode5_direct_player_start_hold :
                mode5_player_start_to_player;
            assign loaded_player_start_input_live =
                smoke_parser_start_to_player ?
                1'b1 : loaded_player_start_input_normal;
            assign smoke_parser_loaded_player_reset =
                mode5_load_begin_pulse |
                vgm_load_busy |
                vgm_load_error |
                vgm_load_overflow;
            assign mode5_loaded_player_reset =
                reset |
                (smoke_parser_run_enable ?
                 smoke_parser_loaded_player_reset :
                 mode5_sound_core_reset);
            assign mode5_sound_reset_active = mode5_sound_reset_active_i;
            assign mode5_player_start_pulse_debug = loaded_player_start_input_live;
            assign mode5_start_hold_debug = {
                reset,
                mode5_loaded_player_reset,
                mode5_load_session_active,
                (DIRECT_PLAYER_START_DEBUG || smoke_parser_run_enable),
                mode5_top_file_ok,
                vgm_load_done,
                (vgm_load_error || vgm_load_overflow),
                (mode5_direct_player_start_hold || smoke_parser_start_hold),
                mode5_player_start_hold,
                mode5_player_start_to_player,
                vgm_player_lifecycle_debug[11],
                vgm_player_lifecycle_debug[7],
                mode5_start_hold_lost_without_accept,
                START_HOLD_NO_BUSY_CLEAR,
                mode5_start_hold_clear_by_other,
                loaded_player_start_input_live
            };
            assign mode5_load_begin_count = mode5_load_begin_count_i;
            assign mode5_load_done_edge_count = mode5_load_done_edge_count_i;
            assign mode5_sound_reset_start_count = mode5_sound_reset_start_count_i;
            assign mode5_player_start_count = mode5_player_start_count_i;
            assign mode5_player_reset_count = mode5_player_reset_count_i;
            assign mode5_playback_session_id = mode5_playback_session_id_i;
            assign mode5_duplicate_start_blocked_count =
                mode5_duplicate_start_blocked_count_i;
            assign mode5_player_end_count = mode5_player_end_count_i;
            assign mode5_repeat_restart_count = mode5_repeat_restart_count_i;
            assign mode5_done_armed_debug = mode5_done_armed_i;
            assign mode5_repeat_session_id = mode5_repeat_session_id_i;
            assign mode5_done_session_id = mode5_done_session_id_i;
            assign mode5_cycles_since_start = mode5_cycles_since_start_i;
            assign mode5_done_pc_debug = mode5_done_pc_debug_i;
            assign mode5_done_cmd_debug = mode5_done_cmd_debug_i;
            assign mode5_copy_max_ready_count_debug =
                mode5_copy_max_ready_count_i;
            assign mode5_copy_min_remaining_debug =
                (mode5_copy_min_remaining_i == 16'hffff) ? 16'd0 :
                mode5_copy_min_remaining_i;
            assign mode5_copy_mismatch_debug = {
                12'd0,
                ((mode5_payload_len_low_i != 16'd0) &&
                 (mode5_copy_remaining_from_count == 16'd0) &&
                 (mode5_backend_copy_write_max_i !=
                  mode5_expected_copy_write_words)),
                ((mode5_payload_len_low_i != 16'd0) &&
                 (mode5_copy_remaining_from_count == 16'd0) &&
                 (mode5_backend_copy_accept_max_i != mode5_payload_len_low_i)),
                ((mode5_payload_len_low_i != 16'd0) &&
                 (mode5_copy_remaining_from_count == 16'd0) &&
                 (mode5_copy_max_ready_count_i != mode5_payload_len_low_i)),
                (mode5_copy_max_ready_count_i != mode5_backend_copy_accept_max_i)
            };
            assign mode5_restart_after_load_count_debug =
                mode5_restart_after_load_count_i;
            assign mode5_scan_start_count_debug =
                mode5_scan_start_count_i;
            assign mode5_direct_start_debug = {
                5'd0,
                smoke_parser_run_enable,
                smoke_parser_start_used,
                smoke_parser_start_hold,
                mode5_direct_start_used,
                (mode5_direct_player_start_hold || smoke_parser_start_hold),
                loaded_player_start_input_live,
                (DIRECT_PLAYER_START_DEBUG || smoke_parser_run_enable),
                mode5_start_attempt_count_i[3:0]
            };
            assign mode5_top_stop_snapshot_debug =
                mode5_freeze_active ?
                {8'hf0, 4'd0, mode5_direct_start_used,
                 mode5_freeze_play_seen, mode5_freeze_active, 1'b1} :
                mode5_top_stop_snapshot_debug_i;
            assign vgm_final_state_debug =
                mode5_freeze_active ? mode5_freeze_final_state :
                vgm_final_state_debug_live;
            assign vgm_final_pc_debug =
                mode5_freeze_active ? mode5_freeze_final_pc :
                vgm_final_pc_debug_live;
            assign vgm_final_cmd_debug =
                mode5_freeze_active ? mode5_freeze_final_cmd :
                vgm_final_cmd_debug_live;
            assign vgm_final_error_code_debug =
                mode5_freeze_active ? mode5_freeze_final_error_code :
                vgm_final_error_code_debug_live;
            assign vgm_final_flags_debug =
                mode5_freeze_active ? mode5_freeze_final_flags :
                vgm_final_flags_debug_live;
            assign vgm_final_reason_debug =
                mode5_freeze_active ? mode5_freeze_final_reason :
                vgm_final_reason_debug_live;
            assign vgm_final_progress_debug =
                mode5_freeze_active ? mode5_freeze_final_progress :
                vgm_final_progress_debug_live;
            assign vgm_first_playback_cmd_after_scan_debug =
                mode5_freeze_active ? mode5_freeze_first_playback_cmd :
                vgm_first_playback_cmd_after_scan_debug_live;
            assign vgm_first_playback_cmds_after_scan_debug =
                mode5_freeze_active ? mode5_freeze_first_playback_cmds :
                vgm_first_playback_cmds_after_scan_debug_live;
            assign vgm_scan_state_debug =
                mode5_freeze_active ? mode5_freeze_scan_state :
                vgm_scan_state_debug_live;
            assign vgm_scan_pc_debug =
                mode5_freeze_active ? mode5_freeze_scan_pc :
                vgm_scan_pc_debug_live;
            assign vgm_scan_last_cmd_debug =
                mode5_freeze_active ? mode5_freeze_scan_last_cmd :
                vgm_scan_last_cmd_debug_live;
            assign vgm_scan_block_type_debug =
                mode5_freeze_active ? mode5_freeze_scan_block_type :
                vgm_scan_block_type_debug_live;
            assign vgm_scan_block_size_low_debug =
                mode5_freeze_active ? mode5_freeze_scan_block_size_low :
                vgm_scan_block_size_low_debug_live;
            assign vgm_scan_remaining_low_debug =
                mode5_freeze_active ? mode5_freeze_scan_remaining_low :
                vgm_scan_remaining_low_debug_live;
            assign vgm_scan_wait_debug =
                mode5_freeze_active ? mode5_freeze_scan_wait :
                vgm_scan_wait_debug_live;
            assign vgm_scan_abort_reason_debug =
                mode5_freeze_active ? mode5_freeze_scan_abort_reason :
                vgm_scan_abort_reason_debug_live;
            assign vgm_scan_copy_last_index_low_debug =
                mode5_freeze_active ? mode5_freeze_scan_copy_last_index_low :
                vgm_scan_copy_last_index_low_debug_live;
            assign vgm_scan_copy_req_count_debug =
                mode5_freeze_active ? mode5_freeze_scan_copy_req_count :
                vgm_scan_copy_req_count_debug_live;
            assign vgm_scan_copy_ready_count_debug =
                mode5_freeze_active ? mode5_freeze_scan_copy_ready_count :
                vgm_scan_copy_ready_count_debug_live;
            assign vgm_scan_copy_tail_debug =
                mode5_freeze_active ? mode5_freeze_scan_copy_tail :
                {vgm_scan_copy_tail_debug_live[15:10],
                 mode5_copy_fifo_full_seen_i,
                 mode5_copy_ready_low_seen_i,
                 vgm_scan_copy_tail_debug_live[7:0]};
            assign vgm_scan_player_accept_count_debug =
                mode5_copy_max_ready_count_i;
            assign vgm_scan_player_remaining_debug =
                mode5_copy_remaining_from_count;
            assign vgm_scan_payload_len_low_debug =
                mode5_payload_len_low_i;
            assign vgm_scan_remaining_zero_before_expected_accept_debug =
                mode5_remaining_zero_early_seen_i |
                vgm_scan_remaining_zero_before_expected_accept_debug_live |
                (mode5_freeze_active && mode5_freeze_scan_copy_tail[7]) |
                ((mode5_payload_len_low_i != 16'd0) &&
                 (mode5_copy_remaining_from_count == 16'd0) &&
                 (mode5_copy_max_ready_count_i != mode5_payload_len_low_i));
            assign vgm_scan_zero_state_debug = mode5_zero_state_debug_i;
            assign vgm_scan_zero_pc_debug = mode5_zero_pc_debug_i;
            assign vgm_scan_zero_cmd_debug = mode5_zero_cmd_debug_i;
            assign vgm_scan_copy_accept_fire_count_debug =
                mode5_copy_max_ready_count_i;
            assign vgm_scan_noncopy_advance_count_debug =
                vgm_scan_noncopy_advance_count_debug_live;
            assign vgm_scan_used_noncopy_advance_debug =
                vgm_scan_used_noncopy_advance_debug_live;
            assign vgm_scan_raw_copy_byte_count_debug =
                mode5_raw_copy_byte_max_i;
            assign vgm_scan_raw_event_debug =
                mode5_raw_event_seen_i | vgm_scan_raw_event_debug_live;
            assign vgm_scan_copy_exit_debug =
                vgm_scan_copy_exit_debug_live;
            assign vgm_scan_copy_exit_pc_debug =
                vgm_scan_copy_exit_pc_debug_live;
            assign vgm_scan_copy_exit_count_debug =
                vgm_scan_copy_exit_count_debug_live;
            assign vgm_scan_copy_phase_debug =
                vgm_scan_copy_phase_debug_live;
            assign vgm_scan_copy_read_req_count_debug =
                mode5_copy_read_req_max_i;
            assign vgm_scan_copy_read_accept_count_debug =
                mode5_copy_read_accept_max_i;
            assign vgm_scan_copy_read_accept_internal_debug =
                vgm_scan_copy_read_accept_count_debug_live;
            assign vgm_scan_copy_read_valid_count_debug =
                mode5_copy_read_valid_max_i;
            assign vgm_scan_copy_mem_req_cycle_count_debug =
                mode5_copy_mem_req_cycle_max_i;
            assign vgm_scan_copy_mem_req_ready_cycle_count_debug =
                mode5_copy_mem_req_ready_cycle_max_i;
            assign vgm_scan_copy_request_state_debug =
                vgm_scan_copy_request_state_debug_live;
            assign vgm_scan_copy_state_lifetime_debug =
                mode5_copy_state_lifetime_i;
            assign vgm_scan_copy_clear_reason_debug =
                mode5_copy_clear_reason_i;
            assign vgm_scan_copy_payload_pc_debug =
                mode5_copy_payload_pc_i;
            assign vgm_scan_copy_first01_debug =
                vgm_scan_copy_first01_debug_live;
            assign vgm_scan_copy_first23_debug =
                vgm_scan_copy_first23_debug_live;
            assign vgm_scan_copy_first45_debug =
                vgm_scan_copy_first45_debug_live;
            assign vgm_scan_copy_first67_debug =
                vgm_scan_copy_first67_debug_live;
            assign vgm_scan_copy_first8_phase_debug =
                vgm_scan_copy_first8_phase_debug_live;
            assign vgm_scan_copy_read_raw_valid_count_debug =
                mode5_copy_read_raw_valid_max_i;
            assign vgm_scan_copy_read_ignored_valid_count_debug =
                mode5_copy_read_ignored_valid_max_i;
            assign vgm_scan_copy_read_handshake_debug =
                mode5_copy_read_handshake_seen_i |
                mode5_copy_read_handshake_mapped;
            assign vgm_scan_payload_o0_debug =
                vgm_scan_payload_o0_debug_live;
            assign vgm_scan_payload_oh_debug =
                mode5_payload_oh_valid_i ? mode5_payload_oh_i : 16'd0;
            assign vgm_scan_payload_bd_debug = mode5_payload_bd_i;
            assign vgm_scan_payload_af_debug =
                vgm_scan_payload_af_debug_live;
            assign vgm_scan_payload_ah_debug =
                mode5_payload_oh_valid_i ? mode5_payload_ah_i : 16'd0;
            assign vgm_scan_payload_oh2_debug =
                mode5_payload_oh2_valid_i ? mode5_payload_oh2_i : 16'd0;
            assign vgm_scan_payload_as_debug = {
                8'hE0,
                5'd0,
                mode5_payload_as_i
            };
            assign vgm_scan_payload_vd_debug =
                vgm_scan_payload_vd_debug_live;
            assign vgm_scan_payload_vh_debug =
                mode5_payload_vh_valid_i ? mode5_payload_vh_i : 16'd0;
            assign vgm_scan_payload_vs_debug = {
                8'hE1,
                3'd0,
                mode5_payload_vs_i
            };
            assign vgm_scan_payload_cp_debug =
                vgm_scan_payload_cp_debug_live;
            assign vgm_scan_payload_ch_debug =
                mode5_payload_ch_valid_i ? mode5_payload_ch_i : 16'd0;
            assign vgm_scan_payload_cs_debug = {
                8'hE2,
                2'd0,
                mode5_payload_cs_i
            };
            assign vgm_scan_raw_player_accept_count_debug =
                vgm_scan_player_accept_count_debug_live;
            assign vgm_scan_raw_copy_accept_count_debug =
                vgm_scan_copy_accept_fire_count_debug_live;
            assign vgm_scan_raw_read_accept_count_debug =
                vgm_scan_copy_read_accept_count_debug_live;
            assign vgm_scan_raw_read_valid_count_debug =
                vgm_scan_copy_read_valid_count_debug_live;
            assign vgm_scan_max_player_accept_count_debug =
                mode5_copy_max_ready_count_i;
            assign vgm_scan_max_copy_accept_count_debug =
                mode5_copy_max_ready_count_i;
            assign vgm_scan_max_read_accept_count_debug =
                mode5_copy_read_accept_max_i;
            assign vgm_scan_max_read_valid_count_debug =
                mode5_copy_read_valid_max_i;
            assign vgm_scan_counter_latch_accept_debug =
                mode5_counter_latch_valid_i ?
                mode5_counter_latch_accept_i : 16'd0;
            assign vgm_scan_counter_latch_read_debug =
                mode5_counter_latch_valid_i ?
                mode5_counter_latch_read_i : 16'd0;
            assign vgm_scan_counter_anomaly_debug = {
                8'hE3,
                mode5_counter_reset_reason_i,
                mode5_counter_reset_after_increment_i,
                mode5_be_continue_guard ?
                    1'b0 : mode5_counter_update_overwritten_i
            };
            assign vgm_scan_counter_reset_source_debug = {
                8'hE4,
                mode5_be_continue_guard ?
                    ((mode5_counter_reset_source_i |
                      mode5_counter_reset_source_live) & 8'b1111_1110) :
                    (mode5_counter_reset_source_i |
                     mode5_counter_reset_source_live)
            };
            assign vgm_scan_stop_source_debug = {
                8'hE5,
                mode5_be_continue_guard ?
                    ((mode5_stop_source_i | mode5_stop_source_live) &
                     8'b0111_1110) :
                    (mode5_stop_source_i | mode5_stop_source_live)
            };
            assign vgm_scan_term_pl_debug =
                mode5_term_valid_i ? mode5_term_pl_i : vgm_scan_payload_len_low_debug_live;
            assign vgm_scan_term_rm_debug =
                mode5_term_valid_i ? mode5_term_rm_i : vgm_scan_remaining_low_debug_live;
            assign vgm_scan_term_cc_debug =
                mode5_term_valid_i ? mode5_term_cc_i : vgm_scan_raw_copy_byte_count_debug_live;
            assign vgm_scan_term_nx_debug =
                mode5_term_valid_i ? mode5_term_nx_i : vgm_scan_term_nx_debug_live;
            assign vgm_scan_term_be_debug =
                mode5_term_valid_i ? mode5_term_be_i : vgm_scan_term_be_debug_live;
            assign vgm_scan_guard_debug = {
                8'hD6,
                mode5_guard_debug_i | mode5_guard_debug_live
            };
            assign vgm_scan_sticky_guard_debug = {
                8'hE6,
                vgm_scan_sticky_guard_debug_live[7:0] |
                mode5_sticky_guard_debug_i |
                {7'd0, mode5_term_capture_continue_live}
            };
            assign vgm_scan_payload_qg_debug = {
                8'hE7,
                vgm_scan_payload_qg_debug_live[7:0] |
                {7'd0, (mode5_copy_read_req_max_i != 16'd0)}
            };
            assign vgm_scan_payload_sf_debug = {
                8'hE9,
                mode5_payload_sf_i | vgm_scan_payload_sf_debug_live[7:0]
            };
            assign mode5_backend_copy_accept_count_debug =
                mode5_backend_copy_accept_max_i;
            assign mode5_backend_copy_write_count_debug =
                mode5_backend_copy_write_max_i;
            assign mode5_backend_copy_fifo_debug = backend_copy_fifo_debug;
            assign mode5_backend_copy_ready_debug = backend_copy_ready_debug;
            assign mode5_backend_copy_write_req_debug =
                backend_copy_write_req_debug;
            assign mode5_backend_copy_word_debug = backend_copy_word_debug;
            assign mode5_backend_copy_flush_debug = backend_copy_flush_debug;
            assign mode5_backend_copy_full_detect_count_debug =
                backend_copy_full_detect_count_debug;
            assign mode5_backend_copy_push_req_count_debug =
                backend_copy_push_req_count_debug;
            assign mode5_backend_copy_push_fire_count_debug =
                backend_copy_push_fire_count_debug;
            assign mode5_backend_copy_fifo_push_count_debug =
                backend_copy_fifo_push_count_debug;
            assign mode5_backend_copy_pack_ready_debug =
                backend_copy_pack_ready_debug;
            assign mode5_backend_copy_post_push_debug =
                backend_copy_post_push_debug;
            assign mode5_backend_read_gate_debug = backend_read_gate_debug;
            assign mode5_backend_read_after_copy_count_debug =
                backend_read_after_copy_count_debug;
            assign mode5_read_mux_debug = mode5_read_mux_live;
            assign mode5_read_ready_compare_debug =
                mode5_read_ready_compare_live;
            assign mode5_read_ready_blocker_debug =
                mode5_read_ready_blocker_live;
            assign vgm_error_session_id = mode5_error_session_id_i;
            assign player_done = mode5_player_done_latched;
            assign mode5_audio_pre_unmute = audio_gate_open &&
                                            vgm_load_done &&
                                            vgm_header_valid &&
                                            !vgm_load_busy &&
                                            !vgm_load_error &&
                                            !vgm_load_overflow &&
                                            !vgm_player_error &&
                                            !mode5_sound_core_reset &&
                                            player_busy;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
            assign audio_runtime_open = !reset;
`else
            assign audio_runtime_open = mode5_audio_pre_unmute &&
                                        mode5_audio_unmute_ready;
`endif

            always_ff @(posedge clk) begin
                if (reset || !mode5_audio_pre_unmute) begin
                    mode5_audio_unmute_counter <= 32'd0;
                    mode5_audio_unmute_ready <= 1'b0;
                end else if (MODE5_AUDIO_UNMUTE_DELAY_CYCLES == 32'd0) begin
                    mode5_audio_unmute_counter <= 32'd0;
                    mode5_audio_unmute_ready <= 1'b1;
                end else if (mode5_audio_unmute_counter >= (MODE5_AUDIO_UNMUTE_DELAY_CYCLES - 32'd1)) begin
                    mode5_audio_unmute_ready <= 1'b1;
                end else begin
                    mode5_audio_unmute_counter <= mode5_audio_unmute_counter + 32'd1;
                    mode5_audio_unmute_ready <= 1'b0;
                end
            end

            if (MODE5_VGM_BACKEND == MODE5_BACKEND_BRAM) begin : backend_bram
                vgm_file_loader #(
                    .ADDR_WIDTH       (VGM_LOAD_ADDR_WIDTH),
                    .ACCEPT_ANY_INDEX (1'b0),
                    .FILE_INDEX       (VGM_LOAD_FILE_INDEX)
                ) loader (
                    .clk              (clk),
                    .reset            (reset),
                    .ioctl_download   (ioctl_download),
                    .ioctl_wr         (ioctl_wr),
                    .ioctl_addr       (ioctl_addr),
                    .ioctl_dout       (ioctl_dout),
                    .ioctl_index      (ioctl_index),
                    .rd_addr          (ram_rd_addr),
                    .rd_data          (ram_rd_data),
                    .load_busy        (vgm_load_busy),
                    .load_done        (vgm_load_done),
                    .load_done_pulse  (load_done_pulse),
                    .load_error       (vgm_load_error),
                    .overflow_error   (vgm_load_overflow),
                    .file_size        (vgm_load_size),
                    .magic_debug      (vgm_load_magic)
                );

                assign play_ready_pulse = load_done_pulse;
                assign ioctl_wait = 1'b0;
                assign segapcm_copy_wr_ready = 1'b1;
                assign segapcm_copy_flush_done = segapcm_copy_flush_req;
                assign backend_copy_accept_count_debug = 16'd0;
                assign backend_copy_write_count_debug = 16'd0;
                assign backend_copy_fifo_debug = 16'd0;
                assign backend_copy_ready_debug = 16'd0;
                assign backend_copy_write_req_debug = 16'd0;
                assign backend_copy_word_debug = 16'd0;
                assign backend_copy_flush_debug = 16'd0;
                assign backend_copy_full_detect_count_debug = 16'd0;
                assign backend_copy_push_req_count_debug = 16'd0;
                assign backend_copy_push_fire_count_debug = 16'd0;
                assign backend_copy_fifo_push_count_debug = 16'd0;
                assign backend_copy_pack_ready_debug = 16'd0;
                assign backend_copy_post_push_debug = 16'd0;
                assign backend_read_gate_debug = 16'd0;
                assign backend_read_after_copy_count_debug = 16'd0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                assign smoke_ddr_rd_ready = 1'b0;
                assign smoke_ddr_rd_valid = 1'b0;
                assign smoke_ddr_rd_data = 8'h80;
                assign smoke_ddr_payload_present = 1'b0;
                assign smoke_ddr_payload_length = 19'd0;
                assign smoke_ddr_write_req_count_debug = 16'd0;
                assign smoke_ddr_write_count_debug = 16'd0;
                assign smoke_ddr_write_blocked_count_debug = 16'd0;
                assign smoke_ddr_write_status_debug = 16'd0;
                assign smoke_ddr_header_skip_count_debug = 16'd0;
                assign smoke_ddr_last_write_index_debug = 16'd0;
                assign smoke_ddr_last_write_addr_debug = 16'd0;
                assign smoke_ddr_last_write_lane_debug = 16'd0;
                assign smoke_ddr_last_write_data_debug = 8'd0;
                assign smoke_ddr_read_count_debug = 16'd0;
                assign smoke_ddr_last_read_index_i = 16'd0;
                assign smoke_ddr_last_read_addr_debug = 16'd0;
                assign smoke_ddr_last_read_lane_debug = 16'd0;
                assign smoke_ddr_last_read_word0_i = 16'd0;
                assign smoke_ddr_last_read_word1_i = 16'd0;
                assign smoke_ddr_last_read_data_i = 8'd0;
                assign smoke_ddr_base_addr_debug = 16'd0;
                assign smoke_ddr_probe_write_index_i = 16'd0;
                assign smoke_ddr_probe_write_word_i = 16'd0;
                assign smoke_ddr_probe_write_lane_i = 16'd0;
                assign smoke_ddr_probe_write_addr_i = 16'd0;
                assign smoke_ddr_probe_write_count_i = 16'd0;
                assign smoke_ddr_probe_write_flags_i = 16'd0;
                assign smoke_ddr_probe_write_word0_i = 16'd0;
                assign smoke_ddr_probe_write_word6_i = 16'd0;
`endif

                vgm_bram_read_adapter #(
                    .ADDR_WIDTH       (VGM_LOAD_ADDR_WIDTH)
                ) bram_read_adapter (
                    .clk              (clk),
                    .reset            (reset),
                    .mem_rd_req       (mem_rd_req),
                    .mem_rd_addr      (mem_rd_addr),
                    .mem_rd_ready     (mem_rd_ready),
                    .mem_rd_valid     (mem_rd_valid),
                    .mem_rd_data      (mem_rd_data),
                    .bram_rd_addr     (ram_rd_addr),
                    .bram_rd_data     (ram_rd_data)
                );

                assign ddram_burstcnt = 8'd0;
                assign ddram_addr     = 29'd0;
                assign ddram_rd       = 1'b0;
                assign ddram_din      = 64'd0;
                assign ddram_be       = 8'd0;
                assign ddram_we       = 1'b0;
            end else if (MODE5_VGM_BACKEND == MODE5_BACKEND_DDRAM) begin : backend_ddram
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
                assign segapcm_copy_wr_ready = 1'b1;
                assign segapcm_copy_flush_done = segapcm_copy_flush_req;
                assign backend_copy_accept_count_debug = 16'd0;
                assign backend_copy_write_count_debug = 16'd0;
                assign backend_copy_fifo_debug = 16'd0;
                assign backend_copy_ready_debug = 16'd0;
                assign backend_copy_write_req_debug = 16'd0;
                assign backend_copy_word_debug = 16'd0;
                assign backend_copy_flush_debug = 16'd0;
                assign backend_copy_full_detect_count_debug = 16'd0;
                assign backend_copy_push_req_count_debug = 16'd0;
                assign backend_copy_push_fire_count_debug = 16'd0;
                assign backend_copy_fifo_push_count_debug = 16'd0;
                assign backend_copy_pack_ready_debug = 16'd0;
                assign backend_copy_post_push_debug = 16'd0;
                assign backend_read_gate_debug = 16'd0;
                assign backend_read_after_copy_count_debug = 16'd0;

                vgm_c0_lab_backend #(
                    .ADDR_WIDTH       (VGM_LOAD_ADDR_WIDTH),
                    .ACCEPT_ANY_INDEX (1'b0),
                    .FILE_INDEX       (VGM_LOAD_FILE_INDEX[7:0]),
                    .DDRAM_BASE_ADDR  ({4'b0011, 25'd0})
                ) c0_lab_backend (
                    .clk              (clk),
                    .reset            (reset),
                    .ioctl_download   (ioctl_download),
                    .ioctl_wr         (ioctl_wr),
                    .ioctl_addr       ({5'd0, ioctl_addr}),
                    .ioctl_dout       (ioctl_dout),
                    .ioctl_index      (ioctl_index[7:0]),
                    .ioctl_wait       (ioctl_wait),

                    .mem_rd_req       (mem_rd_req),
                    .mem_rd_addr      (mem_rd_addr),
                    .mem_rd_ready     (mem_rd_ready),
                    .mem_rd_valid     (mem_rd_valid),
                    .mem_rd_data      (mem_rd_data),

                    .payload_tap_valid(segapcm_payload_tap_valid),
                    .payload_tap_addr (segapcm_payload_tap_addr),
                    .payload_tap_data (segapcm_payload_tap_data),
                    .type80_block_dest(smoke_ddr_type80_dest_addr),
                    .type80_block_size(smoke_ddr_type80_block_size),

`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                    .smoke_rd_req     (smoke_ddr_rd_req),
                    .smoke_rd_ready   (smoke_ddr_rd_ready),
                    .smoke_rd_addr    (smoke_ddr_rd_addr),
                    .smoke_rd_valid   (smoke_ddr_rd_valid),
                    .smoke_rd_data    (smoke_ddr_rd_data),
                    .smoke_payload_present(smoke_ddr_payload_present),
                    .smoke_payload_length(smoke_ddr_payload_length),
                    .smoke_write_req_count_debug(smoke_ddr_write_req_count_debug),
                    .smoke_write_count_debug(smoke_ddr_write_count_debug),
                    .smoke_write_blocked_count_debug(smoke_ddr_write_blocked_count_debug),
                    .smoke_write_status_debug(smoke_ddr_write_status_debug),
                    .smoke_header_skip_count_debug(smoke_ddr_header_skip_count_debug),
                    .smoke_last_write_index_debug(smoke_ddr_last_write_index_debug),
                    .smoke_last_write_addr_debug(smoke_ddr_last_write_addr_debug),
                    .smoke_last_write_lane_debug(smoke_ddr_last_write_lane_debug),
                    .smoke_last_write_data_debug(smoke_ddr_last_write_data_debug),
                    .smoke_read_count_debug(smoke_ddr_read_count_debug),
                    .smoke_last_read_index_debug(smoke_ddr_last_read_index_i),
                    .smoke_last_read_addr_debug(smoke_ddr_last_read_addr_debug),
                    .smoke_last_read_lane_debug(smoke_ddr_last_read_lane_debug),
                    .smoke_last_read_word0_debug(smoke_ddr_last_read_word0_i),
                    .smoke_last_read_word1_debug(smoke_ddr_last_read_word1_i),
                    .smoke_last_read_data_debug(smoke_ddr_last_read_data_i),
                    .smoke_base_addr_debug(smoke_ddr_base_addr_debug),
                    .smoke_probe_write_index_debug(smoke_ddr_probe_write_index_i),
                    .smoke_probe_write_word_debug(smoke_ddr_probe_write_word_i),
                    .smoke_probe_write_lane_debug(smoke_ddr_probe_write_lane_i),
                    .smoke_probe_write_addr_debug(smoke_ddr_probe_write_addr_i),
                    .smoke_probe_write_count_debug(smoke_ddr_probe_write_count_i),
                    .smoke_probe_write_flags_debug(smoke_ddr_probe_write_flags_i),
                    .smoke_probe_write_word0_debug(smoke_ddr_probe_write_word0_i),
                    .smoke_probe_write_word6_debug(smoke_ddr_probe_write_word6_i),
`endif

                    .load_busy        (vgm_load_busy),
                    .load_done        (vgm_load_done),
                    .load_done_pulse  (load_done_pulse),
                    .play_ready_pulse (play_ready_pulse),
                    .load_error       (vgm_load_error),
                    .overflow_error   (vgm_load_overflow),
                    .file_size        (vgm_load_size),
                    .magic_debug      (vgm_load_magic),

                    .ddram_busy       (ddram_busy),
                    .ddram_burstcnt   (ddram_burstcnt),
                    .ddram_addr       (ddram_addr),
                    .ddram_dout       (ddram_dout),
                    .ddram_dout_ready (ddram_dout_ready),
                    .ddram_rd         (ddram_rd),
                    .ddram_din        (ddram_din),
                    .ddram_be         (ddram_be),
                    .ddram_we         (ddram_we)
                );
`else
                vgm_ddram_backend #(
                    .ADDR_WIDTH       (VGM_LOAD_ADDR_WIDTH),
                    .ACCEPT_ANY_INDEX (1'b0),
                    .FILE_INDEX       (VGM_LOAD_FILE_INDEX),
                    .WRITE_FIFO_DEPTH (1024),
                    // Match the common MiSTer DDRAM window used by PSX/GBA:
                    // DDRAM_ADDR[28:25] = 4'b0011 maps to 0x30000000.
                    .DDRAM_BASE_ADDR  ({4'b0011, 25'd0}),
                    .SEGAPCM_ROM_BASE_ADDR({4'b0011, 25'd0} + 29'h0010_0000)
                ) ddram_backend (
                    .clk              (clk),
                    .reset            (reset),
                    .ioctl_download   (ioctl_download),
                    .ioctl_wr         (ioctl_wr),
                    .ioctl_addr       (ioctl_addr),
                    .ioctl_dout       (ioctl_dout),
                    .ioctl_index      (ioctl_index),
                    .ioctl_wait       (ioctl_wait),

                    .mem_rd_req       (mem_rd_req),
                    .mem_rd_addr      (mem_rd_addr),
                    .mem_rd_ready     (mem_rd_ready),
                    .mem_rd_valid     (mem_rd_valid),
                    .mem_rd_data      (mem_rd_data),
                    .segapcm_copy_wr_req(segapcm_copy_wr_req),
                    .segapcm_copy_wr_ready(segapcm_copy_wr_ready),
                    .segapcm_copy_wr_addr(segapcm_copy_wr_addr),
                    .segapcm_copy_wr_data(segapcm_copy_wr_data),
                    .segapcm_copy_flush_req(segapcm_copy_flush_req),
                    .segapcm_copy_flush_done(segapcm_copy_flush_done),
                    .segapcm_copy_accept_count_debug(backend_copy_accept_count_debug),
                    .segapcm_copy_write_count_debug(backend_copy_write_count_debug),
                    .segapcm_copy_fifo_debug(backend_copy_fifo_debug),
                    .segapcm_copy_ready_debug(backend_copy_ready_debug),
                    .segapcm_copy_write_req_debug(backend_copy_write_req_debug),
                    .segapcm_copy_word_debug(backend_copy_word_debug),
                    .segapcm_copy_flush_debug(backend_copy_flush_debug),
                    .segapcm_copy_full_detect_count_debug(backend_copy_full_detect_count_debug),
                    .segapcm_copy_push_req_count_debug(backend_copy_push_req_count_debug),
                    .segapcm_copy_push_fire_count_debug(backend_copy_push_fire_count_debug),
                    .segapcm_copy_fifo_push_count_debug(backend_copy_fifo_push_count_debug),
                    .segapcm_copy_pack_ready_debug(backend_copy_pack_ready_debug),
                    .segapcm_copy_post_push_debug(backend_copy_post_push_debug),
                    .segapcm_read_gate_debug(backend_read_gate_debug),
                    .segapcm_read_after_copy_count_debug(backend_read_after_copy_count_debug),
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                    .smoke_ddr_payload_tap_valid(segapcm_payload_tap_valid),
                    .smoke_ddr_payload_tap_addr(segapcm_payload_tap_addr),
                    .smoke_ddr_payload_tap_data(segapcm_payload_tap_data),
                    .smoke_ddr_capture_limit(smoke_ddr_capture_limit),
                    .smoke_ddr_rd_req(smoke_ddr_rd_req),
                    .smoke_ddr_rd_ready(smoke_ddr_rd_ready),
                    .smoke_ddr_rd_addr(smoke_ddr_rd_addr),
                    .smoke_ddr_rd_valid(smoke_ddr_rd_valid),
                    .smoke_ddr_rd_data(smoke_ddr_rd_data),
                    .smoke_ddr_payload_present(smoke_ddr_payload_present),
                    .smoke_ddr_payload_length(smoke_ddr_payload_length),
                    .smoke_ddr_write_req_count_debug(smoke_ddr_write_req_count_debug),
                    .smoke_ddr_write_count_debug(smoke_ddr_write_count_debug),
                    .smoke_ddr_write_blocked_count_debug(smoke_ddr_write_blocked_count_debug),
                    .smoke_ddr_write_status_debug(smoke_ddr_write_status_debug),
                    .smoke_ddr_header_skip_count_debug(smoke_ddr_header_skip_count_debug),
                    .smoke_ddr_last_write_index_debug(smoke_ddr_last_write_index_debug),
                    .smoke_ddr_last_write_addr_debug(smoke_ddr_last_write_addr_debug),
                    .smoke_ddr_last_write_lane_debug(smoke_ddr_last_write_lane_debug),
                    .smoke_ddr_last_write_data_debug(smoke_ddr_last_write_data_debug),
                    .smoke_ddr_read_count_debug(smoke_ddr_read_count_debug),
                    .smoke_ddr_last_read_index_debug(smoke_ddr_last_read_index_i),
                    .smoke_ddr_last_read_addr_debug(smoke_ddr_last_read_addr_debug),
                    .smoke_ddr_last_read_lane_debug(smoke_ddr_last_read_lane_debug),
                    .smoke_ddr_last_read_word0_debug(smoke_ddr_last_read_word0_i),
                    .smoke_ddr_last_read_word1_debug(smoke_ddr_last_read_word1_i),
                    .smoke_ddr_last_read_data_debug(smoke_ddr_last_read_data_i),
                    .smoke_ddr_base_addr_debug(smoke_ddr_base_addr_debug),
                    .smoke_ddr_probe_write_index_debug(smoke_ddr_probe_write_index_i),
                    .smoke_ddr_probe_write_word_debug(smoke_ddr_probe_write_word_i),
                    .smoke_ddr_probe_write_lane_debug(smoke_ddr_probe_write_lane_i),
                    .smoke_ddr_probe_write_addr_debug(smoke_ddr_probe_write_addr_i),
                    .smoke_ddr_probe_write_count_debug(smoke_ddr_probe_write_count_i),
                    .smoke_ddr_probe_write_flags_debug(smoke_ddr_probe_write_flags_i),
                    .smoke_ddr_probe_write_word0_debug(smoke_ddr_probe_write_word0_i),
                    .smoke_ddr_probe_write_word6_debug(smoke_ddr_probe_write_word6_i),
`endif

                    .load_busy        (vgm_load_busy),
                    .load_done        (vgm_load_done),
                    .load_done_pulse  (load_done_pulse),
                    .play_ready_pulse (play_ready_pulse),
                    .load_error       (vgm_load_error),
                    .overflow_error   (vgm_load_overflow),
                    .file_size        (vgm_load_size),
                    .magic_debug      (vgm_load_magic),

                    .ddram_busy       (ddram_busy),
                    .ddram_burstcnt   (ddram_burstcnt),
                    .ddram_addr       (ddram_addr),
                    .ddram_dout       (ddram_dout),
                    .ddram_dout_ready (ddram_dout_ready),
                    .ddram_rd         (ddram_rd),
                    .ddram_din        (ddram_din),
                    .ddram_be         (ddram_be),
                    .ddram_we         (ddram_we)
                );
`endif
            end else begin : backend_reserved
                assign mem_rd_ready = 1'b0;
                assign mem_rd_valid = 1'b0;
                assign mem_rd_data = 8'd0;
                assign segapcm_copy_wr_ready = 1'b0;
                assign segapcm_copy_flush_done = 1'b0;
                assign backend_copy_accept_count_debug = 16'd0;
                assign backend_copy_write_count_debug = 16'd0;
                assign backend_copy_fifo_debug = 16'd0;
                assign backend_copy_ready_debug = 16'd0;
                assign backend_copy_write_req_debug = 16'd0;
                assign backend_copy_word_debug = 16'd0;
                assign backend_copy_flush_debug = 16'd0;
                assign backend_copy_full_detect_count_debug = 16'd0;
                assign backend_copy_push_req_count_debug = 16'd0;
                assign backend_copy_push_fire_count_debug = 16'd0;
                assign backend_copy_fifo_push_count_debug = 16'd0;
                assign backend_copy_pack_ready_debug = 16'd0;
                assign backend_copy_post_push_debug = 16'd0;
                assign backend_read_gate_debug = 16'd0;
                assign backend_read_after_copy_count_debug = 16'd0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                assign smoke_ddr_rd_ready = 1'b0;
                assign smoke_ddr_rd_valid = 1'b0;
                assign smoke_ddr_rd_data = 8'h80;
                assign smoke_ddr_payload_present = 1'b0;
                assign smoke_ddr_payload_length = 19'd0;
                assign smoke_ddr_write_req_count_debug = 16'd0;
                assign smoke_ddr_write_count_debug = 16'd0;
                assign smoke_ddr_write_blocked_count_debug = 16'd0;
                assign smoke_ddr_write_status_debug = 16'd0;
                assign smoke_ddr_header_skip_count_debug = 16'd0;
                assign smoke_ddr_last_write_index_debug = 16'd0;
                assign smoke_ddr_last_write_addr_debug = 16'd0;
                assign smoke_ddr_last_write_lane_debug = 16'd0;
                assign smoke_ddr_last_write_data_debug = 8'd0;
                assign smoke_ddr_read_count_debug = 16'd0;
                assign smoke_ddr_last_read_index_i = 16'd0;
                assign smoke_ddr_last_read_addr_debug = 16'd0;
                assign smoke_ddr_last_read_lane_debug = 16'd0;
                assign smoke_ddr_last_read_word0_i = 16'd0;
                assign smoke_ddr_last_read_word1_i = 16'd0;
                assign smoke_ddr_last_read_data_i = 8'd0;
                assign smoke_ddr_base_addr_debug = 16'd0;
                assign smoke_ddr_probe_write_index_i = 16'd0;
                assign smoke_ddr_probe_write_word_i = 16'd0;
                assign smoke_ddr_probe_write_lane_i = 16'd0;
                assign smoke_ddr_probe_write_addr_i = 16'd0;
                assign smoke_ddr_probe_write_count_i = 16'd0;
                assign smoke_ddr_probe_write_flags_i = 16'd0;
                assign smoke_ddr_probe_write_word0_i = 16'd0;
                assign smoke_ddr_probe_write_word6_i = 16'd0;
`endif
                assign load_done_pulse = 1'b0;
                assign play_ready_pulse = 1'b0;
                assign ioctl_wait = 1'b0;
                assign vgm_load_busy = 1'b0;
                assign vgm_load_done = 1'b0;
                assign vgm_load_error = 1'b1;
                assign vgm_load_overflow = 1'b1;
                assign vgm_load_size = '0;
                assign vgm_load_magic = 32'd0;

                assign ddram_burstcnt = 8'd0;
                assign ddram_addr     = 29'd0;
                assign ddram_rd       = 1'b0;
                assign ddram_din      = 64'd0;
                assign ddram_be       = 8'd0;
                assign ddram_we       = 1'b0;
            end

            vgm_loaded_player #(
                .ADDR_WIDTH   (VGM_LOAD_ADDR_WIDTH),
                .YM2151_MODE  (YM2151_EXPERIMENTAL_MODE)
            ) loaded_player (
                .clk                   (clk),
                .reset                 (mode5_loaded_player_reset),
                .start                 (loaded_player_start_input_live),
                .load_done             (vgm_load_done),
                .load_done_pulse       (1'b0),
                .load_error            (vgm_load_error),
                .overflow_error        (vgm_load_overflow),
                .file_size             (vgm_load_size),
                .vgm_wait_tick         (vgm_wait_tick),
                .mem_rd_req            (mem_rd_req),
                .mem_rd_addr           (mem_rd_addr),
                .mem_rd_ready          (mem_rd_ready),
                .mem_rd_valid          (mem_rd_valid),
                .mem_rd_data           (mem_rd_data),
                .segapcm_copy_wr_req   (segapcm_copy_wr_req),
                .segapcm_copy_wr_ready (segapcm_copy_wr_ready),
                .segapcm_copy_wr_addr  (segapcm_copy_wr_addr),
                .segapcm_copy_wr_data  (segapcm_copy_wr_data),
                .segapcm_copy_flush_req(segapcm_copy_flush_req),
                .segapcm_copy_flush_done(segapcm_copy_flush_done),
                .segapcm_payload_tap_valid(segapcm_payload_tap_valid),
                .segapcm_payload_tap_addr(segapcm_payload_tap_addr),
                .segapcm_payload_tap_data(segapcm_payload_tap_data),
                .segapcm_payload_tap_byte_count_debug(segapcm_payload_tap_byte_count),
                .segapcm_tap_block_size_debug(segapcm_tap_block_size),
                .segapcm_tap_block_start_debug(segapcm_tap_block_start),
                .ym_cmd_ready          (ym_cmd_ready),
                .psg_cmd_ready         (psg_cmd_ready),
                .ym_cmd_valid          (ym_cmd_valid),
                .ym_cmd_port           (ym_cmd_port),
                .ym_cmd_reg            (ym_cmd_reg),
                .ym_cmd_data           (ym_cmd_data),
                .psg_cmd_valid         (psg_cmd_valid),
                .psg_cmd_data          (psg_cmd_data),
                .ym2151_cmd_ready      (ym2151_cmd_ready),
                .ym2151_cmd_valid      (ym2151_cmd_valid),
                .ym2151_cmd_reg        (ym2151_cmd_reg),
                .ym2151_cmd_data       (ym2151_cmd_data),
                .busy                  (loaded_player_busy),
                .done                  (loaded_player_done),
                .header_valid          (vgm_header_valid),
                .player_error          (vgm_player_error),
                .unsupported_opcode    (vgm_unsupported_opcode),
                .unsupported_pc        (vgm_unsupported_pc),
                .player_error_code     (vgm_player_error_code),
                .error_pc_debug        (vgm_error_pc_debug),
                .error_cmd_debug       (vgm_error_cmd_debug),
                .state_debug           (vgm_player_state_debug),
                .mem_rd_req_debug      (vgm_mem_rd_req_debug),
                .mem_rd_ready_debug    (vgm_mem_rd_ready_debug),
                .mem_rd_valid_debug    (vgm_mem_rd_valid_debug),
                .mem_rd_addr_debug     (vgm_mem_rd_addr_debug),
                .player_core_debug     (vgm_player_core_debug),
                .player_lifecycle_debug(vgm_player_lifecycle_debug),
                .last_read_byte_debug  (vgm_player_last_read_byte_debug),
                .header_magic_read_debug(vgm_header_magic_read_debug),
                .header_magic_fail_index_debug(vgm_header_magic_fail_index_debug),
                .read_request_addr_debug(vgm_read_request_addr_debug),
                .read_response_addr_debug(vgm_read_response_addr_debug),
                .read_pending_debug    (vgm_read_pending_debug),
                .read_valid_consumed_debug(vgm_read_valid_consumed_debug),
                .final_state_debug     (vgm_final_state_debug_live),
                .final_pc_debug        (vgm_final_pc_debug_live),
                .final_cmd_debug       (vgm_final_cmd_debug_live),
                .final_error_code_debug(vgm_final_error_code_debug_live),
                .final_flags_debug     (vgm_final_flags_debug_live),
                .final_reason_debug_out(vgm_final_reason_debug_live),
                .final_progress_debug  (vgm_final_progress_debug_live),
                .first_playback_cmd_after_scan_debug_out(vgm_first_playback_cmd_after_scan_debug_live),
                .first_playback_cmds_after_scan_debug(vgm_first_playback_cmds_after_scan_debug_live),
                .scan_state_debug      (vgm_scan_state_debug_live),
                .scan_pc_debug         (vgm_scan_pc_debug_live),
                .scan_last_cmd_debug   (vgm_scan_last_cmd_debug_live),
                .scan_block_type_debug (vgm_scan_block_type_debug_live),
                .scan_block_size_low_debug(vgm_scan_block_size_low_debug_live),
                .scan_remaining_low_debug(vgm_scan_remaining_low_debug_live),
                .scan_wait_debug       (vgm_scan_wait_debug_live),
                .scan_abort_reason_debug(vgm_scan_abort_reason_debug_live),
                .scan_copy_last_index_low_debug(vgm_scan_copy_last_index_low_debug_live),
                .scan_copy_req_count_debug(vgm_scan_copy_req_count_debug_live),
                .scan_copy_ready_count_debug(vgm_scan_copy_ready_count_debug_live),
                .scan_copy_tail_debug  (vgm_scan_copy_tail_debug_live),
                .scan_player_accept_count_debug(vgm_scan_player_accept_count_debug_live),
                .scan_player_remaining_debug(vgm_scan_player_remaining_debug_live),
                .scan_payload_len_low_debug(vgm_scan_payload_len_low_debug_live),
                .scan_copy_accept_fire_count_debug(vgm_scan_copy_accept_fire_count_debug_live),
                .scan_noncopy_advance_count_debug(vgm_scan_noncopy_advance_count_debug_live),
                .scan_used_noncopy_advance_during_copy_debug(vgm_scan_used_noncopy_advance_debug_live),
                .scan_raw_copy_byte_count_debug(vgm_scan_raw_copy_byte_count_debug_live),
                .scan_raw_event_debug(vgm_scan_raw_event_debug_live),
                .scan_copy_exit_debug(vgm_scan_copy_exit_debug_live),
                .scan_copy_exit_pc_debug(vgm_scan_copy_exit_pc_debug_live),
                .scan_copy_exit_count_debug(vgm_scan_copy_exit_count_debug_live),
                .scan_copy_phase_debug(vgm_scan_copy_phase_debug_live),
                .scan_copy_read_req_count_debug(vgm_scan_copy_read_req_count_debug_live),
                .scan_copy_read_accept_count_debug(vgm_scan_copy_read_accept_count_debug_live),
                .scan_copy_read_valid_count_debug(vgm_scan_copy_read_valid_count_debug_live),
                .scan_copy_mem_req_cycle_count_debug(vgm_scan_copy_mem_req_cycle_count_debug_live),
                .scan_copy_mem_req_ready_cycle_count_debug(vgm_scan_copy_mem_req_ready_cycle_count_debug_live),
                .scan_copy_request_state_debug(vgm_scan_copy_request_state_debug_live),
                .scan_copy_state_lifetime_debug(vgm_scan_copy_state_lifetime_debug_live),
                .scan_copy_clear_reason_debug(vgm_scan_copy_clear_reason_debug_live),
                .scan_copy_payload_pc_debug(vgm_scan_copy_payload_pc_debug_live),
                .scan_copy_first01_debug(vgm_scan_copy_first01_debug_live),
                .scan_copy_first23_debug(vgm_scan_copy_first23_debug_live),
                .scan_copy_first45_debug(vgm_scan_copy_first45_debug_live),
                .scan_copy_first67_debug(vgm_scan_copy_first67_debug_live),
                .scan_copy_first8_phase_debug(vgm_scan_copy_first8_phase_debug_live),
                .scan_copy_read_raw_valid_count_debug(vgm_scan_copy_read_raw_valid_count_debug_live),
                .scan_copy_read_ignored_valid_count_debug(vgm_scan_copy_read_ignored_valid_count_debug_live),
                .scan_copy_read_handshake_debug(vgm_scan_copy_read_handshake_debug_live),
                .scan_payload_o0_debug(vgm_scan_payload_o0_debug_live),
                .scan_payload_af_debug(vgm_scan_payload_af_debug_live),
                .scan_payload_vd_debug(vgm_scan_payload_vd_debug_live),
                .scan_payload_cp_debug(vgm_scan_payload_cp_debug_live),
                .scan_term_pl_debug(vgm_scan_term_pl_debug_live),
                .scan_term_rm_debug(vgm_scan_term_rm_debug_live),
                .scan_term_cc_debug(vgm_scan_term_cc_debug_live),
                .scan_term_nx_debug(vgm_scan_term_nx_debug_live),
                .scan_term_be_debug(vgm_scan_term_be_debug_live),
                .scan_sticky_guard_debug(vgm_scan_sticky_guard_debug_live),
                .scan_payload_qg_debug(vgm_scan_payload_qg_debug_live),
                .scan_payload_sf_debug(vgm_scan_payload_sf_debug_live),
                .scan_payload_continue_guard_active_debug(vgm_scan_payload_continue_guard_active_live),
                .scan_remaining_zero_before_expected_accept_debug(vgm_scan_remaining_zero_before_expected_accept_debug_live),
                .data_start_debug      (vgm_data_start_debug),
                .current_pc_debug      (vgm_current_pc_debug),
                .loop_pc_debug         (vgm_loop_pc_debug),
                .loop_valid_debug      (vgm_loop_valid_debug),
                .loop_taken_debug      (vgm_loop_taken_debug),
                .end_command_seen      (vgm_end_command_seen),
                .restarted_from_data_start(vgm_restarted_from_data_start),
                .pcm_oob               (vgm_pcm_oob),
                .pcm_oob_count         (vgm_pcm_oob_count),
                .wait_ticks_consumed_debug(vgm_wait_ticks_consumed_debug),
                .dac_stream_cmd_count  (dac_stream_cmd_count),
                .dac_stream_wait_samples_total(dac_stream_wait_samples_total),
                .dac_stream_clk_cycles_total(dac_stream_clk_cycles_total),
                .dac_stream_overhead_cycles_total(dac_stream_overhead_cycles_total),
                .max_dac_stream_cmd_cycles(max_dac_stream_cmd_cycles),
                .count_wait0_dac_stream_cmd(count_wait0_dac_stream_cmd),
                .count_wait0_overhead_nonzero(count_wait0_overhead_nonzero),
                .ym2151_write_count    (ym2151_write_count),
                .ym2151_last_reg       (ym2151_last_reg),
                .ym2151_last_data      (ym2151_last_data),
                .unsupported_command_count(ym2151_unsupported_command_count),
                .segapcm_cmd_valid     (segapcm_cmd_valid),
                .segapcm_cmd_addr      (segapcm_cmd_addr),
                .segapcm_cmd_data      (segapcm_cmd_data),
                .segapcm_write_count   (segapcm_write_count),
                .segapcm_last_addr     (segapcm_last_addr),
                .segapcm_last_data     (segapcm_last_data),
                .data_block_count      (data_block_count),
                .last_data_block_type  (last_data_block_type),
                .last_data_block_size_low(last_data_block_size_low),
                .parser_command_count_debug(parser_command_count_debug),
                .parser_data_block_count_debug(parser_data_block_count_debug),
                .parser_last_block_type_debug(parser_last_block_type_debug),
                .parser_type00_block_count_debug(parser_type00_block_count_debug),
                .parser_type80_block_count_debug(parser_type80_block_count_debug),
                .segapcm_rom_block_count(segapcm_rom_block_count),
                .segapcm_last_rom_size (segapcm_last_rom_size),
                .segapcm_last_rom_start(segapcm_last_rom_start),
                .pcm_ram_write_skip_count(pcm_ram_write_skip_count),
                .segapcm_rom_scan_busy (segapcm_rom_scan_busy),
                .segapcm_rom_scan_done (segapcm_rom_scan_done),
                .segapcm_rom_scan_overflow(segapcm_rom_scan_overflow),
                .segapcm_rom_scan_block_count(segapcm_rom_scan_block_count),
                .segapcm_rom_scan_byte_count(segapcm_rom_scan_byte_count),
                .segapcm_rom_scan_checksum32(segapcm_rom_scan_checksum32),
                .segapcm_rom_scan_total_size(segapcm_rom_scan_total_size),
                .segapcm_rom_scan_last_start(segapcm_rom_scan_last_start),
                .segapcm_rom_copy_byte_count(segapcm_rom_copy_byte_count),
                .segapcm_rom_copy_overflow(segapcm_rom_copy_overflow),
                .segapcm_rom_copy_flush_done(segapcm_rom_copy_flush_done),
                .segapcm_copy_flush_req_debug(segapcm_copy_flush_req_debug),
                .done_pc_debug         (player_done_pc_debug),
                .done_cmd_debug        (player_done_cmd_debug),
                .pc_debug              (player_pc_debug),
                .last_cmd_debug        (player_last_cmd_debug)
            );

            if (YM2151_EXPERIMENTAL_MODE) begin : ym2151_sound_enabled
`ifdef MEGAVGMDRIVE_SEGAPCM_AUDIO_STUB_BUILD
                assign ym2151_cmd_ready = 1'b1;
                assign ym2151_audio_l = 16'sd0;
                assign ym2151_audio_r = 16'sd0;
                assign ym2151_audio_sample_valid = 1'b0;
`else
                ym2151_sound_module #(
                    .CLK_SYS_HZ    (CLK_SYS_HZ),
                    .YM2151_CLK_HZ (32'd4_000_000)
                ) ym2151_sound (
                    .clk                (clk),
                    .reset              (reset | mode5_sound_core_reset),
                    .ym2151_cmd_valid   (ym2151_cmd_valid),
                    .ym2151_cmd_reg     (ym2151_cmd_reg),
                    .ym2151_cmd_data    (ym2151_cmd_data),
                    .ym2151_cmd_ready   (ym2151_cmd_ready),
                    .audio_l            (ym2151_audio_l),
                    .audio_r            (ym2151_audio_r),
                    .audio_sample_valid (ym2151_audio_sample_valid)
                );
`endif

                segapcm_sound_module #(
                    .CLK_SYS_HZ      (CLK_SYS_HZ),
                    .SEGAPCM_CLK_HZ  (32'd16_000_000)
                ) segapcm_sound (
                    .clk                            (clk),
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    .reset                          (reset),
`else
                    .reset                          (reset | mode5_sound_core_reset),
`endif
                    .segapcm_cmd_valid              (segapcm_cmd_valid),
                    .segapcm_cmd_addr               (segapcm_cmd_addr),
                    .segapcm_cmd_data               (segapcm_cmd_data),
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    .smoke_variant                  (segapcm_smoke_variant),
                    .smoke_variant_valid            (segapcm_smoke_variant_valid),
                    .smoke_source_loaded            (segapcm_smoke_source_loaded),
                    .loaded_payload_clear           (ioctl_download),
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                    .smoke_ddr_follow_mode         (segapcm_smoke_ddr_follow),
                    .smoke_ddr_follow_offset_sel   (segapcm_smoke_ddr_offset),
                    .smoke_ddr_follow_delta_sel    (segapcm_smoke_ddr_delta),
                    .smoke_ddr_follow_dest_map     (segapcm_smoke_ddr_dest_map),
                    .smoke_ddr_follow_dest_basis   (segapcm_smoke_ddr_dest_basis),
                    .smoke_ddr_follow_dest_loop_wrap(segapcm_smoke_ddr_dest_loop_wrap),
                    .smoke_c0_use_sel              (segapcm_smoke_c0_use),
                    .smoke_c0_sample_mode_sel      (segapcm_smoke_c0_sample_mode),
                    .smoke_c0_vol_map_sel          (segapcm_smoke_c0_vol_map),
                    .smoke_c0_drive_sel            (segapcm_smoke_c0_drive),
                    .smoke_playback_running        (player_busy),
                    .smoke_playback_done           (player_done),
                    .smoke_vgm_end_seen            (vgm_end_command_seen),
                    .loaded_type80_rom_size         (smoke_ddr_type80_block_size),
                    .loaded_type80_rom_dest         (smoke_ddr_type80_dest_addr),
                    .loaded_payload_wr_valid        (segapcm_payload_tap_valid),
                    .loaded_payload_wr_addr         (segapcm_payload_tap_addr),
                    .loaded_payload_wr_data         (segapcm_payload_tap_data),
                    .loaded_payload_present         (smoke_ddr_payload_present),
                    .loaded_payload_length          (segapcm_payload_tap_byte_count[18:0]),
                    .loaded_payload_block_count     (parser_type80_block_count_debug[15:0]),
                    .loaded_ddr_rd_req              (smoke_ddr_rd_req),
                    .loaded_ddr_rd_ready            (smoke_ddr_rd_ready),
                    .loaded_ddr_rd_addr             (smoke_ddr_rd_addr),
                    .loaded_ddr_rd_valid            (smoke_ddr_rd_valid),
                    .loaded_ddr_rd_data             (smoke_ddr_rd_data),
                    .loaded_ddr_payload_present     (smoke_ddr_payload_present),
                    .loaded_ddr_payload_length      (smoke_ddr_payload_length),
                    .loaded_ddr_write_req_count_debug(smoke_ddr_write_req_count_debug),
                    .loaded_ddr_write_count_debug   (smoke_ddr_write_count_debug),
                    .loaded_ddr_write_blocked_count_debug(smoke_ddr_write_blocked_count_debug),
                    .loaded_ddr_write_status_debug  (smoke_ddr_write_status_debug),
                    .loaded_ddr_header_skip_count_debug(smoke_ddr_header_skip_count_debug),
                    .loaded_ddr_last_write_index_debug(smoke_ddr_last_write_index_debug),
                    .loaded_ddr_last_write_addr_debug(smoke_ddr_last_write_addr_debug),
                    .loaded_ddr_last_write_lane_debug(smoke_ddr_last_write_lane_debug),
                    .loaded_ddr_last_write_data_debug(smoke_ddr_last_write_data_debug),
                    .loaded_ddr_read_count_debug    (smoke_ddr_read_count_debug),
                    .loaded_ddr_last_read_index_debug(smoke_ddr_last_read_index_debug),
                    .loaded_ddr_last_read_addr_debug(smoke_ddr_last_read_addr_debug),
                    .loaded_ddr_last_read_lane_debug(smoke_ddr_last_read_lane_debug),
                    .loaded_ddr_last_read_word0_debug(smoke_ddr_last_read_word0_debug),
                    .loaded_ddr_last_read_word1_debug(smoke_ddr_last_read_word1_debug),
                    .loaded_ddr_last_read_data_debug(smoke_ddr_last_read_data_debug),
                    .loaded_ddr_base_addr_debug     (smoke_ddr_base_addr_debug),
                    .loaded_ddr_probe_write_index_debug(smoke_ddr_probe_write_index_debug),
                    .loaded_ddr_probe_write_word_debug(smoke_ddr_probe_write_word_debug),
                    .loaded_ddr_probe_write_lane_debug(smoke_ddr_probe_write_lane_debug),
                    .loaded_ddr_probe_write_addr_debug(smoke_ddr_probe_write_addr_debug),
                    .loaded_ddr_probe_write_count_debug(smoke_ddr_probe_write_count_debug),
                    .loaded_ddr_probe_write_flags_debug(smoke_ddr_probe_write_flags_debug),
                    .loaded_ddr_probe_write_word0_debug(smoke_ddr_probe_write_word0_debug),
                    .loaded_ddr_probe_write_word6_debug(smoke_ddr_probe_write_word6_debug),
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST
                    .loaded_payload_wr_valid        (segapcm_payload_tap_valid),
                    .loaded_payload_wr_addr         (segapcm_payload_tap_addr),
                    .loaded_payload_wr_data         (segapcm_payload_tap_data),
                    .loaded_payload_present         (1'b0),
                    .loaded_payload_length          (segapcm_payload_tap_byte_count[18:0]),
                    .loaded_payload_block_count     (parser_type80_block_count_debug[15:0]),
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST
                    .loaded_payload_wr_valid        (segapcm_payload_tap_valid),
                    .loaded_payload_wr_addr         (segapcm_payload_tap_addr),
                    .loaded_payload_wr_data         (segapcm_payload_tap_data),
                    .loaded_payload_present         (1'b0),
                    .loaded_payload_length          (segapcm_payload_tap_byte_count[18:0]),
                    .loaded_payload_block_count     (parser_type80_block_count_debug[15:0]),
`else
                    .loaded_payload_wr_valid        (segapcm_copy_wr_req &&
                                                     segapcm_copy_wr_ready),
                    .loaded_payload_wr_addr         (segapcm_copy_wr_addr),
                    .loaded_payload_wr_data         (segapcm_copy_wr_data),
                    .loaded_payload_present         (segapcm_rom_copy_flush_done &&
                                                     (segapcm_rom_copy_byte_count != 32'd0) &&
                                                     !segapcm_rom_copy_overflow),
                    .loaded_payload_length          (segapcm_rom_copy_byte_count[18:0]),
                    .loaded_payload_block_count     (segapcm_rom_scan_block_count[15:0]),
`endif
`endif
                    .audio_l                        (segapcm_audio_l),
                    .audio_r                        (segapcm_audio_r),
                    .audio_sample_valid             (segapcm_audio_sample_valid),
                    .rom_addr_low_debug             (segapcm_core_rom_addr_low),
                    .rom_addr_raw_high_debug        (segapcm_core_rom_addr_raw_high),
                    .rom_addr_raw_low_debug         (segapcm_core_rom_addr_raw_low),
                    .rom_addr_mapped_high_debug     (segapcm_core_rom_addr_mapped_high),
                    .rom_addr_mapped_low_debug      (segapcm_core_rom_addr_mapped_low),
                    .rom_addr_min_high_debug        (segapcm_core_rom_addr_min_high),
                    .rom_addr_min_low_debug         (segapcm_core_rom_addr_min_low),
                    .rom_addr_max_high_debug        (segapcm_core_rom_addr_max_high),
                    .rom_addr_max_low_debug         (segapcm_core_rom_addr_max_low),
                    .rom_audio_active_high_debug    (segapcm_core_rom_audio_active_high),
                    .rom_audio_active_low_debug     (segapcm_core_rom_audio_active_low),
                    .rom_first_after_ctrl_high_debug(segapcm_core_rom_first_after_ctrl_high),
                    .rom_first_after_ctrl_low_debug (segapcm_core_rom_first_after_ctrl_low),
                    .rom_range_group_debug          (segapcm_core_rom_range_group),
                    .rom_range_group2_debug         (segapcm_core_rom_range_group2),
                    .rom_early_after_ctrl_high_debug(segapcm_core_rom_early_after_ctrl_high),
                    .rom_early_after_ctrl_low_debug (segapcm_core_rom_early_after_ctrl_low),
                    .rom_active_after_ctrl_high_debug(segapcm_core_rom_active_after_ctrl_high),
                    .rom_active_after_ctrl_low_debug(segapcm_core_rom_active_after_ctrl_low),
                    .rom_hit_miss_compact_debug     (segapcm_core_rom_hit_miss_compact),
                    .rom_range_hit_count_debug      (segapcm_core_rom_range_hit_count),
                    .rom_range_miss_count_debug     (segapcm_core_rom_range_miss_count),
                    .rom_activity_count_debug       (segapcm_core_rom_activity_count),
                    .rom_return_mapped_high_debug   (segapcm_core_rom_return_mapped_high),
                    .rom_return_mapped_low_debug    (segapcm_core_rom_return_mapped_low),
                    .rom_return_data_debug          (segapcm_core_rom_return_data),
                    .rom_return_last01_debug        (segapcm_core_rom_return_last01),
                    .rom_return_last23_debug        (segapcm_core_rom_return_last23),
                    .rom_return_nonzero_count_debug (segapcm_core_rom_return_nonzero_count),
                    .rom_return_change_count_debug  (segapcm_core_rom_return_change_count),
                    .rom_return_neutral_count_debug (segapcm_core_rom_return_neutral_count),
                    .rom_preload_data_debug         (segapcm_core_rom_preload_data),
                    .rom_core_ok_count_debug        (segapcm_core_rom_core_ok_count),
                    .rom_fallback_count_debug       (segapcm_core_rom_fallback_count),
                    .rom_read_valid_count_debug     (segapcm_core_rom_read_valid_count),
                    .rom_latency_debug              (segapcm_core_rom_latency_debug),
                    .rom_payload_len_low_debug      (segapcm_core_rom_payload_len_low),
                    .rom_payload_len_high_debug     (segapcm_core_rom_payload_len_high),
                    .pcm_debug_bank_channel         (segapcm_core_pcm_debug_bk),
                    .pcm_debug_cur_addr_high        (segapcm_core_pcm_debug_cuh),
                    .pcm_debug_cur_addr_low_state   (segapcm_core_pcm_debug_cul),
                    .known38686_flags_debug         (segapcm_core_known38686_flags),
                    .known38686_bank_debug          (segapcm_core_known38686_bank),
                    .known38686_channel_debug       (segapcm_core_known38686_channel),
                    .known38686_state_debug         (segapcm_core_known38686_state),
                    .known38686_cur_high_debug      (segapcm_core_known38686_cur_high),
                    .known38686_cur_low_debug       (segapcm_core_known38686_cur_low),
                    .known38686_en_addr_debug       (segapcm_core_known38686_en_addr),
                    .known38686_en_value_debug      (segapcm_core_known38686_en_value),
                    .known38686_d0_addr_debug       (segapcm_core_known38686_d0_addr),
                    .known38686_d0_value_debug      (segapcm_core_known38686_d0_value),
                    .known38686_d1_addr_debug       (segapcm_core_known38686_d1_addr),
                    .known38686_d1_value_debug      (segapcm_core_known38686_d1_value),
                    .known38686_d2_addr_debug       (segapcm_core_known38686_d2_addr),
                    .known38686_d2_value_debug      (segapcm_core_known38686_d2_value),
                    .known38686_cfg_en_debug        (segapcm_core_known38686_cfg_en),
                    .known38686_cur_23_debug        (segapcm_core_known38686_cur_23),
                    .known38686_cur_15_debug        (segapcm_core_known38686_cur_15),
                    .known38686_cur_07_debug        (segapcm_core_known38686_cur_07),
                    .c0_capture_write_count_debug   (segapcm_core_c0_capture_write_count),
                    .c0_capture_last_addr_debug     (segapcm_core_c0_capture_last_addr),
                    .c0_capture_last_data_debug     (segapcm_core_c0_capture_last_data),
                    .c0_capture_channel_activity_debug(segapcm_core_c0_capture_channel_activity),
                    .c0_capture_selected_channel_debug(segapcm_core_c0_capture_selected_channel),
                    .c0_capture_ch3_ctrl_debug      (segapcm_core_c0_capture_ch3_ctrl),
                    .c0_capture_ch3_cur_low_debug   (segapcm_core_c0_capture_ch3_cur_low),
                    .c0_capture_ch3_cur_mid_debug   (segapcm_core_c0_capture_ch3_cur_mid),
                    .c0_capture_ch3_cur_high_debug  (segapcm_core_c0_capture_ch3_cur_high),
                    .c0_capture_ch3_delta_debug     (segapcm_core_c0_capture_ch3_delta),
                    .c0_capture_ch3_vol_l_debug     (segapcm_core_c0_capture_ch3_vol_l),
                    .c0_capture_ch3_vol_r_debug     (segapcm_core_c0_capture_ch3_vol_r),
                    .c0_capture_ch3_loop_debug      (segapcm_core_c0_capture_ch3_loop),
                    .c0_capture_ch3_end_debug       (segapcm_core_c0_capture_ch3_end),
                    .jt_smoke_vol_l_debug           (segapcm_core_jt_smoke_vol_l),
                    .jt_smoke_vol_r_debug           (segapcm_core_jt_smoke_vol_r),
                    .jt_smoke_sample_byte_debug     (segapcm_core_jt_smoke_sample_byte),
                    .jt_smoke_out_l_debug           (segapcm_core_jt_smoke_out_l),
                    .jt_smoke_out_r_debug           (segapcm_core_jt_smoke_out_r),
                    .ch3_evolution_flags_debug      (segapcm_core_ch3_evolution_flags),
                    .ch3_delta_debug                (segapcm_core_ch3_delta),
                    .ch1_first_high_debug           (segapcm_core_ch1_first_high),
                    .ch1_first_low_debug            (segapcm_core_ch1_first_low),
                    .ch1_first_raw_high_debug       (segapcm_core_ch1_first_raw_high),
                    .ch1_first_raw_low_debug        (segapcm_core_ch1_first_raw_low),
                    .ch3_first_high_debug           (segapcm_core_ch3_first_high),
                    .ch3_first_low_debug            (segapcm_core_ch3_first_low),
                    .ch3_first_raw_high_debug       (segapcm_core_ch3_first_raw_high),
                    .ch3_first_raw_low_debug        (segapcm_core_ch3_first_raw_low),
                    .ch3_r0_high_debug              (segapcm_core_ch3_r0_high),
                    .ch3_r0_low_debug               (segapcm_core_ch3_r0_low),
                    .ch3_r1_high_debug              (segapcm_core_ch3_r1_high),
                    .ch3_r1_low_debug               (segapcm_core_ch3_r1_low),
                    .ch3_r2_high_debug              (segapcm_core_ch3_r2_high),
                    .ch3_r2_low_debug               (segapcm_core_ch3_r2_low),
                    .update_state_channel_debug     (segapcm_core_update_state_channel),
                    .update_before_23_debug         (segapcm_core_update_before_23),
                    .update_before_15_debug         (segapcm_core_update_before_15),
                    .update_before_07_debug         (segapcm_core_update_before_07),
                    .update_addend_debug            (segapcm_core_update_addend),
                    .update_after_23_debug          (segapcm_core_update_after_23),
                    .update_after_15_debug          (segapcm_core_update_after_15),
                    .update_after_07_debug          (segapcm_core_update_after_07),
                    .update_reason_debug            (segapcm_core_update_reason),
                    .cpu_write_count_debug          (segapcm_core_cpu_write_count),
                    .cpu_cen_write_count_debug      (segapcm_core_cpu_cen_write_count),
                    .cpu_addr_debug                 (segapcm_core_cpu_addr_debug),
                    .shadow_decode_debug            (segapcm_core_shadow_decode_debug),
                    .shadow_ch0_vol_debug           (segapcm_core_shadow_ch0_vol_debug),
                    .shadow_ch0_end_delta_debug     (segapcm_core_shadow_ch0_end_delta_debug),
                    .shadow_ch0_start_debug         (segapcm_core_shadow_ch0_start_debug),
                    .shadow_ch0_ctrl_debug          (segapcm_core_shadow_ch0_ctrl_debug),
                    .shadow_ch1_vol_debug           (segapcm_core_shadow_ch1_vol_debug),
                    .shadow_ch1_loop_debug          (segapcm_core_shadow_ch1_loop_debug),
                    .shadow_ch1_end_delta_debug     (segapcm_core_shadow_ch1_end_delta_debug),
                    .shadow_ch1_start_debug         (segapcm_core_shadow_ch1_start_debug),
                    .shadow_ch1_ctrl_debug          (segapcm_core_shadow_ch1_ctrl_debug),
                    .shadow_ch3_loop_debug          (segapcm_core_shadow_ch3_loop_debug),
                    .shadow_ch3_end_delta_debug     (segapcm_core_shadow_ch3_end_delta_debug),
                    .shadow_ch3_start_debug         (segapcm_core_shadow_ch3_start_debug),
                    .shadow_ch3_ctrl_debug          (segapcm_core_shadow_ch3_ctrl_debug),
                    .shadow_ch3_l0_debug            (segapcm_core_shadow_ch3_l0_debug),
                    .shadow_ch3_l2_debug            (segapcm_core_shadow_ch3_l2_debug),
                    .shadow_ch3_l4_debug            (segapcm_core_shadow_ch3_l4_debug),
                    .shadow_ch3_l6_debug            (segapcm_core_shadow_ch3_l6_debug),
                    .shadow_ch3_h0_debug            (segapcm_core_shadow_ch3_h0_debug),
                    .shadow_ch3_h2_debug            (segapcm_core_shadow_ch3_h2_debug),
                    .shadow_ch3_h4_debug            (segapcm_core_shadow_ch3_h4_debug),
                    .shadow_ch3_h6_debug            (segapcm_core_shadow_ch3_h6_debug),
                    .audio_nonzero_count_debug      (segapcm_core_audio_nonzero_count),
                    .audio_abs_peak_debug           (segapcm_core_audio_abs_peak),
                    .last_audio_l_debug             (segapcm_core_last_audio_l),
                    .last_audio_r_debug             (segapcm_core_last_audio_r),
                    .core_status_debug              (segapcm_core_status_debug)
                );
            end else begin : ym2151_sound_disabled
                assign ym2151_cmd_ready = 1'b1;
                assign ym2151_audio_l = 16'sd0;
                assign ym2151_audio_r = 16'sd0;
                assign ym2151_audio_sample_valid = 1'b0;
                assign segapcm_audio_l = 16'sd0;
                assign segapcm_audio_r = 16'sd0;
                assign segapcm_audio_sample_valid = 1'b0;
                assign segapcm_core_rom_addr_low = 16'd0;
                assign segapcm_core_rom_addr_raw_high = 16'd0;
                assign segapcm_core_rom_addr_raw_low = 16'd0;
                assign segapcm_core_rom_addr_mapped_high = 16'd0;
                assign segapcm_core_rom_addr_mapped_low = 16'd0;
                assign segapcm_core_rom_addr_min_high = 16'd0;
                assign segapcm_core_rom_addr_min_low = 16'd0;
                assign segapcm_core_rom_addr_max_high = 16'd0;
                assign segapcm_core_rom_addr_max_low = 16'd0;
                assign segapcm_core_rom_audio_active_high = 16'd0;
                assign segapcm_core_rom_audio_active_low = 16'd0;
                assign segapcm_core_rom_first_after_ctrl_high = 16'd0;
                assign segapcm_core_rom_first_after_ctrl_low = 16'd0;
                assign segapcm_core_rom_range_group = 16'd0;
                assign segapcm_core_rom_range_group2 = 16'd0;
                assign segapcm_core_rom_early_after_ctrl_high = 16'd0;
                assign segapcm_core_rom_early_after_ctrl_low = 16'd0;
                assign segapcm_core_rom_active_after_ctrl_high = 16'd0;
                assign segapcm_core_rom_active_after_ctrl_low = 16'd0;
                assign segapcm_core_rom_hit_miss_compact = 16'd0;
                assign segapcm_core_rom_range_hit_count = 16'd0;
                assign segapcm_core_rom_range_miss_count = 16'd0;
                assign segapcm_core_rom_activity_count = 16'd0;
                assign segapcm_core_rom_return_mapped_high = 16'd0;
                assign segapcm_core_rom_return_mapped_low = 16'd0;
                assign segapcm_core_rom_return_data = 16'd0;
                assign segapcm_core_rom_return_last01 = 16'd0;
                assign segapcm_core_rom_return_last23 = 16'd0;
                assign segapcm_core_rom_return_nonzero_count = 16'd0;
                assign segapcm_core_rom_return_change_count = 16'd0;
                assign segapcm_core_rom_return_neutral_count = 16'd0;
                assign segapcm_core_rom_preload_data = 16'd0;
                assign segapcm_core_rom_core_ok_count = 16'd0;
                assign segapcm_core_rom_fallback_count = 16'd0;
                assign segapcm_core_rom_read_valid_count = 16'd0;
                assign segapcm_core_rom_latency_debug = 16'd0;
                assign segapcm_core_rom_payload_len_low = 16'd0;
                assign segapcm_core_rom_payload_len_high = 16'd0;
                assign segapcm_core_pcm_debug_bk = 16'd0;
                assign segapcm_core_pcm_debug_cuh = 16'd0;
                assign segapcm_core_pcm_debug_cul = 16'd0;
                assign segapcm_core_known38686_flags = 16'd0;
                assign segapcm_core_known38686_bank = 16'd0;
                assign segapcm_core_known38686_channel = 16'd0;
                assign segapcm_core_known38686_state = 16'd0;
                assign segapcm_core_known38686_cur_high = 16'd0;
                assign segapcm_core_known38686_cur_low = 16'd0;
                assign segapcm_core_known38686_en_addr = 16'd0;
                assign segapcm_core_known38686_en_value = 16'd0;
                assign segapcm_core_known38686_d0_addr = 16'd0;
                assign segapcm_core_known38686_d0_value = 16'd0;
                assign segapcm_core_known38686_d1_addr = 16'd0;
                assign segapcm_core_known38686_d1_value = 16'd0;
                assign segapcm_core_known38686_d2_addr = 16'd0;
                assign segapcm_core_known38686_d2_value = 16'd0;
                assign segapcm_core_known38686_cfg_en = 16'd0;
                assign segapcm_core_known38686_cur_23 = 16'd0;
                assign segapcm_core_known38686_cur_15 = 16'd0;
                assign segapcm_core_known38686_cur_07 = 16'd0;
                assign segapcm_core_c0_capture_write_count = 16'd0;
                assign segapcm_core_c0_capture_last_addr = 16'd0;
                assign segapcm_core_c0_capture_last_data = 16'd0;
                assign segapcm_core_c0_capture_channel_activity = 16'd0;
                assign segapcm_core_c0_capture_selected_channel = 16'd0;
                assign segapcm_core_c0_capture_ch3_ctrl = 16'd0;
                assign segapcm_core_c0_capture_ch3_cur_low = 16'd0;
                assign segapcm_core_c0_capture_ch3_cur_mid = 16'd0;
                assign segapcm_core_c0_capture_ch3_cur_high = 16'd0;
                assign segapcm_core_c0_capture_ch3_delta = 16'd0;
                assign segapcm_core_c0_capture_ch3_vol_l = 16'd0;
                assign segapcm_core_c0_capture_ch3_vol_r = 16'd0;
                assign segapcm_core_c0_capture_ch3_loop = 16'd0;
                assign segapcm_core_c0_capture_ch3_end = 16'd0;
                assign segapcm_core_jt_smoke_vol_l = 16'd0;
                assign segapcm_core_jt_smoke_vol_r = 16'd0;
                assign segapcm_core_jt_smoke_sample_byte = 16'd0;
                assign segapcm_core_jt_smoke_out_l = 16'd0;
                assign segapcm_core_jt_smoke_out_r = 16'd0;
                assign segapcm_core_ch3_evolution_flags = 16'd0;
                assign segapcm_core_ch3_delta = 16'd0;
                assign segapcm_core_ch1_first_high = 16'd0;
                assign segapcm_core_ch1_first_low = 16'd0;
                assign segapcm_core_ch1_first_raw_high = 16'd0;
                assign segapcm_core_ch1_first_raw_low = 16'd0;
                assign segapcm_core_ch3_first_high = 16'd0;
                assign segapcm_core_ch3_first_low = 16'd0;
                assign segapcm_core_ch3_first_raw_high = 16'd0;
                assign segapcm_core_ch3_first_raw_low = 16'd0;
                assign segapcm_core_ch3_r0_high = 16'd0;
                assign segapcm_core_ch3_r0_low = 16'd0;
                assign segapcm_core_ch3_r1_high = 16'd0;
                assign segapcm_core_ch3_r1_low = 16'd0;
                assign segapcm_core_ch3_r2_high = 16'd0;
                assign segapcm_core_ch3_r2_low = 16'd0;
                assign segapcm_core_update_state_channel = 16'd0;
                assign segapcm_core_update_before_23 = 16'd0;
                assign segapcm_core_update_before_15 = 16'd0;
                assign segapcm_core_update_before_07 = 16'd0;
                assign segapcm_core_update_addend = 16'd0;
                assign segapcm_core_update_after_23 = 16'd0;
                assign segapcm_core_update_after_15 = 16'd0;
                assign segapcm_core_update_after_07 = 16'd0;
                assign segapcm_core_update_reason = 16'd0;
                assign segapcm_core_cpu_write_count = 16'd0;
                assign segapcm_core_cpu_cen_write_count = 16'd0;
                assign segapcm_core_cpu_addr_debug = 16'd0;
                assign segapcm_core_shadow_decode_debug = 16'd0;
                assign segapcm_core_shadow_ch0_vol_debug = 16'd0;
                assign segapcm_core_shadow_ch0_end_delta_debug = 16'd0;
                assign segapcm_core_shadow_ch0_start_debug = 16'd0;
                assign segapcm_core_shadow_ch0_ctrl_debug = 16'd0;
                assign segapcm_core_shadow_ch1_vol_debug = 16'd0;
                assign segapcm_core_shadow_ch1_loop_debug = 16'd0;
                assign segapcm_core_shadow_ch1_end_delta_debug = 16'd0;
                assign segapcm_core_shadow_ch1_start_debug = 16'd0;
                assign segapcm_core_shadow_ch1_ctrl_debug = 16'd0;
                assign segapcm_core_shadow_ch3_loop_debug = 16'd0;
                assign segapcm_core_shadow_ch3_end_delta_debug = 16'd0;
                assign segapcm_core_shadow_ch3_start_debug = 16'd0;
                assign segapcm_core_shadow_ch3_ctrl_debug = 16'd0;
                assign segapcm_core_shadow_ch3_l0_debug = 16'd0;
                assign segapcm_core_shadow_ch3_l2_debug = 16'd0;
                assign segapcm_core_shadow_ch3_l4_debug = 16'd0;
                assign segapcm_core_shadow_ch3_l6_debug = 16'd0;
                assign segapcm_core_shadow_ch3_h0_debug = 16'd0;
                assign segapcm_core_shadow_ch3_h2_debug = 16'd0;
                assign segapcm_core_shadow_ch3_h4_debug = 16'd0;
                assign segapcm_core_shadow_ch3_h6_debug = 16'd0;
                assign segapcm_core_audio_nonzero_count = 16'd0;
                assign segapcm_core_audio_abs_peak = 16'd0;
                assign segapcm_core_last_audio_l = 16'sd0;
                assign segapcm_core_last_audio_r = 16'sd0;
                assign segapcm_core_status_debug = 16'd0;
            end

`ifdef MEGAVGMDRIVE_SEGAPCM_AUDIO_STUB_BUILD
            assign ym_cmd_ready = 1'b1;
            assign psg_cmd_ready = 1'b1;
            assign md_audio_l = 16'sd0;
            assign md_audio_r = 16'sd0;
            assign md_audio_sample_valid = 1'b0;
            assign fm_adjust_clip_count_l = 16'd0;
            assign fm_adjust_clip_count_r = 16'd0;
            assign genmix_wrap_count_l = 16'd0;
            assign genmix_wrap_count_r = 16'd0;
            assign md_ym_write_requested_count = 32'd0;
            assign md_ym_write_accepted_count = 32'd0;
            assign md_ym_write_dropped_or_busy_count = 32'd0;
            assign md_ym_port0_count = 32'd0;
            assign md_ym_port1_count = 32'd0;
            assign md_last_ym_port = 1'b0;
            assign md_last_ym_addr = 8'd0;
            assign md_last_ym_data = 8'd0;
            assign jt12_cen_interval_1_count = 16'd0;
            assign jt12_cen_interval_2_count = 16'd0;
            assign jt12_cen_interval_3_count = 16'd0;
            assign jt12_cen_interval_4_count = 16'd0;
            assign jt12_cen_interval_ge5_count = 16'd0;
            assign jt12_cen_interval_min = 8'd0;
            assign jt12_cen_interval_max = 8'd0;
            assign jt12_cen_interval_last = 8'd0;
            assign fm_raw_abs_peak = 16'd0;
            assign fm_adjust_abs_peak = 16'd0;
            assign fm_lpf_abs_peak = 16'd0;
            assign genmix_abs_peak = 16'd0;
            assign md_final_audio_abs_peak = 16'd0;
`else
            md_sound_module sound (
                .clk                   (clk),
                .reset                 (reset | mode5_sound_core_reset),
                .ym_cmd_valid          (ym_cmd_valid),
                .ym_cmd_port           (ym_cmd_port),
                .ym_cmd_reg            (ym_cmd_reg),
                .ym_cmd_data           (ym_cmd_data),
                .psg_cmd_valid         (psg_cmd_valid),
                .psg_cmd_data          (psg_cmd_data),
                .ym_cmd_ready          (ym_cmd_ready),
                .psg_cmd_ready         (psg_cmd_ready),
                .audio_l               (md_audio_l),
                .audio_r               (md_audio_r),
                .audio_sample_valid    (md_audio_sample_valid),
                .audio_lpf_mode        (audio_lpf_mode),
                .audio_gain_boost      (audio_gain_boost),
                .audio_psg_level       (audio_psg_level),
                .fm_adjust_clip_count_l(fm_adjust_clip_count_l),
                .fm_adjust_clip_count_r(fm_adjust_clip_count_r),
                .genmix_wrap_count_l   (genmix_wrap_count_l),
                .genmix_wrap_count_r   (genmix_wrap_count_r),
                .ym_write_requested_count(md_ym_write_requested_count),
                .ym_write_accepted_count(md_ym_write_accepted_count),
                .ym_write_dropped_or_busy_count(md_ym_write_dropped_or_busy_count),
                .ym_port0_count        (md_ym_port0_count),
                .ym_port1_count        (md_ym_port1_count),
                .last_ym_port          (md_last_ym_port),
                .last_ym_addr          (md_last_ym_addr),
                .last_ym_data          (md_last_ym_data),
                .jt12_cen_interval_1_count(jt12_cen_interval_1_count),
                .jt12_cen_interval_2_count(jt12_cen_interval_2_count),
                .jt12_cen_interval_3_count(jt12_cen_interval_3_count),
                .jt12_cen_interval_4_count(jt12_cen_interval_4_count),
                .jt12_cen_interval_ge5_count(jt12_cen_interval_ge5_count),
                .jt12_cen_interval_min(jt12_cen_interval_min),
                .jt12_cen_interval_max(jt12_cen_interval_max),
                .jt12_cen_interval_last(jt12_cen_interval_last),
                .fm_raw_abs_peak      (fm_raw_abs_peak),
                .fm_adjust_abs_peak   (fm_adjust_abs_peak),
                .fm_lpf_abs_peak      (fm_lpf_abs_peak),
                .genmix_abs_peak      (genmix_abs_peak),
                .final_audio_abs_peak (md_final_audio_abs_peak)
            );
`endif
        end else begin : fixed_region_mode
            assign vgm_load_busy = 1'b0;
            assign vgm_load_done = 1'b0;
            assign vgm_load_error = 1'b0;
            assign vgm_load_overflow = 1'b0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
            assign smoke_ddr_payload_tap_count_debug = 16'd0;
            assign smoke_ddr_last_read_index_debug = 16'd0;
            assign smoke_ddr_last_read_word0_debug = 16'd0;
            assign smoke_ddr_last_read_word1_debug = 16'd0;
            assign smoke_ddr_probe_write_index_debug = 16'd0;
            assign smoke_ddr_probe_write_word_debug = 16'd0;
            assign smoke_ddr_probe_write_lane_debug = 16'd0;
            assign smoke_ddr_probe_write_addr_debug = 16'd0;
            assign smoke_ddr_probe_write_count_debug = 16'd0;
            assign smoke_ddr_probe_write_flags_debug = 16'd0;
            assign smoke_ddr_probe_write_word0_debug = 16'd0;
            assign smoke_ddr_probe_write_word6_debug = 16'd0;
`endif
            assign vgm_header_valid = 1'b0;
            assign vgm_player_error = 1'b0;
            assign vgm_unsupported_opcode = 8'd0;
            assign vgm_unsupported_pc = '0;
            assign vgm_player_error_code = 8'd0;
            assign vgm_error_pc_debug = '0;
            assign vgm_error_cmd_debug = 8'd0;
            assign vgm_error_session_id = 32'd0;
            assign vgm_player_state_debug = 7'd0;
            assign vgm_mem_rd_req_debug = 1'b0;
            assign vgm_mem_rd_ready_debug = 1'b0;
            assign vgm_mem_rd_valid_debug = 1'b0;
            assign vgm_mem_rd_addr_debug = '0;
            assign vgm_player_core_debug = 16'd0;
            assign vgm_player_lifecycle_debug = 16'd0;
            assign vgm_player_last_read_byte_debug = 8'd0;
            assign vgm_header_magic_read_debug = 32'd0;
            assign vgm_header_magic_fail_index_debug = 4'd0;
            assign vgm_read_request_addr_debug = '0;
            assign vgm_read_response_addr_debug = '0;
            assign vgm_read_pending_debug = 1'b0;
            assign vgm_read_valid_consumed_debug = 1'b0;
            assign vgm_final_state_debug = 7'd0;
            assign vgm_final_pc_debug = '0;
            assign vgm_final_cmd_debug = 8'd0;
            assign vgm_final_error_code_debug = 8'd0;
            assign vgm_final_flags_debug = 16'd0;
            assign vgm_final_reason_debug = 4'd0;
            assign vgm_final_progress_debug = 16'd0;
            assign vgm_first_playback_cmd_after_scan_debug = 8'd0;
            assign vgm_first_playback_cmds_after_scan_debug = 32'd0;
            assign vgm_scan_state_debug = 7'd0;
            assign vgm_scan_pc_debug = '0;
            assign vgm_scan_last_cmd_debug = 8'd0;
            assign vgm_scan_block_type_debug = 8'd0;
            assign vgm_scan_block_size_low_debug = 16'd0;
            assign vgm_scan_remaining_low_debug = 16'd0;
            assign vgm_scan_wait_debug = 16'd0;
            assign vgm_scan_abort_reason_debug = 8'd0;
            assign vgm_scan_copy_last_index_low_debug = 16'd0;
            assign vgm_scan_copy_req_count_debug = 16'd0;
            assign vgm_scan_copy_ready_count_debug = 16'd0;
            assign vgm_scan_copy_tail_debug = 16'd0;
            assign vgm_scan_player_accept_count_debug = 16'd0;
            assign vgm_scan_player_remaining_debug = 16'd0;
            assign vgm_scan_payload_len_low_debug = 16'd0;
            assign vgm_scan_remaining_zero_before_expected_accept_debug = 1'b0;
            assign vgm_scan_zero_state_debug = 16'd0;
            assign vgm_scan_zero_pc_debug = 16'd0;
            assign vgm_scan_zero_cmd_debug = 16'd0;
            assign vgm_scan_copy_accept_fire_count_debug = 16'd0;
            assign vgm_scan_noncopy_advance_count_debug = 16'd0;
            assign vgm_scan_used_noncopy_advance_debug = 1'b0;
            assign vgm_scan_raw_copy_byte_count_debug = 16'd0;
            assign vgm_scan_raw_event_debug = 16'd0;
            assign vgm_scan_copy_exit_debug = 16'd0;
            assign vgm_scan_copy_exit_pc_debug = 16'd0;
            assign vgm_scan_copy_exit_count_debug = 16'd0;
            assign vgm_scan_copy_phase_debug = 16'd0;
            assign vgm_scan_copy_read_req_count_debug = 16'd0;
            assign vgm_scan_copy_read_accept_count_debug = 16'd0;
            assign vgm_scan_copy_read_accept_internal_debug = 16'd0;
            assign vgm_scan_copy_read_valid_count_debug = 16'd0;
            assign vgm_scan_copy_mem_req_cycle_count_debug = 16'd0;
            assign vgm_scan_copy_mem_req_ready_cycle_count_debug = 16'd0;
            assign vgm_scan_copy_request_state_debug = 16'd0;
            assign vgm_scan_copy_state_lifetime_debug = 16'd0;
            assign vgm_scan_copy_clear_reason_debug = 16'd0;
            assign vgm_scan_copy_payload_pc_debug = 16'd0;
            assign vgm_scan_copy_first01_debug = 16'd0;
            assign vgm_scan_copy_first23_debug = 16'd0;
            assign vgm_scan_copy_first45_debug = 16'd0;
            assign vgm_scan_copy_first67_debug = 16'd0;
            assign vgm_scan_copy_first8_phase_debug = 16'd0;
            assign vgm_scan_copy_read_raw_valid_count_debug = 16'd0;
            assign vgm_scan_copy_read_ignored_valid_count_debug = 16'd0;
            assign vgm_scan_copy_read_handshake_debug = 16'd0;
            assign vgm_scan_payload_o0_debug = 16'd0;
            assign vgm_scan_payload_oh_debug = 16'd0;
            assign vgm_scan_payload_bd_debug = 16'd0;
            assign vgm_scan_payload_af_debug = 16'd0;
            assign vgm_scan_payload_ah_debug = 16'd0;
            assign vgm_scan_payload_oh2_debug = 16'd0;
            assign vgm_scan_payload_as_debug = 16'd0;
            assign vgm_scan_payload_vd_debug = 16'd0;
            assign vgm_scan_payload_vh_debug = 16'd0;
            assign vgm_scan_payload_vs_debug = 16'd0;
            assign vgm_scan_payload_cp_debug = 16'd0;
            assign vgm_scan_payload_ch_debug = 16'd0;
            assign vgm_scan_payload_cs_debug = 16'd0;
            assign vgm_scan_raw_player_accept_count_debug = 16'd0;
            assign vgm_scan_raw_copy_accept_count_debug = 16'd0;
            assign vgm_scan_raw_read_accept_count_debug = 16'd0;
            assign vgm_scan_raw_read_valid_count_debug = 16'd0;
            assign vgm_scan_max_player_accept_count_debug = 16'd0;
            assign vgm_scan_max_copy_accept_count_debug = 16'd0;
            assign vgm_scan_max_read_accept_count_debug = 16'd0;
            assign vgm_scan_max_read_valid_count_debug = 16'd0;
            assign vgm_scan_counter_latch_accept_debug = 16'd0;
            assign vgm_scan_counter_latch_read_debug = 16'd0;
            assign vgm_scan_counter_anomaly_debug = 16'd0;
            assign vgm_scan_counter_reset_source_debug = 16'd0;
            assign vgm_scan_stop_source_debug = 16'd0;
            assign vgm_scan_term_pl_debug = 16'd0;
            assign vgm_scan_term_rm_debug = 16'd0;
            assign vgm_scan_term_cc_debug = 16'd0;
            assign vgm_scan_term_nx_debug = 16'd0;
            assign vgm_scan_term_be_debug = 16'd0;
            assign vgm_scan_guard_debug = 16'd0;
            assign vgm_scan_sticky_guard_debug = 16'd0;
            assign vgm_scan_payload_qg_debug = 16'd0;
            assign vgm_scan_payload_sf_debug = 16'd0;
            assign mode5_backend_copy_accept_count_debug = 16'd0;
            assign mode5_backend_copy_write_count_debug = 16'd0;
            assign mode5_backend_copy_fifo_debug = 16'd0;
            assign mode5_backend_copy_ready_debug = 16'd0;
            assign mode5_backend_copy_write_req_debug = 16'd0;
            assign mode5_backend_copy_word_debug = 16'd0;
            assign mode5_backend_copy_flush_debug = 16'd0;
            assign mode5_backend_copy_full_detect_count_debug = 16'd0;
            assign mode5_backend_copy_push_req_count_debug = 16'd0;
            assign mode5_backend_copy_push_fire_count_debug = 16'd0;
            assign mode5_backend_copy_fifo_push_count_debug = 16'd0;
            assign mode5_backend_copy_pack_ready_debug = 16'd0;
            assign mode5_backend_copy_post_push_debug = 16'd0;
            assign mode5_backend_read_gate_debug = 16'd0;
            assign mode5_backend_read_after_copy_count_debug = 16'd0;
            assign mode5_read_mux_debug = 16'd0;
            assign mode5_read_ready_compare_debug = 16'd0;
            assign mode5_read_ready_blocker_debug = 16'd0;
            assign mode5_copy_mismatch_debug = 16'd0;
            assign mode5_copy_max_ready_count_debug = 16'd0;
            assign mode5_copy_min_remaining_debug = 16'd0;
            assign mode5_restart_after_load_count_debug = 16'd0;
            assign mode5_scan_start_count_debug = 16'd0;
            assign mode5_direct_start_debug = 16'd0;
            assign mode5_top_stop_snapshot_debug = 16'd0;
            assign vgm_load_size = '0;
            assign vgm_load_magic = 32'd0;
            assign vgm_data_start_debug = '0;
            assign vgm_current_pc_debug = '0;
            assign vgm_loop_pc_debug = '0;
            assign vgm_loop_valid_debug = 1'b0;
            assign vgm_loop_taken_debug = 1'b0;
            assign vgm_end_command_seen = 1'b0;
            assign vgm_restarted_from_data_start = 1'b0;
            assign vgm_pcm_oob = 1'b0;
            assign vgm_pcm_oob_count = 32'd0;
            assign vgm_wait_ticks_consumed_debug = 32'd0;
            assign dac_stream_cmd_count = 32'd0;
            assign dac_stream_wait_samples_total = 32'd0;
            assign dac_stream_clk_cycles_total = 32'd0;
            assign dac_stream_overhead_cycles_total = 32'd0;
            assign max_dac_stream_cmd_cycles = 32'd0;
            assign count_wait0_dac_stream_cmd = 32'd0;
            assign count_wait0_overhead_nonzero = 32'd0;
            assign segapcm_write_count = 32'd0;
            assign segapcm_last_addr = 16'd0;
            assign segapcm_last_data = 8'd0;
            assign segapcm_core_rom_addr_low = 16'd0;
            assign segapcm_core_rom_addr_raw_high = 16'd0;
            assign segapcm_core_rom_addr_raw_low = 16'd0;
            assign segapcm_core_rom_addr_mapped_high = 16'd0;
            assign segapcm_core_rom_addr_mapped_low = 16'd0;
            assign segapcm_core_rom_addr_min_high = 16'd0;
            assign segapcm_core_rom_addr_min_low = 16'd0;
            assign segapcm_core_rom_addr_max_high = 16'd0;
            assign segapcm_core_rom_addr_max_low = 16'd0;
            assign segapcm_core_rom_audio_active_high = 16'd0;
            assign segapcm_core_rom_audio_active_low = 16'd0;
            assign segapcm_core_rom_first_after_ctrl_high = 16'd0;
            assign segapcm_core_rom_first_after_ctrl_low = 16'd0;
            assign segapcm_core_rom_range_group = 16'd0;
            assign segapcm_core_rom_range_group2 = 16'd0;
            assign segapcm_core_rom_early_after_ctrl_high = 16'd0;
            assign segapcm_core_rom_early_after_ctrl_low = 16'd0;
            assign segapcm_core_rom_active_after_ctrl_high = 16'd0;
            assign segapcm_core_rom_active_after_ctrl_low = 16'd0;
            assign segapcm_core_rom_hit_miss_compact = 16'd0;
            assign segapcm_core_rom_range_hit_count = 16'd0;
            assign segapcm_core_rom_range_miss_count = 16'd0;
            assign segapcm_core_rom_activity_count = 16'd0;
            assign segapcm_core_rom_return_mapped_high = 16'd0;
            assign segapcm_core_rom_return_mapped_low = 16'd0;
            assign segapcm_core_rom_return_data = 16'd0;
            assign segapcm_core_rom_return_last01 = 16'd0;
            assign segapcm_core_rom_return_last23 = 16'd0;
            assign segapcm_core_rom_return_nonzero_count = 16'd0;
            assign segapcm_core_rom_return_change_count = 16'd0;
            assign segapcm_core_rom_return_neutral_count = 16'd0;
            assign segapcm_core_rom_preload_data = 16'd0;
            assign segapcm_core_rom_core_ok_count = 16'd0;
            assign segapcm_core_rom_fallback_count = 16'd0;
            assign segapcm_core_rom_read_valid_count = 16'd0;
            assign segapcm_core_rom_latency_debug = 16'd0;
            assign segapcm_core_rom_payload_len_low = 16'd0;
            assign segapcm_core_rom_payload_len_high = 16'd0;
            assign segapcm_core_pcm_debug_bk = 16'd0;
            assign segapcm_core_pcm_debug_cuh = 16'd0;
            assign segapcm_core_pcm_debug_cul = 16'd0;
            assign segapcm_core_known38686_flags = 16'd0;
            assign segapcm_core_known38686_bank = 16'd0;
            assign segapcm_core_known38686_channel = 16'd0;
            assign segapcm_core_known38686_state = 16'd0;
            assign segapcm_core_known38686_cur_high = 16'd0;
            assign segapcm_core_known38686_cur_low = 16'd0;
            assign segapcm_core_known38686_en_addr = 16'd0;
            assign segapcm_core_known38686_en_value = 16'd0;
            assign segapcm_core_known38686_d0_addr = 16'd0;
            assign segapcm_core_known38686_d0_value = 16'd0;
            assign segapcm_core_known38686_d1_addr = 16'd0;
            assign segapcm_core_known38686_d1_value = 16'd0;
            assign segapcm_core_known38686_d2_addr = 16'd0;
            assign segapcm_core_known38686_d2_value = 16'd0;
            assign segapcm_core_known38686_cfg_en = 16'd0;
            assign segapcm_core_known38686_cur_23 = 16'd0;
            assign segapcm_core_known38686_cur_15 = 16'd0;
            assign segapcm_core_known38686_cur_07 = 16'd0;
            assign segapcm_core_c0_capture_write_count = 16'd0;
            assign segapcm_core_c0_capture_last_addr = 16'd0;
            assign segapcm_core_c0_capture_last_data = 16'd0;
            assign segapcm_core_c0_capture_channel_activity = 16'd0;
            assign segapcm_core_c0_capture_selected_channel = 16'd0;
            assign segapcm_core_c0_capture_ch3_ctrl = 16'd0;
            assign segapcm_core_c0_capture_ch3_cur_low = 16'd0;
            assign segapcm_core_c0_capture_ch3_cur_mid = 16'd0;
            assign segapcm_core_c0_capture_ch3_cur_high = 16'd0;
            assign segapcm_core_c0_capture_ch3_delta = 16'd0;
            assign segapcm_core_c0_capture_ch3_vol_l = 16'd0;
            assign segapcm_core_c0_capture_ch3_vol_r = 16'd0;
            assign segapcm_core_c0_capture_ch3_loop = 16'd0;
            assign segapcm_core_c0_capture_ch3_end = 16'd0;
            assign segapcm_core_jt_smoke_vol_l = 16'd0;
            assign segapcm_core_jt_smoke_vol_r = 16'd0;
            assign segapcm_core_jt_smoke_sample_byte = 16'd0;
            assign segapcm_core_jt_smoke_out_l = 16'd0;
            assign segapcm_core_jt_smoke_out_r = 16'd0;
            assign segapcm_core_ch3_evolution_flags = 16'd0;
            assign segapcm_core_ch3_delta = 16'd0;
            assign segapcm_core_ch1_first_high = 16'd0;
            assign segapcm_core_ch1_first_low = 16'd0;
            assign segapcm_core_ch1_first_raw_high = 16'd0;
            assign segapcm_core_ch1_first_raw_low = 16'd0;
            assign segapcm_core_ch3_first_high = 16'd0;
            assign segapcm_core_ch3_first_low = 16'd0;
            assign segapcm_core_ch3_first_raw_high = 16'd0;
            assign segapcm_core_ch3_first_raw_low = 16'd0;
            assign segapcm_core_ch3_r0_high = 16'd0;
            assign segapcm_core_ch3_r0_low = 16'd0;
            assign segapcm_core_ch3_r1_high = 16'd0;
            assign segapcm_core_ch3_r1_low = 16'd0;
            assign segapcm_core_ch3_r2_high = 16'd0;
            assign segapcm_core_ch3_r2_low = 16'd0;
            assign segapcm_core_update_state_channel = 16'd0;
            assign segapcm_core_update_before_23 = 16'd0;
            assign segapcm_core_update_before_15 = 16'd0;
            assign segapcm_core_update_before_07 = 16'd0;
            assign segapcm_core_update_addend = 16'd0;
            assign segapcm_core_update_after_23 = 16'd0;
            assign segapcm_core_update_after_15 = 16'd0;
            assign segapcm_core_update_after_07 = 16'd0;
            assign segapcm_core_update_reason = 16'd0;
            assign segapcm_core_cpu_write_count = 16'd0;
            assign segapcm_core_cpu_cen_write_count = 16'd0;
            assign segapcm_core_cpu_addr_debug = 16'd0;
            assign segapcm_core_shadow_decode_debug = 16'd0;
            assign segapcm_core_shadow_ch0_vol_debug = 16'd0;
            assign segapcm_core_shadow_ch0_end_delta_debug = 16'd0;
            assign segapcm_core_shadow_ch0_start_debug = 16'd0;
            assign segapcm_core_shadow_ch0_ctrl_debug = 16'd0;
            assign segapcm_core_shadow_ch1_vol_debug = 16'd0;
            assign segapcm_core_shadow_ch1_loop_debug = 16'd0;
            assign segapcm_core_shadow_ch1_end_delta_debug = 16'd0;
            assign segapcm_core_shadow_ch1_start_debug = 16'd0;
            assign segapcm_core_shadow_ch1_ctrl_debug = 16'd0;
            assign segapcm_core_shadow_ch3_loop_debug = 16'd0;
            assign segapcm_core_shadow_ch3_end_delta_debug = 16'd0;
            assign segapcm_core_shadow_ch3_start_debug = 16'd0;
            assign segapcm_core_shadow_ch3_ctrl_debug = 16'd0;
            assign segapcm_core_shadow_ch3_l0_debug = 16'd0;
            assign segapcm_core_shadow_ch3_l2_debug = 16'd0;
            assign segapcm_core_shadow_ch3_l4_debug = 16'd0;
            assign segapcm_core_shadow_ch3_l6_debug = 16'd0;
            assign segapcm_core_shadow_ch3_h0_debug = 16'd0;
            assign segapcm_core_shadow_ch3_h2_debug = 16'd0;
            assign segapcm_core_shadow_ch3_h4_debug = 16'd0;
            assign segapcm_core_shadow_ch3_h6_debug = 16'd0;
            assign segapcm_core_audio_nonzero_count = 16'd0;
            assign segapcm_core_audio_abs_peak = 16'd0;
            assign segapcm_core_last_audio_l = 16'sd0;
            assign segapcm_core_last_audio_r = 16'sd0;
            assign segapcm_core_status_debug = 16'd0;
            assign data_block_count = 32'd0;
            assign last_data_block_type = 8'd0;
            assign last_data_block_size_low = 16'd0;
            assign parser_command_count_debug = 32'd0;
            assign parser_data_block_count_debug = 32'd0;
            assign parser_last_block_type_debug = 8'd0;
            assign parser_type00_block_count_debug = 32'd0;
            assign parser_type80_block_count_debug = 32'd0;
            assign segapcm_rom_block_count = 32'd0;
            assign segapcm_last_rom_size = 32'd0;
            assign segapcm_last_rom_start = 32'd0;
            assign pcm_ram_write_skip_count = 32'd0;
            assign segapcm_rom_scan_busy = 1'b0;
            assign segapcm_rom_scan_done = 1'b0;
            assign segapcm_rom_scan_overflow = 1'b0;
            assign segapcm_rom_scan_block_count = 32'd0;
            assign segapcm_rom_scan_byte_count = 32'd0;
            assign segapcm_rom_scan_checksum32 = 32'd0;
            assign segapcm_rom_scan_total_size = 32'd0;
            assign segapcm_rom_scan_last_start = 32'd0;
            assign segapcm_rom_copy_byte_count = 32'd0;
            assign segapcm_rom_copy_overflow = 1'b0;
            assign segapcm_rom_copy_flush_done = 1'b0;
            assign segapcm_copy_flush_req_debug = 1'b0;
            assign mode5_sound_reset_active = 1'b0;
            assign mode5_player_start_pulse_debug = 1'b0;
            assign mode5_start_hold_debug = 16'd0;
            assign mode5_load_begin_count = 32'd0;
            assign mode5_load_done_edge_count = 32'd0;
            assign mode5_sound_reset_start_count = 32'd0;
            assign mode5_player_start_count = 32'd0;
            assign mode5_player_reset_count = 32'd0;
            assign mode5_playback_session_id = 32'd0;
            assign mode5_duplicate_start_blocked_count = 32'd0;
            assign mode5_player_end_count = 32'd0;
            assign mode5_repeat_restart_count = 32'd0;
            assign mode5_done_armed_debug = 1'b0;
            assign mode5_repeat_session_id = 32'd0;
            assign mode5_done_session_id = 32'd0;
            assign mode5_cycles_since_start = 32'd0;
            assign mode5_done_pc_debug = '0;
            assign mode5_done_cmd_debug = 8'd0;
            assign audio_runtime_open = audio_gate_open;
            assign ioctl_wait = 1'b0;

            md_sound_fixed_region_test #(
                .REGION_MODE (REGION_MODE)
            ) fixed_region (
                .clk                   (clk),
                .reset                 (reset),
                .player_reset          (player_reset_active),
                .start                 (start_pulse),
                .vgm_wait_tick         (vgm_wait_tick),
                .audio_l               (raw_audio_l),
                .audio_r               (raw_audio_r),
                .audio_sample_valid    (raw_audio_sample_valid),
                .audio_lpf_mode        (audio_lpf_mode),
                .audio_gain_boost      (audio_gain_boost),
                .audio_psg_level       (audio_psg_level),
                .player_busy           (player_busy),
                .player_done           (player_done),
                .player_pc_debug       (player_pc_debug),
                .player_last_cmd_debug (player_last_cmd_debug),
                .fm_adjust_clip_count_l(fm_adjust_clip_count_l),
                .fm_adjust_clip_count_r(fm_adjust_clip_count_r),
                .genmix_wrap_count_l   (genmix_wrap_count_l),
                .genmix_wrap_count_r   (genmix_wrap_count_r),
                .ym_write_requested_count(ym_write_requested_count),
                .ym_write_accepted_count(ym_write_accepted_count),
                .ym_write_dropped_or_busy_count(ym_write_dropped_or_busy_count),
                .ym_port0_count        (ym_port0_count),
                .ym_port1_count        (ym_port1_count),
                .last_ym_port          (last_ym_port),
                .last_ym_addr          (last_ym_addr),
                .last_ym_data          (last_ym_data),
                .jt12_cen_interval_1_count(jt12_cen_interval_1_count),
                .jt12_cen_interval_2_count(jt12_cen_interval_2_count),
                .jt12_cen_interval_3_count(jt12_cen_interval_3_count),
                .jt12_cen_interval_4_count(jt12_cen_interval_4_count),
                .jt12_cen_interval_ge5_count(jt12_cen_interval_ge5_count),
                .jt12_cen_interval_min(jt12_cen_interval_min),
                .jt12_cen_interval_max(jt12_cen_interval_max),
                .jt12_cen_interval_last(jt12_cen_interval_last),
                .fm_raw_abs_peak      (fm_raw_abs_peak),
                .fm_adjust_abs_peak   (fm_adjust_abs_peak),
                .fm_lpf_abs_peak      (fm_lpf_abs_peak),
                .genmix_abs_peak      (genmix_abs_peak),
                .final_audio_abs_peak (md_final_audio_abs_peak)
            );
        end
    endgenerate

endmodule
