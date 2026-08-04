// SPDX-License-Identifier: GPL-2.0-or-later
// Versioned Stage C drop-in for the immutable Golden Player Shell boundary.
`timescale 1ns/1ps

module ym2610_golden_stage_a #(
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
    localparam int SOUND_RESET_CYCLES = 32;
    localparam logic [7:0] REJECT_TIMEOUT = 8'h09;
    localparam logic [7:0] REJECT_STALE   = 8'h0a;
    localparam logic [7:0] REJECT_CLOCK   = 8'h0b;
    localparam logic [7:0] REJECT_OWNER   = 8'h0c;
    localparam logic [7:0] REJECT_SOUND   = 8'h0d;

    typedef enum logic [4:0] {
        LC_WAIT_LOAD,
        LC_COMPLETE_FENCE,
        LC_META_REQUEST,
        LC_META_RESPONSE,
        LC_META_VALIDATE,
        LC_SCAN_FENCE,
        LC_SCAN_BUSY,
        LC_HANDOFF,
        LC_SOUND_RESET,
        LC_SOUND_ZERO_WAIT,
        LC_PLAYBACK_ARM,
        LC_PLAYBACK,
        LC_REJECTED_IDLE,
        LC_ENDED_IDLE,
        LC_FATAL
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
    logic parser_start;
    logic [5:0] sound_reset_count;
    logic [7:0] profile_reject_code;

    logic meta_req;
    logic [VGM_ADDR_WIDTH-1:0] meta_addr;
    logic scan_mem_req;
    logic [VGM_ADDR_WIDTH-1:0] scan_mem_addr;
    logic scanner_client_req;
    logic [VGM_ADDR_WIDTH-1:0] scanner_client_addr;
    logic scanner_client_ready;
    logic scanner_client_valid;
    logic [7:0] scanner_client_data;
    logic parser_mem_req;
    logic [VGM_ADDR_WIDTH-1:0] parser_mem_addr;
    logic parser_mem_ready;
    logic parser_mem_valid;
    logic [7:0] parser_mem_data;

    logic owner_client_req;
    logic [VGM_ADDR_WIDTH-1:0] owner_client_addr;
    logic owner_client_ready;
    logic owner_client_valid;
    logic [7:0] owner_client_data;
    logic [1:0] read_owner;
    logic parser_owned;
    logic owner_transition_error;
    logic [31:0] owner_transition_count;
    logic scanner_enable;
    logic parser_handoff;
    logic owner_cancel;

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

    logic parser_active;
    logic parser_ended;
    logic parser_fatal;
    logic [7:0] parser_fatal_code;
    logic parser_loop_event;
    logic [31:0] parser_current_pc;
    logic [31:0] parser_timeline_sample;
    logic [31:0] parser_command_count;
    logic [31:0] parser_write_count;
    logic [31:0] parser_forwarded_fm_count;
    logic [31:0] parser_forwarded_ssg_count;
    logic [31:0] parser_suppressed_a_count;
    logic [31:0] parser_suppressed_b_count;
    logic [31:0] parser_data_block_count;
    logic [31:0] parser_loop_count;
    logic [63:0] parser_trace_hash;
    logic [63:0] parser_first256_trace_hash;
    logic parser_trace_valid;
    logic [31:0] parser_trace_command_pc;
    logic [31:0] parser_trace_sample;
    logic parser_trace_port;
    logic [7:0] parser_trace_address;
    logic [7:0] parser_trace_data;
    logic [3:0] parser_trace_semantic;
    logic parser_trace_forwarded;
    logic [31:0] parser_trace_next_pc;
    logic [63:0] parser_trace_sound_accept_cycle;

    logic sound_write_req;
    logic sound_write_port;
    logic [7:0] sound_write_address;
    logic [7:0] sound_write_data;
    logic sound_write_accept;
    logic sound_write_busy;
    logic sound_busy_timeout;
    logic sound_write_while_busy;
    logic [31:0] sound_accepted_write_count;
    logic signed [15:0] sound_audio_l;
    logic signed [15:0] sound_audio_r;
    logic sound_audio_sample_valid;
    logic signed [15:0] sound_fm_l;
    logic signed [15:0] sound_fm_r;
    logic [7:0] sound_psg_a;
    logic [7:0] sound_psg_b;
    logic [7:0] sound_psg_c;
    logic [9:0] sound_psg_snd;
    logic signed [15:0] sound_adpcma_l;
    logic signed [15:0] sound_adpcma_r;
    logic signed [15:0] sound_adpcmb_l;
    logic signed [15:0] sound_adpcmb_r;
    logic sound_adpcma_request;
    logic sound_adpcmb_request;
    logic [19:0] sound_adpcma_addr;
    logic [3:0] sound_adpcma_bank;
    logic [23:0] sound_adpcmb_addr;
    logic sound_unexpected_pcm_request;
    logic sound_unexpected_pcm_activity;
    logic sound_core_ready;
    logic sound_public_sample_rise;
    logic sound_cen;
    logic [31:0] sound_cen_accumulator;
    logic sound_clock_invalid;
    logic sound_core_reset;
    logic sound_publish_enable;
    logic sound_fault;
    logic parser_abort;
    logic timeline_tick;
    logic [31:0] timeline_accumulator;
    logic [32:0] timeline_sum;

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

    assign meta_req = lifecycle_state == LC_META_REQUEST;
    assign meta_addr = uploaded_physical_size[VGM_ADDR_WIDTH-1:0] -
                       VGM_ADDR_WIDTH'(TRAILER_SIZE) +
                       {{(VGM_ADDR_WIDTH-8){1'b0}}, trailer_index};
    assign scanner_client_req = meta_req || scan_mem_req;
    assign scanner_client_addr = meta_req ? meta_addr : scan_mem_addr;

    assign scanner_enable =
        lifecycle_state == LC_COMPLETE_FENCE ||
        lifecycle_state == LC_META_REQUEST ||
        lifecycle_state == LC_META_RESPONSE ||
        lifecycle_state == LC_META_VALIDATE ||
        lifecycle_state == LC_SCAN_FENCE ||
        lifecycle_state == LC_SCAN_BUSY ||
        lifecycle_state == LC_HANDOFF;
    assign parser_handoff = lifecycle_state == LC_HANDOFF;
    assign owner_cancel =
        download_active || lifecycle_state == LC_WAIT_LOAD ||
        lifecycle_state == LC_REJECTED_IDLE ||
        lifecycle_state == LC_ENDED_IDLE || lifecycle_state == LC_FATAL;

    assign parser_abort =
        download_active ||
        !(lifecycle_state == LC_PLAYBACK_ARM ||
          lifecycle_state == LC_PLAYBACK ||
          lifecycle_state == LC_ENDED_IDLE);
    assign sound_core_reset =
        reset || download_active ||
        !(lifecycle_state == LC_SOUND_ZERO_WAIT ||
          lifecycle_state == LC_PLAYBACK_ARM ||
          lifecycle_state == LC_PLAYBACK);
    assign sound_publish_enable =
        lifecycle_state == LC_SOUND_ZERO_WAIT ||
        lifecycle_state == LC_PLAYBACK_ARM ||
        lifecycle_state == LC_PLAYBACK;
    assign sound_fault =
        sound_busy_timeout || sound_write_while_busy ||
        sound_unexpected_pcm_request || sound_unexpected_pcm_activity ||
        sound_clock_invalid;
    assign timeline_sum = {1'b0, timeline_accumulator} + 33'd44_100;

    // The immutable Golden Shell keeps shell_sample_timing tied low. Stage C
    // therefore owns the 44.1 kHz VGM timeline locally. Holding the phase at
    // zero outside playback makes cold load, reload, and software reset match.
    always_ff @(posedge clk_sys) begin
        if (reset || download_active || lifecycle_state != LC_PLAYBACK) begin
            timeline_accumulator <= 32'd0;
            timeline_tick <= 1'b0;
        end else if (timeline_sum >= CLK_SYS_HZ) begin
            timeline_accumulator <= timeline_sum[31:0] - CLK_SYS_HZ;
            timeline_tick <= 1'b1;
        end else begin
            timeline_accumulator <= timeline_sum[31:0];
            timeline_tick <= 1'b0;
        end
    end

    ym2610_golden_stage_b_read_adapter #(
        .ADDR_WIDTH(VGM_ADDR_WIDTH)
    ) u_read_adapter (
        .clk(clk_sys),
        .reset(reset),
        .cancel(owner_cancel || scanner_abort),
        .download_active(download_active),
        .load_generation(load_generation),
        .client_req(owner_client_req),
        .client_addr(owner_client_addr),
        .client_ready(owner_client_ready),
        .client_valid(owner_client_valid),
        .client_data(owner_client_data),
        .file_req(file_read_request),
        .file_addr(file_read_address),
        .file_ready(file_read_ready),
        .file_valid(file_read_valid),
        .file_data(file_read_data),
        .outstanding(adapter_outstanding),
        .timeout_error(adapter_timeout),
        .stale_response_error(adapter_stale),
        .accepted_count(ddr_accept_count),
        .response_count(ddr_response_count)
    );

    ym2610_golden_stage_c_owner #(
        .ADDR_WIDTH(VGM_ADDR_WIDTH)
    ) u_owner (
        .clk(clk_sys),
        .reset(reset),
        .cancel(owner_cancel),
        .scanner_enable(scanner_enable),
        .parser_handoff(parser_handoff),
        .adapter_outstanding(adapter_outstanding),
        .scanner_req(scanner_client_req),
        .scanner_addr(scanner_client_addr),
        .scanner_ready(scanner_client_ready),
        .scanner_valid(scanner_client_valid),
        .scanner_data(scanner_client_data),
        .parser_req(parser_mem_req),
        .parser_addr(parser_mem_addr),
        .parser_ready(parser_mem_ready),
        .parser_valid(parser_mem_valid),
        .parser_data(parser_mem_data),
        .client_req(owner_client_req),
        .client_addr(owner_client_addr),
        .client_ready(owner_client_ready),
        .client_valid(owner_client_valid),
        .client_data(owner_client_data),
        .owner(read_owner),
        .parser_owned(parser_owned),
        .transition_error(owner_transition_error),
        .transition_count(owner_transition_count)
    );

    ym2610_golden_stage_b_scanner #(
        .ADDR_WIDTH(VGM_ADDR_WIDTH),
        .MAX_DESCRIPTORS(8)
    ) u_scanner (
        .clk(clk_sys),
        .reset(reset || download_active || scanner_abort),
        .start(scan_start),
        .scan_limit(exact_original_size),
        .mem_req(scan_mem_req),
        .mem_addr(scan_mem_addr),
        .mem_ready(scanner_client_ready),
        .mem_valid(scanner_client_valid),
        .mem_data(scanner_client_data),
        .busy(scan_busy),
        .done(scan_done),
        .accepted(scan_accepted),
        .classification(scan_classification),
        .reject_code(scan_reject_code),
        .original_size(scan_original_size),
        .data_offset(scan_data_offset),
        .chip_clock(scan_chip_clock),
        .loop_target(scan_loop_target),
        .loop_samples(scan_loop_samples),
        .end_pc(scan_end_pc),
        .total_samples(scan_total_samples),
        .total_writes(scan_total_writes),
        .port0_writes(scan_port0_writes),
        .port1_writes(scan_port1_writes),
        .b_only_writes(scan_b_only_writes),
        .unknown_writes(scan_unknown_writes),
        .command_count(scan_command_count),
        .unsupported_opcodes(scan_unsupported_opcodes),
        .ssg_writes(scan_ssg_writes),
        .adpcma_key_on_voices(scan_adpcma_key_on_voices),
        .adpcma_key_off_voices(scan_adpcma_key_off_voices),
        .adpcmb_start_count(scan_adpcmb_start_count),
        .adpcmb_reset_count(scan_adpcmb_reset_count),
        .trace_hash(scan_trace_hash),
        .first256_trace_hash(scan_first256_trace_hash),
        .debug_state(scan_debug_state),
        .variant_b(scan_variant_b),
        .dual_chip(scan_dual_chip),
        .first_bad_pc(scan_first_bad_pc),
        .first_bad_port(scan_first_bad_port),
        .first_bad_address(scan_first_bad_address),
        .first_bad_data(scan_first_bad_data),
        .first_bad_sample(scan_first_bad_sample),
        .first_bad_semantic(scan_first_bad_semantic),
        .first_bad_target(scan_first_bad_target),
        .descriptor_a_count(scan_descriptor_a_count),
        .descriptor_b_count(scan_descriptor_b_count),
        .map_space_b(1'b0),
        .map_logical_addr(20'd0),
        .map_hit(scan_map_hit),
        .map_file_addr(scan_map_file_addr)
    );

    ym2610_golden_stage_c_parser #(
        .ADDR_WIDTH(VGM_ADDR_WIDTH)
    ) u_parser (
        .clk(clk_sys),
        .reset(reset),
        .abort(parser_abort),
        .start(parser_start),
        .original_size(scan_original_size),
        .data_offset(scan_data_offset),
        .loop_target(scan_loop_target),
        .sample_tick(timeline_tick),
        .mem_req(parser_mem_req),
        .mem_addr(parser_mem_addr),
        .mem_ready(parser_mem_ready),
        .mem_valid(parser_mem_valid),
        .mem_data(parser_mem_data),
        .sound_write_req(sound_write_req),
        .sound_write_port(sound_write_port),
        .sound_write_address(sound_write_address),
        .sound_write_data(sound_write_data),
        .sound_write_accept(sound_write_accept),
        .sound_fault(sound_fault),
        .active(parser_active),
        .ended(parser_ended),
        .fatal(parser_fatal),
        .fatal_code(parser_fatal_code),
        .loop_event(parser_loop_event),
        .current_pc(parser_current_pc),
        .timeline_sample(parser_timeline_sample),
        .command_count(parser_command_count),
        .write_count(parser_write_count),
        .forwarded_fm_global_count(parser_forwarded_fm_count),
        .forwarded_ssg_count(parser_forwarded_ssg_count),
        .suppressed_adpcma_count(parser_suppressed_a_count),
        .suppressed_adpcmb_count(parser_suppressed_b_count),
        .data_block_count(parser_data_block_count),
        .loop_count(parser_loop_count),
        .trace_hash(parser_trace_hash),
        .first256_trace_hash(parser_first256_trace_hash),
        .trace_valid(parser_trace_valid),
        .trace_command_pc(parser_trace_command_pc),
        .trace_sample(parser_trace_sample),
        .trace_port(parser_trace_port),
        .trace_address(parser_trace_address),
        .trace_data(parser_trace_data),
        .trace_semantic(parser_trace_semantic),
        .trace_forwarded(parser_trace_forwarded),
        .trace_next_pc(parser_trace_next_pc),
        .trace_sound_accept_cycle(parser_trace_sound_accept_cycle)
    );

    ym2610_golden_stage_c_sound_adapter #(
        .CLK_SYS_HZ(CLK_SYS_HZ)
    ) u_sound (
        .clk(clk_sys),
        .reset(reset),
        .core_reset(sound_core_reset),
        .publish_enable(sound_publish_enable),
        .chip_clock(scan_chip_clock),
        .write_req(sound_write_req),
        .write_port(sound_write_port),
        .write_address(sound_write_address),
        .write_data(sound_write_data),
        .write_accept(sound_write_accept),
        .write_busy(sound_write_busy),
        .busy_timeout(sound_busy_timeout),
        .write_while_busy(sound_write_while_busy),
        .accepted_write_count(sound_accepted_write_count),
        .audio_l(sound_audio_l),
        .audio_r(sound_audio_r),
        .audio_sample_valid(sound_audio_sample_valid),
        .fm_l(sound_fm_l),
        .fm_r(sound_fm_r),
        .psg_a(sound_psg_a),
        .psg_b(sound_psg_b),
        .psg_c(sound_psg_c),
        .psg_snd(sound_psg_snd),
        .adpcma_l(sound_adpcma_l),
        .adpcma_r(sound_adpcma_r),
        .adpcmb_l(sound_adpcmb_l),
        .adpcmb_r(sound_adpcmb_r),
        .adpcma_request(sound_adpcma_request),
        .adpcmb_request(sound_adpcmb_request),
        .adpcma_addr(sound_adpcma_addr),
        .adpcma_bank(sound_adpcma_bank),
        .adpcmb_addr(sound_adpcmb_addr),
        .unexpected_pcm_request(sound_unexpected_pcm_request),
        .unexpected_pcm_activity(sound_unexpected_pcm_activity),
        .core_ready(sound_core_ready),
        .public_sample_rise(sound_public_sample_rise),
        .cen(sound_cen),
        .cen_accumulator(sound_cen_accumulator),
        .clock_invalid(sound_clock_invalid)
    );

    always_ff @(posedge clk_sys) begin
        scan_start <= 1'b0;
        scanner_abort <= 1'b0;
        parser_start <= 1'b0;
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
            sound_reset_count <= 6'd0;
            profile_reject_code <= 8'd0;
            parser_start_count <= 32'd0;
            scanner_start_count <= 32'd0;
            sound_write_count <= 32'd0;
        end else if (download_active) begin
            if (!download_d) begin
                load_generation <= load_generation + 8'd1;
                generation_valid <= 1'b1;
                parser_start_count <= 32'd0;
                scanner_start_count <= 32'd0;
                sound_write_count <= 32'd0;
            end
            lifecycle_state <= LC_WAIT_LOAD;
            fence_count <= 2'd0;
            trailer_index <= 8'd0;
            exact_original_size <= 32'd0;
            original_size_valid <= 1'b0;
            prepared_file <= 1'b0;
            sound_reset_count <= 6'd0;
            profile_reject_code <= 8'd0;
        end else if ((adapter_timeout || adapter_stale ||
                      owner_transition_error || parser_fatal ||
                      (sound_fault &&
                       (lifecycle_state == LC_SOUND_RESET ||
                        lifecycle_state == LC_SOUND_ZERO_WAIT ||
                        lifecycle_state == LC_PLAYBACK_ARM ||
                        lifecycle_state == LC_PLAYBACK))) &&
                     lifecycle_state != LC_WAIT_LOAD &&
                     lifecycle_state != LC_REJECTED_IDLE &&
                     lifecycle_state != LC_ENDED_IDLE &&
                     lifecycle_state != LC_FATAL) begin
            scanner_abort <= 1'b1;
            if (adapter_timeout)
                profile_reject_code <= REJECT_TIMEOUT;
            else if (adapter_stale)
                profile_reject_code <= REJECT_STALE;
            else if (owner_transition_error)
                profile_reject_code <= REJECT_OWNER;
            else if (parser_fatal)
                profile_reject_code <= parser_fatal_code;
            else
                profile_reject_code <= REJECT_SOUND;
            lifecycle_state <= LC_FATAL;
        end else begin
            if (sound_write_accept)
                sound_write_count <= sound_write_count + 32'd1;

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
                    if (scanner_client_ready)
                        lifecycle_state <= LC_META_RESPONSE;
                end

                LC_META_RESPONSE: begin
                    if (scanner_client_valid) begin
                        trailer[trailer_index] <= scanner_client_data;
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
                        if (!scan_accepted) begin
                            scanner_abort <= 1'b1;
                            lifecycle_state <= LC_REJECTED_IDLE;
                        end else if (scan_chip_clock == 0 ||
                                     scan_chip_clock > CLK_SYS_HZ) begin
                            profile_reject_code <= REJECT_CLOCK;
                            scanner_abort <= 1'b1;
                            lifecycle_state <= LC_REJECTED_IDLE;
                        end else begin
                            lifecycle_state <= LC_HANDOFF;
                        end
                    end
                end

                LC_HANDOFF: begin
                    if (parser_owned) begin
                        sound_reset_count <= 6'd0;
                        lifecycle_state <= LC_SOUND_RESET;
                    end
                end

                LC_SOUND_RESET: begin
                    if (sound_reset_count == SOUND_RESET_CYCLES-1) begin
                        sound_reset_count <= 6'd0;
                        lifecycle_state <= LC_SOUND_ZERO_WAIT;
                    end else begin
                        sound_reset_count <= sound_reset_count + 6'd1;
                    end
                end

                LC_SOUND_ZERO_WAIT: begin
                    if (sound_core_ready && sound_public_sample_rise) begin
                        if (sound_audio_l != 0 || sound_audio_r != 0) begin
                            profile_reject_code <= REJECT_SOUND;
                            lifecycle_state <= LC_FATAL;
                        end else begin
                            lifecycle_state <= LC_PLAYBACK_ARM;
                        end
                    end
                end

                LC_PLAYBACK_ARM: begin
                    parser_start <= 1'b1;
                    parser_start_count <= parser_start_count + 32'd1;
                    lifecycle_state <= LC_PLAYBACK;
                end

                LC_PLAYBACK: begin
                    if (parser_ended)
                        lifecycle_state <= LC_ENDED_IDLE;
                end

                LC_REJECTED_IDLE: begin end
                LC_ENDED_IDLE: begin end
                LC_FATAL: begin end
                default: lifecycle_state <= LC_WAIT_LOAD;
            endcase
        end
    end

    assign pcm_a_read_request = 1'b0;
    assign pcm_a_read_address = '0;
    assign pcm_b_read_request = 1'b0;
    assign pcm_b_read_address = '0;

    assign playback_active = lifecycle_state == LC_PLAYBACK;
    assign profile_fatal = lifecycle_state == LC_FATAL;
    assign audio_l = playback_active ? sound_audio_l : 16'sd0;
    assign audio_r = playback_active ? sound_audio_r : 16'sd0;
    assign audio_sample_valid =
        playback_active ? sound_audio_sample_valid : 1'b0;
    assign profile_status = {
        prepared_file,
        parser_owned,
        adapter_outstanding,
        sound_core_ready,
        sound_unexpected_pcm_request,
        sound_unexpected_pcm_activity,
        profile_fatal,
        playback_active,
        lifecycle_state[4:0],
        scan_classification[2:0]
    };
    assign debug_page_data = {
        lifecycle_state[3:0],
        read_owner,
        profile_reject_code,
        parser_loop_event,
        parser_ended
    };

    wire unused_profile_signals = ^{
        osd_audio_lpf_mode, osd_audio_gain_boost, osd_audio_psg_level,
        title_valid, title_text_byte, scan_busy, scan_loop_samples,
        scan_end_pc, scan_total_samples, scan_total_writes,
        scan_port0_writes, scan_port1_writes, scan_b_only_writes,
        scan_unknown_writes, scan_command_count, scan_unsupported_opcodes,
        scan_ssg_writes, scan_adpcma_key_on_voices,
        scan_adpcma_key_off_voices, scan_adpcmb_start_count,
        scan_adpcmb_reset_count, scan_trace_hash,
        scan_first256_trace_hash, scan_debug_state, scan_variant_b,
        scan_dual_chip, scan_first_bad_pc, scan_first_bad_port,
        scan_first_bad_address, scan_first_bad_data, scan_first_bad_sample,
        scan_first_bad_semantic, scan_first_bad_target,
        scan_descriptor_a_count, scan_descriptor_b_count, scan_map_hit,
        scan_map_file_addr, owner_transition_count, ddr_accept_count,
        ddr_response_count, parser_active, parser_current_pc,
        parser_timeline_sample, parser_command_count, parser_write_count,
        parser_forwarded_fm_count, parser_forwarded_ssg_count,
        parser_suppressed_a_count, parser_suppressed_b_count,
        parser_data_block_count, parser_loop_count, parser_trace_hash,
        parser_first256_trace_hash, parser_trace_valid,
        parser_trace_command_pc, parser_trace_sample, parser_trace_port,
        parser_trace_address, parser_trace_data, parser_trace_semantic,
        parser_trace_forwarded, parser_trace_next_pc,
        parser_trace_sound_accept_cycle, sound_write_busy,
        sound_accepted_write_count, sound_fm_l, sound_fm_r, sound_psg_a,
        sound_psg_b, sound_psg_c, sound_psg_snd, sound_adpcma_l,
        sound_adpcma_r, sound_adpcmb_l, sound_adpcmb_r,
        sound_adpcma_request, sound_adpcmb_request, sound_adpcma_addr,
        sound_adpcma_bank, sound_adpcmb_addr, sound_cen,
        sound_cen_accumulator, shell_sample_timing, timeline_accumulator,
        timeline_tick
    };
endmodule
