// SPDX-License-Identifier: GPL-2.0-or-later
//
// Read-only observer for the prepared-VGM display-name trailer.
//
// This module never stalls or modifies the ioctl stream. It retains the final
// 128 bytes in a ring, validates the complete trailer after the selected file
// download ends, and only then atomically publishes a new pair of names.

/* verilator lint_off PROCASSINIT */
module megavgm_title_receiver #(
	parameter logic [15:0] FILE_INDEX = 16'd1
) (
	input  logic        clk,
	input  logic        reset,
	input  logic        ioctl_download,
	input  logic        ioctl_wr,
	input  logic [26:0] ioctl_addr,
	input  logic [7:0]  ioctl_dout,
	input  logic [15:0] ioctl_index,

	output logic        title_valid = 1'b0,
	output logic [5:0]  directory_length = 6'd0,
	output logic [5:0]  basename_length = 6'd0,
	input  logic [6:0]  title_read_addr,
	output logic [7:0]  title_read_data,

	output logic        metadata_busy
);

	(* ramstyle = "MLAB" *) logic [7:0] trailer_ring [0:127];

	logic        ioctl_download_d = 1'b0;
	logic        selected_download = 1'b0;
	logic [27:0] physical_size = 28'd0;

	logic        validation_active = 1'b0;
	logic [7:0]  validation_offset = 8'd0;
	logic [6:0]  trailer_base_low = 7'd0;
	logic [27:0] expected_original_size = 28'd0;
	logic        validation_failed = 1'b0;
	logic [1:0]  candidate_flags = 2'd0;
	logic [5:0]  candidate_directory_length = 6'd0;
	logic [5:0]  candidate_basename_length = 6'd0;

	wire download_start = ioctl_download && !ioctl_download_d;
	wire download_end   = !ioctl_download && ioctl_download_d;
	wire index_matches  = ioctl_index == FILE_INDEX;
	wire [6:0] title_trailer_offset =
		(title_read_addr < 32) ? (7'd32 + title_read_addr) :
		                         (7'd64 + title_read_addr - 7'd32);
	// Validation and display are mutually exclusive. Muxing the read address
	// lets Quartus infer one small asynchronous ring RAM instead of duplicating
	// it for two read ports.
	wire [6:0] ring_read_address =
		trailer_base_low +
		(validation_active ? validation_offset[6:0] : title_trailer_offset);
	wire [7:0] ring_read_byte = trailer_ring[ring_read_address];
	wire [7:0] validation_byte = ring_read_byte;

	function automatic [7:0] magic_byte(input logic [2:0] offset);
		begin
			case(offset)
				0: magic_byte = 8'h4d;
				1: magic_byte = 8'h56;
				2: magic_byte = 8'h47;
				3: magic_byte = 8'h4d;
				4: magic_byte = 8'h54;
				5: magic_byte = 8'h54;
				6: magic_byte = 8'h4c;
				default: magic_byte = 8'h00;
			endcase
		end
	endfunction

	logic current_byte_invalid;
	always @* begin
		current_byte_invalid = 1'b0;

		if(validation_active) begin
			if(validation_offset < 8) begin
				current_byte_invalid = validation_byte != magic_byte(validation_offset[2:0]);
			end
			else begin
				case(validation_offset)
					8:  current_byte_invalid = validation_byte != 8'd1;
					9:  current_byte_invalid = (validation_byte & 8'hfc) != 0;
					10: current_byte_invalid = validation_byte > 8'd32;
					11: current_byte_invalid =
						(validation_byte > 8'd48) ||
						(candidate_flags[0] != (candidate_directory_length != 0)) ||
						(candidate_flags[1] != (validation_byte != 0));
					12: current_byte_invalid = validation_byte != 8'h80;
					13: current_byte_invalid = validation_byte != 8'h00;
					14, 15: current_byte_invalid = validation_byte != 0;
					16: current_byte_invalid = validation_byte != expected_original_size[7:0];
					17: current_byte_invalid = validation_byte != expected_original_size[15:8];
					18: current_byte_invalid = validation_byte != expected_original_size[23:16];
					19: current_byte_invalid =
						validation_byte != {4'd0, expected_original_size[27:24]};
					default: begin
						if((validation_offset >= 20) && (validation_offset < 32))
							current_byte_invalid = validation_byte != 0;
						else if((validation_offset >= 32) && (validation_offset < 64)) begin
							if((validation_offset - 32) < candidate_directory_length)
								current_byte_invalid =
									(validation_byte < 8'h20) || (validation_byte > 8'h7e);
							else
								current_byte_invalid = validation_byte != 0;
						end
						else if((validation_offset >= 64) && (validation_offset < 112)) begin
							if((validation_offset - 64) < candidate_basename_length)
								current_byte_invalid =
									(validation_byte < 8'h20) || (validation_byte > 8'h7e);
							else
								current_byte_invalid = validation_byte != 0;
						end
						else
							current_byte_invalid = validation_byte != 0;
					end
				endcase
			end
		end
	end

	always @* begin
		if(!title_valid)
			title_read_data = 8'h00;
		else
			title_read_data = ring_read_byte;
	end

	assign metadata_busy = selected_download || validation_active;

	always_ff @(posedge clk) begin
		ioctl_download_d <= ioctl_download;

		// Soft reset aborts only an in-progress observation. A completed title
		// deliberately remains visible across the player's Reset command.
		if(reset) begin
			ioctl_download_d <= ioctl_download;
			selected_download <= 1'b0;
			validation_active <= 1'b0;
			physical_size <= 0;
		end
		else begin
			if(download_start && index_matches) begin
				selected_download <= 1'b1;
				validation_active <= 1'b0;
				physical_size <= 0;
				title_valid <= 1'b0;
				directory_length <= 0;
				basename_length <= 0;
			end
			else if(download_start) begin
				selected_download <= 1'b0;
			end

			if((selected_download || (download_start && index_matches)) &&
			   ioctl_download && ioctl_wr && index_matches) begin
				trailer_ring[ioctl_addr[6:0]] <= ioctl_dout;
				if(download_start)
					physical_size <= {1'b0, ioctl_addr} + 1'b1;
				else begin
					if(({1'b0, ioctl_addr} + 1'b1) > physical_size)
						physical_size <= {1'b0, ioctl_addr} + 1'b1;
				end
			end

			if(download_end && selected_download) begin
				selected_download <= 1'b0;
				if(physical_size >= 128) begin
					validation_active <= 1'b1;
					validation_offset <= 0;
					// Subtracting the 128-byte ring size does not change
					// the low seven address bits.
					trailer_base_low <= physical_size[6:0];
					expected_original_size <= physical_size - 128;
					validation_failed <= 1'b0;
					candidate_flags <= 0;
					candidate_directory_length <= 0;
					candidate_basename_length <= 0;
				end
			end

			// A new selected load always wins over publication of the previous
			// trailer, including the unlikely final-validation-cycle overlap.
			if(validation_active && !(download_start && index_matches)) begin
				if(validation_offset == 9)
					candidate_flags <= validation_byte[1:0];
				if(validation_offset == 10)
					candidate_directory_length <= validation_byte[5:0];
				if(validation_offset == 11)
					candidate_basename_length <= validation_byte[5:0];

				if(current_byte_invalid)
					validation_failed <= 1'b1;

				if(validation_offset == 127) begin
					validation_active <= 1'b0;
					if(!validation_failed && !current_byte_invalid) begin
						title_valid <= 1'b1;
						directory_length <= candidate_directory_length;
						basename_length <= candidate_basename_length;
					end
				end
				else begin
					validation_offset <= validation_offset + 1'b1;
				end
			end
		end
	end

endmodule
/* verilator lint_on PROCASSINIT */
