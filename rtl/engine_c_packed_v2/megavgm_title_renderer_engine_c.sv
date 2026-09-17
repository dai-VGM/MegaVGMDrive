// SPDX-License-Identifier: GPL-2.0-or-later
// Engine C visual-only title panel. History bit 0 is newest; the renderer
// presents oldest at the left and newest at the right.
module megavgm_title_renderer (
    input  logic [9:0] h_count,
    input  logic [8:0] v_count,
    input  logic       drawing_active,
    input  logic       title_valid,
    input  logic [5:0] directory_length,
    input  logic [5:0] basename_length,
    output logic [6:0] title_read_addr,
    input  logic [7:0] title_read_data,
    input  logic [23:0] sid_activity_history,
    input  logic        sid_model_8580,
    input  logic        sid_timing_ntsc,
    output logic       text_pixel,
    output logic       panel_pixel,
    output logic [23:0] panel_rgb
);
    localparam logic [9:0] PANEL_LEFT = 10'd104;
    localparam logic [9:0] PANEL_RIGHT = 10'd423;
    localparam logic [8:0] PANEL_BOTTOM = 9'd239;
    localparam logic [9:0] TEXT_X = 10'd120;
    localparam logic [8:0] DIRECTORY_Y = 9'd24;
    localparam logic [8:0] BASENAME_Y = 9'd34;
    localparam logic [8:0] INFO_Y = 9'd54;
    localparam logic [8:0] LANE0_Y = 9'd70;
    localparam logic [8:0] LANE1_Y = 9'd82;
    localparam logic [8:0] LANE2_Y = 9'd94;
    localparam logic [8:0] LANE3_Y = 9'd106;
    localparam logic [9:0] HISTORY_X = 10'd192;
    localparam logic [23:0] PANEL_COLOR = 24'h000818;
    localparam logic [23:0] ACTIVITY_OFF_COLOR = 24'h102838;
    localparam logic [23:0] ACTIVITY_ON_COLOR = 24'h40c5d8;

    logic [7:0] character;
    logic [2:0] glyph_x, glyph_y;
    logic cell_visible, glyph_pixel;
    logic [9:0] relative_x, character_cell_x;
    logic [6:0] character_index;
    logic [2:0] lane;
    logic [8:0] lane_y;
    logic lane_valid, history_pixel, history_on;
    logic [2:0] history_slot;

    function automatic logic [7:0] info_character(input logic [4:0] index);
        begin
            info_character = " ";
            case (index)
                0: info_character="S"; 1: info_character="I"; 2: info_character="D";
                4: info_character="6"; 5: info_character=sid_model_8580 ? "8" : "5";
                6: info_character=sid_model_8580 ? "5" : "8"; 7: info_character=sid_model_8580 ? "8" : "1";
                10: info_character=sid_timing_ntsc ? "N" : "P";
                11: info_character=sid_timing_ntsc ? "T" : "A";
                12: info_character=sid_timing_ntsc ? "S" : "L";
                13: info_character=sid_timing_ntsc ? "C" : " ";
                default: info_character=" ";
            endcase
        end
    endfunction

    function automatic logic [7:0] lane_character(input logic [2:0] row, input logic [3:0] index);
        begin
            lane_character = " ";
            if (row < 3) begin
                case (index)
                    0: lane_character="V"; 1: lane_character="O"; 2: lane_character="I";
                    3: lane_character="C"; 4: lane_character="E";
                    6: lane_character = "1" + row;
                    default: lane_character=" ";
                endcase
            end else begin
                case (index)
                    0: lane_character="D"; 1: lane_character="4";
                    2: lane_character="1"; 3: lane_character="8";
                    default: lane_character=" ";
                endcase
            end
        end
    endfunction

    megavgm_font5x7 font(.character(character),.glyph_x(glyph_x),.glyph_y(glyph_y),.pixel(glyph_pixel));

    always @* begin
        character=" "; glyph_x=0; glyph_y=0; title_read_addr=0; cell_visible=0;
        relative_x=0; character_index=0; character_cell_x=0;
        lane=0; lane_y=0; lane_valid=0; history_pixel=0; history_on=0; history_slot=0;
        panel_pixel=drawing_active && h_count>=PANEL_LEFT && h_count<=PANEL_RIGHT && v_count<=PANEL_BOTTOM;

        if(v_count>=LANE0_Y && v_count<LANE0_Y+7) begin lane=0;lane_y=LANE0_Y;lane_valid=1;end
        else if(v_count>=LANE1_Y && v_count<LANE1_Y+7) begin lane=1;lane_y=LANE1_Y;lane_valid=1;end
        else if(v_count>=LANE2_Y && v_count<LANE2_Y+7) begin lane=2;lane_y=LANE2_Y;lane_valid=1;end
        else if(v_count>=LANE3_Y && v_count<LANE3_Y+7) begin lane=3;lane_y=LANE3_Y;lane_valid=1;end

        if(panel_pixel && lane_valid && h_count>=HISTORY_X && h_count<HISTORY_X+48) begin
            history_slot=(h_count-HISTORY_X)/8;
            history_pixel=((h_count-HISTORY_X)%8)<6 && v_count>=lane_y+1 && v_count<=lane_y+5;
            history_on=history_pixel && sid_activity_history[(lane*6)+(5-history_slot)];
        end
        panel_rgb=!panel_pixel ? 24'h000000 : history_on ? ACTIVITY_ON_COLOR :
                  history_pixel ? ACTIVITY_OFF_COLOR : PANEL_COLOR;

        if(panel_pixel && h_count>=TEXT_X) begin
            relative_x=h_count-TEXT_X;
            character_index=relative_x/6;
            character_cell_x=character_index*6;
            glyph_x=relative_x-character_cell_x;
            if(v_count>=DIRECTORY_Y && v_count<DIRECTORY_Y+7 && title_valid && character_index<directory_length) begin
                glyph_y=v_count-DIRECTORY_Y; title_read_addr=character_index; character=title_read_data; cell_visible=1;
            end else if(v_count>=BASENAME_Y && v_count<BASENAME_Y+7 && title_valid && character_index<basename_length) begin
                glyph_y=v_count-BASENAME_Y; title_read_addr=7'd32+character_index; character=title_read_data; cell_visible=1;
            end else if(v_count>=INFO_Y && v_count<INFO_Y+7 && character_index<14) begin
                glyph_y=v_count-INFO_Y; character=info_character(character_index[4:0]); cell_visible=1;
            end else if(lane_valid && character_index<8) begin
                glyph_y=v_count-lane_y; character=lane_character(lane,character_index[3:0]); cell_visible=1;
            end
        end
        text_pixel=cell_visible && glyph_x<5 && glyph_pixel;
    end
endmodule
