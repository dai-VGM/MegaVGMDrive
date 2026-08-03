`timescale 1ns/1ps

// Compact 5x7 debug overlay.  Labels are deliberately short so both pages fit
// comfortably inside the 529x240 native picture (15 rows, below the 29-row
// contract).  Debug View=Off bypasses this module entirely.
module ym2610_player_debug_renderer (
    input  logic       enable,
    input  logic       pcm_page,
    input  logic [9:0] h_count,
    input  logic [8:0] v_count,
    input  logic       drawing_active,
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
    output logic       background,
    output logic       text_pixel
);
    logic [7:0] character;
    logic [2:0] glyph_x, glyph_y;
    logic glyph_pixel;
    logic [9:0] column;
    logic [8:0] row;
    logic [9:0] glyph_x_full;
    logic [8:0] glyph_y_full;
    logic [31:0] row_value;
    logic [7:0] label0, label1;
    logic row_valid;
    logic [3:0] nibble;
    logic [31:0] shifted_value;

    function automatic [7:0] hex_char(input logic [3:0] value);
        hex_char = value < 10 ?
                   (8'h30 + {4'd0, value}) :
                   (8'h41 + {4'd0, (value - 4'd10)});
    endfunction

    megavgm_font5x7 u_font (
        .character(character), .glyph_x(glyph_x), .glyph_y(glyph_y),
        .pixel(glyph_pixel)
    );

    always_comb begin
        background = enable && drawing_active;
        column = h_count / 10'd6;
        row = (v_count >= 9'd4) ? (v_count - 9'd4) / 9'd8 : 9'd31;
        glyph_x_full = h_count - column * 10'd6;
        glyph_y_full = (v_count >= 9'd4) ?
                       (v_count - 9'd4) - row * 9'd8 : 9'd0;
        glyph_x = glyph_x_full[2:0];
        glyph_y = glyph_y_full[2:0];
        character = " ";
        row_value = 32'd0;
        label0 = " ";
        label1 = " ";
        row_valid = 1'b1;
        shifted_value = 32'd0;

        if (!pcm_page) begin
            case (row)
                1: begin label0="L"; label1="S"; row_value={28'd0,load_state}; end
                2: begin label0="S"; label1="Z"; row_value=original_size; end
                3: begin label0="R"; label1="V"; row_value={31'd0,raw_variant_b}; end
                4: begin label0="C"; label1="L"; row_value={28'd0,classification}; end
                5: begin label0="R"; label1="J"; row_value={24'd0,reject_code}; end
                6: begin label0="B"; label1="P"; row_value=first_bad_pc; end
                7: begin label0="B"; label1="D"; row_value={15'd0,first_bad_port,first_bad_address,first_bad_data}; end
                8: begin label0="P"; label1="C"; row_value=parser_pc; end
                9: begin label0="O"; label1="P"; row_value={24'd0,parser_opcode}; end
                10:begin label0="W"; label1="T"; row_value=wait_remaining; end
                11:begin label0="P"; label1="0"; row_value=port0_writes; end
                12:begin label0="P"; label1="1"; row_value=port1_writes; end
                13:begin label0="S"; label1="T"; row_value=start_count; end
                14:begin label0="L"; label1="P"; row_value=loop_count; end
                15:begin label0="U"; label1="P"; row_value=unsupported_pc; end
                16:begin label0="U"; label1="O"; row_value={24'd0,unsupported_opcode}; end
                default: row_valid = 1'b0;
            endcase
        end else begin
            case (row)
                1: begin label0="D"; label1="A"; row_value={28'd0,descriptor_a_count}; end
                2: begin label0="D"; label1="B"; row_value={28'd0,descriptor_b_count}; end
                3: begin label0="A"; label1="Q"; row_value=adpcma_fetch_requests; end
                4: begin label0="A"; label1="S"; row_value=adpcma_fetch_responses; end
                5: begin label0="B"; label1="Q"; row_value=adpcmb_fetch_requests; end
                6: begin label0="B"; label1="S"; row_value=adpcmb_fetch_responses; end
                7: begin label0="A"; label1="R"; row_value=adpcma_requests; end
                8: begin label0="B"; label1="R"; row_value=adpcmb_requests; end
                9: begin label0="L"; label1="A"; row_value={12'd0,adpcma_last_address}; end
                10:begin label0="L"; label1="B"; row_value={12'd0,adpcmb_last_address}; end
                11:begin label0="O"; label1="C"; row_value={25'd0,pcm_occupancy}; end
                12:begin label0="U"; label1="A"; row_value={31'd0,adpcma_underflow}; end
                13:begin label0="U"; label1="B"; row_value={31'd0,adpcmb_underflow}; end
                14:begin label0="S"; label1="T"; row_value={31'd0,stale_response}; end
                15:begin label0="O"; label1="M"; row_value={31'd0,owner_mismatch}; end
                16:begin label0="P"; label1="L"; row_value={16'd0,peak_l}; end
                17:begin label0="P"; label1="R"; row_value={16'd0,peak_r}; end
                default: row_valid = 1'b0;
            endcase
        end

        if (row == 0) begin
            if (column == 0) character = "Y";
            else if (column == 1) character = "M";
            else if (column == 2) character = "2";
            else if (column == 3) character = "6";
            else if (column == 4) character = "1";
            else if (column == 5) character = "0";
            else if (column == 7) character = pcm_page ? "P" : "P";
            else if (column == 8) character = pcm_page ? "C" : "A";
            else if (column == 9) character = pcm_page ? "M" : "R";
        end else if (row_valid) begin
            if (column == 0) character = label0;
            else if (column == 1) character = label1;
            else if (column >= 3 && column <= 10) begin
                shifted_value = row_value >> ((10-column) * 4);
                nibble = shifted_value[3:0];
                character = hex_char(nibble);
            end
        end
        text_pixel = background && (glyph_x < 5) && (glyph_y < 7) && glyph_pixel;
    end
endmodule
