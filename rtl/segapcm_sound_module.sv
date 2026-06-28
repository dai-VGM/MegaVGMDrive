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
    wire [15:0] core_dbg_smoke_cur_zero_event;
    wire [15:0] core_dbg_smoke_cur_seed_ref;
    wire [15:0] core_dbg_smoke_cur_state;
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
    wire [7:0] smoke_delta = smoke_ddr_follow_delta_i;
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
    wire [15:0] smoke_ap_debug =
        {1'b0, smoke_vol_l, 1'b0, smoke_vol_r};
    logic [18:0] smoke_payload_addr_i;
    logic [2:0] smoke_payload_div_count_i;
    logic [2:0] smoke_variant_d_i;
    logic smoke_source_loaded_d_i;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    localparam logic [18:0] SMOKE_LOADED_DDR_BYTES_19 = 19'h01000;
    localparam logic [15:0] SMOKE_DDR_READ_DIV_LAST = 16'd0;
    wire smoke_loaded_payload_present_i = loaded_ddr_payload_present;
    wire [18:0] smoke_loaded_payload_length_i = loaded_ddr_payload_length;
    logic [7:0] smoke_ddr_audio_byte_hold_i;
    logic [15:0] smoke_ddr_audio_index_hold_i;
    logic smoke_ddr_audio_valid_seen_i;
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
    logic [11:0] smoke_ddr_follow_offset_i;
    wire [11:0] smoke_ddr_follow_mapped_next =
        core_rom_addr[11:0] + smoke_ddr_follow_offset_i;
    wire [18:0] smoke_ddr_follow_read_index =
        {7'd0, smoke_ddr_follow_mapped_next};
    wire [15:0] smoke_ddr_follow_word_next =
        loaded_ddr_base_addr_debug + {7'd0, smoke_ddr_follow_mapped_next[11:3]};
    wire [15:0] smoke_ddr_follow_lane_next =
        {13'd0, smoke_ddr_follow_mapped_next[2:0]};
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
        (loaded_ddr_payload_length >= SMOKE_LOADED_DDR_BYTES_19);
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
    logic [7:0] mapped_cpu_addr;
    logic [7:0] latched_cpu_addr;
    logic [7:0] latched_cpu_data;
    logic [15:0] latched_raw_addr;
    logic cpu_write_pending;
    logic cpu_write_pulse;
    logic core_cpu_cs;
    logic [15:0] core_write_count_i;
    logic [15:0] core_cen_write_count_i;
    logic core_cpu_cs_d;
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
    assign core_cpu_cs = 1'b0;
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

    assign core_rom_ok =
        (ROM_OK_LATENCY_MODE == 1) ? core_rom_cs_d :
        (ROM_OK_LATENCY_MODE == 2) ? core_rom_cs_d2 :
        preload_rom_ok;
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
        smoke_effective_loaded_source ?
        smoke_loaded_payload_data_i : selected_preload_rom_data;
`else
    assign selected_rom_data_before_fallback = selected_preload_rom_data;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
    assign preload_rom_data_valid =
        selected_preload_addr_valid && smoke_effective_addr_in_range;
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
    assign rom_addr_raw_high_debug = {15'd0, smoke_source_loaded};
    assign rom_addr_raw_low_debug = {15'd0, smoke_loaded_payload_present_i};
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
    assign rom_return_last23_debug = loaded_ddr_base_addr_debug;
`else
    assign rom_return_last23_debug = selected_mapped_rom_addr[15:0];
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign rom_return_nonzero_count_debug = loaded_ddr_write_req_count_debug;
    assign rom_return_change_count_debug = smoke_ddr_read_req_count_i;
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
    assign rom_core_ok_count_debug = smoke_ddr_read_valid_count_i;
`else
    assign rom_core_ok_count_debug = {15'd0, smoke_effective_addr_in_range};
`endif
`else
    assign rom_core_ok_count_debug = {15'd0, selected_preload_addr_in_range};
`endif
    assign rom_fallback_count_debug = {15'd0, preload_rom_data_valid};
    assign rom_read_valid_count_debug = {15'd0, fallback_used_this_cycle};
    assign rom_latency_debug = {
        8'hF0,
        2'd0,
        fallback_used_this_cycle,
        preload_rom_data_valid,
        selected_preload_addr_in_range,
        selected_preload_addr_valid,
        core_rom_ok,
        core_rom_cs
    };
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign rom_payload_len_low_debug = loaded_payload_length[15:0];
    assign rom_payload_len_high_debug =
        {13'd0, loaded_payload_length[18:16]};
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
    assign known38686_flags_debug = smoke_ddr_follow_core_addr_low_i;
    assign known38686_bank_debug = smoke_ddr_follow_word_i;
    assign known38686_channel_debug = smoke_ddr_read_nonzero_count_i;
    assign known38686_state_debug = smoke_ddr_follow_flags_i;
    assign known38686_cur_high_debug = smoke_ddr_audio_index_hold_i;
    assign known38686_cur_low_debug = loaded_ddr_last_write_lane_debug;
    assign known38686_en_addr_debug = smoke_ddr_follow_lane_i;
    assign known38686_en_value_debug = core_dbg_smoke_cur_initialized;
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
    assign known38686_d0_addr_debug = smoke_ddr_follow_mapped_index_i;
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
    assign known38686_d0_value_debug =
        smoke_ddr_follow_prev_addr_low_i;
`else
    assign known38686_d0_value_debug = smoke_ap_debug;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign known38686_d1_addr_debug =
        smoke_ddr_follow_cs_count_i;
`else
    assign known38686_d1_addr_debug = 16'h0030;
`endif
`else
    assign known38686_d0_value_debug = active_req_amp_pan_debug_i;
    assign known38686_d1_addr_debug = active_req_cfg_debug_i;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign known38686_d1_value_debug = loaded_ddr_write_count_debug;
    assign known38686_d2_value_debug =
        loaded_ddr_last_write_index_debug;
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
    assign known38686_d2_addr_debug =
        smoke_ddr_follow_ok_count_i;
`else
    assign known38686_d2_addr_debug = active_req_page_debug_i;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign known38686_cfg_en_debug = smoke_ddr_follow_request_count_i;
`else
    assign known38686_cfg_en_debug = 16'h0030;
`endif
`else
    assign known38686_cfg_en_debug = active_req_cfg_debug_i;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign known38686_cur_23_debug = smoke_ddr_scan_last_nonzero_index_i;
    assign known38686_cur_15_debug = {8'd0, smoke_ddr_audio_byte_hold_i};
    assign known38686_cur_07_debug = smoke_ddr_follow_addr_change_count_i;
`else
    assign known38686_cur_23_debug = {8'd0, core_dbg_cur_addr_high[15:8]};
    assign known38686_cur_15_debug = {8'd0, core_dbg_cur_addr_high[7:0]};
    assign known38686_cur_07_debug = {8'd0, core_dbg_cur_addr_low_state[15:8]};
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign ch3_evolution_flags_debug =
        smoke_ddr_audio_update_count_i;
    assign ch3_delta_debug = {8'd0, smoke_ddr_audio_byte_hold_i};
`else
    assign ch3_evolution_flags_debug = core_dbg_ch3_evolution_flags;
    assign ch3_delta_debug = core_dbg_ch3_delta;
`endif
    assign ch1_first_high_debug = core_dbg_ch1_first_high;
    assign ch1_first_low_debug = core_dbg_ch1_first_low;
    assign ch1_first_raw_high_debug = core_dbg_ch1_first_raw_high;
    assign ch1_first_raw_low_debug = core_dbg_ch1_first_raw_low;
    assign ch3_first_high_debug = core_dbg_ch3_first_high;
    assign ch3_first_low_debug = core_dbg_ch3_first_low;
    assign ch3_first_raw_high_debug = core_dbg_ch3_first_raw_high;
    assign ch3_first_raw_low_debug = core_dbg_ch3_first_raw_low;
    assign ch3_r0_high_debug = core_dbg_ch3_r0_high;
    assign ch3_r0_low_debug = core_dbg_ch3_r0_low;
    assign ch3_r1_high_debug = core_dbg_ch3_r1_high;
    assign ch3_r1_low_debug = core_dbg_ch3_r1_low;
    assign ch3_r2_high_debug = core_dbg_ch3_r2_high;
    assign ch3_r2_low_debug = core_dbg_ch3_r2_low;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    assign update_state_channel_debug = core_dbg_smoke_cur_state;
    assign update_before_23_debug = core_dbg_smoke_cur_seed_event;
    assign update_before_15_debug = core_dbg_smoke_cur_seed_ref;
    assign update_before_07_debug = core_dbg_smoke_cur_live_low;
    assign update_addend_debug = {8'd0, smoke_delta};
    assign update_after_23_debug = core_dbg_smoke_cur_live_high;
    assign update_after_15_debug = core_dbg_smoke_cur_zero_event;
    assign update_after_07_debug = {4'd0, smoke_ddr_follow_offset_i};
    assign update_reason_debug = 16'hDD20;
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
    assign shadow_decode_debug = shadow_decode_i;
    assign shadow_ch0_vol_debug = {shadow_ram[8'h02], shadow_ram[8'h03]};
    assign shadow_ch0_end_delta_debug = {shadow_ram[8'h06], shadow_ram[8'h07]};
    assign shadow_ch0_start_debug = {shadow_ram[8'h84], shadow_ram[8'h85]};
    assign shadow_ch0_ctrl_debug = {shadow_ram[8'h86], shadow_ram[8'h87]};
    assign shadow_ch1_vol_debug = {shadow_ram[8'h0a], shadow_ram[8'h0b]};
    assign shadow_ch1_loop_debug = {shadow_ram[8'h0c], shadow_ram[8'h0d]};
    assign shadow_ch1_end_delta_debug = {shadow_ram[8'h0e], shadow_ram[8'h0f]};
    assign shadow_ch1_start_debug = {shadow_ram[8'h8c], shadow_ram[8'h8d]};
    assign shadow_ch1_ctrl_debug = {shadow_ram[8'h8e], shadow_ram[8'h8f]};
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
            shadow_decode_i <= 16'd0;
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
            end
            if (core_cpu_cs && segapcm_cen) begin
                if (core_cen_write_count_i != 16'hffff) begin
                    core_cen_write_count_i <= core_cen_write_count_i + 16'd1;
                end
            end
            if (rom_request_event) begin
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
            end
            if (rom_return_event) begin
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
            end
            if (core_sample) begin
                logic [15:0] abs_l;
                logic [15:0] abs_r;
                logic [15:0] abs_now;

                last_audio_l_i <= core_snd_left;
                last_audio_r_i <= core_snd_right;
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
        end else begin
            smoke_ddr_follow_mode_d_i <= smoke_ddr_follow_mode;
            smoke_ddr_follow_flags_i <= {
                8'hC0,
                1'b0,
                smoke_ddr_follow_mode,
                smoke_ddr_audio_active,
                loaded_ddr_rd_req,
                loaded_ddr_rd_ready,
                loaded_ddr_rd_valid,
                core_rom_cs,
                core_rom_ok
            };
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
            end else if (!smoke_ddr_audio_active) begin
                loaded_ddr_rd_req <= 1'b0;
                smoke_ddr_read_div_i <= 16'd0;
            end else if (smoke_ddr_follow_mode_d_i != smoke_ddr_follow_mode) begin
                loaded_ddr_rd_req <= 1'b0;
                smoke_ddr_read_div_i <= 16'd0;
                smoke_ddr_read_index_i <= 19'd0;
                smoke_ddr_audio_byte_hold_i <= 8'h80;
                smoke_ddr_audio_index_hold_i <= 16'd0;
                smoke_ddr_audio_valid_seen_i <= 1'b0;
                smoke_ddr_follow_prev_addr_low_i <=
                    smoke_ddr_follow_core_addr_low_i;
            end else if (loaded_ddr_rd_req) begin
                if (loaded_ddr_rd_ready) begin
                    loaded_ddr_rd_req <= 1'b0;
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
            end else if (smoke_ddr_follow_mode) begin
                smoke_ddr_read_div_i <= 16'd0;
                if (rom_request_event) begin
                    loaded_ddr_rd_req <= 1'b1;
                    loaded_ddr_rd_addr <= smoke_ddr_follow_read_index;
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
                        {4'd0, smoke_ddr_follow_mapped_next};
                    smoke_ddr_follow_word_i <= smoke_ddr_follow_word_next;
                    smoke_ddr_follow_lane_i <= smoke_ddr_follow_lane_next;
                    if (smoke_ddr_follow_request_count_i != 16'hffff) begin
                        smoke_ddr_follow_request_count_i <=
                            smoke_ddr_follow_request_count_i + 16'd1;
                    end
                    if (smoke_ddr_read_req_count_i != 16'hffff) begin
                        smoke_ddr_read_req_count_i <=
                            smoke_ddr_read_req_count_i + 16'd1;
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
                // Keep the smoke audio feed from collapsing back to zero
                // between sparse useful DDR bytes; RD still shows raw readback.
                if ((loaded_ddr_rd_data != 8'd0) ||
                    !smoke_ddr_audio_valid_seen_i) begin
                    smoke_ddr_audio_byte_hold_i <= loaded_ddr_rd_data;
                    smoke_ddr_audio_index_hold_i <=
                        loaded_ddr_last_read_index_debug;
                end
                smoke_ddr_audio_valid_seen_i <= 1'b1;
                smoke_ddr_read_valid_seen_i <= 1'b1;
                if (smoke_ddr_audio_update_count_i != 16'hffff) begin
                    smoke_ddr_audio_update_count_i <=
                        smoke_ddr_audio_update_count_i + 16'd1;
                end
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
        .smoke_cur_initialized_debug(core_dbg_smoke_cur_initialized),
        .smoke_cur_seed_event_debug(core_dbg_smoke_cur_seed_event),
        .smoke_cur_live_low_debug(core_dbg_smoke_cur_live_low),
        .smoke_cur_live_high_debug(core_dbg_smoke_cur_live_high),
        .smoke_cur_zero_event_debug(core_dbg_smoke_cur_zero_event),
        .smoke_cur_seed_ref_debug(core_dbg_smoke_cur_seed_ref),
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
        .dbg_update_reason     (core_dbg_update_reason)
    );

endmodule
