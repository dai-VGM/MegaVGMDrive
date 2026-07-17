`timescale 1ns/1ps

module tb_segapcm_ddr_request_queue;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic payload_clear = 1'b0;
    logic ready = 1'b0;
    logic valid = 1'b0;
    logic [7:0] data = 8'd0;
    logic [15:0] last_index = 16'd0;
    logic request_event = 1'b0;
    logic [3:0] request_ch = 4'd0;
    logic [18:0] request_index = 19'd0;
    logic [18:0] mapper_index = 19'd0;
    logic [18:0] request_address = 19'd0;
    logic [3:0] request_block = 4'd1;
    logic mapper_hit = 1'b1;
    logic mapper_range = 1'b1;
    logic follow_range = 1'b1;
    logic [18:0] payload_length = 19'h40000;
    logic [31:0] vgm_wait_ticks = 32'd0;
    logic payload_wr_valid = 1'b0;
    logic [18:0] payload_wr_addr = 19'd0;
    logic [31:0] type80_rom_size = 32'd0;
    logic [31:0] type80_rom_dest = 32'd0;
    integer max_fifo_count = 0;
    integer descriptor_commit_count = 0;
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
        .smoke_source_loaded(1'b1), .loaded_payload_clear(payload_clear),
        .loaded_payload_wr_valid(payload_wr_valid),
        .loaded_payload_wr_addr(payload_wr_addr),
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
        .smoke_vgm_wait_ticks(vgm_wait_ticks),
        .loaded_type80_rom_size(type80_rom_size),
        .loaded_type80_rom_dest(type80_rom_dest),
        .loaded_ddr_rd_req(rd_req), .loaded_ddr_rd_ready(ready),
        .loaded_ddr_rd_addr(rd_addr), .loaded_ddr_rd_valid(valid),
        .loaded_ddr_rd_data(data), .loaded_ddr_payload_present(1'b1),
        .loaded_ddr_payload_length(payload_length),
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
        .loaded_ddr_last_read_lane_debug({13'd0, last_index[2:0]}),
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

    task register_descriptor(input [3:0] expected_block,
                             input [20:0] dest,
                             input [18:0] base,
                             input [18:0] length);
        begin
            @(negedge clk);
            type80_rom_dest = {11'd0, dest};
            type80_rom_size = {13'd0, length} + 32'd8;
            payload_wr_addr = base;
            payload_wr_valid = 1'b1;
            @(posedge clk); #1;
            payload_wr_valid = 1'b0;
            if (!dut.smoke_type80_table_valid_i[expected_block] ||
                dut.smoke_type80_table_dest_i[expected_block] !== dest ||
                dut.smoke_type80_table_base_i[expected_block] !== base ||
                dut.smoke_type80_table_len_i[expected_block] !== length ||
                dut.smoke_type80_table_count_i !== (expected_block + 5'd1))
                $fatal(1, "descriptor commit mismatch block=%0d", expected_block);
            descriptor_commit_count = descriptor_commit_count + 1;
            $display("DESCRIPTOR_COMMIT t=%0t block=%0d dest=%05h base=%05h len=%05h count=%0d",
                     $time, expected_block, dest, base, length,
                     dut.smoke_type80_table_count_i);
            repeat (2) @(posedge clk);
        end
    endtask

    task request(input [3:0] ch, input [18:0] index,
                 input [18:0] address);
        begin
            @(negedge clk);
            request_ch = ch;
            request_index = index;
            mapper_index = index;
            request_address = address;
            request_event = 1'b1;
            // Inject one already-qualified wrapper event. A procedural force
            // is used per pulse because Icarus snapshots force-expression RHS.
            force dut.lab_jt_request_seen_pulse = 1'b1;
            @(posedge clk);
            #1;
            request_event = 1'b0;
            release dut.lab_jt_request_seen_pulse;
        end
    endtask

    task accept_request(input [3:0] expected_ch,
                        input [18:0] expected_index);
        begin
            wait (rd_req);
            if (dut.lab_jt_ddr_issue_ch_i !== expected_ch ||
                rd_addr !== expected_index)
                $fatal(1, "issue order/tag mismatch ch=%0d/%0d idx=%05h/%05h",
                       dut.lab_jt_ddr_issue_ch_i, expected_ch,
                       rd_addr, expected_index);
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

    task probe_path(input [3:0] ch, input [3:0] block,
                    input [18:0] index, input [18:0] address,
                    input [7:0] value);
        begin
            request_block = block;
            request(ch, index, address);
            accept_request(ch, index);
            return_data(index[15:0], value, ch, 3);
        end
    endtask

    initial begin
        payload_length = 19'h40000;
        repeat (4) @(posedge clk);
        reset = 1'b0;
        register_descriptor(4'd0, 21'h00000, 19'h00000, 19'h00d00);
        register_descriptor(4'd1, 21'h02c00, 19'h00d00, 19'h04300);
        register_descriptor(4'd2, 21'h08000, 19'h05000, 19'h08000);
        register_descriptor(4'd3, 21'h2c000, 19'h0d000, 19'h14000);
        register_descriptor(4'd4, 21'h42000, 19'h21000, 19'h00400);
        register_descriptor(4'd5, 21'h50000, 19'h21400, 19'h00400);
        register_descriptor(4'd6, 21'h59600, 19'h21800, 19'h04000);
        if (descriptor_commit_count != 7 ||
            dut.smoke_type80_table_count_i != 5'd7 ||
            dut.lab_jt_req_event_count_i != 16'd0)
            $fatal(1, "play-start preparation mismatch commits=%0d table=%0d early_req=%0d",
                   descriptor_commit_count, dut.smoke_type80_table_count_i,
                   dut.lab_jt_req_event_count_i);
        force dut.smoke_loaded_ddr_usable_bytes = 19'h40000;
        force dut.lab_jt_rom_addr = 19'h00000;
        #1;
        if (!dut.lab_jt_payload_table_hit_next ||
            !dut.lab_jt_payload_index_in_range_next ||
            dut.lab_jt_payload_block_next !== 4'd0 ||
            dut.lab_jt_payload_read_index_next !== 19'h00000)
            $fatal(1, "first Final Take Off request did not map to block 0");
        release dut.lab_jt_rom_addr;
        release dut.smoke_loaded_ddr_usable_bytes;
        $display("PLAY_START_READY t=%0t descriptors=7/7 early_requests=0",
                 $time);
        // Isolate the existing directed FIFO/ownership tests from the
        // descriptor-start phase above.
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        @(negedge clk);
        dut.smoke_type80_table_valid_i[2] = 1'b1;
        dut.smoke_type80_table_dest_i[2] = 21'h08000;
        dut.smoke_type80_table_base_i[2] = 19'h05000;
        dut.smoke_type80_table_len_i[2] = 19'h08000;
        force dut.smoke_loaded_ddr_usable_bytes = 19'h40000;
        force dut.lab_jt_rom_addr = 19'h0893b;
        #1;
        $display("893b map hit=%b range=%b block=%0d off=%05h idx=%05h wide=%05h usable=%05h",
                 dut.lab_jt_payload_table_hit_next,
                 dut.lab_jt_payload_index_in_range_next,
                 dut.lab_jt_payload_block_next,
                 dut.lab_jt_payload_offset_next,
                 dut.lab_jt_payload_read_index_next,
                 dut.lab_jt_payload_read_index_wide_next,
                 dut.smoke_loaded_ddr_usable_bytes);
        if (!dut.lab_jt_payload_table_hit_next ||
            !dut.lab_jt_payload_index_in_range_next ||
            dut.lab_jt_payload_block_next !== 4'd2 ||
            dut.lab_jt_payload_offset_next !== 19'h0093b ||
            dut.lab_jt_payload_read_index_next !== 19'h0593b ||
            dut.lab_jt_payload_read_index_wide_next !== 20'h0593b)
            $fatal(1, "RQ 0x0893b mapper equation mismatch");
        release dut.lab_jt_rom_addr;
        dut.smoke_type80_table_valid_i[2] = 1'b0;
        force dut.lab_jt_req_src_ch = request_ch;
        force dut.lab_jt_payload_block_next = request_block;
        force dut.smoke_ddr_follow_read_index = request_index;
        force dut.lab_jt_rom_addr = request_address;
        force dut.rom_request_event = request_event;
        force dut.lab_c0_active_i = 1'b0;
        force dut.lab_jt_payload_table_hit_next = mapper_hit;
        force dut.lab_jt_payload_match_valid_next = mapper_hit && mapper_range;
        force dut.lab_jt_payload_index_in_range_next = mapper_range;
        force dut.lab_jt_payload_read_index_next = mapper_index;
        force dut.smoke_ddr_follow_read_in_range_next = follow_range;
        @(negedge clk);
        dut.smoke_type80_table_valid_i[6] = 1'b1;
        dut.smoke_type80_table_dest_i[6] = 21'h59600;
        dut.smoke_type80_table_base_i[6] = 19'h21800;
        dut.smoke_type80_table_len_i[6] = 19'h04000;

        request(4'd1, 19'h00123, 19'h10123);
        wait (rd_req);
        request(4'd2, 19'h00234, 19'h10234);
        accept_request(4'd1, 19'h00123);
        return_data(16'h0123, 8'h6a, 4'd1, 3);
        accept_request(4'd2, 19'h00234);
        return_data(16'h0234, 8'h75, 4'd2, 3);

        // Enter the Final Take Off 26..33 s window. Reproduce the two block-6
        // silent strikes followed by the normal block-3 strike, for ch0/ch1.
        vgm_wait_ticks = 32'd1_146_600;
        @(posedge clk); #1;
        probe_path(4'd0, 4'd6, 19'h21800, 19'h59600, 8'h7a);
        probe_path(4'd1, 4'd6, 19'h21800, 19'h59600, 8'h7a);
        probe_path(4'd0, 4'd6, 19'h21800, 19'h59600, 8'h7a);
        probe_path(4'd1, 4'd6, 19'h21800, 19'h59600, 8'h7a);
        probe_path(4'd0, 4'd3, 19'h0d000, 19'h2c000, 8'h81);
        probe_path(4'd1, 4'd3, 19'h0d000, 19'h2c000, 8'h81);
        if (dut.ch01_probe_failure_valid_i)
            $fatal(1, "valid block6/block3 requests triggered snapshot");
        if (dut.pipeline_probe_fault_flags_i !== 8'd0 ||
            dut.pipeline_probe_qd_i !== 16'd0 ||
            dut.pipeline_probe_rd_i !== 16'd0 ||
            dut.pipeline_probe_ad_i !== 16'd0 ||
            dut.pipeline_probe_hd_i !== 16'd0)
            $fatal(1, "normal pipeline did not drain cleanly");

        // First failure A: request/event and mapper both see 0x595ff, one byte
        // below block 6. Previous is the last block-3 request; next is 0x59600.
        // Hold a deterministic JT live-state image so the observation-only
        // fault snapshot and its five overlay words can be checked directly.
        force dut.lab_jt_rv65_normal_current_before = 24'h200000;
        force dut.lab_jt_rv68_loop_addr = 16'h2000;
        // At the first oracle 0x02000 slot, the following end=0x23 write has
        // not landed yet; live end is still the preceding voice's 0x97.
        force dut.lab_jt_live_end_addr = 8'h97;
        force dut.lab_jt_rv65_normal_delta = 8'h70;
        force dut.lab_jt_dbg_active_cfg = 16'h1002;
        force dut.lab_jt_dbg_vol_lr = 16'h272e;
        force dut.lab_jt_control_written_mask = 16'h0010;
        force dut.lab_jt_scratch_valid_mask = 16'h0000;
        force dut.lab_jt_current_source_flags = 8'h18;
        force dut.lab_jt_rv62_live_state_channel = 16'h0084;
        mapper_hit = 1'b0;
        mapper_range = 1'b0;
        follow_range = 1'b0;
        request_block = 4'd0;
        request(4'd0, 19'h00000, 19'h595ff);
        request_address = 19'h59600;
        @(posedge clk); #1;
        $display("pipeline A B=%08h R=%08h H=%08h C=%08h M=%04h",
                 dut.block6_probe_b6_debug, dut.block6_probe_r6_debug,
                 dut.block6_probe_h6_debug, dut.block6_probe_c6_debug,
                 dut.block6_probe_m6_debug);
        $display("snapshot A idx=%05h upper=%05h input=%05h port=%05h usable=%05h b6=%05h/%05h/%05h",
                 dut.ch01_probe_failure_index_i,
                 dut.ch01_probe_failure_upper_i,
                 payload_length,
                 dut.loaded_ddr_payload_length,
                 dut.smoke_loaded_ddr_usable_bytes,
                 dut.ch01_probe_failure_b6_dest_i,
                 dut.ch01_probe_failure_b6_base_i,
                 dut.ch01_probe_failure_b6_len_i);
	        if (dut.pipeline_probe_fault_mapping_subflags_i !== 5'b00011 ||
            !dut.ch01_probe_failure_valid_i ||
            dut.ch01_probe_failure_type_b_i ||
            dut.ch01_probe_failure_ch_i !== 4'd0 ||
            dut.ch01_probe_failure_jt_addr_i !== 19'h595ff ||
            dut.ch01_probe_failure_mapper_addr_i !== 19'h595ff ||
            dut.ch01_probe_failure_event_addr_i !== 19'h595ff ||
            dut.ch01_probe_failure_prev_addr_i !== 19'h2c000 ||
            dut.ch01_probe_failure_next_addr_i !== 19'h59600 ||
            dut.ch01_probe_failure_bank_i !== 3'd5 ||
            dut.ch01_probe_failure_current_i !== 16'h95ff ||
            dut.ch01_probe_failure_mapper_valid_i ||
            dut.ch01_probe_failure_in_range_i ||
            dut.ch01_probe_failure_index_i !== 19'h00000 ||
            dut.ch01_probe_failure_upper_i !== 19'h40000 ||
            dut.ch01_probe_failure_b6_dest_i !== 21'h59600 ||
            dut.ch01_probe_failure_b6_base_i !== 19'h21800 ||
            dut.ch01_probe_failure_b6_len_i !== 19'h04000 ||
            dut.ch01_probe_failure_inside_b6_i)
            $fatal(1, "first mapper-failure snapshot mismatch");
        vgm_wait_ticks = 32'd1_455_300;
        request_block = 4'd1;
        mapper_hit = 1'b1;
        mapper_range = 1'b1;
        follow_range = 1'b1;

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
        if (dut.lab_jt_req_event_count_i != 47 ||
            dut.lab_jt_req_issue_count_i != 47 ||
            dut.lab_jt_req_accept_count_i != 47 ||
            dut.lab_jt_req_response_count_i != 47 ||
            dut.lab_jt_req_queue_push_count_i != 47 ||
            dut.lab_jt_req_queue_pop_count_i != 47 ||
            dut.lab_jt_req_dropped_count_i != 0 ||
            dut.lab_jt_req_overflow_count_i != 0 ||
            dut.lab_jt_req_fifo_count_i != 0)
            $fatal(1, "request queue counters mismatch");
	        if (dut.pipeline_probe_re_count_i !== 16'd48 ||
	            dut.pipeline_probe_hu_count_i !== 16'd47 ||
	            dut.pipeline_probe_rr_count_i !== 16'd47 ||
	            dut.pipeline_probe_gr_count_i !== 16'd0 ||
	            dut.pipeline_probe_nn_count_i !== 16'd47)
            $fatal(1, "pipeline visibility counters/last values mismatch");
	        $display("QUEUE PASS galaxy_retrigger_first_reads=39 events=%0d issue=%0d accept=%0d response=%0d dropped=%0d overflow=%0d max_queue=%0d",
                 dut.lab_jt_req_event_count_i, dut.lab_jt_req_issue_count_i,
                 dut.lab_jt_req_accept_count_i, dut.lab_jt_req_response_count_i,
                 dut.lab_jt_req_dropped_count_i,
	                 dut.lab_jt_req_overflow_count_i, max_fifo_count);
	        $display("COVERAGE RR=%0d GR=%0d NN=%0d CN=%0d NZ=%0d OM=%0d",
	                 dut.pipeline_probe_rr_count_i,
	                 dut.pipeline_probe_gr_count_i,
	                 dut.pipeline_probe_nn_count_i,
	                 dut.pipeline_probe_cn_count_i,
	                 dut.pipeline_probe_nz_count_i,
	                 dut.pipeline_probe_om_count_i);

        // Re-arm and reproduce the hardware failure B without forcing mapper
        // results. The active C0 lab backend exposes only 0x20000 payload bytes.
        vgm_wait_ticks = 32'd0;
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        @(negedge clk);
        dut.smoke_type80_table_valid_i[6] = 1'b1;
        dut.smoke_type80_table_dest_i[6] = 21'h59600;
        dut.smoke_type80_table_base_i[6] = 19'h21800;
        dut.smoke_type80_table_len_i[6] = 19'h04000;
        release dut.lab_jt_payload_table_hit_next;
        release dut.lab_jt_payload_match_valid_next;
        release dut.lab_jt_payload_index_in_range_next;
        release dut.lab_jt_payload_read_index_next;
        release dut.smoke_ddr_follow_read_in_range_next;
        payload_length = 19'h20000;
        release dut.smoke_loaded_ddr_usable_bytes;
        force dut.smoke_loaded_ddr_usable_bytes = 19'h20000;
        request_block = 4'd6;
        request_address = 19'h0c00f;
        vgm_wait_ticks = 32'd1_146_600;
        @(posedge clk); #1;
        request(4'd0, 19'h21800, 19'h59600);
        request_address = 19'h59600;
        @(posedge clk); #1;
        $display("pipeline B B=%08h R=%08h H=%08h C=%08h M=%04h",
                 dut.block6_probe_b6_debug, dut.block6_probe_r6_debug,
                 dut.block6_probe_h6_debug, dut.block6_probe_c6_debug,
                 dut.block6_probe_m6_debug);
	        if (dut.pipeline_probe_fault_mapping_subflags_i !== 5'b01000 ||
            !dut.ch01_probe_failure_valid_i ||
            !dut.ch01_probe_failure_type_b_i ||
            dut.ch01_probe_failure_ch_i !== 4'd0 ||
            dut.ch01_probe_failure_mapper_addr_i !== 19'h59600 ||
            dut.ch01_probe_failure_prev_addr_i !== 19'h0c00f ||
            dut.ch01_probe_failure_next_addr_i !== 19'h59600 ||
            !dut.ch01_probe_failure_mapper_valid_i ||
            dut.ch01_probe_failure_in_range_i ||
            dut.ch01_probe_failure_block_i !== 4'd6 ||
            dut.ch01_probe_failure_dest_i !== 21'h59600 ||
            dut.ch01_probe_failure_base_i !== 19'h21800 ||
            dut.ch01_probe_failure_len_i !== 19'h04000 ||
            dut.ch01_probe_failure_index_i !== 19'h21800 ||
            dut.ch01_probe_failure_upper_i !== 19'h20000 ||
            !dut.ch01_probe_failure_inside_b6_i)
            $fatal(1, "out-of-range mapper-failure snapshot mismatch");

        // Re-arm, then return an otherwise valid response with an index that
        // differs by eight. The byte lane still matches, so only FL bit2 may
        // assert. A second mismatch must not overwrite the first snapshot.
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        payload_length = 19'h40000;
        force dut.smoke_loaded_ddr_usable_bytes = 19'h40000;
        @(negedge clk);
        dut.smoke_type80_table_valid_i[6] = 1'b1;
        dut.smoke_type80_table_dest_i[6] = 21'h59600;
        dut.smoke_type80_table_base_i[6] = 19'h21800;
        dut.smoke_type80_table_len_i[6] = 19'h04000;
        request(4'd0, 19'h21800, 19'h59600);
        accept_request(4'd0, 19'h21800);
        return_data(16'h1808, 8'h5a, 4'd0, 3);
        if (dut.pipeline_probe_fault_flags_i !== 8'h04 ||
            dut.pipeline_probe_qd_i !== 16'd0 ||
            dut.pipeline_probe_rd_i !== 16'd0 ||
            dut.pipeline_probe_ad_i !== 16'd0 ||
	            dut.pipeline_probe_hd_i !== 16'd0 ||
	            dut.block6_probe_m6_debug[7:0] !== 8'h04)
            $fatal(1, "owner mismatch flag/snapshot mismatch");
        request(4'd1, 19'h21808, 19'h59608);
        accept_request(4'd1, 19'h21808);
        return_data(16'h1810, 8'h6b, 4'd1, 3);
	        if (dut.pipeline_probe_fault_flags_i !== 8'h04 ||
	            dut.block6_probe_m6_debug[7:0] !== 8'h04)
            $fatal(1, "first fault snapshot was overwritten");

        reset = 1'b1;
        repeat (3) @(posedge clk);
        if (dut.pipeline_probe_fault_flags_i !== 8'd0 ||
            dut.pipeline_probe_backlog_max_i !== 16'd0 ||
            dut.pipeline_probe_fault_snapshot_valid_i ||
            dut.block6_probe_b6_debug !== 32'd0 ||
            dut.block6_probe_r6_debug !== 32'd0 ||
            dut.block6_probe_c6_debug !== 32'd0 ||
            dut.block6_probe_m6_debug !== 16'd0)
            $fatal(1, "reset did not clear pipeline diagnostics");

        reset = 1'b0;
        // Final Take Off legitimately exposes current 0x2000 for two PCM ticks
        // while C0 writes move ch4 between the surrounding ROM descriptors.
        // Seed a non-neutral old hold to reproduce the legacy stale-byte path,
        // then require the ordered synthetic response to replace it with 0x80.
        @(negedge clk);
        dut.smoke_type80_table_valid_i[0] = 1'b1;
        dut.smoke_type80_table_dest_i[0] = 21'h00000;
        dut.smoke_type80_table_base_i[0] = 19'h00000;
        dut.smoke_type80_table_len_i[0] = 19'h00d00;
        dut.smoke_type80_table_valid_i[1] = 1'b1;
        dut.smoke_type80_table_dest_i[1] = 21'h02c00;
        dut.smoke_type80_table_base_i[1] = 19'h00d00;
        dut.smoke_type80_table_len_i[1] = 19'h04300;
        force dut.smoke_type80_table_count_i = 5'd7;
        dut.lab_jt_sample_hold_i[4] = 8'h7a;
        dut.lab_jt_sample_hold_valid_i[4] = 1'b1;
        request(4'd4, 19'h00000, 19'h02000);
        repeat (4) @(posedge clk);
        #1;
        $display("GAP_RESULT rd_req=%b gap=%0d rsp=%0d fifo=%0d owner=%b hold=%02h valid=%b fl=%02h",
                 rd_req, dut.lab_jt_gap_read_count_i,
                 dut.lab_jt_gap_response_count_i, dut.lab_jt_req_fifo_count_i,
                 dut.lab_jt_ddr_owner_valid_i, dut.lab_jt_sample_hold_i[4],
                 dut.lab_jt_sample_hold_valid_i[4],
                 dut.pipeline_probe_fault_flags_i);
        if (rd_req ||
            dut.lab_jt_gap_read_count_i !== 16'd1 ||
	            dut.lab_jt_gap_response_count_i !== 16'd1 ||
	            dut.pipeline_probe_rr_count_i !== 16'd0 ||
	            dut.pipeline_probe_gr_count_i !== 16'd1 ||
	            dut.pipeline_probe_nn_count_i !== 16'd0 ||
            dut.lab_jt_req_fifo_count_i !== 6'd0 ||
            dut.lab_jt_ddr_owner_valid_i ||
            !dut.lab_jt_sample_hold_valid_i[4] ||
            dut.lab_jt_sample_hold_i[4] !== 8'h80 ||
            dut.pipeline_probe_fault_flags_i !== 8'h00)
            $fatal(1, "ch4 0x02000 neutral gap response mismatch");
        $display("GAP_STALE_REPRO ch=4 addr=02000 old_hold=7a synthetic=80 fault=00");
        release dut.smoke_type80_table_count_i;

        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        request(4'd0, 19'h00000, 19'h12345);
        if (dut.pipeline_probe_fault_flags_i !== 8'h20)
            $fatal(1, "failed to create mapper fault before payload clear");
        @(negedge clk);
        payload_clear = 1'b1;
        @(posedge clk); #1;
        payload_clear = 1'b0;
        if (dut.pipeline_probe_fault_flags_i !== 8'd0 ||
            dut.pipeline_probe_backlog_max_i !== 16'd0 ||
            dut.pipeline_probe_fault_snapshot_valid_i ||
            dut.block6_probe_b6_debug !== 32'd0 ||
            dut.block6_probe_r6_debug !== 32'd0 ||
            dut.block6_probe_c6_debug !== 32'd0 ||
            dut.block6_probe_m6_debug !== 16'd0)
            $fatal(1, "loaded_payload_clear did not clear diagnostics");
        $display("PASS tb_segapcm_ddr_request_queue backlog_fault_snapshot");
        $finish;
    end
endmodule
