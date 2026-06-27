// Minimal VGM player for bytes loaded into vgm_file_loader BRAM.
//
// First pass scope:
//   - uncompressed VGM only
//   - validate "Vgm "
//   - data start from header offset 0x34; zero means 0x40
//   - YM2612 0x52/0x53, PSG 0x50, waits, GG stereo skip, 0x66 end
//   - 0x67 type 0x00 data block is kept as the YM2612 PCM bank
//   - 0xe0 PCM seek and 0x80-0x8f YM2612 DAC stream commands

module vgm_loaded_player #(
    parameter int ADDR_WIDTH = 18,
    parameter bit YM2151_MODE = 1'b0
) (
    input  logic                  clk,
    input  logic                  reset,
    input  logic                  start,
    input  logic                  load_done,
    input  logic                  load_done_pulse,
    input  logic                  load_error,
    input  logic                  overflow_error,
    input  logic [ADDR_WIDTH:0]   file_size,

    input  logic                  vgm_wait_tick,

    output logic                  mem_rd_req,
    output logic [ADDR_WIDTH-1:0] mem_rd_addr,
    input  logic                  mem_rd_ready,
    input  logic                  mem_rd_valid,
    input  logic [7:0]            mem_rd_data,
    output logic                  segapcm_copy_wr_req,
    input  logic                  segapcm_copy_wr_ready,
    output logic [18:0]           segapcm_copy_wr_addr,
    output logic [7:0]            segapcm_copy_wr_data,
    output logic                  segapcm_copy_flush_req,
    input  logic                  segapcm_copy_flush_done,
    output logic                  segapcm_payload_tap_valid,
    output logic [18:0]           segapcm_payload_tap_addr,
    output logic [7:0]            segapcm_payload_tap_data,
    output logic [31:0]           segapcm_payload_tap_byte_count_debug,

    input  logic                  ym_cmd_ready,
    input  logic                  psg_cmd_ready,
    output logic                  ym_cmd_valid,
    output logic                  ym_cmd_port,
    output logic [7:0]            ym_cmd_reg,
    output logic [7:0]            ym_cmd_data,
    output logic                  psg_cmd_valid,
    output logic [7:0]            psg_cmd_data,
    input  logic                  ym2151_cmd_ready,
    output logic                  ym2151_cmd_valid,
    output logic [7:0]            ym2151_cmd_reg,
    output logic [7:0]            ym2151_cmd_data,

    output logic                  busy,
    output logic                  done,
    output logic                  header_valid,
    output logic                  player_error,
    output logic [7:0]            unsupported_opcode,
    output logic [ADDR_WIDTH-1:0] unsupported_pc,
    output logic [7:0]            player_error_code,
    output logic [ADDR_WIDTH-1:0] error_pc_debug,
    output logic [7:0]            error_cmd_debug,
    output logic [6:0]            state_debug,
    output logic                  mem_rd_req_debug,
    output logic                  mem_rd_ready_debug,
    output logic                  mem_rd_valid_debug,
    output logic [ADDR_WIDTH-1:0] mem_rd_addr_debug,
    output logic [15:0]           player_core_debug,
    output logic [15:0]           player_lifecycle_debug,
    output logic [7:0]            last_read_byte_debug,
    output logic [31:0]           header_magic_read_debug,
    output logic [3:0]            header_magic_fail_index_debug,
    output logic [ADDR_WIDTH-1:0] read_request_addr_debug,
    output logic [ADDR_WIDTH-1:0] read_response_addr_debug,
    output logic                  read_pending_debug,
    output logic                  read_valid_consumed_debug,
    output logic [6:0]            final_state_debug,
    output logic [ADDR_WIDTH-1:0] final_pc_debug,
    output logic [7:0]            final_cmd_debug,
    output logic [7:0]            final_error_code_debug,
    output logic [15:0]           final_flags_debug,
    output logic [3:0]            final_reason_debug_out,
    output logic [15:0]           final_progress_debug,
    output logic [7:0]            first_playback_cmd_after_scan_debug_out,
    output logic [31:0]           first_playback_cmds_after_scan_debug,
    output logic [6:0]            scan_state_debug,
    output logic [ADDR_WIDTH-1:0] scan_pc_debug,
    output logic [7:0]            scan_last_cmd_debug,
    output logic [7:0]            scan_block_type_debug,
    output logic [15:0]           scan_block_size_low_debug,
    output logic [15:0]           scan_remaining_low_debug,
    output logic [15:0]           scan_wait_debug,
    output logic [7:0]            scan_abort_reason_debug,
    output logic [15:0]           scan_copy_last_index_low_debug,
    output logic [15:0]           scan_copy_req_count_debug,
    output logic [15:0]           scan_copy_ready_count_debug,
    output logic [15:0]           scan_copy_tail_debug,
    output logic [15:0]           scan_player_accept_count_debug,
    output logic [15:0]           scan_player_remaining_debug,
    output logic [15:0]           scan_payload_len_low_debug,
    output logic [15:0]           scan_copy_accept_fire_count_debug,
    output logic [15:0]           scan_noncopy_advance_count_debug,
    output logic                  scan_used_noncopy_advance_during_copy_debug,
    output logic [15:0]           scan_raw_copy_byte_count_debug,
    output logic [15:0]           scan_raw_event_debug,
    output logic [15:0]           scan_copy_exit_debug,
    output logic [15:0]           scan_copy_exit_pc_debug,
    output logic [15:0]           scan_copy_exit_count_debug,
    output logic [15:0]           scan_copy_phase_debug,
    output logic [15:0]           scan_copy_read_req_count_debug,
    output logic [15:0]           scan_copy_read_accept_count_debug,
    output logic [15:0]           scan_copy_read_valid_count_debug,
    output logic [15:0]           scan_copy_mem_req_cycle_count_debug,
    output logic [15:0]           scan_copy_mem_req_ready_cycle_count_debug,
    output logic [15:0]           scan_copy_request_state_debug,
    output logic [15:0]           scan_copy_state_lifetime_debug,
    output logic [15:0]           scan_copy_clear_reason_debug,
    output logic [15:0]           scan_copy_payload_pc_debug,
    output logic [15:0]           scan_copy_first01_debug,
    output logic [15:0]           scan_copy_first23_debug,
    output logic [15:0]           scan_copy_first45_debug,
    output logic [15:0]           scan_copy_first67_debug,
    output logic [15:0]           scan_copy_first8_phase_debug,
    output logic [15:0]           scan_copy_read_raw_valid_count_debug,
    output logic [15:0]           scan_copy_read_ignored_valid_count_debug,
    output logic [15:0]           scan_copy_read_handshake_debug,
    output logic [15:0]           scan_payload_o0_debug,
    output logic [15:0]           scan_payload_af_debug,
    output logic [15:0]           scan_payload_vd_debug,
    output logic [15:0]           scan_payload_cp_debug,
    output logic [15:0]           scan_term_pl_debug,
    output logic [15:0]           scan_term_rm_debug,
    output logic [15:0]           scan_term_cc_debug,
    output logic [15:0]           scan_term_nx_debug,
    output logic [15:0]           scan_term_be_debug,
    output logic [15:0]           scan_sticky_guard_debug,
    output logic [15:0]           scan_payload_qg_debug,
    output logic [15:0]           scan_payload_sf_debug,
    output logic                  scan_payload_continue_guard_active_debug,
    output logic                  scan_remaining_zero_before_expected_accept_debug,
    output logic [ADDR_WIDTH-1:0] data_start_debug,
    output logic [ADDR_WIDTH-1:0] current_pc_debug,
    output logic [ADDR_WIDTH-1:0] loop_pc_debug,
    output logic                  loop_valid_debug,
    output logic                  loop_taken_debug,
    output logic                  end_command_seen,
    output logic                  restarted_from_data_start,
    output logic                  pcm_oob,
    output logic [31:0]           pcm_oob_count,
    output logic [31:0]           wait_ticks_consumed_debug,
    output logic [31:0]           dac_stream_cmd_count,
    output logic [31:0]           dac_stream_wait_samples_total,
    output logic [31:0]           dac_stream_clk_cycles_total,
    output logic [31:0]           dac_stream_overhead_cycles_total,
    output logic [31:0]           max_dac_stream_cmd_cycles,
    output logic [31:0]           count_wait0_dac_stream_cmd,
    output logic [31:0]           count_wait0_overhead_nonzero,
    output logic [31:0]           ym2151_write_count,
    output logic [7:0]            ym2151_last_reg,
    output logic [7:0]            ym2151_last_data,
    output logic [31:0]           unsupported_command_count,
    output logic                  segapcm_cmd_valid,
    output logic [15:0]           segapcm_cmd_addr,
    output logic [7:0]            segapcm_cmd_data,
    output logic [31:0]           segapcm_write_count,
    output logic [15:0]           segapcm_last_addr,
    output logic [7:0]            segapcm_last_data,
    output logic [31:0]           data_block_count,
    output logic [7:0]            last_data_block_type,
    output logic [15:0]           last_data_block_size_low,
    output logic [31:0]           parser_command_count_debug,
    output logic [31:0]           parser_data_block_count_debug,
    output logic [7:0]            parser_last_block_type_debug,
    output logic [31:0]           parser_type00_block_count_debug,
    output logic [31:0]           parser_type80_block_count_debug,
    output logic [31:0]           segapcm_rom_block_count,
    output logic [31:0]           segapcm_last_rom_size,
    output logic [31:0]           segapcm_last_rom_start,
    output logic [31:0]           pcm_ram_write_skip_count,
    output logic                  segapcm_rom_scan_busy,
    output logic                  segapcm_rom_scan_done,
    output logic                  segapcm_rom_scan_overflow,
    output logic [31:0]           segapcm_rom_scan_block_count,
    output logic [31:0]           segapcm_rom_scan_byte_count,
    output logic [31:0]           segapcm_rom_scan_checksum32,
    output logic [31:0]           segapcm_rom_scan_total_size,
    output logic [31:0]           segapcm_rom_scan_last_start,
    output logic [31:0]           segapcm_rom_copy_byte_count,
    output logic                  segapcm_rom_copy_overflow,
    output logic                  segapcm_rom_copy_flush_done,
    output logic                  segapcm_copy_flush_req_debug,
    output logic [ADDR_WIDTH-1:0] done_pc_debug,
    output logic [7:0]            done_cmd_debug,
    output logic [9:0]            pc_debug,
    output logic [7:0]            last_cmd_debug
);

    // Temporary FM-only restore mode for YM2151/SegaPCM VGMs. SegaPCM ROM
    // blocks are skipped during normal command playback and the experimental
    // pre-scan/copy path is bypassed until the SegaPCM audio path is ready.
    localparam bit SEGAPCM_FM_ONLY_RESTORE = 1'b1;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
`define MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_ACTIVE 1
`endif
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_ACTIVE
    localparam logic [18:0] SEGAPCM_SMOKE_DDR_CAPTURE_BYTES = 19'h01000;
`endif

`ifdef MEGAVGMDRIVE_SEGAPCM_COPY_DISABLE
    localparam bit SEGAPCM_COPY_ENABLED = 1'b0;
`else
    localparam bit SEGAPCM_COPY_ENABLED = !SEGAPCM_FM_ONLY_RESTORE;
`endif

    wire segapcm_rom_block_skip_debug_active =
        YM2151_MODE && SEGAPCM_FM_ONLY_RESTORE;

    typedef enum logic [6:0] {
        ST_IDLE,
        ST_READ_WAIT,
        ST_READ_DATA,
        ST_CHECK_MAGIC0,
        ST_CHECK_MAGIC1,
        ST_CHECK_MAGIC2,
        ST_CHECK_MAGIC3,
        ST_READ_LOOP0,
        ST_READ_LOOP1,
        ST_READ_LOOP2,
        ST_READ_LOOP3,
        ST_READ_OFF0,
        ST_READ_OFF1,
        ST_READ_OFF2,
        ST_READ_OFF3,
        ST_FETCH_CMD,
        ST_DECODE,
        ST_ARG1,
        ST_ARG2,
        ST_BLOCK_MARKER,
        ST_BLOCK_TYPE,
        ST_BLOCK_SIZE0,
        ST_BLOCK_SIZE1,
        ST_BLOCK_SIZE2,
        ST_BLOCK_SIZE3,
        ST_SEEK0,
        ST_SEEK1,
        ST_SEEK2,
        ST_SEEK3,
        ST_DAC_READ,
        ST_YM_WAIT_READY,
        ST_YM_PULSE,
        ST_YM2151_WAIT_READY,
        ST_YM2151_PULSE,
        ST_SEGAPCM_DATA,
        ST_SEGAPCM_ROM_SIZE0,
        ST_SEGAPCM_ROM_SIZE1,
        ST_SEGAPCM_ROM_SIZE2,
        ST_SEGAPCM_ROM_SIZE3,
        ST_SEGAPCM_ROM_START0,
        ST_SEGAPCM_ROM_START1,
        ST_SEGAPCM_ROM_START2,
        ST_SEGAPCM_ROM_START3,
        ST_SCAN_FETCH_CMD,
        ST_SCAN_DECODE,
        ST_SCAN_BLOCK_MARKER,
        ST_SCAN_BLOCK_TYPE,
        ST_SCAN_BLOCK_SIZE0,
        ST_SCAN_BLOCK_SIZE1,
        ST_SCAN_BLOCK_SIZE2,
        ST_SCAN_BLOCK_SIZE3,
        ST_SCAN_ROM_TOTAL0,
        ST_SCAN_ROM_TOTAL1,
        ST_SCAN_ROM_TOTAL2,
        ST_SCAN_ROM_TOTAL3,
        ST_SCAN_ROM_START0,
        ST_SCAN_ROM_START1,
        ST_SCAN_ROM_START2,
        ST_SCAN_ROM_START3,
        ST_SEGAPCM_COPY_READ_WAIT,
        ST_SEGAPCM_COPY_READ_DATA,
        ST_SEGAPCM_COPY_WRITE,
        ST_SCAN_ROM_PAYLOAD,
        ST_SCAN_ROM_COPY,
        ST_SCAN_FLUSH,
        ST_PSG_WAIT_READY,
        ST_PSG_PULSE,
        ST_WAIT_SAMPLES,
        ST_DONE,
        ST_ERROR,
        ST_SEGAPCM_TAP_PAYLOAD
    } state_t;

    state_t state;
    state_t read_return_state;

    logic [ADDR_WIDTH-1:0] pc;
    logic [7:0] read_data;
    logic [7:0] cmd;
    logic [7:0] arg1;
    logic [7:0] block_type;
    logic [31:0] block_size;
    logic [ADDR_WIDTH-1:0] block_skip_target;
    logic [31:0] data_offset;
    logic [31:0] loop_offset;
    logic [ADDR_WIDTH-1:0] loop_pc;
    logic loop_valid;
    logic [31:0] pcm_data_start;
    logic [31:0] pcm_data_size;
    logic [31:0] pcm_pos;
    logic [15:0] segapcm_pending_addr;
    logic [15:0] wait_remaining;
    logic vgm_wait_tick_d;
    logic start_d;
    logic dac_stream_measure_active;
    logic dac_stream_wait0_current;
    logic [31:0] dac_stream_cmd_cycles;
    logic [31:0] dac_stream_cmd_wait_cycles;
    logic [31:0] scan_payload_remaining;
    logic [31:0] scan_payload_addr;
    logic [18:0] scan_copy_addr;
    logic [7:0] scan_copy_data;
    logic scan_copy_enabled;
    logic segapcm_copy_active_i;
    logic scan_copy_req_armed;
    logic [31:0] segapcm_tap_payload_remaining;
    logic [31:0] segapcm_tap_payload_addr;
    logic [18:0] segapcm_tap_payload_index;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_ACTIVE
    logic segapcm_smoke_ddr_capture_done_i;
