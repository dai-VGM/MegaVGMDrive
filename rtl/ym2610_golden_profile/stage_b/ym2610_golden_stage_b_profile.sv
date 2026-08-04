// SPDX-License-Identifier: GPL-2.0-or-later
// Versioned drop-in implementation of the immutable Stage A profile boundary.
// The module name and ports intentionally remain identical so the proven
// Golden Shell shim is reused byte-for-byte. Stage B only reads and classifies.
`timescale 1ns/1ps

module ym2610_golden_stage_a #(
    parameter int VGM_ADDR_WIDTH = 23
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
    output logic signed [15:0]        audio_l,
    output logic signed [15:0]        audio_r,
    output logic                      audio_sample_valid,
    output logic                      playback_active,
    output logic                      profile_fatal,
    output logic [15:0]               profile_status,
    output logic [15:0]               debug_page_data,
    output logic [31:0]               parser_start_count,
    output logic [31:0]               scanner_start_count,
    output logic [31:0]               sound_write_count
);
    localparam int TRAILER_SIZE = 128;
    localparam logic [7:0] ADAPTER_REJECT_TIMEOUT = 8'h09;
    localparam logic [7:0] ADAPTER_REJECT_STALE   = 8'h0a;

    typedef enum logic [3:0] {
        LC_WAIT_LOAD,
        LC_COMPLETE_FENCE,
        LC_META_REQUEST,
        LC_META_RESPONSE,
        LC_META_VALIDATE,
        LC_SCAN_FENCE,
        LC_SCAN_BUSY,
        LC_ACCEPTED_IDLE,
        LC_REJECTED_IDLE
    } lifecycle_t;

    lifecycle_t lifecycle_state;
    logic download_d;
    logic generation_valid;
    logic [7:0] load_generation;
    logic [1:0] fence_count;
    logic [7:0] trailer [0:TRAILER_SIZE-1];
    logic [7:0] trailer_index;
    logic [31:0] exact_original_size;
    logic original_size_valid;
    logic prepared_file;
    logic scan_start;
    logic scanner_abort;

    logic meta_req;
    logic [VGM_ADDR_WIDTH-1:0] meta_addr;
    logic scan_mem_req;
    logic [VGM_ADDR_WIDTH-1:0] scan_mem_addr;
    logic client_req;
    logic [VGM_ADDR_WIDTH-1:0] client_addr;
    logic client_ready;
    logic client_valid;
    logic [7:0] client_data;
    logic adapter_outstanding;
    logic adapter_timeout;
    logic adapter_stale;
    logic [31:0] ddr_accept_count;
    logic [31:0] ddr_response_count;

    logic scan_busy;
    logic scan_done;
    logic scan_accepted;
    logic [3:0] scan_classification;
    logic [7:0] scan_reject_code;
    logic [31:0] scan_original_size;
    logic [31:0] scan_data_offset;
    logic [31:0] scan_chip_clock;
    logic [31:0] scan_loop_target;
    logic [31:0] scan_loop_samples;
    logic [31:0] scan_end_pc;
    logic [31:0] scan_total_samples;
    logic [31:0] scan_total_writes;
    logic [31:0] scan_port0_writes;
    logic [31:0] scan_port1_writes;
    logic [31:0] scan_b_only_writes;
    logic [31:0] scan_unknown_writes;
    logic [31:0] scan_command_count;
    logic [31:0] scan_unsupported_opcodes;
    logic [31:0] scan_ssg_writes;
    logic [31:0] scan_adpcma_key_on_voices;
    logic [31:0] scan_adpcma_key_off_voices;
    logic [31:0] scan_adpcmb_start_count;
    logic [31:0] scan_adpcmb_reset_count;
    logic [63:0] scan_trace_hash;
    logic [63:0] scan_first256_trace_hash;
    logic [4:0] scan_debug_state;
    logic scan_variant_b;
    logic scan_dual_chip;
    logic [31:0] scan_first_bad_pc;
    logic scan_first_bad_port;
    logic [7:0] scan_first_bad_address;
    logic [7:0] scan_first_bad_data;
    logic [31:0] scan_first_bad_sample;
    logic [3:0] scan_first_bad_semantic;
    logic [2:0] scan_first_bad_target;
    logic [3:0] scan_descriptor_a_count;
    logic [3:0] scan_descriptor_b_count;
    logic scan_map_hit;
    logic [VGM_ADDR_WIDTH-1:0] scan_map_file_addr;
    logic [7:0] profile_reject_code;

    function automatic [31:0] trailer32(input integer offset);
        trailer32 = {trailer[offset+3], trailer[offset+2],
                     trailer[offset+1], trailer[offset]};
    endfunction

    function automatic logic trailer_valid;
        integer byte_index;
        logic valid;
        begin
            valid =
                trailer[0] == 8'h4d && trailer[1] == 8'h56 &&
                trailer[2] == 8'h47 && trailer[3] == 8'h4d &&
                trailer[4] == 8'h54 && trailer[5] == 8'h54 &&
                trailer[6] == 8'h4c && trailer[7] == 8'h00 &&
                trailer[8] == 8'h01 && trailer[9][7:2] == 6'd0 &&
                trailer[10] <= 8'd32 && trailer[11] <= 8'd48 &&
                trailer[12] == 8'h80 && trailer[13] == 8'h00 &&
                trailer[14] == 8'h00 && trailer[15] == 8'h00 &&
                trailer32(16) >= 32'h80 &&
                trailer32(16) <= 32'hffff_ff7f &&
                trailer32(16) + 32'd128 == uploaded_physical_size &&
                trailer[9][0] == (trailer[10] != 0) &&
                trailer[9][1] == (trailer[11] != 0);
            for (byte_index = 20; byte_index < 32; byte_index = byte_index + 1)
                if (trailer[byte_index] != 0) valid = 1'b0;
            for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1) begin
                if (byte_index < trailer[10]) begin
                    if (trailer[32+byte_index] < 8'h20 ||
                        trailer[32+byte_index] > 8'h7e) valid = 1'b0;
                end else if (trailer[32+byte_index] != 0) valid = 1'b0;
            end
            for (byte_index = 0; byte_index < 64; byte_index = byte_index + 1) begin
                if (byte_index < trailer[11]) begin
                    if (trailer[64+byte_index] < 8'h20 ||
                        trailer[64+byte_index] > 8'h7e) valid = 1'b0;
                end else if (trailer[64+byte_index] != 0) valid = 1'b0;
            end
            trailer_valid = valid;
        end
    endfunction

    assign meta_req = (lifecycle_state == LC_META_REQUEST);
    assign meta_addr = uploaded_physical_size[VGM_ADDR_WIDTH-1:0] -
                       VGM_ADDR_WIDTH'(TRAILER_SIZE) +
                       {{(VGM_ADDR_WIDTH-8){1'b0}}, trailer_index};
    assign client_req = meta_req || scan_mem_req;
    assign client_addr = meta_req ? meta_addr : scan_mem_addr;

    ym2610_golden_stage_b_read_adapter #(
        .ADDR_WIDTH(VGM_ADDR_WIDTH)
    ) read_adapter (
        .clk(clk_sys), .reset(reset), .cancel(scanner_abort),
        .download_active(download_active), .load_generation(load_generation),
        .client_req(client_req), .client_addr(client_addr),
        .client_ready(client_ready), .client_valid(client_valid),
        .client_data(client_data), .file_req(file_read_request),
        .file_addr(file_read_address), .file_ready(file_read_ready),
        .file_valid(file_read_valid), .file_data(file_read_data),
        .outstanding(adapter_outstanding), .timeout_error(adapter_timeout),
        .stale_response_error(adapter_stale),
        .accepted_count(ddr_accept_count), .response_count(ddr_response_count)
    );

    ym2610_golden_stage_b_scanner #(
        .ADDR_WIDTH(VGM_ADDR_WIDTH), .MAX_DESCRIPTORS(8)
    ) scanner (
        .clk(clk_sys), .reset(reset || download_active || scanner_abort),
        .start(scan_start), .scan_limit(exact_original_size),
        .mem_req(scan_mem_req), .mem_addr(scan_mem_addr),
        .mem_ready(client_ready), .mem_valid(client_valid),
        .mem_data(client_data), .busy(scan_busy), .done(scan_done),
        .accepted(scan_accepted), .classification(scan_classification),
        .reject_code(scan_reject_code), .original_size(scan_original_size),
        .data_offset(scan_data_offset), .chip_clock(scan_chip_clock),
        .loop_target(scan_loop_target), .loop_samples(scan_loop_samples),
        .end_pc(scan_end_pc), .total_samples(scan_total_samples),
        .total_writes(scan_total_writes), .port0_writes(scan_port0_writes),
        .port1_writes(scan_port1_writes), .b_only_writes(scan_b_only_writes),
        .unknown_writes(scan_unknown_writes), .command_count(scan_command_count),
        .unsupported_opcodes(scan_unsupported_opcodes),
        .ssg_writes(scan_ssg_writes),
        .adpcma_key_on_voices(scan_adpcma_key_on_voices),
        .adpcma_key_off_voices(scan_adpcma_key_off_voices),
        .adpcmb_start_count(scan_adpcmb_start_count),
        .adpcmb_reset_count(scan_adpcmb_reset_count),
        .trace_hash(scan_trace_hash),
        .first256_trace_hash(scan_first256_trace_hash),
        .debug_state(scan_debug_state), .variant_b(scan_variant_b),
        .dual_chip(scan_dual_chip), .first_bad_pc(scan_first_bad_pc),
        .first_bad_port(scan_first_bad_port),
        .first_bad_address(scan_first_bad_address),
        .first_bad_data(scan_first_bad_data),
        .first_bad_sample(scan_first_bad_sample),
        .first_bad_semantic(scan_first_bad_semantic),
        .first_bad_target(scan_first_bad_target),
        .descriptor_a_count(scan_descriptor_a_count),
        .descriptor_b_count(scan_descriptor_b_count),
        .map_space_b(1'b0), .map_logical_addr(20'd0),
        .map_hit(scan_map_hit), .map_file_addr(scan_map_file_addr)
    );

    always_ff @(posedge clk_sys) begin
        scan_start <= 1'b0;
        scanner_abort <= 1'b0;
        download_d <= download_active;

        if (reset) begin
            lifecycle_state <= LC_WAIT_LOAD;
            download_d <= 1'b0;
            generation_valid <= 1'b0;
            load_generation <= 8'd0;
            fence_count <= 2'd0;
            trailer_index <= 8'd0;
            exact_original_size <= 32'd0;
            original_size_valid <= 1'b0;
            prepared_file <= 1'b0;
            scanner_start_count <= 32'd0;
            profile_reject_code <= 8'd0;
        end else if (download_active) begin
            if (!download_d) begin
                load_generation <= load_generation + 8'd1;
                generation_valid <= 1'b1;
            end
            lifecycle_state <= LC_WAIT_LOAD;
            fence_count <= 2'd0;
            trailer_index <= 8'd0;
            exact_original_size <= 32'd0;
            original_size_valid <= 1'b0;
            prepared_file <= 1'b0;
            profile_reject_code <= 8'd0;
        end else if ((adapter_timeout || adapter_stale) &&
                     lifecycle_state != LC_WAIT_LOAD &&
                     lifecycle_state != LC_REJECTED_IDLE) begin
            scanner_abort <= 1'b1;
            profile_reject_code <= adapter_timeout ?
                ADAPTER_REJECT_TIMEOUT : ADAPTER_REJECT_STALE;
            lifecycle_state <= LC_REJECTED_IDLE;
        end else begin
            case (lifecycle_state)
                LC_WAIT_LOAD: begin
                    fence_count <= 2'd0;
                    if (generation_valid && upload_complete &&
                        uploaded_physical_size >= 32'h80)
                        lifecycle_state <= LC_COMPLETE_FENCE;
                end

                LC_COMPLETE_FENCE: begin
                    if (!upload_complete) begin
                        fence_count <= 2'd0;
                        lifecycle_state <= LC_WAIT_LOAD;
                    end else if (fence_count == 2'd1) begin
                        fence_count <= 2'd0;
                        trailer_index <= 8'd0;
                        lifecycle_state <= LC_META_REQUEST;
                    end else begin
                        fence_count <= fence_count + 2'd1;
                    end
                end

                LC_META_REQUEST: begin
                    if (client_ready)
                        lifecycle_state <= LC_META_RESPONSE;
                end

                LC_META_RESPONSE: begin
                    if (client_valid) begin
                        trailer[trailer_index] <= client_data;
                        if (trailer_index == 8'd127)
                            lifecycle_state <= LC_META_VALIDATE;
                        else begin
                            trailer_index <= trailer_index + 8'd1;
                            lifecycle_state <= LC_META_REQUEST;
                        end
                    end
                end

                LC_META_VALIDATE: begin
                    if (trailer_valid()) begin
                        exact_original_size <= trailer32(16);
                        prepared_file <= 1'b1;
                    end else begin
                        exact_original_size <= uploaded_physical_size;
                        prepared_file <= 1'b0;
                    end
                    original_size_valid <= 1'b1;
                    fence_count <= 2'd0;
                    lifecycle_state <= LC_SCAN_FENCE;
                end

                LC_SCAN_FENCE: begin
                    if (!upload_complete || !original_size_valid ||
                        adapter_outstanding) begin
                        fence_count <= 2'd0;
                    end else if (fence_count == 2'd1) begin
                        scan_start <= 1'b1;
                        scanner_start_count <= scanner_start_count + 32'd1;
                        fence_count <= 2'd0;
                        lifecycle_state <= LC_SCAN_BUSY;
                    end else begin
                        fence_count <= fence_count + 2'd1;
                    end
                end

                LC_SCAN_BUSY: begin
                    if (scan_done) begin
                        profile_reject_code <= scan_reject_code;
                        if (scan_accepted)
                            lifecycle_state <= LC_ACCEPTED_IDLE;
                        else
                            lifecycle_state <= LC_REJECTED_IDLE;
                    end
                end

                LC_ACCEPTED_IDLE: begin end
                LC_REJECTED_IDLE: begin end
                default: lifecycle_state <= LC_WAIT_LOAD;
            endcase
        end
    end

    assign pcm_a_read_request = 1'b0;
    assign pcm_a_read_address = '0;
    assign pcm_b_read_request = 1'b0;
    assign pcm_b_read_address = '0;
    assign audio_l = 16'sd0;
    assign audio_r = 16'sd0;
    assign audio_sample_valid = 1'b0;
    assign playback_active = 1'b0;
    assign profile_fatal = 1'b0;
    assign profile_status = {
        8'd0,
        prepared_file,
        adapter_stale,
        adapter_timeout,
        adapter_outstanding,
        lifecycle_state == LC_SCAN_BUSY,
        lifecycle_state == LC_REJECTED_IDLE,
        lifecycle_state == LC_ACCEPTED_IDLE,
        generation_valid
    };
    assign debug_page_data = {scan_classification, lifecycle_state,
                              profile_reject_code};
    assign parser_start_count = 32'd0;
    assign sound_write_count = 32'd0;

    wire unused_shell_inputs = ^{
        osd_audio_lpf_mode, osd_audio_gain_boost, osd_audio_psg_level,
        title_valid, title_text_byte, shell_sample_timing,
        scan_busy, scan_original_size, scan_data_offset, scan_chip_clock,
        scan_loop_target, scan_loop_samples, scan_end_pc, scan_total_samples,
        scan_total_writes, scan_port0_writes, scan_port1_writes,
        scan_b_only_writes, scan_unknown_writes, scan_command_count,
        scan_unsupported_opcodes, scan_ssg_writes,
        scan_adpcma_key_on_voices, scan_adpcma_key_off_voices,
        scan_adpcmb_start_count, scan_adpcmb_reset_count,
        scan_trace_hash, scan_first256_trace_hash, scan_debug_state,
        scan_variant_b, scan_dual_chip, scan_first_bad_pc,
        scan_first_bad_port, scan_first_bad_address, scan_first_bad_data,
        scan_first_bad_sample, scan_first_bad_semantic, scan_first_bad_target,
        scan_descriptor_a_count, scan_descriptor_b_count,
        scan_map_hit, scan_map_file_addr, ddr_accept_count, ddr_response_count
    };
endmodule
