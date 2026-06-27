`timescale 1ns/1ps

module tb_vgm_loaded_player_mem_if_case #(
    parameter int CASE_ID = 0,
    parameter int RESPONSE_LATENCY = 1,
    parameter int WAIT_CYCLES = 0
) (
    output logic case_done
);

    localparam int ADDR_WIDTH = 8;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic load_done = 1'b0;
    logic load_done_pulse = 1'b0;
    logic [ADDR_WIDTH:0] file_size = 9'h05c;
    logic vgm_wait_tick = 1'b0;

    wire mem_rd_req;
    wire [ADDR_WIDTH-1:0] mem_rd_addr;
    logic mem_rd_ready;
    logic mem_rd_valid;
    logic [7:0] mem_rd_data;

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
    wire [31:0] wait_ticks_consumed_debug;
    wire pcm_oob;
    wire [31:0] pcm_oob_count;

    logic [7:0] mem [0:255];
    integer ym_count = 0;
    integer psg_count = 0;
    integer dac_count = 0;
    logic [7:0] dac_data0 = 8'h00;
    logic [7:0] dac_data1 = 8'h00;

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
        .player_error        (player_error),
        .unsupported_opcode  (),
        .unsupported_pc      (),
        .player_error_code   (player_error_code),
        .error_pc_debug      (),
        .error_cmd_debug     (),
        .state_debug         (),
        .mem_rd_req_debug    (),
        .mem_rd_ready_debug  (),
        .mem_rd_valid_debug  (),
        .mem_rd_addr_debug   (),
        .data_start_debug    (),
        .current_pc_debug    (),
        .loop_pc_debug       (),
        .loop_valid_debug    (),
        .loop_taken_debug    (),
        .end_command_seen    (),
        .restarted_from_data_start(),
        .pcm_oob             (pcm_oob),
        .pcm_oob_count       (pcm_oob_count),
        .wait_ticks_consumed_debug(wait_ticks_consumed_debug),
        .done_pc_debug       (),
        .done_cmd_debug      (),
        .pc_debug            (),
        .last_cmd_debug      ()
    );

    always #5 clk = ~clk;

    generate
        if (RESPONSE_LATENCY == 0) begin : zero_latency_model
            always_comb begin
                mem_rd_ready = 1'b1;
                mem_rd_valid = mem_rd_req;
                mem_rd_data = mem[mem_rd_addr];
            end
        end else begin : registered_model
            logic pending = 1'b0;
            logic [7:0] pending_data = 8'd0;
            logic [7:0] latency_count = 8'd0;
            logic [7:0] wait_count = 8'd0;

            always_ff @(posedge clk) begin
                if (reset) begin
                    pending <= 1'b0;
                    pending_data <= 8'd0;
                    latency_count <= 8'd0;
                    wait_count <= 8'd0;
                    mem_rd_ready <= 1'b1;
                    mem_rd_valid <= 1'b0;
                    mem_rd_data <= 8'd0;
                end else begin
                    mem_rd_valid <= 1'b0;
                    mem_rd_ready <= !pending && (wait_count == 8'd0);

                    if (pending) begin
                        if (latency_count == 8'd0) begin
                            mem_rd_data <= pending_data;
                            mem_rd_valid <= 1'b1;
                            pending <= 1'b0;
                        end else begin
                            latency_count <= latency_count - 8'd1;
                        end
                    end else if (wait_count != 8'd0) begin
                        wait_count <= wait_count - 8'd1;
                    end

                    if (mem_rd_req && mem_rd_ready) begin
                        pending_data <= mem[mem_rd_addr];
                        pending <= 1'b1;
                        latency_count <= RESPONSE_LATENCY[7:0] - 8'd1;
                        wait_count <= WAIT_CYCLES[7:0];
                    end
                end
            end
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (reset) begin
            ym_count <= 0;
            psg_count <= 0;
            dac_count <= 0;
            dac_data0 <= 8'h00;
            dac_data1 <= 8'h00;
        end else begin
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
    end

    task automatic pulse_load_done;
        begin
            @(posedge clk);
            load_done <= 1'b1;
            load_done_pulse <= 1'b1;
            @(posedge clk);
            load_done_pulse <= 1'b0;
        end
    endtask

    task automatic pulse_wait_tick;
        begin
            @(posedge clk);
            vgm_wait_tick <= 1'b1;
            @(posedge clk);
            vgm_wait_tick <= 1'b0;
        end
    endtask

    initial begin
        case_done = 1'b0;
        for (integer i = 0; i < 256; i = i + 1) begin
            mem[i] = 8'h00;
        end

        mem[8'h00] = "V";
        mem[8'h01] = "g";
        mem[8'h02] = "m";
        mem[8'h03] = " ";
        mem[8'h34] = 8'h00;
        mem[8'h35] = 8'h00;
        mem[8'h36] = 8'h00;
        mem[8'h37] = 8'h00;

        mem[8'h40] = 8'h67;
        mem[8'h41] = 8'h66;
        mem[8'h42] = 8'h00;
        mem[8'h43] = 8'h04;
        mem[8'h44] = 8'h00;
        mem[8'h45] = 8'h00;
        mem[8'h46] = 8'h00;
        mem[8'h47] = 8'h11;
        mem[8'h48] = 8'h22;
        mem[8'h49] = 8'h33;
        mem[8'h4a] = 8'h44;
        mem[8'h4b] = 8'h52;
        mem[8'h4c] = 8'h28;
        mem[8'h4d] = 8'h00;
        mem[8'h4e] = 8'h53;
        mem[8'h4f] = 8'h28;
        mem[8'h50] = 8'h00;
        mem[8'h51] = 8'h50;
        mem[8'h52] = 8'h9f;
        mem[8'h53] = 8'hE0;
        mem[8'h54] = 8'h01;
        mem[8'h55] = 8'h00;
        mem[8'h56] = 8'h00;
        mem[8'h57] = 8'h00;
        mem[8'h58] = 8'h80;
        mem[8'h59] = 8'h81;
        mem[8'h5a] = 8'h70;
        mem[8'h5b] = 8'h66;

        repeat (4) @(posedge clk);
        reset <= 1'b0;
        repeat (2) @(posedge clk);
        pulse_load_done();

        repeat (200) begin
            pulse_wait_tick();
        end

        if (!done || !header_valid || player_error ||
            ym_count != 4 || psg_count != 1 || dac_count != 2 ||
            dac_data0 != 8'h22 || dac_data1 != 8'h33 ||
            pcm_oob || pcm_oob_count != 32'd0 ||
            wait_ticks_consumed_debug != 32'd2) begin
            $display("FAIL mem_if case=%0d done=%0b header=%0b error=%0b code=%0d ym=%0d psg=%0d dac=%0d data0=%02h data1=%02h oob=%0b oob_count=%0d ticks=%0d",
                     CASE_ID, done, header_valid, player_error,
                     player_error_code, ym_count, psg_count, dac_count,
                     dac_data0, dac_data1, pcm_oob, pcm_oob_count,
                     wait_ticks_consumed_debug);
            $finish;
        end

        $display("PASS tb_vgm_loaded_player_mem_if case=%0d", CASE_ID);
        case_done = 1'b1;
    end

endmodule

module tb_vgm_loaded_player_mem_if;

    wire done0;
    wire done1;
    wire done2;

    tb_vgm_loaded_player_mem_if_case #(
        .CASE_ID          (0),
        .RESPONSE_LATENCY (0),
        .WAIT_CYCLES      (0)
    ) latency0 (
        .case_done (done0)
    );

    tb_vgm_loaded_player_mem_if_case #(
        .CASE_ID          (1),
        .RESPONSE_LATENCY (1),
        .WAIT_CYCLES      (0)
    ) latency1 (
        .case_done (done1)
    );

    tb_vgm_loaded_player_mem_if_case #(
        .CASE_ID          (2),
        .RESPONSE_LATENCY (2),
        .WAIT_CYCLES      (3)
    ) wait_states (
        .case_done (done2)
    );

    initial begin
        wait (done0 && done1 && done2);
        $display("PASS tb_vgm_loaded_player_mem_if");
        $finish;
    end

endmodule
