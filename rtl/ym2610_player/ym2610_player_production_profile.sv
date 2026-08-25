// SPDX-License-Identifier: GPL-2.0-or-later
//
// YM2610 production profile for the immutable Golden Player Shell v1.1 ABI.
// The shell owns HPS/ioctl, physical DDR upload, title, video, and reset. This
// module is only the logical DDR client and the already-validated YM2610
// player/audio backend.

`timescale 1ns/1ps

module golden_player_shell_v1_1_profile #(
    parameter int VGM_ADDR_WIDTH = 23,
    parameter int CLK_SYS_HZ = 20_000_000
) (
    input  logic                      clk_sys,
    input  logic                      reset,
    input  logic                      download_active,
    input  logic [31:0]               uploaded_physical_size,
    input  logic                      upload_complete,
    input  logic                      file_read_ready,
    input  logic                      file_read_valid,
    input  logic [7:0]                file_read_data,
    output logic                      file_read_request,
    output logic [VGM_ADDR_WIDTH-1:0] file_read_address,
    output logic                      pcm_a_read_request,
    output logic [VGM_ADDR_WIDTH-1:0] pcm_a_read_address,
    output logic                      pcm_b_read_request,
    output logic [VGM_ADDR_WIDTH-1:0] pcm_b_read_address,
    input  logic [1:0]                osd_audio_lpf_mode,
    input  logic                      osd_audio_gain_boost,
    input  logic [1:0]                osd_audio_psg_level,
    input  logic                      title_valid,
    input  logic [7:0]                title_text_byte,
    input  logic                      shell_sample_timing,
    output logic signed [15:0]        profile_audio_l,
    output logic signed [15:0]        profile_audio_r,
    output logic                      profile_audio_sample_valid,
    output logic                      profile_audio_enable,
    output logic                      playback_active,
    output logic                      profile_fatal,
    output logic [15:0]               profile_status,
    output logic [15:0]               debug_page_data,
    output logic [31:0]               parser_start_count,
    output logic [31:0]               scanner_start_count,
    output logic [31:0]               sound_write_count
);
`ifdef YM2610B_PLAYER
    localparam ENABLE_YM2610B = 1;
`else
    localparam ENABLE_YM2610B = 0;
`endif
    logic download_q;
    logic upload_session_armed;
    logic core_load_done_pulse;
    logic [7:0] load_generation;

    logic core_mem_req;
    logic [VGM_ADDR_WIDTH-1:0] core_mem_addr;
    logic signed [15:0] core_audio_l;
    logic signed [15:0] core_audio_r;
    logic core_audio_sample;
    logic core_external_mute;
    logic [31:0] core_start_count;
    logic [31:0] core_scanner_start_count;
    logic [3:0] core_load_state;
    logic [31:0] core_parser_command_count;
    logic core_fatal;
    logic [7:0] core_fatal_code;
