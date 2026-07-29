`timescale 1ns/1ps

module tb_megavgm_title_receiver;

	logic clk = 1'b0;
	always #25 clk = ~clk;

	logic reset = 1'b0;
	logic ioctl_download = 1'b0;
	logic ioctl_wr = 1'b0;
	logic [26:0] ioctl_addr = 0;
	logic [7:0] ioctl_dout = 0;
	logic [15:0] ioctl_index = 0;
	logic title_valid;
	logic [5:0] directory_length;
	logic [5:0] basename_length;
	logic [6:0] title_read_addr = 0;
	logic [7:0] title_read_data;
	logic metadata_busy;

	byte unsigned file_bytes [0:2047];
	integer file_size;
	integer trailer_start;
	integer checks = 0;
	integer failures = 0;

	megavgm_title_receiver dut (
		.clk(clk),
		.reset(reset),
		.ioctl_download(ioctl_download),
		.ioctl_wr(ioctl_wr),
		.ioctl_addr(ioctl_addr),
		.ioctl_dout(ioctl_dout),
		.ioctl_index(ioctl_index),
		.title_valid(title_valid),
		.directory_length(directory_length),
		.basename_length(basename_length),
		.title_read_addr(title_read_addr),
		.title_read_data(title_read_data),
		.metadata_busy(metadata_busy)
	);

	task automatic tick;
		begin
			@(posedge clk);
			#1;
		end
	endtask

	task automatic check_result(input logic condition, input string message);
		begin
			checks = checks + 1;
			if(!condition) begin
				failures = failures + 1;
				$display("FAIL: %s", message);
			end
		end
	endtask

	task automatic build_valid(
		input integer body_size,
		input integer directory_size,
		input integer basename_size
	);
		integer i;
		begin
			for(i = 0; i < 2048; i = i + 1)
				file_bytes[i] = 0;
			for(i = 0; i < body_size; i = i + 1)
				file_bytes[i] = (i * 29 + 8'h37) & 8'hff;

			trailer_start = body_size;
			file_size = body_size + 128;
			file_bytes[trailer_start + 0] = "M";
			file_bytes[trailer_start + 1] = "V";
			file_bytes[trailer_start + 2] = "G";
			file_bytes[trailer_start + 3] = "M";
			file_bytes[trailer_start + 4] = "T";
			file_bytes[trailer_start + 5] = "T";
			file_bytes[trailer_start + 6] = "L";
			file_bytes[trailer_start + 7] = 0;
			file_bytes[trailer_start + 8] = 1;
			file_bytes[trailer_start + 9] =
				(directory_size != 0) | ((basename_size != 0) << 1);
			file_bytes[trailer_start + 10] = directory_size;
			file_bytes[trailer_start + 11] = basename_size;
			file_bytes[trailer_start + 12] = 8'h80;
			file_bytes[trailer_start + 13] = 0;
			file_bytes[trailer_start + 16] = body_size[7:0];
			file_bytes[trailer_start + 17] = body_size[15:8];
			file_bytes[trailer_start + 18] = body_size[23:16];
			file_bytes[trailer_start + 19] = body_size[31:24];
			for(i = 0; i < directory_size; i = i + 1)
				file_bytes[trailer_start + 32 + i] = "A" + (i % 26);
			for(i = 0; i < basename_size; i = i + 1)
				file_bytes[trailer_start + 64 + i] = "a" + (i % 26);
		end
	endtask

	task automatic set_example_names;
		begin
			file_bytes[trailer_start + 32 + 0] = "O";
			file_bytes[trailer_start + 32 + 1] = "u";
			file_bytes[trailer_start + 32 + 2] = "t";
			file_bytes[trailer_start + 32 + 3] = " ";
			file_bytes[trailer_start + 32 + 4] = "R";
			file_bytes[trailer_start + 32 + 5] = "u";
			file_bytes[trailer_start + 32 + 6] = "n";

			file_bytes[trailer_start + 64 + 0]  = "0";
			file_bytes[trailer_start + 64 + 1]  = "1";
			file_bytes[trailer_start + 64 + 2]  = "_";
			file_bytes[trailer_start + 64 + 3]  = "M";
			file_bytes[trailer_start + 64 + 4]  = "a";
			file_bytes[trailer_start + 64 + 5]  = "g";
			file_bytes[trailer_start + 64 + 6]  = "i";
			file_bytes[trailer_start + 64 + 7]  = "c";
			file_bytes[trailer_start + 64 + 8]  = "a";
			file_bytes[trailer_start + 64 + 9]  = "l";
			file_bytes[trailer_start + 64 + 10] = " ";
			file_bytes[trailer_start + 64 + 11] = "S";
			file_bytes[trailer_start + 64 + 12] = "o";
			file_bytes[trailer_start + 64 + 13] = "u";
			file_bytes[trailer_start + 64 + 14] = "n";
			file_bytes[trailer_start + 64 + 15] = "d";
			file_bytes[trailer_start + 64 + 16] = " ";
			file_bytes[trailer_start + 64 + 17] = "S";
			file_bytes[trailer_start + 64 + 18] = "h";
			file_bytes[trailer_start + 64 + 19] = "o";
			file_bytes[trailer_start + 64 + 20] = "w";
			file_bytes[trailer_start + 64 + 21] = "e";
			file_bytes[trailer_start + 64 + 22] = "r";
		end
	endtask

	task automatic send_file(input logic [15:0] file_index);
		integer i;
		integer timeout;
		begin
			ioctl_index = file_index;
			ioctl_addr = 0;
			ioctl_dout = file_bytes[0];
			ioctl_wr = 1;
			ioctl_download = 1;
			tick();

			for(i = 1; i < file_size; i = i + 1) begin
				ioctl_addr = i;
				ioctl_dout = file_bytes[i];
				ioctl_wr = 1;
				tick();
			end
			ioctl_wr = 0;
			tick();
			ioctl_download = 0;
			tick();

			timeout = 0;
			while(metadata_busy && (timeout < 300)) begin
				check_result(!title_valid, "title committed before validation completed");
				tick();
				timeout = timeout + 1;
			end
			check_result(timeout < 300, "metadata validation timeout");
			tick();
		end
	endtask

	task automatic expect_example_names;
		byte unsigned expected;
		integer i;
		begin
			check_result(title_valid, "example trailer accepted");
			check_result(directory_length == 7, "example directory length");
			check_result(basename_length == 23, "example basename length");
			for(i = 0; i < 7; i = i + 1) begin
				case(i)
					0: expected = "O"; 1: expected = "u"; 2: expected = "t";
					3: expected = " "; 4: expected = "R"; 5: expected = "u";
					default: expected = "n";
				endcase
				title_read_addr = i;
				#1;
				check_result(title_read_data == expected, "example directory byte");
			end
			title_read_addr = 32;
			#1;
			check_result(title_read_data == "0", "example basename first byte");
			title_read_addr = 54;
			#1;
			check_result(title_read_data == "r", "example basename last byte");
		end
	endtask

	task automatic expect_invalid(input string message);
		begin
			check_result(!title_valid, message);
			check_result(directory_length == 0, "invalid trailer directory length cleared");
			check_result(basename_length == 0, "invalid trailer basename length cleared");
			title_read_addr = 0;
			#1;
			check_result(title_read_data == 0, "invalid trailer read data blank");
		end
	endtask

	initial begin
		$display("YM title receiver: 18 validation cases");
		reset = 1;
		repeat(3) tick();
		reset = 0;
		tick();

		// 1. Valid trailer at a non-zero ring rotation.
		build_valid(259, 7, 23);
		set_example_names();
		send_file(16'd1);
		expect_example_names();

		// 2. Player Reset preserves a completed title.
		reset = 1;
		repeat(3) tick();
		reset = 0;
		tick();
		expect_example_names();

		// 3. An unrelated ioctl file index is ignored.
		build_valid(173, 4, 5);
		send_file(16'd2);
		expect_example_names();

		// 4. A selected load clears the old title immediately, then commits.
		build_valid(129, 3, 4);
		ioctl_index = 1;
		ioctl_download = 1;
		tick();
		check_result(!title_valid, "selected load start clears old title");
		ioctl_download = 0;
		tick();
		build_valid(129, 3, 4);
		send_file(16'd1);
		check_result(title_valid && directory_length == 3 && basename_length == 4,
		             "new selected trailer committed");

		// 5. Maximum field lengths.
		build_valid(384, 32, 48);
		send_file(16'd1);
		check_result(title_valid && directory_length == 32 && basename_length == 48,
		             "32/48 boundary accepted");

		// 6. Empty but structurally valid names.
		build_valid(130, 0, 0);
		send_file(16'd1);
		check_result(title_valid && directory_length == 0 && basename_length == 0,
		             "empty valid trailer accepted");

		// 7. No complete trailer.
		build_valid(0, 0, 0);
		file_size = 64;
		send_file(16'd1);
		expect_invalid("short file rejected");

		// 8. Bad magic.
		build_valid(140, 3, 4);
		file_bytes[trailer_start] = "X";
		send_file(16'd1);
		expect_invalid("bad magic rejected");

		// 9. Unknown version.
		build_valid(141, 3, 4);
		file_bytes[trailer_start + 8] = 2;
		send_file(16'd1);
		expect_invalid("unknown version rejected");

		// 10. Unknown flag bit.
		build_valid(142, 3, 4);
		file_bytes[trailer_start + 9] = 8'h83;
		send_file(16'd1);
		expect_invalid("unknown flags rejected");

		// 11. Directory length overflow.
		build_valid(143, 32, 4);
		file_bytes[trailer_start + 10] = 33;
		send_file(16'd1);
		expect_invalid("directory overflow rejected");

		// 12. Basename length overflow.
		build_valid(144, 3, 48);
		file_bytes[trailer_start + 11] = 49;
		send_file(16'd1);
		expect_invalid("basename overflow rejected");

		// 13. Incorrect trailer-size field.
		build_valid(145, 3, 4);
		file_bytes[trailer_start + 12] = 8'h7f;
		send_file(16'd1);
		expect_invalid("trailer size mismatch rejected");

		// 14. Original-size/physical-size mismatch.
		build_valid(146, 3, 4);
		file_bytes[trailer_start + 16] =
			file_bytes[trailer_start + 16] + 1;
		send_file(16'd1);
		expect_invalid("original size mismatch rejected");

		// 15. Non-zero header reserved byte.
		build_valid(147, 3, 4);
		file_bytes[trailer_start + 20] = 1;
		send_file(16'd1);
		expect_invalid("header reserved byte rejected");

		// 16. Non-zero field padding.
		build_valid(148, 3, 4);
		file_bytes[trailer_start + 32 + 3] = "X";
		send_file(16'd1);
		expect_invalid("directory padding rejected");

		// 17. Non-printable byte inside a declared name.
		build_valid(149, 3, 4);
		file_bytes[trailer_start + 64 + 1] = 8'h1f;
		send_file(16'd1);
		expect_invalid("non-printable name byte rejected");

		// 18. Non-zero future-use byte.
		build_valid(150, 3, 4);
		file_bytes[trailer_start + 127] = 1;
		send_file(16'd1);
		expect_invalid("future reserved byte rejected");

		if(failures == 0) begin
			$display("PASS: 18/18 receiver cases, %0d checks", checks);
			$finish;
		end
		$fatal(1, "FAIL: %0d of %0d checks failed", failures, checks);
	end

	initial begin
		#20_000_000;
		$fatal(1, "FAIL: global simulation timeout");
	end

endmodule
