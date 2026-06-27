module tb_vgm_loaded_player_ym2151;
    localparam int ADDR_WIDTH = 8;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic load_done = 1'b0;
    logic load_done_pulse = 1'b0;
    logic vgm_wait_tick = 1'b0;
    logic [ADDR_WIDTH:0] file_size = 9'd128;

    wire mem_rd_req;
    wire [ADDR_WIDTH-1:0] mem_rd_addr;
    logic mem_rd_ready = 1'b1;
    logic mem_rd_valid = 1'b0;
    logic [7:0] mem_rd_data = 8'd0;

    wire busy;
    wire done;
    wire player_error;
    wire ym2151_cmd_valid;
    wire [7:0] ym2151_cmd_reg;
    wire [7:0] ym2151_cmd_data;
    wire [31:0] ym2151_write_count;
    wire [7:0] ym2151_last_reg;
    wire [7:0] ym2151_last_data;
    wire [31:0] unsupported_command_count;
    wire segapcm_cmd_valid;
    wire [15:0] segapcm_cmd_addr;
    wire [7:0] segapcm_cmd_data;
    wire [31:0] segapcm_write_count;
    wire [15:0] segapcm_last_addr;
    wire [7:0] segapcm_last_data;
    wire [31:0] data_block_count;
    wire [7:0] last_data_block_type;
    wire [15:0] last_data_block_size_low;
    wire [31:0] segapcm_rom_block_count;
    wire [31:0] segapcm_last_rom_size;
    wire [31:0] segapcm_last_rom_start;
    wire [31:0] pcm_ram_write_skip_count;
    wire segapcm_rom_scan_busy;
    wire segapcm_rom_scan_done;
    wire segapcm_rom_scan_overflow;
    wire [31:0] segapcm_rom_scan_block_count;
    wire [31:0] segapcm_rom_scan_byte_count;
    wire [31:0] segapcm_rom_scan_checksum32;
    wire [31:0] segapcm_rom_scan_total_size;
    wire [31:0] segapcm_rom_scan_last_start;
    wire segapcm_copy_wr_req;
    logic segapcm_copy_wr_ready = 1'b1;
    wire [18:0] segapcm_copy_wr_addr;
    wire [7:0] segapcm_copy_wr_data;
    wire segapcm_copy_flush_req;
    logic segapcm_copy_flush_done = 1'b0;
    wire [31:0] segapcm_rom_copy_byte_count;
    wire segapcm_rom_copy_overflow;
    wire segapcm_rom_copy_flush_done;

    logic [7:0] mem [0:255];
    logic pending = 1'b0;
    logic [7:0] pending_data = 8'd0;
    integer ym2151_seen = 0;
    integer segapcm_seen = 0;
    integer copy_seen = 0;
    integer flush_delay = 0;
    integer timeout;
    logic playback_before_scan_done = 1'b0;
    logic playback_before_flush_done = 1'b0;
    logic copy_flush_seen = 1'b0;
    logic copy_flush_pending = 1'b0;

    vgm_loaded_player #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .YM2151_MODE (1'b1)
    ) dut (
        .clk                         (clk),
        .reset                       (reset),
        .start                       (1'b0),
        .load_done                   (load_done),
        .load_done_pulse             (load_done_pulse),
        .load_error                  (1'b0),
        .overflow_error              (1'b0),
        .file_size                   (file_size),
        .vgm_wait_tick               (vgm_wait_tick),
        .mem_rd_req                  (mem_rd_req),
        .mem_rd_addr                 (mem_rd_addr),
        .mem_rd_ready                (mem_rd_ready),
        .mem_rd_valid                (mem_rd_valid),
        .mem_rd_data                 (mem_rd_data),
        .segapcm_copy_wr_req         (segapcm_copy_wr_req),
        .segapcm_copy_wr_ready       (segapcm_copy_wr_ready),
        .segapcm_copy_wr_addr        (segapcm_copy_wr_addr),
        .segapcm_copy_wr_data        (segapcm_copy_wr_data),
        .segapcm_copy_flush_req      (segapcm_copy_flush_req),
        .segapcm_copy_flush_done     (segapcm_copy_flush_done),
        .ym_cmd_ready                (1'b1),
        .psg_cmd_ready               (1'b1),
        .ym_cmd_valid                (),
        .ym_cmd_port                 (),
        .ym_cmd_reg                  (),
        .ym_cmd_data                 (),
        .psg_cmd_valid               (),
        .psg_cmd_data                (),
        .ym2151_cmd_ready            (1'b1),
        .ym2151_cmd_valid            (ym2151_cmd_valid),
        .ym2151_cmd_reg              (ym2151_cmd_reg),
        .ym2151_cmd_data             (ym2151_cmd_data),
        .busy                        (busy),
        .done                        (done),
        .header_valid                (),
        .player_error                (player_error),
        .unsupported_opcode          (),
        .unsupported_pc              (),
        .player_error_code           (),
        .error_pc_debug              (),
        .error_cmd_debug             (),
        .state_debug                 (),
        .mem_rd_req_debug            (),
        .mem_rd_ready_debug          (),
        .mem_rd_valid_debug          (),
        .mem_rd_addr_debug           (),
        .data_start_debug            (),
        .current_pc_debug            (),
        .loop_pc_debug               (),
        .loop_valid_debug            (),
        .loop_taken_debug            (),
        .end_command_seen            (),
        .restarted_from_data_start   (),
        .pcm_oob                     (),
        .pcm_oob_count               (),
        .wait_ticks_consumed_debug   (),
        .dac_stream_cmd_count        (),
        .dac_stream_wait_samples_total(),
        .dac_stream_clk_cycles_total (),
        .dac_stream_overhead_cycles_total(),
        .max_dac_stream_cmd_cycles   (),
        .count_wait0_dac_stream_cmd  (),
        .count_wait0_overhead_nonzero(),
        .ym2151_write_count          (ym2151_write_count),
        .ym2151_last_reg             (ym2151_last_reg),
        .ym2151_last_data            (ym2151_last_data),
        .unsupported_command_count   (unsupported_command_count),
        .segapcm_cmd_valid           (segapcm_cmd_valid),
        .segapcm_cmd_addr            (segapcm_cmd_addr),
        .segapcm_cmd_data            (segapcm_cmd_data),
        .segapcm_write_count         (segapcm_write_count),
        .segapcm_last_addr           (segapcm_last_addr),
        .segapcm_last_data           (segapcm_last_data),
        .data_block_count            (data_block_count),
        .last_data_block_type        (last_data_block_type),
        .last_data_block_size_low    (last_data_block_size_low),
        .segapcm_rom_block_count     (segapcm_rom_block_count),
        .segapcm_last_rom_size       (segapcm_last_rom_size),
        .segapcm_last_rom_start      (segapcm_last_rom_start),
        .pcm_ram_write_skip_count    (pcm_ram_write_skip_count),
        .segapcm_rom_scan_busy       (segapcm_rom_scan_busy),
        .segapcm_rom_scan_done       (segapcm_rom_scan_done),
        .segapcm_rom_scan_overflow   (segapcm_rom_scan_overflow),
        .segapcm_rom_scan_block_count(segapcm_rom_scan_block_count),
        .segapcm_rom_scan_byte_count (segapcm_rom_scan_byte_count),
        .segapcm_rom_scan_checksum32 (segapcm_rom_scan_checksum32),
        .segapcm_rom_scan_total_size (segapcm_rom_scan_total_size),
        .segapcm_rom_scan_last_start (segapcm_rom_scan_last_start),
        .segapcm_rom_copy_byte_count (segapcm_rom_copy_byte_count),
        .segapcm_rom_copy_overflow   (segapcm_rom_copy_overflow),
        .segapcm_rom_copy_flush_done (segapcm_rom_copy_flush_done),
        .segapcm_copy_flush_req_debug(),
        .done_pc_debug               (),
        .done_cmd_debug              (),
        .pc_debug                    (),
        .last_cmd_debug              ()
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        vgm_wait_tick <= !vgm_wait_tick;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            pending <= 1'b0;
            pending_data <= 8'd0;
            mem_rd_ready <= 1'b1;
            mem_rd_valid <= 1'b0;
            mem_rd_data <= 8'd0;
        end else begin
            mem_rd_valid <= 1'b0;
            mem_rd_ready <= !pending;
            if (pending) begin
                mem_rd_data <= pending_data;
                mem_rd_valid <= 1'b1;
                pending <= 1'b0;
            end
            if (mem_rd_req && mem_rd_ready) begin
                pending_data <= mem[mem_rd_addr];
                pending <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            ym2151_seen <= 0;
            segapcm_seen <= 0;
            playback_before_scan_done <= 1'b0;
            playback_before_flush_done <= 1'b0;
        end else if (ym2151_cmd_valid) begin
            ym2151_seen <= ym2151_seen + 1;
            if (!segapcm_rom_scan_done) begin
                playback_before_scan_done <= 1'b1;
            end
            if (!copy_flush_seen) begin
                playback_before_flush_done <= 1'b1;
            end
        end else if (segapcm_cmd_valid) begin
            segapcm_seen <= segapcm_seen + 1;
            if (!segapcm_rom_scan_done) begin
                playback_before_scan_done <= 1'b1;
            end
            if (!copy_flush_seen) begin
                playback_before_flush_done <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            segapcm_copy_wr_ready <= 1'b1;
            segapcm_copy_flush_done <= 1'b0;
            copy_seen <= 0;
            flush_delay <= 0;
            copy_flush_seen <= 1'b0;
            copy_flush_pending <= 1'b0;
        end else begin
            segapcm_copy_flush_done <= 1'b0;
            if (segapcm_copy_wr_req && segapcm_copy_wr_ready) begin
                case (copy_seen)
                    0: if ((segapcm_copy_wr_addr != 19'h02000) ||
                           (segapcm_copy_wr_data != 8'haa)) begin
                        $display("FAIL copy0 addr=%05h data=%02h",
                                 segapcm_copy_wr_addr, segapcm_copy_wr_data);
                        $finish;
                    end
                    1: if ((segapcm_copy_wr_addr != 19'h02001) ||
                           (segapcm_copy_wr_data != 8'hbb)) begin
                        $display("FAIL copy1 addr=%05h data=%02h",
                                 segapcm_copy_wr_addr, segapcm_copy_wr_data);
                        $finish;
                    end
                    2: if ((segapcm_copy_wr_addr != 19'h02002) ||
                           (segapcm_copy_wr_data != 8'hcc)) begin
                        $display("FAIL copy2 addr=%05h data=%02h",
                                 segapcm_copy_wr_addr, segapcm_copy_wr_data);
                        $finish;
                    end
                    3: if ((segapcm_copy_wr_addr != 19'h02003) ||
                           (segapcm_copy_wr_data != 8'hdd)) begin
                        $display("FAIL copy3 addr=%05h data=%02h",
                                 segapcm_copy_wr_addr, segapcm_copy_wr_data);
                        $finish;
                    end
                    default: begin
                        $display("FAIL unexpected copy addr=%05h data=%02h",
                                 segapcm_copy_wr_addr, segapcm_copy_wr_data);
                        $finish;
                    end
                endcase
                copy_seen <= copy_seen + 1;
            end

            if (segapcm_copy_flush_req && !copy_flush_pending) begin
                copy_flush_pending <= 1'b1;
                flush_delay <= 0;
            end else if (copy_flush_pending) begin
                if (flush_delay == 2) begin
                    segapcm_copy_flush_done <= 1'b1;
                    copy_flush_seen <= 1'b1;
                    copy_flush_pending <= 1'b0;
                end else begin
                    flush_delay <= flush_delay + 1;
                end
            end
        end
    end

    initial begin
        for (int i = 0; i < 256; i++) mem[i] = 8'h00;
        mem[8'h00] = "V";
        mem[8'h01] = "g";
        mem[8'h02] = "m";
        mem[8'h03] = " ";
        mem[8'h1c] = 8'h24;
        mem[8'h1d] = 8'h00;
        mem[8'h1e] = 8'h00;
        mem[8'h1f] = 8'h00;
        mem[8'h34] = 8'h00;
        mem[8'h35] = 8'h00;
        mem[8'h36] = 8'h00;
        mem[8'h37] = 8'h00;

        mem[8'h40] = 8'h67; mem[8'h41] = 8'h66; mem[8'h42] = 8'h80;
        mem[8'h43] = 8'h0c; mem[8'h44] = 8'h00; mem[8'h45] = 8'h00; mem[8'h46] = 8'h00;
        mem[8'h47] = 8'h00; mem[8'h48] = 8'h00; mem[8'h49] = 8'h08; mem[8'h4a] = 8'h00;
        mem[8'h4b] = 8'h00; mem[8'h4c] = 8'h20; mem[8'h4d] = 8'h00; mem[8'h4e] = 8'h00;
        mem[8'h4f] = 8'haa; mem[8'h50] = 8'hbb; mem[8'h51] = 8'hcc; mem[8'h52] = 8'hdd;
        mem[8'h53] = 8'h54; mem[8'h54] = 8'h20; mem[8'h55] = 8'hc0;
        mem[8'h56] = 8'hc0; mem[8'h57] = 8'h34; mem[8'h58] = 8'h12; mem[8'h59] = 8'h56;
        mem[8'h5a] = 8'h68; mem[8'h5b] = 8'h66; mem[8'h5c] = 8'h80;
        mem[8'h5d] = 8'h00; mem[8'h5e] = 8'h00; mem[8'h5f] = 8'h00;
        mem[8'h60] = 8'h10; mem[8'h61] = 8'h00; mem[8'h62] = 8'h00;
        mem[8'h63] = 8'h04; mem[8'h64] = 8'h00; mem[8'h65] = 8'h00;
        mem[8'h66] = 8'h61; mem[8'h67] = 8'h02; mem[8'h68] = 8'h00;
        mem[8'h69] = 8'h54; mem[8'h6a] = 8'h08; mem[8'h6b] = 8'h78;
        mem[8'h6c] = 8'h66;

        repeat (4) @(posedge clk);
        reset <= 1'b0;
        @(posedge clk);
        load_done <= 1'b1;
        load_done_pulse <= 1'b1;
        @(posedge clk);
        load_done_pulse <= 1'b0;

        timeout = 0;
        while (!dut.loop_taken_debug && !player_error && timeout < 10000) begin
            timeout++;
            @(posedge clk);
        end
        if (player_error) begin
            $display("FAIL ym2151 parser entered error code=%0d pc=%02h cmd=%02h state=%0d",
                     dut.player_error_code,
                     dut.error_pc_debug,
                     dut.error_cmd_debug,
                     dut.state_debug);
            $finish;
        end
        if (!dut.loop_taken_debug || done || !busy) begin
            $display("FAIL ym2151/segapcm parser did not loop busy=%0b done=%0b loop=%0b",
                     busy, done, dut.loop_taken_debug);
            $finish;
        end
        if (ym2151_seen != 2 || ym2151_write_count != 2) begin
            $display("FAIL ym2151 writes seen=%0d count=%0d", ym2151_seen, ym2151_write_count);
            $finish;
        end
        if (!segapcm_rom_scan_done ||
            segapcm_rom_scan_busy ||
            segapcm_rom_scan_overflow ||
            playback_before_scan_done ||
            playback_before_flush_done ||
            !copy_flush_seen ||
            !segapcm_rom_copy_flush_done) begin
            $display("FAIL scan gate done=%0b busy=%0b overflow=%0b early_scan=%0b early_flush=%0b flush_seen=%0b copy_flush_done=%0b",
                     segapcm_rom_scan_done,
                     segapcm_rom_scan_busy,
                     segapcm_rom_scan_overflow,
                     playback_before_scan_done,
                     playback_before_flush_done,
                     copy_flush_seen,
                     segapcm_rom_copy_flush_done);
            $finish;
        end
        if (segapcm_rom_scan_block_count != 1 ||
            segapcm_rom_scan_byte_count != 4 ||
            segapcm_rom_scan_checksum32 != 32'h0000_030e ||
            segapcm_rom_scan_total_size != 32'h0008_0000 ||
            segapcm_rom_scan_last_start != 32'h0000_2000) begin
            $display("FAIL scan blocks=%0d bytes=%0d checksum=%08h total=%08h start=%08h",
                     segapcm_rom_scan_block_count,
                     segapcm_rom_scan_byte_count,
                     segapcm_rom_scan_checksum32,
                     segapcm_rom_scan_total_size,
                     segapcm_rom_scan_last_start);
            $finish;
        end
        if (copy_seen != 4 ||
            segapcm_rom_copy_byte_count != 4 ||
            segapcm_rom_copy_overflow) begin
            $display("FAIL copy seen=%0d count=%0d overflow=%0b",
                     copy_seen,
                     segapcm_rom_copy_byte_count,
                     segapcm_rom_copy_overflow);
            $finish;
        end
        if (ym2151_last_reg != 8'h08 || ym2151_last_data != 8'h78) begin
            $display("FAIL ym2151 last reg=%02h data=%02h", ym2151_last_reg, ym2151_last_data);
            $finish;
        end
        if (segapcm_seen != 1 || segapcm_write_count != 1) begin
            $display("FAIL segapcm writes seen=%0d count=%0d", segapcm_seen, segapcm_write_count);
            $finish;
        end
        if (segapcm_cmd_addr != 16'h1234 || segapcm_cmd_data != 8'h56 ||
            segapcm_last_addr != 16'h1234 || segapcm_last_data != 8'h56) begin
            $display("FAIL segapcm last addr=%04h data=%02h cmd_addr=%04h cmd_data=%02h",
                     segapcm_last_addr, segapcm_last_data,
                     segapcm_cmd_addr, segapcm_cmd_data);
            $finish;
        end
        if (segapcm_rom_block_count != 1 ||
            data_block_count != 1 ||
            last_data_block_type != 8'h80 ||
            last_data_block_size_low != 16'h000c ||
            segapcm_last_rom_size != 32'h0008_0000 ||
            segapcm_last_rom_start != 32'h0000_2000) begin
            $display("FAIL data blocks=%0d last_type=%02h last_size_low=%04h segapcm_rom=%0d size=%08h start=%08h",
                     data_block_count,
                     last_data_block_type,
                     last_data_block_size_low,
                     segapcm_rom_block_count,
                     segapcm_last_rom_size,
                     segapcm_last_rom_start);
            $finish;
        end
        if (pcm_ram_write_skip_count != 1) begin
            $display("FAIL pcm ram write skip count=%0d", pcm_ram_write_skip_count);
            $finish;
        end
        if (unsupported_command_count != 0) begin
            $display("FAIL unsupported skip count=%0d", unsupported_command_count);
            $finish;
        end
        $display("PASS tb_vgm_loaded_player_ym2151");
        $finish;
    end
endmodule