`ifdef YM2610B_METAL_SLUG_REJECT_UART_LAB
    logic [3:0] core_classification;
    logic [31:0] core_parser_pc;
    logic [31:0] core_parser_samples;
    logic [31:0] core_loop_count;
    logic lab_ym_port;
    logic [7:0] lab_ym_register, lab_ym_value, lab_bus_dout;
    logic [3:0] lab_bus_state;
    logic [15:0] lab_bus_watchdog;
    logic [23:0] lab_adpcma_logical, lab_adpcmb_logical;
    logic lab_a_current_hit, lab_a_next_hit;
    logic lab_b_current_hit, lab_b_next_hit;
    logic lab_request_active, lab_request_pending, lab_request_space_b;
    logic [23:0] lab_request_logical;
    logic lab_response_valid, lab_response_hit, lab_response_space_b;
    logic [VGM_ADDR_WIDTH-1:0] lab_response_file_addr;
    logic lab_last_fill_valid, lab_last_fill_space_b;
    logic [23:0] lab_last_fill_logical;
    logic lab_uart_tx;
    logic core_busy_timeout;
`endif
`ifdef YM2610_GF_RG1_PROBE
    logic core_range_fault_valid;
    logic [19:0] core_range_fault_addr;
    logic core_range_fault_current;
`endif
`ifdef YM2610_GF_PERSISTENT_RANGE_PROBE
    logic core_diag_range_fault_valid;
    logic [19:0] core_diag_range_fault_addr;
    logic core_diag_range_fault_current;
`endif

    // The physical backend's upload_complete level is asserted only after an
    // accepted index-1 upload has ended and its final write has drained. One
    // generation is allocated at the raw download edge and published once,
    // after raw download has returned low. No backend debug signal participates.
    always_ff @(posedge clk_sys) begin
        core_load_done_pulse <= 1'b0;
        if (reset) begin
            download_q <= 1'b0;
            upload_session_armed <= 1'b0;
            load_generation <= 8'd0;
        end else begin
            download_q <= download_active;

            if (download_active && !download_q) begin
                upload_session_armed <= 1'b1;
                load_generation <= load_generation + 8'd1;
            end

            if (upload_session_armed && upload_complete &&
                !download_active) begin
                core_load_done_pulse <= 1'b1;
                upload_session_armed <= 1'b0;
            end
        end
    end

    ym2610_player_core #(
        .SYS_CLK_HZ(CLK_SYS_HZ),
        .ADDR_WIDTH(VGM_ADDR_WIDTH),
        .ENABLE_YM2610B(ENABLE_YM2610B)
    ) production_player (
        .clk(clk_sys),
        .hard_reset(reset),
        .soft_reset(1'b0),
        .ioctl_download(download_active),
        .load_done_pulse(core_load_done_pulse),
        .file_size(uploaded_physical_size),
        .load_generation(load_generation),
        .mem_req(core_mem_req),
        .mem_addr(core_mem_addr),
        .mem_ready(file_read_ready),
        .mem_valid(file_read_valid),
        .mem_data(file_read_data),
        .audio_l(core_audio_l),
        .audio_r(core_audio_r),
        .audio_sample(core_audio_sample),
        .external_mute(core_external_mute),
        .start_pulse(),
        .start_count(core_start_count),
        .scanner_start_count(core_scanner_start_count),
        .load_state(core_load_state),
        .scanner_state(),
        .parser_state(),
        .parser_command_count(core_parser_command_count),
        .fatal_active(core_fatal),
        .fatal_code(core_fatal_code),
`ifdef YM2610B_METAL_SLUG_REJECT_UART_LAB
        .classification(core_classification),
`else
        .classification(),
`endif
        .raw_variant_b(),
        .reject_code(),
        .original_size(),
`ifdef YM2610B_METAL_SLUG_REJECT_UART_LAB
        .parser_pc(core_parser_pc),
`else
        .parser_pc(),
`endif
        .parser_opcode(),
        .wait_remaining(),
`ifdef YM2610B_METAL_SLUG_REJECT_UART_LAB
        .parser_samples(core_parser_samples),
`else
        .parser_samples(),
`endif
        .parser_writes(),
        .port0_writes(),
        .port1_writes(),
`ifdef YM2610B_METAL_SLUG_REJECT_UART_LAB
        .loop_count(core_loop_count),
`else
        .loop_count(),
`endif
        .descriptor_a_count(),
        .descriptor_b_count(),
        .b_only_writes(),
        .unknown_writes(),
        .first_bad_pc(),
        .first_bad_port(),
        .first_bad_address(),
        .first_bad_data(),
        .unsupported_pc(),
        .unsupported_opcode(),
        .pcm_requests(),
        .pcm_responses(),
        .adpcma_requests(),
        .adpcmb_requests(),
        .pcm_last_address(),
        .adpcma_last_address(),
        .adpcmb_last_address(),
`ifdef YM2610_GF_RG1_PROBE
        .range_fault_valid(core_range_fault_valid),
        .range_fault_addr(core_range_fault_addr),
        .range_fault_current(core_range_fault_current),
`endif
`ifdef YM2610_GF_PERSISTENT_RANGE_PROBE
        .diag_range_fault_valid(core_diag_range_fault_valid),
        .diag_range_fault_addr(core_diag_range_fault_addr),
        .diag_range_fault_current(core_diag_range_fault_current),
`endif
        .adpcma_fetch_requests(),
        .adpcma_fetch_responses(),
        .adpcmb_fetch_requests(),
        .adpcmb_fetch_responses(),
        .pcm_occupancy(),
        .parser_underflow(),
        .adpcma_underflow(),
        .adpcmb_underflow(),
        .stale_response(),
        .owner_mismatch(),
`ifdef YM2610B_METAL_SLUG_REJECT_UART_LAB
        .busy_timeout(core_busy_timeout),
`else
        .busy_timeout(),
`endif
        .write_while_busy(),
        .memory_timeout(),
        .memory_request_held(),
        .memory_outstanding(),
        .memory_held_owner(),
        .memory_outstanding_owner(),
        .last_memory_accept_addr(),
        .last_memory_response_addr(),
        .last_memory_accept_generation(),
        .last_memory_response_generation(),
        .pcm_request_held(),
        .pcm_response_pending(),
        .pcm_held_space_b(),
        .pcm_held_logical_addr(),
        .player_heartbeat(),
        .ddr_heartbeat(),
        .peak_l(),
        .peak_r(),
        .psg_a(),
        .psg_b(),
        .psg_c(),
        .psg_snd(),
        .adpcma_l(),
        .adpcma_r(),
        .adpcmb_l(),
        .adpcmb_r()
`ifdef YM2610B_METAL_SLUG_REJECT_UART_LAB
        ,.lab_ym_port(lab_ym_port),
        .lab_ym_register(lab_ym_register),
        .lab_ym_value(lab_ym_value),
        .lab_bus_state(lab_bus_state),
        .lab_bus_dout(lab_bus_dout),
        .lab_bus_watchdog(lab_bus_watchdog),
        .lab_adpcma_logical(lab_adpcma_logical),
        .lab_adpcmb_logical(lab_adpcmb_logical),
        .lab_a_current_hit(lab_a_current_hit),
        .lab_a_next_hit(lab_a_next_hit),
        .lab_b_current_hit(lab_b_current_hit),
        .lab_b_next_hit(lab_b_next_hit),
        .lab_request_active(lab_request_active),
        .lab_request_pending(lab_request_pending),
        .lab_request_space_b(lab_request_space_b),
        .lab_request_logical(lab_request_logical),
        .lab_response_valid(lab_response_valid),
        .lab_response_hit(lab_response_hit),
        .lab_response_file_addr(lab_response_file_addr),
        .lab_response_space_b(lab_response_space_b),
        .lab_last_fill_valid(lab_last_fill_valid),
        .lab_last_fill_space_b(lab_last_fill_space_b),
        .lab_last_fill_logical(lab_last_fill_logical)
`endif
    );

    assign file_read_request = core_mem_req;
    assign file_read_address = core_mem_addr;

    // The existing player core already arbitrates scanner, parser, and both
    // PCM spaces onto the single immutable shell read-client boundary.
    assign pcm_a_read_request = 1'b0;
    assign pcm_a_read_address = '0;
    assign pcm_b_read_request = 1'b0;
    assign pcm_b_read_address = '0;

    // Normal mode is a wire-only handoff. No YM2610 selector or post-mix
    // arithmetic is introduced in this candidate.
    assign profile_audio_l = core_audio_l;
    assign profile_audio_r = core_audio_r;
    assign profile_audio_sample_valid = core_audio_sample;
    assign profile_audio_enable = !reset && !core_external_mute;
    assign playback_active = core_load_state == 4'd7;
    ym2610_gunfrontier_reject_probe u_gunfrontier_reject_probe (
        .fatal_active(core_fatal), .reject_code(core_fatal_code),
`ifdef YM2610_GF_RG1_PROBE
        .range_fault_valid(core_range_fault_valid),
        .range_fault_addr(core_range_fault_addr),
        .range_fault_current(core_range_fault_current),
`endif
`ifdef YM2610_GF_PERSISTENT_RANGE_PROBE
        .diag_range_fault_valid(core_diag_range_fault_valid),
        .diag_range_fault_addr(core_diag_range_fault_addr),
        .diag_range_fault_current(core_diag_range_fault_current),
`endif
        .profile_fatal(profile_fatal)
    );
    assign profile_status = {core_fatal, 3'd0, core_fatal_code,
                             core_load_state};
`ifdef YM2610B_METAL_SLUG_REJECT_UART_LAB
    ym2610b_metal_slug_reject_serial_observer #(
        .CLK_HZ(CLK_SYS_HZ), .BAUD(115_200)
    ) u_metal_slug_reject_observer (
        .clk(clk_sys), .reset(reset || download_active),
        .capture(core_fatal && core_fatal_code >= 8'h09),
        .reject_code(core_fatal_code),
        .classification(core_classification),
        .sample_count(core_parser_samples), .vgm_pc(core_parser_pc),
        .loop_count(core_loop_count), .ym_port(lab_ym_port),
        .ym_register(lab_ym_register), .ym_value(lab_ym_value),
        .bus_state(lab_bus_state), .bus_dout(lab_bus_dout),
        .busy_timeout(core_busy_timeout),
        .bus_watchdog(lab_bus_watchdog),
        .adpcma_logical(lab_adpcma_logical),
        .adpcmb_logical(lab_adpcmb_logical),
        .a_current_hit(lab_a_current_hit), .a_next_hit(lab_a_next_hit),
        .b_current_hit(lab_b_current_hit), .b_next_hit(lab_b_next_hit),
        .request_active(lab_request_active),
        .request_pending(lab_request_pending),
        .request_space_b(lab_request_space_b),
        .request_logical(lab_request_logical),
        .response_valid(lab_response_valid),
        .response_hit(lab_response_hit),
        .response_space_b(lab_response_space_b),
        .response_file_addr(lab_response_file_addr),
        .last_fill_valid(lab_last_fill_valid),
        .last_fill_space_b(lab_last_fill_space_b),
        .last_fill_logical(lab_last_fill_logical),
        .uart_tx(lab_uart_tx), .frozen(), .sent()
    );
    assign debug_page_data = {15'd0, lab_uart_tx};
`else
    assign debug_page_data = 16'd0;
`endif
    assign parser_start_count = core_start_count;
    assign scanner_start_count = core_scanner_start_count;
    assign sound_write_count = core_parser_command_count;

    wire unused_shell_profile_inputs = ^{
        osd_audio_lpf_mode,
        osd_audio_gain_boost,
        osd_audio_psg_level,
        title_valid,
        title_text_byte,
        shell_sample_timing
    };

endmodule

// Lab-only external diagnostic gate.  The normal build preserves the
// established profile_fatal = fatal_active contract exactly.  Probe macros
// only select which existing reject-code bit is presented at that ABI output;
// they have no fanout into the player core or audio path.
module ym2610_gunfrontier_reject_probe (
    input  logic       fatal_active,
    input  logic [7:0] reject_code,
`ifdef YM2610_GF_RG1_PROBE
    input  logic       range_fault_valid,
    input  logic [19:0] range_fault_addr,
    input  logic       range_fault_current,
`endif
`ifdef YM2610_GF_PERSISTENT_RANGE_PROBE
    input  logic       diag_range_fault_valid,
    input  logic [19:0] diag_range_fault_addr,
    input  logic       diag_range_fault_current,
`endif
    output logic       profile_fatal
);
`ifdef YM2610_GF_PERSISTENT_VALID_PROBE
    assign profile_fatal = fatal_active && reject_code == 8'h0b &&
                           diag_range_fault_valid;
`elsif YM2610_GF_PERSISTENT_CURRENT_PROBE
    assign profile_fatal = fatal_active && reject_code == 8'h0b &&
                           diag_range_fault_valid &&
                           diag_range_fault_current;
`elsif YM2610_GF_PERSISTENT_RG1_PROBE
    assign profile_fatal = fatal_active && reject_code == 8'h0b &&
                           diag_range_fault_valid &&
                           diag_range_fault_addr == 20'h07600 &&
                           diag_range_fault_current;
`elsif YM2610_GF_RG1_VALID_PROBE
    assign profile_fatal = fatal_active && reject_code == 8'h0b &&
                           range_fault_valid;
`elsif YM2610_GF_RG1_CURRENT_PROBE
    assign profile_fatal = fatal_active && reject_code == 8'h0b &&
                           range_fault_valid && range_fault_current;
`elsif YM2610_GF_RG1_ADDR_PROBE
    assign profile_fatal = fatal_active && reject_code == 8'h0b &&
                           range_fault_valid && range_fault_addr == 20'h07600;
`elsif YM2610_GF_RG1_PROBE
    assign profile_fatal = fatal_active && reject_code == 8'h0b &&
                           range_fault_valid && range_fault_addr == 20'h07600 &&
                           range_fault_current;
`elsif YM2610_GF_REJECT_PROBE_BIT0
    assign profile_fatal = fatal_active && reject_code[0];
`elsif YM2610_GF_REJECT_PROBE_BIT1
    assign profile_fatal = fatal_active && reject_code[1];
`elsif YM2610_GF_REJECT_PROBE_BIT2
    assign profile_fatal = fatal_active && reject_code[2];
`else
    assign profile_fatal = fatal_active;
`endif
endmodule
