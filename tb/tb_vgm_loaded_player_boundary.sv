`timescale 1ns/1ps

module tb_vgm_loaded_player_boundary;

    localparam int ADDR_WIDTH = 17;
    localparam int MEM_BYTES = 1 << ADDR_WIDTH;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic load_done = 1'b0;
    logic load_done_pulse = 1'b0;
    logic [ADDR_WIDTH:0] file_size = '0;
    logic vgm_wait_tick = 1'b0;
    wire [ADDR_WIDTH-1:0] rd_addr;
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
    wire [7:0] player_error_code;
    wire [ADDR_WIDTH-1:0] current_pc_debug;
    wire [31:0] wait_ticks_consumed_debug;

    logic [7:0] mem [0:MEM_BYTES-1];
    integer psg_count = 0;

    vgm_loaded_player #(
        .ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .clk                 (clk),
        .reset               (reset),
        .start               (1'b0),
        .load_done           (load_done),
        .load_done_pulse     (load_done_pulse),
        .load_error          (1'b0),
        .overflow_error      (1'b0),
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
        .unsupported_opcode  (),
        .unsupported_pc      (),
        .player_error_code   (player_error_code),
        .data_start_debug    (),
        .current_pc_debug    (current_pc_debug),
        .loop_pc_debug       (),
        .loop_valid_debug    (),
        .loop_taken_debug    (),
        .end_command_seen    (),
        .restarted_from_data_start(),
        .pcm_oob             (),
        .pcm_oob_count       (),
        .wait_ticks_consumed_debug(wait_ticks_consumed_debug),
        .pc_debug            (),
        .last_cmd_debug      ()
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        rd_data <= mem[rd_addr];
        if (psg_cmd_valid) begin
            psg_count <= psg_count + 1;
        end
    end

    task pulse_load_done;
        begin
            @(posedge clk);
            load_done <= 1'b1;
            load_done_pulse <= 1'b1;
            @(posedge clk);
            load_done_pulse <= 1'b0;
        end
    endtask

    initial begin
        mem[17'h00000] = "V";
        mem[17'h00001] = "g";
        mem[17'h00002] = "m";
        mem[17'h00003] = " ";
        mem[17'h00034] = 8'h00;
        mem[17'h00035] = 8'h00;
        mem[17'h00036] = 8'h00;
        mem[17'h00037] = 8'h00;

        mem[17'h00040] = 8'h67;
        mem[17'h00041] = 8'h66;
        mem[17'h00042] = 8'h00;
        mem[17'h00043] = 8'h00;
        mem[17'h00044] = 8'h00;
        mem[17'h00045] = 8'h01;
        mem[17'h00046] = 8'h00;

        mem[17'h10047] = 8'h50;
        mem[17'h10048] = 8'h9f;
        mem[17'h10049] = 8'h66;
        file_size = 18'h1004a;

        repeat (4) @(posedge clk);
        reset <= 1'b0;
        repeat (2) @(posedge clk);
        pulse_load_done();

        repeat (200) @(posedge clk);
        if (!header_valid || player_error || !done || psg_count != 1 ||
            psg_cmd_data != 8'h9f || current_pc_debug != 17'h10049 ||
            wait_ticks_consumed_debug != 32'd0) begin
            $display("FAIL block_skip_cross_64k header=%0b error=%0b code=%0d done=%0b psg_count=%0d psg=%02h pc=%05h ticks=%0d",
                     header_valid, player_error, player_error_code, done,
                     psg_count, psg_cmd_data, current_pc_debug,
                     wait_ticks_consumed_debug);
            $finish;
        end

        $display("PASS tb_vgm_loaded_player_boundary");
        $finish;
    end

endmodule
