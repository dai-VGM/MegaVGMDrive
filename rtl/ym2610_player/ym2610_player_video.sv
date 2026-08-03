`timescale 1ns/1ps

module ym2610_player_video (
    input  logic       clk,
    input  logic       reset,
    input  logic [1:0] debug_view,
    input  logic       title_valid,
    input  logic [5:0] directory_length,
    input  logic [5:0] basename_length,
    output logic [6:0] title_read_addr,
    input  logic [7:0] title_read_data,
    input  logic [3:0] load_state,
    input  logic [31:0] original_size,
    input  logic       raw_variant_b,
    input  logic [3:0] classification,
    input  logic [7:0] reject_code,
    input  logic [31:0] first_bad_pc,
    input  logic       first_bad_port,
    input  logic [7:0] first_bad_address,
    input  logic [7:0] first_bad_data,
    input  logic [31:0] parser_pc,
    input  logic [7:0] parser_opcode,
    input  logic [31:0] wait_remaining,
    input  logic [31:0] port0_writes,
    input  logic [31:0] port1_writes,
    input  logic [31:0] start_count,
    input  logic [31:0] loop_count,
    input  logic [31:0] unsupported_pc,
    input  logic [7:0] unsupported_opcode,
    input  logic [3:0] descriptor_a_count,
    input  logic [3:0] descriptor_b_count,
    input  logic [31:0] pcm_requests,
    input  logic [31:0] pcm_responses,
    input  logic [31:0] adpcma_requests,
    input  logic [31:0] adpcmb_requests,
    input  logic [31:0] adpcma_fetch_requests,
    input  logic [31:0] adpcma_fetch_responses,
    input  logic [31:0] adpcmb_fetch_requests,
    input  logic [31:0] adpcmb_fetch_responses,
    input  logic [19:0] pcm_last_address,
    input  logic [19:0] adpcma_last_address,
    input  logic [19:0] adpcmb_last_address,
    input  logic [6:0] pcm_occupancy,
    input  logic       adpcma_underflow,
    input  logic       adpcmb_underflow,
    input  logic       stale_response,
    input  logic       owner_mismatch,
    input  logic       fatal_active,
    input  logic [7:0] fatal_code,
    input  logic [5:0] fatal_error_flags,
    input  logic [4:0] scanner_state,
    input  logic [3:0] parser_state,
    input  logic [1:0] memory_held_owner,
    input  logic [1:0] memory_outstanding_owner,
    input  logic       memory_request,
    input  logic       memory_request_held,
    input  logic       memory_outstanding,
    input  logic       ddram_busy,
    input  logic [22:0] last_memory_accept_addr,
    input  logic [22:0] last_memory_response_addr,
    input  logic [7:0] load_generation,
    input  logic [7:0] last_accept_generation,
    input  logic [7:0] last_response_generation,
    input  logic [2:0] last_reset_source,
    input  logic [15:0] video_reset_edge_count,
    input  logic       pll_unlock_observed,
    input  logic [31:0] player_heartbeat,
    input  logic [31:0] ddr_heartbeat,
    input  logic [31:0] scanner_start_count,
    input  logic [31:0] parser_command_count,
    input  logic [15:0] upload_fifo_debug,
    input  logic       upload_partial_valid,
    input  logic       pcm_request_held,
    input  logic       pcm_response_pending,
    input  logic       pcm_held_space_b,
    input  logic [15:0] peak_l,
    input  logic [15:0] peak_r,
    output logic       ce_pixel,
    output logic       hsync,
    output logic       vsync,
    output logic       de,
    output logic [7:0] red,
    output logic [7:0] green,
    output logic [7:0] blue,
    output logic [15:0] frame_heartbeat,
    output logic [15:0] line_heartbeat
);
    logic [9:0] h_count;
    logic [8:0] v_count;
    logic hblank, vblank, vblank_start;
    logic title_text, title_panel;
    logic [23:0] title_rgb;
    logic debug_background, debug_text;
    logic [23:0] rgb;

    megavgm_video_timing u_timing (
        .clk_video(clk), .reset(reset), .ce_pix(ce_pixel),
        .h_count(h_count), .v_count(v_count), .hblank(hblank),
        .vblank(vblank), .hsync(hsync), .vsync(vsync), .de(de),
        .vblank_start(vblank_start)
    );

    megavgm_title_renderer u_title (
        .h_count(h_count), .v_count(v_count), .drawing_active(de),
        .title_valid(title_valid), .directory_length(directory_length),
        .basename_length(basename_length), .title_read_addr(title_read_addr),
        .title_read_data(title_read_data), .text_pixel(title_text),
        .panel_pixel(title_panel), .panel_rgb(title_rgb)
    );

    ym2610_player_debug_renderer u_debug (
        .enable(debug_view != 0 || fatal_active), .pcm_page(debug_view == 2),
        .h_count(h_count), .v_count(v_count), .drawing_active(de),
        .load_state(load_state), .original_size(original_size),
        .raw_variant_b(raw_variant_b),
        .classification(classification), .reject_code(reject_code),
        .first_bad_pc(first_bad_pc), .first_bad_port(first_bad_port),
        .first_bad_address(first_bad_address),
        .first_bad_data(first_bad_data), .parser_pc(parser_pc),
        .parser_opcode(parser_opcode), .wait_remaining(wait_remaining),
        .port0_writes(port0_writes), .port1_writes(port1_writes),
        .start_count(start_count), .loop_count(loop_count),
        .unsupported_pc(unsupported_pc),
        .unsupported_opcode(unsupported_opcode),
        .descriptor_a_count(descriptor_a_count),
        .descriptor_b_count(descriptor_b_count), .pcm_requests(pcm_requests),
        .pcm_responses(pcm_responses), .adpcma_requests(adpcma_requests),
        .adpcmb_requests(adpcmb_requests),
        .adpcma_fetch_requests(adpcma_fetch_requests),
        .adpcma_fetch_responses(adpcma_fetch_responses),
        .adpcmb_fetch_requests(adpcmb_fetch_requests),
        .adpcmb_fetch_responses(adpcmb_fetch_responses),
        .pcm_last_address(pcm_last_address),
        .adpcma_last_address(adpcma_last_address),
        .adpcmb_last_address(adpcmb_last_address),
        .pcm_occupancy(pcm_occupancy), .adpcma_underflow(adpcma_underflow),
        .adpcmb_underflow(adpcmb_underflow),
        .stale_response(stale_response), .owner_mismatch(owner_mismatch),
        .fatal_active(fatal_active), .fatal_code(fatal_code),
        .fatal_error_flags(fatal_error_flags),
        .scanner_state(scanner_state), .parser_state(parser_state),
        .memory_held_owner(memory_held_owner),
        .memory_outstanding_owner(memory_outstanding_owner),
        .memory_request(memory_request),
        .memory_request_held(memory_request_held),
        .memory_outstanding(memory_outstanding),
        .ddram_busy(ddram_busy),
        .last_memory_accept_addr(last_memory_accept_addr),
        .last_memory_response_addr(last_memory_response_addr),
        .load_generation(load_generation),
        .last_accept_generation(last_accept_generation),
        .last_response_generation(last_response_generation),
        .last_reset_source(last_reset_source),
        .video_reset_edge_count(video_reset_edge_count),
        .pll_unlock_observed(pll_unlock_observed),
        .video_frame_heartbeat(frame_heartbeat),
        .video_line_heartbeat(line_heartbeat),
        .player_heartbeat(player_heartbeat), .ddr_heartbeat(ddr_heartbeat),
        .scanner_start_count(scanner_start_count),
        .parser_command_count(parser_command_count),
        .upload_fifo_debug(upload_fifo_debug),
        .upload_partial_valid(upload_partial_valid),
        .pcm_request_held(pcm_request_held),
        .pcm_response_pending(pcm_response_pending),
        .pcm_held_space_b(pcm_held_space_b),
        .peak_l(peak_l), .peak_r(peak_r), .background(debug_background),
        .text_pixel(debug_text)
    );

    always_comb begin
        if (!de)
            rgb = 24'h000000;
        else if (fatal_active || debug_view != 0)
            rgb = debug_text ? 24'he8f0ff : 24'h000818;
        else if (title_text)
            rgb = 24'he8f0ff;
        else if (title_panel)
            rgb = title_rgb;
        else
            rgb = 24'h000000;
        red = rgb[23:16];
        green = rgb[15:8];
        blue = rgb[7:0];
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            frame_heartbeat <= 16'd0;
            line_heartbeat <= 16'd0;
        end else begin
            if (vblank_start)
                frame_heartbeat <= frame_heartbeat + 16'd1;
            if (ce_pixel && h_count == 10'd0)
                line_heartbeat <= line_heartbeat + 16'd1;
        end
    end
endmodule
