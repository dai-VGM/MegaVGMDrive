`timescale 1ns/1ps

module tb_vgm_loaded_player_error_halt;
    localparam int ADDR_WIDTH = 8;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic load_done = 1'b0;
    logic load_done_pulse = 1'b0;
    logic [ADDR_WIDTH:0] file_size = 9'h080;
    logic vgm_wait_tick = 1'b0;

    wire mem_rd_req;
    wire [ADDR_WIDTH-1:0] mem_rd_addr;
    logic mem_rd_ready = 1'b1;
    logic mem_rd_valid = 1'b0;
    logic [7:0] mem_rd_data = 8'd0;

    wire busy;
    wire done;
    wire header_valid;
    wire player_error;
    wire [7:0] unsupported_opcode;
    wire [ADDR_WIDTH-1:0] unsupported_pc;
    wire [7:0] player_error_code;
    wire [ADDR_WIDTH-1:0] error_pc_debug;
    wire [7:0] error_cmd_debug;
    wire [6:0] state_debug;
    wire mem_rd_req_debug;
    wire mem_rd_ready_debug;
    wire mem_rd_valid_debug;
    wire [ADDR_WIDTH-1:0] mem_rd_addr_debug;

    logic [7:0] mem [0:255];
    logic pending = 1'b0;
    logic [7:0] pending_data = 8'd0;

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
        .halt_at_loop_boundary(1'b0),
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
        .ym_cmd_ready        (1'b1),
        .psg_cmd_ready       (1'b1),
        .ym_cmd_valid        (),
        .ym_cmd_port         (),
        .ym_cmd_reg          (),
        .ym_cmd_data         (),
        .psg_cmd_valid       (),
        .psg_cmd_data        (),
        .ym2151_cmd_ready    (1'b1),
        .ym2151_cmd_valid    (),
        .ym2151_cmd_reg      (),
        .ym2151_cmd_data     (),
        .busy                (busy),
        .done                (done),
        .header_valid        (header_valid),
        .player_error        (player_error),
        .unsupported_opcode  (unsupported_opcode),
        .unsupported_pc      (unsupported_pc),
        .player_error_code   (player_error_code),
        .error_pc_debug      (error_pc_debug),
        .error_cmd_debug     (error_cmd_debug),
        .state_debug         (state_debug),
        .mem_rd_req_debug    (mem_rd_req_debug),
        .mem_rd_ready_debug  (mem_rd_ready_debug),
        .mem_rd_valid_debug  (mem_rd_valid_debug),
        .mem_rd_addr_debug   (mem_rd_addr_debug),
        .data_start_debug    (),
        .current_pc_debug    (),
        .loop_pc_debug       (),
        .loop_valid_debug    (),
        .loop_taken_debug    (),
        .end_command_seen    (),
        .restarted_from_data_start(),
        .pcm_oob             (),
        .pcm_oob_count       (),
        .wait_ticks_consumed_debug(),
        .done_pc_debug       (),
        .done_cmd_debug      (),
        .pc_debug            (),
        .last_cmd_debug      ()
    );

    always #5 clk = ~clk;

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
            if (mem_rd_req && !pending) begin
                pending_data <= mem[mem_rd_addr];
                pending <= 1'b1;
            end
        end
    end

    task automatic tick_wait(input int cycles);
        repeat (cycles) @(posedge clk);
    endtask

    initial begin
        integer i;
        for (i = 0; i < 256; i = i + 1) begin
            mem[i] = 8'h00;
        end

        mem[8'h00] = 8'h56;
        mem[8'h01] = 8'h67;
        mem[8'h02] = 8'h6d;
        mem[8'h03] = 8'h20;
        mem[8'h34] = 8'h00;
        mem[8'h35] = 8'h00;
        mem[8'h36] = 8'h00;
        mem[8'h37] = 8'h00;
        mem[8'h40] = 8'hF2;

        tick_wait(4);
        reset <= 1'b0;
        tick_wait(2);
        load_done <= 1'b1;
        load_done_pulse <= 1'b1;
        tick_wait(1);
        load_done_pulse <= 1'b0;

        tick_wait(200);
        if (!player_error ||
            player_error_code != 8'd4 ||
            unsupported_opcode != 8'hF2 ||
            unsupported_pc != 8'h40 ||
            error_cmd_debug != 8'hF2 ||
            error_pc_debug != 8'h40 ||
            busy ||
            done) begin
            $display("FAIL error halt err=%0b code=%02h uns=%02h upc=%02h ecmd=%02h epc=%02h busy=%0b done=%0b state=%0d mem_req=%0b mem_addr=%02h",
                     player_error, player_error_code, unsupported_opcode,
                     unsupported_pc, error_cmd_debug, error_pc_debug, busy,
                     done, state_debug, mem_rd_req_debug, mem_rd_addr_debug);
            $finish;
        end

        if (!mem_rd_ready_debug && mem_rd_valid_debug) begin
            $display("FAIL inconsistent mem debug ready=%0b valid=%0b",
                     mem_rd_ready_debug, mem_rd_valid_debug);
            $finish;
        end

        $display("PASS tb_vgm_loaded_player_error_halt");
        $finish;
    end
endmodule
