`timescale 1ns/1ps

// Galaxy Force II, "Beyond the Galaxy", first ch1/ch2 bass overlap:
//   ch1 commit 97.515442 s, full ROM 0x11BB00, JT-mapped ROM 0x1BB00
//   ch2 active at full ROM 0x00EA00, JT-mapped ROM 0x0EA00
// ROM bytes below come directly from the VGM type-0x80 payloads.
module galaxy_force_pcm_case #(
    parameter bit ENABLE_CH1 = 1'b1,
    parameter bit ENABLE_CH2 = 1'b1,
    parameter bit TRACE = 1'b0,
    parameter integer ROM_LATENCY_CYCLES = 50
) (
    input logic clk,
    input logic reset,
    input logic cen
);
    reg rom_ok = 1'b0;
    reg [3:0] last_request_ch = 4'hf;
    reg [18:0] last_request_addr = 19'd0;
    reg [3:0] last_return_ch = 4'hf;
    reg [7:0] last_return_sample = 8'h80;
    reg last_return_accepted = 1'b0;
    reg [7:0] tagged_hold_ch1 = 8'h80;
    reg [7:0] tagged_hold_ch2 = 8'h80;
    wire [7:0] rom_data =
        (dut.cur_ch == 4'd1) ? tagged_hold_ch1 :
        (dut.cur_ch == 4'd2) ? tagged_hold_ch2 : 8'h80;
    wire [18:0] rom_addr;
    wire rom_cs;
    reg rom_cs_d = 1'b0;

    reg response_valid [0:ROM_LATENCY_CYCLES];
    reg [18:0] response_addr [0:ROM_LATENCY_CYCLES];
    reg [3:0] response_ch [0:ROM_LATENCY_CYCLES];
    integer pipe_i;
    integer ram_i;
    integer trace_frame = 0;

    integer req_count_ch1 = 0;
    integer req_count_ch2 = 0;
    integer ret_count_ch1 = 0;
    integer ret_count_ch2 = 0;
    integer contrib_count_ch1 = 0;
    integer contrib_count_ch2 = 0;
    integer mix_count = 0;
    integer mix_peak = 0;
    integer mix_clip_count = 0;
    integer rejected_return_count = 0;

    reg [18:0] req_addr_ch1 [0:63];
    reg [18:0] req_addr_ch2 [0:63];
    reg [7:0] ret_data_ch1 [0:63];
    reg [7:0] ret_data_ch2 [0:63];
    reg signed [15:0] contrib_ch1 [0:63];
    reg signed [15:0] contrib_ch2 [0:63];

    function automatic [7:0] actual_rom_byte(input [18:0] addr);
        integer index;
        begin
            actual_rom_byte = 8'h80;
            if (addr >= 19'h1bb00 && addr < 19'h1bb40) begin
                index = addr - 19'h1bb00;
                case (index)
                    0:actual_rom_byte=8'h6a; 1:actual_rom_byte=8'h67;
                    2:actual_rom_byte=8'h65; 3:actual_rom_byte=8'h62;
                    4:actual_rom_byte=8'h5e; 5:actual_rom_byte=8'h59;
                    6:actual_rom_byte=8'h54; 7:actual_rom_byte=8'h4f;
                    8:actual_rom_byte=8'h4b; 9:actual_rom_byte=8'h47;
                    10:actual_rom_byte=8'h45; 11:actual_rom_byte=8'h42;
                    12:actual_rom_byte=8'h3d; 13:actual_rom_byte=8'h37;
                    14:actual_rom_byte=8'h32; 15:actual_rom_byte=8'h2d;
                    16:actual_rom_byte=8'h29; 17:actual_rom_byte=8'h27;
                    18:actual_rom_byte=8'h26; 19:actual_rom_byte=8'h23;
                    20:actual_rom_byte=8'h22; 21:actual_rom_byte=8'h21;
                    22:actual_rom_byte=8'h20; 23:actual_rom_byte=8'h1e;
                    24:actual_rom_byte=8'h1d; 25:actual_rom_byte=8'h1e;
                    26:actual_rom_byte=8'h20; 27:actual_rom_byte=8'h23;
                    28:actual_rom_byte=8'h1a; 29:actual_rom_byte=8'h0e;
                    30:actual_rom_byte=8'h0d; 31:actual_rom_byte=8'h08;
                    32:actual_rom_byte=8'h03; 33:actual_rom_byte=8'h01;
                    34:actual_rom_byte=8'h03; 35:actual_rom_byte=8'h00;
                    36:actual_rom_byte=8'h00; 37:actual_rom_byte=8'h00;
                    38:actual_rom_byte=8'h00; 39:actual_rom_byte=8'h00;
                    40:actual_rom_byte=8'h00; 41:actual_rom_byte=8'h02;
                    42:actual_rom_byte=8'h08; 43:actual_rom_byte=8'h13;
                    44:actual_rom_byte=8'h19; 45:actual_rom_byte=8'h27;
                    46:actual_rom_byte=8'h21; 47:actual_rom_byte=8'h24;
                    48:actual_rom_byte=8'h2c; 49:actual_rom_byte=8'h37;
                    50:actual_rom_byte=8'h3f; 51:actual_rom_byte=8'h3c;
                    52:actual_rom_byte=8'h53; 53:actual_rom_byte=8'h3f;
                    54:actual_rom_byte=8'h40; 55:actual_rom_byte=8'h66;
                    56:actual_rom_byte=8'h64; 57:actual_rom_byte=8'h49;
                    58:actual_rom_byte=8'h43; 59:actual_rom_byte=8'h50;
                    60:actual_rom_byte=8'h76; 61:actual_rom_byte=8'h85;
                    62:actual_rom_byte=8'ha7; 63:actual_rom_byte=8'h91;
                endcase
            end else if (addr >= 19'h0ea00 && addr < 19'h0ea40) begin
                index = addr - 19'h0ea00;
                case (index)
                    0:actual_rom_byte=8'h80; 1:actual_rom_byte=8'h80;
                    2:actual_rom_byte=8'h80; 3:actual_rom_byte=8'h81;
                    4:actual_rom_byte=8'h7f; 5:actual_rom_byte=8'h7b;
                    6:actual_rom_byte=8'h88; 7:actual_rom_byte=8'h7f;
                    8:actual_rom_byte=8'h79; 9:actual_rom_byte=8'h7d;
                    10:actual_rom_byte=8'h7d; 11:actual_rom_byte=8'h84;
                    12:actual_rom_byte=8'h7f; 13:actual_rom_byte=8'h70;
                    14:actual_rom_byte=8'h6b; 15:actual_rom_byte=8'h69;
                    16:actual_rom_byte=8'h8b; 17:actual_rom_byte=8'h5c;
                    18:actual_rom_byte=8'hb3; 19:actual_rom_byte=8'h6e;
                    20:actual_rom_byte=8'h71; 21:actual_rom_byte=8'h7d;
                    22:actual_rom_byte=8'ha6; 23:actual_rom_byte=8'h82;
                    24:actual_rom_byte=8'h6c; 25:actual_rom_byte=8'h57;
                    26:actual_rom_byte=8'ha2; 27:actual_rom_byte=8'h83;
                    28:actual_rom_byte=8'h7e; 29:actual_rom_byte=8'h5e;
                    30:actual_rom_byte=8'h5f; 31:actual_rom_byte=8'h84;
                    32:actual_rom_byte=8'h73; 33:actual_rom_byte=8'h98;
                    34:actual_rom_byte=8'h61; 35:actual_rom_byte=8'h82;
                    36:actual_rom_byte=8'h70; 37:actual_rom_byte=8'h81;
                    38:actual_rom_byte=8'h93; 39:actual_rom_byte=8'h86;
                    40:actual_rom_byte=8'h84; 41:actual_rom_byte=8'h91;
                    42:actual_rom_byte=8'h78; 43:actual_rom_byte=8'ha0;
                    44:actual_rom_byte=8'h9a; 45:actual_rom_byte=8'h84;
                    46:actual_rom_byte=8'h99; 47:actual_rom_byte=8'h8b;
                    48:actual_rom_byte=8'h8e; 49:actual_rom_byte=8'h9b;
                    50:actual_rom_byte=8'h96; 51:actual_rom_byte=8'h8f;
                    52:actual_rom_byte=8'h88; 53:actual_rom_byte=8'ha5;
                    54:actual_rom_byte=8'h7c; 55:actual_rom_byte=8'h91;
                    56:actual_rom_byte=8'h95; 57:actual_rom_byte=8'h85;
                    58:actual_rom_byte=8'ha4; 59:actual_rom_byte=8'h7b;
                    60:actual_rom_byte=8'hb6; 61:actual_rom_byte=8'h6e;
                    62:actual_rom_byte=8'h9d; 63:actual_rom_byte=8'haa;
                endcase
            end
        end
    endfunction

    initial begin
        for (ram_i = 0; ram_i < 512; ram_i = ram_i + 1)
            dut.u_ram.mem[ram_i] = 8'hff;
        for (pipe_i = 0; pipe_i <= ROM_LATENCY_CYCLES; pipe_i = pipe_i + 1) begin
            response_valid[pipe_i] = 1'b0;
            response_addr[pipe_i] = 19'd0;
            response_ch[pipe_i] = 4'd0;
        end
        #1;
        // ch1, raw ctrl 0x8a transformed by MegaVGMDrive to JT ctrl 0x12.
        dut.u_ram.mem[9'h008] = 8'h41;
        dut.u_ram.mem[9'h00a] = 8'h24;
        dut.u_ram.mem[9'h00b] = 8'h24;
        dut.u_ram.mem[9'h00c] = 8'h00;
        dut.u_ram.mem[9'h00d] = 8'hbb;
        dut.u_ram.mem[9'h00e] = 8'hd0;
        dut.u_ram.mem[9'h00f] = 8'h6e;
        dut.u_ram.mem[9'h08c] = 8'h00;
        dut.u_ram.mem[9'h08d] = 8'hbb;
        dut.u_ram.mem[9'h08e] = ENABLE_CH1 ? 8'h12 : 8'h13;

        // ch2 state immediately before the 97.515442 s ch1 retrigger.
        dut.u_ram.mem[9'h010] = 8'h06;
        dut.u_ram.mem[9'h012] = 8'h29;
        dut.u_ram.mem[9'h013] = 8'h0f;
        dut.u_ram.mem[9'h014] = 8'h00;
        dut.u_ram.mem[9'h015] = 8'hea;
        dut.u_ram.mem[9'h016] = 8'hf1;
        dut.u_ram.mem[9'h017] = 8'ha0;
        dut.u_ram.mem[9'h094] = 8'h00;
        dut.u_ram.mem[9'h095] = 8'hea;
        dut.u_ram.mem[9'h096] = ENABLE_CH2 ? 8'h02 : 8'h03;
    end

    always @(posedge clk) begin
        rom_ok <= 1'b0;
        last_return_accepted <= 1'b0;
        rom_cs_d <= rom_cs;
        for (pipe_i = ROM_LATENCY_CYCLES; pipe_i > 0; pipe_i = pipe_i - 1) begin
            response_valid[pipe_i] <= response_valid[pipe_i-1];
            response_addr[pipe_i] <= response_addr[pipe_i-1];
            response_ch[pipe_i] <= response_ch[pipe_i-1];
        end
        response_valid[0] <= rom_cs && !rom_cs_d;
        response_addr[0] <= rom_addr;
        response_ch[0] <= dut.cur_ch;

        if (rom_cs && !rom_cs_d) begin
            last_request_ch <= dut.cur_ch;
            last_request_addr <= rom_addr;
            if (dut.cur_ch == 4'd1) begin
                req_addr_ch1[req_count_ch1] <= rom_addr;
                req_count_ch1 <= req_count_ch1 + 1;
            end else if (dut.cur_ch == 4'd2) begin
                req_addr_ch2[req_count_ch2] <= rom_addr;
                req_count_ch2 <= req_count_ch2 + 1;
            end
        end

        if (response_valid[ROM_LATENCY_CYCLES]) begin
            last_return_ch <= response_ch[ROM_LATENCY_CYCLES];
            last_return_sample <= actual_rom_byte(response_addr[ROM_LATENCY_CYCLES]);
            // The returned request tag owns the response. Route it only to
            // that channel's hold; a later live request cannot retag it.
            rom_ok <= 1'b1;
            last_return_accepted <= 1'b1;
            if (response_ch[ROM_LATENCY_CYCLES] == 4'd1) begin
                tagged_hold_ch1 <= actual_rom_byte(response_addr[ROM_LATENCY_CYCLES]);
                ret_data_ch1[ret_count_ch1] <=
                    actual_rom_byte(response_addr[ROM_LATENCY_CYCLES]);
                ret_count_ch1 <= ret_count_ch1 + 1;
            end else if (response_ch[ROM_LATENCY_CYCLES] == 4'd2) begin
                tagged_hold_ch2 <= actual_rom_byte(response_addr[ROM_LATENCY_CYCLES]);
                ret_data_ch2[ret_count_ch2] <=
                    actual_rom_byte(response_addr[ROM_LATENCY_CYCLES]);
                ret_count_ch2 <= ret_count_ch2 + 1;
            end else begin
                $fatal(1, "response without a registered channel owner");
            end
        end

        if (!reset && cen && dut.st == 4'd15) begin
            if (dut.cur_ch == 4'd1) begin
                contrib_ch1[contrib_count_ch1] <= dut.mul_data;
                contrib_count_ch1 <= contrib_count_ch1 + 1;
            end else if (dut.cur_ch == 4'd2) begin
                contrib_ch2[contrib_count_ch2] <= dut.mul_data;
                contrib_count_ch2 <= contrib_count_ch2 + 1;
            end
        end

        if (!reset && dut.sample) begin : capture_mix
            integer magnitude;
            magnitude = dut.snd_left < 0 ? -dut.snd_left : dut.snd_left;
            mix_count <= mix_count + 1;
            if (magnitude > mix_peak)
                mix_peak <= magnitude;
            if (dut.snd_left == 16'sh7fff || dut.snd_left == -16'sh8000)
                mix_clip_count <= mix_clip_count + 1;
        end

        if (TRACE && !reset && trace_frame < 2 && cen &&
            (dut.cur_ch == 4'd1 || dut.cur_ch == 4'd2)) begin
            $display("TRACE t=%0t cen=%b st=%0d ch=%0d req_ch=%0d ret_ch=%0d accepted=%b rom=%05h cs=%b ok=%b returned=%02h cur_before=%06h cur_after=%06h delta=%02h global_hold=%02h hold_ch1=%02h hold_ch2=%02h mix_l=%0d mix_r=%0d",
                     $time, cen, dut.st, dut.cur_ch,
                     last_request_ch, last_return_ch, last_return_accepted,
                     rom_addr, rom_cs, rom_ok, last_return_sample,
                     dut.cur_addr, dut.cur_addr + {16'd0, dut.delta}, dut.delta,
                     rom_data, tagged_hold_ch1, tagged_hold_ch2,
                     $signed(dut.mul_data), $signed(dut.buf_r));
            if (dut.cur_ch == 4'd2 && dut.st == 4'd15)
                trace_frame <= trace_frame + 1;
        end
    end

    jtoutrun_pcm dut (
        .rst(reset), .clk(clk), .cen(cen), .debug_bus(8'd0),
        .cpu_addr(8'd0), .cpu_dout(8'd0), .cpu_rnw(1'b0), .cpu_cs(1'b0),
        .smoke_variant(3'd0), .smoke_ddr_follow_mode(1'b0),
        .smoke_ddr_follow_init_enable(1'b0), .smoke_ddr_follow_delta_sel(3'd0),
        .smoke_c0_use_sel(2'd0), .smoke_c0_sample_mode(2'd0),
        .smoke_c0_delta(8'd0), .smoke_c0_vol_l(7'd0), .smoke_c0_vol_r(7'd0),
        .smoke_c0_raw_audible(1'b0), .smoke_c0_drive_sel(2'd0),
        .smoke_c0_seed_pulse(1'b0), .smoke_c0_endcmp_sel(2'd0),
        .smoke_c0_loopsrc_sel(2'd0), .smoke_c0_current_seed(24'd0),
        .smoke_c0_loop_seed(24'd0), .smoke_c0_end_addr(8'd0),
        .smoke_c0_ctrl(8'd0), .rom_addr(rom_addr), .rom_data(rom_data),
        .rom_ok(rom_ok), .rom_cs(rom_cs)
    );
endmodule


module tb_jtoutrun_pcm_galaxy_force_ch12_overlap;
    logic clk = 1'b0;
    logic reset = 1'b1;
    wire cen;
    integer timeout;
    integer i;
    integer first_diff_ch1 = -1;
    integer first_diff_ch2 = -1;

    always #25 clk = ~clk;

    segapcm_fractional_cen #(
        .CLK_SYS_HZ(32'd20_000_000),
        .TARGET_HZ(32'd8_053_974)
    ) cen_gen (.clk(clk), .reset(reset), .cen(cen));

    galaxy_force_pcm_case #(.ENABLE_CH1(1), .ENABLE_CH2(0)) ch1_only(
        .clk(clk), .reset(reset), .cen(cen));
    galaxy_force_pcm_case #(.ENABLE_CH1(0), .ENABLE_CH2(1)) ch2_only(
        .clk(clk), .reset(reset), .cen(cen));
    galaxy_force_pcm_case #(.ENABLE_CH1(1), .ENABLE_CH2(1), .TRACE(1)) both(
        .clk(clk), .reset(reset), .cen(cen));

    initial begin
        repeat (8) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        begin : wait_capture
            for (timeout = 0; timeout < 200000; timeout = timeout + 1) begin
                @(negedge clk);
                if (ch1_only.contrib_count_ch1 >= 16 &&
                    ch2_only.contrib_count_ch2 >= 16 &&
                    both.contrib_count_ch1 >= 16 && both.contrib_count_ch2 >= 16)
                    disable wait_capture;
            end
            $display("FAIL capture timeout");
            $fatal(1);
        end

        for (i = 0; i < 16; i = i + 1) begin
            if (ch1_only.req_addr_ch1[i] !== both.req_addr_ch1[i]) begin
                $display("FAIL ch1 address progression i=%0d single=%05h both=%05h",
                         i, ch1_only.req_addr_ch1[i], both.req_addr_ch1[i]);
                $fatal(1);
            end
            if (ch2_only.req_addr_ch2[i] !== both.req_addr_ch2[i]) begin
                $display("FAIL ch2 address progression i=%0d single=%05h both=%05h",
                         i, ch2_only.req_addr_ch2[i], both.req_addr_ch2[i]);
                $fatal(1);
            end
            if (ch1_only.ret_data_ch1[i] !== both.ret_data_ch1[i] ||
                ch2_only.ret_data_ch2[i] !== both.ret_data_ch2[i]) begin
                $display("FAIL tagged ROM return sequence i=%0d", i);
                $fatal(1);
            end
            if (first_diff_ch1 < 0 &&
                ch1_only.contrib_ch1[i] !== both.contrib_ch1[i])
                first_diff_ch1 = i;
            if (first_diff_ch2 < 0 &&
                ch2_only.contrib_ch2[i] !== both.contrib_ch2[i])
                first_diff_ch2 = i;
        end

        if (first_diff_ch1 >= 0 || first_diff_ch2 >= 0) begin
            $display("FAIL overlap changed per-channel waveform ch1_diff=%0d ch2_diff=%0d",
                     first_diff_ch1, first_diff_ch2);
            $fatal(1);
        end
        if (both.rejected_return_count != 0) begin
            $display("FAIL corrected ownership rejected %0d returns",
                     both.rejected_return_count);
            $fatal(1);
        end
        if (both.mix_clip_count != 0) begin
            $display("FAIL unexpected mixer clipping count=%0d", both.mix_clip_count);
            $fatal(1);
        end

        $display("FIXED first_diff ch1_update=%0d ch2_update=%0d", first_diff_ch1,
                 first_diff_ch2);
        $display("FIXED address_and_tagged_rom_sequences_match=1 rejected_returns=%0d mix_clip=0 peak=%0d",
                 both.rejected_return_count, both.mix_peak);
        $display("PASS tb_jtoutrun_pcm_galaxy_force_ch12_overlap");
        $finish;
    end
endmodule
