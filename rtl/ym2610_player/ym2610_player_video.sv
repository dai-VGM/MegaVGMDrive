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
    input  logic [15:0] peak_l,
    input  logic [15:0] peak_r,
    output logic       ce_pixel,
    output logic       hsync,
    output logic       vsync,
    output logic       de,
    output logic [7:0] red,
    output logic [7:0] green,
    output logic [7:0] blue
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
        .enable(debug_view != 0), .pcm_page(debug_view == 2),
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
        .peak_l(peak_l), .peak_r(peak_r), .background(debug_background),
        .text_pixel(debug_text)
    );

    always_comb begin
        if (!de)
            rgb = 24'h000000;
        else if (debug_view != 0)
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
endmodule
