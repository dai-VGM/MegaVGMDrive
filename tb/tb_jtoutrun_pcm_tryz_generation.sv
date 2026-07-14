`timescale 1ns/1ps

// Try-Z ch0 generations 1/2 with the real type-0x80 ROM bytes. This is a
// diagnostic-only bridge: 32-entry request FIFO, one DDR owner, 50-clock
// response latency, per-channel holds, and generation tags.
module tryz_generation_case #(
    parameter bit AB1_MAME_SCRATCH = 1'b0,
    parameter bit AB2_MAME_END = 1'b0,
    parameter integer CASE_ID = 0
) (
    input logic clk,
    input logic reset,
    input logic cen,
    input logic [7:0] cpu_addr,
    input logic [7:0] cpu_data,
    input logic cpu_cs,
    output integer generation = 0,
    output integer boundary_old_consume = 0,
    output integer boundary_new_consume = 0,
    output integer nonneutral_consume = 0,
    output integer dropped = 0,
    output integer overflow = 0
);
    localparam integer FIFO_DEPTH = 32;
    localparam integer DDR_LATENCY = 50;
    reg [7:0] rom [0:524287];
    reg [18:0] fifo_addr [0:FIFO_DEPTH-1];
    integer fifo_gen [0:FIFO_DEPTH-1];
    reg [3:0] fifo_ch [0:FIFO_DEPTH-1];
    integer wr_ptr = 0, rd_ptr = 0, fifo_count = 0;
    reg owner_valid = 1'b0;
    reg [18:0] owner_addr = 0;
    reg [3:0] owner_ch = 0;
    integer owner_gen = -1;
    integer response_wait = 0;
    reg [7:0] sample_hold [0:15];
    reg sample_hold_valid [0:15];
    integer hold_gen [0:15];
    reg [18:0] rom_addr_d = 0;
    reg rom_cs_d = 0;
    integer request_count = 0, issue_count = 0, response_count = 0;
    integer consume_count = 0, mixer_commit_count = 0;
    integer gen2_ch0_request_count = 0;
    integer max_fifo_count = 0;
    integer output_strobes [0:2];
    integer output_nonzero [0:2];
    longint output_abs_sum [0:2];
    time output_first_nonzero [0:2];
    time output_last_nonzero [0:2];
    integer i;
    wire [18:0] rom_addr;
    wire rom_cs;
    wire [7:0] rom_data = sample_hold_valid[dut.cur_ch] ?
                          sample_hold[dut.cur_ch] : 8'h80;
    wire request_event = rom_cs && (!rom_cs_d || rom_addr != rom_addr_d);

    jtoutrun_pcm #(
        .MAME_SCRATCH_CURRENT(AB1_MAME_SCRATCH),
        .MAME_NONLOOP_END(AB2_MAME_END)
    ) dut (
        .rst(reset), .clk(clk), .cen(cen), .debug_bus(8'd0),
        .cpu_addr(cpu_addr), .cpu_dout(cpu_data), .cpu_rnw(1'b0),
        .cpu_cs(cpu_cs), .rom_addr(rom_addr), .rom_data(rom_data),
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

    initial begin
        for (i = 0; i < 524288; i = i + 1)
            rom[i] = 8'h80;
        $readmemh("tb/data/galaxy_force_tryz_ch0_first_two.memh", rom);
        for (i = 0; i < 16; i = i + 1) begin
            sample_hold[i] = 8'h80;
            sample_hold_valid[i] = 1'b0;
            hold_gen[i] = -1;
        end
        for (i = 0; i < 3; i = i + 1) begin
            output_strobes[i] = 0;
            output_nonzero[i] = 0;
            output_abs_sum[i] = 0;
            output_first_nonzero[i] = 0;
            output_last_nonzero[i] = 0;
        end
        for (i = 0; i < 512; i = i + 1)
            dut.u_ram.mem[i] = 8'hff;
        // Keep five additional voices active to reproduce the six-request
        // frame load present when the Try-Z slap enters. Their neutral ROM
        // data does not affect the ch0 generation check.
        for (i = 2; i <= 6; i = i + 1) begin
            dut.u_ram.mem[i*8 + 0] = 8'h00;
            dut.u_ram.mem[i*8 + 2] = 8'h00;
            dut.u_ram.mem[i*8 + 3] = 8'h00;
            dut.u_ram.mem[i*8 + 4] = 8'h00;
            dut.u_ram.mem[i*8 + 5] = 8'h00;
            dut.u_ram.mem[i*8 + 6] = 8'hfe;
            dut.u_ram.mem[i*8 + 7] = 8'h80;
            dut.u_ram.mem[9'h080 + i*8 + 4] = 8'h00;
            dut.u_ram.mem[9'h080 + i*8 + 5] = 8'h00;
            dut.u_ram.mem[9'h080 + i*8 + 6] = 8'h02;
        end
    end

    always @(posedge clk) begin
        rom_cs_d <= rom_cs;
        rom_addr_d <= rom_addr;
        if (reset) begin
            wr_ptr <= 0; rd_ptr <= 0; fifo_count <= 0;
            owner_valid <= 1'b0; response_wait <= 0;
            generation <= 0;
        end else begin
            if (fifo_count > max_fifo_count)
                max_fifo_count <= fifo_count;
            if (cpu_cs && cpu_addr == 8'h85)
                generation <= generation + 1;

            if (request_event) begin
                request_count <= request_count + 1;
                if (dut.cur_ch == 4'd0 && generation == 1 &&
                    $time > 102700000000)
                    $display("PRETRACE case=%0d t=%0t gen=1 st=%0d cur=%06h addr=%05h hold_gen=%0d hold=%02h",
                             CASE_ID, $time, dut.st, dut.cur_addr, rom_addr,
                             hold_gen[0], rom_data);
                if (dut.cur_ch == 4'd0 && generation == 2) begin
                    if (gen2_ch0_request_count < 16)
                        $display("REQTRACE case=%0d t=%0t gen=2 n=%0d st=%0d cur=%06h addr=%05h hold_gen=%0d hold=%02h",
                                 CASE_ID, $time, gen2_ch0_request_count,
                                 dut.st, dut.cur_addr, rom_addr,
                                 hold_gen[0], rom_data);
                    gen2_ch0_request_count <= gen2_ch0_request_count + 1;
                end
                if (fifo_count == FIFO_DEPTH) begin
                    overflow <= overflow + 1;
                    dropped <= dropped + 1;
                end else begin
                    fifo_addr[wr_ptr] <= rom_addr;
                    fifo_ch[wr_ptr] <= dut.cur_ch;
                    fifo_gen[wr_ptr] <= generation;
                    wr_ptr <= (wr_ptr + 1) % FIFO_DEPTH;
                end
            end

            if (!owner_valid && fifo_count != 0) begin
                owner_valid <= 1'b1;
                owner_addr <= fifo_addr[rd_ptr];
                owner_ch <= fifo_ch[rd_ptr];
                owner_gen <= fifo_gen[rd_ptr];
                response_wait <= DDR_LATENCY;
                rd_ptr <= (rd_ptr + 1) % FIFO_DEPTH;
                issue_count <= issue_count + 1;
            end else if (owner_valid && response_wait != 0) begin
                response_wait <= response_wait - 1;
            end else if (owner_valid) begin
                sample_hold[owner_ch] <= rom[owner_addr];
                sample_hold_valid[owner_ch] <= 1'b1;
                hold_gen[owner_ch] <= owner_gen;
                owner_valid <= 1'b0;
                response_count <= response_count + 1;
            end

            case ({request_event && fifo_count != FIFO_DEPTH,
                   !owner_valid && fifo_count != 0})
                2'b10: fifo_count <= fifo_count + 1;
                2'b01: fifo_count <= fifo_count - 1;
                default: begin end
            endcase

            if (cen && dut.st == 4'd14 && dut.cur_ch == 4'd0) begin
                consume_count <= consume_count + 1;
                if (rom_data != 8'h80)
                    nonneutral_consume <= nonneutral_consume + 1;
                if (generation == 2 && hold_gen[0] == 1)
                    boundary_old_consume <= boundary_old_consume + 1;
                if (generation == 2 && hold_gen[0] == 2)
                    boundary_new_consume <= boundary_new_consume + 1;
                if (generation == 2 &&
                    (boundary_old_consume + boundary_new_consume) < 8)
                    $display("TRACE case=%0d t=%0t st=14 gen=%0d cur=%06h hold_gen=%0d hold=%02h req=%0d issue=%0d resp=%0d fifo=%0d",
                             CASE_ID, $time, generation, dut.cur_addr,
                             hold_gen[0], rom_data, request_count,
                             issue_count, response_count, fifo_count);
            end
            if (cen && dut.st == 4'd15 && dut.cur_ch == 4'd0)
                mixer_commit_count <= mixer_commit_count + 1;
            if (dut.sample && generation <= 2) begin
                output_strobes[generation] <= output_strobes[generation] + 1;
                if (dut.snd_left != 0 || dut.snd_right != 0) begin
                    output_nonzero[generation] <= output_nonzero[generation] + 1;
                    output_abs_sum[generation] <= output_abs_sum[generation] +
                        (dut.snd_left < 0 ? -dut.snd_left : dut.snd_left) +
                        (dut.snd_right < 0 ? -dut.snd_right : dut.snd_right);
                    if (output_first_nonzero[generation] == 0)
                        output_first_nonzero[generation] <= $time;
                    output_last_nonzero[generation] <= $time;
                end
            end
        end
    end

    final begin
        $display("SUMMARY case=%0d ab1=%0d ab2=%0d hold=1 gen=%0d req=%0d issue=%0d resp=%0d consume=%0d nonneutral=%0d mix=%0d old_at_gen2=%0d new_at_gen2=%0d max_fifo=%0d dropped=%0d overflow=%0d",
                 CASE_ID, AB1_MAME_SCRATCH, AB2_MAME_END, generation,
                 request_count, issue_count, response_count, consume_count,
                 nonneutral_consume, mixer_commit_count, boundary_old_consume,
                 boundary_new_consume, max_fifo_count, dropped, overflow);
        $display("OUTPUT case=%0d gen1 strobes=%0d nonzero=%0d abs=%0d first=%0t last=%0t; gen2 strobes=%0d nonzero=%0d abs=%0d first=%0t last=%0t",
                 CASE_ID, output_strobes[1], output_nonzero[1],
                 output_abs_sum[1], output_first_nonzero[1],
                 output_last_nonzero[1], output_strobes[2],
                 output_nonzero[2], output_abs_sum[2],
                 output_first_nonzero[2], output_last_nonzero[2]);
    end
endmodule

module tb_jtoutrun_pcm_tryz_generation;
    localparam integer CLK_HZ = 20_000_000;
    logic clk = 0, reset = 1;
    logic [31:0] accum = 0;
    logic cen = 0;
    logic [7:0] cpu_addr = 0, cpu_data = 0;
    logic cpu_cs = 0;
    integer sim_cycle = 0;
    integer old_count [0:3], new_count [0:3];
    integer dropped [0:3], overflow [0:3], generation [0:3];
    integer nonneutral [0:3];

    always #25 clk = ~clk;
    always @(posedge clk) begin
        sim_cycle <= sim_cycle + 1;
        if (reset) begin accum <= 0; cen <= 0; end
        else if (accum >= CLK_HZ-8_053_974) begin
            accum <= accum + 8_053_974-CLK_HZ; cen <= 1;
        end else begin accum <= accum + 8_053_974; cen <= 0; end
    end

`ifdef TRYZ_HOLD_ONLY
    tryz_generation_case #(.AB1_MAME_SCRATCH(1),
        .AB2_MAME_END(1),.CASE_ID(3)) d(
        .clk(clk),.reset(reset),.cen(cen),.cpu_addr(cpu_addr),
        .cpu_data(cpu_data),.cpu_cs(cpu_cs),.generation(generation[3]),
        .boundary_old_consume(old_count[3]),.boundary_new_consume(new_count[3]),
        .nonneutral_consume(nonneutral[3]),
        .dropped(dropped[3]),.overflow(overflow[3]));
