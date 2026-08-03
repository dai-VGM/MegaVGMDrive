`timescale 1ns/1ps

module emu (
    input CLK_50M, input RESET, inout [48:0] HPS_BUS,
    output CLK_VIDEO, output CE_PIXEL,
    output [12:0] VIDEO_ARX, output [12:0] VIDEO_ARY,
    output [7:0] VGA_R, output [7:0] VGA_G, output [7:0] VGA_B,
    output VGA_HS, output VGA_VS, output VGA_DE, output VGA_F1,
    output [1:0] VGA_SL, output VGA_SCALER, output VGA_DISABLE,
    input [11:0] HDMI_WIDTH, input [11:0] HDMI_HEIGHT,
    output HDMI_FREEZE, output HDMI_BLACKOUT,
`ifdef MISTER_FB
    output FB_EN, output [4:0] FB_FORMAT, output [11:0] FB_WIDTH,
    output [11:0] FB_HEIGHT, output [31:0] FB_BASE,
    output [13:0] FB_STRIDE, input FB_VBL, input FB_LL,
    output FB_FORCE_BLANK,
`ifdef MISTER_FB_PALETTE
    output FB_PAL_CLK, output [7:0] FB_PAL_ADDR,
    output [23:0] FB_PAL_DOUT, input [23:0] FB_PAL_DIN,
    output FB_PAL_WR,
`endif
`endif
    output LED_USER, output [1:0] LED_POWER, output [1:0] LED_DISK,
    output [1:0] BUTTONS, input CLK_AUDIO,
    output [15:0] AUDIO_L, output [15:0] AUDIO_R, output AUDIO_S,
    output [1:0] AUDIO_MIX, inout [3:0] ADC_BUS,
    output SD_SCK, output SD_MOSI, input SD_MISO, output SD_CS,
    input SD_CD, output DDRAM_CLK, input DDRAM_BUSY,
    output [7:0] DDRAM_BURSTCNT, output [28:0] DDRAM_ADDR,
    input [63:0] DDRAM_DOUT, input DDRAM_DOUT_READY,
    output DDRAM_RD, output [63:0] DDRAM_DIN, output [7:0] DDRAM_BE,
    output DDRAM_WE, output SDRAM_CLK, output SDRAM_CKE,
    output [12:0] SDRAM_A, output [1:0] SDRAM_BA,
    inout [15:0] SDRAM_DQ, output SDRAM_DQML, output SDRAM_DQMH,
    output SDRAM_nCS, output SDRAM_nCAS, output SDRAM_nRAS,
    output SDRAM_nWE,
`ifdef MISTER_DUAL_SDRAM
    input SDRAM2_EN, output SDRAM2_CLK, output [12:0] SDRAM2_A,
    output [1:0] SDRAM2_BA, inout [15:0] SDRAM2_DQ,
    output SDRAM2_nCS, output SDRAM2_nCAS, output SDRAM2_nRAS,
    output SDRAM2_nWE,
