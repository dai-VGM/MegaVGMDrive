// Minimal VGM player for bytes loaded into vgm_file_loader BRAM.
//
// First pass scope:
//   - uncompressed VGM only
//   - validate "Vgm "
//   - data start from header offset 0x34; zero means 0x40
//   - YM2612 0x52/0x53, PSG 0x50, waits, GG stereo skip, 0x66 end
//   - 0x67 data blocks are skipped, not decoded

module vgm_loaded_player #(
    parameter int ADDR_WIDTH = 18
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

    output logic [ADDR_WIDTH-1:0] rd_addr,
    input  logic [7:0]            rd_data,

    input  logic                  ym_cmd_ready,
    input  logic                  psg_cmd_ready,
    output logic                  ym_cmd_valid,
    output logic                  ym_cmd_port,
    output logic [7:0]            ym_cmd_reg,
    output logic [7:0]            ym_cmd_data,
    output logic                  psg_cmd_valid,
    output logic [7:0]            psg_cmd_data,

    output logic                  busy,
    output logic                  done,
    output logic                  header_valid,
    output logic                  player_error,
    output logic [7:0]            unsupported_opcode,
    output logic [ADDR_WIDTH-1:0] unsupported_pc,
    output logic [7:0]            player_error_code,
    output logic [ADDR_WIDTH-1:0] data_start_debug,
    output logic [ADDR_WIDTH-1:0] current_pc_debug,
    output logic [ADDR_WIDTH-1:0] loop_pc_debug,
    output logic                  loop_valid_debug,
    output logic                  loop_taken_debug,
    output logic                  end_command_seen,
    output logic                  restarted_from_data_start,
    output logic [31:0]           wait_ticks_consumed_debug,
    output logic [9:0]            pc_debug,
    output logic [7:0]            last_cmd_debug
);

    typedef enum logic [5:0] {
        ST_IDLE,
        ST_READ_WAIT,
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
        ST_YM_WAIT_READY,
        ST_YM_PULSE,
        ST_PSG_WAIT_READY,
        ST_PSG_PULSE,
        ST_WAIT_SAMPLES,
        ST_DONE,
        ST_ERROR
    } state_t;

    state_t state;
    state_t read_return_state;

    logic [ADDR_WIDTH-1:0] pc;
    logic [7:0] cmd;
    logic [7:0] arg1;
    logic [31:0] block_size;
    logic [31:0] data_offset;
    logic [31:0] loop_offset;
    logic [ADDR_WIDTH-1:0] loop_pc;
    logic loop_valid;
    logic [15:0] wait_remaining;
    logic vgm_wait_tick_d;
    logic start_d;

    wire start_edge = start && !start_d;
    wire vgm_wait_tick_edge = vgm_wait_tick && !vgm_wait_tick_d;
    wire file_ok = load_done && !load_error && !overflow_error && (file_size > 17'd64);
    wire pc_in_range = ({1'b0, pc} < file_size);
    wire [31:0] pc_32 = {{(32-ADDR_WIDTH){1'b0}}, pc};
    wire [31:0] block_skip_end_32 = pc_32 + 32'd7 + {rd_data, block_size[23:0]};
    wire block_skip_in_range =
        (block_skip_end_32 <= file_size) && (block_skip_end_32[31:ADDR_WIDTH] == '0);
    wire [31:0] header_data_offset = {rd_data, data_offset[23:0]};
    wire [31:0] selected_data_start =
        (header_data_offset == 32'd0) ? 32'h0000_0040 : (32'h0000_0034 + header_data_offset);
    wire selected_data_start_in_range =
        (selected_data_start < file_size) && (selected_data_start[31:ADDR_WIDTH] == '0);
    wire [31:0] header_loop_offset = {rd_data, loop_offset[23:0]};
    wire [31:0] selected_loop_pc = 32'h0000_001c + header_loop_offset;
    wire selected_loop_valid =
        (header_loop_offset != 32'd0) && (selected_loop_pc < file_size) &&
        (selected_loop_pc[31:ADDR_WIDTH] == '0);

    generate
        if (ADDR_WIDTH >= 10) begin : wide_pc_debug
            assign pc_debug = pc[9:0];
        end else begin : narrow_pc_debug
            assign pc_debug = {{(10-ADDR_WIDTH){1'b0}}, pc};
        end
    endgenerate

    task automatic request_byte(input logic [ADDR_WIDTH-1:0] addr, input state_t return_state);
        begin
            rd_addr <= addr;
            read_return_state <= return_state;
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
            busy <= 1'b0;
            done <= 1'b0;
            header_valid <= 1'b0;
            player_error <= 1'b1;
            player_error_code <= error_code;
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

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            read_return_state <= ST_IDLE;
            pc <= '0;
            cmd <= 8'd0;
            arg1 <= 8'd0;
            data_offset <= 32'd0;
            loop_offset <= 32'd0;
            loop_pc <= '0;
            loop_valid <= 1'b0;
            block_size <= 32'd0;
            wait_remaining <= 16'd0;
            vgm_wait_tick_d <= 1'b0;
            start_d <= 1'b0;
            rd_addr <= '0;
            ym_cmd_valid <= 1'b0;
            ym_cmd_port <= 1'b0;
            ym_cmd_reg <= 8'd0;
            ym_cmd_data <= 8'd0;
            psg_cmd_valid <= 1'b0;
            psg_cmd_data <= 8'd0;
            busy <= 1'b0;
            done <= 1'b0;
            header_valid <= 1'b0;
            player_error <= 1'b0;
            unsupported_opcode <= 8'd0;
            unsupported_pc <= '0;
            player_error_code <= ERR_NONE;
            data_start_debug <= '0;
            current_pc_debug <= '0;
            loop_pc_debug <= '0;
            loop_valid_debug <= 1'b0;
            loop_taken_debug <= 1'b0;
            end_command_seen <= 1'b0;
            restarted_from_data_start <= 1'b0;
            wait_ticks_consumed_debug <= 32'd0;
            last_cmd_debug <= 8'd0;
        end else begin
            vgm_wait_tick_d <= vgm_wait_tick;
            start_d <= start;
            ym_cmd_valid <= 1'b0;
            psg_cmd_valid <= 1'b0;

            if (load_error || overflow_error) begin
                busy <= 1'b0;
                done <= 1'b0;
                header_valid <= 1'b0;
                player_error <= 1'b1;
                player_error_code <= ERR_LOAD;
                state <= ST_IDLE;
            end else begin
                case (state)
                    ST_IDLE: begin
                        busy <= 1'b0;
                        done <= 1'b0;
                        if ((load_done_pulse || start_edge) && file_ok) begin
                            busy <= 1'b1;
                            header_valid <= 1'b0;
                            player_error <= 1'b0;
                            unsupported_opcode <= 8'd0;
                            unsupported_pc <= '0;
                            player_error_code <= ERR_NONE;
                            data_offset <= 32'd0;
                            loop_offset <= 32'd0;
                            loop_pc <= '0;
                            loop_valid <= 1'b0;
                            loop_pc_debug <= '0;
                            loop_valid_debug <= 1'b0;
                            loop_taken_debug <= 1'b0;
                            end_command_seen <= 1'b0;
                            restarted_from_data_start <= 1'b0;
                            wait_ticks_consumed_debug <= 32'd0;
                            block_size <= 32'd0;
                            request_byte('0, ST_CHECK_MAGIC0);
                        end
                    end

                    ST_READ_WAIT: begin
                        state <= read_return_state;
                    end

                    ST_CHECK_MAGIC0: begin
                        if (rd_data == 8'h56) begin
                            request_byte({{(ADDR_WIDTH-1){1'b0}}, 1'b1}, ST_CHECK_MAGIC1);
                        end else begin
                            enter_error(ERR_BAD_MAGIC);
                        end
                    end

                    ST_CHECK_MAGIC1: begin
                        if (rd_data == 8'h67) begin
                            request_byte({{(ADDR_WIDTH-2){1'b0}}, 2'd2}, ST_CHECK_MAGIC2);
                        end else begin
                            enter_error(ERR_BAD_MAGIC);
                        end
                    end

                    ST_CHECK_MAGIC2: begin
                        if (rd_data == 8'h6d) begin
                            request_byte({{(ADDR_WIDTH-2){1'b0}}, 2'd3}, ST_CHECK_MAGIC3);
                        end else begin
                            enter_error(ERR_BAD_MAGIC);
                        end
                    end

                    ST_CHECK_MAGIC3: begin
                        if (rd_data == 8'h20) begin
                            request_byte({{(ADDR_WIDTH-5){1'b0}}, 5'h1c}, ST_READ_LOOP0);
                        end else begin
                            enter_error(ERR_BAD_MAGIC);
                        end
                    end

                    ST_READ_LOOP0: begin
                        loop_offset[7:0] <= rd_data;
                        request_byte({{(ADDR_WIDTH-5){1'b0}}, 5'h1d}, ST_READ_LOOP1);
                    end

                    ST_READ_LOOP1: begin
                        loop_offset[15:8] <= rd_data;
                        request_byte({{(ADDR_WIDTH-5){1'b0}}, 5'h1e}, ST_READ_LOOP2);
                    end

                    ST_READ_LOOP2: begin
                        loop_offset[23:16] <= rd_data;
                        request_byte({{(ADDR_WIDTH-5){1'b0}}, 5'h1f}, ST_READ_LOOP3);
                    end

                    ST_READ_LOOP3: begin
                        loop_offset[31:24] <= rd_data;
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
                        data_offset[7:0] <= rd_data;
                        request_byte({{(ADDR_WIDTH-6){1'b0}}, 6'h35}, ST_READ_OFF1);
                    end

                    ST_READ_OFF1: begin
                        data_offset[15:8] <= rd_data;
                        request_byte({{(ADDR_WIDTH-6){1'b0}}, 6'h36}, ST_READ_OFF2);
                    end

                    ST_READ_OFF2: begin
                        data_offset[23:16] <= rd_data;
                        request_byte({{(ADDR_WIDTH-6){1'b0}}, 6'h37}, ST_READ_OFF3);
                    end

                    ST_READ_OFF3: begin
                        data_offset[31:24] <= rd_data;
                        if (!selected_data_start_in_range) begin
                            enter_error(ERR_BAD_DATA_START);
                        end else begin
                            pc <= selected_data_start[ADDR_WIDTH-1:0];
                            data_start_debug <= selected_data_start[ADDR_WIDTH-1:0];
                            current_pc_debug <= selected_data_start[ADDR_WIDTH-1:0];
                            restarted_from_data_start <= 1'b1;
                            header_valid <= 1'b1;
                            request_byte(selected_data_start[ADDR_WIDTH-1:0], ST_FETCH_CMD);
                        end
                    end

                    ST_FETCH_CMD: begin
                        cmd <= rd_data;
                        last_cmd_debug <= rd_data;
                        current_pc_debug <= pc;
                        state <= ST_DECODE;
                    end

                    ST_DECODE: begin
                        if (!pc_in_range) begin
                            enter_error(ERR_PC_RANGE);
                        end else begin
                            case (cmd)
                                8'h52, 8'h53, 8'h50, 8'h4F, 8'h61: begin
                                    request_byte(pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1}, ST_ARG1);
                                end

                                8'h67: begin
                                    request_byte(pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1}, ST_BLOCK_MARKER);
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
                                        state <= ST_DONE;
                                    end
                                end

                                default: begin
                                    if (cmd[7:4] == 4'h7) begin
                                        wait_remaining <= {12'd0, cmd[3:0]} + 16'd1;
                                        pc <= pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                                        current_pc_debug <= pc + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                                        state <= ST_WAIT_SAMPLES;
                                    end else begin
                                        enter_unsupported_error();
                                    end
                                end
                            endcase
                        end
                    end

                    ST_ARG1: begin
                        arg1 <= rd_data;
                        if ((cmd == 8'h52) || (cmd == 8'h53) || (cmd == 8'h61)) begin
                            request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2}, ST_ARG2);
                        end else if (cmd == 8'h50) begin
                            psg_cmd_data <= rd_data;
                            state <= ST_PSG_WAIT_READY;
                        end else begin
                            pc <= pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2};
                            current_pc_debug <= pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2};
                            request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2}, ST_FETCH_CMD);
                        end
                    end

                    ST_ARG2: begin
                        if ((cmd == 8'h52) || (cmd == 8'h53)) begin
                            ym_cmd_port <= (cmd == 8'h53);
                            ym_cmd_reg <= arg1;
                            ym_cmd_data <= rd_data;
                            state <= ST_YM_WAIT_READY;
                        end else begin
                            wait_remaining <= {rd_data, arg1};
                            pc <= pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3};
                            current_pc_debug <= pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3};
                            state <= ST_WAIT_SAMPLES;
                        end
                    end

                    ST_BLOCK_MARKER: begin
                        if (rd_data == 8'h66) begin
                            request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd2}, ST_BLOCK_TYPE);
                        end else begin
                            enter_error(ERR_BAD_DATA_BLOCK);
                        end
                    end

                    ST_BLOCK_TYPE: begin
                        request_byte(pc + {{(ADDR_WIDTH-2){1'b0}}, 2'd3}, ST_BLOCK_SIZE0);
                    end

                    ST_BLOCK_SIZE0: begin
                        block_size[7:0] <= rd_data;
                        request_byte(pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd4}, ST_BLOCK_SIZE1);
                    end

                    ST_BLOCK_SIZE1: begin
                        block_size[15:8] <= rd_data;
                        request_byte(pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd5}, ST_BLOCK_SIZE2);
                    end

                    ST_BLOCK_SIZE2: begin
                        block_size[23:16] <= rd_data;
                        request_byte(pc + {{(ADDR_WIDTH-3){1'b0}}, 3'd6}, ST_BLOCK_SIZE3);
                    end

                    ST_BLOCK_SIZE3: begin
                        block_size[31:24] <= rd_data;
                        if (!block_skip_in_range) begin
                            enter_error(ERR_DATA_BLOCK_RANGE);
                        end else begin
                            pc <= block_skip_end_32[ADDR_WIDTH-1:0];
                            current_pc_debug <= block_skip_end_32[ADDR_WIDTH-1:0];
                            request_byte(block_skip_end_32[ADDR_WIDTH-1:0], ST_FETCH_CMD);
                        end
                    end

                    ST_YM_WAIT_READY: begin
                        if (ym_cmd_ready) begin
                            ym_cmd_valid <= 1'b1;
                            state <= ST_YM_PULSE;
                        end
                    end

                    ST_YM_PULSE: begin
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
