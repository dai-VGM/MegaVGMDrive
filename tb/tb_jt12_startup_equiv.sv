`timescale 1ps/1ps

// Original/patched equivalence regression.  The original modules are renamed
// to jt12_orig_* by scripts/run_jt12_startup_regression.sh and come from the
// clean pre-patch HEAD outside the working tree.
module tb_jt12_startup_equiv #(
    parameter integer NUM_CH = 3
);
    localparam integer SYS_CLK_HZ = 32_000_000;
    localparam integer CHIP_CLK_HZ = 4_000_000;
    localparam integer CEN_DIV = SYS_CLK_HZ / CHIP_CLK_HZ;
    localparam integer HALF_PS = 500_000_000_000 / SYS_CLK_HZ;
    localparam integer USE_LFO = NUM_CH == 6;
    localparam integer USE_PCM = NUM_CH == 6;
    localparam integer MASK_DIV = NUM_CH == 6;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cen = 1'b0;
    integer cen_count = 0;
    integer sys_cycle = 0;
    integer reset_internal_en = 0;

    logic [7:0] din = 8'h00;
    logic [1:0] addr = 2'b00;
    logic cs_n = 1'b1;
    logic wr_n = 1'b1;

    wire [7:0] dout_p, dout_o;
    wire signed [15:0] fm_l_p, fm_r_p, fm_l_o, fm_r_o;
    wire signed [15:0] snd_l_p, snd_r_p, snd_l_o, snd_r_o;
    wire snd_sample_p, snd_sample_o;
    wire [17:0] acc_probe_p, acc_probe_o;
    wire [17:0] snd_probe_p, snd_probe_o;

    bit strict_compare = 1'b0;
    integer compared_cycles = 0;
    integer compared_samples = 0;
    integer write_count = 0;
    logic [63:0] hash_p = 64'hcbf29ce484222325;
    logic [63:0] hash_o = 64'hcbf29ce484222325;

    always #(HALF_PS) clk = ~clk;

    always @(posedge clk) begin
        sys_cycle <= sys_cycle + 1;
        if (cen_count == CEN_DIV-1) begin
            cen <= 1'b1;
            cen_count <= 0;
        end else begin
            cen <= 1'b0;
            cen_count <= cen_count + 1;
        end
        if (rst && dut_o.clk_en)
            reset_internal_en <= reset_internal_en + 1;
    end

    jt12_top #(
        .use_lfo(USE_LFO), .use_ssg(0), .num_ch(NUM_CH),
        .use_pcm(USE_PCM), .use_adpcm(0), .JT49_DIV(2),
        .mask_div(MASK_DIV)
    ) dut_p (
        .rst(rst), .clk(clk), .cen(cen), .din(din), .addr(addr),
        .cs_n(cs_n), .wr_n(wr_n), .ladder(1'b0), .dout(dout_p),
        .en_hifi_pcm(1'b0), .adpcma_data(8'h00), .adpcmb_data(8'h00),
        .IOA_in(8'h00), .IOB_in(8'h00), .fm_snd_left(fm_l_p),
        .fm_snd_right(fm_r_p), .snd_left(snd_l_p), .snd_right(snd_r_p),
        .snd_sample(snd_sample_p), .debug_bus(8'h00)
    );

    jt12_orig_top #(
        .use_lfo(USE_LFO), .use_ssg(0), .num_ch(NUM_CH),
        .use_pcm(USE_PCM), .use_adpcm(0), .JT49_DIV(2),
        .mask_div(MASK_DIV)
    ) dut_o (
        .rst(rst), .clk(clk), .cen(cen), .din(din), .addr(addr),
        .cs_n(cs_n), .wr_n(wr_n), .ladder(1'b0), .dout(dout_o),
        .en_hifi_pcm(1'b0), .adpcma_data(8'h00), .adpcmb_data(8'h00),
        .IOA_in(8'h00), .IOB_in(8'h00), .fm_snd_left(fm_l_o),
        .fm_snd_right(fm_r_o), .snd_left(snd_l_o), .snd_right(snd_r_o),
        .snd_sample(snd_sample_o), .debug_bus(8'h00)
    );

    generate
    if( NUM_CH == 3 ) begin : gen_probe_3ch
        assign acc_probe_p = dut_p.gen_2203_acc.u_acc.u_mono.acc;
        assign acc_probe_o = dut_o.gen_2203_acc.u_acc.u_mono.acc;
        assign snd_probe_p = dut_p.gen_2203_acc.u_acc.u_mono.snd;
        assign snd_probe_o = dut_o.gen_2203_acc.u_acc.u_mono.snd;
    end else begin : gen_probe_6ch
        assign acc_probe_p = {{9{dut_p.gen_pcm_acc.accumulator_block[0].u_acc.u_acc.acc[8]}},
                              dut_p.gen_pcm_acc.accumulator_block[0].u_acc.u_acc.acc};
        assign acc_probe_o = {{9{dut_o.gen_pcm_acc.accumulator_block[0].u_acc.u_acc.acc[8]}},
                              dut_o.gen_pcm_acc.accumulator_block[0].u_acc.u_acc.acc};
        assign snd_probe_p = {{2{fm_l_p[15]}}, fm_l_p};
        assign snd_probe_o = {{2{fm_l_o[15]}}, fm_l_o};
    end
    endgenerate

    task automatic fail_now(input string reason);
        begin
            $display("FAIL NUM_CH=%0d cycle=%0d time=%0t reason=%s",
                     NUM_CH, sys_cycle, $time, reason);
            $fatal(1);
        end
    endtask

    task automatic bus_idle;
        begin
            @(negedge clk);
            addr = 2'b00;
            din = 8'h00;
            cs_n = 1'b1;
            wr_n = 1'b1;
        end
    endtask

    task automatic bus_pulse(input logic [1:0] bus_addr,
                             input logic [7:0] bus_data);
        begin
            @(negedge clk);
            addr = bus_addr;
            din = bus_data;
            cs_n = 1'b0;
            wr_n = 1'b0;
            @(posedge clk);
            @(negedge clk);
            addr = 2'b00;
            din = 8'h00;
            cs_n = 1'b1;
            wr_n = 1'b1;
        end
    endtask

    task automatic opn_write(input logic [7:0] reg_addr,
                             input logic [7:0] reg_data);
        integer timeout;
        begin
            bus_pulse(2'b00, reg_addr);
            @(posedge clk);
            bus_pulse(2'b01, reg_data);
            @(negedge clk);
            addr = 2'b00;
            cs_n = 1'b0;
            wr_n = 1'b1;
            timeout = 0;
            while (dout_p[7] !== 1'b1 || dout_o[7] !== 1'b1) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 256)
                    fail_now("busy assert timeout");
            end
            while (dout_p[7] !== 1'b0 || dout_o[7] !== 1'b0) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 4096)
                    fail_now("busy clear timeout");
            end
            write_count = write_count + 1;
            bus_idle();
        end
    endtask

    task automatic wait_samples(input integer count);
        integer seen;
        integer timeout;
        begin
            seen = 0;
            timeout = 0;
            while (seen < count) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (dut_p.clk_en && dut_p.zero)
                    seen = seen + 1;
                if (timeout > count*(NUM_CH == 6 ? 2048 : 1024) + 4096)
                    fail_now("sample wait timeout");
            end
        end
    endtask

    task automatic program_tone(input integer channel,
                                input logic [7:0] alg_fb,
                                input logic [7:0] fnum_hi,
                                input logic [7:0] fnum_lo);
        integer slot;
        begin
            opn_write(8'h28, channel[7:0]);
            for (slot = 0; slot < 4; slot = slot + 1) begin
                opn_write(8'h30 + slot*4 + channel, 8'h01);
                opn_write(8'h40 + slot*4 + channel, 8'h28);
                opn_write(8'h50 + slot*4 + channel, 8'h1f);
                opn_write(8'h60 + slot*4 + channel, 8'h00);
                opn_write(8'h70 + slot*4 + channel, 8'h00);
                opn_write(8'h80 + slot*4 + channel, 8'h0f);
                opn_write(8'h90 + slot*4 + channel, 8'h00);
            end
            opn_write(8'hA4 + channel, fnum_hi);
            opn_write(8'hA0 + channel, fnum_lo);
            opn_write(8'hB0 + channel, alg_fb);
            opn_write(8'h28, 8'hf0 | channel[7:0]);
        end
    endtask

    task automatic random_writes;
        logic [31:0] lfsr;
        logic [7:0] reg_addr;
        logic [7:0] reg_data;
        integer i;
        integer channel;
        integer slot;
        begin
            lfsr = 32'h1badf00d;
            for (i = 0; i < 32; i = i + 1) begin
                lfsr = {lfsr[30:0], lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
                channel = lfsr[17:16] % 3;
                slot = lfsr[19:18];
                case (i % 6)
                    0: reg_addr = 8'h30 + slot*4 + channel;
                    1: reg_addr = 8'h40 + slot*4 + channel;
                    2: reg_addr = 8'h50 + slot*4 + channel;
                    3: reg_addr = 8'h80 + slot*4 + channel;
                    4: reg_addr = 8'hA0 + channel;
                    default: reg_addr = 8'hB0 + channel;
                endcase
                reg_data = lfsr[15:8];
                if ((i % 6) == 5)
                    reg_data = {lfsr[13:11], lfsr[2:0]};
                opn_write(reg_addr, reg_data);
            end
        end
    endtask

    always @(posedge clk) begin : compare_cycle
        #1;
        if (strict_compare) begin
            compared_cycles = compared_cycles + 1;
            if ({dut_p.cur_ch,dut_p.cur_op,dut_p.zero,dut_p.op_result_hd,
                 acc_probe_p,snd_probe_p,fm_l_p,fm_r_p,snd_sample_p} !==
                {dut_o.cur_ch,dut_o.cur_op,dut_o.zero,dut_o.op_result_hd,
                 acc_probe_o,snd_probe_o,fm_l_o,fm_r_o,snd_sample_o})
                fail_now("cycle comparison mismatch");
            if ((^{dut_p.cur_ch,dut_p.cur_op,dut_p.zero,dut_p.op_result_hd,
                   acc_probe_p,snd_probe_p,fm_l_p,fm_r_p,snd_sample_p}) === 1'bx)
                fail_now("patched comparison signal became X/Z");
            if ((^{dut_o.cur_ch,dut_o.cur_op,dut_o.zero,dut_o.op_result_hd,
                   acc_probe_o,snd_probe_o,fm_l_o,fm_r_o,snd_sample_o}) === 1'bx)
                fail_now("original comparison signal became X/Z");
            if (dut_p.clk_en && dut_p.zero) begin
                compared_samples = compared_samples + 1;
                hash_p = (hash_p ^ {fm_l_p,fm_r_p}) * 64'h00000100000001b3;
                hash_o = (hash_o ^ {fm_l_o,fm_r_o}) * 64'h00000100000001b3;
            end
        end
    end

    generate
    if( NUM_CH == 6 ) begin : gen_compare_6ch_accumulators
        always @(posedge clk) begin : compare_accumulators
            integer i;
            #2;
            if (strict_compare) begin
                for (i = 0; i < 7; i = i + 1) begin
                    if (dut_p.gen_pcm_acc.accum_l[i] !== dut_o.gen_pcm_acc.accum_l[i] ||
                        dut_p.gen_pcm_acc.accum_r[i] !== dut_o.gen_pcm_acc.accum_r[i])
                        fail_now("YM2612 accumulator comparison mismatch");
                end
            end
        end
    end
    endgenerate

    initial begin : stimulus
        integer common_valid_count;
        integer common_timeout;

        // Prime the original resetless pipeline with an exact multiple of both
        // the 12-slot and 24-slot scheduler lengths.  The patched DUT receives
        // the identical reset and CEN stream.
        while (reset_internal_en < 72)
            @(posedge clk);
        while (!(dut_o.cur_ch === 3'd0 && dut_o.cur_op === 2'd0 &&
                 dut_o.zero === 1'b1))
            @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        common_valid_count = 0;
        common_timeout = 0;
        while (common_valid_count < 48) begin
            @(posedge clk);
            #2;
            common_timeout = common_timeout + 1;
            if (dut_p.clk_en) begin
                if ((^{dut_p.cur_ch,dut_p.cur_op,dut_p.zero,dut_p.op_result_hd,
                       acc_probe_p,snd_probe_p,fm_l_p,fm_r_p,
                       dut_o.cur_ch,dut_o.cur_op,dut_o.zero,dut_o.op_result_hd,
                       acc_probe_o,snd_probe_o,fm_l_o,fm_r_o}) !== 1'bx &&
                    {dut_p.cur_ch,dut_p.cur_op,dut_p.zero,dut_p.op_result_hd,
                     acc_probe_p,snd_probe_p,fm_l_p,fm_r_p} ===
                    {dut_o.cur_ch,dut_o.cur_op,dut_o.zero,dut_o.op_result_hd,
                     acc_probe_o,snd_probe_o,fm_l_o,fm_r_o})
                    common_valid_count = common_valid_count + 1;
                else
                    common_valid_count = 0;
            end
            if (common_timeout > 100_000)
                fail_now("no common valid boundary");
        end

        @(negedge clk);
        strict_compare = 1'b1;
        $display("COMMON_VALID NUM_CH=%0d cycle=%0d reset_internal_en=%0d",
                 NUM_CH, sys_cycle, reset_internal_en);

        // 1. Idle.
        wait_samples(32);

        // 2. Channel 0 tone, then 3. key-off.
        program_tone(0, 8'h07, 8'h22, 8'h69);
        wait_samples(128);
        opn_write(8'h28, 8'h00);
        wait_samples(96);

        // 4. Channel 1 tone.
        program_tone(1, 8'h07, 8'h21, 8'hb0);
        wait_samples(128);
        opn_write(8'h28, 8'h01);
        wait_samples(96);

        // 5. Different algorithm and feedback on channel 0.
        program_tone(0, 8'h2c, 8'h23, 8'h10);
        wait_samples(128);

        // 6. Fixed-seed deterministic OPN writes, followed by long-run hash.
        random_writes();
        wait_samples(512);

        if (hash_p !== hash_o)
            fail_now("long-run audio hash mismatch");
        if (compared_samples < 1000)
            fail_now("insufficient compared samples");
        $display("PASS_EQUIV NUM_CH=%0d cycles=%0d samples=%0d writes=%0d hash=%016h",
                 NUM_CH, compared_cycles, compared_samples, write_count, hash_p);
        $finish;
    end

    initial begin
        repeat (4_000_000) @(posedge clk);
        fail_now("global timeout");
    end
endmodule
