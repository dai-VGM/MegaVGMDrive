`timescale 1ns/1ps

module tb_behavior_short_end_psg_sequence;

    localparam int ADDR_WIDTH = 8;
    localparam int MEM_BYTES = 1 << ADDR_WIDTH;
    localparam int EXPECTED_PSG_COUNT = 23;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic load_done = 1'b1;
    logic load_error = 1'b0;
    logic overflow_error = 1'b0;
    logic [ADDR_WIDTH:0] file_size = 9'd0;
    logic vgm_wait_tick = 1'b0;
    logic wait_tick_toggle = 1'b0;
    wire mem_rd_req;
    wire [ADDR_WIDTH-1:0] mem_rd_addr;
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
    wire player_error;
    wire [7:0] player_error_code;
    wire [ADDR_WIDTH-1:0] current_pc_debug;

    logic [7:0] mem [0:MEM_BYTES-1];
    logic [7:0] pending_data = 8'd0;
    logic pending = 1'b0;
    logic [7:0] captured_psg [0:63];
    integer psg_count = 0;
    integer pass_index = 0;

    vgm_loaded_player #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk                      (clk),
        .reset                    (reset),
        .start                    (start),
        .load_done                (load_done),
        .load_done_pulse          (1'b0),
        .load_error               (load_error),
        .overflow_error           (overflow_error),
        .file_size                (file_size),
        .vgm_wait_tick            (vgm_wait_tick),
        .halt_at_loop_boundary    (1'b0),
        .mem_rd_req               (mem_rd_req),
        .mem_rd_addr              (mem_rd_addr),
        .mem_rd_ready             (mem_rd_ready),
        .mem_rd_valid             (mem_rd_valid),
        .mem_rd_data              (mem_rd_data),
        .segapcm_copy_wr_req      (),
        .segapcm_copy_wr_ready    (1'b1),
        .segapcm_copy_wr_addr     (),
        .segapcm_copy_wr_data     (),
        .segapcm_copy_flush_req   (),
        .segapcm_copy_flush_done  (1'b1),
        .ym_cmd_ready             (ym_cmd_ready),
        .psg_cmd_ready            (psg_cmd_ready),
        .ym_cmd_valid             (ym_cmd_valid),
        .ym_cmd_port              (ym_cmd_port),
        .ym_cmd_reg               (ym_cmd_reg),
        .ym_cmd_data              (ym_cmd_data),
        .psg_cmd_valid            (psg_cmd_valid),
        .psg_cmd_data             (psg_cmd_data),
        .ym2151_cmd_ready         (1'b1),
        .ym2151_cmd_valid         (),
        .ym2151_cmd_reg           (),
        .ym2151_cmd_data          (),
        .busy                     (busy),
        .done                     (done),
        .header_valid             (header_valid),
        .player_error             (player_error),
        .unsupported_opcode       (),
        .unsupported_pc           (),
        .player_error_code        (player_error_code),
        .error_pc_debug           (),
        .error_cmd_debug          (),
        .state_debug              (),
        .mem_rd_req_debug         (),
        .mem_rd_ready_debug       (),
        .mem_rd_valid_debug       (),
        .mem_rd_addr_debug        (),
        .data_start_debug         (),
        .current_pc_debug         (current_pc_debug),
        .loop_pc_debug            (),
        .loop_valid_debug         (),
        .loop_taken_debug         (),
        .end_command_seen         (),
        .restarted_from_data_start(),
        .pcm_oob                  (),
        .pcm_oob_count            (),
        .wait_ticks_consumed_debug(),
        .done_pc_debug            (),
        .done_cmd_debug           (),
        .pc_debug                 (),
        .last_cmd_debug           ()
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (reset) begin
            wait_tick_toggle <= 1'b0;
            vgm_wait_tick <= 1'b0;
        end else begin
            wait_tick_toggle <= !wait_tick_toggle;
            vgm_wait_tick <= !wait_tick_toggle;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            mem_rd_valid <= 1'b0;
            mem_rd_data <= 8'd0;
            pending <= 1'b0;
            pending_data <= 8'd0;
            mem_rd_ready <= 1'b1;
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
            psg_count <= 0;
        end else if (psg_cmd_valid && psg_cmd_ready) begin
            captured_psg[psg_count] <= psg_cmd_data;
            psg_count <= psg_count + 1;
        end
    end

    function automatic [7:0] expected_psg(input int index);
        begin
            unique case (index)
                0: expected_psg = 8'h9F;
                1: expected_psg = 8'hBF;
                2: expected_psg = 8'hDF;
                3: expected_psg = 8'hFF;
                4: expected_psg = 8'h80;
                5: expected_psg = 8'h08;
                6: expected_psg = 8'hA0;
                7: expected_psg = 8'h10;
                8: expected_psg = 8'hC0;
                9: expected_psg = 8'h18;
                10: expected_psg = 8'hE0;
                11: expected_psg = 8'h9F;
                12: expected_psg = 8'h80;
                13: expected_psg = 8'h05;
                14: expected_psg = 8'h92;
                15: expected_psg = 8'h9F;
                16: expected_psg = 8'h80;
                17: expected_psg = 8'h18;
                18: expected_psg = 8'h92;
                19: expected_psg = 8'h9F;
                20: expected_psg = 8'hBF;
                21: expected_psg = 8'hDF;
                default: expected_psg = 8'hFF;
            endcase
        end
    endfunction

    function automatic [7:0] short_end_byte(input int addr);
        begin
            unique case (addr)
                0: short_end_byte = "V";
                1: short_end_byte = "g";
                2: short_end_byte = "m";
                3: short_end_byte = " ";
                'h08: short_end_byte = 8'h50;
                'h09: short_end_byte = 8'h01;
                'h0a: short_end_byte = 8'h00;
                'h0b: short_end_byte = 8'h00;
                'h34: short_end_byte = 8'h0c;
                'h40: short_end_byte = 8'h50;
                'h41: short_end_byte = 8'h9f;
                'h42: short_end_byte = 8'h50;
                'h43: short_end_byte = 8'hbf;
                'h44: short_end_byte = 8'h50;
                'h45: short_end_byte = 8'hdf;
                'h46: short_end_byte = 8'h50;
                'h47: short_end_byte = 8'hff;
                'h48: short_end_byte = 8'h50;
                'h49: short_end_byte = 8'h80;
                'h4a: short_end_byte = 8'h50;
                'h4b: short_end_byte = 8'h08;
                'h4c: short_end_byte = 8'h50;
                'h4d: short_end_byte = 8'ha0;
                'h4e: short_end_byte = 8'h50;
                'h4f: short_end_byte = 8'h10;
                'h50: short_end_byte = 8'h50;
                'h51: short_end_byte = 8'hc0;
                'h52: short_end_byte = 8'h50;
                'h53: short_end_byte = 8'h18;
                'h54: short_end_byte = 8'h50;
                'h55: short_end_byte = 8'he0;
                'h56: short_end_byte = 8'h61;
                'h57: short_end_byte = 8'hdf;
                'h58: short_end_byte = 8'h02;
                'h59: short_end_byte = 8'h50;
                'h5a: short_end_byte = 8'h9f;
                'h5b: short_end_byte = 8'h50;
                'h5c: short_end_byte = 8'h80;
                'h5d: short_end_byte = 8'h50;
                'h5e: short_end_byte = 8'h05;
                'h5f: short_end_byte = 8'h50;
                'h60: short_end_byte = 8'h92;
                'h61: short_end_byte = 8'h61;
                'h62: short_end_byte = 8'h96;
                'h63: short_end_byte = 8'h78;
                'h64: short_end_byte = 8'h50;
                'h65: short_end_byte = 8'h9f;
                'h66: short_end_byte = 8'h50;
                'h67: short_end_byte = 8'h80;
                'h68: short_end_byte = 8'h50;
                'h69: short_end_byte = 8'h18;
                'h6a: short_end_byte = 8'h50;
                'h6b: short_end_byte = 8'h92;
                'h6c: short_end_byte = 8'h61;
                'h6d: short_end_byte = 8'hb8;
                'h6e: short_end_byte = 8'hce;
                'h6f: short_end_byte = 8'h50;
                'h70: short_end_byte = 8'h9f;
                'h71: short_end_byte = 8'h50;
                'h72: short_end_byte = 8'hbf;
                'h73: short_end_byte = 8'h50;
                'h74: short_end_byte = 8'hdf;
                'h75: short_end_byte = 8'h50;
                'h76: short_end_byte = 8'hff;
                'h77: short_end_byte = 8'h61;
                'h78: short_end_byte = 8'h74;
                'h79: short_end_byte = 8'h22;
                'h7a: short_end_byte = 8'h66;
                default: short_end_byte = 8'h00;
            endcase
        end
    endfunction

    function automatic [7:0] prior_latch_byte(input int addr);
        begin
            unique case (addr)
                0: prior_latch_byte = "V";
                1: prior_latch_byte = "g";
                2: prior_latch_byte = "m";
                3: prior_latch_byte = " ";
                'h08: prior_latch_byte = 8'h50;
                'h09: prior_latch_byte = 8'h01;
                'h34: prior_latch_byte = 8'h0c;
                'h40: prior_latch_byte = 8'h50;
                'h41: prior_latch_byte = 8'ha0;
                'h42: prior_latch_byte = 8'h50;
                'h43: prior_latch_byte = 8'h12;
                'h44: prior_latch_byte = 8'h50;
                'h45: prior_latch_byte = 8'hbf;
                'h46: prior_latch_byte = 8'h66;
                default: prior_latch_byte = 8'h00;
            endcase
        end
    endfunction

    task automatic load_short_end;
        begin
            for (int i = 0; i < MEM_BYTES; i++) begin
                mem[i] = short_end_byte(i);
            end
            file_size = 9'h07b;
        end
    endtask

    task automatic load_prior_latch_vgm;
        begin
            for (int i = 0; i < MEM_BYTES; i++) begin
                mem[i] = prior_latch_byte(i);
            end
            file_size = 9'h047;
        end
    endtask

    task automatic reset_player;
        begin
            reset <= 1'b1;
            start <= 1'b0;
            repeat (4) @(posedge clk);
            reset <= 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic run_loaded_file(input int max_cycles);
        begin
            psg_count <= 0;
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            for (int i = 0; i < max_cycles; i++) begin
                @(posedge clk);
                if (done || player_error) begin
                    i = max_cycles;
                end
            end

            if (player_error || !done) begin
                $display("FAIL pass=%0d done=%0b error=%0b code=%0d pc=%02h",
                         pass_index, done, player_error, player_error_code,
                         current_pc_debug);
                $finish;
            end
        end
    endtask

    task automatic check_short_sequence(input int pass);
        begin
            if (psg_count != EXPECTED_PSG_COUNT) begin
                $display("FAIL pass=%0d psg_count=%0d expected=%0d",
                         pass, psg_count, EXPECTED_PSG_COUNT);
                $finish;
            end

            for (int i = 0; i < EXPECTED_PSG_COUNT; i++) begin
                if (captured_psg[i] != expected_psg(i)) begin
                    $display("FAIL pass=%0d psg[%0d]=%02h expected=%02h",
                             pass, i, captured_psg[i], expected_psg(i));
                    $finish;
                end
            end

            if (captured_psg[13][7] || captured_psg[17][7] ||
                captured_psg[12] != 8'h80 || captured_psg[16] != 8'h80) begin
                $display("FAIL pass=%0d tone data not explicitly latched pi=%02h/%02h bo=%02h/%02h",
                         pass, captured_psg[12], captured_psg[13],
                         captured_psg[16], captured_psg[17]);
                $finish;
            end
        end
    endtask

    initial begin
        reset_player();

        pass_index = 0;
        load_prior_latch_vgm();
        run_loaded_file(2000);

        pass_index = 1;
        reset_player();
        load_short_end();
        run_loaded_file(300000);
        check_short_sequence(1);

        pass_index = 2;
        reset_player();
        load_short_end();
        run_loaded_file(300000);
        check_short_sequence(2);

        $display("PASS tb_behavior_short_end_psg_sequence");
        $finish;
    end

endmodule
