`timescale 1ns/1ps

// Magical Sound Shower channel-path diagnostic.  foobar's displayed ch2 is
// the second SegaPCM voice, i.e. the zero-origin JT/VGM channel 1 (C0 08/8c).
// It covers the fixed 16-entry table and the disabled-channel setup/current
// writeback ordering using real Magical Sound Shower descriptors and bytes.
module tb_segapcm_magical_ch2_missing;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cmd_valid = 1'b0;
    logic [15:0] cmd_addr = 16'd0;
    logic [7:0] cmd_data = 8'd0;
    logic payload_wr_valid = 1'b0;
    logic [18:0] payload_wr_addr = 19'd0;
    logic [7:0] payload_wr_data = 8'h80;
    logic [31:0] type80_rom_size = 32'd0;
    logic [31:0] type80_rom_dest = 32'd0;
    logic ddr_ready = 1'b1;
    logic ddr_valid = 1'b0;
    logic [7:0] ddr_data = 8'h80;
    logic [15:0] ddr_last_index = 16'd0;
    logic bridge_enable = 1'b0;
    logic response_pending = 1'b0;
    logic [18:0] response_index = 19'd0;
    integer response_delay = 0;
    integer phase = 0;

    wire ddr_req;
    wire [18:0] ddr_addr;
    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire audio_valid;

    integer req_count [0:15];
    integer push_count [0:15];
    integer accept_count [0:15];
    integer response_count [0:15];
    integer hold_count [0:15];
    integer consume_count [0:15];
    integer nonneutral_consume_count [0:15];
    integer mixer_count [0:15];
    integer audio_nonzero_phase [0:4];
    logic [18:0] first_req_addr [0:15];
    logic [23:0] first_req_current [0:15];
    logic [18:0] first_push_index [0:15];
    logic [3:0] first_push_block [0:15];
    logic [3:0] first_accept_block [0:15];
    logic [3:0] first_response_block [0:15];
    logic [3:0] first_hold_block [0:15];
    integer ch1_old_54300_count;
    integer i;

    always #25 clk = ~clk;

    // Real bytes from block 2 at VGM payload file offset 0x191a.  Only the
    // leading bytes are needed to prove the complete nonzero audio path.
    function automatic [7:0] magical_payload_byte(input [18:0] index);
        begin
            case (index)
                // Magical Sound Shower block 8, local payload base 0x0adac.
                19'h0adac: magical_payload_byte = 8'h80;
                19'h0adad: magical_payload_byte = 8'h6b;
                19'h0adae: magical_payload_byte = 8'h5a;
                19'h0adaf: magical_payload_byte = 8'h72;
                19'h0adb0: magical_payload_byte = 8'h8e;
                19'h0adb1: magical_payload_byte = 8'h91;
                19'h0adb2: magical_payload_byte = 8'h87;
                19'h0adb3: magical_payload_byte = 8'h6c;
                19'h0adb4: magical_payload_byte = 8'h82;
                19'h0adb5: magical_payload_byte = 8'hd0;
                19'h0adb6: magical_payload_byte = 8'hab;
                19'h0adb7: magical_payload_byte = 8'h77;
                19'h0adb8: magical_payload_byte = 8'h35;
                19'h0adb9: magical_payload_byte = 8'h4c;
                19'h0adba: magical_payload_byte = 8'h9f;
                19'h0adbb: magical_payload_byte = 8'h9f;
                19'h0186d: magical_payload_byte = 8'h7d;
                19'h0186e: magical_payload_byte = 8'h6b;
                19'h0186f: magical_payload_byte = 8'h70;
                19'h01870: magical_payload_byte = 8'h7b;
                19'h01871: magical_payload_byte = 8'h7c;
                19'h01872: magical_payload_byte = 8'h77;
                19'h01873: magical_payload_byte = 8'h72;
                19'h01874: magical_payload_byte = 8'h79;
                19'h01875: magical_payload_byte = 8'h7c;
                19'h01876: magical_payload_byte = 8'h6c;
                19'h01877: magical_payload_byte = 8'h73;
                19'h01878: magical_payload_byte = 8'h7d;
                19'h01879: magical_payload_byte = 8'h70;
                19'h0187a: magical_payload_byte = 8'h65;
                19'h0187b: magical_payload_byte = 8'h5f;
                19'h0187c: magical_payload_byte = 8'h61;
                // After Burner block 4, local payload base 0x12800.
                19'h12800: magical_payload_byte = 8'h80;
                19'h12801: magical_payload_byte = 8'h80;
                19'h12802: magical_payload_byte = 8'h80;
                19'h12803: magical_payload_byte = 8'h80;
                19'h12804: magical_payload_byte = 8'h81;
                19'h12805: magical_payload_byte = 8'h82;
                19'h12806: magical_payload_byte = 8'h82;
                19'h12807: magical_payload_byte = 8'h82;
                19'h12808: magical_payload_byte = 8'h82;
                19'h12809: magical_payload_byte = 8'h83;
                19'h1280a: magical_payload_byte = 8'h84;
                19'h1280b: magical_payload_byte = 8'h84;
                19'h1280c: magical_payload_byte = 8'h83;
                19'h1280d: magical_payload_byte = 8'h82;
                19'h1280e: magical_payload_byte = 8'h84;
                19'h1280f: magical_payload_byte = 8'h85;
                19'h12810: magical_payload_byte = 8'h84;
                19'h12811: magical_payload_byte = 8'h84;
                19'h12812: magical_payload_byte = 8'h83;
                19'h12813: magical_payload_byte = 8'h84;
                19'h12814: magical_payload_byte = 8'h84;
                19'h12815: magical_payload_byte = 8'h84;
                19'h12816: magical_payload_byte = 8'h83;
                19'h12817: magical_payload_byte = 8'h83;
                19'h12818: magical_payload_byte = 8'h83;
                19'h12819: magical_payload_byte = 8'h82;
                19'h1281a: magical_payload_byte = 8'h83;
                19'h1281b: magical_payload_byte = 8'h82;
                19'h1281c: magical_payload_byte = 8'h80;
                19'h1281d: magical_payload_byte = 8'h7d;
                19'h1281e: magical_payload_byte = 8'h7a;
                19'h1281f: magical_payload_byte = 8'h79;
                default:   magical_payload_byte = 8'h80;
            endcase
        end
    endfunction

    // Four-cycle single-outstanding DDR response model.
    always @(negedge clk) begin
        ddr_valid = 1'b0;
        if (reset) begin
            response_pending = 1'b0;
            response_delay = 0;
            response_index = 19'd0;
            ddr_last_index = 16'd0;
            ddr_data = 8'h80;
        end else if (ddr_req && ddr_ready && !response_pending) begin
            response_pending = 1'b1;
            response_index = ddr_addr;
            response_delay = 4;
        end else if (response_pending && response_delay != 0) begin
            response_delay = response_delay - 1;
            if (response_delay == 1) begin
                ddr_last_index = response_index[15:0];
                ddr_data = magical_payload_byte(response_index);
                ddr_valid = 1'b1;
                response_pending = 1'b0;
            end
        end
    end

    // Per-stage counters use the same channel tag as the production path.
    always @(posedge clk) begin : trace_counters
        integer ch;
        if (!reset) begin
            if (dut.rom_request_event) begin
                ch = dut.lab_jt_req_src_ch;
                req_count[ch] = req_count[ch] + 1;
                if (req_count[ch] == 1) begin
                    first_req_addr[ch] = dut.lab_jt_rom_addr;
                    first_req_current[ch] =
                        dut.lab_jt_pcm_core.dbg_last_cur_addr;
                end
                if (phase == 1 && ch == 1 &&
                    dut.lab_jt_rom_addr == 19'h54300)
                    ch1_old_54300_count = ch1_old_54300_count + 1;
                if (((phase == 1) && (ch == 1)) ||
                    ((phase == 2) && (ch == 3)) ||
                    ((phase == 3) && (ch == 1)) ||
                    ((phase == 4) && (ch == 0))) begin
                if (req_count[ch] <= 10)
                    $display("REQ phase=%0d t=%0t ch=%0d st=%0d addr=%05h current=%06h cfg=%02h table_hit=%b match=%b",
                             phase, $time, ch, dut.lab_jt_req_src_st,
                             dut.lab_jt_rom_addr,
                             dut.lab_jt_pcm_core.cur_addr,
                             dut.lab_jt_pcm_core.cfg_en,
                             dut.lab_jt_payload_table_hit_next,
                             dut.lab_jt_payload_match_valid_next);
                end
            end
            if (dut.lab_jt_ddr_request_queue_push) begin
                ch = dut.lab_jt_req_src_ch;
                push_count[ch] = push_count[ch] + 1;
                if (push_count[ch] == 1) begin
                    first_push_block[ch] = dut.lab_jt_payload_block_next;
                    first_push_index[ch] = dut.lab_jt_payload_read_index_next;
                end
                if (((phase == 1 && ch == 1) ||
                     (phase == 2 && ch == 3) ||
                     (phase == 3 && ch == 1) ||
                     (phase == 4 && ch == 0)) && push_count[ch] <= 2)
                    $display("PUSH phase=%0d t=%0t ch=%0d block=%0d index=%05h",
                             phase, $time, ch, dut.lab_jt_payload_block_next,
                             dut.smoke_ddr_follow_read_index);
            end
            if (dut.lab_jt_ddr_read_request_accept) begin
                ch = dut.lab_jt_ddr_issue_ch_i;
                accept_count[ch] = accept_count[ch] + 1;
                if (accept_count[ch] == 1)
                    first_accept_block[ch] =
                        dut.lab_jt_ddr_req_payload_block_i;
                if (((phase == 1 && ch == 1) ||
                     (phase == 2 && ch == 3) ||
                     (phase == 3 && ch == 1) ||
                     (phase == 4 && ch == 0)) && accept_count[ch] <= 2)
                    $display("ACCEPT phase=%0d t=%0t ch=%0d block=%0d index=%05h owner_pre=%b",
                             phase, $time, ch,
                             dut.lab_jt_ddr_req_payload_block_i,
                             dut.lab_jt_ddr_req_payload_index_i,
                             dut.lab_jt_ddr_owner_valid_i);
            end
            if (dut.lab_jt_ddr_payload_return_event &&
                dut.lab_jt_ddr_owner_valid_i) begin
                ch = dut.lab_jt_ddr_owner_ch_i;
                response_count[ch] = response_count[ch] + 1;
                if (response_count[ch] == 1)
                    first_response_block[ch] = dut.lab_jt_ddr_owner_block_i;
                if (((phase == 1 && ch == 1) ||
                     (phase == 2 && ch == 3) ||
                     (phase == 3 && ch == 1) ||
                     (phase == 4 && ch == 0)) && response_count[ch] <= 2)
                    $display("RESP phase=%0d t=%0t owner_ch=%0d index=%05h data=%02h match=%b",
                             phase, $time, ch, dut.lab_jt_ddr_owner_index_i,
                             ddr_data, dut.lab_jt_ddr_response_matches_current);
            end
            if (dut.lab_jt_ddr_payload_return_event &&
                dut.lab_jt_ddr_return_hold_candidate) begin
                ch = dut.lab_jt_ddr_owner_ch_i;
                hold_count[ch] = hold_count[ch] + 1;
                if (hold_count[ch] == 1)
                    first_hold_block[ch] = dut.lab_jt_ddr_owner_block_i;
            end
            if (dut.segapcm_cen && dut.lab_jt_pcm_core.st == 4'd14) begin
                ch = dut.lab_jt_pcm_core.cur_ch;
                consume_count[ch] = consume_count[ch] + 1;
                if (dut.lab_jt_rom_data_to_core != 8'h80)
                    nonneutral_consume_count[ch] =
                        nonneutral_consume_count[ch] + 1;
                if ((((phase == 1) && (ch == 1)) ||
                     ((phase == 2) && (ch == 3)) ||
                     ((phase == 3) && (ch == 1)) ||
                     ((phase == 4) && (ch == 0))) &&
                    consume_count[ch] <= 2)
                    $display("CONSUME phase=%0d t=%0t ch=%0d hold_valid=%b hold=%02h jt_data=%02h",
                             phase, $time, ch,
                             dut.lab_jt_sample_hold_valid_i[ch],
                             dut.lab_jt_sample_hold_i[ch],
                             dut.lab_jt_rom_data_to_core);
            end
            if (dut.segapcm_cen && dut.lab_jt_pcm_core.st == 4'd15) begin
                ch = dut.lab_jt_pcm_core.cur_ch;
                if (dut.lab_jt_pcm_core.mul_data != 16'sd0)
                    mixer_count[ch] = mixer_count[ch] + 1;
            end
            if (audio_valid && ((audio_l != 16'sd0) || (audio_r != 16'sd0)))
                audio_nonzero_phase[phase] = audio_nonzero_phase[phase] + 1;
        end
    end

    task automatic load_block(input [20:0] dest, input [18:0] len,
                              input [18:0] local_base);
        begin
            @(negedge clk);
            type80_rom_dest = {11'd0, dest};
            type80_rom_size = {13'd0, len} + 32'd8;
            payload_wr_addr = local_base;
            payload_wr_data = 8'h80;
            payload_wr_valid = 1'b1;
            @(negedge clk);
            payload_wr_valid = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    task check_map(input [18:0] rom_addr,
                   input [3:0] block,
                   input [18:0] payload_index);
        begin
            force dut.lab_jt_rom_addr = rom_addr;
            #1;
            if (!dut.lab_jt_payload_match_valid_next ||
                dut.lab_jt_payload_block_next != block ||
                dut.lab_jt_payload_read_index_next != payload_index)
                $fatal(1,
                    "map miss addr=%05h got hit=%b block=%0d index=%05h expected block=%0d index=%05h",
                    rom_addr, dut.lab_jt_payload_match_valid_next,
                    dut.lab_jt_payload_block_next,
                    dut.lab_jt_payload_read_index_next, block, payload_index);
            $display("MAP_HIT block=%0d addr=%05h payload=%05h",
                     block, rom_addr, payload_index);
            release dut.lab_jt_rom_addr;
            #1;
        end
    endtask

    task automatic c0_write(input [15:0] addr, input [7:0] data);
        begin
            @(negedge clk);
            cmd_addr = addr;
            cmd_data = data;
            cmd_valid = 1'b1;
            @(negedge clk);
            cmd_valid = 1'b0;
            repeat (4) @(negedge clk);
        end
    endtask

    task automatic setup_ch1_block8;
        begin
            c0_write(16'h0008, 8'h00);
            c0_write(16'h000a, 8'h20);
            c0_write(16'h000b, 8'h20);
            c0_write(16'h000c, 8'h7c);
            c0_write(16'h008c, 8'h7c);
            c0_write(16'h000d, 8'h43);
            c0_write(16'h008d, 8'h43);
            c0_write(16'h000e, 8'h48);
            c0_write(16'h000f, 8'h84);
            bridge_enable = 1'b1;
            phase = 1;
            c0_write(16'h008e, 8'hd2);
        end
    endtask

    task automatic setup_ch3_block2;
        begin
            c0_write(16'h0018, 8'h00);
            c0_write(16'h001a, 8'h38);
            c0_write(16'h001b, 8'h38);
            c0_write(16'h001c, 8'hab);
            c0_write(16'h009c, 8'hab);
            c0_write(16'h001d, 8'h29);
            c0_write(16'h009d, 8'h29);
            c0_write(16'h001e, 8'h2e);
            c0_write(16'h001f, 8'h84);
            bridge_enable = 1'b1;
            phase = 2;
            c0_write(16'h009e, 8'hc2);
        end
    endtask

    task automatic load_after_burner_blocks;
        begin
            load_block(21'h00000, 19'h06f00, 19'h00000);
            load_block(21'h08000, 19'h04300, 19'h06f00);
            load_block(21'h0c800, 19'h03800, 19'h0b200);
            load_block(21'h28000, 19'h03e00, 19'h0ea00);
            load_block(21'h30000, 19'h08000, 19'h12800);
            load_block(21'h42000, 19'h03400, 19'h1a800);
            load_block(21'h5d600, 19'h02a00, 19'h1dc00);
        end
    endtask

    task automatic setup_ab_ch1_prior;
        begin
            c0_write(16'h0008, 8'h30);
            c0_write(16'h000a, 8'h02);
            c0_write(16'h000b, 8'h30);
            c0_write(16'h000c, 8'h00);
            c0_write(16'h008c, 8'h00);
            c0_write(16'h000d, 8'hd6);
            c0_write(16'h008d, 8'hd6);
            c0_write(16'h000e, 8'hea);
            c0_write(16'h000f, 8'h5a);
            c0_write(16'h008e, 8'h5a);
        end
    endtask

    task automatic trigger_ab_ch1_guitar;
        begin
            c0_write(16'h0008, 8'h18);
            c0_write(16'h000b, 8'h28);
            c0_write(16'h000c, 8'h00);
            c0_write(16'h008c, 8'h00);
            c0_write(16'h000d, 8'h00);
            c0_write(16'h008d, 8'h00);
            c0_write(16'h000e, 8'h3f);
            bridge_enable = 1'b1;
            phase = 3;
            c0_write(16'h008e, 8'h3a);
        end
    endtask

    task automatic setup_ab_ch0_prior;
        begin
            c0_write(16'h0000, 8'h30);
            c0_write(16'h0002, 8'h30);
            c0_write(16'h0003, 8'h02);
            c0_write(16'h0004, 8'h00);
            c0_write(16'h0084, 8'h00);
            c0_write(16'h0005, 8'hd6);
            c0_write(16'h0085, 8'hd6);
            c0_write(16'h0006, 8'hea);
            c0_write(16'h0007, 8'h5b);
            c0_write(16'h0086, 8'h5a);
        end
    endtask

    task automatic trigger_ab_ch0_guitar;
        begin
            c0_write(16'h0000, 8'h18);
            c0_write(16'h0002, 8'h28);
            c0_write(16'h0004, 8'h00);
            c0_write(16'h0084, 8'h00);
            c0_write(16'h0005, 8'h00);
            c0_write(16'h0085, 8'h00);
            c0_write(16'h0006, 8'h3f);
            bridge_enable = 1'b1;
            phase = 4;
            c0_write(16'h0086, 8'h3a);
        end
    endtask

    segapcm_sound_module dut (
        .clk(clk), .reset(reset),
        .segapcm_cmd_valid(cmd_valid), .segapcm_cmd_addr(cmd_addr),
        .segapcm_cmd_data(cmd_data), .segapcm_interface(32'h0000_000c),
        .smoke_variant(3'd0), .smoke_variant_valid(1'b0),
        .smoke_source_loaded(1'b1), .loaded_payload_clear(1'b0),
        .loaded_payload_wr_valid(payload_wr_valid),
        .loaded_payload_wr_addr(payload_wr_addr),
        .loaded_payload_wr_data(payload_wr_data),
        .loaded_payload_present(1'b1), .loaded_payload_length(19'h30000),
        .loaded_payload_block_count(16'd12),
        .smoke_ddr_follow_mode(bridge_enable), .smoke_ddr_follow_offset_sel(3'd0),
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
        .smoke_vgm_wait_ticks(32'd0),
        .loaded_type80_rom_size(type80_rom_size),
        .loaded_type80_rom_dest(type80_rom_dest),
        .loaded_ddr_rd_req(ddr_req), .loaded_ddr_rd_ready(ddr_ready),
        .loaded_ddr_rd_addr(ddr_addr), .loaded_ddr_rd_valid(ddr_valid),
        .loaded_ddr_rd_data(ddr_data), .loaded_ddr_payload_present(1'b1),
        .loaded_ddr_payload_length(19'h30000),
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
        .loaded_ddr_last_read_index_debug(ddr_last_index),
        .loaded_ddr_last_read_addr_debug(16'd0),
        .loaded_ddr_last_read_lane_debug(16'd0),
        .loaded_ddr_last_read_word0_debug(16'd0),
        .loaded_ddr_last_read_word1_debug(16'd0),
        .loaded_ddr_last_read_data_debug(ddr_data),
        .loaded_ddr_base_addr_debug(16'd0),
        .loaded_ddr_probe_write_index_debug(16'd0),
        .loaded_ddr_probe_write_word_debug(16'd0),
        .loaded_ddr_probe_write_lane_debug(16'd0),
        .loaded_ddr_probe_write_addr_debug(16'd0),
        .loaded_ddr_probe_write_count_debug(16'd0),
        .loaded_ddr_probe_write_flags_debug(16'd0),
        .loaded_ddr_probe_write_word0_debug(16'd0),
        .loaded_ddr_probe_write_word6_debug(16'd0),
        .audio_l(audio_l), .audio_r(audio_r),
        .audio_sample_valid(audio_valid)
    );

    initial begin
        for (i = 0; i < 16; i = i + 1) begin
            req_count[i] = 0;
            push_count[i] = 0;
            accept_count[i] = 0;
            response_count[i] = 0;
            hold_count[i] = 0;
            consume_count[i] = 0;
            nonneutral_consume_count[i] = 0;
            mixer_count[i] = 0;
            first_req_addr[i] = 19'd0;
            first_req_current[i] = 24'd0;
            first_push_index[i] = 19'd0;
            first_push_block[i] = 4'd0;
            first_accept_block[i] = 4'd0;
            first_response_block[i] = 4'd0;
            first_hold_block[i] = 4'd0;
        end
        for (i = 0; i < 5; i = i + 1)
            audio_nonzero_phase[i] = 0;
        ch1_old_54300_count = 0;

        repeat (8) @(posedge clk);
        reset = 1'b0;

        // Exact twelve Magical Sound Shower blocks, in parser/copy order.
        load_block(21'h40090, 19'h00b70, 19'h00000);
        load_block(21'h41c03, 19'h00cfd, 19'h00b70);
        load_block(21'h429ab, 19'h00555, 19'h0186d);
        load_block(21'h4302f, 19'h00ad1, 19'h01dc2);
        load_block(21'h43be6, 19'h0441a, 19'h02893);
        load_block(21'h500f0, 19'h00810, 19'h06cad);
        load_block(21'h50951, 19'h00daf, 19'h074bd);
        load_block(21'h517c0, 19'h02b40, 19'h0826c);
        load_block(21'h5437c, 19'h00584, 19'h0adac);
        load_block(21'h549de, 19'h00322, 19'h0b330);
        load_block(21'h54da0, 19'h00a60, 19'h0b652);
        load_block(21'h55830, 19'h007d0, 19'h0c0b2);

        if (dut.smoke_type80_table_count_i != 5'd12)
            $fatal(1, "type80 table did not capture twelve blocks");
        check_map(19'h5437c, 4'd8, 19'h0adac);
        check_map(19'h549de, 4'd9, 19'h0b330);
        check_map(19'h54da0, 4'd10, 19'h0b652);
        check_map(19'h55830, 4'd11, 19'h0c0b2);

        setup_ch1_block8();
        repeat (20000) @(posedge clk);
        $display("CH1_BLOCK8 shadow=%02h/%02h/%02h/%02h JT_RAM=%02h/%02h/%02h ctrl_written=%04h active=%04h cfg=%02h was=%b req=%0d push=%0d accept=%0d resp=%0d hold=%0d consume=%0d nonneutral=%0d mix=%0d audio=%0d",
                 dut.lab_jt_shadow_cur_high_i[1],
                 dut.lab_jt_shadow_cur_mid_i[1],
                 dut.lab_jt_shadow_ctrl_jt_i[1],
                 dut.lab_jt_shadow_vol_l_i[1],
                 dut.lab_jt_pcm_core.u_ram.mem[9'h08c],
                 dut.lab_jt_pcm_core.u_ram.mem[9'h08d],
                 dut.lab_jt_pcm_core.u_ram.mem[9'h08e],
                 dut.lab_jt_pcm_core.c0_control_written_i,
                 dut.lab_jt_pcm_core.active,
                 dut.lab_jt_pcm_core.cfg_en,
                 dut.lab_jt_pcm_core.was_enb,
                 req_count[1], push_count[1], accept_count[1],
                 response_count[1], hold_count[1], consume_count[1],
                 nonneutral_consume_count[1], mixer_count[1],
                 audio_nonzero_phase[1]);
	        $display("CH1_PREFETCH st=%0d ch=%0d armed=%04h invalid=%04h gen=%0d pfvalid=%04h rom=%05h ok=%b",
	                 dut.lab_jt_pcm_core.st, dut.lab_jt_pcm_core.cur_ch,
	                 dut.lab_jt_pcm_core.c0_rom_prefetch_armed_i,
	                 dut.lab_jt_pcm_core.c0_rom_prefetch_cpu_invalid_i,
	                 dut.lab_jt_channel_generation_i[1],
	                 dut.lab_jt_prefetch_valid_i,
	                 dut.lab_jt_rom_addr, dut.lab_jt_rom_ok_to_core);

        // Stop ch1, then replay the exact ch3 block-2 event at 14.402948 s.
        c0_write(16'h008e, 8'hd3);
        phase = 0;
        setup_ch3_block2();
        repeat (10000) @(posedge clk);
        $display("CH3_NORMAL shadow=%02h/%02h/%02h/%02h JT_RAM=%02h/%02h/%02h req=%0d push=%0d accept=%0d resp=%0d hold=%0d consume=%0d nonneutral=%0d mix=%0d audio=%0d",
                 dut.lab_jt_shadow_cur_high_i[3],
                 dut.lab_jt_shadow_cur_mid_i[3],
                 dut.lab_jt_shadow_ctrl_jt_i[3],
                 dut.lab_jt_shadow_vol_l_i[3],
                 dut.lab_jt_pcm_core.u_ram.mem[9'h09c],
                 dut.lab_jt_pcm_core.u_ram.mem[9'h09d],
                 dut.lab_jt_pcm_core.u_ram.mem[9'h09e],
                 req_count[3], push_count[3], accept_count[3],
                 response_count[3], hold_count[3], consume_count[3],
                 nonneutral_consume_count[3], mixer_count[3],
                 audio_nonzero_phase[2]);

        if (first_req_current[1] != 24'h437c00 ||
            first_req_addr[1] != 19'h5437c ||
            first_push_block[1] != 4'd8 ||
            first_push_index[1] != 19'h0adac ||
            first_accept_block[1] != 4'd8 ||
            first_response_block[1] != 4'd8 ||
            first_hold_block[1] != 4'd8 ||
            ch1_old_54300_count != 0)
            $fatal(1,
                "ch1 first path mismatch current=%06h addr=%05h push=%0d index=%05h accept=%0d response=%0d hold=%0d old54300=%0d",
                first_req_current[1], first_req_addr[1],
                first_push_block[1], first_push_index[1],
                first_accept_block[1], first_response_block[1],
                first_hold_block[1], ch1_old_54300_count);
        if (req_count[1] == 0 || push_count[1] == 0 ||
            accept_count[1] == 0 || response_count[1] == 0 ||
            hold_count[1] == 0 || nonneutral_consume_count[1] == 0 ||
            mixer_count[1] == 0 || audio_nonzero_phase[1] == 0)
            $fatal(1, "ch1/block8 did not traverse the complete path");
        if (req_count[3] == 0 || push_count[3] == 0 ||
            accept_count[3] == 0 || response_count[3] == 0 ||
            hold_count[3] == 0 || nonneutral_consume_count[3] == 0 ||
            mixer_count[3] == 0 || audio_nonzero_phase[2] == 0)
            $fatal(1, "ch3/block2 did not traverse the complete path");
        if (dut.lab_jt_req_dropped_count_i != 0 ||
            dut.lab_jt_req_overflow_count_i != 0)
            $fatal(1, "unexpected FIFO drop/overflow");

        // After Burner has only seven blocks, so repeat its first left/right
        // guitar transitions to determine whether it fails at the same map.
        phase = 0;
        bridge_enable = 1'b0;
        reset = 1'b1;
        repeat (8) @(posedge clk);
        reset = 1'b0;
        load_after_burner_blocks();
        setup_ab_ch1_prior();
        repeat (1000) @(posedge clk);
        req_count[1] = 0; push_count[1] = 0; accept_count[1] = 0;
        response_count[1] = 0; hold_count[1] = 0; consume_count[1] = 0;
        nonneutral_consume_count[1] = 0; mixer_count[1] = 0;
        trigger_ab_ch1_guitar();
        repeat (20000) @(posedge clk);
        $display("AB_CH1_GUITAR shadow=%02h/%02h/%02h JT_RAM=%02h/%02h/%02h req=%0d push=%0d accept=%0d resp=%0d hold=%0d consume=%0d nonneutral=%0d mix=%0d audio=%0d",
                 dut.lab_jt_shadow_cur_high_i[1],
                 dut.lab_jt_shadow_cur_mid_i[1],
                 dut.lab_jt_shadow_ctrl_jt_i[1],
                 dut.lab_jt_pcm_core.u_ram.mem[9'h08c],
                 dut.lab_jt_pcm_core.u_ram.mem[9'h08d],
                 dut.lab_jt_pcm_core.u_ram.mem[9'h08e],
                 req_count[1], push_count[1], accept_count[1],
                 response_count[1], hold_count[1], consume_count[1],
                 nonneutral_consume_count[1], mixer_count[1],
                 audio_nonzero_phase[3]);
	        $display("AB_CH1_SYNC ctrl_written=%04h active=%04h st=%0d ch=%0d armed=%04h gen=%0d pfvalid=%04h",
	                 dut.lab_jt_pcm_core.c0_control_written_i,
	                 dut.lab_jt_pcm_core.active,
	                 dut.lab_jt_pcm_core.st, dut.lab_jt_pcm_core.cur_ch,
	                 dut.lab_jt_pcm_core.c0_rom_prefetch_armed_i,
	                 dut.lab_jt_channel_generation_i[1],
	                 dut.lab_jt_prefetch_valid_i);

        phase = 0;
        bridge_enable = 1'b0;
        reset = 1'b1;
        repeat (8) @(posedge clk);
        reset = 1'b0;
        load_after_burner_blocks();
        setup_ab_ch0_prior();
        repeat (1000) @(posedge clk);
        req_count[0] = 0; push_count[0] = 0; accept_count[0] = 0;
        response_count[0] = 0; hold_count[0] = 0; consume_count[0] = 0;
        nonneutral_consume_count[0] = 0; mixer_count[0] = 0;
        trigger_ab_ch0_guitar();
        repeat (20000) @(posedge clk);
        $display("AB_CH0_GUITAR shadow=%02h/%02h/%02h JT_RAM=%02h/%02h/%02h req=%0d push=%0d accept=%0d resp=%0d hold=%0d consume=%0d nonneutral=%0d mix=%0d audio=%0d",
                 dut.lab_jt_shadow_cur_high_i[0],
                 dut.lab_jt_shadow_cur_mid_i[0],
                 dut.lab_jt_shadow_ctrl_jt_i[0],
                 dut.lab_jt_pcm_core.u_ram.mem[9'h084],
                 dut.lab_jt_pcm_core.u_ram.mem[9'h085],
                 dut.lab_jt_pcm_core.u_ram.mem[9'h086],
                 req_count[0], push_count[0], accept_count[0],
                 response_count[0], hold_count[0], consume_count[0],
	                 nonneutral_consume_count[0], mixer_count[0],
	                 audio_nonzero_phase[4]);
	        $display("PIPE_COVERAGE RR=%0d GR=%0d NN=%0d CN=%0d NZ=%0d OM=%0d",
	                 dut.pipeline_probe_rr_count_i,
	                 dut.pipeline_probe_gr_count_i,
	                 dut.pipeline_probe_nn_count_i,
	                 dut.pipeline_probe_cn_count_i,
	                 dut.pipeline_probe_nz_count_i,
	                 dut.pipeline_probe_om_count_i);
	        if (dut.pipeline_probe_cn_count_i == 16'd0 ||
	            dut.pipeline_probe_nz_count_i == 16'd0 ||
	            dut.pipeline_probe_om_count_i == 16'd0)
	            $fatal(1, "consume/output coverage counters did not advance");
	        if (dut.lab_jt_prefetch_stale_consume_count_i != 32'd0 ||
	            dut.lab_jt_prefetch_wrong_channel_count_i != 32'd0 ||
	            dut.lab_jt_prefetch_wrong_address_count_i != 32'd0)
	            $fatal(1,
	                "tagged consume mismatch stale=%0d channel=%0d address=%0d",
	                dut.lab_jt_prefetch_stale_consume_count_i,
	                dut.lab_jt_prefetch_wrong_channel_count_i,
	                dut.lab_jt_prefetch_wrong_address_count_i);

        $display("PASS tb_segapcm_magical_ch2_missing block8_11_map current_seed CPU_priority full_path");
        $finish;
    end
endmodule