`else
    tryz_generation_case #(.CASE_ID(0)) a(
        .clk(clk),.reset(reset),.cen(cen),.cpu_addr(cpu_addr),
        .cpu_data(cpu_data),.cpu_cs(cpu_cs),.generation(generation[0]),
        .boundary_old_consume(old_count[0]),.boundary_new_consume(new_count[0]),
        .nonneutral_consume(nonneutral[0]),
        .dropped(dropped[0]),.overflow(overflow[0]));
    tryz_generation_case #(.AB1_MAME_SCRATCH(1),.CASE_ID(1)) b(
        .clk(clk),.reset(reset),.cen(cen),.cpu_addr(cpu_addr),
        .cpu_data(cpu_data),.cpu_cs(cpu_cs),.generation(generation[1]),
        .boundary_old_consume(old_count[1]),.boundary_new_consume(new_count[1]),
        .nonneutral_consume(nonneutral[1]),
        .dropped(dropped[1]),.overflow(overflow[1]));
    tryz_generation_case #(.AB2_MAME_END(1),.CASE_ID(2)) c(
        .clk(clk),.reset(reset),.cen(cen),.cpu_addr(cpu_addr),
        .cpu_data(cpu_data),.cpu_cs(cpu_cs),.generation(generation[2]),
        .boundary_old_consume(old_count[2]),.boundary_new_consume(new_count[2]),
        .nonneutral_consume(nonneutral[2]),
        .dropped(dropped[2]),.overflow(overflow[2]));
    tryz_generation_case #(.AB1_MAME_SCRATCH(1),
        .AB2_MAME_END(1),.CASE_ID(3)) d(
        .clk(clk),.reset(reset),.cen(cen),.cpu_addr(cpu_addr),
        .cpu_data(cpu_data),.cpu_cs(cpu_cs),.generation(generation[3]),
        .boundary_old_consume(old_count[3]),.boundary_new_consume(new_count[3]),
        .nonneutral_consume(nonneutral[3]),
        .dropped(dropped[3]),.overflow(overflow[3]));
`endif

    task automatic write_reg(input [7:0] addr,input [7:0] data);
        begin
            @(negedge clk); cpu_addr=addr;
            cpu_data=(addr[7]&&addr[2:0]==6)?
                     {1'b0,data[5:3],1'b0,data[2:0]}:data;
            cpu_cs=1;
