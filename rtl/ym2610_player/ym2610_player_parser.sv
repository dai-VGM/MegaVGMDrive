`timescale 1ns/1ps

// Playback pass for the command set admitted by ym2610_player_scanner.  PC is
// advanced only by a consumed byte or accepted JT10 write.  The logical sample
// counter advances only while executing a VGM wait, which makes BUSY and DDR
// stalls visible as transport latency without shortening a wait by one tick.
module ym2610_player_parser #(
    parameter int ADDR_WIDTH = 23
) (
    input  logic                  clk,
    input  logic                  reset,
    input  logic                  start,
    input  logic                  sample_tick,
    input  logic [31:0]           start_pc,
    input  logic [31:0]           loop_target,

    output logic                  mem_req,
    output logic [ADDR_WIDTH-1:0] mem_addr,
    input  logic                  mem_ready,
    input  logic                  mem_valid,
    input  logic [7:0]            mem_data,

    output logic                  write_valid,
    output logic                  write_port,
    output logic [7:0]            write_address,
    output logic [7:0]            write_data,
    input  logic                  write_ready,

    output logic                  running,
    output logic                  finished,
    output logic                  error,
    output logic [31:0]           pc,
    output logic [7:0]            opcode,
    output logic [31:0]           wait_remaining,
    output logic [31:0]           sample_position,
    output logic [31:0]           accepted_writes,
    output logic [31:0]           port0_writes,
    output logic [31:0]           port1_writes,
    output logic [31:0]           loop_count,
    output logic [31:0]           command_count,
    output logic [3:0]            debug_state,
    output logic [31:0]           unsupported_pc,
    output logic [7:0]            unsupported_opcode,
    output logic                  trace_valid,
    output logic [31:0]           trace_pc,
    output logic [31:0]           trace_sample
);
    typedef enum logic [3:0] {
        ST_IDLE, ST_COMMAND, ST_WRITE_ADDR, ST_WRITE_DATA, ST_WRITE_ACCEPT,
        ST_WAIT_LO, ST_WAIT_HI, ST_WAIT, ST_BLOCK_MARK, ST_BLOCK_TYPE,
        ST_BLOCK_SIZE, ST_DONE, ST_ERROR
    } state_t;

    state_t state;
    assign debug_state = state;
    logic read_pending;
    logic [31:0] command_pc;
    logic [7:0] wait_low;
    logic [1:0] block_size_index;
    logic [31:0] block_size_build;
    logic [31:0] block_size;

    function automatic logic fetch_state(input state_t value);
        case (value)
            ST_COMMAND, ST_WRITE_ADDR, ST_WRITE_DATA, ST_WAIT_LO, ST_WAIT_HI,
            ST_BLOCK_MARK, ST_BLOCK_TYPE, ST_BLOCK_SIZE: fetch_state = 1'b1;
            default: fetch_state = 1'b0;
        endcase
    endfunction

    always_comb begin
        mem_req = running && fetch_state(state) && !read_pending;
        mem_addr = pc[ADDR_WIDTH-1:0];
        write_valid = running && state == ST_WRITE_ACCEPT;
    end

    always_ff @(posedge clk) begin
        trace_valid <= 1'b0;
        if (reset) begin
            state <= ST_IDLE;
            read_pending <= 1'b0;
            running <= 1'b0;
            finished <= 1'b0;
            error <= 1'b0;
            pc <= 32'd0;
            opcode <= 8'd0;
            wait_remaining <= 32'd0;
            sample_position <= 32'd0;
            accepted_writes <= 32'd0;
            port0_writes <= 32'd0;
            port1_writes <= 32'd0;
            loop_count <= 32'd0;
            command_count <= 32'd0;
            unsupported_pc <= 32'd0;
            unsupported_opcode <= 8'd0;
            write_port <= 1'b0;
            write_address <= 8'd0;
            write_data <= 8'd0;
            trace_pc <= 32'd0;
            trace_sample <= 32'd0;
        end else begin
            if (mem_req && mem_ready)
                read_pending <= 1'b1;
            if (mem_valid && read_pending)
                read_pending <= 1'b0;

            if (start) begin
                state <= ST_COMMAND;
                read_pending <= 1'b0;
                running <= 1'b1;
                finished <= 1'b0;
                error <= 1'b0;
                pc <= start_pc;
                opcode <= 8'd0;
                wait_remaining <= 32'd0;
                sample_position <= 32'd0;
                accepted_writes <= 32'd0;
                port0_writes <= 32'd0;
                port1_writes <= 32'd0;
                loop_count <= 32'd0;
                command_count <= 32'd0;
                unsupported_pc <= 32'd0;
                unsupported_opcode <= 8'd0;
            end else begin
                case (state)
                    ST_IDLE: begin end
                    ST_COMMAND: if (mem_valid && read_pending) begin
                        command_count <= command_count + 32'd1;
                        command_pc <= pc;
                        opcode <= mem_data;
                        pc <= pc + 32'd1;
                        case (mem_data)
                            8'h58, 8'h59: begin
                                write_port <= mem_data[0];
                                state <= ST_WRITE_ADDR;
                            end
                            8'h61: state <= ST_WAIT_LO;
                            8'h62: begin
                                wait_remaining <= 32'd735;
                                state <= ST_WAIT;
                            end
                            8'h63: begin
                                wait_remaining <= 32'd882;
                                state <= ST_WAIT;
                            end
                            8'h66: begin
                                if (loop_target != 0) begin
                                    pc <= loop_target;
                                    loop_count <= loop_count + 32'd1;
                                end else begin
                                    running <= 1'b0;
                                    finished <= 1'b1;
                                    state <= ST_DONE;
                                end
                            end
                            8'h67: state <= ST_BLOCK_MARK;
                            8'h70, 8'h71, 8'h72, 8'h73,
                            8'h74, 8'h75, 8'h76, 8'h77,
                            8'h78, 8'h79, 8'h7a, 8'h7b,
                            8'h7c, 8'h7d, 8'h7e, 8'h7f: begin
                                wait_remaining <= {28'd0, mem_data[3:0]} + 32'd1;
                                state <= ST_WAIT;
                            end
                            default: begin
                                running <= 1'b0;
                                error <= 1'b1;
                                unsupported_pc <= pc;
                                unsupported_opcode <= mem_data;
                                state <= ST_ERROR;
                            end
                        endcase
                    end
                    ST_WRITE_ADDR: if (mem_valid && read_pending) begin
                        write_address <= mem_data;
                        pc <= pc + 32'd1;
                        state <= ST_WRITE_DATA;
                    end
                    ST_WRITE_DATA: if (mem_valid && read_pending) begin
                        write_data <= mem_data;
                        pc <= pc + 32'd1;
                        state <= ST_WRITE_ACCEPT;
                    end
                    ST_WRITE_ACCEPT: if (write_ready) begin
                        accepted_writes <= accepted_writes + 32'd1;
                        if (write_port)
                            port1_writes <= port1_writes + 32'd1;
                        else
                            port0_writes <= port0_writes + 32'd1;
                        trace_valid <= 1'b1;
                        trace_pc <= command_pc;
                        trace_sample <= sample_position;
                        state <= ST_COMMAND;
                    end
                    ST_WAIT_LO: if (mem_valid && read_pending) begin
                        wait_low <= mem_data;
                        pc <= pc + 32'd1;
                        state <= ST_WAIT_HI;
                    end
                    ST_WAIT_HI: if (mem_valid && read_pending) begin
                        wait_remaining <= {16'd0, mem_data, wait_low};
                        pc <= pc + 32'd1;
                        if ({mem_data, wait_low} == 16'd0)
                            state <= ST_COMMAND;
                        else
                            state <= ST_WAIT;
                    end
                    ST_WAIT: if (sample_tick) begin
                        sample_position <= sample_position + 32'd1;
                        if (wait_remaining <= 32'd1) begin
                            wait_remaining <= 32'd0;
                            state <= ST_COMMAND;
                        end else
                            wait_remaining <= wait_remaining - 32'd1;
                    end
                    ST_BLOCK_MARK: if (mem_valid && read_pending) begin
                        pc <= pc + 32'd1;
                        if (mem_data == 8'h66)
                            state <= ST_BLOCK_TYPE;
                        else begin
                            running <= 1'b0;
                            error <= 1'b1;
                            unsupported_pc <= command_pc;
                            unsupported_opcode <= 8'h67;
                            state <= ST_ERROR;
                        end
                    end
                    ST_BLOCK_TYPE: if (mem_valid && read_pending) begin
                        pc <= pc + 32'd1;
                        block_size_index <= 2'd0;
                        block_size_build <= 32'd0;
                        if (mem_data == 8'h82 || mem_data == 8'h83)
                            state <= ST_BLOCK_SIZE;
                        else begin
                            running <= 1'b0;
                            error <= 1'b1;
                            unsupported_pc <= command_pc;
                            unsupported_opcode <= 8'h67;
                            state <= ST_ERROR;
                        end
                    end
                    ST_BLOCK_SIZE: if (mem_valid && read_pending) begin
                        pc <= pc + 32'd1;
                        case (block_size_index)
                            2'd0: block_size_build[7:0] <= mem_data;
                            2'd1: block_size_build[15:8] <= mem_data;
                            2'd2: block_size_build[23:16] <= mem_data;
                            2'd3: begin
                                block_size <= {1'b0, mem_data[6:0], block_size_build[23:0]};
                                pc <= pc + {1'b0, mem_data[6:0], block_size_build[23:0]} + 32'd1;
                                state <= ST_COMMAND;
                            end
                        endcase
                        if (block_size_index != 2'd3)
                            block_size_index <= block_size_index + 2'd1;
                    end
                    ST_DONE: begin end
                    ST_ERROR: begin end
                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule
