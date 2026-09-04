module tb_vgm_loaded_player_ym2151_file;
    localparam int ADDR_WIDTH = 12;
    localparam int FILE_BYTES = 179;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic load_done = 1'b0;
    logic load_done_pulse = 1'b0;
    logic vgm_wait_tick = 1'b0;
    logic [ADDR_WIDTH:0] file_size = FILE_BYTES;

    wire mem_rd_req;
    wire [ADDR_WIDTH-1:0] mem_rd_addr;
    logic mem_rd_ready = 1'b1;
    logic mem_rd_valid = 1'b0;
    logic [7:0] mem_rd_data = 8'd0;

    wire busy;
    wire done;
    wire player_error;
    wire header_valid;
    wire loop_taken_debug;
    wire end_command_seen;
    wire [31:0] ym2151_write_count;
    wire [7:0] ym2151_last_reg;
    wire [7:0] ym2151_last_data;
    wire [31:0] unsupported_command_count;

    logic [7:0] mem [0:(1 << ADDR_WIDTH)-1];
    logic pending = 1'b0;
    logic [7:0] pending_data = 8'd0;
    string memh_path;
    integer timeout;
    logic [31:0] writes_at_loop;

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
        .halt_at_loop_boundary       (1'b0),
        .mem_rd_req                  (mem_rd_req),
        .mem_rd_addr                 (mem_rd_addr),
        .mem_rd_ready                (mem_rd_ready),
        .mem_rd_valid                (mem_rd_valid),
        .mem_rd_data                 (mem_rd_data),
        .segapcm_copy_wr_req         (),
        .segapcm_copy_wr_ready       (1'b1),
        .segapcm_copy_wr_addr        (),
        .segapcm_copy_wr_data        (),
        .segapcm_copy_flush_req      (),
        .segapcm_copy_flush_done     (1'b1),
        .ym_cmd_ready                (1'b1),
        .psg_cmd_ready               (1'b1),
        .ym_cmd_valid                (),
        .ym_cmd_port                 (),
        .ym_cmd_reg                  (),
        .ym_cmd_data                 (),
        .psg_cmd_valid               (),
        .psg_cmd_data                (),
        .ym2151_cmd_ready            (1'b1),
        .ym2151_cmd_valid            (),
        .ym2151_cmd_reg              (),
        .ym2151_cmd_data             (),
        .busy                        (busy),
        .done                        (done),
        .header_valid                (header_valid),
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
        .loop_taken_debug            (loop_taken_debug),
        .end_command_seen            (end_command_seen),
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
        .segapcm_cmd_valid           (),
        .segapcm_cmd_addr            (),
        .segapcm_cmd_data            (),
        .segapcm_write_count         (),
        .segapcm_last_addr           (),
        .segapcm_last_data           (),
        .data_block_count            (),
        .last_data_block_type        (),
        .last_data_block_size_low    (),
        .segapcm_rom_block_count     (),
        .segapcm_last_rom_size       (),
        .segapcm_last_rom_start      (),
        .pcm_ram_write_skip_count    (),
        .segapcm_rom_scan_busy       (),
        .segapcm_rom_scan_done       (),
        .segapcm_rom_scan_overflow   (),
        .segapcm_rom_scan_block_count(),
        .segapcm_rom_scan_byte_count (),
        .segapcm_rom_scan_checksum32 (),
        .segapcm_rom_scan_total_size (),
        .segapcm_rom_scan_last_start (),
        .segapcm_rom_copy_byte_count (),
        .segapcm_rom_copy_overflow   (),
        .segapcm_rom_copy_flush_done (),
        .segapcm_copy_flush_req_debug(),
        .done_pc_debug               (),
        .done_cmd_debug              (),
        .pc_debug                    (),
        .last_cmd_debug              ()
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (reset) begin
            vgm_wait_tick <= 1'b0;
        end else begin
            vgm_wait_tick <= !vgm_wait_tick;
        end
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

    initial begin
        for (int i = 0; i < (1 << ADDR_WIDTH); i++) mem[i] = 8'h00;
        if (!$value$plusargs("memh=%s", memh_path)) begin
            memh_path = "/tmp/YM2151_SMOKE.memh";
        end
        $readmemh(memh_path, mem, 0, FILE_BYTES - 1);

        repeat (4) @(posedge clk);
        reset <= 1'b0;
        @(posedge clk);
        load_done <= 1'b1;
        load_done_pulse <= 1'b1;
        @(posedge clk);
        load_done_pulse <= 1'b0;

        timeout = 0;
        while (!header_valid && !player_error && timeout < 1000) begin
            timeout++;
            @(posedge clk);
        end
        if (!header_valid || player_error) begin
            $display("FAIL generated YM2151 VGM did not enter playback header_valid=%0b error=%0b",
                     header_valid, player_error);
            $finish;
        end

        timeout = 0;
        while ((ym2151_write_count < 4) && !player_error && timeout < 5000) begin
            timeout++;
            @(posedge clk);
        end
        if (ym2151_write_count < 4 || player_error) begin
            $display("FAIL generated YM2151 VGM writes=%0d error=%0b",
                     ym2151_write_count, player_error);
            $finish;
        end

        timeout = 0;
        while (!loop_taken_debug && !player_error && timeout < 300000) begin
            timeout++;
            @(posedge clk);
        end
        if (!loop_taken_debug || player_error || done || !busy) begin
            $display("FAIL generated YM2151 VGM loop/end busy=%0b done=%0b loop=%0b error=%0b",
                     busy, done, loop_taken_debug, player_error);
            $finish;
        end
        if (!end_command_seen || unsupported_command_count != 0) begin
            $display("FAIL generated YM2151 VGM end=%0b unsupported=%0d",
                     end_command_seen, unsupported_command_count);
            $finish;
        end
        if (ym2151_last_reg != 8'h08 || ym2151_last_data != 8'h00) begin
            $display("FAIL generated YM2151 VGM last reg=%02h data=%02h",
                     ym2151_last_reg, ym2151_last_data);
            $finish;
        end

        writes_at_loop = ym2151_write_count;
        timeout = 0;
        while ((ym2151_write_count == writes_at_loop) &&
               !player_error && timeout < 1000) begin
            timeout++;
            @(posedge clk);
        end
        if (ym2151_write_count == writes_at_loop || player_error || done || !busy) begin
            $display("FAIL generated YM2151 VGM did not write after loop writes=%0d error=%0b done=%0b busy=%0b",
                     ym2151_write_count, player_error, done, busy);
            $finish;
        end

        $display("PASS tb_vgm_loaded_player_ym2151_file writes=%0d",
                 ym2151_write_count);
        $finish;
    end
endmodule
