`timescale 1ns/1ps

module tb_vgm_loaded_player;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic load_done = 1'b0;
    logic load_done_pulse = 1'b0;
    logic load_error = 1'b0;
    logic overflow_error = 1'b0;
    logic [8:0] file_size = 9'd0;
    logic vgm_wait_tick = 1'b0;
    wire mem_rd_req;
    wire [7:0] mem_rd_addr;
    logic mem_rd_ready = 1'b1;
    logic mem_rd_valid = 1'b0;
    logic [7:0] mem_rd_data = 8'd0;
    logic ym_cmd_ready = 1'b1;
    logic psg_cmd_ready = 1'b1;
    wire ym_cmd_valid;
    wire ym_cmd_port;
    wire [7:0] ym_cmd_reg;
    wire [7:0] ym_cmd_data;
    wire psg_cmd_valid;
    wire [7:0] psg_cmd_data;
    wire busy;
    wire done;
    wire header_valid;
    wire [31:0] segapcm_interface;
    wire player_error;
    wire [7:0] unsupported_opcode;
    wire [7:0] unsupported_pc;
    wire [7:0] player_error_code;
    wire [7:0] error_pc_debug;
    wire [7:0] error_cmd_debug;
    wire [6:0] state_debug;
    wire [7:0] data_start_debug;
    wire [7:0] current_pc_debug;
    wire [7:0] loop_pc_debug;
    wire loop_valid_debug;
    wire loop_taken_debug;
    wire end_command_seen;
    wire restarted_from_data_start;
    wire pcm_oob;
    wire [31:0] pcm_oob_count;
    wire [31:0] wait_ticks_consumed_debug;
    wire [9:0] pc_debug;
    wire [7:0] last_cmd_debug;

    logic [7:0] mem [0:255];
    logic mem_rd_pending = 1'b0;
    logic [7:0] mem_rd_pending_data = 8'd0;
    integer ym_count = 0;
    integer psg_count = 0;
    integer dac_count = 0;
    logic [7:0] dac_data0 = 8'h00;
    logic [7:0] dac_data1 = 8'h00;

    vgm_loaded_player #(
        .ADDR_WIDTH (8)
    ) dut (
        .clk                 (clk),
        .reset               (reset),
        .start               (start),
        .load_done           (load_done),
        .load_done_pulse     (load_done_pulse),
        .load_error          (load_error),
        .overflow_error      (overflow_error),
        .file_size           (file_size),
        .vgm_wait_tick       (vgm_wait_tick),
        .mem_rd_req          (mem_rd_req),
        .mem_rd_addr         (mem_rd_addr),
        .mem_rd_ready        (mem_rd_ready),
        .mem_rd_valid        (mem_rd_valid),
        .mem_rd_data         (mem_rd_data),
        .segapcm_copy_wr_req (),
        .segapcm_copy_wr_ready(1'b1),
        .segapcm_copy_wr_addr(),
        .segapcm_copy_wr_data(),
        .segapcm_copy_flush_req(),
        .segapcm_copy_flush_done(1'b1),
        .ym_cmd_ready        (ym_cmd_ready),
        .psg_cmd_ready       (psg_cmd_ready),
        .ym_cmd_valid        (ym_cmd_valid),
        .ym_cmd_port         (ym_cmd_port),
        .ym_cmd_reg          (ym_cmd_reg),
        .ym_cmd_data         (ym_cmd_data),
        .psg_cmd_valid       (psg_cmd_valid),
        .psg_cmd_data        (psg_cmd_data),
        .ym2151_cmd_ready    (1'b1),
        .ym2151_cmd_valid    (),
        .ym2151_cmd_reg      (),
        .ym2151_cmd_data     (),
        .busy                (busy),
        .done                (done),
        .header_valid        (header_valid),
        .segapcm_interface   (segapcm_interface),
        .player_error        (player_error),
        .unsupported_opcode  (unsupported_opcode),
        .unsupported_pc      (unsupported_pc),
        .player_error_code   (player_error_code),
        .error_pc_debug      (error_pc_debug),
        .error_cmd_debug     (error_cmd_debug),
        .state_debug         (state_debug),
        .mem_rd_req_debug    (),
        .mem_rd_ready_debug  (),
        .mem_rd_valid_debug  (),
        .mem_rd_addr_debug   (),
        .data_start_debug    (data_start_debug),
        .current_pc_debug    (current_pc_debug),
        .loop_pc_debug       (loop_pc_debug),
        .loop_valid_debug    (loop_valid_debug),
        .loop_taken_debug    (loop_taken_debug),
        .end_command_seen    (end_command_seen),
        .restarted_from_data_start(restarted_from_data_start),
        .pcm_oob             (pcm_oob),
        .pcm_oob_count       (pcm_oob_count),
        .wait_ticks_consumed_debug(wait_ticks_consumed_debug),
        .done_pc_debug       (),
        .done_cmd_debug      (),
        .pc_debug            (pc_debug),
        .last_cmd_debug      (last_cmd_debug)
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (reset) begin
            mem_rd_pending <= 1'b0;
            mem_rd_ready <= 1'b1;
            mem_rd_valid <= 1'b0;
            mem_rd_data <= 8'd0;
        end else begin
            mem_rd_valid <= 1'b0;
            mem_rd_ready <= !mem_rd_pending;
            if (mem_rd_pending) begin
                mem_rd_data <= mem_rd_pending_data;
                mem_rd_valid <= 1'b1;
                mem_rd_pending <= 1'b0;
            end
            if (mem_rd_req && !mem_rd_pending) begin
                mem_rd_pending_data <= mem[mem_rd_addr];
                mem_rd_pending <= 1'b1;
            end
        end
        if (ym_cmd_valid) begin
            ym_count <= ym_count + 1;
            if (!ym_cmd_port && ym_cmd_reg == 8'h2A) begin
                if (dac_count == 0) begin
                    dac_data0 <= ym_cmd_data;
                end else if (dac_count == 1) begin
                    dac_data1 <= ym_cmd_data;
                end
                dac_count <= dac_count + 1;
            end
        end
        if (psg_cmd_valid) begin
            psg_count <= psg_count + 1;
        end
    end

    task clear_mem;
        integer i;
        begin
            for (i = 0; i < 256; i = i + 1) begin
                mem[i] = 8'h00;
            end
        end
    endtask

    task write_magic;
        begin
            mem[8'h00] = "V";
            mem[8'h01] = "g";
            mem[8'h02] = "m";
            mem[8'h03] = " ";
        end
    endtask

    task pulse_load_done;
        begin
            @(posedge clk);
            load_done <= 1'b1;
            load_done_pulse <= 1'b1;
            @(posedge clk);
            load_done_pulse <= 1'b0;
        end
    endtask

    task pulse_wait_tick;
        begin
            @(posedge clk);
            vgm_wait_tick <= 1'b1;
            @(posedge clk);
            vgm_wait_tick <= 1'b0;
        end
    endtask

    initial begin
        clear_mem();
        repeat (4) @(posedge clk);
        reset <= 1'b0;
        repeat (2) @(posedge clk);

        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
        repeat (40) @(posedge clk);
        if (ym_count != 0 || psg_count != 0 || busy || done || header_valid) begin
            $display("FAIL no_playback_before_load ym=%0d psg=%0d busy=%0b done=%0b header=%0b",
                     ym_count, psg_count, busy, done, header_valid);
            $finish;
        end

        write_magic();
        mem[8'h34] = 8'h00;
        mem[8'h35] = 8'h00;
        mem[8'h36] = 8'h00;
        mem[8'h37] = 8'h00;
        mem[8'h3c] = 8'h0c;
        mem[8'h40] = 8'h52;
        mem[8'h41] = 8'h28;
        mem[8'h42] = 8'h00;
	        mem[8'h43] = 8'h70;
	        mem[8'h44] = 8'h66;
	        file_size = 9'h045;
	        ym_cmd_ready = 1'b0;
	        pulse_load_done();

	        repeat (120) begin
	            pulse_wait_tick();
	        end

	        if (ym_count != 0 || !busy || !header_valid) begin
	            $display("FAIL ym_waits_for_ready ym_count=%0d busy=%0b header=%0b",
	                     ym_count, busy, header_valid);
	            $finish;
	        end

	        ym_cmd_ready = 1'b1;

	        repeat (120) begin
	            pulse_wait_tick();
	            if (ym_count != 0) begin
                break;
            end
        end

        if (!header_valid || segapcm_interface != 32'h0000_000c ||
            data_start_debug != 8'h40 || !restarted_from_data_start ||
            ym_count != 1 ||
            ym_cmd_reg != 8'h28 || ym_cmd_data != 8'h00) begin
            $display("FAIL zero_offset header=%0b interface=%08h data_start=%02h restarted=%0b ym_count=%0d reg=%02h data=%02h",
                     header_valid, segapcm_interface, data_start_debug,
                     restarted_from_data_start,
                     ym_count, ym_cmd_reg, ym_cmd_data);
            $finish;
        end

        reset <= 1'b1;
        repeat (3) @(posedge clk);
        reset <= 1'b0;
        ym_count <= 0;
        psg_count <= 0;
        dac_count <= 0;
        dac_data0 <= 8'h00;
        dac_data1 <= 8'h00;
        load_done <= 1'b0;
        repeat (2) @(posedge clk);

        clear_mem();
        write_magic();
        mem[8'h34] = 8'h00;
        mem[8'h35] = 8'h00;
        mem[8'h36] = 8'h00;
        mem[8'h37] = 8'h00;
        for (integer i = 0; i < 60; i = i + 1) begin
            mem[8'h40 + i] = 8'h62;
        end
        mem[8'h7c] = 8'h66;
        file_size = 9'h07d;
        pulse_load_done();

        repeat (80) @(posedge clk);
        if (!header_valid || done || wait_ticks_consumed_debug != 32'd0) begin
            $display("FAIL wait_no_clk_decrement header=%0b done=%0b ticks=%0d",
                     header_valid, done, wait_ticks_consumed_debug);
            $finish;
        end

        while (wait_ticks_consumed_debug < 32'd44099) begin
            pulse_wait_tick();
            @(posedge clk);
        end
        repeat (20) @(posedge clk);
        if (done || wait_ticks_consumed_debug != 32'd44099) begin
            $display("FAIL wait_60x62_before_final_tick done=%0b ticks=%0d",
                     done, wait_ticks_consumed_debug);
            $finish;
        end

        while (wait_ticks_consumed_debug < 32'd44100) begin
            pulse_wait_tick();
            @(posedge clk);
        end
        repeat (300) @(posedge clk);
        if (!done || !end_command_seen || wait_ticks_consumed_debug != 32'd44100 ||
            player_error) begin
            $display("FAIL wait_60x62_one_second done=%0b end=%0b ticks=%0d error=%0b",
                     done, end_command_seen, wait_ticks_consumed_debug, player_error);
            $finish;
        end

        reset <= 1'b1;
        repeat (3) @(posedge clk);
        reset <= 1'b0;
        ym_count <= 0;
        psg_count <= 0;
        load_done <= 1'b0;
        repeat (2) @(posedge clk);

        clear_mem();
        write_magic();
        mem[8'h34] = 8'h10;
        mem[8'h35] = 8'h00;
        mem[8'h36] = 8'h00;
        mem[8'h37] = 8'h00;
        mem[8'h44] = 8'h67;
        mem[8'h45] = 8'h66;
        mem[8'h46] = 8'h00;
        mem[8'h47] = 8'h03;
        mem[8'h48] = 8'h00;
        mem[8'h49] = 8'h00;
        mem[8'h4a] = 8'h00;
        mem[8'h4b] = 8'h11;
        mem[8'h4c] = 8'h22;
        mem[8'h4d] = 8'h33;
        mem[8'h4e] = 8'h50;
        mem[8'h4f] = 8'h9f;
        mem[8'h50] = 8'h66;
        file_size = 9'h051;
        pulse_load_done();

        repeat (120) @(posedge clk);
        if (!header_valid || data_start_debug != 8'h44 || psg_count != 1 || psg_cmd_data != 8'h9f) begin
            $display("FAIL data_block_skip header=%0b data_start=%02h psg_count=%0d psg=%02h",
                     header_valid, data_start_debug, psg_count, psg_cmd_data);
            $finish;
        end

        reset <= 1'b1;
        repeat (3) @(posedge clk);
        reset <= 1'b0;
        ym_count <= 0;
        psg_count <= 0;
        dac_count <= 0;
        dac_data0 <= 8'h00;
        dac_data1 <= 8'h00;
        load_done <= 1'b0;
        repeat (2) @(posedge clk);

        clear_mem();
        write_magic();
        mem[8'h34] = 8'h00;
        mem[8'h35] = 8'h00;
        mem[8'h36] = 8'h00;
        mem[8'h37] = 8'h00;
        mem[8'h40] = 8'h67;
        mem[8'h41] = 8'h66;
        mem[8'h42] = 8'h00; // PCM data bank
        mem[8'h43] = 8'h04;
        mem[8'h44] = 8'h00;
        mem[8'h45] = 8'h00;
        mem[8'h46] = 8'h00;
        mem[8'h47] = 8'h11;
        mem[8'h48] = 8'h22;
        mem[8'h49] = 8'h33;
        mem[8'h4a] = 8'h44;
        mem[8'h4b] = 8'hE0;
        mem[8'h4c] = 8'h01;
        mem[8'h4d] = 8'h00;
        mem[8'h4e] = 8'h00;
        mem[8'h4f] = 8'h00;
        mem[8'h50] = 8'h80;
        mem[8'h51] = 8'h81;
        mem[8'h52] = 8'h66;
        file_size = 9'h053;
        pulse_load_done();

        repeat (120) begin
            pulse_wait_tick();
        end
        if (!header_valid || player_error || ym_count != 2 || dac_count != 2 ||
            dac_data0 != 8'h22 || dac_data1 != 8'h33 ||
            pcm_oob || pcm_oob_count != 32'd0 || wait_ticks_consumed_debug != 32'd1) begin
            $display("FAIL pcm_dac_stream header=%0b error=%0b ym=%0d dac=%0d data0=%02h data1=%02h oob=%0b oob_count=%0d ticks=%0d",
                     header_valid, player_error, ym_count, dac_count,
                     dac_data0, dac_data1, pcm_oob, pcm_oob_count,
                     wait_ticks_consumed_debug);
            $finish;
        end

        reset <= 1'b1;
        repeat (3) @(posedge clk);
        reset <= 1'b0;
        ym_count <= 0;
        psg_count <= 0;
        dac_count <= 0;
        dac_data0 <= 8'h00;
        dac_data1 <= 8'h00;
        load_done <= 1'b0;
        repeat (2) @(posedge clk);

        clear_mem();
        write_magic();
        mem[8'h34] = 8'h00;
        mem[8'h35] = 8'h00;
        mem[8'h36] = 8'h00;
        mem[8'h37] = 8'h00;
        mem[8'h40] = 8'h67;
        mem[8'h41] = 8'h66;
        mem[8'h42] = 8'h00; // PCM data bank
        mem[8'h43] = 8'h01;
        mem[8'h44] = 8'h00;
        mem[8'h45] = 8'h00;
        mem[8'h46] = 8'h00;
        mem[8'h47] = 8'h55;
        mem[8'h48] = 8'hE0;
        mem[8'h49] = 8'h00;
        mem[8'h4a] = 8'h00;
        mem[8'h4b] = 8'h00;
        mem[8'h4c] = 8'h00;
        mem[8'h4d] = 8'h80;
        mem[8'h4e] = 8'h66;
        file_size = 9'h04f;
        ym_cmd_ready = 1'b0;
        pulse_load_done();

        repeat (120) begin
            pulse_wait_tick();
        end
        if (!header_valid || player_error || ym_count != 0 || dac_count != 0 ||
            current_pc_debug != 8'h4d || last_cmd_debug != 8'h80 ||
            done || !busy) begin
            $display("FAIL dac_waits_for_ready_before_pc_advance header=%0b error=%0b ym=%0d dac=%0d pc=%02h cmd=%02h done=%0b busy=%0b",
                     header_valid, player_error, ym_count, dac_count,
                     current_pc_debug, last_cmd_debug, done, busy);
            $finish;
        end

        ym_cmd_ready = 1'b1;
        repeat (120) begin
            pulse_wait_tick();
        end
        if (!done || player_error || ym_count != 1 || dac_count != 1 ||
            dac_data0 != 8'h55 || wait_ticks_consumed_debug != 32'd0) begin
            $display("FAIL dac_zero_wait_after_ready done=%0b error=%0b ym=%0d dac=%0d data0=%02h ticks=%0d",
                     done, player_error, ym_count, dac_count,
                     dac_data0, wait_ticks_consumed_debug);
            $finish;
        end

        reset <= 1'b1;
        repeat (3) @(posedge clk);
        reset <= 1'b0;
        ym_count <= 0;
        psg_count <= 0;
        dac_count <= 0;
        dac_data0 <= 8'h00;
        dac_data1 <= 8'h00;
        load_done <= 1'b0;
        ym_cmd_ready = 1'b1;
        repeat (2) @(posedge clk);

        clear_mem();
        write_magic();
        mem[8'h34] = 8'h00;
        mem[8'h35] = 8'h00;
        mem[8'h36] = 8'h00;
        mem[8'h37] = 8'h00;
        mem[8'h40] = 8'h67;
        mem[8'h41] = 8'h66;
        mem[8'h42] = 8'h00; // PCM data bank
        mem[8'h43] = 8'h01;
        mem[8'h44] = 8'h00;
        mem[8'h45] = 8'h00;
        mem[8'h46] = 8'h00;
        mem[8'h47] = 8'h7f;
        mem[8'h48] = 8'hE0;
        mem[8'h49] = 8'h01;
        mem[8'h4a] = 8'h00;
        mem[8'h4b] = 8'h00;
        mem[8'h4c] = 8'h00;
        mem[8'h4d] = 8'h80;
        mem[8'h4e] = 8'h81;
        mem[8'h4f] = 8'h66;
        file_size = 9'h050;
        pulse_load_done();

        repeat (120) begin
            pulse_wait_tick();
        end
        if (!header_valid || player_error || !done || !end_command_seen ||
            ym_count != 2 || dac_count != 2 ||
            dac_data0 != 8'h80 || dac_data1 != 8'h80 ||
            !pcm_oob || pcm_oob_count != 32'd2 ||
            player_error_code != 8'd0 || wait_ticks_consumed_debug != 32'd1) begin
            $display("FAIL pcm_oob_continues header=%0b error=%0b done=%0b end=%0b ym=%0d dac=%0d data0=%02h data1=%02h oob=%0b oob_count=%0d code=%0d ticks=%0d",
                     header_valid, player_error, done, end_command_seen,
                     ym_count, dac_count, dac_data0, dac_data1,
                     pcm_oob, pcm_oob_count, player_error_code,
                     wait_ticks_consumed_debug);
            $finish;
        end

        reset <= 1'b1;
        repeat (3) @(posedge clk);
        reset <= 1'b0;
        ym_count <= 0;
        psg_count <= 0;
        dac_count <= 0;
        dac_data0 <= 8'h00;
        dac_data1 <= 8'h00;
        load_done <= 1'b0;
        repeat (2) @(posedge clk);

        clear_mem();
        write_magic();
        mem[8'h34] = 8'h00;
        mem[8'h35] = 8'h00;
        mem[8'h36] = 8'h00;
        mem[8'h37] = 8'h00;
        mem[8'h40] = 8'h66;
        file_size = 9'h041;
        pulse_load_done();

        repeat (80) @(posedge clk);
        if (!done || !end_command_seen || loop_taken_debug || loop_valid_debug || player_error) begin
            $display("FAIL end_no_loop done=%0b end=%0b loop_taken=%0b loop_valid=%0b error=%0b",
                     done, end_command_seen, loop_taken_debug, loop_valid_debug, player_error);
            $finish;
        end

        reset <= 1'b1;
        repeat (3) @(posedge clk);
        reset <= 1'b0;
        ym_count <= 0;
        psg_count <= 0;
        load_done <= 1'b0;
        repeat (2) @(posedge clk);

        clear_mem();
        write_magic();
        mem[8'h1c] = 8'h2c; // loop_pc = 0x1c + 0x2c = 0x48
        mem[8'h1d] = 8'h00;
        mem[8'h1e] = 8'h00;
        mem[8'h1f] = 8'h00;
        mem[8'h34] = 8'h00;
        mem[8'h35] = 8'h00;
        mem[8'h36] = 8'h00;
        mem[8'h37] = 8'h00;
        mem[8'h40] = 8'h66;
        mem[8'h48] = 8'h50;
        mem[8'h49] = 8'ha5;
        mem[8'h4a] = 8'h66;
        file_size = 9'h04b;
        pulse_load_done();

        repeat (120) @(posedge clk);
        if (!header_valid || !end_command_seen || !loop_valid_debug ||
            !loop_taken_debug || loop_pc_debug != 8'h48 ||
            psg_count == 0 || psg_cmd_data != 8'ha5 || done || player_error) begin
            $display("FAIL end_loop header=%0b end=%0b loop_valid=%0b loop_taken=%0b loop_pc=%02h psg_count=%0d psg=%02h done=%0b error=%0b",
                     header_valid, end_command_seen, loop_valid_debug, loop_taken_debug,
                     loop_pc_debug, psg_count, psg_cmd_data, done, player_error);
            $finish;
        end

        reset <= 1'b1;
        repeat (3) @(posedge clk);
        reset <= 1'b0;
        ym_count <= 0;
        psg_count <= 0;
        load_done <= 1'b0;
        repeat (2) @(posedge clk);

        clear_mem();
        write_magic();
        mem[8'h34] = 8'h00;
        mem[8'h35] = 8'h00;
        mem[8'h36] = 8'h00;
        mem[8'h37] = 8'h00;
        mem[8'h40] = 8'h67;
        mem[8'h41] = 8'h66;
        mem[8'h42] = 8'h00;
        mem[8'h43] = 8'h20;
        mem[8'h44] = 8'h00;
        mem[8'h45] = 8'h00;
        mem[8'h46] = 8'h00;
        file_size = 9'h048;
        pulse_load_done();

        repeat (120) @(posedge clk);
        if (!player_error || player_error_code != 8'd7 || ym_count != 0 || psg_count != 0) begin
            $display("FAIL data_block_range error=%0b code=%0d ym=%0d psg=%0d",
                     player_error, player_error_code, ym_count, psg_count);
            $finish;
        end

        reset <= 1'b1;
        repeat (3) @(posedge clk);
        reset <= 1'b0;
        ym_count <= 0;
        psg_count <= 0;
        load_done <= 1'b0;
        repeat (2) @(posedge clk);

        clear_mem();
        write_magic();
        mem[8'h34] = 8'h00;
        mem[8'h35] = 8'h00;
        mem[8'h36] = 8'h00;
        mem[8'h37] = 8'h00;
        mem[8'h40] = 8'h99;
        mem[8'h41] = 8'h66;
        file_size = 9'h042;
        pulse_load_done();

        repeat (80) @(posedge clk);
        if (!player_error || unsupported_opcode != 8'h99 || unsupported_pc != 8'h40 ||
            player_error_code != 8'd4 || ym_count != 0 || psg_count != 0) begin
            $display("FAIL unsupported_debug error=%0b opcode=%02h pc=%02h code=%0d ym=%0d psg=%0d",
                     player_error, unsupported_opcode, unsupported_pc, player_error_code,
                     ym_count, psg_count);
            $finish;
        end

        reset <= 1'b1;
        repeat (3) @(posedge clk);
        reset <= 1'b0;
        ym_count <= 0;
        psg_count <= 0;
        load_done <= 1'b0;
        load_error <= 1'b1;
        file_size <= 9'h047;
        repeat (2) @(posedge clk);
        pulse_load_done();
        repeat (40) @(posedge clk);
        if (ym_count != 0 || psg_count != 0 || busy || header_valid || !player_error) begin
            $display("FAIL load_error_blocks_playback ym=%0d psg=%0d busy=%0b header=%0b player_error=%0b",
                     ym_count, psg_count, busy, header_valid, player_error);
            $finish;
        end

        load_error <= 1'b0;
        overflow_error <= 1'b1;
        repeat (40) @(posedge clk);
        if (ym_count != 0 || psg_count != 0 || busy || header_valid || !player_error) begin
            $display("FAIL overflow_blocks_playback ym=%0d psg=%0d busy=%0b header=%0b player_error=%0b",
                     ym_count, psg_count, busy, header_valid, player_error);
            $finish;
        end

        $display("PASS tb_vgm_loaded_player");
        $finish;
    end

endmodule
