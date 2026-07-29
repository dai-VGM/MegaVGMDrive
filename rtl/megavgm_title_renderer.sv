// SPDX-License-Identifier: GPL-2.0-or-later
//
// Two-line native prepared-name panel renderer.
//
// Coordinates are native active-picture coordinates. Each printable ASCII
// character occupies a 6x7 cell containing one 5x7 glyph plus one blank
// horizontal pixel.

module megavgm_title_renderer (
	input  logic [9:0] h_count,
	input  logic [8:0] v_count,
	input  logic       drawing_active,

	input  logic       title_valid,
	input  logic [5:0] directory_length,
	input  logic [5:0] basename_length,
	output logic [6:0] title_read_addr,
	input  logic [7:0] title_read_data,

	output logic       text_pixel,
	output logic       panel_pixel,
	output logic [23:0] panel_rgb
);

	// Center the historical 320x240 player surface in the Template's
	// 529x240 active picture. The 288-pixel basename has 16-pixel margins.
	localparam logic [9:0] PANEL_LEFT = 10'd104;
	localparam logic [9:0] PANEL_RIGHT = 10'd423;
	localparam logic [8:0] PANEL_BOTTOM = 9'd239;
	localparam logic [9:0] TEXT_X = 10'd120;
	localparam logic [8:0] DIRECTORY_Y = 9'd24;
	localparam logic [8:0] BASENAME_Y = 9'd34;

	logic [7:0] character;
	logic [2:0] glyph_x;
	logic [2:0] glyph_y;
	logic       cell_visible;
	logic       glyph_pixel;
	logic [9:0] relative_x;
	logic [6:0] character_index;
	logic [9:0] character_cell_x;

	megavgm_font5x7 font (
		.character(character),
		.glyph_x(glyph_x),
		.glyph_y(glyph_y),
		.pixel(glyph_pixel)
	);

	always @* begin
		character = " ";
		glyph_x = 0;
		glyph_y = 0;
		title_read_addr = 0;
		cell_visible = 1'b0;
		relative_x = 0;
		character_index = 0;
		character_cell_x = 0;
		panel_pixel =
			drawing_active &&
			(h_count >= PANEL_LEFT) && (h_count <= PANEL_RIGHT) &&
			(v_count <= PANEL_BOTTOM);
		panel_rgb = panel_pixel ? 24'h000818 : 24'h000000;

		if(panel_pixel && (h_count >= TEXT_X)) begin
			relative_x = h_count - TEXT_X;
			/* verilator lint_off WIDTHTRUNC */
			character_index = relative_x / 10'd6;
			character_cell_x = character_index * 10'd6;
			glyph_x = relative_x - character_cell_x;
			/* verilator lint_on WIDTHTRUNC */

			if((v_count >= DIRECTORY_Y) && (v_count < DIRECTORY_Y + 9'd7) &&
			   title_valid && (character_index < {1'b0, directory_length})) begin
				/* verilator lint_off WIDTHTRUNC */
				glyph_y = v_count - DIRECTORY_Y;
				/* verilator lint_on WIDTHTRUNC */
				title_read_addr = character_index;
				character = title_read_data;
				cell_visible = 1'b1;
			end
			else if((v_count >= BASENAME_Y) && (v_count < BASENAME_Y + 9'd7) &&
			        title_valid && (character_index < {1'b0, basename_length})) begin
				/* verilator lint_off WIDTHTRUNC */
				glyph_y = v_count - BASENAME_Y;
				/* verilator lint_on WIDTHTRUNC */
				title_read_addr = 7'd32 + character_index;
				character = title_read_data;
				cell_visible = 1'b1;
			end
		end

		text_pixel = cell_visible && (glyph_x < 5) && glyph_pixel;
	end

endmodule