`ifdef TRYZ_HOLD_ONLY
            $display("CPUWRITE t=%0t addr=%02h data=%02h jt_ch=%0d st=%0d wb_valid=%0d wb_ch=%0d wb_addr=%06h cfg_we=%0d cfg_addr=%03h cfg_din=%02h",
                     $time, addr, data, d.dut.cur_ch, d.dut.st,
                     d.dut.wb_cur_valid_i, d.dut.wb_cur_ch_i,
                     d.dut.wb_cur_addr_i, d.dut.cfg_we,
                     d.dut.cfg_ram_addr, d.dut.cfg_din);
`endif
            @(negedge clk); cpu_cs=0;
        end
    endtask
    task automatic advance_to(input integer rel_vgm_sample);
        longint target;
        begin
            target=(longint'(rel_vgm_sample)*CLK_HZ)/44100;
            while(sim_cycle<target)@(negedge clk);
        end
    endtask

    initial begin
        repeat(8)@(posedge clk); @(negedge clk); reset=0; sim_cycle=0;
        // Generation 1, VGM samples 101649..101653.
        advance_to(0); write_reg(8'h00,8'h42);
        advance_to(1); write_reg(8'h02,8'h26);
        advance_to(2); write_reg(8'h03,8'h26); write_reg(8'h04,8'h00);
        advance_to(3); write_reg(8'h84,8'h00); write_reg(8'h05,8'hd1);
        write_reg(8'h85,8'hd1);
        advance_to(4); write_reg(8'h06,8'he1); write_reg(8'h07,8'h85);
        write_reg(8'h86,8'h8a);
        // Generation 2, VGM samples 106180..106184.
        advance_to(4531); write_reg(8'h00,8'h43);
        advance_to(4532); write_reg(8'h02,8'h2c); write_reg(8'h03,8'h2c);
        advance_to(4533); write_reg(8'h04,8'h00); write_reg(8'h84,8'h00);
        advance_to(4534); write_reg(8'h05,8'he2); write_reg(8'h85,8'he2);
        write_reg(8'h06,8'hed);
        advance_to(4535); write_reg(8'h86,8'h8a);
        // Keep eight ch0 update slots after the second generation boundary.
        repeat(5500)@(posedge clk);
`ifdef TRYZ_HOLD_ONLY
        if(dropped[3]!=0||overflow[3]!=0)$fatal(1,"hold queue loss");
        if(old_count[3]!=1)$fatal(1,"hold old generation count got %0d",old_count[3]);
        if(new_count[3]<7)$fatal(1,"hold new generation did not continue");
`else
        for(integer k=0;k<4;k=k+1)begin
            if(dropped[k]!=0||overflow[k]!=0)$fatal(1,"queue loss case %0d",k);
            if(old_count[k]!=1)$fatal(1,"old generation count case %0d got %0d",k,old_count[k]);
            if(new_count[k]<7)$fatal(1,"new generation did not continue case %0d",k);
        end
`endif
        $display("PASS tb_jtoutrun_pcm_tryz_generation");
        $finish;
    end
endmodule
