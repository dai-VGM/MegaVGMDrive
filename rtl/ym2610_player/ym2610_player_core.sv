`timescale 1ns/1ps

module ym2610_player_core #(
    parameter int SYS_CLK_HZ = 20_000_000,
    parameter int ADDR_WIDTH = 23,
    parameter int CACHE_ENTRIES = 64
) (
    input  logic                  clk,
    input  logic                  hard_reset,
    input  logic                  soft_reset,
    input  logic                  ioctl_download,
    input  logic                  load_done_pulse,
    input  logic [31:0]           file_size,
    input  logic [7:0]            load_generation,

    output logic                  mem_req,
    output logic [ADDR_WIDTH-1:0] mem_addr,
    input  logic                  mem_ready,
    input  logic                  mem_valid,
    input  logic [7:0]            mem_data,

    output logic signed [15:0]    audio_l,
    output logic signed [15:0]    audio_r,
    output logic                  audio_sample,
    output logic                  external_mute,
    output logic                  start_pulse,
    output logic [31:0]           start_count,
    output logic [31:0]           scanner_start_count,
    output logic [3:0]            load_state,
    output logic [4:0]            scanner_state,
    output logic [3:0]            parser_state,
    output logic [31:0]           parser_command_count,
    output logic                  fatal_active,
    output logic [7:0]            fatal_code,
    output logic [3:0]            classification,
    output logic                  raw_variant_b,
    output logic [7:0]            reject_code,
    output logic [31:0]           original_size,
    output logic [31:0]           parser_pc,
    output logic [7:0]            parser_opcode,
    output logic [31:0]           wait_remaining,
    output logic [31:0]           parser_samples,
    output logic [31:0]           parser_writes,
    output logic [31:0]           port0_writes,
    output logic [31:0]           port1_writes,
    output logic [31:0]           loop_count,
    output logic [3:0]            descriptor_a_count,
    output logic [3:0]            descriptor_b_count,
    output logic [31:0]           b_only_writes,
    output logic [31:0]           unknown_writes,
    output logic [31:0]           first_bad_pc,
    output logic                  first_bad_port,
    output logic [7:0]            first_bad_address,
    output logic [7:0]            first_bad_data,
    output logic [31:0]           unsupported_pc,
    output logic [7:0]            unsupported_opcode,
    output logic [31:0]           pcm_requests,
    output logic [31:0]           pcm_responses,
    output logic [31:0]           adpcma_requests,
    output logic [31:0]           adpcmb_requests,
    output logic [19:0]           pcm_last_address,
    output logic [19:0]           adpcma_last_address,
    output logic [19:0]           adpcmb_last_address,
    output logic [31:0]           adpcma_fetch_requests,
    output logic [31:0]           adpcma_fetch_responses,
    output logic [31:0]           adpcmb_fetch_requests,
    output logic [31:0]           adpcmb_fetch_responses,
    output logic [6:0]            pcm_occupancy,
    output logic                  parser_underflow,
    output logic                  adpcma_underflow,
    output logic                  adpcmb_underflow,
    output logic                  stale_response,
    output logic                  owner_mismatch,
    output logic                  busy_timeout,
    output logic                  write_while_busy,
    output logic                  memory_timeout,
    output logic                  memory_request_held,
    output logic                  memory_outstanding,
    output logic [1:0]            memory_held_owner,
    output logic [1:0]            memory_outstanding_owner,
    output logic [ADDR_WIDTH-1:0] last_memory_accept_addr,
    output logic [ADDR_WIDTH-1:0] last_memory_response_addr,
    output logic [7:0]            last_memory_accept_generation,
    output logic [7:0]            last_memory_response_generation,
    output logic                  pcm_request_held,
    output logic                  pcm_response_pending,
    output logic                  pcm_held_space_b,
    output logic [19:0]           pcm_held_logical_addr,
    output logic [31:0]           player_heartbeat,
    output logic [31:0]           ddr_heartbeat,
    output logic [15:0]           peak_l,
    output logic [15:0]           peak_r,
    output logic [7:0]            psg_a,
    output logic [7:0]            psg_b,
    output logic [7:0]            psg_c,
    output logic [9:0]            psg_snd,
    output logic signed [15:0]    adpcma_l,
    output logic signed [15:0]    adpcma_r,
    output logic signed [15:0]    adpcmb_l,
    output logic signed [15:0]    adpcmb_r
);
    localparam logic [3:0] LS_WAIT       = 4'd0;
    localparam logic [3:0] LS_LOAD       = 4'd1;
    localparam logic [3:0] LS_SCAN_RESET = 4'd2;
    localparam logic [3:0] LS_SCAN       = 4'd3;
    localparam logic [3:0] LS_CHIP_RESET = 4'd4;
    localparam logic [3:0] LS_READY      = 4'd5;
    localparam logic [3:0] LS_START      = 4'd6;
    localparam logic [3:0] LS_PLAY       = 4'd7;
    localparam logic [3:0] LS_DRAIN      = 4'd8;
    localparam logic [3:0] LS_REJECT     = 4'd9;
    localparam logic [3:0] LS_ENDED      = 4'd10;
    localparam logic [3:0] LS_INIT       = 4'd11;
    localparam logic [3:0] LS_SETTLE     = 4'd12;

    localparam logic [7:0] REJECT_RUNTIME_PARSER = 8'h09;
    localparam logic [7:0] REJECT_RUNTIME_BUSY   = 8'h0a;
    localparam logic [7:0] REJECT_RUNTIME_RANGE  = 8'h0b;
    localparam logic [7:0] REJECT_RUNTIME_A      = 8'h0c;
    localparam logic [7:0] REJECT_RUNTIME_B      = 8'h0d;
    localparam logic [7:0] REJECT_RUNTIME_MEMORY = 8'h0e;

    logic file_available;
    logic download_q;
    logic soft_reset_q;
    logic scanner_start;
    logic scanner_reset;
    logic scanner_req, scanner_ready, scanner_valid;
    logic [ADDR_WIDTH-1:0] scanner_addr;
    logic [7:0] scanner_data;
    logic scanner_busy, scanner_done, scanner_accepted;
    logic [31:0] scan_data_offset, scan_clock, scan_loop_target;
    logic [31:0] scan_loop_samples, scan_end_pc, scan_total_samples;
    logic [31:0] scan_total_writes, scan_p0, scan_p1, scan_command_count;
    logic scan_variant_b, scan_dual;
    logic [31:0] scan_first_bad_sample;
    logic [3:0] scan_first_bad_semantic;
    logic [2:0] scan_first_bad_target;

    logic parser_reset;
    logic parser_start;
    logic parser_req, parser_ready, parser_valid;
    logic [ADDR_WIDTH-1:0] parser_addr;
    logic [7:0] parser_data;
    logic parser_write_valid, parser_write_port, parser_write_ready;
    logic [7:0] parser_write_address, parser_write_data;
    logic parser_running, parser_finished, parser_error;
    logic [31:0] parser_accepted, parser_p0, parser_p1;
    logic [31:0] parser_unsupported_pc;
    logic [7:0] parser_unsupported_opcode;
    logic trace_valid;
    logic [31:0] trace_pc, trace_sample;

    logic cache_reset;
    logic cache_write_allow;
    logic map_space_b, map_hit;
    logic [19:0] map_logical_addr;
    logic [ADDR_WIDTH-1:0] map_file_addr;
    logic pcm_req, pcm_ready, pcm_valid;
    logic [ADDR_WIDTH-1:0] pcm_addr;
    logic [7:0] pcm_data;
    logic pcm_range_error, pcm_stale;

    logic arbiter_reset;
    logic [31:0] scanner_memory_requests, parser_memory_requests;
    logic [31:0] pcm_memory_requests;
    logic [31:0] arbiter_response_count;
    logic arbiter_stale, arbiter_owner_mismatch;
    logic arbiter_response_timeout;
    logic [7:0] scanner_reject_code;

    logic chip_reset;
    logic jt10_cen;
    logic [31:0] cen_accum;
    logic [32:0] cen_sum;
    logic sample_tick;
    logic [31:0] sample_accum;
    logic [32:0] sample_sum;
    logic [7:0] bus_dout;
    logic [1:0] bus_addr;
    logic [7:0] bus_din;
    logic bus_cs_n, bus_wr_n;
    logic bus_request_ready;
    logic bus_request_valid;
    logic bus_request_port;
    logic [7:0] bus_request_address;
    logic [7:0] bus_request_data;
    logic init_valid;
    logic [4:0] init_index;
    logic [16:0] init_word;
    logic [31:0] bus_accepted;
    logic irq_n;
    logic signed [15:0] jt_left, jt_right;
    logic jt_sample;
    logic signed [15:0] internal_left, internal_right;
    logic internal_sample;
    logic [19:0] adpcma_addr;
    logic [3:0] adpcma_bank;
    logic adpcma_roe_n;
    logic [7:0] adpcma_data;
    logic [23:0] adpcmb_addr;
    logic adpcmb_roe_n;
    logic [7:0] adpcmb_data;
    logic core_ready;
    logic [2:0] reset_cen_count;
    logic [5:0] adpcma_eos, adpcma_command;
    logic adpcmb_eos, adpcmb_active, adpcmb_command_update;
    logic sample_d;
    logic [2:0] drain_samples;
    logic [5:0] chip_reset_cens;
    logic [6:0] ready_zero_samples;

    wire download_start = ioctl_download && !download_q;
    wire soft_reset_rise = soft_reset && !soft_reset_q;
    wire cache_write_accept = parser_write_valid && parser_write_ready;

    assign scanner_reset = hard_reset || ioctl_download || load_state == LS_WAIT ||
                           load_state == LS_LOAD || load_state == LS_SCAN_RESET;
    assign parser_reset = hard_reset || ioctl_download ||
                          !(load_state == LS_START || load_state == LS_PLAY ||
                            load_state == LS_DRAIN || load_state == LS_ENDED);
    assign cache_reset = parser_reset;
    assign arbiter_reset = hard_reset || ioctl_download ||
                           load_state == LS_SCAN_RESET ||
                           load_state == LS_REJECT;
    assign chip_reset = hard_reset || ioctl_download ||
                        (load_state != LS_READY && load_state != LS_INIT &&
                         load_state != LS_SETTLE && load_state != LS_START &&
                         load_state != LS_PLAY && load_state != LS_DRAIN);
    assign external_mute = load_state != LS_PLAY;
    assign init_valid = load_state == LS_INIT && init_index < 5'd16;
    assign bus_request_valid = init_valid ||
                               (parser_write_valid && cache_write_allow);
    assign bus_request_port = init_valid ? init_word[16] : parser_write_port;
    assign bus_request_address = init_valid ? init_word[15:8] :
                                              parser_write_address;
    assign bus_request_data = init_valid ? init_word[7:0] : parser_write_data;
    assign parser_write_ready = bus_request_ready && cache_write_allow;
    assign stale_response = arbiter_stale || pcm_stale;
    assign owner_mismatch = arbiter_owner_mismatch;
    assign parser_underflow = arbiter_response_timeout && parser_running;
    assign memory_timeout = arbiter_response_timeout;
    assign raw_variant_b = scan_variant_b;
    assign unsupported_pc = scanner_reject_code == 8'h05 ?
                            first_bad_pc : parser_unsupported_pc;
    assign unsupported_opcode = scanner_reject_code == 8'h05 ?
                                first_bad_data : parser_unsupported_opcode;
    assign fatal_active = load_state == LS_REJECT;
    assign fatal_code = reject_code;
    assign player_heartbeat = arbiter_response_count;
    assign ddr_heartbeat = scanner_memory_requests + parser_memory_requests +
                           pcm_memory_requests + arbiter_response_count;

    assign cen_sum = {1'b0, cen_accum} + {1'b0, scan_clock};
    assign sample_sum = {1'b0, sample_accum} + 33'd44_100;

    always_comb begin
        case (init_index)
            5'd0:  init_word = {1'b0, 8'h28, 8'h01};
            5'd1:  init_word = {1'b0, 8'h28, 8'h02};
            5'd2:  init_word = {1'b0, 8'h28, 8'h05};
            5'd3:  init_word = {1'b0, 8'h28, 8'h06};
            5'd4:  init_word = {1'b0, 8'h22, 8'h00};
            5'd5:  init_word = {1'b0, 8'h27, 8'h00};
            5'd6:  init_word = {1'b0, 8'h08, 8'h00};
            5'd7:  init_word = {1'b0, 8'h09, 8'h00};
            5'd8:  init_word = {1'b0, 8'h0a, 8'h00};
            5'd9:  init_word = {1'b0, 8'h07, 8'h3f};
            5'd10: init_word = {1'b1, 8'h00, 8'hbf};
            5'd11: init_word = {1'b1, 8'h01, 8'h3f};
            5'd12: init_word = {1'b0, 8'h10, 8'h01};
            5'd13: init_word = {1'b0, 8'h1c, 8'h80};
            5'd14: init_word = {1'b0, 8'h10, 8'h00};
            default: init_word = {1'b0, 8'h1b, 8'h00};
        endcase
    end

    always_ff @(posedge clk) begin
        if (hard_reset || ioctl_download || scan_clock == 0 ||
            load_state == LS_SCAN_RESET || load_state == LS_SCAN) begin
            cen_accum <= 32'd0;
            jt10_cen <= 1'b0;
        end else if (cen_sum >= {1'b0, SYS_CLK_HZ[31:0]}) begin
            cen_accum <= cen_sum[31:0] - SYS_CLK_HZ[31:0];
            jt10_cen <= 1'b1;
        end else begin
            cen_accum <= cen_sum[31:0];
            jt10_cen <= 1'b0;
        end

        if (parser_reset) begin
            sample_accum <= 32'd0;
            sample_tick <= 1'b0;
        end else if (sample_sum >= {1'b0, SYS_CLK_HZ[31:0]}) begin
            sample_accum <= sample_sum[31:0] - SYS_CLK_HZ[31:0];
            sample_tick <= 1'b1;
        end else begin
            sample_accum <= sample_sum[31:0];
            sample_tick <= 1'b0;
        end
    end

    ym2610_player_scanner #(.ADDR_WIDTH(ADDR_WIDTH)) u_scanner (
        .clk(clk), .reset(scanner_reset), .start(scanner_start),
        .physical_size(file_size), .mem_req(scanner_req),
        .mem_addr(scanner_addr), .mem_ready(scanner_ready),
        .mem_valid(scanner_valid), .mem_data(scanner_data),
        .busy(scanner_busy), .done(scanner_done), .accepted(scanner_accepted),
        .classification(classification), .reject_code(scanner_reject_code),
        .original_size(original_size), .data_offset(scan_data_offset),
        .chip_clock(scan_clock), .loop_target(scan_loop_target),
        .loop_samples(scan_loop_samples), .end_pc(scan_end_pc),
        .total_samples(scan_total_samples), .total_writes(scan_total_writes),
        .port0_writes(scan_p0), .port1_writes(scan_p1),
        .b_only_writes(b_only_writes), .unknown_writes(unknown_writes),
        .command_count(scan_command_count), .debug_state(scanner_state),
        .variant_b(scan_variant_b),
        .dual_chip(scan_dual), .first_bad_pc(first_bad_pc),
        .first_bad_port(first_bad_port), .first_bad_address(first_bad_address),
        .first_bad_data(first_bad_data),
        .first_bad_sample(scan_first_bad_sample),
        .first_bad_semantic(scan_first_bad_semantic),
        .first_bad_target(scan_first_bad_target),
        .descriptor_a_count(descriptor_a_count),
        .descriptor_b_count(descriptor_b_count),
        .map_space_b(map_space_b), .map_logical_addr(map_logical_addr),
        .map_hit(map_hit), .map_file_addr(map_file_addr)
    );

    ym2610_player_parser #(.ADDR_WIDTH(ADDR_WIDTH)) u_parser (
        .clk(clk), .reset(parser_reset), .start(parser_start),
        .sample_tick(sample_tick), .start_pc(scan_data_offset),
        .loop_target(scan_loop_target), .mem_req(parser_req),
        .mem_addr(parser_addr), .mem_ready(parser_ready),
        .mem_valid(parser_valid), .mem_data(parser_data),
        .write_valid(parser_write_valid), .write_port(parser_write_port),
        .write_address(parser_write_address), .write_data(parser_write_data),
        .write_ready(parser_write_ready), .running(parser_running),
        .finished(parser_finished), .error(parser_error), .pc(parser_pc),
        .opcode(parser_opcode), .wait_remaining(wait_remaining),
        .sample_position(parser_samples), .accepted_writes(parser_accepted),
        .port0_writes(parser_p0), .port1_writes(parser_p1),
        .loop_count(loop_count), .command_count(parser_command_count),
        .debug_state(parser_state), .unsupported_pc(parser_unsupported_pc),
        .unsupported_opcode(parser_unsupported_opcode),
        .trace_valid(trace_valid),
        .trace_pc(trace_pc), .trace_sample(trace_sample)
    );

    assign parser_writes = parser_accepted;
    assign port0_writes = parser_p0;
    assign port1_writes = parser_p1;

    ym2610_player_bus u_bus (
        .clk(clk), .reset(chip_reset), .request_valid(bus_request_valid),
        .request_port(bus_request_port),
        .request_address(bus_request_address),
        .request_data(bus_request_data), .request_ready(bus_request_ready),
        .bus_addr(bus_addr), .bus_din(bus_din), .bus_cs_n(bus_cs_n),
        .bus_wr_n(bus_wr_n), .bus_dout(bus_dout),
        .busy_timeout(busy_timeout), .write_while_busy(write_while_busy),
        .accepted_count(bus_accepted)
    );

    ym2610_player_pcm_cache #(
        .ADDR_WIDTH(ADDR_WIDTH), .ENTRIES(CACHE_ENTRIES)
    ) u_cache (
        .clk(clk), .reset(cache_reset), .active(load_state == LS_PLAY),
        .write_valid(parser_write_valid), .write_accept(cache_write_accept),
        .write_port(parser_write_port), .write_address(parser_write_address),
        .write_data(parser_write_data), .write_allow(cache_write_allow),
        .adpcma_addr(adpcma_addr), .adpcma_bank(adpcma_bank),
        .adpcma_roe_n(adpcma_roe_n), .adpcma_data(adpcma_data),
        .adpcmb_addr(adpcmb_addr), .adpcmb_roe_n(adpcmb_roe_n),
        .adpcmb_data(adpcmb_data), .map_space_b(map_space_b),
        .map_logical_addr(map_logical_addr), .map_hit(map_hit),
        .map_file_addr(map_file_addr), .mem_req(pcm_req), .mem_addr(pcm_addr),
        .mem_ready(pcm_ready), .mem_valid(pcm_valid), .mem_data(pcm_data),
        .request_count(pcm_requests), .response_count(pcm_responses),
        .adpcma_request_count(adpcma_requests),
        .adpcmb_request_count(adpcmb_requests),
        .adpcma_fetch_requests(adpcma_fetch_requests),
        .adpcma_fetch_responses(adpcma_fetch_responses),
        .adpcmb_fetch_requests(adpcmb_fetch_requests),
        .adpcmb_fetch_responses(adpcmb_fetch_responses),
        .adpcma_underflow(adpcma_underflow),
        .adpcmb_underflow(adpcmb_underflow), .range_error(pcm_range_error),
        .stale_response(pcm_stale), .request_held(pcm_request_held),
        .response_pending(pcm_response_pending),
        .held_space_b(pcm_held_space_b),
        .held_logical_addr(pcm_held_logical_addr),
        .occupancy(pcm_occupancy),
        .last_logical_addr(pcm_last_address),
        .adpcma_last_address(adpcma_last_address),
        .adpcmb_last_address(adpcmb_last_address)
    );

    ym2610_player_memory_arbiter #(.ADDR_WIDTH(ADDR_WIDTH)) u_arbiter (
        .clk(clk), .reset(arbiter_reset), .generation(load_generation),
        .scan_req(scanner_req),
        .scan_addr(scanner_addr), .scan_ready(scanner_ready),
        .scan_valid(scanner_valid), .scan_data(scanner_data),
        .parser_req(parser_req), .parser_addr(parser_addr),
        .parser_ready(parser_ready), .parser_valid(parser_valid),
        .parser_data(parser_data), .pcm_req(pcm_req), .pcm_addr(pcm_addr),
        .pcm_ready(pcm_ready), .pcm_valid(pcm_valid), .pcm_data(pcm_data),
        .mem_req(mem_req), .mem_addr(mem_addr), .mem_ready(mem_ready),
        .mem_valid(mem_valid), .mem_data(mem_data),
        .scanner_requests(scanner_memory_requests),
        .parser_requests(parser_memory_requests),
        .pcm_requests(pcm_memory_requests),
        .response_count(arbiter_response_count),
        .stale_response(arbiter_stale),
        .owner_mismatch(arbiter_owner_mismatch),
        .response_timeout(arbiter_response_timeout),
        .request_held(memory_request_held),
        .outstanding(memory_outstanding),
        .held_owner(memory_held_owner),
        .outstanding_owner(memory_outstanding_owner),
        .last_accept_addr(last_memory_accept_addr),
        .last_response_addr(last_memory_response_addr),
        .last_accept_generation(last_memory_accept_generation),
        .last_response_generation(last_memory_response_generation)
    );

    ym2610_hw0_jt10_wrapper u_jt10 (
        .clk(clk), .rst(chip_reset), .cen(jt10_cen),
        .bus_addr(bus_addr), .bus_din(bus_din), .bus_cs_n(bus_cs_n),
        .bus_wr_n(bus_wr_n), .bus_dout(bus_dout), .irq_n(irq_n),
        .snd_left(jt_left), .snd_right(jt_right), .snd_sample(jt_sample),
        .psg_a(psg_a), .psg_b(psg_b), .psg_c(psg_c), .psg_snd(psg_snd),
        .adpcma_addr(adpcma_addr), .adpcma_bank(adpcma_bank),
        .adpcma_roe_n(adpcma_roe_n), .adpcma_data(adpcma_data),
        .adpcmb_addr(adpcmb_addr), .adpcmb_roe_n(adpcmb_roe_n),
        .adpcmb_data(adpcmb_data), .ready(core_ready),
        .reset_cen_count(reset_cen_count), .adpcma_eos(adpcma_eos),
        .adpcma_command(adpcma_command), .adpcma_left(adpcma_l),
        .adpcma_right(adpcma_r), .adpcmb_eos(adpcmb_eos),
        .adpcmb_active(adpcmb_active),
        .adpcmb_command_update(adpcmb_command_update),
        .adpcmb_left(adpcmb_l), .adpcmb_right(adpcmb_r),
        .internal_left(internal_left), .internal_right(internal_right),
        .internal_sample(internal_sample)
    );

    function automatic [15:0] abs16(input logic signed [15:0] value);
        abs16 = value[15] ? (~value + 16'd1) : value;
    endfunction

    always_ff @(posedge clk) begin
        download_q <= ioctl_download;
        soft_reset_q <= soft_reset;
        scanner_start <= 1'b0;
        parser_start <= 1'b0;
        start_pulse <= 1'b0;
        sample_d <= jt_sample;
        if (hard_reset) begin
            load_state <= LS_WAIT;
            file_available <= 1'b0;
            download_q <= ioctl_download;
            soft_reset_q <= soft_reset;
            start_count <= 32'd0;
            scanner_start_count <= 32'd0;
            drain_samples <= 3'd0;
            chip_reset_cens <= 6'd0;
            ready_zero_samples <= 7'd0;
            init_index <= 5'd0;
            reject_code <= 8'd0;
            peak_l <= 16'd0;
            peak_r <= 16'd0;
            sample_d <= 1'b0;
        end else begin
            if (download_start) begin
                load_state <= LS_LOAD;
                file_available <= 1'b0;
                scanner_start_count <= 32'd0;
                peak_l <= 16'd0;
                peak_r <= 16'd0;
                reject_code <= 8'd0;
            end else if (load_done_pulse) begin
                file_available <= 1'b1;
                load_state <= LS_SCAN_RESET;
                reject_code <= 8'd0;
            end else if (soft_reset_rise && file_available) begin
                load_state <= LS_SCAN_RESET;
                peak_l <= 16'd0;
                peak_r <= 16'd0;
                reject_code <= 8'd0;
            end else begin
                case (load_state)
                    LS_WAIT: begin end
                    LS_LOAD: begin end
                    LS_SCAN_RESET: load_state <= LS_SCAN;
                    LS_SCAN: begin
                        if (!scanner_busy && !scanner_done && !scanner_start) begin
                            scanner_start <= 1'b1;
                            scanner_start_count <= scanner_start_count + 32'd1;
                        end
                        if (scanner_done) begin
                            reject_code <= scanner_reject_code;
                            if (scanner_accepted) begin
                                chip_reset_cens <= 6'd0;
                                ready_zero_samples <= 7'd0;
                                load_state <= LS_CHIP_RESET;
                            end else
                                load_state <= LS_REJECT;
                        end else if (arbiter_response_timeout ||
                                     stale_response || owner_mismatch) begin
                            reject_code <= REJECT_RUNTIME_MEMORY;
                            load_state <= LS_REJECT;
                        end
                    end
                    LS_CHIP_RESET: begin
                        if (jt10_cen) begin
                            if (chip_reset_cens == 6'd15)
                                load_state <= LS_READY;
                            else
                                chip_reset_cens <= chip_reset_cens + 6'd1;
                        end
                    end
                    LS_READY: if (core_ready && jt_sample && !sample_d) begin
                        if (ready_zero_samples == 7'd63 && !bus_dout[7]) begin
                            init_index <= 5'd0;
                            load_state <= LS_INIT;
                        end
                        else
                            ready_zero_samples <= ready_zero_samples + 7'd1;
                    end
                    LS_INIT: if (init_valid && bus_request_ready) begin
                        if (init_index == 5'd15) begin
                            ready_zero_samples <= 7'd0;
                            load_state <= LS_SETTLE;
                        end else
                            init_index <= init_index + 5'd1;
                    end
                    LS_SETTLE: if (jt_sample && !sample_d) begin
                        if (ready_zero_samples == 7'd31)
                            load_state <= LS_START;
                        else
                            ready_zero_samples <= ready_zero_samples + 7'd1;
                    end
                    LS_START: begin
                        parser_start <= 1'b1;
                        start_pulse <= 1'b1;
                        start_count <= start_count + 32'd1;
                        load_state <= LS_PLAY;
                    end
                    LS_PLAY: begin
                        if (jt_sample && !sample_d) begin
                            if (abs16(jt_left) > peak_l) peak_l <= abs16(jt_left);
                            if (abs16(jt_right) > peak_r) peak_r <= abs16(jt_right);
                        end
                        if (parser_finished) begin
                            drain_samples <= 3'd0;
                            load_state <= LS_DRAIN;
                        end else if (parser_error || busy_timeout ||
                                     pcm_range_error || adpcma_underflow ||
                                     adpcmb_underflow || stale_response ||
                                     owner_mismatch || parser_underflow) begin
                            if (parser_error)
                                reject_code <= REJECT_RUNTIME_PARSER;
                            else if (busy_timeout)
                                reject_code <= REJECT_RUNTIME_BUSY;
                            else if (pcm_range_error)
                                reject_code <= REJECT_RUNTIME_RANGE;
                            else if (adpcma_underflow)
                                reject_code <= REJECT_RUNTIME_A;
                            else if (adpcmb_underflow)
                                reject_code <= REJECT_RUNTIME_B;
                            else
                                reject_code <= REJECT_RUNTIME_MEMORY;
                            load_state <= LS_REJECT;
                        end
                    end
                    LS_DRAIN: if (jt_sample && !sample_d) begin
                        if (drain_samples == 3'd3)
                            load_state <= LS_ENDED;
                        else drain_samples <= drain_samples + 3'd1;
                    end
                    LS_REJECT: begin end
                    LS_ENDED: begin end
                    default: load_state <= LS_WAIT;
                endcase
            end
        end
    end

    always_comb begin
        audio_l = external_mute ? 16'sd0 : jt_left;
        audio_r = external_mute ? 16'sd0 : jt_right;
        audio_sample = external_mute ? 1'b0 : jt_sample;
    end
endmodule