`endif
    input UART_CTS, output UART_RTS, input UART_RXD, output UART_TXD,
    output UART_DTR, input UART_DSR, input [6:0] USER_IN,
    output [6:0] USER_OUT, output [1:0] VGM_PLAYER_STATE,
    input OSD_STATUS
);
    `include "build_id.v"
    localparam CONF_STR = {
        "MegaVGMPlayer YM2610;;",
        "F1,VGM,Load VGM;",
        "O23,Debug View,Off,Parser,PCM,Reserved;",
        "-;",
        "R0,Reset;",
        "V,v", `BUILD_DATE
    };

    wire clk_sys, pll_locked;
    wire [31:0] status;
    wire [1:0] buttons;
    wire ioctl_download, ioctl_wr, ioctl_wait, backend_ioctl_wait;
    wire [26:0] ioctl_addr;
    wire [7:0] ioctl_dout;
    wire [15:0] ioctl_index;
    wire soft_reset = status[0];
    wire forced_scandoubler, direct_video;
    wire [21:0] gamma_bus;
    wire player_reset, video_reset, por_active;
    wire [2:0] last_reset_source;
    wire pll_unlock_observed;
    wire [15:0] video_reset_edge_count;
    logic upload_abort_hold;
    wire backend_ioctl_download = ioctl_download && !upload_abort_hold &&
                                  !player_reset;
    wire backend_ioctl_wr = ioctl_wr && backend_ioctl_download;
    // A cold POR stalls a transfer until the profile is ready.  A software
    // reset or recorded runtime PLL loss aborts the current generation and
    // then waits for raw ioctl_download to return low before re-arming.
    assign ioctl_wait = player_reset && !upload_abort_hold ?
                        ioctl_download : backend_ioctl_wait;

    wire title_valid, title_metadata_busy;
    wire [5:0] title_directory_length, title_basename_length;
    wire [6:0] title_read_addr;
    wire [7:0] title_read_data;
    wire load_busy, load_done, load_done_pulse, play_ready_pulse;
    wire load_error, overflow_error;
    wire [31:0] file_size, magic_debug;
    wire backend_mem_req, backend_mem_ready, backend_mem_valid;
    wire [22:0] backend_mem_addr;
    wire [7:0] backend_mem_data;
    wire [15:0] backend_fifo_debug, backend_ready_debug;
    wire [15:0] backend_word_debug;
    wire scanner_ready_pulse;
    wire [7:0] load_generation;
    wire [31:0] load_fence_count;
    wire load_fence_waiting, load_fence_stable;

    wire signed [15:0] audio_l, audio_r;
    wire audio_sample, external_mute, start_pulse;
    wire [31:0] start_count;
    wire [31:0] scanner_start_count, parser_command_count;
    wire [3:0] load_state, classification;
    wire [4:0] scanner_state;
    wire [3:0] parser_state;
    wire core_fatal_active;
    wire [7:0] core_fatal_code;
    wire raw_variant_b;
    wire [7:0] reject_code;
    wire [31:0] original_size, parser_pc, wait_remaining, parser_samples;
    wire [31:0] parser_writes, port0_writes, port1_writes, loop_count;
    wire [7:0] parser_opcode;
    wire [3:0] descriptor_a_count, descriptor_b_count;
    wire [31:0] b_only_writes, unknown_writes, first_bad_pc;
    wire first_bad_port;
    wire [7:0] first_bad_address, first_bad_data;
    wire [31:0] unsupported_pc;
    wire [7:0] unsupported_opcode;
    wire [31:0] pcm_requests, pcm_responses, adpcma_requests, adpcmb_requests;
    wire [19:0] pcm_last_address;
    wire [19:0] adpcma_last_address, adpcmb_last_address;
    wire [31:0] adpcma_fetch_requests, adpcma_fetch_responses;
    wire [31:0] adpcmb_fetch_requests, adpcmb_fetch_responses;
    wire [6:0] pcm_occupancy;
    wire parser_underflow, adpcma_underflow, adpcmb_underflow;
    wire stale_response, owner_mismatch, busy_timeout, write_while_busy;
    wire memory_timeout;
    wire memory_request_held, memory_outstanding;
    wire [1:0] memory_held_owner, memory_outstanding_owner;
    wire [22:0] last_memory_accept_addr, last_memory_response_addr;
    wire [7:0] last_memory_accept_generation;
    wire [7:0] last_memory_response_generation;
    wire pcm_request_held, pcm_response_pending, pcm_held_space_b;
    wire [19:0] pcm_held_logical_addr;
    wire [31:0] player_heartbeat, ddr_heartbeat;
    wire [15:0] peak_l, peak_r;
    wire [7:0] psg_a, psg_b, psg_c;
    wire [9:0] psg_snd;
    wire signed [15:0] adpcma_l, adpcma_r, adpcmb_l, adpcmb_r;
    wire video_ce, video_hs, video_vs, video_de;
    wire [7:0] video_r, video_g, video_b;
    wire [15:0] video_frame_heartbeat, video_line_heartbeat;
    wire fatal_active = core_fatal_active || load_error || overflow_error;
    wire [7:0] fatal_code = core_fatal_active ? core_fatal_code : 8'h0f;
    wire [7:0] first_fatal_code;
    wire [3:0] recorded_player_state, recorded_parser_state;
    wire [4:0] recorded_scanner_state;
    wire recorded_request_held, recorded_outstanding;
    wire [1:0] recorded_held_owner, recorded_outstanding_owner;
    wire [22:0] recorded_last_accept_addr, recorded_last_response_addr;
    wire [7:0] recorded_load_generation;
    wire [7:0] recorded_last_accept_generation;
    wire [7:0] recorded_last_response_generation;
    wire [31:0] recorded_player_heartbeat, recorded_ddr_heartbeat;
    wire [31:0] recorded_scanner_start_count;
    wire [31:0] recorded_playback_start_count;
    wire [31:0] recorded_parser_command_count;
    wire [31:0] recorded_a_fetch_requests, recorded_a_fetch_responses;
    wire [31:0] recorded_b_fetch_requests, recorded_b_fetch_responses;
    wire [15:0] recorded_upload_fifo_debug;
    wire recorded_upload_partial_valid, recorded_pcm_request_held;
    wire recorded_pcm_response_pending, recorded_pcm_held_space_b;
    wire recorded_memory_request, recorded_ddram_busy;
    wire [5:0] recorded_error_flags;

    pll u_pll (
        .refclk(CLK_50M), .rst(1'b0), .outclk_0(clk_sys),
        .locked(pll_locked)
    );

    ym2610_player_reset_controller u_reset_controller (
        .ref_clk(CLK_50M), .clk(clk_sys), .pll_locked(pll_locked),
        .shell_reset(RESET),
        .software_reset(soft_reset), .video_reset(video_reset),
        .player_reset(player_reset), .por_active(por_active),
        .last_reset_source(last_reset_source),
        .pll_unlock_observed(pll_unlock_observed),
        .video_reset_edge_count(video_reset_edge_count)
    );

    always_ff @(posedge clk_sys or negedge pll_locked) begin
        if (!pll_locked)
            upload_abort_hold <= 1'b0;
        else if ((soft_reset ||
                  (player_reset && (pll_unlock_observed ||
                                    last_reset_source == 3'd2))) &&
                 ioctl_download)
            upload_abort_hold <= 1'b1;
        else if (!ioctl_download)
            upload_abort_hold <= 1'b0;
    end

    hps_io #(.CONF_STR(CONF_STR)) u_hps_io (
        .clk_sys(clk_sys), .HPS_BUS(HPS_BUS), .buttons(buttons),
        .status(status), .status_menumask({direct_video}),
        .forced_scandoubler(forced_scandoubler),
        .video_rotated(1'b0), .new_vmode(1'b0),
        .direct_video(direct_video), .gamma_bus(gamma_bus),
        .ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
        .ioctl_index(ioctl_index), .ioctl_wait(ioctl_wait)
    );

    megavgm_title_receiver #(.FILE_INDEX(16'd1)) u_title_receiver (
        .clk(clk_sys), .reset(player_reset),
        .ioctl_download(backend_ioctl_download),
        .ioctl_wr(backend_ioctl_wr), .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout), .ioctl_index(ioctl_index),
        .title_valid(title_valid),
        .directory_length(title_directory_length),
        .basename_length(title_basename_length),
        .title_read_addr(title_read_addr), .title_read_data(title_read_data),
        .metadata_busy(title_metadata_busy)
    );

    vgm_ddram_backend #(
        .ADDR_WIDTH(23), .ACCEPT_ANY_INDEX(1'b0), .FILE_INDEX(8'd1),
        .DDRAM_ADDR_WIDTH(29), .DDRAM_BASE_ADDR(29'd0),
        .SEGAPCM_ROM_BASE_ADDR(29'h0010_0000), .WRITE_FIFO_DEPTH(64)
    ) u_backend (
        .clk(clk_sys), .reset(player_reset),
        .ioctl_download(backend_ioctl_download), .ioctl_wr(backend_ioctl_wr),
        .ioctl_addr({5'd0, ioctl_addr}), .ioctl_dout(ioctl_dout),
        .ioctl_index(ioctl_index[7:0]), .ioctl_wait(backend_ioctl_wait),
        .mem_rd_req(backend_mem_req), .mem_rd_addr(backend_mem_addr),
        .mem_rd_ready(backend_mem_ready), .mem_rd_valid(backend_mem_valid),
        .mem_rd_data(backend_mem_data), .segapcm_copy_wr_req(1'b0),
        .segapcm_copy_wr_ready(), .segapcm_copy_wr_addr(19'd0),
        .segapcm_copy_wr_data(8'd0), .segapcm_copy_flush_req(1'b0),
        .segapcm_copy_flush_done(), .segapcm_copy_accept_count_debug(),
        .segapcm_copy_write_count_debug(),
        .segapcm_copy_fifo_debug(backend_fifo_debug),
        .segapcm_copy_ready_debug(backend_ready_debug),
        .segapcm_copy_write_req_debug(),
        .segapcm_copy_word_debug(backend_word_debug),
        .segapcm_copy_flush_debug(),
        .segapcm_copy_full_detect_count_debug(),
        .segapcm_copy_push_req_count_debug(),
        .segapcm_copy_push_fire_count_debug(),
        .segapcm_copy_fifo_push_count_debug(),
        .segapcm_copy_pack_ready_debug(), .segapcm_copy_post_push_debug(),
        .segapcm_read_gate_debug(), .segapcm_read_after_copy_count_debug(),
        .load_busy(load_busy), .load_done(load_done),
        .load_done_pulse(load_done_pulse),
        .play_ready_pulse(play_ready_pulse), .load_error(load_error),
        .overflow_error(overflow_error), .file_size(file_size),
        .magic_debug(magic_debug), .ddram_busy(DDRAM_BUSY),
        .ddram_burstcnt(DDRAM_BURSTCNT), .ddram_addr(DDRAM_ADDR),
        .ddram_dout(DDRAM_DOUT), .ddram_dout_ready(DDRAM_DOUT_READY),
        .ddram_rd(DDRAM_RD), .ddram_din(DDRAM_DIN), .ddram_be(DDRAM_BE),
        .ddram_we(DDRAM_WE)
    );

    ym2610_player_load_fence u_load_fence (
        .clk(clk_sys), .reset(player_reset),
        .ioctl_download(backend_ioctl_download), .load_busy(load_busy),
        .load_done(load_done), .play_ready_pulse(play_ready_pulse),
        .load_error(load_error), .overflow_error(overflow_error),
        .fifo_debug(backend_fifo_debug),
        .ready_debug(backend_ready_debug), .word_debug(backend_word_debug),
        .ddram_busy(DDRAM_BUSY), .ddram_rd(DDRAM_RD), .ddram_we(DDRAM_WE),
        .scanner_ready_pulse(scanner_ready_pulse),
        .load_generation(load_generation), .fence_count(load_fence_count),
        .fence_waiting(load_fence_waiting), .fence_stable(load_fence_stable)
    );

    ym2610_player_core u_player (
        .clk(clk_sys), .hard_reset(player_reset), .soft_reset(1'b0),
        .ioctl_download(backend_ioctl_download),
        .load_done_pulse(scanner_ready_pulse), .file_size(file_size),
        .load_generation(load_generation), .mem_req(backend_mem_req),
        .mem_addr(backend_mem_addr), .mem_ready(backend_mem_ready),
        .mem_valid(backend_mem_valid), .mem_data(backend_mem_data),
        .audio_l(audio_l), .audio_r(audio_r), .audio_sample(audio_sample),
        .external_mute(external_mute), .start_pulse(start_pulse),
        .start_count(start_count), .scanner_start_count(scanner_start_count),
        .load_state(load_state), .scanner_state(scanner_state),
        .parser_state(parser_state),
        .parser_command_count(parser_command_count),
        .fatal_active(core_fatal_active), .fatal_code(core_fatal_code),
        .classification(classification), .raw_variant_b(raw_variant_b),
        .reject_code(reject_code),
        .original_size(original_size), .parser_pc(parser_pc),
        .parser_opcode(parser_opcode), .wait_remaining(wait_remaining),
        .parser_samples(parser_samples), .parser_writes(parser_writes),
        .port0_writes(port0_writes), .port1_writes(port1_writes),
        .loop_count(loop_count), .descriptor_a_count(descriptor_a_count),
        .descriptor_b_count(descriptor_b_count),
        .b_only_writes(b_only_writes), .unknown_writes(unknown_writes),
        .first_bad_pc(first_bad_pc), .first_bad_port(first_bad_port),
        .first_bad_address(first_bad_address), .first_bad_data(first_bad_data),
        .unsupported_pc(unsupported_pc),
        .unsupported_opcode(unsupported_opcode),
        .pcm_requests(pcm_requests), .pcm_responses(pcm_responses),
        .adpcma_requests(adpcma_requests), .adpcmb_requests(adpcmb_requests),
        .pcm_last_address(pcm_last_address), .pcm_occupancy(pcm_occupancy),
        .adpcma_last_address(adpcma_last_address),
        .adpcmb_last_address(adpcmb_last_address),
        .adpcma_fetch_requests(adpcma_fetch_requests),
        .adpcma_fetch_responses(adpcma_fetch_responses),
        .adpcmb_fetch_requests(adpcmb_fetch_requests),
        .adpcmb_fetch_responses(adpcmb_fetch_responses),
        .parser_underflow(parser_underflow),
        .adpcma_underflow(adpcma_underflow),
        .adpcmb_underflow(adpcmb_underflow),
        .stale_response(stale_response), .owner_mismatch(owner_mismatch),
        .busy_timeout(busy_timeout), .write_while_busy(write_while_busy),
        .memory_timeout(memory_timeout),
        .memory_request_held(memory_request_held),
        .memory_outstanding(memory_outstanding),
        .memory_held_owner(memory_held_owner),
        .memory_outstanding_owner(memory_outstanding_owner),
        .last_memory_accept_addr(last_memory_accept_addr),
        .last_memory_response_addr(last_memory_response_addr),
        .last_memory_accept_generation(last_memory_accept_generation),
        .last_memory_response_generation(last_memory_response_generation),
        .pcm_request_held(pcm_request_held),
        .pcm_response_pending(pcm_response_pending),
        .pcm_held_space_b(pcm_held_space_b),
        .pcm_held_logical_addr(pcm_held_logical_addr),
        .player_heartbeat(player_heartbeat), .ddr_heartbeat(ddr_heartbeat),
        .peak_l(peak_l), .peak_r(peak_r), .psg_a(psg_a), .psg_b(psg_b),
        .psg_c(psg_c), .psg_snd(psg_snd), .adpcma_l(adpcma_l),
        .adpcma_r(adpcma_r), .adpcmb_l(adpcmb_l), .adpcmb_r(adpcmb_r)
    );

    ym2610_player_diagnostics u_diagnostics (
        .clk(clk_sys), .reset(player_reset || backend_ioctl_download),
        .fatal_active(fatal_active), .fatal_code(fatal_code),
        .player_state(load_state), .scanner_state(scanner_state),
        .parser_state(parser_state), .memory_request(backend_mem_req),
        .request_held(memory_request_held),
        .outstanding(memory_outstanding), .ddram_busy(DDRAM_BUSY),
        .held_owner(memory_held_owner),
        .outstanding_owner(memory_outstanding_owner),
        .last_accept_addr(last_memory_accept_addr),
        .last_response_addr(last_memory_response_addr),
        .load_generation(load_generation),
        .last_accept_generation(last_memory_accept_generation),
        .last_response_generation(last_memory_response_generation),
        .player_heartbeat(player_heartbeat), .ddr_heartbeat(ddr_heartbeat),
        .scanner_start_count(scanner_start_count),
        .playback_start_count(start_count),
        .parser_command_count(parser_command_count),
        .adpcma_fetch_requests(adpcma_fetch_requests),
        .adpcma_fetch_responses(adpcma_fetch_responses),
        .adpcmb_fetch_requests(adpcmb_fetch_requests),
        .adpcmb_fetch_responses(adpcmb_fetch_responses),
        .upload_fifo_debug(backend_fifo_debug),
        .upload_partial_valid(backend_word_debug[2]),
        .pcm_request_held(pcm_request_held),
        .pcm_response_pending(pcm_response_pending),
        .pcm_held_space_b(pcm_held_space_b),
        .parser_underflow(parser_underflow),
        .adpcma_underflow(adpcma_underflow),
        .adpcmb_underflow(adpcmb_underflow),
        .stale_response(stale_response), .owner_mismatch(owner_mismatch),
        .response_timeout(memory_timeout),
        .first_fatal_code(first_fatal_code),
        .recorded_player_state(recorded_player_state),
        .recorded_scanner_state(recorded_scanner_state),
        .recorded_parser_state(recorded_parser_state),
        .recorded_memory_request(recorded_memory_request),
        .recorded_request_held(recorded_request_held),
        .recorded_outstanding(recorded_outstanding),
        .recorded_ddram_busy(recorded_ddram_busy),
        .recorded_held_owner(recorded_held_owner),
        .recorded_outstanding_owner(recorded_outstanding_owner),
        .recorded_last_accept_addr(recorded_last_accept_addr),
        .recorded_last_response_addr(recorded_last_response_addr),
        .recorded_load_generation(recorded_load_generation),
        .recorded_last_accept_generation(recorded_last_accept_generation),
        .recorded_last_response_generation(recorded_last_response_generation),
        .recorded_player_heartbeat(recorded_player_heartbeat),
        .recorded_ddr_heartbeat(recorded_ddr_heartbeat),
        .recorded_scanner_start_count(recorded_scanner_start_count),
        .recorded_playback_start_count(recorded_playback_start_count),
        .recorded_parser_command_count(recorded_parser_command_count),
        .recorded_adpcma_fetch_requests(recorded_a_fetch_requests),
        .recorded_adpcma_fetch_responses(recorded_a_fetch_responses),
        .recorded_adpcmb_fetch_requests(recorded_b_fetch_requests),
        .recorded_adpcmb_fetch_responses(recorded_b_fetch_responses),
        .recorded_upload_fifo_debug(recorded_upload_fifo_debug),
        .recorded_upload_partial_valid(recorded_upload_partial_valid),
        .recorded_pcm_request_held(recorded_pcm_request_held),
        .recorded_pcm_response_pending(recorded_pcm_response_pending),
        .recorded_pcm_held_space_b(recorded_pcm_held_space_b),
        .recorded_error_flags(recorded_error_flags)
    );

    ym2610_player_video u_video (
        .clk(clk_sys), .reset(video_reset), .debug_view(status[3:2]),
        .title_valid(title_valid), .directory_length(title_directory_length),
        .basename_length(title_basename_length),
        .title_read_addr(title_read_addr), .title_read_data(title_read_data),
        .load_state(load_state), .original_size(original_size),
        .raw_variant_b(raw_variant_b), .classification(classification),
        .reject_code(reject_code), .first_bad_pc(first_bad_pc),
        .first_bad_port(first_bad_port),
        .first_bad_address(first_bad_address),
        .first_bad_data(first_bad_data), .parser_pc(parser_pc),
        .parser_opcode(parser_opcode), .wait_remaining(wait_remaining),
        .port0_writes(port0_writes), .port1_writes(port1_writes),
        .start_count(fatal_active ? recorded_playback_start_count : start_count),
        .loop_count(loop_count),
        .unsupported_pc(unsupported_pc),
        .unsupported_opcode(unsupported_opcode),
        .descriptor_a_count(descriptor_a_count),
        .descriptor_b_count(descriptor_b_count), .pcm_requests(pcm_requests),
        .pcm_responses(pcm_responses), .adpcma_requests(adpcma_requests),
        .adpcmb_requests(adpcmb_requests), .pcm_last_address(pcm_last_address),
        .adpcma_last_address(adpcma_last_address),
        .adpcmb_last_address(adpcmb_last_address),
        .adpcma_fetch_requests(fatal_active ? recorded_a_fetch_requests :
                                              adpcma_fetch_requests),
        .adpcma_fetch_responses(fatal_active ? recorded_a_fetch_responses :
                                               adpcma_fetch_responses),
        .adpcmb_fetch_requests(fatal_active ? recorded_b_fetch_requests :
                                              adpcmb_fetch_requests),
        .adpcmb_fetch_responses(fatal_active ? recorded_b_fetch_responses :
                                               adpcmb_fetch_responses),
        .pcm_occupancy(pcm_occupancy), .adpcma_underflow(adpcma_underflow),
        .adpcmb_underflow(adpcmb_underflow),
        .stale_response(stale_response), .owner_mismatch(owner_mismatch),
        .fatal_active(fatal_active),
        .fatal_code(first_fatal_code != 0 ? first_fatal_code : fatal_code),
        .fatal_error_flags(recorded_error_flags),
        .scanner_state(fatal_active ? recorded_scanner_state : scanner_state),
        .parser_state(fatal_active ? recorded_parser_state : parser_state),
        .memory_held_owner(fatal_active ? recorded_held_owner :
                                          memory_held_owner),
        .memory_outstanding_owner(fatal_active ? recorded_outstanding_owner :
                                                 memory_outstanding_owner),
        .memory_request(fatal_active ? recorded_memory_request :
                                      backend_mem_req),
        .memory_request_held(fatal_active ? recorded_request_held :
                                            memory_request_held),
        .memory_outstanding(fatal_active ? recorded_outstanding :
                                          memory_outstanding),
        .ddram_busy(fatal_active ? recorded_ddram_busy : DDRAM_BUSY),
        .last_memory_accept_addr(fatal_active ? recorded_last_accept_addr :
                                               last_memory_accept_addr),
        .last_memory_response_addr(fatal_active ? recorded_last_response_addr :
                                                 last_memory_response_addr),
        .load_generation(fatal_active ? recorded_load_generation :
                                        load_generation),
        .last_accept_generation(fatal_active ?
            recorded_last_accept_generation : last_memory_accept_generation),
        .last_response_generation(fatal_active ?
            recorded_last_response_generation : last_memory_response_generation),
        .last_reset_source(last_reset_source),
        .video_reset_edge_count(video_reset_edge_count),
        .pll_unlock_observed(pll_unlock_observed),
        .player_heartbeat(fatal_active ? recorded_player_heartbeat :
                                          player_heartbeat),
        .ddr_heartbeat(fatal_active ? recorded_ddr_heartbeat : ddr_heartbeat),
        .scanner_start_count(fatal_active ? recorded_scanner_start_count :
                                             scanner_start_count),
        .parser_command_count(fatal_active ? recorded_parser_command_count :
                                              parser_command_count),
        .upload_fifo_debug(fatal_active ? recorded_upload_fifo_debug :
                                          backend_fifo_debug),
        .upload_partial_valid(fatal_active ? recorded_upload_partial_valid :
                                             backend_word_debug[2]),
        .pcm_request_held(fatal_active ? recorded_pcm_request_held :
                                        pcm_request_held),
        .pcm_response_pending(fatal_active ? recorded_pcm_response_pending :
                                            pcm_response_pending),
        .pcm_held_space_b(fatal_active ? recorded_pcm_held_space_b :
                                        pcm_held_space_b),
        .peak_l(peak_l), .peak_r(peak_r), .ce_pixel(video_ce),
        .hsync(video_hs), .vsync(video_vs), .de(video_de),
        .red(video_r), .green(video_g), .blue(video_b),
        .frame_heartbeat(video_frame_heartbeat),
        .line_heartbeat(video_line_heartbeat)
    );

    assign CLK_VIDEO = clk_sys;
    assign CE_PIXEL = video_ce;
    assign VGA_R = video_r;
    assign VGA_G = video_g;
    assign VGA_B = video_b;
    assign VGA_HS = video_hs;
    assign VGA_VS = video_vs;
    assign VGA_DE = video_de;
    assign VIDEO_ARX = 13'd4;
    assign VIDEO_ARY = 13'd3;
    assign VGA_F1 = 1'b0;
    assign VGA_SL = 2'b00;
    assign VGA_SCALER = 1'b0;
    assign VGA_DISABLE = 1'b0;
    assign HDMI_FREEZE = 1'b0;
    assign HDMI_BLACKOUT = 1'b0;
    assign AUDIO_L = player_reset ? 16'd0 : audio_l;
    assign AUDIO_R = player_reset ? 16'd0 : audio_r;
    assign AUDIO_S = 1'b1;
    assign AUDIO_MIX = 2'b00;
    assign LED_USER = (load_state == 4'd9) || load_error || overflow_error;
    assign LED_POWER = 2'b00;
    assign LED_DISK = 2'b00;
    assign BUTTONS = 2'b00;
    assign ADC_BUS = 4'hz;
    assign USER_OUT = 7'h7f;
    assign VGM_PLAYER_STATE = ioctl_download || load_busy ? 2'd1 :
                              load_state == 4'd7 ? 2'd2 : 2'd0;
    assign {UART_RTS, UART_TXD, UART_DTR} = 3'b000;
    assign {SD_SCK, SD_MOSI, SD_CS} = 3'bzzz;
    assign DDRAM_CLK = clk_sys;
    assign {SDRAM_CLK, SDRAM_CKE, SDRAM_A, SDRAM_BA,
            SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nCAS,
            SDRAM_nRAS, SDRAM_nWE} = '0;
    assign SDRAM_DQ = 16'hzzzz;
`ifdef MISTER_DUAL_SDRAM
    assign {SDRAM2_CLK, SDRAM2_A, SDRAM2_BA,
            SDRAM2_nCS, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nWE} = '0;
    assign SDRAM2_DQ = 16'hzzzz;
`endif
`ifdef MISTER_FB
    assign FB_EN = 1'b0;
    assign FB_FORMAT = 5'd0;
    assign FB_WIDTH = 12'd0;
    assign FB_HEIGHT = 12'd0;
    assign FB_BASE = 32'd0;
    assign FB_STRIDE = 14'd0;
    assign FB_FORCE_BLANK = 1'b0;
`ifdef MISTER_FB_PALETTE
    assign FB_PAL_CLK = clk_sys;
    assign FB_PAL_ADDR = 8'd0;
    assign FB_PAL_DOUT = 24'd0;
    assign FB_PAL_WR = 1'b0;
`endif
`endif
endmodule
