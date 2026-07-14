`timescale 1ns/1ps

module tb_segapcm_ddr_request_queue;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ready = 1'b0;
    logic valid = 1'b0;
    logic [7:0] data = 8'd0;
    logic [15:0] last_index = 16'd0;
    logic request_event = 1'b0;
    logic [3:0] request_ch = 4'd0;
    logic [18:0] request_index = 19'd0;
    logic [18:0] request_address = 19'd0;
    integer max_fifo_count = 0;
    wire rd_req;
    wire [18:0] rd_addr;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && dut.lab_jt_req_fifo_count_i > max_fifo_count)
            max_fifo_count <= dut.lab_jt_req_fifo_count_i;
    end

    segapcm_sound_module dut (
        .clk(clk), .reset(reset),
        .segapcm_cmd_valid(1'b0), .segapcm_cmd_addr(16'd0),
        .segapcm_cmd_data(8'd0),
        .segapcm_interface(32'h00f8_000d),
        .smoke_variant(3'd0), .smoke_variant_valid(1'b0),
        .smoke_source_loaded(1'b1), .loaded_payload_clear(1'b0),
        .loaded_payload_wr_valid(1'b0), .loaded_payload_wr_addr(19'd0),
        .loaded_payload_wr_data(8'd0), .loaded_payload_present(1'b1),
        .loaded_payload_length(19'h40000), .loaded_payload_block_count(16'd1),
        .smoke_ddr_follow_mode(1'b1), .smoke_ddr_follow_offset_sel(3'd0),
        .smoke_ddr_follow_delta_sel(3'd0), .smoke_ddr_follow_dest_map(1'b1),
        .smoke_ddr_follow_dest_basis(2'd1),
        .smoke_ddr_follow_dest_loop_wrap(1'b0), .smoke_c0_use_sel(2'd0),
        .smoke_c0_sample_mode_sel(3'd0), .smoke_c0_delta_speed_sel(2'd0),
        .smoke_c0_hit_window_sel(3'd0), .smoke_c0_format_sel(2'd0),
        .smoke_c0_mame_tick_div_sel(3'd0), .smoke_c0_vol_map_sel(3'd0),
        .smoke_c0_drive_sel(2'd1), .smoke_c0_pm3_audio_mask(16'hffff),
        .smoke_c0_pm3_mix_mode(2'd1), .smoke_c0_pm3_start_policy(3'd0),
        .smoke_c0_jt_backend(1'b1), .smoke_playback_running(1'b1),
        .smoke_playback_done(1'b0), .smoke_vgm_end_seen(1'b0),
        .loaded_type80_rom_size(32'h40000), .loaded_type80_rom_dest(32'd0),
        .loaded_ddr_rd_req(rd_req), .loaded_ddr_rd_ready(ready),
        .loaded_ddr_rd_addr(rd_addr), .loaded_ddr_rd_valid(valid),
        .loaded_ddr_rd_data(data), .loaded_ddr_payload_present(1'b1),
        .loaded_ddr_payload_length(19'h40000),
        .loaded_ddr_write_req_count_debug(16'd0),
        .loaded_ddr_write_count_debug(16'd0),
        .loaded_ddr_write_blocked_count_debug(16'd0),
        .loaded_ddr_write_status_debug(16'd0),
        .loaded_ddr_header_skip_count_debug(16'd0),
        .loaded_ddr_last_write_index_debug(16'd0),
        .loaded_ddr_last_write_addr_debug(16'd0),
        .loaded_ddr_last_write_lane_debug(16'd0),
        .loaded_ddr_last_write_data_debug(8'd0),
        .loaded_ddr_read_count_debug(16'd0),
        .loaded_ddr_last_read_index_debug(last_index),
        .loaded_ddr_last_read_addr_debug(16'd0),
        .loaded_ddr_last_read_lane_debug(16'd0),
        .loaded_ddr_last_read_word0_debug(16'd0),
        .loaded_ddr_last_read_word1_debug(16'd0),
        .loaded_ddr_last_read_data_debug(data),
        .loaded_ddr_base_addr_debug(16'd0),
        .loaded_ddr_probe_write_index_debug(16'd0),
        .loaded_ddr_probe_write_word_debug(16'd0),
        .loaded_ddr_probe_write_lane_debug(16'd0),
        .loaded_ddr_probe_write_addr_debug(16'd0),
        .loaded_ddr_probe_write_count_debug(16'd0),
        .loaded_ddr_probe_write_flags_debug(16'd0),
        .loaded_ddr_probe_write_word0_debug(16'd0),
        .loaded_ddr_probe_write_word6_debug(16'd0)
    );

    task request(input [3:0] ch, input [18:0] index,
                 input [18:0] address);
        begin
            @(negedge clk);
            request_ch = ch;
            request_index = index;
            request_address = address;
            request_event = 1'b1;
            @(posedge clk);
            #1;
            request_event = 1'b0;
        end
    endtask

    task accept_request(input [3:0] expected_ch,
                        input [18:0] expected_index);
        begin
            wait (rd_req);
            if (dut.lab_jt_ddr_issue_ch_i !== expected_ch ||
                rd_addr !== expected_index)
                $fatal(1, "issue order/tag mismatch");
            @(negedge clk); ready = 1'b1;
            @(posedge clk); #1;
            ready = 1'b0;
            if (!dut.lab_jt_ddr_owner_valid_i ||
                dut.lab_jt_ddr_owner_ch_i !== expected_ch ||
                dut.lab_jt_ddr_owner_index_i !== expected_index)
                $fatal(1, "accepted owner mismatch");
        end
    endtask

    task return_data(input [15:0] index, input [7:0] value,
                     input [3:0] expected_ch, input integer delay_cycles);
        begin
            repeat (delay_cycles) @(posedge clk);
            @(negedge clk);
            last_index = index;
            data = value;
            valid = 1'b1;
            @(posedge clk); #1;
            valid = 1'b0;
            if (!dut.lab_jt_sample_hold_valid_i[expected_ch] ||
                dut.lab_jt_sample_hold_i[expected_ch] !== value)
                $fatal(1, "channel hold was not updated");
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;
        force dut.lab_jt_req_src_ch = request_ch;
        force dut.lab_jt_payload_block_next = 3'd1;
        force dut.smoke_ddr_follow_read_index = request_index;
        force dut.lab_jt_rom_addr = request_address;
        force dut.rom_request_event = request_event;
        force dut.lab_c0_active_i = 1'b0;
        force dut.lab_jt_payload_match_valid_next = 1'b1;
        force dut.lab_jt_payload_index_in_range_next = 1'b1;
        force dut.smoke_ddr_follow_read_in_range_next = 1'b1;

        request(4'd1, 19'h00123, 19'h10123);
        wait (rd_req);
        request(4'd2, 19'h00234, 19'h10234);
        accept_request(4'd1, 19'h00123);
        return_data(16'h0123, 8'h6a, 4'd1, 3);
        accept_request(4'd2, 19'h00234);
        return_data(16'h0234, 8'h75, 4'd2, 3);

        // Galaxy Force has 39 ch1/ch2 retrigger commits in 96..100 s.
        // Model each commit's first read while the single-outstanding backend
        // takes the existing overlap TB's 50-cycle response latency.
        fork
            begin : produce_galaxy_retrigger_reads
                integer i;
                for (i = 0; i < 39; i = i + 1) begin
                    request((i % 3) == 2 ? 4'd1 : 4'd2,
                            19'h01000 + i, 19'h11000 + i);
                    repeat (40) @(posedge clk);
                end
            end
            begin : consume_galaxy_retrigger_reads
                integer i;
                reg [3:0] ch;
                for (i = 0; i < 39; i = i + 1) begin
                    ch = (i % 3) == 2 ? 4'd1 : 4'd2;
                    accept_request(ch, 19'h01000 + i);
                    return_data(16'h1000 + i, 8'h40 + i, ch, 50);
                end
            end
        join

        repeat (3) @(posedge clk);
        if (dut.lab_jt_req_event_count_i != 41 ||
            dut.lab_jt_req_issue_count_i != 41 ||
            dut.lab_jt_req_accept_count_i != 41 ||
            dut.lab_jt_req_response_count_i != 41 ||
            dut.lab_jt_req_queue_push_count_i != 41 ||
            dut.lab_jt_req_queue_pop_count_i != 41 ||
            dut.lab_jt_req_dropped_count_i != 0 ||
            dut.lab_jt_req_overflow_count_i != 0 ||
            dut.lab_jt_req_fifo_count_i != 0)
            $fatal(1, "request queue counters mismatch");
        $display("PASS tb_segapcm_ddr_request_queue galaxy_retrigger_first_reads=39 events=%0d issue=%0d accept=%0d response=%0d dropped=%0d overflow=%0d max_queue=%0d",
                 dut.lab_jt_req_event_count_i, dut.lab_jt_req_issue_count_i,
                 dut.lab_jt_req_accept_count_i, dut.lab_jt_req_response_count_i,
                 dut.lab_jt_req_dropped_count_i,
                 dut.lab_jt_req_overflow_count_i, max_fifo_count);
        $finish;
    end
endmodule