`endif
    logic start_seen_debug;
    logic start_edge_seen_debug;
    logic start_file_ok_seen_debug;
    logic header_request_seen_debug;
    logic read_wait_seen_debug;
    logic mem_valid_seen_debug;
    logic magic_error_seen_debug;
    logic entered_idle_after_start_debug;
    logic entered_read_data_debug;
    logic entered_magic_check_debug;
    logic start_level_file_ok_seen_debug;
    logic read_pending;
    logic read_accepted;
    logic read_valid_consumed;
    logic read_ignore_valid_until_low;
    logic scan_payload_read_owner;
    logic outstanding_payload_read;
    logic sega_payload_continue_guard_i;
    logic scan_payload_continue_pending_i;
    logic scan_payload_req_hold_i;
    logic [ADDR_WIDTH-1:0] scan_payload_req_addr_i;
    logic [7:0] scan_payload_qg_debug_i;
    logic [7:0] scan_payload_sf_debug_i;
    logic [ADDR_WIDTH-1:0] last_payload_read_addr;
    logic last_payload_read_addr_valid;
    logic outstanding_payload_read_seen_debug_i;
    logic rq_increment_without_outstanding_debug_i;
    logic outstanding_cleared_while_rq_gt_rr_debug_i;
    logic payload_gap_without_addr_debug_i;
    logic read_accept_fire_debug_i;
    logic read_accept_rr_increment_debug_i;
    logic read_accept_to_read_data_debug_i;
    logic read_accept_clear_pending_debug_i;
    logic read_data_consumed_debug_i;
    logic read_valid_rv_increment_debug_i;
    logic payload_byte_valid_pulse_debug_i;
    logic read_data_return_to_payload_debug_i;
    logic copy_pa_increment_debug_i;
    logic copy_ca_increment_debug_i;
    logic copy_transition_next_payload_debug_i;
    logic scan_finish_taken_debug_i;
    logic [15:0] scan_term_pl_debug_i;
    logic [15:0] scan_term_rm_debug_i;
    logic [15:0] scan_term_cc_debug_i;
    logic [15:0] scan_term_nx_debug_i;
    logic [15:0] scan_term_be_debug_i;
    logic [7:0] scan_sticky_guard_debug_i;
    logic final_valid_debug;
    logic header_valid_seen_debug;
    logic scan_started_seen_debug;
    logic scan_done_seen_debug;
    logic copy_flush_done_seen_debug;
    logic playback_started_after_scan_debug;
    logic scan_overflow_seen_debug;
    logic copy_overflow_seen_debug;
    logic normal_command_fetch_started_debug;
    logic scan_finish_called_debug;
    logic pc_rewound_to_data_start_debug;
    logic status_stop_without_final_reason_debug;
    logic scan_final_byte_accepted_debug;
    logic scan_transitioned_to_flush_debug;
    logic [15:0] scan_copy_last_index_low_debug_i;
    logic [15:0] scan_copy_req_count_debug_i;
    logic [15:0] scan_copy_ready_count_debug_i;
    logic [15:0] scan_copy_accept_fire_count_debug_i;
    logic [15:0] scan_noncopy_advance_count_debug_i;
    logic scan_used_noncopy_advance_during_copy_debug_i;
    logic [15:0] scan_copy_exit_debug_i;
    logic [15:0] scan_copy_exit_pc_debug_i;
    logic [15:0] scan_copy_exit_count_debug_i;
    logic [15:0] scan_copy_read_req_count_debug_i;
    logic [15:0] scan_copy_read_accept_count_debug_i;
    logic [15:0] scan_copy_read_valid_count_debug_i;
    logic [15:0] scan_copy_mem_req_cycle_count_debug_i;
    logic [15:0] scan_copy_mem_req_ready_cycle_count_debug_i;
    logic [15:0] scan_copy_request_gap_debug_i;
    logic [6:0] previous_state_debug_i;
    logic [6:0] last_nonzero_state_debug_i;
    logic [6:0] return_state_snapshot_debug_i;
    logic [7:0] scan_copy_clear_reason_debug_i;
    logic [15:0] scan_copy_payload_pc_debug_i;
    logic scan_payload_byte_valid_debug_i;
    logic [7:0] scan_copy_first_byte0_debug_i;
    logic [7:0] scan_copy_first_byte1_debug_i;
    logic [7:0] scan_copy_first_byte2_debug_i;
    logic [7:0] scan_copy_first_byte3_debug_i;
    logic [7:0] scan_copy_first_byte4_debug_i;
    logic [7:0] scan_copy_first_byte5_debug_i;
    logic [7:0] scan_copy_first_byte6_debug_i;
    logic [7:0] scan_copy_first_byte7_debug_i;
    logic [7:0] scan_copy_first_byte8_debug_i;
    logic [7:0] scan_copy_source_phase_debug_i;
    logic [15:0] scan_copy_read_raw_valid_count_debug_i;
    logic [15:0] scan_copy_read_ignored_valid_count_debug_i;
    logic [15:0] scan_abort_remaining_low_debug;
    logic [31:0] scan_current_payload_len_debug;
    logic scan_remaining_zero_before_expected_accept_debug_i;
    logic [7:0] first_playback_cmd_after_scan_debug;
    logic [31:0] first_playback_cmds_after_scan_debug_i;
    logic [2:0] first_playback_cmd_count_debug;
    logic [3:0] final_reason_debug;

    localparam logic [3:0] STOP_REASON_NONE          = 4'h0;
    localparam logic [3:0] STOP_REASON_66_NO_LOOP    = 4'h1;
    localparam logic [3:0] STOP_REASON_MAGIC_ERROR   = 4'h2;
    localparam logic [3:0] STOP_REASON_UNSUPPORTED   = 4'h3;
    localparam logic [3:0] STOP_REASON_BOUNDS_EOF    = 4'h4;
    localparam logic [3:0] STOP_REASON_SCAN_OVERFLOW = 4'h5;
    localparam logic [3:0] STOP_REASON_COPY_OVERFLOW = 4'h6;
    localparam logic [3:0] STOP_REASON_OTHER_ERROR   = 4'h7;

    wire start_edge = start && !start_d;
    wire start_request = load_done_pulse || start_edge || (YM2151_MODE && start);
    wire vgm_wait_tick_edge = vgm_wait_tick && !vgm_wait_tick_d;
    wire file_ok = load_done && !load_error && !overflow_error && (file_size > 17'd64);
    wire pc_in_range = ({1'b0, pc} < file_size);
    wire [31:0] pc_32 = {{(32-ADDR_WIDTH){1'b0}}, pc};
    wire [31:0] current_block_size = {read_data, block_size[23:0]};
    wire [31:0] block_data_start_32 = pc_32 + 32'd7;
    wire [31:0] block_skip_end_32 = block_data_start_32 + current_block_size;
    wire [31:0] segapcm_tap_payload_start_32 = block_data_start_32 + 32'd8;
    wire [31:0] segapcm_tap_payload_size_32 =
        (current_block_size > 32'd8) ? (current_block_size - 32'd8) : 32'd0;
    wire block_skip_in_range =
        (block_skip_end_32 <= file_size) && (block_skip_end_32[31:ADDR_WIDTH] == '0);
    wire [31:0] segapcm_tap_payload_next_addr =
        segapcm_tap_payload_addr + 32'd1;
    wire [18:0] segapcm_tap_payload_next_index =
        segapcm_tap_payload_index + 19'd1;
    wire [31:0] segapcm_rom_header_end_32 = block_data_start_32 + 32'd8;
    wire segapcm_rom_header_in_range =
        (current_block_size >= 32'd8) &&
        (segapcm_rom_header_end_32 <= file_size) &&
        (segapcm_rom_header_end_32[31:ADDR_WIDTH] == '0);
    wire [31:0] header_data_offset = {read_data, data_offset[23:0]};
    wire [31:0] selected_data_start =
        (header_data_offset == 32'd0) ? 32'h0000_0040 : (32'h0000_0034 + header_data_offset);
    wire selected_data_start_in_range =
        (selected_data_start < file_size) && (selected_data_start[31:ADDR_WIDTH] == '0);
    wire [31:0] header_loop_offset = {read_data, loop_offset[23:0]};
    wire [31:0] selected_loop_pc = 32'h0000_001c + header_loop_offset;
    wire selected_loop_valid =
        (header_loop_offset != 32'd0) && (selected_loop_pc < file_size) &&
        (selected_loop_pc[31:ADDR_WIDTH] == '0);
    wire [31:0] pcm_read_addr_32 = pcm_data_start + pcm_pos;
    wire pcm_read_in_range =
        (pcm_pos < pcm_data_size) &&
        (pcm_read_addr_32 < file_size) &&
        (pcm_read_addr_32[31:ADDR_WIDTH] == '0);
    wire [31:0] scan_rom_start_32 = {read_data, segapcm_rom_scan_last_start[23:0]};
    wire [32:0] scan_rom_payload_end_33 =
        {1'b0, scan_rom_start_32} + {1'b0, scan_payload_remaining};
    wire scan_rom_copy_range_ok =
        (segapcm_rom_scan_total_size <= 32'h0008_0000) &&
        (scan_rom_start_32 <= 32'h0008_0000) &&
        (scan_rom_payload_end_33 <= 33'h0_0008_0000);
    wire copy_accept_fire =
        (((state == ST_SCAN_ROM_COPY) &&
          segapcm_copy_wr_ready) ||
         ((state == ST_SEGAPCM_COPY_WRITE) &&
          segapcm_copy_wr_req &&
          segapcm_copy_wr_ready));
    wire payload_read_accept_gap =
        scan_copy_read_req_count_debug_i >
        scan_copy_read_accept_count_debug_i;
    wire actual_read_accept_fire =
        (state == ST_READ_WAIT) &&
        (read_pending || scan_payload_read_owner ||
         scan_payload_req_hold_i) &&
        mem_rd_req &&
        mem_rd_ready;
    wire actual_read_accept_rr_increment =
        actual_read_accept_fire &&
        (read_return_state == ST_SCAN_ROM_PAYLOAD) &&
        (scan_copy_read_accept_count_debug_i != 16'hffff);
    wire qg_request_owner_is_payload =
        scan_payload_req_hold_i ||
        scan_payload_read_owner ||
        segapcm_copy_active_i ||
        (state == ST_SEGAPCM_COPY_READ_WAIT) ||
        (state == ST_SEGAPCM_COPY_READ_DATA) ||
        (state == ST_SEGAPCM_COPY_WRITE) ||
        (read_return_state == ST_SCAN_ROM_PAYLOAD);
    wire qg_payload_req_asserted =
        mem_rd_req && qg_request_owner_is_payload;
    wire qg_payload_hold_driven =
        mem_rd_req &&
        ((scan_payload_req_hold_i &&
          (mem_rd_addr == scan_payload_req_addr_i)) ||
         (segapcm_copy_active_i &&
          (state == ST_SEGAPCM_COPY_READ_WAIT) &&
          (mem_rd_addr == scan_payload_addr[ADDR_WIDTH-1:0])));
    wire qg_backend_read_accept_seen =
        qg_payload_req_asserted && mem_rd_ready;
    wire qg_backend_request_blocked =
        qg_payload_req_asserted && !mem_rd_ready;
    wire qg_payload_addr_invalid =
        qg_request_owner_is_payload &&
        ((scan_payload_req_hold_i && (scan_payload_req_addr_i == '0)) ||
         (!scan_payload_req_hold_i && !last_payload_read_addr_valid &&
          (mem_rd_addr == '0)));
    wire [7:0] scan_payload_qg_live = {
        qg_payload_addr_invalid,
        qg_request_owner_is_payload,
        qg_backend_request_blocked,
        qg_backend_read_accept_seen,
        qg_payload_hold_driven,
        scan_payload_req_hold_i,
        qg_payload_req_asserted,
        1'b0
    };
    wire sega_payload_copy_active =
        scan_copy_enabled &&
        (scan_current_payload_len_debug != 32'd0) &&
        !segapcm_rom_scan_done &&
        !segapcm_rom_scan_overflow &&
        !segapcm_rom_copy_overflow;
    wire sega_payload_continue_pending =
        sega_payload_copy_active &&
        ((scan_payload_remaining != 32'd0) ||
         (segapcm_rom_copy_byte_count < scan_current_payload_len_debug) ||
         payload_read_accept_gap ||
         (scan_copy_read_accept_count_debug_i >
          scan_copy_read_valid_count_debug_i) ||
         scan_payload_byte_valid_debug_i ||
         scan_copy_req_armed ||
         outstanding_payload_read ||
         scan_payload_read_owner ||
         ((read_return_state == ST_SCAN_ROM_PAYLOAD) &&
          (read_pending || read_accepted || mem_rd_req)) ||
         (state == ST_SCAN_ROM_PAYLOAD) ||
         (state == ST_SCAN_ROM_COPY) ||
         (state == ST_SEGAPCM_COPY_READ_WAIT) ||
         (state == ST_SEGAPCM_COPY_READ_DATA) ||
         (state == ST_SEGAPCM_COPY_WRITE) ||
         (state == ST_READ_WAIT) ||
         (state == ST_READ_DATA));
    wire sega_payload_continue_guard =
        sega_payload_continue_pending || sega_payload_continue_guard_i;
    wire sega_payload_continue_guard_set =
        YM2151_MODE &&
        (scan_copy_enabled || sega_payload_copy_active ||
         (scan_current_payload_len_debug != 32'd0)) &&
        ((state == ST_SCAN_ROM_PAYLOAD) ||
         (state == ST_SCAN_ROM_COPY) ||
         (state == ST_SEGAPCM_COPY_READ_WAIT) ||
         (state == ST_SEGAPCM_COPY_READ_DATA) ||
         (state == ST_SEGAPCM_COPY_WRITE) ||
         copy_accept_fire ||
         scan_payload_byte_valid_debug_i ||
         payload_byte_valid_pulse_debug_i ||
         copy_pa_increment_debug_i ||
         copy_ca_increment_debug_i ||
         copy_transition_next_payload_debug_i ||
         scan_copy_req_armed ||
         outstanding_payload_read ||
         scan_payload_read_owner ||
         ((read_return_state == ST_SCAN_ROM_PAYLOAD) &&
          (read_pending || read_accepted || mem_rd_req)) ||
         (scan_payload_remaining != 32'd0) ||
         (segapcm_rom_copy_byte_count < scan_current_payload_len_debug));
    wire sega_payload_work_active =
        YM2151_MODE &&
        (sega_payload_continue_guard ||
         scan_payload_continue_pending_i ||
         ((scan_current_payload_len_debug != 32'd0) &&
          (scan_payload_remaining != 32'd0)) ||
         scan_payload_byte_valid_debug_i ||
         scan_copy_req_armed ||
         scan_payload_req_hold_i ||
         outstanding_payload_read ||
         scan_payload_read_owner);
    wire sega_payload_continue_guard_clear =
        sega_payload_continue_guard_i &&
        !sega_payload_continue_pending &&
        (scan_payload_remaining == 32'd0) &&
        !scan_payload_byte_valid_debug_i &&
        !segapcm_copy_wr_req &&
        !copy_accept_fire &&
        !scan_copy_req_armed &&
        !outstanding_payload_read &&
        !scan_payload_read_owner &&
        !payload_read_accept_gap &&
        !(scan_copy_read_accept_count_debug_i >
          scan_copy_read_valid_count_debug_i) &&
        !((read_return_state == ST_SCAN_ROM_PAYLOAD) &&
          (read_pending || read_accepted || mem_rd_req)) &&
        ((state == ST_SCAN_FETCH_CMD) || (state == ST_SCAN_DECODE));
    wire payload_read_recovery_needed =
        (outstanding_payload_read || sega_payload_copy_active) &&
        payload_read_accept_gap &&
        last_payload_read_addr_valid &&
        ((state == ST_IDLE) ||
         !read_pending ||
         (!mem_rd_req && !read_accepted) ||
         (read_return_state != ST_SCAN_ROM_PAYLOAD));
    wire [7:0] scan_payload_invariant_debug = {
        2'd0,
        payload_gap_without_addr_debug_i,
        last_payload_read_addr_valid,
        outstanding_cleared_while_rq_gt_rr_debug_i,
        rq_increment_without_outstanding_debug_i,
        payload_read_accept_gap,
        outstanding_payload_read | outstanding_payload_read_seen_debug_i
    };
    wire [15:0] scan_copy_request_state_live = {
        busy,
        done,
        player_error,
        (state == ST_SCAN_ROM_PAYLOAD),
        scan_payload_byte_valid_debug_i,
        scan_copy_req_armed,
        ((state == ST_SCAN_ROM_COPY) ||
         (state == ST_SEGAPCM_COPY_WRITE)),
        (read_return_state == ST_SCAN_ROM_PAYLOAD),
        (state == ST_READ_DATA),
        (state == ST_READ_WAIT),
        (read_pending && read_accepted && !mem_rd_valid),
        read_accepted,
        read_pending,
        (mem_rd_req && mem_rd_ready),
        mem_rd_ready,
        mem_rd_req
    };
    wire [31:0] scan_next_copy_accept_count =
        segapcm_rom_copy_byte_count + 32'd1;
    wire scan_copy_has_more_payload_after_accept =
        (scan_payload_remaining > 32'd1) ||
        (scan_current_payload_len_debug > scan_next_copy_accept_count);
    wire [31:0] scan_next_payload_remaining =
        (scan_payload_remaining > 32'd0) ?
        (scan_payload_remaining - 32'd1) :
        ((scan_current_payload_len_debug > scan_next_copy_accept_count) ?
         (scan_current_payload_len_debug - scan_next_copy_accept_count) :
         32'd0);
    wire [31:0] scan_display_remaining =
        (scan_current_payload_len_debug > segapcm_rom_copy_byte_count) ?
        (scan_current_payload_len_debug - segapcm_rom_copy_byte_count) :
        32'd0;
    wire scan_copy_source_total_header =
        (scan_payload_addr >= block_data_start_32) &&
        (scan_payload_addr < (block_data_start_32 + 32'd4));
    wire scan_copy_source_start_header =
        (scan_payload_addr >= (block_data_start_32 + 32'd4)) &&
        (scan_payload_addr < (block_data_start_32 + 32'd8));
    wire scan_copy_source_payload =
        (scan_payload_addr >= (block_data_start_32 + 32'd8));

    assign state_debug = state;
    assign mem_rd_req_debug = mem_rd_req;
    assign mem_rd_ready_debug = mem_rd_ready;
    assign mem_rd_valid_debug = mem_rd_valid;
    assign mem_rd_addr_debug = mem_rd_addr;
    assign segapcm_copy_flush_req_debug = segapcm_copy_flush_req;
    assign read_pending_debug = read_pending;
    assign read_valid_consumed_debug = read_valid_consumed;
    assign final_flags_debug = {
        final_valid_debug,
        header_valid_seen_debug,
        scan_started_seen_debug,
        scan_done_seen_debug,
        copy_flush_done_seen_debug,
        playback_started_after_scan_debug,
        scan_overflow_seen_debug,
        copy_overflow_seen_debug,
        player_error,
        done,
        loop_valid,
        end_command_seen,
        final_reason_debug
    };
    assign final_reason_debug_out = final_reason_debug;
    assign first_playback_cmd_after_scan_debug_out =
        first_playback_cmd_after_scan_debug;
    assign first_playback_cmds_after_scan_debug =
        first_playback_cmds_after_scan_debug_i;
    assign scan_state_debug = state;
    assign scan_pc_debug = pc;
    assign scan_last_cmd_debug = cmd;
    assign scan_block_type_debug = block_type;
    assign scan_block_size_low_debug = block_size[15:0];
    assign scan_remaining_low_debug = scan_payload_remaining[15:0];
    assign scan_copy_last_index_low_debug = scan_copy_last_index_low_debug_i;
    assign scan_copy_req_count_debug = scan_copy_req_count_debug_i;
    assign scan_copy_ready_count_debug = scan_copy_ready_count_debug_i;
    assign scan_player_accept_count_debug = segapcm_rom_copy_byte_count[15:0];
    assign scan_player_remaining_debug = scan_display_remaining[15:0];
    assign scan_payload_len_low_debug = scan_current_payload_len_debug[15:0];
    assign scan_copy_accept_fire_count_debug =
        scan_copy_accept_fire_count_debug_i;
    assign scan_noncopy_advance_count_debug =
        scan_noncopy_advance_count_debug_i;
    assign scan_used_noncopy_advance_during_copy_debug =
        scan_used_noncopy_advance_during_copy_debug_i;
    assign scan_raw_copy_byte_count_debug =
        segapcm_rom_copy_byte_count[15:0];
    assign scan_raw_event_debug = {
        11'd0,
        copy_accept_fire,
        (state == ST_SCAN_ROM_COPY),
        segapcm_copy_wr_ready,
        scan_copy_req_armed,
        copy_accept_fire
    };
    assign scan_copy_exit_debug = scan_copy_exit_debug_i;
    assign scan_copy_exit_pc_debug = scan_copy_exit_pc_debug_i;
    assign scan_copy_exit_count_debug = scan_copy_exit_count_debug_i;
    assign scan_copy_phase_debug = {
        busy,
        player_error,
        segapcm_rom_scan_busy,
        (scan_current_payload_len_debug != 32'd0),
        scan_copy_enabled,
        (state == ST_SCAN_ROM_PAYLOAD),
        ((state == ST_SCAN_ROM_COPY) ||
         (state == ST_SEGAPCM_COPY_WRITE)),
        ((state == ST_SCAN_ROM_COPY) ||
         (state == ST_SEGAPCM_COPY_WRITE)) &&
            (scan_copy_req_armed || segapcm_copy_active_i) &&
            !segapcm_copy_wr_ready,
        ((state == ST_READ_WAIT) || (state == ST_READ_DATA)) &&
            (read_return_state == ST_SCAN_ROM_PAYLOAD),
        mem_rd_valid,
        mem_rd_ready,
        mem_rd_req,
        read_accepted,
        read_pending,
        scan_copy_req_armed,
        scan_payload_byte_valid_debug_i
    };
    assign scan_copy_read_req_count_debug =
        scan_copy_read_req_count_debug_i;
    assign scan_copy_read_accept_count_debug =
        scan_copy_read_accept_count_debug_i;
    assign scan_copy_read_valid_count_debug =
        scan_copy_read_valid_count_debug_i;
    assign scan_copy_mem_req_cycle_count_debug =
        scan_copy_mem_req_cycle_count_debug_i;
    assign scan_copy_mem_req_ready_cycle_count_debug =
        scan_copy_mem_req_ready_cycle_count_debug_i;
    assign scan_copy_request_state_debug =
        (scan_copy_request_gap_debug_i != 16'd0) ?
        scan_copy_request_gap_debug_i :
        scan_copy_request_state_live;
    assign scan_copy_state_lifetime_debug = {
        2'd0,
        last_nonzero_state_debug_i,
        previous_state_debug_i
    };
    assign scan_copy_clear_reason_debug = {
        scan_payload_invariant_debug,
        1'b0,
        return_state_snapshot_debug_i
    };
    assign scan_copy_payload_pc_debug = scan_copy_payload_pc_debug_i;
    assign scan_copy_first01_debug = {
        scan_copy_first_byte1_debug_i,
        scan_copy_first_byte0_debug_i
    };
    assign scan_copy_first23_debug = {
        scan_copy_first_byte3_debug_i,
        scan_copy_first_byte2_debug_i
    };
    assign scan_copy_first45_debug = {
        scan_copy_first_byte5_debug_i,
        scan_copy_first_byte4_debug_i
    };
    assign scan_copy_first67_debug = {
        scan_copy_first_byte7_debug_i,
        scan_copy_first_byte6_debug_i
    };
    assign scan_copy_first8_phase_debug = {
        scan_copy_source_phase_debug_i,
        scan_copy_first_byte8_debug_i
    };
    assign scan_copy_read_raw_valid_count_debug =
        scan_copy_read_raw_valid_count_debug_i;
    assign scan_copy_read_ignored_valid_count_debug =
        scan_copy_read_ignored_valid_count_debug_i;
    assign scan_copy_read_handshake_debug = {
        8'd0,
        ((state == ST_READ_DATA) &&
         (read_return_state == ST_SCAN_ROM_PAYLOAD) &&
         read_pending &&
         read_accepted &&
         read_ignore_valid_until_low &&
         mem_rd_valid),
        read_ignore_valid_until_low,
        read_valid_consumed,
        mem_rd_valid,
        mem_rd_ready,
        mem_rd_req,
        read_accepted,
        read_pending
    };
    assign scan_payload_o0_debug = {
        8'hD0,
        outstanding_payload_read,
        last_payload_read_addr_valid,
        payload_read_accept_gap,
        scan_payload_read_owner,
        read_pending,
        mem_rd_req,
        mem_rd_ready,
        (state == ST_IDLE)
    };
    assign scan_payload_af_debug = {
        8'hA0,
        (state == ST_READ_WAIT),
        read_accept_to_read_data_debug_i || actual_read_accept_fire,
        read_accept_rr_increment_debug_i || actual_read_accept_rr_increment,
        read_accept_fire_debug_i || actual_read_accept_fire,
        read_pending,
        mem_rd_req && mem_rd_ready,
        mem_rd_ready,
        mem_rd_req
    };
    assign scan_payload_qg_debug = {
        8'hE7,
        scan_payload_qg_debug_i | scan_payload_qg_live
    };
    assign scan_payload_sf_debug = {8'hE9, scan_payload_sf_debug_i};
    assign scan_payload_vd_debug = {
        8'hD1,
        copy_accept_fire,
        (state == ST_SCAN_ROM_PAYLOAD),
        read_data_return_to_payload_debug_i,
        payload_byte_valid_pulse_debug_i,
        read_valid_rv_increment_debug_i,
        read_data_consumed_debug_i,
        mem_rd_valid,
        (state == ST_READ_DATA)
    };
    assign scan_payload_cp_debug = {
        8'hC2,
        copy_accept_fire,
        copy_transition_next_payload_debug_i,
        copy_ca_increment_debug_i,
        copy_pa_increment_debug_i,
        segapcm_copy_wr_req && segapcm_copy_wr_ready,
        segapcm_copy_wr_ready,
        segapcm_copy_wr_req,
        scan_payload_byte_valid_debug_i
    };
    assign scan_term_pl_debug = scan_term_pl_debug_i;
    assign scan_term_rm_debug = scan_term_rm_debug_i;
    assign scan_term_cc_debug = scan_term_cc_debug_i;
    assign scan_term_nx_debug = scan_term_nx_debug_i;
    assign scan_term_be_debug = scan_term_be_debug_i;
    assign scan_sticky_guard_debug = {8'hE6, scan_sticky_guard_debug_i};
    assign scan_payload_continue_guard_active_debug =
        sega_payload_continue_guard;
    assign scan_remaining_zero_before_expected_accept_debug =
        scan_remaining_zero_before_expected_accept_debug_i;
    assign scan_wait_debug = {
        8'd0,
        scan_abort_reason_debug[3:0],
        (state == ST_SCAN_FLUSH) && !segapcm_copy_flush_done,
        (state == ST_SCAN_ROM_COPY) && !segapcm_copy_wr_ready,
        read_pending,
        (state == ST_READ_DATA)
    };
    assign scan_copy_tail_debug = {
        scan_abort_reason_debug[7:4],
        scan_abort_remaining_low_debug[3:0],
        scan_remaining_zero_before_expected_accept_debug_i,
        (scan_copy_req_count_debug_i != scan_copy_ready_count_debug_i),
        (state == ST_SCAN_FLUSH) && !segapcm_copy_flush_done,
        (state == ST_SCAN_ROM_COPY) && !segapcm_copy_wr_ready,
        scan_copy_req_armed,
        scan_transitioned_to_flush_debug,
        scan_final_byte_accepted_debug,
        (scan_display_remaining == 32'd0)
    };
    assign final_progress_debug = {
        5'd0,
        status_stop_without_final_reason_debug,
        pc_rewound_to_data_start_debug,
        scan_finish_called_debug,
        copy_overflow_seen_debug,
        scan_overflow_seen_debug,
        normal_command_fetch_started_debug,
        playback_started_after_scan_debug,
        copy_flush_done_seen_debug,
        scan_done_seen_debug,
        scan_started_seen_debug,
        header_valid_seen_debug
    };
    assign player_core_debug = {
        start_seen_debug,
        start_edge_seen_debug,
        start_file_ok_seen_debug,
        header_request_seen_debug,
        read_wait_seen_debug,
        mem_valid_seen_debug,
        magic_error_seen_debug,
        file_ok,
        load_done,
        load_error,
        overflow_error,
        (file_size > 17'd64),
        busy,
        done,
        header_valid,
        player_error
    };
    assign player_lifecycle_debug = {
        reset,
        start,
        start_request,
        file_ok,
        start_seen_debug,
        start_edge_seen_debug,
        start_file_ok_seen_debug,
        start_level_file_ok_seen_debug,
        header_request_seen_debug,
        read_wait_seen_debug,
        entered_read_data_debug,
        entered_magic_check_debug,
        entered_idle_after_start_debug,
        player_error,
        done,
        busy
    };

    generate
        if (ADDR_WIDTH >= 10) begin : wide_pc_debug
            assign pc_debug = pc[9:0];
        end else begin : narrow_pc_debug
            assign pc_debug = {{(10-ADDR_WIDTH){1'b0}}, pc};
        end
    endgenerate

    task automatic request_byte(input logic [ADDR_WIDTH-1:0] addr, input state_t return_state);
        begin
            mem_rd_req <= 1'b1;
            mem_rd_addr <= addr;
            read_pending <= 1'b1;
            read_accepted <= 1'b0;
            read_request_addr_debug <= addr;
            read_return_state <= return_state;
            if (return_state == ST_SCAN_ROM_PAYLOAD) begin
                busy <= 1'b1;
                done <= 1'b0;
                scan_payload_read_owner <= 1'b1;
                sega_payload_continue_guard_i <= 1'b1;
                scan_payload_continue_pending_i <= 1'b1;
                scan_payload_req_hold_i <= 1'b1;
                scan_payload_req_addr_i <= addr;
                scan_sticky_guard_debug_i[1] <= 1'b1;
                outstanding_payload_read <= 1'b1;
                outstanding_payload_read_seen_debug_i <= 1'b1;
                last_payload_read_addr <= addr;
                last_payload_read_addr_valid <= 1'b1;
            end else begin
                scan_payload_read_owner <= 1'b0;
            end
            state <= ST_READ_WAIT;
        end
    endtask

    localparam logic [7:0] ERR_NONE = 8'd0;
    localparam logic [7:0] ERR_BAD_MAGIC = 8'd1;
    localparam logic [7:0] ERR_BAD_DATA_START = 8'd2;
    localparam logic [7:0] ERR_PC_RANGE = 8'd3;
    localparam logic [7:0] ERR_UNSUPPORTED_OPCODE = 8'd4;
    localparam logic [7:0] ERR_LOAD = 8'd5;
    localparam logic [7:0] ERR_BAD_DATA_BLOCK = 8'd6;
    localparam logic [7:0] ERR_DATA_BLOCK_RANGE = 8'd7;

    task automatic enter_error(input logic [7:0] error_code);
        begin
            mem_rd_req <= 1'b0;
            scan_payload_read_owner <= 1'b0;
            if (outstanding_payload_read && payload_read_accept_gap) begin
                outstanding_cleared_while_rq_gt_rr_debug_i <= 1'b1;
            end
            outstanding_payload_read <= 1'b0;
            sega_payload_continue_guard_i <= 1'b0;
            scan_payload_continue_pending_i <= 1'b0;
            scan_payload_req_hold_i <= 1'b0;
            scan_sticky_guard_debug_i[5] <= 1'b1;
            busy <= 1'b0;
            done <= 1'b0;
            header_valid <= 1'b0;
            player_error <= 1'b1;
            player_error_code <= error_code;
            error_pc_debug <= pc;
            error_cmd_debug <= cmd;
            final_valid_debug <= 1'b1;
            final_state_debug <= ST_ERROR;
            final_pc_debug <= pc;
            final_cmd_debug <= cmd;
            final_error_code_debug <= error_code;
            if (error_code == ERR_BAD_MAGIC) begin
                final_reason_debug <= STOP_REASON_MAGIC_ERROR;
            end else if (error_code == ERR_UNSUPPORTED_OPCODE) begin
                final_reason_debug <= STOP_REASON_UNSUPPORTED;
            end else if ((error_code == ERR_PC_RANGE) ||
                         (error_code == ERR_BAD_DATA_START) ||
                         (error_code == ERR_BAD_DATA_BLOCK) ||
                         (error_code == ERR_DATA_BLOCK_RANGE)) begin
                final_reason_debug <= STOP_REASON_BOUNDS_EOF;
            end else if (segapcm_rom_copy_overflow) begin
                final_reason_debug <= STOP_REASON_COPY_OVERFLOW;
            end else if (segapcm_rom_scan_overflow) begin
                final_reason_debug <= STOP_REASON_SCAN_OVERFLOW;
            end else begin
                final_reason_debug <= STOP_REASON_OTHER_ERROR;
            end
            state <= ST_ERROR;
        end
    endtask

    task automatic enter_unsupported_error;
        begin
            unsupported_opcode <= cmd;
            unsupported_pc <= pc;
            enter_error(ERR_UNSUPPORTED_OPCODE);
        end
    endtask

    task automatic skip_unsupported_command(input logic [3:0] command_size);
        logic [ADDR_WIDTH-1:0] next_pc;
        begin
            next_pc = pc + {{(ADDR_WIDTH-4){1'b0}}, command_size};
            unsupported_opcode <= cmd;
            unsupported_pc <= pc;
            if (unsupported_command_count != 32'hffff_ffff) begin
                unsupported_command_count <= unsupported_command_count + 32'd1;
            end
            pc <= next_pc;
            current_pc_debug <= next_pc;
            request_byte(next_pc, ST_FETCH_CMD);
        end
    endtask

    task automatic skip_observed_command(input logic [3:0] command_size);
        logic [ADDR_WIDTH-1:0] next_pc;
        begin
            next_pc = pc + {{(ADDR_WIDTH-4){1'b0}}, command_size};
            pc <= next_pc;
            current_pc_debug <= next_pc;
            request_byte(next_pc, ST_FETCH_CMD);
        end
    endtask

    task automatic scan_start_playback;
        begin
            segapcm_rom_scan_busy <= 1'b0;
            segapcm_rom_scan_done <= 1'b1;
            segapcm_rom_copy_flush_done <= 1'b1;
            scan_done_seen_debug <= 1'b1;
            copy_flush_done_seen_debug <= 1'b1;
            playback_started_after_scan_debug <= 1'b1;
            pc_rewound_to_data_start_debug <= 1'b1;
            pc <= data_start_debug;
            current_pc_debug <= data_start_debug;
            request_byte(data_start_debug, ST_FETCH_CMD);
        end
    endtask

    task automatic scan_finish;
        begin
            segapcm_copy_flush_req <= 1'b1;
            scan_payload_read_owner <= 1'b0;
            if (outstanding_payload_read && payload_read_accept_gap) begin
                outstanding_cleared_while_rq_gt_rr_debug_i <= 1'b1;
            end
            outstanding_payload_read <= 1'b0;
            scan_finish_called_debug <= 1'b1;
            scan_transitioned_to_flush_debug <= 1'b1;
            scan_finish_taken_debug_i <= 1'b1;
            scan_term_be_debug_i <= {
                scan_term_be_debug_i[15:8],
                1'b1,
                scan_term_be_debug_i[6:0]
            };
            scan_abort_remaining_low_debug <= scan_payload_remaining[15:0];
            state <= ST_SCAN_FLUSH;
        end
    endtask

    task automatic scan_advance_payload;
        begin
            if (scan_payload_remaining <= 32'd1) begin
                scan_payload_remaining <= 32'd0;
                scan_payload_addr <= 32'd0;
                pc <= block_skip_target;
                current_pc_debug <= block_skip_target;
                request_byte(block_skip_target, ST_SCAN_FETCH_CMD);
            end else begin
                scan_payload_remaining <= scan_payload_remaining - 32'd1;
                scan_payload_addr <= scan_payload_addr + 32'd1;
                request_byte(scan_payload_addr[ADDR_WIDTH-1:0] +
                             {{(ADDR_WIDTH-1){1'b0}}, 1'b1},
                             ST_SCAN_ROM_PAYLOAD);
            end
        end
    endtask

    task automatic scan_skip_command(input logic [4:0] command_size);
        logic [31:0] next_pc_32;
        begin
            next_pc_32 = pc_32 + {27'd0, command_size};
            if ((next_pc_32 >= file_size) || (next_pc_32[31:ADDR_WIDTH] != '0)) begin
                scan_finish();
            end else begin
                pc <= next_pc_32[ADDR_WIDTH-1:0];
                current_pc_debug <= next_pc_32[ADDR_WIDTH-1:0];
                request_byte(next_pc_32[ADDR_WIDTH-1:0], ST_SCAN_FETCH_CMD);
            end
        end
    endtask

    task automatic finish_dac_stream_measurement;
        logic [31:0] cmd_cycles_done;
        logic [31:0] overhead_cycles_done;
        begin
            cmd_cycles_done = dac_stream_cmd_cycles + 32'd1;
            overhead_cycles_done =
                (cmd_cycles_done > dac_stream_cmd_wait_cycles) ?
                (cmd_cycles_done - dac_stream_cmd_wait_cycles) : 32'd0;

            dac_stream_clk_cycles_total <=
                dac_stream_clk_cycles_total + cmd_cycles_done;
            dac_stream_overhead_cycles_total <=
                dac_stream_overhead_cycles_total + overhead_cycles_done;

            if (cmd_cycles_done > max_dac_stream_cmd_cycles) begin
                max_dac_stream_cmd_cycles <= cmd_cycles_done;
            end

            if (dac_stream_wait0_current && (overhead_cycles_done != 32'd0)) begin
                count_wait0_overhead_nonzero <=
                    count_wait0_overhead_nonzero + 32'd1;
            end

            dac_stream_measure_active <= 1'b0;
            dac_stream_wait0_current <= 1'b0;
            dac_stream_cmd_cycles <= 32'd0;
            dac_stream_cmd_wait_cycles <= 32'd0;
        end
    endtask

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            read_return_state <= ST_IDLE;
            pc <= '0;
            read_data <= 8'd0;
            cmd <= 8'd0;
            arg1 <= 8'd0;
            block_type <= 8'd0;
            block_skip_target <= '0;
            data_offset <= 32'd0;
            loop_offset <= 32'd0;
            loop_pc <= '0;
            loop_valid <= 1'b0;
            block_size <= 32'd0;
            pcm_data_start <= 32'd0;
            pcm_data_size <= 32'd0;
            pcm_pos <= 32'd0;
            segapcm_pending_addr <= 16'd0;
            wait_remaining <= 16'd0;
            vgm_wait_tick_d <= 1'b0;
            start_d <= 1'b0;
            mem_rd_req <= 1'b0;
            mem_rd_addr <= '0;
            read_pending <= 1'b0;
            read_accepted <= 1'b0;
            read_ignore_valid_until_low <= 1'b0;
            read_request_addr_debug <= '0;
            read_response_addr_debug <= '0;
            read_valid_consumed <= 1'b0;
            scan_payload_read_owner <= 1'b0;
            outstanding_payload_read <= 1'b0;
            segapcm_copy_active_i <= 1'b0;
            sega_payload_continue_guard_i <= 1'b0;
            scan_payload_continue_pending_i <= 1'b0;
            scan_payload_req_hold_i <= 1'b0;
            scan_payload_req_addr_i <= '0;
            scan_payload_qg_debug_i <= 8'd0;
            scan_payload_sf_debug_i <= 8'd0;
            scan_sticky_guard_debug_i <= 8'd0;
            last_payload_read_addr <= '0;
            last_payload_read_addr_valid <= 1'b0;
            outstanding_payload_read_seen_debug_i <= 1'b0;
            rq_increment_without_outstanding_debug_i <= 1'b0;
            outstanding_cleared_while_rq_gt_rr_debug_i <= 1'b0;
            payload_gap_without_addr_debug_i <= 1'b0;
            read_accept_fire_debug_i <= 1'b0;
            read_accept_rr_increment_debug_i <= 1'b0;
            read_accept_to_read_data_debug_i <= 1'b0;
            read_accept_clear_pending_debug_i <= 1'b0;
            read_data_consumed_debug_i <= 1'b0;
            read_valid_rv_increment_debug_i <= 1'b0;
            payload_byte_valid_pulse_debug_i <= 1'b0;
            read_data_return_to_payload_debug_i <= 1'b0;
            copy_pa_increment_debug_i <= 1'b0;
            copy_ca_increment_debug_i <= 1'b0;
            copy_transition_next_payload_debug_i <= 1'b0;
            scan_abort_reason_debug <= 8'd0;
            final_state_debug <= ST_IDLE;
            final_pc_debug <= '0;
            final_cmd_debug <= 8'd0;
            final_error_code_debug <= ERR_NONE;
            final_valid_debug <= 1'b0;
            final_reason_debug <= STOP_REASON_NONE;
            header_valid_seen_debug <= 1'b0;
            scan_started_seen_debug <= 1'b0;
            scan_done_seen_debug <= 1'b0;
            copy_flush_done_seen_debug <= 1'b0;
            playback_started_after_scan_debug <= 1'b0;
            scan_overflow_seen_debug <= 1'b0;
            copy_overflow_seen_debug <= 1'b0;
            normal_command_fetch_started_debug <= 1'b0;
            scan_finish_called_debug <= 1'b0;
            pc_rewound_to_data_start_debug <= 1'b0;
            status_stop_without_final_reason_debug <= 1'b0;
            scan_final_byte_accepted_debug <= 1'b0;
            scan_transitioned_to_flush_debug <= 1'b0;
            scan_copy_last_index_low_debug_i <= 16'd0;
            scan_copy_req_count_debug_i <= 16'd0;
            scan_copy_ready_count_debug_i <= 16'd0;
            scan_copy_accept_fire_count_debug_i <= 16'd0;
            scan_noncopy_advance_count_debug_i <= 16'd0;
            scan_used_noncopy_advance_during_copy_debug_i <= 1'b0;
            scan_copy_exit_debug_i <= 16'd0;
            scan_copy_exit_pc_debug_i <= 16'd0;
            scan_copy_exit_count_debug_i <= 16'd0;
            scan_copy_read_req_count_debug_i <= 16'd0;
            scan_copy_read_accept_count_debug_i <= 16'd0;
            scan_copy_read_valid_count_debug_i <= 16'd0;
            scan_copy_mem_req_cycle_count_debug_i <= 16'd0;
            scan_copy_mem_req_ready_cycle_count_debug_i <= 16'd0;
            scan_copy_request_gap_debug_i <= 16'd0;
            previous_state_debug_i <= ST_IDLE;
            last_nonzero_state_debug_i <= ST_IDLE;
            return_state_snapshot_debug_i <= ST_IDLE;
            scan_copy_clear_reason_debug_i <= 8'd0;
            scan_copy_payload_pc_debug_i <= 16'd0;
            scan_payload_byte_valid_debug_i <= 1'b0;
            scan_copy_first_byte0_debug_i <= 8'd0;
            scan_copy_first_byte1_debug_i <= 8'd0;
            scan_copy_first_byte2_debug_i <= 8'd0;
            scan_copy_first_byte3_debug_i <= 8'd0;
            scan_copy_first_byte4_debug_i <= 8'd0;
            scan_copy_first_byte5_debug_i <= 8'd0;
            scan_copy_first_byte6_debug_i <= 8'd0;
            scan_copy_first_byte7_debug_i <= 8'd0;
            scan_copy_first_byte8_debug_i <= 8'd0;
            scan_copy_source_phase_debug_i <= 8'd0;
            scan_copy_read_raw_valid_count_debug_i <= 16'd0;
            scan_copy_read_ignored_valid_count_debug_i <= 16'd0;
            scan_term_pl_debug_i <= 16'd0;
            scan_term_rm_debug_i <= 16'd0;
            scan_term_cc_debug_i <= 16'd0;
            scan_term_nx_debug_i <= 16'd0;
            scan_term_be_debug_i <= 16'hBE00;
            scan_sticky_guard_debug_i <= 8'd0;
            scan_abort_remaining_low_debug <= 16'd0;
            scan_current_payload_len_debug <= 32'd0;
            scan_remaining_zero_before_expected_accept_debug_i <= 1'b0;
            first_playback_cmd_after_scan_debug <= 8'd0;
            first_playback_cmds_after_scan_debug_i <= 32'd0;
            first_playback_cmd_count_debug <= 3'd0;
            segapcm_copy_wr_req <= 1'b0;
            segapcm_copy_wr_addr <= 19'd0;
            segapcm_copy_wr_data <= 8'd0;
            segapcm_copy_flush_req <= 1'b0;
            segapcm_payload_tap_valid <= 1'b0;
            segapcm_payload_tap_addr <= 19'd0;
            segapcm_payload_tap_data <= 8'd0;
            segapcm_payload_tap_byte_count_debug <= 32'd0;
            ym_cmd_valid <= 1'b0;
            ym_cmd_port <= 1'b0;
            ym_cmd_reg <= 8'd0;
            ym_cmd_data <= 8'd0;
            psg_cmd_valid <= 1'b0;
            psg_cmd_data <= 8'd0;
            ym2151_cmd_valid <= 1'b0;
            ym2151_cmd_reg <= 8'd0;
            ym2151_cmd_data <= 8'd0;
            segapcm_cmd_valid <= 1'b0;
            segapcm_cmd_addr <= 16'd0;
            segapcm_cmd_data <= 8'd0;
            busy <= 1'b0;
            done <= 1'b0;
            header_valid <= 1'b0;
            player_error <= 1'b0;
            unsupported_opcode <= 8'd0;
            unsupported_pc <= '0;
            player_error_code <= ERR_NONE;
            error_pc_debug <= '0;
            error_cmd_debug <= 8'd0;
            data_start_debug <= '0;
            current_pc_debug <= '0;
            loop_pc_debug <= '0;
            loop_valid_debug <= 1'b0;
            loop_taken_debug <= 1'b0;
            end_command_seen <= 1'b0;
            restarted_from_data_start <= 1'b0;
            pcm_oob <= 1'b0;
            pcm_oob_count <= 32'd0;
            wait_ticks_consumed_debug <= 32'd0;
            dac_stream_cmd_count <= 32'd0;
            dac_stream_wait_samples_total <= 32'd0;
            dac_stream_clk_cycles_total <= 32'd0;
            dac_stream_overhead_cycles_total <= 32'd0;
            max_dac_stream_cmd_cycles <= 32'd0;
            count_wait0_dac_stream_cmd <= 32'd0;
            count_wait0_overhead_nonzero <= 32'd0;
            ym2151_write_count <= 32'd0;
            ym2151_last_reg <= 8'd0;
            ym2151_last_data <= 8'd0;
            unsupported_command_count <= 32'd0;
            segapcm_write_count <= 32'd0;
            segapcm_last_addr <= 16'd0;
            segapcm_last_data <= 8'd0;
            data_block_count <= 32'd0;
            last_data_block_type <= 8'd0;
            last_data_block_size_low <= 16'd0;
            parser_command_count_debug <= 32'd0;
            parser_data_block_count_debug <= 32'd0;
            parser_last_block_type_debug <= 8'd0;
            parser_type00_block_count_debug <= 32'd0;
            parser_type80_block_count_debug <= 32'd0;
            segapcm_rom_block_count <= 32'd0;
            segapcm_last_rom_size <= 32'd0;
            segapcm_last_rom_start <= 32'd0;
            pcm_ram_write_skip_count <= 32'd0;
            segapcm_rom_scan_busy <= 1'b0;
            segapcm_rom_scan_done <= 1'b0;
            segapcm_rom_scan_overflow <= 1'b0;
            segapcm_rom_scan_block_count <= 32'd0;
            segapcm_rom_scan_byte_count <= 32'd0;
            segapcm_rom_scan_checksum32 <= 32'd0;
            segapcm_rom_scan_total_size <= 32'd0;
            segapcm_rom_scan_last_start <= 32'd0;
            segapcm_rom_copy_byte_count <= 32'd0;
            segapcm_rom_copy_overflow <= 1'b0;
            segapcm_rom_copy_flush_done <= 1'b0;
            scan_payload_remaining <= 32'd0;
            scan_payload_addr <= 32'd0;
            scan_copy_addr <= 19'd0;
            scan_copy_data <= 8'd0;
            scan_copy_enabled <= 1'b0;
            scan_copy_req_armed <= 1'b0;
            segapcm_tap_payload_remaining <= 32'd0;
            segapcm_tap_payload_addr <= 32'd0;
            segapcm_tap_payload_index <= 19'd0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_ACTIVE
            segapcm_smoke_ddr_capture_done_i <= 1'b0;
`endif
            dac_stream_measure_active <= 1'b0;
            dac_stream_wait0_current <= 1'b0;
            dac_stream_cmd_cycles <= 32'd0;
            dac_stream_cmd_wait_cycles <= 32'd0;
            done_pc_debug <= '0;
            done_cmd_debug <= 8'd0;
            last_cmd_debug <= 8'd0;
            last_read_byte_debug <= 8'd0;
            header_magic_read_debug <= 32'd0;
            header_magic_fail_index_debug <= 4'hf;
            start_seen_debug <= 1'b0;
            start_edge_seen_debug <= 1'b0;
            start_file_ok_seen_debug <= 1'b0;
            header_request_seen_debug <= 1'b0;
            read_wait_seen_debug <= 1'b0;
            mem_valid_seen_debug <= 1'b0;
            magic_error_seen_debug <= 1'b0;
            entered_idle_after_start_debug <= 1'b0;
            entered_read_data_debug <= 1'b0;
            entered_magic_check_debug <= 1'b0;
            start_level_file_ok_seen_debug <= 1'b0;
        end else begin
            vgm_wait_tick_d <= vgm_wait_tick;
            start_d <= start;
            ym_cmd_valid <= 1'b0;
            psg_cmd_valid <= 1'b0;
            ym2151_cmd_valid <= 1'b0;
            segapcm_cmd_valid <= 1'b0;
            segapcm_copy_wr_req <= 1'b0;
            segapcm_copy_flush_req <= 1'b0;
            segapcm_payload_tap_valid <= 1'b0;
            read_valid_consumed <= 1'b0;
            read_accept_fire_debug_i <= 1'b0;
            read_accept_rr_increment_debug_i <= 1'b0;
            read_accept_to_read_data_debug_i <= 1'b0;
            read_accept_clear_pending_debug_i <= 1'b0;
            read_data_consumed_debug_i <= 1'b0;
            read_valid_rv_increment_debug_i <= 1'b0;
            payload_byte_valid_pulse_debug_i <= 1'b0;
            read_data_return_to_payload_debug_i <= 1'b0;
            copy_pa_increment_debug_i <= 1'b0;
            copy_ca_increment_debug_i <= 1'b0;
            copy_transition_next_payload_debug_i <= 1'b0;
            scan_finish_taken_debug_i <= 1'b0;

            previous_state_debug_i <= state;
            if (state != ST_IDLE) begin
                last_nonzero_state_debug_i <= state;
            end
            return_state_snapshot_debug_i <= read_return_state;

            if (segapcm_copy_active_i &&
                (scan_payload_remaining != 32'd0) &&
                !((state == ST_SEGAPCM_COPY_READ_WAIT) ||
                  (state == ST_SEGAPCM_COPY_READ_DATA) ||
                  (state == ST_SEGAPCM_COPY_WRITE))) begin
                scan_payload_sf_debug_i[5] <= 1'b1;
                if (state == ST_SCAN_FETCH_CMD) begin
                    scan_payload_sf_debug_i[6] <= 1'b1;
                end
                if (state == ST_IDLE) begin
                    scan_payload_sf_debug_i[7] <= 1'b1;
                end
            end

            if (qg_payload_req_asserted) begin
                scan_payload_qg_debug_i[1] <= 1'b1;
            end
            if (scan_payload_req_hold_i) begin
                scan_payload_qg_debug_i[2] <= 1'b1;
            end
            if (qg_payload_hold_driven) begin
                scan_payload_qg_debug_i[3] <= 1'b1;
            end
            if (qg_backend_read_accept_seen) begin
                scan_payload_qg_debug_i[4] <= 1'b1;
            end
            if (qg_backend_request_blocked) begin
                scan_payload_qg_debug_i[5] <= 1'b1;
            end
            if (qg_request_owner_is_payload) begin
                scan_payload_qg_debug_i[6] <= 1'b1;
            end
            if (qg_payload_addr_invalid) begin
                scan_payload_qg_debug_i[7] <= 1'b1;
            end

            if (start) begin
                start_seen_debug <= 1'b1;
            end

            if (start_edge) begin
                start_edge_seen_debug <= 1'b1;
            end

            if (sega_payload_continue_guard_set) begin
                sega_payload_continue_guard_i <= 1'b1;
                if (sega_payload_continue_pending ||
                    (scan_payload_remaining != 32'd0) ||
                    (segapcm_rom_copy_byte_count <
                     scan_current_payload_len_debug)) begin
                    scan_sticky_guard_debug_i[2] <= 1'b1;
                end
            end else if (sega_payload_continue_guard_clear) begin
                sega_payload_continue_guard_i <= 1'b0;
                scan_sticky_guard_debug_i[4] <= 1'b1;
            end

            if (sega_payload_continue_guard &&
                ((scan_payload_remaining != 32'd0) ||
                 sega_payload_continue_pending)) begin
                scan_sticky_guard_debug_i[2] <= 1'b1;
            end

            if (read_pending &&
                read_accepted &&
                !read_ignore_valid_until_low &&
                mem_rd_valid) begin
                mem_valid_seen_debug <= 1'b1;
                last_read_byte_debug <= mem_rd_data;
                read_valid_consumed <= 1'b1;
            end

            if (qg_payload_req_asserted &&
                read_pending &&
                (scan_copy_mem_req_cycle_count_debug_i != 16'hffff)) begin
                scan_copy_mem_req_cycle_count_debug_i <=
                    scan_copy_mem_req_cycle_count_debug_i + 16'd1;
            end

            if (qg_payload_req_asserted &&
                read_pending &&
                mem_rd_ready &&
                (scan_copy_mem_req_ready_cycle_count_debug_i !=
                 16'hffff)) begin
                scan_copy_mem_req_ready_cycle_count_debug_i <=
                    scan_copy_mem_req_ready_cycle_count_debug_i + 16'd1;
            end

            if ((scan_copy_request_gap_debug_i == 16'd0) &&
                (outstanding_payload_read ||
                 (read_return_state == ST_SCAN_ROM_PAYLOAD) ||
                 scan_payload_read_owner) &&
                payload_read_accept_gap &&
                (read_pending || mem_rd_req ||
                 (state == ST_IDLE) ||
                 (state == ST_READ_WAIT) ||
                 (state == ST_READ_DATA))) begin
                scan_copy_request_gap_debug_i <= scan_copy_request_state_live;
            end

            if ((outstanding_payload_read ||
                 (read_return_state == ST_SCAN_ROM_PAYLOAD) ||
                 scan_payload_read_owner) &&
                payload_read_accept_gap) begin
                if (state == ST_IDLE) begin
                    scan_copy_clear_reason_debug_i[5] <= 1'b1;
                    scan_sticky_guard_debug_i[7] <= 1'b1;
                end
                if (!read_pending) begin
                    scan_copy_clear_reason_debug_i[6] <= 1'b1;
                end
                if (!mem_rd_req && !read_accepted) begin
                    scan_copy_clear_reason_debug_i[7] <= 1'b1;
                end
            end

            if (sega_payload_copy_active &&
                payload_read_accept_gap &&
                !outstanding_payload_read) begin
                rq_increment_without_outstanding_debug_i <= 1'b1;
            end

            if (payload_read_accept_gap &&
                !last_payload_read_addr_valid) begin
                payload_gap_without_addr_debug_i <= 1'b1;
            end

            if (header_valid) begin
                header_valid_seen_debug <= 1'b1;
            end
            if (segapcm_rom_scan_done) begin
                scan_done_seen_debug <= 1'b1;
            end
            if (segapcm_rom_copy_flush_done) begin
                copy_flush_done_seen_debug <= 1'b1;
            end
            if (segapcm_rom_scan_overflow) begin
                scan_overflow_seen_debug <= 1'b1;
            end
            if (segapcm_rom_copy_overflow) begin
                copy_overflow_seen_debug <= 1'b1;
            end
            if (start_seen_debug &&
                !busy &&
                !done &&
                !player_error &&
                sega_payload_continue_guard &&
                (final_reason_debug == STOP_REASON_NONE)) begin
                scan_sticky_guard_debug_i[3] <= 1'b1;
            end

            if (start_seen_debug &&
                !busy &&
                !done &&
                !player_error &&
                !sega_payload_continue_guard &&
                (final_reason_debug == STOP_REASON_NONE)) begin
                scan_sticky_guard_debug_i[6] <= 1'b1;
                status_stop_without_final_reason_debug <= 1'b1;
                if (scan_copy_read_req_count_debug_i >
                    scan_copy_read_accept_count_debug_i) begin
                    scan_copy_clear_reason_debug_i[3] <= 1'b1;
                end
            end

            if (dac_stream_measure_active) begin
                dac_stream_cmd_cycles <= dac_stream_cmd_cycles + 32'd1;
                if ((state == ST_WAIT_SAMPLES) && (wait_remaining != 16'd0)) begin
                    dac_stream_cmd_wait_cycles <=
                        dac_stream_cmd_wait_cycles + 32'd1;
                end
            end

            if (load_error || overflow_error) begin
                mem_rd_req <= 1'b0;
                read_pending <= 1'b0;
                read_accepted <= 1'b0;
                read_ignore_valid_until_low <= 1'b0;
                outstanding_payload_read <= 1'b0;
                segapcm_copy_active_i <= 1'b0;
                sega_payload_continue_guard_i <= 1'b0;
                scan_payload_continue_pending_i <= 1'b0;
                scan_payload_req_hold_i <= 1'b0;
                scan_sticky_guard_debug_i[5] <= 1'b1;
                if (outstanding_payload_read && payload_read_accept_gap) begin
                    outstanding_cleared_while_rq_gt_rr_debug_i <= 1'b1;
                end
                scan_copy_clear_reason_debug_i[2] <= 1'b1;
                busy <= 1'b0;
                done <= 1'b0;
                header_valid <= 1'b0;
                player_error <= 1'b1;
                player_error_code <= ERR_LOAD;
                error_pc_debug <= pc;
                error_cmd_debug <= cmd;
                final_valid_debug <= 1'b1;
                final_state_debug <= ST_ERROR;
                final_pc_debug <= pc;
                final_cmd_debug <= cmd;
                final_error_code_debug <= ERR_LOAD;
                final_reason_debug <= STOP_REASON_OTHER_ERROR;
                state <= ST_IDLE;
            end else if (!segapcm_copy_active_i &&
                         scan_payload_req_hold_i &&
                         !read_accepted &&
                         (state != ST_READ_WAIT) &&
                         !segapcm_rom_scan_done) begin
                busy <= 1'b1;
                done <= 1'b0;
                mem_rd_req <= 1'b1;
                mem_rd_addr <= scan_payload_req_addr_i;
                read_pending <= 1'b1;
                read_ignore_valid_until_low <= 1'b0;
                read_return_state <= ST_SCAN_ROM_PAYLOAD;
                scan_payload_read_owner <= 1'b1;
                outstanding_payload_read <= 1'b1;
                outstanding_payload_read_seen_debug_i <= 1'b1;
                last_payload_read_addr <= scan_payload_req_addr_i;
                last_payload_read_addr_valid <= 1'b1;
                scan_copy_req_armed <= 1'b0;
                state <= ST_READ_WAIT;
            end else if (!segapcm_copy_active_i &&
                         (payload_read_recovery_needed ||
                          (sega_payload_continue_guard_i &&
                           (state == ST_IDLE) &&
                           (last_payload_read_addr_valid || payload_read_accept_gap)) ||
                          (scan_payload_continue_pending_i &&
                           (state == ST_IDLE) &&
                           (scan_payload_remaining != 32'd0))) &&
                         !segapcm_rom_scan_done) begin
                busy <= 1'b1;
                done <= 1'b0;
                mem_rd_req <= 1'b1;
                if (last_payload_read_addr_valid) begin
                    mem_rd_addr <= last_payload_read_addr;
                end else if (scan_payload_continue_pending_i) begin
                    mem_rd_addr <= scan_payload_addr[ADDR_WIDTH-1:0];
                    last_payload_read_addr <=
                        scan_payload_addr[ADDR_WIDTH-1:0];
                    last_payload_read_addr_valid <= 1'b1;
                    if (!payload_read_accept_gap &&
                        (scan_copy_read_req_count_debug_i != 16'hffff)) begin
                        scan_copy_read_req_count_debug_i <=
                            scan_copy_read_req_count_debug_i + 16'd1;
                        scan_payload_qg_debug_i[0] <= 1'b1;
                        if (state != ST_SEGAPCM_COPY_READ_WAIT) begin
                            scan_payload_sf_debug_i[4] <= 1'b1;
                        end
                    end
                end
                read_pending <= 1'b1;
                read_accepted <= 1'b0;
                read_ignore_valid_until_low <= 1'b0;
                read_return_state <= ST_SCAN_ROM_PAYLOAD;
                scan_payload_read_owner <= 1'b1;
                outstanding_payload_read <= 1'b1;
                outstanding_payload_read_seen_debug_i <= 1'b1;
                scan_copy_req_armed <= 1'b0;
                if (state == ST_IDLE) begin
                    scan_copy_clear_reason_debug_i[5] <= 1'b1;
                    scan_sticky_guard_debug_i[7] <= 1'b1;
                end
                if (!read_pending) begin
                    scan_copy_clear_reason_debug_i[6] <= 1'b1;
                end
                if (!mem_rd_req && !read_accepted) begin
                    scan_copy_clear_reason_debug_i[7] <= 1'b1;
                end
                state <= ST_READ_WAIT;
            end else if (!segapcm_copy_active_i &&
                         sega_payload_copy_active &&
                         payload_read_accept_gap &&
                         !last_payload_read_addr_valid) begin
                payload_gap_without_addr_debug_i <= 1'b1;
                player_error <= 1'b1;
                player_error_code <= ERR_DATA_BLOCK_RANGE;
                final_valid_debug <= 1'b1;
                final_state_debug <= ST_ERROR;
                final_error_code_debug <= ERR_DATA_BLOCK_RANGE;
                final_reason_debug <= STOP_REASON_BOUNDS_EOF;
                state <= ST_ERROR;
            end else begin
                case (state)
                    ST_IDLE: begin
                        if (start_seen_debug &&
                            sega_payload_continue_guard) begin
                            scan_sticky_guard_debug_i[3] <= 1'b1;
                        end
                        if (start_seen_debug &&
                            !sega_payload_continue_guard) begin
                            scan_sticky_guard_debug_i[6] <= 1'b1;
                            entered_idle_after_start_debug <= 1'b1;
                        end
                        busy <= 1'b0;
                        done <= 1'b0;
                        if (sega_payload_work_active) begin
                            busy <= 1'b1;
                            done <= 1'b0;
                        end
                        if (scan_payload_read_owner &&
                            (scan_copy_read_req_count_debug_i >
                             scan_copy_read_accept_count_debug_i)) begin
                            busy <= 1'b1;
                            done <= 1'b0;
                            mem_rd_req <= 1'b1;
                            if (last_payload_read_addr_valid) begin
                                mem_rd_addr <= last_payload_read_addr;
                            end else begin
                                payload_gap_without_addr_debug_i <= 1'b1;
                                player_error <= 1'b1;
                                player_error_code <= ERR_DATA_BLOCK_RANGE;
                            end
                            read_pending <= 1'b1;
                            read_accepted <= 1'b0;
                            read_return_state <= ST_SCAN_ROM_PAYLOAD;
                            outstanding_payload_read <= 1'b1;
                            outstanding_payload_read_seen_debug_i <= 1'b1;
                            scan_copy_clear_reason_debug_i[5] <= 1'b1;
                            state <= ST_READ_WAIT;
                        end else if (start_request && file_ok &&
                                     !sega_payload_work_active) begin
                            start_file_ok_seen_debug <= 1'b1;
                            if (YM2151_MODE && start && !start_edge && !load_done_pulse) begin
                                start_level_file_ok_seen_debug <= 1'b1;
                            end
                            header_request_seen_debug <= 1'b1;
                            busy <= 1'b1;
                            header_valid <= 1'b0;
                            player_error <= 1'b0;
                            unsupported_opcode <= 8'd0;
                            unsupported_pc <= '0;
                            player_error_code <= ERR_NONE;
                            error_pc_debug <= '0;
                            error_cmd_debug <= 8'd0;
                            done_pc_debug <= '0;
                            done_cmd_debug <= 8'd0;
                            header_magic_read_debug <= 32'd0;
                            header_magic_fail_index_debug <= 4'hf;
                            read_data <= 8'd0;
                            mem_rd_req <= 1'b0;
                            mem_rd_addr <= '0;
                            read_pending <= 1'b0;
                            read_accepted <= 1'b0;
                            read_ignore_valid_until_low <= 1'b0;
                            read_request_addr_debug <= '0;
                            read_response_addr_debug <= '0;
                            read_valid_consumed <= 1'b0;
                            scan_payload_read_owner <= 1'b0;
                            outstanding_payload_read <= 1'b0;
                            segapcm_copy_active_i <= 1'b0;
                            sega_payload_continue_guard_i <= 1'b0;
                            scan_payload_continue_pending_i <= 1'b0;
                            scan_payload_req_hold_i <= 1'b0;
                            scan_payload_req_addr_i <= '0;
                            scan_payload_qg_debug_i <= 8'd0;
                            scan_payload_sf_debug_i <= 8'd0;
                            scan_sticky_guard_debug_i <= 8'd0;
                            last_payload_read_addr <= '0;
                            last_payload_read_addr_valid <= 1'b0;
                            scan_abort_reason_debug <= 8'd0;
                            final_state_debug <= ST_IDLE;
                            final_pc_debug <= '0;
                            final_cmd_debug <= 8'd0;
                            final_error_code_debug <= ERR_NONE;
                            final_valid_debug <= 1'b0;
                            final_reason_debug <= STOP_REASON_NONE;
                            header_valid_seen_debug <= 1'b0;
                            scan_started_seen_debug <= 1'b0;
                            scan_done_seen_debug <= 1'b0;
                            copy_flush_done_seen_debug <= 1'b0;
                            playback_started_after_scan_debug <= 1'b0;
                            scan_overflow_seen_debug <= 1'b0;
                            copy_overflow_seen_debug <= 1'b0;
                            normal_command_fetch_started_debug <= 1'b0;
                            scan_finish_called_debug <= 1'b0;
                            pc_rewound_to_data_start_debug <= 1'b0;
                            status_stop_without_final_reason_debug <= 1'b0;
                            scan_final_byte_accepted_debug <= 1'b0;
                            scan_transitioned_to_flush_debug <= 1'b0;
                            scan_copy_last_index_low_debug_i <= 16'd0;
                            scan_copy_req_count_debug_i <= 16'd0;
                            scan_copy_ready_count_debug_i <= 16'd0;
                            scan_copy_accept_fire_count_debug_i <= 16'd0;
                            scan_noncopy_advance_count_debug_i <= 16'd0;
                            scan_used_noncopy_advance_during_copy_debug_i <=
                                1'b0;
                            scan_copy_exit_debug_i <= 16'd0;
                            scan_copy_exit_pc_debug_i <= 16'd0;
                            scan_copy_exit_count_debug_i <= 16'd0;
                            scan_copy_read_req_count_debug_i <= 16'd0;
                            scan_copy_read_accept_count_debug_i <= 16'd0;
                            scan_copy_read_valid_count_debug_i <= 16'd0;
                            scan_copy_mem_req_cycle_count_debug_i <= 16'd0;
                            scan_copy_mem_req_ready_cycle_count_debug_i <=
                                16'd0;
                            scan_copy_request_gap_debug_i <= 16'd0;
                            previous_state_debug_i <= ST_IDLE;
                            last_nonzero_state_debug_i <= ST_IDLE;
                            return_state_snapshot_debug_i <= ST_IDLE;
                            scan_copy_clear_reason_debug_i <= 8'd0;
                            outstanding_payload_read_seen_debug_i <= 1'b0;
                            rq_increment_without_outstanding_debug_i <= 1'b0;
                            outstanding_cleared_while_rq_gt_rr_debug_i <= 1'b0;
                            payload_gap_without_addr_debug_i <= 1'b0;
                            scan_copy_payload_pc_debug_i <= 16'd0;
                            scan_payload_byte_valid_debug_i <= 1'b0;
                            scan_copy_first_byte0_debug_i <= 8'd0;
                            scan_copy_first_byte1_debug_i <= 8'd0;
                            scan_copy_first_byte2_debug_i <= 8'd0;
                            scan_copy_first_byte3_debug_i <= 8'd0;
                            scan_copy_first_byte4_debug_i <= 8'd0;
                            scan_copy_first_byte5_debug_i <= 8'd0;
                            scan_copy_first_byte6_debug_i <= 8'd0;
                            scan_copy_first_byte7_debug_i <= 8'd0;
                            scan_copy_first_byte8_debug_i <= 8'd0;
                            scan_copy_source_phase_debug_i <= 8'd0;
                            scan_copy_read_raw_valid_count_debug_i <= 16'd0;
                            scan_copy_read_ignored_valid_count_debug_i <=
                                16'd0;
                            scan_term_pl_debug_i <= 16'd0;
                            scan_term_rm_debug_i <= 16'd0;
                            scan_term_cc_debug_i <= 16'd0;
                            scan_term_nx_debug_i <= 16'd0;
                            scan_term_be_debug_i <= 16'hBE00;
                            scan_abort_remaining_low_debug <= 16'd0;
                            scan_current_payload_len_debug <= 32'd0;
                            scan_remaining_zero_before_expected_accept_debug_i <= 1'b0;
                            first_playback_cmd_after_scan_debug <= 8'd0;
                            first_playback_cmds_after_scan_debug_i <= 32'd0;
                            first_playback_cmd_count_debug <= 3'd0;
                            data_offset <= 32'd0;
                            loop_offset <= 32'd0;
                            loop_pc <= '0;
                            loop_valid <= 1'b0;
                            loop_pc_debug <= '0;
                            loop_valid_debug <= 1'b0;
                            loop_taken_debug <= 1'b0;
                            end_command_seen <= 1'b0;
                            restarted_from_data_start <= 1'b0;
                            pcm_oob <= 1'b0;
                            pcm_oob_count <= 32'd0;
                            wait_ticks_consumed_debug <= 32'd0;
                            dac_stream_cmd_count <= 32'd0;
                            dac_stream_wait_samples_total <= 32'd0;
                            dac_stream_clk_cycles_total <= 32'd0;
                            dac_stream_overhead_cycles_total <= 32'd0;
                            max_dac_stream_cmd_cycles <= 32'd0;
                            count_wait0_dac_stream_cmd <= 32'd0;
                            count_wait0_overhead_nonzero <= 32'd0;
                            ym2151_write_count <= 32'd0;
                            ym2151_last_reg <= 8'd0;
                            ym2151_last_data <= 8'd0;
                            unsupported_command_count <= 32'd0;
                            segapcm_write_count <= 32'd0;
                            segapcm_last_addr <= 16'd0;
                            segapcm_last_data <= 8'd0;
                            data_block_count <= 32'd0;
                            last_data_block_type <= 8'd0;
                            last_data_block_size_low <= 16'd0;
                            parser_command_count_debug <= 32'd0;
                            parser_data_block_count_debug <= 32'd0;
                            parser_last_block_type_debug <= 8'd0;
                            parser_type00_block_count_debug <= 32'd0;
                            parser_type80_block_count_debug <= 32'd0;
                            segapcm_rom_block_count <= 32'd0;
                            segapcm_last_rom_size <= 32'd0;
                            segapcm_last_rom_start <= 32'd0;
                            pcm_ram_write_skip_count <= 32'd0;
                            segapcm_rom_scan_busy <= 1'b0;
                            segapcm_rom_scan_done <= 1'b0;
                            segapcm_rom_scan_overflow <= 1'b0;
                            segapcm_rom_scan_block_count <= 32'd0;
                            segapcm_rom_scan_byte_count <= 32'd0;
                            segapcm_rom_scan_checksum32 <= 32'd0;
                            segapcm_rom_scan_total_size <= 32'd0;
                            segapcm_rom_scan_last_start <= 32'd0;
                            segapcm_rom_copy_byte_count <= 32'd0;
                            segapcm_rom_copy_overflow <= 1'b0;
                            segapcm_rom_copy_flush_done <= 1'b0;
                            segapcm_payload_tap_valid <= 1'b0;
                            segapcm_payload_tap_addr <= 19'd0;
                            segapcm_payload_tap_data <= 8'd0;
                            segapcm_payload_tap_byte_count_debug <= 32'd0;
                            scan_payload_remaining <= 32'd0;
                            scan_payload_addr <= 32'd0;
                            scan_copy_addr <= 19'd0;
                            scan_copy_data <= 8'd0;
                            scan_copy_enabled <= 1'b0;
                            scan_copy_req_armed <= 1'b0;
                            segapcm_tap_payload_remaining <= 32'd0;
                            segapcm_tap_payload_addr <= 32'd0;
                            segapcm_tap_payload_index <= 19'd0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_ACTIVE
                            segapcm_smoke_ddr_capture_done_i <= 1'b0;
`endif
                            dac_stream_measure_active <= 1'b0;
                            dac_stream_wait0_current <= 1'b0;
                            dac_stream_cmd_cycles <= 32'd0;
                            dac_stream_cmd_wait_cycles <= 32'd0;
                            block_size <= 32'd0;
                            block_type <= 8'd0;
                            pcm_data_start <= 32'd0;
                            pcm_data_size <= 32'd0;
                            pcm_pos <= 32'd0;
                            request_byte('0, ST_CHECK_MAGIC0);
                        end
                    end

                    ST_READ_WAIT: begin
                        read_wait_seen_debug <= 1'b1;
                        if (scan_payload_read_owner && !read_pending) begin
                            read_pending <= 1'b1;
                            read_return_state <= ST_SCAN_ROM_PAYLOAD;
                            if (scan_payload_req_hold_i) begin
                                mem_rd_addr <= scan_payload_req_addr_i;
                            end
                            scan_copy_clear_reason_debug_i[6] <= 1'b1;
                        end
                        if ((read_pending || scan_payload_read_owner ||
                             scan_payload_req_hold_i) &&
                            !read_accepted) begin
                            mem_rd_req <= 1'b1;
                            if (scan_payload_req_hold_i) begin
                                mem_rd_addr <= scan_payload_req_addr_i;
                                read_return_state <= ST_SCAN_ROM_PAYLOAD;
                            end
                        end
                        if ((read_pending || scan_payload_read_owner ||
                             scan_payload_req_hold_i) &&
                            mem_rd_req &&
                            mem_rd_ready) begin
                            read_accept_fire_debug_i <= 1'b1;
                            read_accept_to_read_data_debug_i <= 1'b1;
                            if ((read_return_state == ST_SCAN_ROM_PAYLOAD) &&
                                (scan_copy_read_accept_count_debug_i !=
                                 16'hffff)) begin
                                read_accept_rr_increment_debug_i <= 1'b1;
                                scan_copy_read_accept_count_debug_i <=
                                    scan_copy_read_accept_count_debug_i +
                                    16'd1;
                            end
                            mem_rd_req <= 1'b0;
                            if (read_return_state == ST_SCAN_ROM_PAYLOAD) begin
                                scan_payload_req_hold_i <= 1'b0;
                            end
                            read_accepted <= 1'b1;
                            read_ignore_valid_until_low <= mem_rd_valid;
                            read_response_addr_debug <= mem_rd_addr;
                            state <= ST_READ_DATA;
                        end
                    end

                    ST_READ_DATA: begin
                        entered_read_data_debug <= 1'b1;
                        if (read_pending &&
                            read_accepted &&
                            (read_return_state == ST_SCAN_ROM_PAYLOAD) &&
                            mem_rd_valid &&
                            (scan_copy_read_raw_valid_count_debug_i !=
                             16'hffff)) begin
                            scan_copy_read_raw_valid_count_debug_i <=
                                scan_copy_read_raw_valid_count_debug_i +
                                16'd1;
                        end
                        if (read_pending &&
                            read_accepted &&
                            read_ignore_valid_until_low) begin
                            if (mem_rd_valid &&
                                (read_return_state == ST_SCAN_ROM_PAYLOAD) &&
                                (scan_copy_read_ignored_valid_count_debug_i !=
                                 16'hffff)) begin
                                scan_copy_read_ignored_valid_count_debug_i <=
                                    scan_copy_read_ignored_valid_count_debug_i +
                                    16'd1;
                            end
                            read_ignore_valid_until_low <= 1'b0;
                        end else if (read_pending &&
                                     read_accepted &&
                                     mem_rd_valid) begin
                            read_data_consumed_debug_i <= 1'b1;
                            read_data <= mem_rd_data;
                            read_pending <= 1'b0;
                            read_accepted <= 1'b0;
                            if (read_return_state == ST_SCAN_ROM_PAYLOAD) begin
                                read_data_return_to_payload_debug_i <= 1'b1;
                                scan_payload_read_owner <= 1'b0;
                                if (outstanding_payload_read &&
                                    payload_read_accept_gap) begin
                                    outstanding_cleared_while_rq_gt_rr_debug_i <=
                                        1'b1;
                                end
                                outstanding_payload_read <= 1'b0;
                                last_payload_read_addr_valid <= 1'b0;
                                scan_copy_clear_reason_debug_i[0] <= 1'b1;
                            end
                            state <= read_return_state;
                        end
                    end

                    ST_CHECK_MAGIC0: begin
                        entered_magic_check_debug <= 1'b1;
                        header_magic_read_debug[7:0] <= read_data;
                        if (read_data == 8'h56) begin
                            request_byte({{(ADDR_WIDTH-1){1'b0}}, 1'b1}, ST_CHECK_MAGIC1);
                        end else begin
                            magic_error_seen_debug <= 1'b1;
                            header_magic_fail_index_debug <= 4'd0;
                            enter_error(ERR_BAD_MAGIC);
                        end
                    end

                    ST_CHECK_MAGIC1: begin
                        header_magic_read_debug[15:8] <= read_data;
                        if (read_data == 8'h67) begin
                            request_byte({{(ADDR_WIDTH-2){1'b0}}, 2'd2}, ST_CHECK_MAGIC2);
                        end else begin
                            magic_error_seen_debug <= 1'b1;
                            header_magic_fail_index_debug <= 4'd1;
                            enter_error(ERR_BAD_MAGIC);
                        end
                    end

                    ST_CHECK_MAGIC2: begin
                        header_magic_read_debug[23:16] <= read_data;
                        if (read_data == 8'h6d) begin
                            request_byte({{(ADDR_WIDTH-2){1'b0}}, 2'd3}, ST_CHECK_MAGIC3);
                        end else begin
                            magic_error_seen_debug <= 1'b1;
                            header_magic_fail_index_debug <= 4'd2;
                            enter_error(ERR_BAD_MAGIC);
                        end
                    end

                    ST_CHECK_MAGIC3: begin
                        header_magic_read_debug[31:24] <= read_data;
                        if (read_data == 8'h20) begin
                            request_byte({{(ADDR_WIDTH-5){1'b0}}, 5'h1c}, ST_READ_LOOP0);
                        end else begin
                            magic_error_seen_debug <= 1'b1;
                            header_magic_fail_index_debug <= 4'd3;
                            enter_error(ERR_BAD_MAGIC);
                        end
                    end

                    ST_READ_LOOP0: begin
                        loop_offset[7:0] <= read_data;
                        request_byte({{(ADDR_WIDTH-5){1'b0}}, 5'h1d}, ST_READ_LOOP1);
                    end

                    ST_READ_LOOP1: begin
                        loop_offset[15:8] <= read_data;
                        request_byte({{(ADDR_WIDTH-5){1'b0}}, 5'h1e}, ST_READ_LOOP2);
                    end

                    ST_READ_LOOP2: begin
                        loop_offset[23:16] <= read_data;
                        request_byte({{(ADDR_WIDTH-5){1'b0}}, 5'h1f}, ST_READ_LOOP3);
                    end

                    ST_READ_LOOP3: begin
                        loop_offset[31:24] <= read_data;
                        if (selected_loop_valid) begin
                            loop_pc <= selected_loop_pc[ADDR_WIDTH-1:0];
                            loop_pc_debug <= selected_loop_pc[ADDR_WIDTH-1:0];
                            loop_valid <= 1'b1;
                            loop_valid_debug <= 1'b1;
                        end else begin
                            loop_pc <= '0;
                            loop_pc_debug <= '0;
                            loop_valid <= 1'b0;
                            loop_valid_debug <= 1'b0;
                        end
                        request_byte({{(ADDR_WIDTH-6){1'b0}}, 6'h34}, ST_READ_OFF0);
                    end

                    ST_READ_OFF0: begin
                        data_offset[7:0] <= read_data;
                        request_byte({{(ADDR_WIDTH-6){1'b0}}, 6'h35}, ST_READ_OFF1);
                    end

                    ST_READ_OFF1: begin
                        data_offset[15:8] <= read_data;
                        request_byte({{(ADDR_WIDTH-6){1'b0}}, 6'h36}, ST_READ_OFF2);
                    end

                    ST_READ_OFF2: begin
                        data_offset[23:16] <= read_data;
                        request_byte({{(ADDR_WIDTH-6){1'b0}}, 6'h37}, ST_READ_OFF3);
                    end

                    ST_READ_OFF3: begin
                        data_offset[31:24] <= read_data;
                        if (!selected_data_start_in_range) begin
                            enter_error(ERR_BAD_DATA_START);
                        end else begin
                            pc <= selected_data_start[ADDR_WIDTH-1:0];
                            data_start_debug <= selected_data_start[ADDR_WIDTH-1:0];
                            current_pc_debug <= selected_data_start[ADDR_WIDTH-1:0];
                            restarted_from_data_start <= 1'b1;
                            header_valid <= 1'b1;
                            header_valid_seen_debug <= 1'b1;
                            if (YM2151_MODE && !SEGAPCM_FM_ONLY_RESTORE) begin
                                segapcm_rom_scan_busy <= 1'b1;
                                segapcm_rom_scan_done <= 1'b0;
                                scan_started_seen_debug <= 1'b1;
                                pc <= selected_data_start[ADDR_WIDTH-1:0];
                                request_byte(selected_data_start[ADDR_WIDTH-1:0],
                                             ST_SCAN_FETCH_CMD);
                            end else begin
                                if (YM2151_MODE) begin
                                    segapcm_rom_scan_busy <= 1'b0;
                                    segapcm_rom_scan_done <= 1'b1;
                                    playback_started_after_scan_debug <= 1'b1;
                                end
                                request_byte(selected_data_start[ADDR_WIDTH-1:0],
                                             ST_FETCH_CMD);
                            end
                        end
                    end

                    ST_SCAN_FETCH_CMD: begin
                        cmd <= read_data;
                        last_cmd_debug <= read_data;
                        current_pc_debug <= pc;
                        if (parser_command_count_debug != 32'hffff_ffff) begin
                            parser_command_count_debug <=
                                parser_command_count_debug + 32'd1;
                        end
                        state <= ST_SCAN_DECODE;
                    end

                    ST_SCAN_DECODE: begin
                        if (!pc_in_range) begin
                            scan_abort_reason_debug <= 8'h01;
                            scan_finish();
                        end else begin
                            case (cmd)
                                8'h66: begin
                                    scan_abort_reason_debug <= 8'h02;
                                    scan_finish();
                                end

                                8'h67: begin
                                    request_byte(pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1},
                                                 ST_SCAN_BLOCK_MARKER);
                                end

                                8'h68: begin
                                    scan_skip_command(5'd12);
                                end

                                8'h50, 8'h30, 8'h31, 8'h4F, 8'h4E: begin
                                    scan_skip_command(5'd2);
                                end

                                8'h51, 8'h52, 8'h53, 8'h54, 8'h55, 8'h56,
                                8'h57, 8'h58, 8'h59, 8'h5A, 8'h5B, 8'h5C,
                                8'h5E, 8'h5F, 8'h61, 8'hA0: begin
                                    scan_skip_command(5'd3);
                                end

                                8'h62, 8'h63: begin
                                    scan_skip_command(5'd1);
                                end

                                8'hE0: begin
                                    scan_skip_command(5'd5);
                                end

                                8'h90, 8'h91, 8'h95: begin
                                    scan_skip_command(5'd5);
                                end

                                8'h92: begin
                                    scan_skip_command(5'd6);
                                end

                                8'h93: begin
                                    scan_skip_command(5'd11);
                                end

                                8'h94: begin
                                    scan_skip_command(5'd2);
                                end

                                8'hC0: begin
                                    scan_skip_command(5'd4);
                                end

                                default: begin
                                    if ((cmd[7:4] == 4'h7) ||
                                        (cmd[7:4] == 4'h8)) begin
                                        scan_skip_command(5'd1);
                                    end else if (cmd[7:4] == 4'hB) begin
                                        scan_skip_command(5'd3);
                                    end else if ((cmd[7:4] == 4'hC) ||
                                                 (cmd[7:4] == 4'hD)) begin
                                        scan_skip_command(5'd4);
                                    end else if ((cmd >= 8'h3F) && (cmd <= 8'h4D)) begin
                                        scan_skip_command(5'd2);
                                    end else begin
                                        segapcm_rom_scan_overflow <= 1'b1;
                                        scan_abort_reason_debug <= 8'h03;
                                        scan_finish();
                                    end
                                end
                            endcase
                        end
                    end

                    ST_SCAN_BLOCK_MARKER: begin
                        if (read_data == 8'h66) begin
                            request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2},
                                         ST_SCAN_BLOCK_TYPE);
                        end else begin
                            segapcm_rom_scan_overflow <= 1'b1;
                            scan_abort_reason_debug <= 8'h04;
                            scan_finish();
                        end
                    end

                    ST_SCAN_BLOCK_TYPE: begin
                        block_type <= read_data;
                        request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3},
                                     ST_SCAN_BLOCK_SIZE0);
                    end

                    ST_SCAN_BLOCK_SIZE0: begin
                        block_size[7:0] <= read_data;
                        request_byte(pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd4},
                                     ST_SCAN_BLOCK_SIZE1);
                    end

                    ST_SCAN_BLOCK_SIZE1: begin
                        block_size[15:8] <= read_data;
                        request_byte(pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd5},
                                     ST_SCAN_BLOCK_SIZE2);
                    end

                    ST_SCAN_BLOCK_SIZE2: begin
                        block_size[23:16] <= read_data;
                        request_byte(pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd6},
                                     ST_SCAN_BLOCK_SIZE3);
                    end

                    ST_SCAN_BLOCK_SIZE3: begin
                        block_size[31:24] <= read_data;
                        if (parser_data_block_count_debug != 32'hffff_ffff) begin
                            parser_data_block_count_debug <=
                                parser_data_block_count_debug + 32'd1;
                        end
                        parser_last_block_type_debug <= block_type;
                        if ((block_type == 8'h00) &&
                            (parser_type00_block_count_debug !=
                             32'hffff_ffff)) begin
                            parser_type00_block_count_debug <=
                                parser_type00_block_count_debug + 32'd1;
                        end
                        if ((block_type == 8'h80) &&
                            (parser_type80_block_count_debug !=
                             32'hffff_ffff)) begin
                            parser_type80_block_count_debug <=
                                parser_type80_block_count_debug + 32'd1;
                        end
                        if (!block_skip_in_range) begin
                            segapcm_rom_scan_overflow <= 1'b1;
                            scan_abort_reason_debug <= 8'h05;
                            scan_finish();
                        end else if (block_type == 8'h80) begin
                            if (segapcm_rom_block_skip_debug_active) begin
                                if (segapcm_rom_scan_block_count !=
                                    32'hffff_ffff) begin
                                    segapcm_rom_scan_block_count <=
                                        segapcm_rom_scan_block_count + 32'd1;
                                end
                                scan_current_payload_len_debug <=
                                    (current_block_size >= 32'd8) ?
                                    (current_block_size - 32'd8) : 32'd0;
                                scan_payload_remaining <= 32'd0;
                                scan_payload_addr <= 32'd0;
                                scan_copy_enabled <= 1'b0;
                                segapcm_copy_active_i <= 1'b0;
                                block_skip_target <=
                                    block_skip_end_32[ADDR_WIDTH-1:0];
                                pc <= block_skip_end_32[ADDR_WIDTH-1:0];
                                current_pc_debug <=
                                    block_skip_end_32[ADDR_WIDTH-1:0];
                                request_byte(block_skip_end_32[ADDR_WIDTH-1:0],
                                             ST_SCAN_FETCH_CMD);
                            end else if (current_block_size < 32'd8) begin
                                segapcm_rom_scan_overflow <= 1'b1;
                                scan_abort_reason_debug <= 8'h06;
                                pc <= block_skip_end_32[ADDR_WIDTH-1:0];
                                current_pc_debug <= block_skip_end_32[ADDR_WIDTH-1:0];
                                request_byte(block_skip_end_32[ADDR_WIDTH-1:0],
                                             ST_SCAN_FETCH_CMD);
                            end else begin
                                if (segapcm_rom_scan_block_count != 32'hffff_ffff) begin
                                    segapcm_rom_scan_block_count <=
                                        segapcm_rom_scan_block_count + 32'd1;
                                end
                                scan_payload_remaining <= current_block_size - 32'd8;
                                scan_current_payload_len_debug <=
                                    current_block_size - 32'd8;
                                block_skip_target <= block_skip_end_32[ADDR_WIDTH-1:0];
                                request_byte(block_data_start_32[ADDR_WIDTH-1:0],
                                             ST_SCAN_ROM_TOTAL0);
                            end
                        end else begin
                            pc <= block_skip_end_32[ADDR_WIDTH-1:0];
                            current_pc_debug <= block_skip_end_32[ADDR_WIDTH-1:0];
                            request_byte(block_skip_end_32[ADDR_WIDTH-1:0],
                                         ST_SCAN_FETCH_CMD);
                        end
                    end

                    ST_SCAN_ROM_TOTAL0: begin
                        segapcm_rom_scan_total_size[7:0] <= read_data;
                        request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-1){1'b0}}, 1'b1},
                                     ST_SCAN_ROM_TOTAL1);
                    end

                    ST_SCAN_ROM_TOTAL1: begin
                        segapcm_rom_scan_total_size[15:8] <= read_data;
                        request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-2){1'b0}}, 2'd2},
                                     ST_SCAN_ROM_TOTAL2);
                    end

                    ST_SCAN_ROM_TOTAL2: begin
                        segapcm_rom_scan_total_size[23:16] <= read_data;
                        request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-2){1'b0}}, 2'd3},
                                     ST_SCAN_ROM_TOTAL3);
                    end

                    ST_SCAN_ROM_TOTAL3: begin
                        segapcm_rom_scan_total_size[31:24] <= read_data;
                        request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-3){1'b0}}, 3'd4},
                                     ST_SCAN_ROM_START0);
                    end

                    ST_SCAN_ROM_START0: begin
                        segapcm_rom_scan_last_start[7:0] <= read_data;
                        request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-3){1'b0}}, 3'd5},
                                     ST_SCAN_ROM_START1);
                    end

                    ST_SCAN_ROM_START1: begin
                        segapcm_rom_scan_last_start[15:8] <= read_data;
                        request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-3){1'b0}}, 3'd6},
                                     ST_SCAN_ROM_START2);
                    end

                    ST_SCAN_ROM_START2: begin
                        segapcm_rom_scan_last_start[23:16] <= read_data;
                        request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-3){1'b0}}, 3'd7},
                                     ST_SCAN_ROM_START3);
                    end

                    ST_SCAN_ROM_START3: begin
                        segapcm_rom_scan_last_start[31:24] <= read_data;
                        scan_payload_addr <= block_data_start_32 + 32'd8;
                        scan_copy_addr <= scan_rom_start_32[18:0];
                        scan_copy_enabled <= SEGAPCM_COPY_ENABLED &&
                                             scan_rom_copy_range_ok;
                        if (SEGAPCM_COPY_ENABLED &&
                            !scan_rom_copy_range_ok) begin
                            segapcm_rom_copy_overflow <= 1'b1;
                            segapcm_rom_scan_overflow <= 1'b1;
                            scan_abort_reason_debug <= 8'h07;
                        end
                        if (scan_payload_remaining == 32'd0) begin
                            segapcm_copy_active_i <= 1'b0;
                            pc <= block_skip_target;
                            current_pc_debug <= block_skip_target;
                            request_byte(block_skip_target, ST_SCAN_FETCH_CMD);
                        end else if (SEGAPCM_COPY_ENABLED &&
                                     scan_rom_copy_range_ok) begin
                            scan_payload_sf_debug_i[0] <= 1'b1;
                            segapcm_copy_active_i <= 1'b1;
                            busy <= 1'b1;
                            done <= 1'b0;
                            read_pending <= 1'b0;
                            read_accepted <= 1'b0;
                            read_ignore_valid_until_low <= 1'b0;
                            read_return_state <= ST_SEGAPCM_COPY_READ_DATA;
                            scan_payload_read_owner <= 1'b0;
                            outstanding_payload_read <= 1'b0;
                            last_payload_read_addr_valid <= 1'b0;
                            scan_payload_req_hold_i <= 1'b0;
                            scan_payload_continue_pending_i <= 1'b0;
                            scan_copy_payload_pc_debug_i <=
                                (block_data_start_32[ADDR_WIDTH-1:0] +
                                 {{(ADDR_WIDTH-4){1'b0}}, 4'd8});
                            state <= ST_SEGAPCM_COPY_READ_WAIT;
                        end else begin
                            scan_copy_payload_pc_debug_i <=
                                (block_data_start_32[ADDR_WIDTH-1:0] +
                                 {{(ADDR_WIDTH-4){1'b0}}, 4'd8});
                            request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                         {{(ADDR_WIDTH-4){1'b0}}, 4'd8},
                                         ST_SCAN_ROM_PAYLOAD);
                        end
                    end

                    ST_SEGAPCM_COPY_READ_WAIT: begin
                        scan_payload_sf_debug_i[1] <= 1'b1;
                        busy <= 1'b1;
                        done <= 1'b0;
                        segapcm_copy_active_i <= 1'b1;
                        read_return_state <= ST_SEGAPCM_COPY_READ_DATA;
                        scan_payload_read_owner <= 1'b0;
                        scan_payload_req_hold_i <= 1'b0;
                        scan_payload_byte_valid_debug_i <= 1'b0;
                        if (!read_pending && !read_accepted) begin
                            mem_rd_req <= 1'b1;
                            mem_rd_addr <= scan_payload_addr[ADDR_WIDTH-1:0];
                            scan_payload_qg_debug_i[1] <= 1'b1;
                            scan_payload_qg_debug_i[3] <= 1'b1;
                            scan_payload_qg_debug_i[6] <= 1'b1;
                            read_request_addr_debug <=
                                scan_payload_addr[ADDR_WIDTH-1:0];
                            read_pending <= 1'b1;
                            if (scan_copy_read_req_count_debug_i !=
                                16'hffff) begin
                                scan_copy_read_req_count_debug_i <=
                                    scan_copy_read_req_count_debug_i + 16'd1;
                                scan_payload_qg_debug_i[0] <= 1'b1;
                                if (state != ST_SEGAPCM_COPY_READ_WAIT) begin
                                    scan_payload_sf_debug_i[4] <= 1'b1;
                                end
                            end
                            outstanding_payload_read <= 1'b1;
                            outstanding_payload_read_seen_debug_i <= 1'b1;
                            last_payload_read_addr <=
                                scan_payload_addr[ADDR_WIDTH-1:0];
                            last_payload_read_addr_valid <= 1'b1;
                        end else if (read_pending && !read_accepted) begin
                            mem_rd_req <= 1'b1;
                            mem_rd_addr <= scan_payload_addr[ADDR_WIDTH-1:0];
                            scan_payload_qg_debug_i[1] <= 1'b1;
                            scan_payload_qg_debug_i[3] <= 1'b1;
                            scan_payload_qg_debug_i[6] <= 1'b1;
                            if (mem_rd_req && mem_rd_ready) begin
                                read_accept_fire_debug_i <= 1'b1;
                                read_accept_to_read_data_debug_i <= 1'b1;
                                read_accept_rr_increment_debug_i <= 1'b1;
                                scan_payload_qg_debug_i[4] <= 1'b1;
                                if (scan_copy_read_accept_count_debug_i !=
                                    16'hffff) begin
                                    scan_copy_read_accept_count_debug_i <=
                                        scan_copy_read_accept_count_debug_i +
                                        16'd1;
                                end
                                mem_rd_req <= 1'b0;
                                read_accepted <= 1'b1;
                                read_response_addr_debug <= mem_rd_addr;
                                state <= ST_SEGAPCM_COPY_READ_DATA;
                            end
                        end
                    end

                    ST_SEGAPCM_COPY_READ_DATA: begin
                        scan_payload_sf_debug_i[2] <= 1'b1;
                        busy <= 1'b1;
                        done <= 1'b0;
                        segapcm_copy_active_i <= 1'b1;
                        mem_rd_req <= 1'b0;
                        read_return_state <= ST_SEGAPCM_COPY_READ_DATA;
                        if (read_pending && read_accepted && mem_rd_valid) begin
                            read_data_consumed_debug_i <= 1'b1;
                            read_valid_rv_increment_debug_i <= 1'b1;
                            payload_byte_valid_pulse_debug_i <= 1'b1;
                            read_data <= mem_rd_data;
                            scan_copy_data <= mem_rd_data;
                            scan_payload_byte_valid_debug_i <= 1'b1;
                            segapcm_rom_scan_checksum32 <=
                                segapcm_rom_scan_checksum32 +
                                {24'd0, mem_rd_data};
                            if (segapcm_rom_scan_byte_count !=
                                32'hffff_ffff) begin
                                segapcm_rom_scan_byte_count <=
                                    segapcm_rom_scan_byte_count + 32'd1;
                            end
                            if (scan_copy_read_valid_count_debug_i !=
                                16'hffff) begin
                                scan_copy_read_valid_count_debug_i <=
                                    scan_copy_read_valid_count_debug_i + 16'd1;
                            end
                            read_pending <= 1'b0;
                            read_accepted <= 1'b0;
                            outstanding_payload_read <= 1'b0;
                            last_payload_read_addr_valid <= 1'b0;
                            state <= ST_SEGAPCM_COPY_WRITE;
                        end
                    end

                    ST_SEGAPCM_COPY_WRITE: begin
                        scan_payload_sf_debug_i[3] <= 1'b1;
                        busy <= 1'b1;
                        done <= 1'b0;
                        segapcm_copy_active_i <= 1'b1;
                        segapcm_copy_wr_req <= 1'b1;
                        segapcm_copy_wr_addr <= scan_copy_addr;
                        segapcm_copy_wr_data <= scan_copy_data;
                        if (scan_copy_req_count_debug_i != 16'hffff) begin
                            scan_copy_req_count_debug_i <=
                                scan_copy_req_count_debug_i + 16'd1;
                        end
                        if (segapcm_copy_wr_req &&
                            segapcm_copy_wr_ready) begin
                            scan_term_pl_debug_i <=
                                scan_current_payload_len_debug[15:0];
                            scan_term_rm_debug_i <=
                                scan_payload_remaining[15:0];
                            scan_term_cc_debug_i <=
                                segapcm_rom_copy_byte_count[15:0];
                            scan_term_nx_debug_i <=
                                (scan_payload_remaining > 32'd0) ?
                                (scan_payload_remaining - 32'd1) : 16'd0;
                            scan_term_be_debug_i <= {
                                8'hBE,
                                3'd0,
                                (scan_payload_remaining > 32'd1),
                                (scan_payload_remaining <= 32'd1),
                                (scan_payload_remaining <= 32'd1),
                                (scan_payload_remaining <= 32'd1),
                                1'b1
                            };
                            if (segapcm_rom_copy_byte_count < 32'd9) begin
                                unique case (segapcm_rom_copy_byte_count[3:0])
                                    4'd0: scan_copy_first_byte0_debug_i <=
                                        scan_copy_data;
                                    4'd1: scan_copy_first_byte1_debug_i <=
                                        scan_copy_data;
                                    4'd2: scan_copy_first_byte2_debug_i <=
                                        scan_copy_data;
                                    4'd3: scan_copy_first_byte3_debug_i <=
                                        scan_copy_data;
                                    4'd4: scan_copy_first_byte4_debug_i <=
                                        scan_copy_data;
                                    4'd5: scan_copy_first_byte5_debug_i <=
                                        scan_copy_data;
                                    4'd6: scan_copy_first_byte6_debug_i <=
                                        scan_copy_data;
                                    4'd7: scan_copy_first_byte7_debug_i <=
                                        scan_copy_data;
                                    4'd8: scan_copy_first_byte8_debug_i <=
                                        scan_copy_data;
                                    default: begin
                                    end
                                endcase
                                scan_copy_source_phase_debug_i <= {
                                    5'd0,
                                    scan_copy_source_payload,
                                    scan_copy_source_start_header,
                                    scan_copy_source_total_header
                                };
                            end
                            copy_pa_increment_debug_i <= 1'b1;
                            copy_ca_increment_debug_i <= 1'b1;
                            scan_copy_ready_count_debug_i <=
                                scan_copy_ready_count_debug_i + 16'd1;
                            if (scan_copy_accept_fire_count_debug_i !=
                                16'hffff) begin
                                scan_copy_accept_fire_count_debug_i <=
                                    scan_copy_accept_fire_count_debug_i +
                                    16'd1;
                            end
                            if (segapcm_rom_copy_byte_count !=
                                32'hffff_ffff) begin
                                segapcm_rom_copy_byte_count <=
                                    segapcm_rom_copy_byte_count + 32'd1;
                            end
                            scan_copy_last_index_low_debug_i <=
                                segapcm_rom_scan_byte_count[15:0] - 16'd1;
                            scan_payload_byte_valid_debug_i <= 1'b0;
                            segapcm_copy_wr_req <= 1'b0;
                            if (scan_payload_remaining <= 32'd1) begin
                                segapcm_copy_active_i <= 1'b0;
                                scan_payload_remaining <= 32'd0;
                                scan_payload_addr <= 32'd0;
                                scan_copy_addr <= scan_copy_addr + 19'd1;
                                scan_final_byte_accepted_debug <= 1'b1;
                                scan_copy_exit_debug_i <=
                                    {4'h1, 5'd0, ST_SCAN_FETCH_CMD};
                                scan_copy_exit_pc_debug_i <=
                                    block_skip_target[15:0];
                                scan_copy_exit_count_debug_i <=
                                    (segapcm_rom_copy_byte_count[15:0] +
                                     16'd1);
                                pc <= block_skip_target;
                                current_pc_debug <= block_skip_target;
                                request_byte(block_skip_target,
                                             ST_SCAN_FETCH_CMD);
                            end else begin
                                scan_payload_remaining <=
                                    scan_payload_remaining - 32'd1;
                                scan_payload_addr <= scan_payload_addr + 32'd1;
                                scan_copy_addr <= scan_copy_addr + 19'd1;
                                copy_transition_next_payload_debug_i <= 1'b1;
                                scan_copy_exit_debug_i <=
                                    {4'h2, 5'd0,
                                     ST_SEGAPCM_COPY_READ_WAIT};
                                scan_copy_exit_pc_debug_i <=
                                    (scan_payload_addr[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-1){1'b0}}, 1'b1});
                                scan_copy_exit_count_debug_i <=
                                    (segapcm_rom_copy_byte_count[15:0] +
                                     16'd1);
                                state <= ST_SEGAPCM_COPY_READ_WAIT;
                            end
                        end
                    end

                    ST_SCAN_ROM_PAYLOAD: begin
                        segapcm_rom_scan_checksum32 <=
                            segapcm_rom_scan_checksum32 + {24'd0, read_data};
                        if (segapcm_rom_scan_byte_count != 32'hffff_ffff) begin
                            segapcm_rom_scan_byte_count <=
                                segapcm_rom_scan_byte_count + 32'd1;
                        end
                        if (scan_copy_enabled) begin
                            scan_payload_continue_pending_i <= 1'b0;
                            scan_copy_data <= read_data;
                            scan_copy_req_armed <= 1'b0;
                            scan_copy_clear_reason_debug_i[4] <= 1'b1;
                            scan_payload_byte_valid_debug_i <= 1'b1;
                            payload_byte_valid_pulse_debug_i <= 1'b1;
                            if (scan_copy_read_valid_count_debug_i !=
                                16'hffff) begin
                                read_valid_rv_increment_debug_i <= 1'b1;
                                scan_copy_read_valid_count_debug_i <=
                                    scan_copy_read_valid_count_debug_i +
                                    16'd1;
                            end
                            state <= ST_SCAN_ROM_COPY;
                        end else begin
                            if (SEGAPCM_COPY_ENABLED &&
                                (scan_current_payload_len_debug != 32'd0) &&
                                (scan_payload_remaining != 32'd0)) begin
                                if (scan_noncopy_advance_count_debug_i !=
                                    16'hffff) begin
                                    scan_noncopy_advance_count_debug_i <=
                                        scan_noncopy_advance_count_debug_i +
                                        16'd1;
                                end
                                scan_used_noncopy_advance_during_copy_debug_i <=
                                    1'b1;
                                scan_remaining_zero_before_expected_accept_debug_i <=
                                    1'b1;
                                scan_abort_reason_debug <= 8'h0a;
                            end
                            scan_advance_payload();
                        end
                    end

                    ST_SCAN_ROM_COPY: begin
                        segapcm_copy_wr_req <= 1'b1;
                        segapcm_copy_wr_addr <= scan_copy_addr;
                        segapcm_copy_wr_data <= scan_copy_data;
                        scan_copy_req_count_debug_i <=
                            scan_copy_req_count_debug_i + 16'd1;
                        if (copy_accept_fire) begin
                            scan_term_pl_debug_i <=
                                scan_current_payload_len_debug[15:0];
                            scan_term_rm_debug_i <=
                                scan_payload_remaining[15:0];
                            scan_term_cc_debug_i <=
                                segapcm_rom_copy_byte_count[15:0];
                            scan_term_nx_debug_i <=
                                scan_next_payload_remaining[15:0];
                            scan_term_be_debug_i <= {
                                8'hBE,
                                scan_finish_taken_debug_i,
                                !scan_copy_has_more_payload_after_accept,
                                status_stop_without_final_reason_debug,
                                scan_copy_has_more_payload_after_accept,
                                !scan_copy_has_more_payload_after_accept,
                                (scan_next_copy_accept_count >=
                                 scan_current_payload_len_debug),
                                (scan_payload_remaining <= 32'd1),
                                1'b1
                            };
                            if (segapcm_rom_copy_byte_count < 32'd9) begin
                                unique case (segapcm_rom_copy_byte_count[3:0])
                                    4'd0: scan_copy_first_byte0_debug_i <=
                                        scan_copy_data;
                                    4'd1: scan_copy_first_byte1_debug_i <=
                                        scan_copy_data;
                                    4'd2: scan_copy_first_byte2_debug_i <=
                                        scan_copy_data;
                                    4'd3: scan_copy_first_byte3_debug_i <=
                                        scan_copy_data;
                                    4'd4: scan_copy_first_byte4_debug_i <=
                                        scan_copy_data;
                                    4'd5: scan_copy_first_byte5_debug_i <=
                                        scan_copy_data;
                                    4'd6: scan_copy_first_byte6_debug_i <=
                                        scan_copy_data;
                                    4'd7: scan_copy_first_byte7_debug_i <=
                                        scan_copy_data;
                                    4'd8: scan_copy_first_byte8_debug_i <=
                                        scan_copy_data;
                                    default: begin
                                    end
                                endcase
                                scan_copy_source_phase_debug_i <= {
                                    5'd0,
                                    scan_copy_source_payload,
                                    scan_copy_source_start_header,
                                    scan_copy_source_total_header
                                };
                            end
                            if (scan_copy_accept_fire_count_debug_i !=
                                16'hffff) begin
                                copy_ca_increment_debug_i <= 1'b1;
                                scan_copy_accept_fire_count_debug_i <=
                                    scan_copy_accept_fire_count_debug_i +
                                    16'd1;
                            end
                            if (segapcm_rom_copy_byte_count != 32'hffff_ffff) begin
                                copy_pa_increment_debug_i <= 1'b1;
                                segapcm_rom_copy_byte_count <=
                                    scan_next_copy_accept_count;
                            end
                            scan_copy_ready_count_debug_i <=
                                scan_copy_ready_count_debug_i + 16'd1;
                            scan_copy_last_index_low_debug_i <=
                                segapcm_rom_scan_byte_count[15:0] - 16'd1;
                            if (scan_copy_has_more_payload_after_accept) begin
                                copy_transition_next_payload_debug_i <= 1'b1;
                                sega_payload_continue_guard_i <= 1'b1;
                                scan_payload_continue_pending_i <= 1'b1;
                                scan_sticky_guard_debug_i[0] <= 1'b1;
                                scan_copy_exit_debug_i <=
                                    {4'h2, 5'd0, ST_SCAN_ROM_PAYLOAD};
                                scan_copy_exit_pc_debug_i <=
                                    (scan_payload_addr[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-1){1'b0}}, 1'b1});
                                scan_copy_exit_count_debug_i <=
                                    scan_next_copy_accept_count[15:0];
                                scan_payload_byte_valid_debug_i <= 1'b0;
                                if (scan_copy_read_req_count_debug_i !=
                                    16'hffff) begin
                                    scan_copy_read_req_count_debug_i <=
                                        scan_copy_read_req_count_debug_i +
                                        16'd1;
                                    scan_payload_qg_debug_i[0] <= 1'b1;
                                    if (state != ST_SEGAPCM_COPY_READ_WAIT) begin
                                        scan_payload_sf_debug_i[4] <= 1'b1;
                                    end
                                    outstanding_payload_read <= 1'b1;
                                    outstanding_payload_read_seen_debug_i <= 1'b1;
                                    last_payload_read_addr <=
                                        scan_payload_addr[ADDR_WIDTH-1:0] +
                                        {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                                    last_payload_read_addr_valid <= 1'b1;
                                    read_return_state <= ST_SCAN_ROM_PAYLOAD;
                                    scan_payload_read_owner <= 1'b1;
                                end
                                scan_copy_payload_pc_debug_i <=
                                    (scan_payload_addr[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-1){1'b0}}, 1'b1});
                                scan_payload_remaining <=
                                    scan_next_payload_remaining;
                                scan_payload_addr <= scan_payload_addr + 32'd1;
                                request_byte(scan_payload_addr[ADDR_WIDTH-1:0] +
                                             {{(ADDR_WIDTH-1){1'b0}}, 1'b1},
                                             ST_SCAN_ROM_PAYLOAD);
                            end else begin
                                scan_final_byte_accepted_debug <= 1'b1;
                                scan_copy_exit_debug_i <=
                                    {4'h1, 5'd0, ST_SCAN_FETCH_CMD};
                                scan_copy_exit_pc_debug_i <=
                                    block_skip_target[15:0];
                                scan_copy_exit_count_debug_i <=
                                    scan_next_copy_accept_count[15:0];
                                scan_payload_byte_valid_debug_i <= 1'b0;
                                if (scan_next_copy_accept_count !=
                                    scan_current_payload_len_debug) begin
                                    scan_remaining_zero_before_expected_accept_debug_i <=
                                        1'b1;
                                end
                                scan_payload_remaining <= 32'd0;
                                scan_payload_addr <= 32'd0;
                                pc <= block_skip_target;
                                current_pc_debug <= block_skip_target;
                                request_byte(block_skip_target, ST_SCAN_FETCH_CMD);
                            end
                            scan_copy_req_armed <= 1'b0;
                            scan_copy_clear_reason_debug_i[1] <= 1'b1;
                            scan_copy_addr <= scan_copy_addr + 19'd1;
                        end else if (!scan_copy_req_armed) begin
                            scan_copy_req_armed <= 1'b1;
                        end
                    end

                    ST_SCAN_FLUSH: begin
                        segapcm_copy_flush_req <= 1'b1;
                        if (segapcm_copy_flush_done) begin
                            if (SEGAPCM_COPY_ENABLED &&
                                (scan_current_payload_len_debug != 32'd0) &&
                                (segapcm_rom_copy_byte_count !=
                                 scan_current_payload_len_debug)) begin
                                scan_remaining_zero_before_expected_accept_debug_i <=
                                    1'b1;
                                scan_abort_reason_debug <= 8'h09;
                                enter_error(ERR_DATA_BLOCK_RANGE);
                            end else begin
                                scan_start_playback();
                            end
                        end
                    end

                    ST_FETCH_CMD: begin
                        cmd <= read_data;
                        last_cmd_debug <= read_data;
                        current_pc_debug <= pc;
                        if (parser_command_count_debug != 32'hffff_ffff) begin
                            parser_command_count_debug <=
                                parser_command_count_debug + 32'd1;
                        end
                        if (playback_started_after_scan_debug &&
                            !normal_command_fetch_started_debug) begin
                            normal_command_fetch_started_debug <= 1'b1;
                            first_playback_cmd_after_scan_debug <= read_data;
                        end
                        if (playback_started_after_scan_debug &&
                            (first_playback_cmd_count_debug < 3'd4)) begin
                            case (first_playback_cmd_count_debug)
                                3'd0: first_playback_cmds_after_scan_debug_i[7:0] <= read_data;
                                3'd1: first_playback_cmds_after_scan_debug_i[15:8] <= read_data;
                                3'd2: first_playback_cmds_after_scan_debug_i[23:16] <= read_data;
                                default: first_playback_cmds_after_scan_debug_i[31:24] <= read_data;
                            endcase
                            first_playback_cmd_count_debug <=
                                first_playback_cmd_count_debug + 3'd1;
                        end
                        state <= ST_DECODE;
                    end

                    ST_DECODE: begin
                        if (!pc_in_range) begin
                            enter_error(ERR_PC_RANGE);
                        end else begin
                            case (cmd)
                                8'h52, 8'h53, 8'h50, 8'h4F, 8'h54, 8'h61: begin
                                    request_byte(pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1}, ST_ARG1);
                                end

                                8'h67: begin
                                    request_byte(pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1}, ST_BLOCK_MARKER);
                                end

                                8'h68: begin
                                    if (YM2151_MODE) begin
                                        if (pcm_ram_write_skip_count != 32'hffff_ffff) begin
                                            pcm_ram_write_skip_count <=
                                                pcm_ram_write_skip_count + 32'd1;
                                        end
                                        skip_observed_command(4'd12);
                                    end else begin
                                        enter_unsupported_error();
                                    end
                                end

                                8'hE0: begin
                                    request_byte(pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1}, ST_SEEK0);
                                end

                                8'h62: begin
                                    wait_remaining <= 16'd735;
                                    pc <= pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                                    current_pc_debug <= pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                                    state <= ST_WAIT_SAMPLES;
                                end

                                8'h63: begin
                                    wait_remaining <= 16'd882;
                                    pc <= pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                                    current_pc_debug <= pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                                    state <= ST_WAIT_SAMPLES;
                                end

                                8'h66: begin
                                    end_command_seen <= 1'b1;
                                    if (loop_valid) begin
                                        loop_taken_debug <= 1'b1;
                                        pc <= loop_pc;
                                        current_pc_debug <= loop_pc;
                                        request_byte(loop_pc, ST_FETCH_CMD);
                                    end else begin
                                        busy <= 1'b0;
                                        done <= 1'b1;
                                        done_pc_debug <= pc;
                                        done_cmd_debug <= cmd;
                                        final_valid_debug <= 1'b1;
                                        final_state_debug <= ST_DONE;
                                        final_pc_debug <= pc;
                                        final_cmd_debug <= cmd;
                                        final_error_code_debug <= ERR_NONE;
                                        final_reason_debug <= STOP_REASON_66_NO_LOOP;
                                        state <= ST_DONE;
                                    end
                                end

                                default: begin
                                    if (cmd[7:4] == 4'h7) begin
                                        wait_remaining <= {12'd0, cmd[3:0]} + 16'd1;
                                        pc <= pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                                        current_pc_debug <= pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                                        state <= ST_WAIT_SAMPLES;
                                    end else if (cmd[7:4] == 4'h8) begin
                                        if (YM2151_MODE) begin
                                            wait_remaining <= {12'd0, cmd[3:0]};
                                            pc <= pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                                            current_pc_debug <= pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                                            if (unsupported_command_count != 32'hffff_ffff) begin
                                                unsupported_command_count <=
                                                    unsupported_command_count + 32'd1;
                                            end
                                            state <= ST_WAIT_SAMPLES;
                                        end else begin
                                        dac_stream_measure_active <= 1'b1;
                                        dac_stream_wait0_current <= (cmd[3:0] == 4'd0);
                                        dac_stream_cmd_cycles <= 32'd1;
                                        dac_stream_cmd_wait_cycles <= 32'd0;
                                        dac_stream_cmd_count <=
                                            dac_stream_cmd_count + 32'd1;
                                        dac_stream_wait_samples_total <=
                                            dac_stream_wait_samples_total +
                                            {28'd0, cmd[3:0]};
                                        if (cmd[3:0] == 4'd0) begin
                                            count_wait0_dac_stream_cmd <=
                                                count_wait0_dac_stream_cmd + 32'd1;
                                        end

                                        if (!pcm_read_in_range) begin
                                            pcm_oob <= 1'b1;
                                            if (pcm_oob_count != 32'hffff_ffff) begin
                                                pcm_oob_count <= pcm_oob_count + 32'd1;
                                            end
                                            ym_cmd_port <= 1'b0;
                                            ym_cmd_reg <= 8'h2A;
                                            ym_cmd_data <= 8'h80;
                                            pcm_pos <= pcm_pos + 32'd1;
                                            state <= ST_YM_WAIT_READY;
                                        end else begin
                                            request_byte(pcm_read_addr_32[ADDR_WIDTH-1:0], ST_DAC_READ);
                                        end
                                        end
                                    end else if (YM2151_MODE &&
                                                 (cmd == 8'hC0)) begin
                                        request_byte(pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1}, ST_ARG1);
                                    end else if (YM2151_MODE &&
                                                 (cmd[7:4] == 4'h5)) begin
                                        skip_unsupported_command(4'd3);
                                    end else if (YM2151_MODE &&
                                                 (cmd == 8'hA0)) begin
                                        skip_unsupported_command(4'd3);
                                    end else if (YM2151_MODE &&
                                                 (cmd[7:4] == 4'hB)) begin
                                        skip_unsupported_command(4'd3);
                                    end else if (YM2151_MODE &&
                                                 (cmd[7:4] == 4'h9) &&
                                                 (cmd[3:0] <= 4'h5)) begin
                                        case (cmd)
                                            8'h90: skip_unsupported_command(4'd5);
                                            8'h91: skip_unsupported_command(4'd5);
                                            8'h92: skip_unsupported_command(4'd6);
                                            8'h93: skip_unsupported_command(4'd11);
                                            8'h94: skip_unsupported_command(4'd2);
                                            8'h95: skip_unsupported_command(4'd5);
                                            default: enter_unsupported_error();
                                        endcase
                                    end else if (YM2151_MODE &&
                                                 ((cmd[7:4] == 4'hC) ||
                                                  (cmd[7:4] == 4'hD))) begin
                                        skip_unsupported_command(4'd4);
                                    end else begin
                                        enter_unsupported_error();
                                    end
                                end
                            endcase
                        end
                    end

                    ST_ARG1: begin
                        arg1 <= read_data;
                        if ((cmd == 8'h52) || (cmd == 8'h53) ||
                            (cmd == 8'h54) || (cmd == 8'h61) ||
                            (cmd == 8'hC0)) begin
                            request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2}, ST_ARG2);
                        end else if (cmd == 8'h50) begin
                            if (YM2151_MODE) begin
                                skip_unsupported_command(4'd2);
                            end else begin
                                psg_cmd_data <= read_data;
                                state <= ST_PSG_WAIT_READY;
                            end
                        end else begin
                            pc <= pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2};
                            current_pc_debug <= pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2};
                            request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2}, ST_FETCH_CMD);
                        end
                    end

                    ST_ARG2: begin
                        if ((cmd == 8'h52) || (cmd == 8'h53)) begin
                            if (YM2151_MODE) begin
                                skip_unsupported_command(4'd3);
                            end else begin
                                ym_cmd_port <= (cmd == 8'h53);
                                ym_cmd_reg <= arg1;
                                ym_cmd_data <= read_data;
                                state <= ST_YM_WAIT_READY;
                            end
                        end else if (cmd == 8'h54) begin
                            if (YM2151_MODE) begin
                                ym2151_cmd_reg <= arg1;
                                ym2151_cmd_data <= read_data;
                                ym2151_last_reg <= arg1;
                                ym2151_last_data <= read_data;
                                if (ym2151_write_count != 32'hffff_ffff) begin
                                    ym2151_write_count <= ym2151_write_count + 32'd1;
                                end
                                state <= ST_YM2151_WAIT_READY;
                            end else begin
                                enter_unsupported_error();
                            end
                        end else if (cmd == 8'hC0) begin
                            if (YM2151_MODE) begin
                                segapcm_pending_addr <= {read_data, arg1};
                                request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3},
                                             ST_SEGAPCM_DATA);
                            end else begin
                                enter_unsupported_error();
                            end
                        end else begin
                            wait_remaining <= {read_data, arg1};
                            pc <= pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3};
                            current_pc_debug <= pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3};
                            state <= ST_WAIT_SAMPLES;
                        end
                    end

                    ST_SEGAPCM_DATA: begin
                        segapcm_cmd_addr <= segapcm_pending_addr;
                        segapcm_cmd_data <= read_data;
                        segapcm_last_addr <= segapcm_pending_addr;
                        segapcm_last_data <= read_data;
                        segapcm_cmd_valid <= 1'b1;
                        if (segapcm_write_count != 32'hffff_ffff) begin
                            segapcm_write_count <= segapcm_write_count + 32'd1;
                        end
                        pc <= pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd4};
                        current_pc_debug <= pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd4};
                        request_byte(pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd4},
                                     ST_FETCH_CMD);
                    end

                    ST_BLOCK_MARKER: begin
                        if (read_data == 8'h66) begin
                            request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2}, ST_BLOCK_TYPE);
                        end else begin
                            enter_error(ERR_BAD_DATA_BLOCK);
                        end
                    end

                    ST_BLOCK_TYPE: begin
                        block_type <= read_data;
                        request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3}, ST_BLOCK_SIZE0);
                    end

                    ST_BLOCK_SIZE0: begin
                        block_size[7:0] <= read_data;
                        request_byte(pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd4}, ST_BLOCK_SIZE1);
                    end

                    ST_BLOCK_SIZE1: begin
                        block_size[15:8] <= read_data;
                        request_byte(pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd5}, ST_BLOCK_SIZE2);
                    end

                    ST_BLOCK_SIZE2: begin
                        block_size[23:16] <= read_data;
                        request_byte(pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd6}, ST_BLOCK_SIZE3);
                    end

                    ST_BLOCK_SIZE3: begin
                        block_size[31:24] <= read_data;
                        if (parser_data_block_count_debug != 32'hffff_ffff) begin
                            parser_data_block_count_debug <=
                                parser_data_block_count_debug + 32'd1;
                        end
                        parser_last_block_type_debug <= block_type;
                        if ((block_type == 8'h00) &&
                            (parser_type00_block_count_debug !=
                             32'hffff_ffff)) begin
                            parser_type00_block_count_debug <=
                                parser_type00_block_count_debug + 32'd1;
                        end
                        if ((block_type == 8'h80) &&
                            (parser_type80_block_count_debug !=
                             32'hffff_ffff)) begin
                            parser_type80_block_count_debug <=
                                parser_type80_block_count_debug + 32'd1;
                        end
                        if (!block_skip_in_range) begin
                            enter_error(ERR_DATA_BLOCK_RANGE);
                        end else begin
                            block_skip_target <= block_skip_end_32[ADDR_WIDTH-1:0];
                            if (data_block_count != 32'hffff_ffff) begin
                                data_block_count <= data_block_count + 32'd1;
                            end
                            last_data_block_type <= block_type;
                            last_data_block_size_low <= current_block_size[15:0];
                            if (block_type == 8'h00) begin
                                pcm_data_start <= block_data_start_32;
                                pcm_data_size <= current_block_size;
                            end
                            if (YM2151_MODE && (block_type == 8'h80)) begin
                                if (segapcm_rom_block_count != 32'hffff_ffff) begin
                                    segapcm_rom_block_count <=
                                        segapcm_rom_block_count + 32'd1;
                                end
                                segapcm_last_rom_size <= current_block_size;
                                segapcm_last_rom_start <= block_data_start_32;
                                if (segapcm_rom_block_skip_debug_active) begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_ACTIVE
                                    if (segapcm_tap_payload_size_32 != 32'd0) begin
                                        segapcm_tap_payload_remaining <=
                                            segapcm_tap_payload_size_32;
                                        segapcm_tap_payload_addr <=
                                            segapcm_tap_payload_start_32;
                                        segapcm_tap_payload_index <= 19'd0;
                                        current_pc_debug <=
                                            segapcm_tap_payload_start_32[ADDR_WIDTH-1:0];
                                        request_byte(
                                            segapcm_tap_payload_start_32[ADDR_WIDTH-1:0],
                                            ST_SEGAPCM_TAP_PAYLOAD);
                                    end else begin
                                        pc <= block_skip_end_32[ADDR_WIDTH-1:0];
                                        current_pc_debug <=
                                            block_skip_end_32[ADDR_WIDTH-1:0];
                                        request_byte(block_skip_end_32[ADDR_WIDTH-1:0],
                                                     ST_FETCH_CMD);
                                    end
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST
                                    if (segapcm_tap_payload_size_32 != 32'd0) begin
                                        segapcm_tap_payload_remaining <=
                                            segapcm_tap_payload_size_32;
                                        segapcm_tap_payload_addr <=
                                            segapcm_tap_payload_start_32;
                                        segapcm_tap_payload_index <= 19'd0;
                                        current_pc_debug <=
                                            segapcm_tap_payload_start_32[ADDR_WIDTH-1:0];
                                        request_byte(
                                            segapcm_tap_payload_start_32[ADDR_WIDTH-1:0],
                                            ST_SEGAPCM_TAP_PAYLOAD);
                                    end else begin
                                        pc <= block_skip_end_32[ADDR_WIDTH-1:0];
                                        current_pc_debug <=
                                            block_skip_end_32[ADDR_WIDTH-1:0];
                                        request_byte(block_skip_end_32[ADDR_WIDTH-1:0],
                                                     ST_FETCH_CMD);
                                    end
`elsif MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST
                                    if (segapcm_tap_payload_size_32 != 32'd0) begin
                                        segapcm_tap_payload_remaining <=
                                            segapcm_tap_payload_size_32;
                                        segapcm_tap_payload_addr <=
                                            segapcm_tap_payload_start_32;
                                        segapcm_tap_payload_index <= 19'd0;
                                        current_pc_debug <=
                                            segapcm_tap_payload_start_32[ADDR_WIDTH-1:0];
                                        request_byte(
                                            segapcm_tap_payload_start_32[ADDR_WIDTH-1:0],
                                            ST_SEGAPCM_TAP_PAYLOAD);
                                    end else begin
                                        pc <= block_skip_end_32[ADDR_WIDTH-1:0];
                                        current_pc_debug <=
                                            block_skip_end_32[ADDR_WIDTH-1:0];
                                        request_byte(block_skip_end_32[ADDR_WIDTH-1:0],
                                                     ST_FETCH_CMD);
                                    end
`else
                                    pc <= block_skip_end_32[ADDR_WIDTH-1:0];
                                    current_pc_debug <=
                                        block_skip_end_32[ADDR_WIDTH-1:0];
                                    request_byte(block_skip_end_32[ADDR_WIDTH-1:0],
                                                 ST_FETCH_CMD);
`endif
                                end else if (segapcm_rom_header_in_range) begin
                                    request_byte(block_data_start_32[ADDR_WIDTH-1:0],
                                                 ST_SEGAPCM_ROM_SIZE0);
                                end else begin
                                    pc <= block_skip_end_32[ADDR_WIDTH-1:0];
                                    current_pc_debug <= block_skip_end_32[ADDR_WIDTH-1:0];
                                    request_byte(block_skip_end_32[ADDR_WIDTH-1:0],
                                                 ST_FETCH_CMD);
                                end
                            end else begin
                                pc <= block_skip_end_32[ADDR_WIDTH-1:0];
                                current_pc_debug <= block_skip_end_32[ADDR_WIDTH-1:0];
                                request_byte(block_skip_end_32[ADDR_WIDTH-1:0],
                                             ST_FETCH_CMD);
                            end
                        end
                    end

                    ST_SEGAPCM_TAP_PAYLOAD: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_ACTIVE
                        if (!segapcm_smoke_ddr_capture_done_i &&
                            (segapcm_tap_payload_index <
                             SEGAPCM_SMOKE_DDR_CAPTURE_BYTES)) begin
                            segapcm_copy_wr_req <= 1'b1;
                            segapcm_copy_wr_addr <= segapcm_tap_payload_index;
                            segapcm_copy_wr_data <= read_data;
                        end

                        if (segapcm_smoke_ddr_capture_done_i ||
                            (segapcm_tap_payload_index >=
                             SEGAPCM_SMOKE_DDR_CAPTURE_BYTES) ||
                            segapcm_copy_wr_ready) begin
                            if (!segapcm_smoke_ddr_capture_done_i &&
                                (segapcm_tap_payload_index <
                                 SEGAPCM_SMOKE_DDR_CAPTURE_BYTES)) begin
                                segapcm_copy_wr_req <= 1'b0;
                            end
                            if (!segapcm_smoke_ddr_capture_done_i &&
                                (segapcm_tap_payload_index ==
                                 (SEGAPCM_SMOKE_DDR_CAPTURE_BYTES - 19'd1)) &&
                                segapcm_copy_wr_ready) begin
                                segapcm_smoke_ddr_capture_done_i <= 1'b1;
                            end
                            segapcm_payload_tap_valid <= 1'b1;
                            segapcm_payload_tap_addr <= segapcm_tap_payload_index;
                            segapcm_payload_tap_data <= read_data;
                            if (segapcm_payload_tap_byte_count_debug !=
                                32'hffff_ffff) begin
                                segapcm_payload_tap_byte_count_debug <=
                                    segapcm_payload_tap_byte_count_debug + 32'd1;
                            end
                            if (segapcm_tap_payload_remaining <= 32'd1) begin
                                segapcm_tap_payload_remaining <= 32'd0;
                                segapcm_tap_payload_addr <= 32'd0;
                                segapcm_tap_payload_index <= 19'd0;
                                pc <= block_skip_target;
                                current_pc_debug <= block_skip_target;
                                request_byte(block_skip_target, ST_FETCH_CMD);
                            end else begin
                                segapcm_tap_payload_remaining <=
                                    segapcm_tap_payload_remaining - 32'd1;
                                segapcm_tap_payload_addr <=
                                    segapcm_tap_payload_next_addr;
                                segapcm_tap_payload_index <=
                                    segapcm_tap_payload_next_index;
                                current_pc_debug <=
                                    segapcm_tap_payload_next_addr[ADDR_WIDTH-1:0];
                                request_byte(
                                    segapcm_tap_payload_next_addr[ADDR_WIDTH-1:0],
                                    ST_SEGAPCM_TAP_PAYLOAD);
                            end
                        end
`else
                        segapcm_payload_tap_valid <= 1'b1;
                        segapcm_payload_tap_addr <= segapcm_tap_payload_index;
                        segapcm_payload_tap_data <= read_data;
                        if (segapcm_payload_tap_byte_count_debug !=
                            32'hffff_ffff) begin
                            segapcm_payload_tap_byte_count_debug <=
                                segapcm_payload_tap_byte_count_debug + 32'd1;
                        end
                        if (segapcm_tap_payload_remaining <= 32'd1) begin
                            segapcm_tap_payload_remaining <= 32'd0;
                            segapcm_tap_payload_addr <= 32'd0;
                            segapcm_tap_payload_index <= 19'd0;
                            pc <= block_skip_target;
                            current_pc_debug <= block_skip_target;
                            request_byte(block_skip_target, ST_FETCH_CMD);
                        end else begin
                            segapcm_tap_payload_remaining <=
                                segapcm_tap_payload_remaining - 32'd1;
                            segapcm_tap_payload_addr <=
                                segapcm_tap_payload_next_addr;
                            segapcm_tap_payload_index <=
                                segapcm_tap_payload_next_index;
                            current_pc_debug <=
                                segapcm_tap_payload_next_addr[ADDR_WIDTH-1:0];
                            request_byte(
                                segapcm_tap_payload_next_addr[ADDR_WIDTH-1:0],
                                ST_SEGAPCM_TAP_PAYLOAD);
                        end
`endif
                    end

                    ST_SEGAPCM_ROM_SIZE0: begin
                        segapcm_last_rom_size[7:0] <= read_data;
                        request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-1){1'b0}}, 1'b1},
                                     ST_SEGAPCM_ROM_SIZE1);
                    end

                    ST_SEGAPCM_ROM_SIZE1: begin
                        segapcm_last_rom_size[15:8] <= read_data;
                        request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-2){1'b0}}, 2'd2},
                                     ST_SEGAPCM_ROM_SIZE2);
                    end

                    ST_SEGAPCM_ROM_SIZE2: begin
                        segapcm_last_rom_size[23:16] <= read_data;
                        request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-2){1'b0}}, 2'd3},
                                     ST_SEGAPCM_ROM_SIZE3);
                    end

                    ST_SEGAPCM_ROM_SIZE3: begin
                        segapcm_last_rom_size[31:24] <= read_data;
                        request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-3){1'b0}}, 3'd4},
                                     ST_SEGAPCM_ROM_START0);
                    end

                    ST_SEGAPCM_ROM_START0: begin
                        segapcm_last_rom_start[7:0] <= read_data;
                        request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-3){1'b0}}, 3'd5},
                                     ST_SEGAPCM_ROM_START1);
                    end

                    ST_SEGAPCM_ROM_START1: begin
                        segapcm_last_rom_start[15:8] <= read_data;
                        request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-3){1'b0}}, 3'd6},
                                     ST_SEGAPCM_ROM_START2);
                    end

                    ST_SEGAPCM_ROM_START2: begin
                        segapcm_last_rom_start[23:16] <= read_data;
                        request_byte(block_data_start_32[ADDR_WIDTH-1:0] +
                                     {{(ADDR_WIDTH-3){1'b0}}, 3'd7},
                                     ST_SEGAPCM_ROM_START3);
                    end

                    ST_SEGAPCM_ROM_START3: begin
                        segapcm_last_rom_start[31:24] <= read_data;
                        pc <= block_skip_target;
                        current_pc_debug <= block_skip_target;
                        request_byte(block_skip_target, ST_FETCH_CMD);
                    end

                    ST_SEEK0: begin
                        pcm_pos[7:0] <= read_data;
                        request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2}, ST_SEEK1);
                    end

                    ST_SEEK1: begin
                        pcm_pos[15:8] <= read_data;
                        request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3}, ST_SEEK2);
                    end

                    ST_SEEK2: begin
                        pcm_pos[23:16] <= read_data;
                        request_byte(pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd4}, ST_SEEK3);
                    end

                    ST_SEEK3: begin
                        pcm_pos[31:24] <= read_data;
                        pc <= pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd5};
                        current_pc_debug <= pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd5};
                        request_byte(pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd5}, ST_FETCH_CMD);
                    end

                    ST_DAC_READ: begin
                        ym_cmd_port <= 1'b0;
                        ym_cmd_reg <= 8'h2A;
                        ym_cmd_data <= read_data;
                        pcm_pos <= pcm_pos + 32'd1;
                        state <= ST_YM_WAIT_READY;
                    end

                    ST_YM_WAIT_READY: begin
                        if (ym_cmd_ready) begin
                            ym_cmd_valid <= 1'b1;
                            state <= ST_YM_PULSE;
                        end
                    end

                    ST_YM_PULSE: begin
                        if (cmd[7:4] == 4'h8) begin
                            wait_remaining <= {12'd0, cmd[3:0]};
                            pc <= pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                            current_pc_debug <= pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                            state <= ST_WAIT_SAMPLES;
                        end else begin
                            pc <= pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3};
                            current_pc_debug <= pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3};
                            request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3}, ST_FETCH_CMD);
                        end
                    end

                    ST_YM2151_WAIT_READY: begin
                        if (ym2151_cmd_ready) begin
                            ym2151_cmd_valid <= 1'b1;
                            state <= ST_YM2151_PULSE;
                        end
                    end

                    ST_YM2151_PULSE: begin
                        pc <= pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3};
                        current_pc_debug <= pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3};
                        request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3}, ST_FETCH_CMD);
                    end

                    ST_PSG_WAIT_READY: begin
                        if (psg_cmd_ready) begin
                            psg_cmd_valid <= 1'b1;
                            state <= ST_PSG_PULSE;
                        end
                    end

                    ST_PSG_PULSE: begin
                        pc <= pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2};
                        current_pc_debug <= pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2};
                        request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2}, ST_FETCH_CMD);
                    end

                    ST_WAIT_SAMPLES: begin
                        if (wait_remaining == 16'd0) begin
                            if (dac_stream_measure_active) begin
                                finish_dac_stream_measurement();
                            end
                            request_byte(pc, ST_FETCH_CMD);
                        end else if (vgm_wait_tick_edge) begin
                            wait_remaining <= wait_remaining - 16'd1;
                            wait_ticks_consumed_debug <= wait_ticks_consumed_debug + 32'd1;
                        end
                    end

                    ST_DONE: begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        if (load_done_pulse || start_edge) begin
                            done <= 1'b0;
                            state <= ST_IDLE;
                        end
                    end

                    ST_ERROR: begin
                        busy <= 1'b0;
                        done <= 1'b0;
                        state <= ST_IDLE;
                    end

                    default: begin
                        enter_error(ERR_UNSUPPORTED_OPCODE);
                    end
                endcase
            end
        end
    end

endmodule

`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_ACTIVE
`undef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_ACTIVE
`endif
