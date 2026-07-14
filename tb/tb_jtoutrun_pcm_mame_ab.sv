`timescale 1ns/1ps

// Independent A/B regression for the two MAME compatibility switches.
// The ch1 register image is the Galaxy Force note beginning at 98.338277 s.
module segapcm_mame_ab_case #(
    parameter bit AB1_MAME_SCRATCH = 1'b0,
    parameter bit AB2_MAME_END = 1'b0,
    parameter integer CASE_ID = 0
) (
    input  logic clk,
    input  logic reset,
    output logic done = 1'b0,
    output logic [23:0] first_current = 24'hffffff,
    output integer request_count = 0
);
    logic [7:0] cpu_addr = 8'd0;
    logic [7:0] cpu_dout = 8'd0;
    logic cpu_cs = 1'b0;
    wire [18:0] rom_addr;
    wire rom_cs;
    integer i;
    integer timeout;

    task automatic cpu_write(input [7:0] addr, input [7:0] data);
        begin
            @(negedge clk);
            cpu_addr = addr;
            cpu_dout = data;
            cpu_cs = 1'b1;
            @(negedge clk);
            cpu_cs = 1'b0;
        end
    endtask

    jtoutrun_pcm #(
        .MAME_SCRATCH_CURRENT(AB1_MAME_SCRATCH),
        .MAME_NONLOOP_END(AB2_MAME_END)
    ) dut (
        .rst(reset), .clk(clk), .cen(1'b1), .debug_bus(8'd0),
        .cpu_addr(cpu_addr), .cpu_dout(cpu_dout), .cpu_rnw(1'b0),
        .cpu_cs(cpu_cs), .rom_addr(rom_addr), .rom_data(8'h81),
        .rom_ok(1'b1), .rom_cs(rom_cs),
        .smoke_variant(3'd0), .smoke_ddr_follow_mode(1'b0),
        .smoke_ddr_follow_init_enable(1'b0),
        .smoke_ddr_follow_delta_sel(3'd0), .smoke_c0_use_sel(2'd0),
        .smoke_c0_sample_mode(2'd0), .smoke_c0_delta(8'd0),
        .smoke_c0_vol_l(7'd0), .smoke_c0_vol_r(7'd0),
        .smoke_c0_raw_audible(1'b0), .smoke_c0_drive_sel(2'd0),
        .smoke_c0_seed_pulse(1'b0), .smoke_c0_endcmp_sel(2'd0),
        .smoke_c0_loopsrc_sel(2'd0), .smoke_c0_current_seed(24'd0),
        .smoke_c0_loop_seed(24'd0), .smoke_c0_end_addr(8'd0),
        .smoke_c0_ctrl(8'd0)
    );

    always @(posedge clk) begin
        if (!reset && dut.cen && dut.st == 4'd8 && dut.cur_ch == 4'd1 &&
            !dut.cfg_en[0]) begin
            if (request_count == 0)
                first_current <= dut.cur_addr;
            request_count <= request_count + 1;
        end
    end

    initial begin
        for (i = 0; i < 512; i = i + 1)
            dut.u_ram.mem[i] = 8'hff;

        // All other voices disabled. ch1 starts disabled while the C0 writes
        // below are applied in their real sequential order.
        dut.u_ram.mem[9'h008] = 8'h00;
        dut.u_ram.mem[9'h00a] = 8'h37;
        dut.u_ram.mem[9'h00b] = 8'h37;
        dut.u_ram.mem[9'h00c] = 8'h00;
        dut.u_ram.mem[9'h00d] = 8'h3a;
        dut.u_ram.mem[9'h00e] = 8'h3b;
        dut.u_ram.mem[9'h00f] = 8'h8e;
        dut.u_ram.mem[9'h08c] = 8'h00;
        dut.u_ram.mem[9'h08d] = 8'h00;
        dut.u_ram.mem[9'h08e] = 8'h13;
        dut.u_ram.mem[9'h108] = 8'h0d;

        // Galaxy Force 98.338185941 .. 98.338276644 s write order.
        cpu_write(8'h08, 8'h46); // offset 0: scratch in MAME
        cpu_write(8'h0a, 8'h37);
        cpu_write(8'h0b, 8'h37);
        cpu_write(8'h8c, 8'h00);
        cpu_write(8'h8d, 8'h3a);
        cpu_write(8'h0e, 8'h3b);
        cpu_write(8'h0f, 8'h8e);
        cpu_write(8'h8e, 8'h12); // enabled, non-loop

        @(negedge reset);
        // The preceding note left 0x0d in the hidden accumulator. The offset
        // 0 write invalidates it only in legacy mode.
        dut.c0_scratch_valid_i[1] = AB1_MAME_SCRATCH;

        begin : wait_stop
            for (timeout = 0; timeout < 500000; timeout = timeout + 1) begin
                @(negedge clk);
                if (request_count != 0 && dut.u_ram.mem[9'h08e][0]) begin
                    done = 1'b1;
                    disable wait_stop;
                end
            end
            $fatal(1, "case %0d timeout", CASE_ID);
        end
    end
endmodule

module tb_jtoutrun_pcm_mame_ab;
    logic clk = 1'b0;
    logic reset = 1'b1;
    wire [3:0] done;
    wire [23:0] first_current [0:3];
    integer request_count [0:3];
    integer timeout;

    always #25 clk = ~clk;

    segapcm_mame_ab_case #(.CASE_ID(0)) legacy(
        .clk(clk), .reset(reset), .done(done[0]),
        .first_current(first_current[0]), .request_count(request_count[0]));
    segapcm_mame_ab_case #(.AB1_MAME_SCRATCH(1), .CASE_ID(1)) ab1(
        .clk(clk), .reset(reset), .done(done[1]),
        .first_current(first_current[1]), .request_count(request_count[1]));
    segapcm_mame_ab_case #(.AB2_MAME_END(1), .CASE_ID(2)) ab2(
        .clk(clk), .reset(reset), .done(done[2]),
        .first_current(first_current[2]), .request_count(request_count[2]));
    segapcm_mame_ab_case #(
        .AB1_MAME_SCRATCH(1), .AB2_MAME_END(1), .CASE_ID(3)
    ) both (
        .clk(clk), .reset(reset), .done(done[3]),
        .first_current(first_current[3]), .request_count(request_count[3]));

    initial begin
        // Each case applies eight two-clock CPU writes while reset holds the
        // FSM. Leave margin before starting all four DUTs together.
        repeat (24) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        begin : wait_all
            for (timeout = 0; timeout < 600000; timeout = timeout + 1) begin
                @(negedge clk);
                if (&done)
                    disable wait_all;
            end
            $fatal(1, "A/B timeout done=%b", done);
        end

        if (first_current[0] !== 24'h3a0046 ||
            first_current[2] !== 24'h3a0046)
            $fatal(1, "legacy fraction mismatch %06h %06h",
                   first_current[0], first_current[2]);
        if (first_current[1] !== 24'h3a000d ||
            first_current[3] !== 24'h3a000d)
            $fatal(1, "MAME fraction mismatch %06h %06h",
                   first_current[1], first_current[3]);
        if (request_count[0] != 923 || request_count[1] != 923)
            $fatal(1, "legacy end counts %0d %0d",
                   request_count[0], request_count[1]);
        if (request_count[2] != 462 || request_count[3] != 462)
            $fatal(1, "MAME end counts %0d %0d",
                   request_count[2], request_count[3]);

        $display("A/B legacy current=%06h requests=%0d", first_current[0], request_count[0]);
        $display("A/B scratch current=%06h requests=%0d", first_current[1], request_count[1]);
        $display("A/B end current=%06h requests=%0d", first_current[2], request_count[2]);
        $display("A/B both current=%06h requests=%0d", first_current[3], request_count[3]);
        $display("PASS tb_jtoutrun_pcm_mame_ab");
        $finish;
    end
endmodule
