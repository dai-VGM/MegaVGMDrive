// SPDX-License-Identifier: GPL-2.0-or-later
// Defensive Stage C VGM parser. PCM commands are classified and traced but
// never forwarded to the sound device.
`timescale 1ns/1ps

module ym2610_golden_stage_c_parser #(
    parameter int ADDR_WIDTH = 23,
    parameter int BUSY_DEADLINE_SAMPLES = 64
) (
    input  logic                  clk,
    input  logic                  reset,
    input  logic                  abort,
    input  logic                  start,
    input  logic [31:0]           original_size,
    input  logic [31:0]           data_offset,
    input  logic [31:0]           loop_target,
    input  logic                  sample_tick,

    output logic                  mem_req,
    output logic [ADDR_WIDTH-1:0] mem_addr,
    input  logic                  mem_ready,
    input  logic                  mem_valid,
    input  logic [7:0]            mem_data,

    output logic                  sound_write_req,
    output logic                  sound_write_port,
    output logic [7:0]            sound_write_address,
    output logic [7:0]            sound_write_data,
    input  logic                  sound_write_accept,
    input  logic                  sound_fault,

    output logic                  active,
    output logic                  ended,
    output logic                  fatal,
    output logic [7:0]            fatal_code,
    output logic                  loop_event,
    output logic [31:0]           current_pc,
    output logic [31:0]           timeline_sample,
    output logic [31:0]           command_count,
    output logic [31:0]           write_count,
    output logic [31:0]           forwarded_fm_global_count,
    output logic [31:0]           forwarded_ssg_count,
    output logic [31:0]           suppressed_adpcma_count,
    output logic [31:0]           suppressed_adpcmb_count,
    output logic [31:0]           data_block_count,
    output logic [31:0]           loop_count,
    output logic [63:0]           trace_hash,
    output logic [63:0]           first256_trace_hash,

    output logic                  trace_valid,
    output logic [31:0]           trace_command_pc,
    output logic [31:0]           trace_sample,
    output logic                  trace_port,
    output logic [7:0]            trace_address,
    output logic [7:0]            trace_data,
    output logic [3:0]            trace_semantic,
    output logic                  trace_forwarded,
    output logic [31:0]           trace_next_pc,
    output logic [63:0]           trace_sound_accept_cycle
);
    localparam logic [7:0] FATAL_RANGE       = 8'h01;
    localparam logic [7:0] FATAL_OPCODE      = 8'h02;
    localparam logic [7:0] FATAL_BLOCK       = 8'h03;
    localparam logic [7:0] FATAL_REGISTER    = 8'h04;
    localparam logic [7:0] FATAL_LOOP        = 8'h05;
    localparam logic [7:0] FATAL_SOUND       = 8'h06;
    localparam logic [7:0] FATAL_BUSY_LIMIT  = 8'h07;

    localparam logic [3:0] SEM_SSG     = 4'd1;
    localparam logic [3:0] SEM_ADPCMA  = 4'd3;
    localparam logic [3:0] SEM_ADPCMB  = 4'd4;

    typedef enum logic [3:0] {
        P_IDLE,
        P_COMMAND,
        P_WRITE_ADDR,
        P_WRITE_DATA,
        P_SOUND_WAIT,
        P_WAIT_LO,
        P_WAIT_HI,
        P_WAIT_ACTIVE,
        P_BLOCK_MARK,
        P_BLOCK_TYPE,
        P_BLOCK_SIZE,
        P_SUPPRESS_TRACE,
        P_ENDED,
        P_FATAL
    } parser_state_t;

    parser_state_t state;
    logic read_pending;
    logic [31:0] pc;
    logic [31:0] command_pc;
    logic [7:0] opcode;
    logic pending_port;
    logic [7:0] pending_address;
    logic [7:0] pending_data;
    logic [3:0] pending_semantic;
    logic [31:0] pending_next_pc;
    logic [31:0] pending_sample;
    logic [7:0] wait_low;
    logic [31:0] wait_remaining;
    logic [7:0] block_type;
    logic [1:0] block_size_index;
    logic [31:0] block_size_build;
    logic [31:0] sound_stall_samples;
    logic [63:0] cycle_count;

    logic compat_accepted;
    logic compat_b_only;
    logic compat_unknown;
    logic [3:0] compat_semantic;
    logic [2:0] compat_target;

    wire [31:0] completed_block_size = {
        1'b0, mem_data[6:0], block_size_build[23:0]
    };
    wire [32:0] completed_block_end =
        {1'b0, command_pc} + 33'd7 + {1'b0, completed_block_size};

    ym2610_golden_stage_b_compat u_compat (
        .port(pending_port),
        .address(pending_address),
        .data(mem_data),
        .accepted(compat_accepted),
        .b_only(compat_b_only),
        .unknown(compat_unknown),
        .semantic(compat_semantic),
        .target(compat_target)
    );

    function automatic logic fetch_state(input parser_state_t value);
        case (value)
            P_COMMAND, P_WRITE_ADDR, P_WRITE_DATA, P_WAIT_LO, P_WAIT_HI,
            P_BLOCK_MARK, P_BLOCK_TYPE, P_BLOCK_SIZE:
                fetch_state = 1'b1;
            default: fetch_state = 1'b0;
        endcase
    endfunction

    function automatic [63:0] fnv_byte(
        input logic [63:0] hash,
        input logic [7:0] value
    );
        fnv_byte = (hash ^ value) * 64'h0000_0100_0000_01b3;
    endfunction

    function automatic [63:0] hash_write(
        input logic [63:0] hash,
        input logic [31:0] event_pc,
        input logic [31:0] event_sample,
        input logic [7:0] event_opcode,
        input logic event_port,
        input logic [7:0] event_address,
        input logic [7:0] event_data
    );
        logic [63:0] next;
        begin
            next = hash;
            next = fnv_byte(next, event_pc[7:0]);
            next = fnv_byte(next, event_pc[15:8]);
            next = fnv_byte(next, event_pc[23:16]);
            next = fnv_byte(next, event_pc[31:24]);
            next = fnv_byte(next, event_sample[7:0]);
            next = fnv_byte(next, event_sample[15:8]);
            next = fnv_byte(next, event_sample[23:16]);
            next = fnv_byte(next, event_sample[31:24]);
            next = fnv_byte(next, event_opcode);
            next = fnv_byte(next, {7'd0, event_port});
            next = fnv_byte(next, event_address);
            next = fnv_byte(next, event_data);
            hash_write = next;
        end
    endfunction

    task automatic publish_trace(
        input logic forwarded,
        input logic [63:0] accept_cycle
    );
        logic [63:0] next_hash;
        begin
            next_hash = hash_write(
                trace_hash, command_pc, pending_sample, opcode,
                pending_port, pending_address, pending_data
            );
            trace_valid <= 1'b1;
            trace_command_pc <= command_pc;
            trace_sample <= pending_sample;
            trace_port <= pending_port;
            trace_address <= pending_address;
            trace_data <= pending_data;
            trace_semantic <= pending_semantic;
            trace_forwarded <= forwarded;
            trace_next_pc <= pending_next_pc;
            trace_sound_accept_cycle <= accept_cycle;
            trace_hash <= next_hash;
            if (write_count < 32'd256)
                first256_trace_hash <= next_hash;
            write_count <= write_count + 32'd1;
        end
    endtask

    assign active = state != P_IDLE && state != P_ENDED && state != P_FATAL;
    assign ended = state == P_ENDED;
    assign fatal = state == P_FATAL;
    assign current_pc = pc;
    assign sound_write_req = state == P_SOUND_WAIT;
    assign sound_write_port = pending_port;
    assign sound_write_address = pending_address;
    assign sound_write_data = pending_data;

    always_comb begin
        mem_req = active && fetch_state(state) && !read_pending &&
                  pc < original_size;
        mem_addr = pc[ADDR_WIDTH-1:0];
    end

    always_ff @(posedge clk) begin
        trace_valid <= 1'b0;
        loop_event <= 1'b0;
        cycle_count <= cycle_count + 64'd1;

        if (reset || abort) begin
            state <= P_IDLE;
            read_pending <= 1'b0;
            pc <= 32'd0;
            command_pc <= 32'd0;
            opcode <= 8'd0;
            pending_port <= 1'b0;
            pending_address <= 8'd0;
            pending_data <= 8'd0;
            pending_semantic <= 4'd0;
            pending_next_pc <= 32'd0;
            pending_sample <= 32'd0;
            wait_low <= 8'd0;
            wait_remaining <= 32'd0;
            block_type <= 8'd0;
            block_size_index <= 2'd0;
            block_size_build <= 32'd0;
            sound_stall_samples <= 32'd0;
            cycle_count <= 64'd0;
            fatal_code <= 8'd0;
            timeline_sample <= 32'd0;
            command_count <= 32'd0;
            write_count <= 32'd0;
            forwarded_fm_global_count <= 32'd0;
            forwarded_ssg_count <= 32'd0;
            suppressed_adpcma_count <= 32'd0;
            suppressed_adpcmb_count <= 32'd0;
            data_block_count <= 32'd0;
            loop_count <= 32'd0;
            trace_hash <= 64'hcbf2_9ce4_8422_2325;
            first256_trace_hash <= 64'hcbf2_9ce4_8422_2325;
            trace_command_pc <= 32'd0;
            trace_sample <= 32'd0;
            trace_port <= 1'b0;
            trace_address <= 8'd0;
            trace_data <= 8'd0;
            trace_semantic <= 4'd0;
            trace_forwarded <= 1'b0;
            trace_next_pc <= 32'd0;
            trace_sound_accept_cycle <= 64'd0;
        end else if (start) begin
            read_pending <= 1'b0;
            timeline_sample <= 32'd0;
            command_count <= 32'd0;
            write_count <= 32'd0;
            forwarded_fm_global_count <= 32'd0;
            forwarded_ssg_count <= 32'd0;
            suppressed_adpcma_count <= 32'd0;
            suppressed_adpcmb_count <= 32'd0;
            data_block_count <= 32'd0;
            loop_count <= 32'd0;
            trace_hash <= 64'hcbf2_9ce4_8422_2325;
            first256_trace_hash <= 64'hcbf2_9ce4_8422_2325;
            sound_stall_samples <= 32'd0;
            fatal_code <= 8'd0;
            if (data_offset < 32'h40 || data_offset >= original_size ||
                (loop_target != 0 &&
                 (loop_target < data_offset || loop_target >= original_size))) begin
                pc <= 32'd0;
                fatal_code <= loop_target != 0 ? FATAL_LOOP : FATAL_RANGE;
                state <= P_FATAL;
            end else begin
                pc <= data_offset;
                state <= P_COMMAND;
            end
        end else begin
            if (mem_req && mem_ready)
                read_pending <= 1'b1;
            if (mem_valid && read_pending)
                read_pending <= 1'b0;

            if (sound_fault && active) begin
                fatal_code <= FATAL_SOUND;
                state <= P_FATAL;
            end else if (active && fetch_state(state) && !read_pending &&
                         pc >= original_size) begin
                fatal_code <= FATAL_RANGE;
                state <= P_FATAL;
            end else begin
                case (state)
                    P_IDLE: begin end

                    P_COMMAND: if (mem_valid && read_pending) begin
                        command_pc <= pc;
                        opcode <= mem_data;
                        command_count <= command_count + 32'd1;
                        pc <= pc + 32'd1;
                        case (mem_data)
                            8'h58, 8'h59: begin
                                pending_port <= mem_data[0];
                                state <= P_WRITE_ADDR;
                            end
                            8'h61: state <= P_WAIT_LO;
                            8'h62: begin
                                wait_remaining <= 32'd735;
                                state <= P_WAIT_ACTIVE;
                            end
                            8'h63: begin
                                wait_remaining <= 32'd882;
                                state <= P_WAIT_ACTIVE;
                            end
                            8'h66: begin
                                if (loop_target != 0) begin
                                    pc <= loop_target;
                                    loop_count <= loop_count + 32'd1;
                                    loop_event <= 1'b1;
                                end else begin
                                    state <= P_ENDED;
                                end
                            end
                            8'h67: state <= P_BLOCK_MARK;
                            8'h70, 8'h71, 8'h72, 8'h73,
                            8'h74, 8'h75, 8'h76, 8'h77,
                            8'h78, 8'h79, 8'h7a, 8'h7b,
                            8'h7c, 8'h7d, 8'h7e, 8'h7f: begin
                                wait_remaining <=
                                    {28'd0, mem_data[3:0]} + 32'd1;
                                state <= P_WAIT_ACTIVE;
                            end
                            default: begin
                                fatal_code <= FATAL_OPCODE;
                                state <= P_FATAL;
                            end
                        endcase
                    end

                    P_WRITE_ADDR: if (mem_valid && read_pending) begin
                        pending_address <= mem_data;
                        pc <= pc + 32'd1;
                        state <= P_WRITE_DATA;
                    end

                    P_WRITE_DATA: if (mem_valid && read_pending) begin
                        pending_data <= mem_data;
                        pending_semantic <= compat_semantic;
                        pending_sample <= timeline_sample;
                        pending_next_pc <= pc + 32'd1;
                        pc <= pc + 32'd1;
                        sound_stall_samples <= 32'd0;
                        if (!compat_accepted || compat_b_only || compat_unknown) begin
                            fatal_code <= FATAL_REGISTER;
                            state <= P_FATAL;
                        end else if (compat_semantic == SEM_ADPCMA) begin
                            suppressed_adpcma_count <=
                                suppressed_adpcma_count + 32'd1;
                            state <= P_SUPPRESS_TRACE;
                        end else if (compat_semantic == SEM_ADPCMB) begin
                            suppressed_adpcmb_count <=
                                suppressed_adpcmb_count + 32'd1;
                            state <= P_SUPPRESS_TRACE;
                        end else begin
                            state <= P_SOUND_WAIT;
                        end
                    end

                    P_SOUND_WAIT: begin
                        if (sound_write_accept) begin
                            if (pending_semantic == SEM_SSG)
                                forwarded_ssg_count <=
                                    forwarded_ssg_count + 32'd1;
                            else
                                forwarded_fm_global_count <=
                                    forwarded_fm_global_count + 32'd1;
                            publish_trace(1'b1, cycle_count);
                            sound_stall_samples <= 32'd0;
                            state <= P_COMMAND;
                        end else if (sample_tick) begin
                            if (sound_stall_samples >=
                                BUSY_DEADLINE_SAMPLES-1) begin
                                fatal_code <= FATAL_BUSY_LIMIT;
                                state <= P_FATAL;
                            end else begin
                                sound_stall_samples <=
                                    sound_stall_samples + 32'd1;
                            end
                        end
                    end

                    P_WAIT_LO: if (mem_valid && read_pending) begin
                        wait_low <= mem_data;
                        pc <= pc + 32'd1;
                        state <= P_WAIT_HI;
                    end

                    P_WAIT_HI: if (mem_valid && read_pending) begin
                        wait_remaining <= {16'd0, mem_data, wait_low};
                        pc <= pc + 32'd1;
                        if ({mem_data, wait_low} == 16'd0)
                            state <= P_COMMAND;
                        else
                            state <= P_WAIT_ACTIVE;
                    end

                    P_WAIT_ACTIVE: if (sample_tick) begin
                        timeline_sample <= timeline_sample + 32'd1;
                        if (wait_remaining == 32'd1) begin
                            wait_remaining <= 32'd0;
                            state <= P_COMMAND;
                        end else begin
                            wait_remaining <= wait_remaining - 32'd1;
                        end
                    end

                    P_BLOCK_MARK: if (mem_valid && read_pending) begin
                        pc <= pc + 32'd1;
                        if (mem_data != 8'h66) begin
                            fatal_code <= FATAL_BLOCK;
                            state <= P_FATAL;
                        end else begin
                            state <= P_BLOCK_TYPE;
                        end
                    end

                    P_BLOCK_TYPE: if (mem_valid && read_pending) begin
                        block_type <= mem_data;
                        block_size_index <= 2'd0;
                        block_size_build <= 32'd0;
                        pc <= pc + 32'd1;
                        state <= P_BLOCK_SIZE;
                    end

                    P_BLOCK_SIZE: if (mem_valid && read_pending) begin
                        pc <= pc + 32'd1;
                        case (block_size_index)
                            2'd0: block_size_build[7:0] <= mem_data;
                            2'd1: block_size_build[15:8] <= mem_data;
                            2'd2: block_size_build[23:16] <= mem_data;
                            2'd3: begin
                                if (mem_data[7] ||
                                    (block_type != 8'h82 &&
                                     block_type != 8'h83) ||
                                    completed_block_size <= 32'd8 ||
                                    completed_block_end[32] ||
                                    completed_block_end > {1'b0, original_size}) begin
                                    fatal_code <= FATAL_BLOCK;
                                    state <= P_FATAL;
                                end else begin
                                    pc <= completed_block_end[31:0];
                                    data_block_count <= data_block_count + 32'd1;
                                    state <= P_COMMAND;
                                end
                            end
                        endcase
                        if (block_size_index != 2'd3)
                            block_size_index <= block_size_index + 2'd1;
                    end

                    P_SUPPRESS_TRACE: begin
                        publish_trace(1'b0, 64'hffff_ffff_ffff_ffff);
                        state <= P_COMMAND;
                    end

                    P_ENDED: begin end
                    P_FATAL: begin end
                    default: begin
                        fatal_code <= FATAL_OPCODE;
                        state <= P_FATAL;
                    end
                endcase
            end
        end
    end

    wire unused_compat_target = ^compat_target;
endmodule
