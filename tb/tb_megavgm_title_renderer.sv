`timescale 1ns/1ps

module tb_megavgm_title_renderer;

	logic [9:0] h_count = 0;
	logic [8:0] v_count = 0;
	logic drawing_active = 1'b1;
	logic title_valid = 1'b1;
	logic [5:0] directory_length = 7;
	logic [5:0] basename_length = 23;
	logic [6:0] title_read_addr;
	logic [7:0] title_read_data;
	logic text_pixel;
	logic panel_pixel;
	logic [23:0] panel_rgb;
	byte unsigned title_bytes [0:79];
	integer checks = 0;
	integer failures = 0;
	integer x;
	integer y;
	integer ch;
	integer panel_pixel_count;
	integer blue_outline_pixel_count;
	integer heading_pixel_count;
	integer text_outside_panel_count;

	always_comb title_read_data = title_bytes[title_read_addr];

	megavgm_title_renderer dut (
		.h_count(h_count),
		.v_count(v_count),
		.drawing_active(drawing_active),
		.title_valid(title_valid),
		.directory_length(directory_length),
		.basename_length(basename_length),
		.title_read_addr(title_read_addr),
		.title_read_data(title_read_data),
		.text_pixel(text_pixel),
		.panel_pixel(panel_pixel),
		.panel_rgb(panel_rgb)
	);

	task automatic check_result(input logic condition, input string message);
		begin
			checks = checks + 1;
			if(!condition) begin
				failures = failures + 1;
				$display("FAIL: %s (x=%0d y=%0d)", message, h_count, v_count);
			end
		end
	endtask

	task automatic set_pixel(input integer px, input integer py);
		begin
			h_count = px;
			v_count = py;
			#1;
		end
	endtask

	task automatic load_example_names;
		integer i;
		begin
			for(i = 0; i < 80; i = i + 1)
				title_bytes[i] = 0;
			title_bytes[0] = "O";
			title_bytes[1] = "u";
			title_bytes[2] = "t";
			title_bytes[3] = " ";
			title_bytes[4] = "R";
			title_bytes[5] = "u";
			title_bytes[6] = "n";

			title_bytes[32 + 0]  = "0";
			title_bytes[32 + 1]  = "1";
			title_bytes[32 + 2]  = "_";
			title_bytes[32 + 3]  = "M";
			title_bytes[32 + 4]  = "a";
			title_bytes[32 + 5]  = "g";
			title_bytes[32 + 6]  = "i";
			title_bytes[32 + 7]  = "c";
			title_bytes[32 + 8]  = "a";
			title_bytes[32 + 9]  = "l";
			title_bytes[32 + 10] = " ";
			title_bytes[32 + 11] = "S";
			title_bytes[32 + 12] = "o";
			title_bytes[32 + 13] = "u";
			title_bytes[32 + 14] = "n";
			title_bytes[32 + 15] = "d";
			title_bytes[32 + 16] = " ";
			title_bytes[32 + 17] = "S";
			title_bytes[32 + 18] = "h";
			title_bytes[32 + 19] = "o";
			title_bytes[32 + 20] = "w";
			title_bytes[32 + 21] = "e";
			title_bytes[32 + 22] = "r";
		end
	endtask

	initial begin
		load_example_names();

		// The historical 320x240 player surface is horizontally centered in the
		// Template's 529x240 active picture. It has no outline or fixed heading.
		set_pixel(104, 0);
		check_result(panel_pixel === 1'b1, "panel top-left");
		check_result(panel_rgb === 24'h000818, "panel navy RGB");
		set_pixel(423, 239);
		check_result(panel_pixel === 1'b1, "panel bottom-right");
		check_result(panel_rgb === 24'h000818, "panel bottom-right RGB");
		set_pixel(200, 30);
		check_result(panel_pixel === 1'b1, "panel interior is filled");
		check_result(panel_rgb === 24'h000818, "filled interior navy RGB");
		set_pixel(103, 0);
		check_result(panel_pixel === 1'b0, "left outside panel unchanged");
		check_result(panel_rgb === 24'h000000, "left outside panel black");
		set_pixel(424, 239);
		check_result(panel_pixel === 1'b0, "right outside panel unchanged");
		set_pixel(423, 240);
		check_result(panel_pixel === 1'b0, "below panel unchanged");
		set_pixel(120, 12);
		check_result(text_pixel === 1'b0, "fixed player heading removed");

		// Directory and basename use the public title-memory read port.
		set_pixel(121, 24);
		check_result(text_pixel === 1'b1, "Out Run directory rendered");
		check_result(title_read_addr == 0, "directory address starts at zero");
		set_pixel(121, 34);
		check_result(text_pixel === 1'b1, "basename rendered");
		check_result(title_read_addr == 32, "basename address starts at 32");

		// Invalid metadata hides both dynamic lines while retaining the panel.
		title_valid = 0;
		set_pixel(121, 24);
		check_result(text_pixel === 1'b0, "invalid directory blank");
		set_pixel(121, 34);
		check_result(text_pixel === 1'b0, "invalid basename blank");
		check_result(panel_pixel === 1'b1, "invalid metadata retains panel");
		title_valid = 1;

		// Maximum lengths fit with 16-pixel left/right panel padding.
		directory_length = 32;
		basename_length = 48;
		for(x = 0; x < 32; x = x + 1)
			title_bytes[x] = "W";
		for(x = 0; x < 48; x = x + 1)
			title_bytes[32 + x] = "W";
		set_pixel(306, 24);
		check_result(text_pixel === 1'b1, "32nd directory character begins at x306");
		set_pixel(312, 24);
		check_result(text_pixel === 1'b0, "directory stops after 32 characters");
		set_pixel(402, 34);
		check_result(text_pixel === 1'b1, "48th basename character begins at x402");
		set_pixel(408, 34);
		check_result(text_pixel === 1'b0, "basename stops before right padding");

		// One blank column follows every 5x7 glyph.
		set_pixel(125, 24);
		check_result(text_pixel === 1'b0, "sixth cell column blank");

		// Drawing-active is a hard clip.
		drawing_active = 0;
		set_pixel(121, 24);
		check_result(text_pixel === 1'b0, "drawing inactive clips text");
		set_pixel(104, 8);
		check_result(panel_pixel === 1'b0, "drawing inactive clips panel");
		check_result(panel_rgb === 24'h000000, "drawing inactive clears panel RGB");
		drawing_active = 1;

		// Check the full centered 320x240 player surface and the remaining
		// Template active width. The surface is a solid fill, never the removed
		// 0x2040c0 outline, and text exists only on its two metadata rows.
		panel_pixel_count = 0;
		blue_outline_pixel_count = 0;
		heading_pixel_count = 0;
		text_outside_panel_count = 0;
		for(y = 0; y < 240; y = y + 1) begin
			for(x = 0; x < 529; x = x + 1) begin
				set_pixel(x, y);
				check_result((text_pixel === 1'b0) || (text_pixel === 1'b1),
				             "native renderer X/Z-free");
				check_result((panel_pixel === 1'b0) || (panel_pixel === 1'b1),
				             "native panel X/Z-free");
				check_result(panel_pixel ===
				             (((x >= 104) && (x <= 423) &&
				               (y <= 239)) ? 1'b1 : 1'b0),
				             "filled panel predicate matches exact geometry");
				check_result(panel_rgb ===
				             (panel_pixel ? 24'h000818 : 24'h000000),
				             "panel RGB is navy inside and black outside");
				if(panel_pixel)
					panel_pixel_count = panel_pixel_count + 1;
				if(panel_rgb == 24'h2040c0)
					blue_outline_pixel_count = blue_outline_pixel_count + 1;
				if((y >= 12) && (y < 19) && text_pixel)
					heading_pixel_count = heading_pixel_count + 1;
				if(text_pixel &&
				   (!panel_pixel ||
				    !(((y >= 24) && (y < 31)) ||
				      ((y >= 34) && (y < 41)))))
					text_outside_panel_count = text_outside_panel_count + 1;
			end
		end
		check_result(panel_pixel_count == (320 * 240), "filled player surface area");
		check_result(blue_outline_pixel_count == 0, "blue outline pixel count");
		check_result(heading_pixel_count == 0, "fixed heading pixel count");
		check_result(text_outside_panel_count == 0,
		             "metadata text remains inside panel rows");
		for(ch = 8'h20; ch <= 8'h7e; ch = ch + 1) begin
			title_bytes[0] = ch;
			directory_length = 1;
			for(y = 24; y < 31; y = y + 1) begin
				for(x = 120; x < 125; x = x + 1) begin
					set_pixel(x, y);
					check_result((text_pixel === 1'b0) || (text_pixel === 1'b1),
					             "printable ASCII glyph X/Z-free");
				end
			end
		end

		if(failures == 0) begin
			$display("PASS: title renderer geometry/font, %0d checks", checks);
			$finish;
		end
		$fatal(1, "FAIL: %0d of %0d checks failed", failures, checks);
	end

endmodule
