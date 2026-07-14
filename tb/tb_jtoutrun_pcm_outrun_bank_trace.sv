`timescale 1ns/1ps

// Splash Wave's first SegaPCM voice through the interface-aware mapper, JT,
// request queue, single response owner, per-channel Hold, mixer and audio.
module tb_jtoutrun_pcm_outrun_bank_trace;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [7:0] cpu_addr = 8'd0;
    logic [7:0] cpu_dout = 8'd0;
    logic cpu_cs = 1'b0;
    wire [18:0] rom_addr;
    wire rom_cs;
    wire signed [15:0] snd_left;
    wire signed [15:0] snd_right;
    wire sample;

    logic core_rom_cs_d = 1'b0;
    logic [18:0] core_rom_addr_d = 19'd0;
    logic [7:0] sample_hold [0:15];
    logic [15:0] sample_hold_valid = 16'd0;
    logic fifo_valid = 1'b0;
    logic [3:0] fifo_ch = 4'd0;
    logic [18:0] fifo_addr = 19'd0;
    logic owner_valid = 1'b0;
    logic [3:0] owner_ch = 4'd0;
    logic [18:0] owner_addr = 19'd0;
    logic [2:0] response_delay = 3'd0;

    integer request_event_count = 0;
    integer fifo_push_count = 0;
    integer fifo_pop_count = 0;
    integer ddr_accept_count = 0;
    integer ddr_response_count = 0;
    integer hold_update_count = 0;
    integer consume_count = 0;
    integer mixer_nonzero_count = 0;
    integer audio_nonzero_count = 0;
    integer timeout;
    integer i;

    wire [7:0] outrun_jt_control;
    wire [20:0] outrun_full_bank;
    wire [7:0] galaxy_jt_control;
    wire [20:0] galaxy_full_bank;

    wire [3:0] request_ch = dut.dbg_bank_channel_state[7:4];
    wire request_event = rom_cs &&
        (!core_rom_cs_d || (rom_addr != core_rom_addr_d));
    // Splash Wave type80 block 3: [0x43be6, 0x48000).
    wire payload_match = (rom_addr >= 19'h43be6) &&
                         ({1'b0, rom_addr} < 20'h48000);
    wire fifo_push = request_event && payload_match;
    wire [7:0] jt_rom_data = sample_hold_valid[dut.cur_ch] ?
                             sample_hold[dut.cur_ch] : 8'h80;
    wire jt_rom_ok = sample_hold_valid[dut.cur_ch];

    function automatic [7:0] splash_rom_byte(input [18:0] addr);
        begin
            case (addr)
                19'h43be6: splash_rom_byte = 8'h7f;
                19'h43be7: splash_rom_byte = 8'h85;
                19'h43be8: splash_rom_byte = 8'h82;
                19'h43be9: splash_rom_byte = 8'h7b;
                default:   splash_rom_byte = 8'h89;
            endcase
        end
    endfunction

    always #25 clk = ~clk;

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

    always @(posedge clk) begin
        core_rom_cs_d <= rom_cs;
        core_rom_addr_d <= rom_addr;
        if (!reset && request_event && request_ch == 4'd1) begin
            request_event_count <= request_event_count + 1;
            if (fifo_push) begin
                if (fifo_valid)
                    $fatal(1, "diagnostic FIFO overflow");
                fifo_push_count <= fifo_push_count + 1;
                fifo_valid <= 1'b1;
                fifo_ch <= request_ch;
                fifo_addr <= rom_addr;
            end
            $display("TRACE request t=%0t ch=%0d st=%0d addr=%05h match=%0d fifo_push=%0d",
                     $time, request_ch, dut.st, rom_addr,
                     payload_match, fifo_push);
        end
        if (!reset && fifo_valid && !owner_valid) begin
            fifo_valid <= 1'b0;
            fifo_pop_count <= fifo_pop_count + 1;
            ddr_accept_count <= ddr_accept_count + 1;
            owner_valid <= 1'b1;
            owner_ch <= fifo_ch;
            owner_addr <= fifo_addr;
            response_delay <= 3'd2;
            $display("TRACE ddr_accept t=%0t ch=%0d addr=%05h payload=%05h",
                     $time, fifo_ch, fifo_addr,
                     19'h02d09 + (fifo_addr - 19'h43be6));
        end
        if (!reset && owner_valid) begin
            if (response_delay != 3'd0) begin
                response_delay <= response_delay - 3'd1;
            end else begin
                ddr_response_count <= ddr_response_count + 1;
                hold_update_count <= hold_update_count + 1;
                sample_hold[owner_ch] <= splash_rom_byte(owner_addr);
                sample_hold_valid[owner_ch] <= 1'b1;
                owner_valid <= 1'b0;
                $display("TRACE ddr_response t=%0t owner_ch=%0d addr=%05h data=%02h hold_update=1",
                         $time, owner_ch, owner_addr,
                         splash_rom_byte(owner_addr));
            end
        end
        if (!reset && dut.cen && dut.st == 4'd14 && dut.cur_ch == 4'd1) begin
            consume_count <= consume_count + 1;
            if (dut.pcm_data != 0)
                mixer_nonzero_count <= mixer_nonzero_count + 1;
            $display("TRACE consume t=%0t ch=%0d st=%0d hold_valid=%0d hold=%02h jt_data=%02h jt_ok=%0d mul=%0d",
                     $time, dut.cur_ch, dut.st, sample_hold_valid[1],
                     sample_hold[1], jt_rom_data, jt_rom_ok,
                     $signed(dut.pcm_data));
        end
        if (!reset && sample && ((snd_left != 0) || (snd_right != 0)))
            audio_nonzero_count <= audio_nonzero_count + 1;
    end

    segapcm_jt_control_mapper outrun_mapper (
        .segapcm_interface(32'h0000_000c),
        .raw_control(8'hc2),
        .jt_control(outrun_jt_control),
        .full_bank(outrun_full_bank)
    );

    segapcm_jt_control_mapper galaxy_mapper (
        .segapcm_interface(32'h00f8_000d),
        .raw_control(8'h8a),
        .jt_control(galaxy_jt_control),
        .full_bank(galaxy_full_bank)
    );

    jtoutrun_pcm #(
        .MAME_SCRATCH_CURRENT(1'b1),
        .MAME_NONLOOP_END(1'b1)
    ) dut (
        .rst(reset), .clk(clk), .cen(1'b1), .debug_bus(8'd0),
        .cpu_addr(cpu_addr), .cpu_dout(cpu_dout), .cpu_rnw(1'b0),
        .cpu_cs(cpu_cs), .rom_addr(rom_addr), .rom_data(jt_rom_data),
        .rom_ok(jt_rom_ok), .rom_cs(rom_cs),
        .snd_left(snd_left), .snd_right(snd_right), .sample(sample),
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
        for (i = 0; i < 16; i = i + 1)
            sample_hold[i] = 8'h80;
        for (i = 0; i < 512; i = i + 1)
            dut.u_ram.mem[i] = 8'hff;

        #1;
        if (outrun_jt_control !== 8'h42 ||
            outrun_full_bank !== 21'h040000)
            $fatal(1, "OutRun mapping ctrl=%02h bank=%06h",
                   outrun_jt_control, outrun_full_bank);
        if (galaxy_jt_control !== 8'h12 ||
            galaxy_full_bank !== 21'h110000)
            $fatal(1, "Galaxy mapping ctrl=%02h bank=%06h",
                   galaxy_jt_control, galaxy_full_bank);

        // Exact first ch1 C0 sequence from Splash Wave.
        cpu_write(8'h08, 8'h00);
        cpu_write(8'h0a, 8'h27);
        cpu_write(8'h0b, 8'h28);
        cpu_write(8'h0c, 8'he6);
        cpu_write(8'h8c, 8'he6);
        cpu_write(8'h0d, 8'h3b);
        cpu_write(8'h8d, 8'h3b);
        cpu_write(8'h0e, 8'h7f);
        cpu_write(8'h0f, 8'h90);
        cpu_write(8'h8e, outrun_jt_control);

        repeat (24) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        begin : wait_trace
            for (timeout = 0; timeout < 10000; timeout = timeout + 1) begin
                @(negedge clk);
                if (request_event_count >= 2 && ddr_response_count >= 2 &&
                    consume_count >= 2 && audio_nonzero_count >= 1)
                    disable wait_trace;
            end
            $fatal(1, "trace timeout request=%0d consume=%0d",
                   request_event_count, consume_count);
        end

        $display("SUMMARY request=%0d fifo_push=%0d fifo_pop=%0d ddr_accept=%0d ddr_response=%0d hold_update=%0d consume=%0d mixer_nonzero=%0d audio_nonzero=%0d",
                 request_event_count, fifo_push_count, fifo_pop_count,
                 ddr_accept_count, ddr_response_count, hold_update_count,
                 consume_count, mixer_nonzero_count, audio_nonzero_count);
        if (rom_addr < 19'h43be6 || fifo_push_count == 0 ||
            fifo_pop_count == 0 || ddr_accept_count == 0 ||
            ddr_response_count == 0 || hold_update_count == 0 ||
            !sample_hold_valid[1])
            $fatal(1, "OutRun payload path did not complete");
        if (mixer_nonzero_count == 0 || audio_nonzero_count == 0)
            $fatal(1, "OutRun sample did not reach audio");
        $display("PASS tb_jtoutrun_pcm_outrun_bank_trace");
        $finish;
    end
endmodule
