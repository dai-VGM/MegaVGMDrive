`timescale 1ns/1ps

// Lab-only passive first-runtime-reject recorder. Context is delayed by one
// clock so that the stable reject/code level captures the production signals
// from the cycle that entered reject. No output feeds functional logic.
module ym2610b_metal_slug_reject_serial_observer #(
    parameter int CLK_HZ = 20_000_000,
    parameter int BAUD = 115_200,
    parameter int FILE_ADDR_WIDTH = 23
) (
    input  logic                       clk,
    input  logic                       reset,
    input  logic                       capture,
    input  logic [7:0]                 reject_code,
    input  logic [3:0]                 classification,
    input  logic [31:0]                sample_count,
    input  logic [31:0]                vgm_pc,
    input  logic [31:0]                loop_count,
    input  logic                       ym_port,
    input  logic [7:0]                 ym_register,
    input  logic [7:0]                 ym_value,
    input  logic [3:0]                 bus_state,
    input  logic [7:0]                 bus_dout,
    input  logic                       busy_timeout,
    input  logic [15:0]                bus_watchdog,
    input  logic [23:0]                adpcma_logical,
    input  logic [23:0]                adpcmb_logical,
    input  logic                       a_current_hit,
    input  logic                       a_next_hit,
    input  logic                       b_current_hit,
    input  logic                       b_next_hit,
    input  logic                       request_active,
    input  logic                       request_pending,
    input  logic                       request_space_b,
    input  logic [23:0]                request_logical,
    input  logic                       response_valid,
    input  logic                       response_hit,
    input  logic                       response_space_b,
    input  logic [FILE_ADDR_WIDTH-1:0] response_file_addr,
    input  logic                       last_fill_valid,
    input  logic                       last_fill_space_b,
    input  logic [23:0]                last_fill_logical,
    output logic                       uart_tx,
    output logic                       frozen,
    output logic                       sent
);
    localparam int CLKS_PER_BIT = (CLK_HZ + (BAUD / 2)) / BAUD;

    localparam logic [119:0] PFX = "MS_REJECT code=";
    localparam logic [55:0] L_CLASS = " class=";
    localparam logic [95:0] L_SCAN = " scan_class=";
    localparam logic [79:0] L_SAMPLE = " sample=0x";
    localparam logic [47:0] L_PC = " pc=0x";
    localparam logic [63:0] L_LOOP = " loop=0x";
    localparam logic [47:0] L_PORT = " port=";
    localparam logic [39:0] L_REG = " reg=";
    localparam logic [55:0] L_VALUE = " value=";
    localparam logic [87:0] L_BUS_STATE = " bus_state=";
    localparam logic [47:0] L_DOUT = " dout=";
    localparam logic [47:0] L_BUSY = " busy=";
    localparam logic [79:0] L_WATCHDOG = " watchdog=";
    localparam logic [63:0] L_A_ADDR = " a_addr=";
    localparam logic [63:0] L_A_BANK = " a_bank=";
    localparam logic [87:0] L_A_MAP = " a_map_hit=";
    localparam logic [119:0] L_A_CURRENT = " a_current_hit=";
    localparam logic [95:0] L_A_NEXT = " a_next_hit=";
    localparam logic [63:0] L_B_ADDR = " b_addr=";
    localparam logic [87:0] L_B_MAP = " b_map_hit=";
    localparam logic [119:0] L_B_CURRENT = " b_current_hit=";
    localparam logic [95:0] L_B_NEXT = " b_next_hit=";
    localparam logic [87:0] L_REQ_SPACE = " req_space=";
    localparam logic [79:0] L_REQ_ADDR = " req_addr=";
    localparam logic [95:0] L_REQ_ACTIVE = " req_active=";
    localparam logic [103:0] L_REQ_PENDING = " req_pending=";
    localparam logic [87:0] L_RSP_VALID = " rsp_valid=";
    localparam logic [87:0] L_RSP_SPACE = " rsp_space=";
    localparam logic [71:0] L_RSP_HIT = " rsp_hit=";
    localparam logic [79:0] L_RSP_FILE = " rsp_file=";
    localparam logic [95:0] L_FILL_VALID = " fill_valid=";
    localparam logic [95:0] L_FILL_SPACE = " fill_space=";
    localparam logic [87:0] L_FILL_ADDR = " fill_addr=";

    logic [7:0] snap_code;
    logic [3:0] snap_classification;
    logic [31:0] snap_sample_count, snap_vgm_pc, snap_loop_count;
    logic snap_ym_port;
    logic [7:0] snap_ym_register, snap_ym_value, snap_bus_dout;
    logic [3:0] snap_bus_state;
    logic snap_busy_timeout;
    logic [15:0] snap_bus_watchdog;
    logic [23:0] snap_adpcma_logical, snap_adpcmb_logical;
    logic snap_a_current_hit, snap_a_next_hit;
    logic snap_b_current_hit, snap_b_next_hit;
    logic snap_request_active, snap_request_pending, snap_request_space_b;
    logic [23:0] snap_request_logical;
    logic snap_response_valid, snap_response_hit, snap_response_space_b;
    logic [FILE_ADDR_WIDTH-1:0] snap_response_file_addr;
    logic snap_last_fill_valid, snap_last_fill_space_b;
    logic [23:0] snap_last_fill_logical;

    logic [31:0] prev_sample_count, prev_vgm_pc, prev_loop_count;
    logic prev_ym_port;
    logic [7:0] prev_ym_register, prev_ym_value, prev_bus_dout;
    logic [3:0] prev_bus_state;
    logic prev_busy_timeout;
    logic [15:0] prev_bus_watchdog;
    logic [23:0] prev_adpcma_logical, prev_adpcmb_logical;
    logic prev_a_current_hit, prev_a_next_hit;
    logic prev_b_current_hit, prev_b_next_hit;
    logic prev_request_active, prev_request_pending, prev_request_space_b;
    logic [23:0] prev_request_logical;
    logic prev_response_valid, prev_response_hit, prev_response_space_b;
    logic [FILE_ADDR_WIDTH-1:0] prev_response_file_addr;
    logic prev_last_fill_valid, prev_last_fill_space_b;
    logic [23:0] prev_last_fill_logical;

    logic stream_active;
    logic [6:0] stream_field;
    logic [5:0] stream_index;
    logic [6:0] field_length;
    logic [7:0] field_char;
    logic uart_busy, tx_start;
    logic [7:0] tx_data;
    logic [31:0] baud_count;
    logic [3:0] uart_bit;
    logic [8:0] uart_shift;

    function automatic logic [7:0] hex_char(input logic [3:0] nibble);
        hex_char = nibble < 4'd10 ? 8'h30 + nibble : 8'h41 + nibble - 4'd10;
    endfunction

    function automatic logic [3:0] class_length(input logic [7:0] code);
        case (code)
            8'h09, 8'h0e: class_length = 4'd6;
            8'h0a: class_length = 4'd4;
            8'h0b, 8'h0f: class_length = 4'd5;
            8'h0c, 8'h0d: class_length = 4'd7;
            default: class_length = 4'd5;
        endcase
    endfunction

    function automatic logic [7:0] class_char(
        input logic [7:0] code, input logic [5:0] index
    );
        begin
            class_char = "?";
            case (code)
                8'h09: case(index) 0:class_char="P";1:class_char="A";2:class_char="R";3:class_char="S";4:class_char="E";5:class_char="R";default:class_char="?";endcase
                8'h0a: case(index) 0:class_char="B";1:class_char="U";2:class_char="S";3:class_char="Y";default:class_char="?";endcase
                8'h0b: case(index) 0:class_char="R";1:class_char="A";2:class_char="N";3:class_char="G";4:class_char="E";default:class_char="?";endcase
                8'h0c: case(index) 0:class_char="A";1:class_char="D";2:class_char="P";3:class_char="C";4:class_char="M";5:class_char="_";6:class_char="A";default:class_char="?";endcase
                8'h0d: case(index) 0:class_char="A";1:class_char="D";2:class_char="P";3:class_char="C";4:class_char="M";5:class_char="_";6:class_char="B";default:class_char="?";endcase
                8'h0e: case(index) 0:class_char="M";1:class_char="E";2:class_char="M";3:class_char="O";4:class_char="R";5:class_char="Y";default:class_char="?";endcase
                8'h0f: case(index) 0:class_char="S";1:class_char="H";2:class_char="E";3:class_char="L";4:class_char="L";default:class_char="?";endcase
                default: case(index) 0:class_char="O";1:class_char="T";2:class_char="H";3:class_char="E";4:class_char="R";default:class_char="?";endcase
            endcase
        end
    endfunction

    function automatic logic [7:0] bit_char(input logic value);
        bit_char = value ? "1" : "0";
    endfunction

    function automatic logic [7:0] space_char(input logic space_b);
        space_char = space_b ? "B" : "A";
    endfunction

    always_comb begin
        field_length = 7'd1;
        field_char = "?";
        case (stream_field)
            0: begin field_length=15; field_char=PFX[((15-stream_index)*8)-1 -: 8]; end
            1: begin field_length=2; field_char=hex_char(stream_index ? snap_code[3:0] : snap_code[7:4]); end
            2: begin field_length=7; field_char=L_CLASS[((7-stream_index)*8)-1 -: 8]; end
            3: begin field_length=class_length(snap_code); field_char=class_char(snap_code,stream_index); end
            4: begin field_length=12; field_char=L_SCAN[((12-stream_index)*8)-1 -: 8]; end
            5: begin field_length=1; field_char=hex_char(snap_classification); end
            6: begin field_length=10; field_char=L_SAMPLE[((10-stream_index)*8)-1 -: 8]; end
            7: begin field_length=8; field_char=hex_char(snap_sample_count >> ((7-stream_index)*4)); end
            8: begin field_length=6; field_char=L_PC[((6-stream_index)*8)-1 -: 8]; end
            9: begin field_length=8; field_char=hex_char(snap_vgm_pc >> ((7-stream_index)*4)); end
            10: begin field_length=8; field_char=L_LOOP[((8-stream_index)*8)-1 -: 8]; end
            11: begin field_length=8; field_char=hex_char(snap_loop_count >> ((7-stream_index)*4)); end
            12: begin field_length=6; field_char=L_PORT[((6-stream_index)*8)-1 -: 8]; end
            13: begin field_length=1; field_char=bit_char(snap_ym_port); end
            14: begin field_length=5; field_char=L_REG[((5-stream_index)*8)-1 -: 8]; end
            15: begin field_length=2; field_char=hex_char(stream_index ? snap_ym_register[3:0] : snap_ym_register[7:4]); end
            16: begin field_length=7; field_char=L_VALUE[((7-stream_index)*8)-1 -: 8]; end
            17: begin field_length=2; field_char=hex_char(stream_index ? snap_ym_value[3:0] : snap_ym_value[7:4]); end
            18: begin field_length=11; field_char=L_BUS_STATE[((11-stream_index)*8)-1 -: 8]; end
            19: begin field_length=1; field_char=hex_char(snap_bus_state); end
            20: begin field_length=6; field_char=L_DOUT[((6-stream_index)*8)-1 -: 8]; end
            21: begin field_length=2; field_char=hex_char(stream_index ? snap_bus_dout[3:0] : snap_bus_dout[7:4]); end
            22: begin field_length=6; field_char=L_BUSY[((6-stream_index)*8)-1 -: 8]; end
            23: begin field_length=1; field_char=bit_char(snap_busy_timeout); end
            24: begin field_length=10; field_char=L_WATCHDOG[((10-stream_index)*8)-1 -: 8]; end
            25: begin field_length=4; field_char=hex_char(snap_bus_watchdog >> ((3-stream_index)*4)); end
            26: begin field_length=8; field_char=L_A_ADDR[((8-stream_index)*8)-1 -: 8]; end
            27: begin field_length=6; field_char=hex_char(snap_adpcma_logical >> ((5-stream_index)*4)); end
            28: begin field_length=8; field_char=L_A_BANK[((8-stream_index)*8)-1 -: 8]; end
            29: begin field_length=1; field_char=hex_char(snap_adpcma_logical[23:20]); end
            30: begin field_length=11; field_char=L_A_MAP[((11-stream_index)*8)-1 -: 8]; end
            31: begin field_length=1; field_char=(!snap_response_valid || snap_response_space_b) ? "X" : bit_char(snap_response_hit); end
            32: begin field_length=15; field_char=L_A_CURRENT[((15-stream_index)*8)-1 -: 8]; end
            33: begin field_length=1; field_char=bit_char(snap_a_current_hit); end
            34: begin field_length=12; field_char=L_A_NEXT[((12-stream_index)*8)-1 -: 8]; end
            35: begin field_length=1; field_char=bit_char(snap_a_next_hit); end
            36: begin field_length=8; field_char=L_B_ADDR[((8-stream_index)*8)-1 -: 8]; end
            37: begin field_length=6; field_char=hex_char(snap_adpcmb_logical >> ((5-stream_index)*4)); end
            38: begin field_length=11; field_char=L_B_MAP[((11-stream_index)*8)-1 -: 8]; end
            39: begin field_length=1; field_char=(!snap_response_valid || !snap_response_space_b) ? "X" : bit_char(snap_response_hit); end
            40: begin field_length=15; field_char=L_B_CURRENT[((15-stream_index)*8)-1 -: 8]; end
            41: begin field_length=1; field_char=bit_char(snap_b_current_hit); end
            42: begin field_length=12; field_char=L_B_NEXT[((12-stream_index)*8)-1 -: 8]; end
            43: begin field_length=1; field_char=bit_char(snap_b_next_hit); end
            44: begin field_length=11; field_char=L_REQ_SPACE[((11-stream_index)*8)-1 -: 8]; end
            45: begin field_length=1; field_char=space_char(snap_request_space_b); end
            46: begin field_length=10; field_char=L_REQ_ADDR[((10-stream_index)*8)-1 -: 8]; end
            47: begin field_length=6; field_char=hex_char(snap_request_logical >> ((5-stream_index)*4)); end
            48: begin field_length=12; field_char=L_REQ_ACTIVE[((12-stream_index)*8)-1 -: 8]; end
            49: begin field_length=1; field_char=bit_char(snap_request_active); end
            50: begin field_length=13; field_char=L_REQ_PENDING[((13-stream_index)*8)-1 -: 8]; end
            51: begin field_length=1; field_char=bit_char(snap_request_pending); end
            52: begin field_length=11; field_char=L_RSP_VALID[((11-stream_index)*8)-1 -: 8]; end
            53: begin field_length=1; field_char=bit_char(snap_response_valid); end
            54: begin field_length=11; field_char=L_RSP_SPACE[((11-stream_index)*8)-1 -: 8]; end
            55: begin field_length=1; field_char=snap_response_valid ? space_char(snap_response_space_b) : "X"; end
            56: begin field_length=9; field_char=L_RSP_HIT[((9-stream_index)*8)-1 -: 8]; end
            57: begin field_length=1; field_char=snap_response_valid ? bit_char(snap_response_hit) : "X"; end
            58: begin field_length=10; field_char=L_RSP_FILE[((10-stream_index)*8)-1 -: 8]; end
            59: begin field_length=6; field_char=snap_response_valid ? hex_char(snap_response_file_addr >> ((5-stream_index)*4)) : "X"; end
            60: begin field_length=12; field_char=L_FILL_VALID[((12-stream_index)*8)-1 -: 8]; end
            61: begin field_length=1; field_char=bit_char(snap_last_fill_valid); end
            62: begin field_length=12; field_char=L_FILL_SPACE[((12-stream_index)*8)-1 -: 8]; end
            63: begin field_length=1; field_char=snap_last_fill_valid ? space_char(snap_last_fill_space_b) : "X"; end
            64: begin field_length=11; field_char=L_FILL_ADDR[((11-stream_index)*8)-1 -: 8]; end
            65: begin field_length=6; field_char=snap_last_fill_valid ? hex_char(snap_last_fill_logical >> ((5-stream_index)*4)) : "X"; end
            66: begin field_length=1; field_char=8'h0d; end
            67: begin field_length=1; field_char=8'h0a; end
            default: begin field_length=1; field_char="?"; end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            frozen <= 1'b0; sent <= 1'b0; stream_active <= 1'b0;
            stream_field <= 7'd0; stream_index <= 6'd0;
            tx_start <= 1'b0; tx_data <= 8'd0;
            snap_code <= 8'd0; snap_classification <= 4'd0;
            prev_sample_count <= 32'd0; prev_vgm_pc <= 32'd0; prev_loop_count <= 32'd0;
            prev_ym_port <= 1'b0; prev_ym_register <= 8'd0; prev_ym_value <= 8'd0;
            prev_bus_state <= 4'd0; prev_bus_dout <= 8'd0; prev_busy_timeout <= 1'b0;
            prev_bus_watchdog <= 16'd0; prev_adpcma_logical <= 24'd0; prev_adpcmb_logical <= 24'd0;
            prev_a_current_hit <= 1'b0; prev_a_next_hit <= 1'b0;
            prev_b_current_hit <= 1'b0; prev_b_next_hit <= 1'b0;
            prev_request_active <= 1'b0; prev_request_pending <= 1'b0;
            prev_request_space_b <= 1'b0; prev_request_logical <= 24'd0;
            prev_response_valid <= 1'b0; prev_response_hit <= 1'b0;
            prev_response_space_b <= 1'b0; prev_response_file_addr <= '0;
            prev_last_fill_valid <= 1'b0; prev_last_fill_space_b <= 1'b0;
            prev_last_fill_logical <= 24'd0;
        end else begin
            tx_start <= 1'b0;
            prev_sample_count <= sample_count; prev_vgm_pc <= vgm_pc; prev_loop_count <= loop_count;
            prev_ym_port <= ym_port; prev_ym_register <= ym_register; prev_ym_value <= ym_value;
            prev_bus_state <= bus_state; prev_bus_dout <= bus_dout; prev_busy_timeout <= busy_timeout;
            prev_bus_watchdog <= bus_watchdog; prev_adpcma_logical <= adpcma_logical;
            prev_adpcmb_logical <= adpcmb_logical;
            prev_a_current_hit <= a_current_hit; prev_a_next_hit <= a_next_hit;
            prev_b_current_hit <= b_current_hit; prev_b_next_hit <= b_next_hit;
            prev_request_active <= request_active; prev_request_pending <= request_pending;
            prev_request_space_b <= request_space_b; prev_request_logical <= request_logical;
            prev_response_valid <= response_valid; prev_response_hit <= response_hit;
            prev_response_space_b <= response_space_b; prev_response_file_addr <= response_file_addr;
            prev_last_fill_valid <= last_fill_valid; prev_last_fill_space_b <= last_fill_space_b;
            prev_last_fill_logical <= last_fill_logical;

            if (capture && !frozen) begin
                frozen <= 1'b1; snap_code <= reject_code;
                snap_classification <= classification;
                snap_sample_count <= prev_sample_count; snap_vgm_pc <= prev_vgm_pc;
                snap_loop_count <= prev_loop_count; snap_ym_port <= prev_ym_port;
                snap_ym_register <= prev_ym_register; snap_ym_value <= prev_ym_value;
                snap_bus_state <= prev_bus_state; snap_bus_dout <= prev_bus_dout;
                snap_busy_timeout <= prev_busy_timeout; snap_bus_watchdog <= prev_bus_watchdog;
                snap_adpcma_logical <= prev_adpcma_logical; snap_adpcmb_logical <= prev_adpcmb_logical;
                snap_a_current_hit <= prev_a_current_hit; snap_a_next_hit <= prev_a_next_hit;
                snap_b_current_hit <= prev_b_current_hit; snap_b_next_hit <= prev_b_next_hit;
                snap_request_active <= prev_request_active; snap_request_pending <= prev_request_pending;
                snap_request_space_b <= prev_request_space_b; snap_request_logical <= prev_request_logical;
                snap_response_valid <= prev_response_valid; snap_response_hit <= prev_response_hit;
                snap_response_space_b <= prev_response_space_b;
                snap_response_file_addr <= prev_response_file_addr;
                snap_last_fill_valid <= prev_last_fill_valid;
                snap_last_fill_space_b <= prev_last_fill_space_b;
                snap_last_fill_logical <= prev_last_fill_logical;
                stream_active <= 1'b1; stream_field <= 7'd0; stream_index <= 6'd0;
            end else if (stream_active && !uart_busy && !tx_start) begin
                tx_data <= field_char; tx_start <= 1'b1;
                if (stream_index + 6'd1 == field_length) begin
                    stream_index <= 6'd0;
                    if (stream_field == 7'd67) begin
                        stream_active <= 1'b0; sent <= 1'b1;
                    end else stream_field <= stream_field + 7'd1;
                end else stream_index <= stream_index + 6'd1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            uart_tx <= 1'b1; uart_busy <= 1'b0; baud_count <= 32'd0;
            uart_bit <= 4'd0; uart_shift <= 9'h1ff;
        end else if (tx_start && !uart_busy) begin
            uart_shift <= {1'b1, tx_data}; uart_tx <= 1'b0;
            uart_busy <= 1'b1; baud_count <= 32'd0; uart_bit <= 4'd0;
        end else if (uart_busy) begin
            if (baud_count == CLKS_PER_BIT - 1) begin
                baud_count <= 32'd0;
                if (uart_bit == 4'd9) begin uart_tx <= 1'b1; uart_busy <= 1'b0; end
                else begin
                    uart_bit <= uart_bit + 4'd1;
                    uart_shift <= {1'b1, uart_shift[8:1]};
                    uart_tx <= uart_shift[0];
                end
            end else baud_count <= baud_count + 32'd1;
        end
    end

    initial if (CLK_HZ <= 0 || BAUD <= 0 || CLKS_PER_BIT < 2)
        $error("invalid UART clock/baud parameters");
endmodule
