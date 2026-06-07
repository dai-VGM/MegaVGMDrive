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
    wire [7:0] rd_addr;
    logic [7:0] rd_data;
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
    wire [7:0] data_start_debug;
    wire [9:0] pc_debug;
    wire [7:0] last_cmd_debug;

    logic [7:0] mem [0:255];
    integer ym_count = 0;
    integer psg_count = 0;

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
        .rd_addr             (rd_addr),
        .rd_data             (rd_data),
        .ym_cmd_ready        (ym_cmd_ready),
        .psg_cmd_ready       (psg_cmd_ready),
        .ym_cmd_valid        (ym_cmd_valid),
        .ym_cmd_port         (ym_cmd_port),
        .ym_cmd_reg          (ym_cmd_reg),
        .ym_cmd_data         (ym_cmd_data),
        .psg_cmd_valid       (psg_cmd_valid),
        .psg_cmd_data        (psg_cmd_data),
        .busy                (busy),
        .done                (done),
        .header_valid        (header_valid),
        .player_error        (player_error),
        .data_start_debug    (data_start_debug),
        .pc_debug            (pc_debug),
        .last_cmd_debug      (last_cmd_debug)
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        rd_data <= mem[rd_addr];
        if (ym_cmd_valid) begin
            ym_count <= ym_count + 1;
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
        mem[8'h40] = 8'h52;
        mem[8'h41] = 8'h28;
        mem[8'h42] = 8'h00;
        mem[8'h43] = 8'h70;
        mem[8'h44] = 8'h66;
        file_size = 9'h045;
        pulse_load_done();

        repeat (120) begin
            pulse_wait_tick();
            if (ym_count != 0) begin
                break;
            end
        end

        if (!header_valid || data_start_debug != 8'h40 || ym_count != 1 ||
            ym_cmd_reg != 8'h28 || ym_cmd_data != 8'h00) begin
            $display("FAIL zero_offset header=%0b data_start=%02h ym_count=%0d reg=%02h data=%02h",
                     header_valid, data_start_debug, ym_count, ym_cmd_reg, ym_cmd_data);
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
        mem[8'h44] = 8'h50;
        mem[8'h45] = 8'h9f;
        mem[8'h46] = 8'h66;
        file_size = 9'h047;
        pulse_load_done();

        repeat (120) @(posedge clk);
        if (!header_valid || data_start_debug != 8'h44 || psg_count != 1 || psg_cmd_data != 8'h9f) begin
            $display("FAIL nonzero_offset header=%0b data_start=%02h psg_count=%0d psg=%02h",
                     header_valid, data_start_debug, psg_count, psg_cmd_data);
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
