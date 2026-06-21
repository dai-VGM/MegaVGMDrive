module tb_vgm_loaded_player_ym2151;
    localparam int ADDR_WIDTH = 8;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic load_done = 1'b0;
    logic load_done_pulse = 1'b0;
    logic vgm_wait_tick = 1'b0;
    logic [ADDR_WIDTH:0] file_size = 9'd96;

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

    logic [7:0] mem [0:255];
    logic pending = 1'b0;
    logic [7:0] pending_data = 8'd0;
    integer ym2151_seen = 0;

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
        end else if (ym2151_cmd_valid) begin
            ym2151_seen <= ym2151_seen + 1;
        end
    end

    initial begin
        for (int i = 0; i < 256; i++) mem[i] = 8'h00;
        mem[8'h00] = "V";
        mem[8'h01] = "g";
        mem[8'h02] = "m";
        mem[8'h03] = " ";
        mem[8'h34] = 8'h00;
        mem[8'h35] = 8'h00;
        mem[8'h36] = 8'h00;
        mem[8'h37] = 8'h00;

        mem[8'h40] = 8'h54; mem[8'h41] = 8'h20; mem[8'h42] = 8'hc0;
        mem[8'h43] = 8'h50; mem[8'h44] = 8'h9f;
        mem[8'h45] = 8'h52; mem[8'h46] = 8'h22; mem[8'h47] = 8'h00;
        mem[8'h48] = 8'h61; mem[8'h49] = 8'h02; mem[8'h4a] = 8'h00;
        mem[8'h4b] = 8'h54; mem[8'h4c] = 8'h08; mem[8'h4d] = 8'h78;
        mem[8'h4e] = 8'h66;

        repeat (4) @(posedge clk);
        reset <= 1'b0;
        @(posedge clk);
        load_done <= 1'b1;
        load_done_pulse <= 1'b1;
        @(posedge clk);
        load_done_pulse <= 1'b0;

        wait (done || player_error);
        if (player_error) begin
            $display("FAIL ym2151 parser entered error");
            $finish;
        end
        if (ym2151_seen != 2 || ym2151_write_count != 2) begin
            $display("FAIL ym2151 writes seen=%0d count=%0d", ym2151_seen, ym2151_write_count);
            $finish;
        end
        if (ym2151_last_reg != 8'h08 || ym2151_last_data != 8'h78) begin
            $display("FAIL ym2151 last reg=%02h data=%02h", ym2151_last_reg, ym2151_last_data);
            $finish;
        end
        if (unsupported_command_count < 2) begin
            $display("FAIL unsupported skip count=%0d", unsupported_command_count);
            $finish;
        end
        $display("PASS tb_vgm_loaded_player_ym2151");
        $finish;
    end
endmodule
