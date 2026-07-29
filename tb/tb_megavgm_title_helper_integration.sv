`timescale 1ns/1ps

module tb_megavgm_title_helper_integration;

	logic clk = 1'b0;
	always #25 clk = ~clk;

	logic reset = 1'b0;
	logic ioctl_download = 1'b0;
	logic ioctl_wr = 1'b0;
	logic [26:0] ioctl_addr = 0;
	logic [7:0] ioctl_dout = 0;
	logic [15:0] ioctl_index = 1;
	logic title_valid;
	logic [5:0] directory_length;
	logic [5:0] basename_length;
	logic [6:0] title_read_addr = 0;
	logic [7:0] title_read_data;
	logic metadata_busy;
	byte unsigned prepared_bytes [0:387];
	integer prepared_size;
	integer i;
	integer timeout;
	string memory_file;

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

	task automatic check_byte(input integer address, input byte unsigned expected);
		begin
			title_read_addr = address;
			#1;
			if(title_read_data !== expected)
				$fatal(1, "title byte %0d: expected %02x, got %02x",
				       address, expected, title_read_data);
		end
	endtask

	initial begin
		if(!$value$plusargs("MEMORY_FILE=%s", memory_file))
			$fatal(1, "MEMORY_FILE plusarg is required");
		if(!$value$plusargs("PREPARED_SIZE=%d", prepared_size))
			$fatal(1, "PREPARED_SIZE plusarg is required");
		if(prepared_size != 388)
			$fatal(1, "invalid prepared size %0d", prepared_size);
		$readmemh(memory_file, prepared_bytes);

		reset = 1;
		repeat(3) tick();
		reset = 0;
		tick();

		ioctl_addr = 0;
		ioctl_dout = prepared_bytes[0];
		ioctl_wr = 1;
		ioctl_download = 1;
		tick();
		for(i = 1; i < prepared_size; i = i + 1) begin
			ioctl_addr = i;
			ioctl_dout = prepared_bytes[i];
			ioctl_wr = 1;
			tick();
		end
		ioctl_wr = 0;
		tick();
		ioctl_download = 0;
		tick();

		timeout = 0;
		while(metadata_busy && (timeout < 300)) begin
			if(title_valid)
				$fatal(1, "title became valid before atomic validation commit");
			tick();
			timeout = timeout + 1;
		end
		if(timeout >= 300)
			$fatal(1, "receiver validation timeout");
		tick();

		if(!title_valid)
			$fatal(1, "helper-produced trailer was rejected");
		if(directory_length != 7 || basename_length != 23)
			$fatal(1, "unexpected lengths %0d/%0d",
			       directory_length, basename_length);

		check_byte(0, "O");
		check_byte(1, "u");
		check_byte(2, "t");
		check_byte(3, " ");
		check_byte(4, "R");
		check_byte(5, "u");
		check_byte(6, "n");
		check_byte(32, "0");
		check_byte(33, "1");
		check_byte(34, "_");
		check_byte(35, "M");
		check_byte(54, "r");

		$display("PASS: helper output accepted by RTL receiver (%0d bytes)",
		         prepared_size);
		$finish;
	end

	initial begin
		#5_000_000;
		$fatal(1, "global simulation timeout");
	end

endmodule
