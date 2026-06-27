`timescale 1ns/1ps

module tb_vgm_loaded_player_segapcm_copy_tail;
    localparam int ADDR_WIDTH = 18;
    localparam int MEM_SIZE = 1 << ADDR_WIDTH;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic load_done = 1'b0;
    logic [ADDR_WIDTH:0] file_size = '0;
    logic vgm_wait_tick = 1'b0;

    wire mem_rd_req;
    wire [ADDR_WIDTH-1:0] mem_rd_addr;
    wire mem_rd_ready;
    logic mem_rd_ready_base = 1'b1;
    logic mem_rd_valid = 1'b0;
    logic [7:0] mem_rd_data = 8'd0;
    logic pending = 1'b0;
    logic [7:0] pending_data = 8'd0;
    logic stall_ninth_payload_read = 1'b0;
    logic stalled_ninth_payload_read = 1'b0;
    logic delay_ninth_payload_valid = 1'b0;
    logic delayed_ninth_payload_valid = 1'b0;
    int pending_delay_cycles = 0;
    logic inject_ninth_payload_loss = 1'b0;
    logic injected_ninth_payload_loss = 1'b0;

    wire segapcm_copy_wr_req;
    logic segapcm_copy_wr_ready = 1'b0;
    wire [18:0] segapcm_copy_wr_addr;
    wire [7:0] segapcm_copy_wr_data;
    wire segapcm_copy_flush_req;
    logic segapcm_copy_flush_done = 1'b0;

    wire busy;
    wire done;
    wire header_valid;
    wire player_error;
    wire segapcm_rom_scan_done;
    wire [31:0] segapcm_rom_scan_byte_count;
    wire [31:0] segapcm_rom_copy_byte_count;
    wire [15:0] scan_remaining_low_debug;
    wire [15:0] scan_copy_last_index_low_debug;
    wire [15:0] scan_copy_req_count_debug;
    wire [15:0] scan_copy_ready_count_debug;
    wire [15:0] scan_copy_read_req_count_debug;
    wire [15:0] scan_copy_read_accept_count_debug;
    wire [15:0] scan_copy_read_valid_count_debug;
    wire [15:0] scan_copy_mem_req_cycle_count_debug;
    wire [15:0] scan_copy_mem_req_ready_cycle_count_debug;
    wire [15:0] scan_copy_request_state_debug;
    wire [15:0] scan_copy_state_lifetime_debug;
    wire [15:0] scan_copy_clear_reason_debug;
    wire [15:0] scan_copy_tail_debug;
    wire [6:0] state_debug;
    wire [15:0] scan_copy_first01_debug;
    wire [15:0] scan_copy_first23_debug;
    wire [15:0] scan_copy_first45_debug;
    wire [15:0] scan_copy_first67_debug;
    wire [15:0] scan_copy_first8_phase_debug;
    wire [15:0] scan_player_accept_count_debug;
    wire [15:0] scan_player_remaining_debug;
    wire [15:0] scan_payload_len_low_debug;
    wire [15:0] scan_payload_af_debug;
    wire scan_remaining_zero_before_expected_accept_debug;
    wire [15:0] final_progress_debug;

    logic [7:0] mem [0:MEM_SIZE-1];
    int copy_accept_count;
    int flush_delay;
    int ready_cycle;
    int timeout;
    logic [15:0] prev_scan_copy_read_req_count_debug = 16'd0;
    logic prev_payload_copy_active = 1'b0;
    int active_payload_len = 0;
    logic payload9_accept_candidate_seen = 1'b0;
    logic payload9_check_rr_advance = 1'b0;
    logic [15:0] payload9_expected_rr = 16'd0;
    logic copy_progress_next_check = 1'b0;

    wire stall_ninth_payload_now =
        stall_ninth_payload_read &&
        !stalled_ninth_payload_read &&
        mem_rd_req &&
        (mem_rd_addr == 18'h00057);
    assign mem_rd_ready = mem_rd_ready_base && !stall_ninth_payload_now;

    vgm_loaded_player #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .YM2151_MODE (1'b1)
    ) dut (
        .clk                         (clk),
        .reset                       (reset),
        .start                       (start),
        .load_done                   (load_done),
        .load_done_pulse             (1'b0),
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
        .state_debug                 (state_debug),
        .mem_rd_req_debug            (),
        .mem_rd_ready_debug          (),
        .mem_rd_valid_debug          (),
        .mem_rd_addr_debug           (),
        .player_core_debug           (),
        .player_lifecycle_debug      (),
        .last_read_byte_debug        (),
        .header_magic_read_debug     (),
        .header_magic_fail_index_debug(),
        .read_request_addr_debug     (),
        .read_response_addr_debug    (),
        .read_pending_debug          (),
        .read_valid_consumed_debug   (),
        .final_state_debug           (),
        .final_pc_debug              (),
        .final_cmd_debug             (),
        .final_error_code_debug      (),
        .final_flags_debug           (),
        .final_reason_debug_out      (),
        .final_progress_debug        (final_progress_debug),
        .first_playback_cmd_after_scan_debug_out(),
        .first_playback_cmds_after_scan_debug(),
        .scan_state_debug            (),
        .scan_pc_debug               (),
        .scan_last_cmd_debug         (),
        .scan_block_type_debug       (),
        .scan_block_size_low_debug   (),
        .scan_remaining_low_debug    (scan_remaining_low_debug),
        .scan_wait_debug             (),
        .scan_abort_reason_debug     (),
        .scan_copy_last_index_low_debug(scan_copy_last_index_low_debug),
        .scan_copy_req_count_debug   (scan_copy_req_count_debug),
        .scan_copy_ready_count_debug (scan_copy_ready_count_debug),
        .scan_copy_read_req_count_debug(scan_copy_read_req_count_debug),
        .scan_copy_read_accept_count_debug(scan_copy_read_accept_count_debug),
        .scan_copy_read_valid_count_debug(scan_copy_read_valid_count_debug),
        .scan_copy_mem_req_cycle_count_debug(scan_copy_mem_req_cycle_count_debug),
        .scan_copy_mem_req_ready_cycle_count_debug(scan_copy_mem_req_ready_cycle_count_debug),
        .scan_copy_request_state_debug(scan_copy_request_state_debug),
        .scan_copy_state_lifetime_debug(scan_copy_state_lifetime_debug),
        .scan_copy_clear_reason_debug(scan_copy_clear_reason_debug),
        .scan_copy_tail_debug        (scan_copy_tail_debug),
        .scan_copy_first01_debug     (scan_copy_first01_debug),
        .scan_copy_first23_debug     (scan_copy_first23_debug),
        .scan_copy_first45_debug     (scan_copy_first45_debug),
        .scan_copy_first67_debug     (scan_copy_first67_debug),
        .scan_copy_first8_phase_debug(scan_copy_first8_phase_debug),
        .scan_player_accept_count_debug(scan_player_accept_count_debug),
        .scan_player_remaining_debug (scan_player_remaining_debug),
        .scan_payload_len_low_debug  (scan_payload_len_low_debug),
        .scan_payload_af_debug       (scan_payload_af_debug),
        .scan_remaining_zero_before_expected_accept_debug(scan_remaining_zero_before_expected_accept_debug),
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
        .ym2151_write_count          (),
        .ym2151_last_reg             (),
        .ym2151_last_data            (),
        .unsupported_command_count   (),
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
        .segapcm_rom_scan_done       (segapcm_rom_scan_done),
        .segapcm_rom_scan_overflow   (),
        .segapcm_rom_scan_block_count(),
        .segapcm_rom_scan_byte_count (segapcm_rom_scan_byte_count),
        .segapcm_rom_scan_checksum32 (),
        .segapcm_rom_scan_total_size (),
        .segapcm_rom_scan_last_start (),
        .segapcm_rom_copy_byte_count (segapcm_rom_copy_byte_count),
        .segapcm_rom_copy_overflow   (),
        .segapcm_rom_copy_flush_done (),
        .segapcm_copy_flush_req_debug(),
        .done_pc_debug               (),
        .done_cmd_debug              (),
        .pc_debug                    (),
        .last_cmd_debug              ()
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && (active_payload_len == 9) &&
            !payload9_accept_candidate_seen &&
            dut.outstanding_payload_read &&
            dut.last_payload_read_addr_valid &&
            (scan_copy_read_req_count_debug == 16'd9) &&
            (scan_copy_read_accept_count_debug == 16'd8) &&
            (dut.scan_payload_read_owner || dut.segapcm_copy_active_i) &&
            dut.read_pending &&
            mem_rd_req &&
            mem_rd_ready &&
            (state_debug != 7'd0)) begin
            payload9_accept_candidate_seen = 1'b1;
            payload9_expected_rr = scan_copy_read_accept_count_debug + 16'd1;
            payload9_check_rr_advance = 1'b1;
            if (!dut.segapcm_copy_active_i) begin
                if (!dut.actual_read_accept_fire || !scan_payload_af_debug[4]) begin
                    $display("FAIL payload=9 diag req/ready/pending but accept did not fire AF=%04h state=%02h RQ=%04h RR=%04h",
                             scan_payload_af_debug,
                             state_debug,
                             scan_copy_read_req_count_debug,
                             scan_copy_read_accept_count_debug);
                    $finish;
                end
                if (!scan_payload_af_debug[5]) begin
                    $display("FAIL payload=9 accept fired without RR increment pulse AF=%04h RQ=%04h RR=%04h",
                             scan_payload_af_debug,
                             scan_copy_read_req_count_debug,
                             scan_copy_read_accept_count_debug);
                    $finish;
                end
            end
        end

        #1;
        if (payload9_check_rr_advance) begin
            payload9_check_rr_advance = 1'b0;
            if (scan_copy_read_accept_count_debug < payload9_expected_rr) begin
                $display("FAIL payload=9 accept fired but RR did not advance AF=%04h expected_RR=%04h RR=%04h RQ=%04h",
                         scan_payload_af_debug,
                         payload9_expected_rr,
                         scan_copy_read_accept_count_debug,
                         scan_copy_read_req_count_debug);
                $finish;
            end
        end
        if (reset) begin
            prev_scan_copy_read_req_count_debug = 16'd0;
            prev_payload_copy_active = 1'b0;
            copy_progress_next_check = 1'b0;
        end else begin
            if (copy_progress_next_check) begin
                copy_progress_next_check = 1'b0;
                if ((state_debug == 7'd0) || (!busy && !done)) begin
                    $display("FAIL copy progress fell idle next cycle state=%02h busy=%0b done=%0b rem=%0d PA=%04h CA=%04h RQ=%04h RR=%04h RV=%04h",
                             state_debug,
                             busy,
                             done,
                             dut.scan_payload_remaining,
                             scan_player_accept_count_debug,
                             scan_copy_ready_count_debug,
                             scan_copy_read_req_count_debug,
                             scan_copy_read_accept_count_debug,
                             scan_copy_read_valid_count_debug);
                    $finish;
                end
            end
            if ((dut.copy_pa_increment_debug_i ||
                 dut.copy_ca_increment_debug_i ||
                 dut.copy_accept_fire) &&
                dut.scan_copy_enabled &&
                (dut.scan_current_payload_len_debug != 32'd0) &&
                (dut.scan_payload_remaining != 32'd0)) begin
                if ((state_debug == 7'd0) || (!busy && !done)) begin
                    $display("FAIL copy progress fell idle same cycle state=%02h busy=%0b done=%0b rem=%0d PA=%04h CA=%04h RQ=%04h RR=%04h RV=%04h",
                             state_debug,
                             busy,
                             done,
                             dut.scan_payload_remaining,
                             scan_player_accept_count_debug,
                             scan_copy_ready_count_debug,
                             scan_copy_read_req_count_debug,
                             scan_copy_read_accept_count_debug,
                             scan_copy_read_valid_count_debug);
                    $finish;
                end
                copy_progress_next_check = 1'b1;
            end
            if (prev_payload_copy_active &&
                (scan_copy_read_req_count_debug >
                 prev_scan_copy_read_req_count_debug) &&
                !dut.outstanding_payload_read) begin
                $display("FAIL RQ increment without outstanding next-cycle RQ=%04h prev=%04h RR=%04h SR=%04h",
                         scan_copy_read_req_count_debug,
                         prev_scan_copy_read_req_count_debug,
                         scan_copy_read_accept_count_debug,
                         scan_copy_clear_reason_debug);
                $finish;
            end
            if ((scan_copy_read_req_count_debug >
                 scan_copy_read_accept_count_debug) &&
                !dut.outstanding_payload_read) begin
                $display("FAIL outstanding cleared while RQ>RR RQ=%04h RR=%04h SR=%04h",
                         scan_copy_read_req_count_debug,
                         scan_copy_read_accept_count_debug,
                         scan_copy_clear_reason_debug);
                $finish;
            end
            prev_scan_copy_read_req_count_debug =
                scan_copy_read_req_count_debug;
            prev_payload_copy_active =
                dut.scan_copy_enabled &&
                (dut.scan_current_payload_len_debug != 32'd0) &&
                !segapcm_rom_scan_done &&
                !player_error;
        end
    end

    always @(posedge clk) begin
        if (!reset && !player_error &&
            (scan_copy_read_req_count_debug >
             scan_copy_read_accept_count_debug) &&
            (state_debug == 7'd0)) begin
            $display("FAIL payload read gap entered ST_IDLE RQ=%04h RR=%04h clear=%04h XR=%04h",
                     scan_copy_read_req_count_debug,
                     scan_copy_read_accept_count_debug,
                     scan_copy_clear_reason_debug,
                     scan_copy_request_state_debug);
            $finish;
        end
    end

    always_ff @(posedge clk) begin
        vgm_wait_tick <= !vgm_wait_tick;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            pending <= 1'b0;
            pending_data <= 8'd0;
            mem_rd_ready_base <= 1'b1;
            mem_rd_valid <= 1'b0;
            mem_rd_data <= 8'd0;
            stalled_ninth_payload_read <= 1'b0;
            delayed_ninth_payload_valid <= 1'b0;
            pending_delay_cycles <= 0;
        end else begin
            mem_rd_valid <= 1'b0;
            mem_rd_ready_base <= !pending;
            if (stall_ninth_payload_now) begin
                stalled_ninth_payload_read <= 1'b1;
            end
            if (pending) begin
                if (pending_delay_cycles > 0) begin
                    pending_delay_cycles <= pending_delay_cycles - 1;
                end else begin
                    mem_rd_data <= pending_data;
                    mem_rd_valid <= 1'b1;
                    pending <= 1'b0;
                end
            end
            if (mem_rd_req && mem_rd_ready) begin
                pending_data <= mem[mem_rd_addr];
                pending <= 1'b1;
                if (delay_ninth_payload_valid &&
                    !delayed_ninth_payload_valid &&
                    (mem_rd_addr == 18'h00057)) begin
                    pending_delay_cycles <= 5;
                    delayed_ninth_payload_valid <= 1'b1;
                end else begin
                    pending_delay_cycles <= 0;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            segapcm_copy_wr_ready <= 1'b0;
            segapcm_copy_flush_done <= 1'b0;
            copy_accept_count <= 0;
            flush_delay <= 0;
            ready_cycle <= 0;
        end else begin
            ready_cycle <= ready_cycle + 1;
            segapcm_copy_wr_ready <= segapcm_copy_wr_req &&
                                     ((ready_cycle % 3) != 1);
            if (segapcm_copy_wr_req && segapcm_copy_wr_ready) begin
                copy_accept_count <= copy_accept_count + 1;
            end

            segapcm_copy_flush_done <= 1'b0;
            if (segapcm_copy_flush_req) begin
                if (flush_delay >= 3) begin
                    segapcm_copy_flush_done <= 1'b1;
                    flush_delay <= 0;
                end else begin
                    flush_delay <= flush_delay + 1;
                end
            end else begin
                flush_delay <= 0;
            end
        end
    end

    task automatic put32(input int addr, input logic [31:0] value);
        begin
            mem[addr + 0] = value[7:0];
            mem[addr + 1] = value[15:8];
            mem[addr + 2] = value[23:16];
            mem[addr + 3] = value[31:24];
        end
    endtask

    task automatic build_vgm(input int payload_len);
        int i;
        int block_size;
        int next_pc;
        begin
            for (i = 0; i < MEM_SIZE; i++) begin
                mem[i] = 8'h00;
            end
            mem[0] = "V";
            mem[1] = "g";
            mem[2] = "m";
            mem[3] = " ";
            put32(32'h34, 32'd0);

            block_size = payload_len + 8;
            mem[32'h40] = 8'h67;
            mem[32'h41] = 8'h66;
            mem[32'h42] = 8'h80;
            put32(32'h43, block_size[31:0]);
            put32(32'h47, 32'h0008_0000);
            put32(32'h4b, 32'h0003_2600);
            for (i = 0; i < payload_len; i++) begin
                mem[32'h4f + i] = i[7:0] ^ 8'ha5;
            end
            next_pc = 32'h4f + payload_len;
            mem[next_pc + 0] = 8'h54;
            mem[next_pc + 1] = 8'h12;
            mem[next_pc + 2] = 8'h34;
            mem[next_pc + 3] = 8'h66;
            file_size = next_pc + 4;
        end
    endtask

    task automatic run_case(input int payload_len);
        begin
            build_vgm(payload_len);
            active_payload_len = payload_len;
            payload9_accept_candidate_seen = 1'b0;
            payload9_check_rr_advance = 1'b0;
            payload9_expected_rr = 16'd0;
            reset <= 1'b1;
            start <= 1'b0;
            load_done <= 1'b0;
            stall_ninth_payload_read <= (payload_len == 10);
            stalled_ninth_payload_read <= 1'b0;
            delay_ninth_payload_valid <= (payload_len == 11);
            delayed_ninth_payload_valid <= 1'b0;
            pending_delay_cycles <= 0;
            inject_ninth_payload_loss <= 1'b0;
            injected_ninth_payload_loss <= 1'b0;
            repeat (6) @(posedge clk);
            reset <= 1'b0;
            load_done <= 1'b1;
            start <= 1'b1;

            timeout = 0;
            while (!segapcm_rom_scan_done && !player_error && timeout < 2_000_000) begin
                if (inject_ninth_payload_loss &&
                    !injected_ninth_payload_loss &&
                    (scan_copy_read_req_count_debug == 16'd9) &&
                    (scan_copy_read_accept_count_debug == 16'd8) &&
                    (state_debug == 7'd1)) begin
                    injected_ninth_payload_loss <= 1'b1;
                    force dut.read_pending = 1'b0;
                    force dut.mem_rd_req = 1'b0;
                    force dut.scan_payload_read_owner = 1'b0;
                    force dut.scan_copy_req_armed = 1'b0;
                    @(posedge clk);
                    release dut.read_pending;
                    release dut.mem_rd_req;
                    release dut.scan_payload_read_owner;
                    release dut.scan_copy_req_armed;
                end
                if ((scan_copy_read_req_count_debug >
                     scan_copy_read_accept_count_debug) &&
                    (state_debug == 0)) begin
                    $display("FAIL payload=%0d returned IDLE before read accept RQ=%04h RR=%04h state_life=%04h clear=%04h XR=%04h",
                             payload_len,
                             scan_copy_read_req_count_debug,
                             scan_copy_read_accept_count_debug,
                             scan_copy_state_lifetime_debug,
                             scan_copy_clear_reason_debug,
                             scan_copy_request_state_debug);
                    $finish;
                end
                timeout++;
                @(posedge clk);
            end
            if (!segapcm_rom_scan_done || player_error) begin
                $display("FAIL payload=%0d scan_done=%0b error=%0b rem=%04h tail=%04h req=%04h ready=%04h idx=%04h",
                         payload_len, segapcm_rom_scan_done, player_error,
                         scan_remaining_low_debug, scan_copy_tail_debug,
                         scan_copy_req_count_debug,
                         scan_copy_ready_count_debug,
                         scan_copy_last_index_low_debug);
                $finish;
            end
            if (segapcm_rom_scan_byte_count != payload_len[31:0] ||
                segapcm_rom_copy_byte_count != payload_len[31:0]) begin
                $display("FAIL payload=%0d scan_bytes=%0d copy_bytes=%0d",
                         payload_len, segapcm_rom_scan_byte_count,
                         segapcm_rom_copy_byte_count);
                $finish;
            end
            if ((scan_player_remaining_debug == 16'd0) &&
                (scan_player_accept_count_debug != payload_len[15:0])) begin
                $display("FAIL payload=%0d player PA=%04h PR=%04h",
                         payload_len, scan_player_accept_count_debug,
                         scan_player_remaining_debug);
                $finish;
            end
            if (scan_payload_len_low_debug != payload_len[15:0]) begin
                $display("FAIL payload=%0d PL=%04h",
                         payload_len, scan_payload_len_low_debug);
                $finish;
            end
            if (scan_player_accept_count_debug != payload_len[15:0] ||
                scan_player_remaining_debug != 16'd0) begin
                $display("FAIL payload=%0d final PA=%04h PR=%04h PL=%04h",
                         payload_len, scan_player_accept_count_debug,
                         scan_player_remaining_debug,
                         scan_payload_len_low_debug);
                $finish;
            end
            if (scan_remaining_zero_before_expected_accept_debug) begin
                $display("FAIL payload=%0d zero-before-expected flag set",
                         payload_len);
                $finish;
            end
            if (payload_len != 0 &&
                scan_copy_last_index_low_debug != ((payload_len - 1) & 16'hffff)) begin
                $display("FAIL payload=%0d last_index=%04h",
                         payload_len, scan_copy_last_index_low_debug);
                $finish;
            end
            if (payload_len != 0 && !scan_copy_tail_debug[1]) begin
                $display("FAIL payload=%0d final byte not marked tail=%04h",
                         payload_len, scan_copy_tail_debug);
                $finish;
            end
            if (scan_copy_mem_req_ready_cycle_count_debug >
                scan_copy_mem_req_cycle_count_debug) begin
                $display("FAIL payload=%0d MA exceeded MR MR=%04h MA=%04h XR=%04h",
                         payload_len,
                         scan_copy_mem_req_cycle_count_debug,
                         scan_copy_mem_req_ready_cycle_count_debug,
                         scan_copy_request_state_debug);
                $finish;
            end
            if (payload_len >= 9) begin
                if (inject_ninth_payload_loss &&
                    !injected_ninth_payload_loss) begin
                    $display("FAIL payload=%0d did not inject byte9 pending/req loss RQ=%04h RR=%04h state=%02h",
                             payload_len,
                             scan_copy_read_req_count_debug,
                             scan_copy_read_accept_count_debug,
                             state_debug);
                    $finish;
                end
                if ((payload_len == 9) && !payload9_accept_candidate_seen) begin
                    $display("FAIL payload=9 did not observe OH=D0FE-style accept candidate RQ=%04h RR=%04h AF=%04h state=%02h",
                             scan_copy_read_req_count_debug,
                             scan_copy_read_accept_count_debug,
                             scan_payload_af_debug,
                             state_debug);
                    $finish;
                end
                if ((payload_len == 11) && !delayed_ninth_payload_valid) begin
                    $display("FAIL payload=11 did not delay byte9 valid response RQ=%04h RR=%04h RV=%04h",
                             scan_copy_read_req_count_debug,
                             scan_copy_read_accept_count_debug,
                             scan_copy_read_valid_count_debug);
                    $finish;
                end
                if (scan_copy_read_req_count_debug < 16'd9 ||
                    scan_copy_read_accept_count_debug < 16'd9 ||
                    scan_copy_read_valid_count_debug < 16'd9 ||
                    scan_copy_mem_req_cycle_count_debug < 16'd9 ||
                    scan_copy_mem_req_ready_cycle_count_debug < 16'd9) begin
                    $display("FAIL payload=%0d byte9 read did not complete RQ=%04h RR=%04h RV=%04h MR=%04h MA=%04h XR=%04h",
                             payload_len,
                             scan_copy_read_req_count_debug,
                             scan_copy_read_accept_count_debug,
                             scan_copy_read_valid_count_debug,
                             scan_copy_mem_req_cycle_count_debug,
                             scan_copy_mem_req_ready_cycle_count_debug,
                             scan_copy_request_state_debug);
                    $finish;
                end
                if (scan_copy_first01_debug != 16'ha4a5 ||
                    scan_copy_first23_debug != 16'ha6a7 ||
                    scan_copy_first45_debug != 16'ha0a1 ||
                    scan_copy_first67_debug != 16'ha2a3 ||
                    scan_copy_first8_phase_debug != 16'h04ad) begin
                    $display("FAIL payload=%0d copied metadata/header bytes? F0=%04h F1=%04h F2=%04h F3=%04h F4=%04h",
                             payload_len,
                             scan_copy_first01_debug,
                             scan_copy_first23_debug,
                             scan_copy_first45_debug,
                             scan_copy_first67_debug,
                             scan_copy_first8_phase_debug);
                    $finish;
                end
            end
            if (!final_progress_debug[3] || !final_progress_debug[4]) begin
                $display("FAIL payload=%0d no flush/playback progress=%04h",
                         payload_len, final_progress_debug);
                $finish;
            end
            @(posedge clk);
            start <= 1'b0;
            load_done <= 1'b0;
        end
    endtask

    initial begin
        run_case(0);
        run_case(1);
        run_case(2);
        run_case(7);
        run_case(8);
        run_case(9);
        run_case(10);
        run_case(11);
        run_case(32);
        run_case(32'h5a00);
        $display("PASS tb_vgm_loaded_player_segapcm_copy_tail");
        $finish;
    end
endmodule
