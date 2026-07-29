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
	logic frame_pixel;
	byte unsigned title_bytes [0:79];
	integer checks = 0;
	integer failures = 0;
	integer x;
	integer y;
	integer ch;
	integer frame_pixel_count;
	integer text_frame_collision_count;

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
		.frame_pixel(frame_pixel)
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

		// Static heading is present at exactly x=16, y=12.
		set_pixel(16, 12);
		check_result(text_pixel === 1'b1, "MegaVGMPlayer first M pixel");
		set_pixel(15, 12);
		check_result(text_pixel === 1'b0, "heading left boundary");
		set_pixel(16, 19);
		check_result(text_pixel === 1'b0, "heading seven-pixel height");
		set_pixel(94, 12);
		check_result(text_pixel === 1'b0, "heading right boundary");

		// Directory and basename use the public title-memory read port.
		set_pixel(17, 24);
		check_result(text_pixel === 1'b1, "Out Run directory rendered");
		check_result(title_read_addr == 0, "directory address starts at zero");
		set_pixel(17, 34);
		check_result(text_pixel === 1'b1, "basename rendered");
		check_result(title_read_addr == 32, "basename address starts at 32");

		// Invalid metadata hides both dynamic lines but not the heading.
		title_valid = 0;
		set_pixel(17, 24);
		check_result(text_pixel === 1'b0, "invalid directory blank");
		set_pixel(17, 34);
		check_result(text_pixel === 1'b0, "invalid basename blank");
		set_pixel(16, 12);
		check_result(text_pixel === 1'b1, "heading independent of metadata");
		title_valid = 1;

		// Maximum lengths fit inside 320 active pixels with no scrolling.
		directory_length = 32;
		basename_length = 48;
		for(x = 0; x < 32; x = x + 1)
			title_bytes[x] = "W";
		for(x = 0; x < 48; x = x + 1)
			title_bytes[32 + x] = "W";
		set_pixel(202, 24);
		check_result(text_pixel === 1'b1, "32nd directory character begins at x202");
		set_pixel(208, 24);
		check_result(text_pixel === 1'b0, "directory stops after 32 characters");
		set_pixel(298, 34);
		check_result(text_pixel === 1'b1, "48th basename character begins at x298");
		set_pixel(304, 34);
		check_result(text_pixel === 1'b0, "basename stops before x304");

		// One blank column follows every 5x7 glyph.
		set_pixel(21, 24);
		check_result(text_pixel === 1'b0, "sixth cell column blank");

		// Drawing-active is a hard clip.
		drawing_active = 0;
		set_pixel(16, 12);
		check_result(text_pixel === 1'b0, "drawing inactive clips text");
		set_pixel(8, 8);
		check_result(frame_pixel === 1'b0, "drawing inactive clips frame");
		drawing_active = 1;

		// Restore the historical navy screen frame on all four sides.  It is
		// two pixels wide and inset eight pixels from the 320x240 drawing edge.
		set_pixel(8, 120);
		check_result(frame_pixel === 1'b1, "left frame outer pixel");
		set_pixel(9, 120);
		check_result(frame_pixel === 1'b1, "left frame inner pixel");
		set_pixel(10, 120);
		check_result(frame_pixel === 1'b0, "left frame stops after two pixels");
		set_pixel(311, 120);
		check_result(frame_pixel === 1'b1, "right frame outer pixel");
		set_pixel(310, 120);
		check_result(frame_pixel === 1'b1, "right frame inner pixel");
		set_pixel(309, 120);
		check_result(frame_pixel === 1'b0, "right frame stops after two pixels");
		set_pixel(160, 8);
		check_result(frame_pixel === 1'b1, "top frame outer pixel");
		set_pixel(160, 9);
		check_result(frame_pixel === 1'b1, "top frame inner pixel");
		set_pixel(160, 10);
		check_result(frame_pixel === 1'b0, "top frame stops after two pixels");
		set_pixel(160, 231);
		check_result(frame_pixel === 1'b1, "bottom frame outer pixel");
		set_pixel(160, 230);
		check_result(frame_pixel === 1'b1, "bottom frame inner pixel");
		set_pixel(160, 229);
		check_result(frame_pixel === 1'b0, "bottom frame stops after two pixels");
		set_pixel(8, 8);
		check_result(frame_pixel === 1'b1, "top-left frame corner");
		set_pixel(311, 231);
		check_result(frame_pixel === 1'b1, "bottom-right frame corner");
		set_pixel(7, 8);
		check_result(frame_pixel === 1'b0, "pixel left of frame unchanged");
		set_pixel(312, 231);
		check_result(frame_pixel === 1'b0, "pixel right of frame unchanged");
		set_pixel(8, 7);
		check_result(frame_pixel === 1'b0, "pixel above frame unchanged");
		set_pixel(311, 232);
		check_result(frame_pixel === 1'b0, "pixel below frame unchanged");

		// Full 320x240 coverage proves exact border geometry, no changes outside
		// the four sides, no text collision at maximum metadata lengths, and
		// X/Z-free renderer outputs.
		frame_pixel_count = 0;
		text_frame_collision_count = 0;
		for(y = 0; y < 240; y = y + 1) begin
			for(x = 0; x < 320; x = x + 1) begin
				set_pixel(x, y);
				check_result((text_pixel === 1'b0) || (text_pixel === 1'b1),
				             "native renderer X/Z-free");
				check_result((frame_pixel === 1'b0) || (frame_pixel === 1'b1),
				             "native frame X/Z-free");
				check_result(frame_pixel ===
				             (((x >= 8) && (x <= 311) &&
				               (y >= 8) && (y <= 231) &&
				               ((x < 10) || (x > 309) ||
				                (y < 10) || (y > 229))) ? 1'b1 : 1'b0),
				             "frame predicate matches exact geometry");
				if(frame_pixel)
					frame_pixel_count = frame_pixel_count + 1;
				if(frame_pixel && text_pixel)
					text_frame_collision_count = text_frame_collision_count + 1;
			end
		end
		check_result(frame_pixel_count == 2096, "two-pixel frame area");
		check_result(text_frame_collision_count == 0,
		             "maximum title strings do not touch frame");
		for(ch = 8'h20; ch <= 8'h7e; ch = ch + 1) begin
			title_bytes[0] = ch;
			directory_length = 1;
			for(y = 24; y < 31; y = y + 1) begin
				for(x = 16; x < 21; x = x + 1) begin
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
