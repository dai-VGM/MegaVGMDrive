`timescale 1ps/1ps

module tb_jt49_reset_trace;

    localparam integer SYS_CLK_HZ = 32_000_000;
    localparam integer CHIP_CLK_HZ = 4_000_000;
    localparam integer CEN_DIV = SYS_CLK_HZ / CHIP_CLK_HZ;
    localparam integer SYS_HALF_PERIOD_PS = 500_000_000_000 / SYS_CLK_HZ;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cen = 1'b0;
    integer cen_div_count = 0;
    integer sys_cycle = 0;

    wire [7:0] top_dout;
    wire [9:0] top_sound;
    wire [7:0] top_A, top_B, top_C;
    wire signed [15:0] fm_left, fm_right, snd_left, snd_right;

    wire [7:0] standalone_dout;
    wire [9:0] standalone_sound;
    wire [7:0] standalone_A, standalone_B, standalone_C;
    wire standalone_sample;
    wire [7:0] standalone_IOA_out, standalone_IOB_out;

    bit embedded_seen[0:31];
    bit standalone_seen[0:31];
    integer embedded_first_sample = -1;
    integer standalone_first_sample = -1;
    integer embedded_first_public_x = -1;
    integer standalone_first_public_x = -1;
    integer comparison_mismatches = 0;
    integer known_sample_count = 0;

    always #(SYS_HALF_PERIOD_PS) clk = ~clk;

    always @(posedge clk) begin
        sys_cycle <= sys_cycle + 1;
        if (reset) begin
            cen <= 1'b0;
            cen_div_count <= 0;
        end else if (cen_div_count == CEN_DIV-1) begin
            cen <= 1'b1;
            cen_div_count <= 0;
        end else begin
            cen <= 1'b0;
            cen_div_count <= cen_div_count + 1;
        end
    end

    jt12_top #(
        .use_lfo(0), .use_ssg(1), .num_ch(3), .use_pcm(0),
        .use_adpcm(0), .JT49_DIV(2), .mask_div(0)
    ) dut (
        .rst(reset), .clk(clk), .cen(cen), .din(8'h00), .addr(2'b00),
        .cs_n(1'b1), .wr_n(1'b1), .ladder(1'b0), .dout(top_dout),
        .irq_n(), .en_hifi_pcm(1'b0), .adpcma_addr(), .adpcma_bank(),
        .adpcma_roe_n(), .adpcma_data(8'h00), .adpcmb_addr(),
        .adpcmb_data(8'h00), .adpcmb_roe_n(), .IOA_in(8'h00),
        .IOB_in(8'h00), .psg_A(top_A), .psg_B(top_B), .psg_C(top_C),
        .fm_snd_left(fm_left), .fm_snd_right(fm_right), .adpcmA_l(),
        .adpcmA_r(), .adpcmB_l(), .adpcmB_r(), .psg_snd(top_sound),
        .snd_right(snd_right), .snd_left(snd_left), .snd_sample(),
        .debug_bus(8'h00), .debug_view()
    );

    // All standalone inputs mirror the embedded JT49 instance exactly.
    jt49 #(.COMP(2'b01), .CLKDIV(2)) u_standalone (
        .rst_n(~reset), .clk(clk), .clk_en(dut.clk_en_ssg),
        .addr(dut.psg_addr), .cs_n(1'b0), .wr_n(dut.psg_wr_n),
        .din(dut.psg_data), .sel(1'b1), .dout(standalone_dout),
        .sound(standalone_sound), .A(standalone_A), .B(standalone_B),
        .C(standalone_C), .sample(standalone_sample), .IOA_in(8'h00),
        .IOA_out(standalone_IOA_out), .IOB_in(8'h00),
        .IOB_out(standalone_IOB_out)
    );

    task automatic trace_embedded(
        input integer id,
        input string signal_name,
        input logic is_unknown,
        input string value,
        input string upstream
    );
        begin
            if (is_unknown && !embedded_seen[id]) begin
                embedded_seen[id] = 1'b1;
                $display("FIRST_X cycle=%0d time=%0t module.signal=embedded.%s value=%s rst_n=%b clk_en=%b sample=%b sel=%b upstream=%s",
                         sys_cycle, $time, signal_name, value, ~reset,
                         dut.clk_en_ssg, dut.gen_ssg.u_psg.sample,
                         dut.gen_ssg.u_psg.sel, upstream);
            end
        end
    endtask

    task automatic trace_standalone(
        input integer id,
        input string signal_name,
        input logic is_unknown,
        input string value,
        input string upstream
    );
        begin
            if (is_unknown && !standalone_seen[id]) begin
                standalone_seen[id] = 1'b1;
                $display("FIRST_X cycle=%0d time=%0t module.signal=standalone.%s value=%s rst_n=%b clk_en=%b sample=%b sel=1 upstream=%s",
                         sys_cycle, $time, signal_name, value, ~reset,
                         dut.clk_en_ssg, standalone_sample, upstream);
            end
        end
    endtask

    task automatic trace_embedded_state;
        begin
            trace_embedded( 0, "Amix", $isunknown(dut.gen_ssg.u_psg.Amix), $sformatf("%b", dut.gen_ssg.u_psg.Amix), "noise/use_noA/bitA/regarray[7][0]");
            trace_embedded( 1, "Bmix", $isunknown(dut.gen_ssg.u_psg.Bmix), $sformatf("%b", dut.gen_ssg.u_psg.Bmix), "noise/use_noB/bitB/regarray[7][1]");
            trace_embedded( 2, "Cmix", $isunknown(dut.gen_ssg.u_psg.Cmix), $sformatf("%b", dut.gen_ssg.u_psg.Cmix), "noise/use_noC/bitC/regarray[7][2]");
            trace_embedded( 3, "logA", $isunknown(dut.gen_ssg.u_psg.logA), $sformatf("%h", dut.gen_ssg.u_psg.logA), "Amix/use_envA/envelope/volA");
            trace_embedded( 4, "logB", $isunknown(dut.gen_ssg.u_psg.logB), $sformatf("%h", dut.gen_ssg.u_psg.logB), "Bmix/use_envB/envelope/volB");
            trace_embedded( 5, "logC", $isunknown(dut.gen_ssg.u_psg.logC), $sformatf("%h", dut.gen_ssg.u_psg.logC), "Cmix/use_envC/envelope/volC");
            trace_embedded( 6, "log", $isunknown(dut.gen_ssg.u_psg.log), $sformatf("%h", dut.gen_ssg.u_psg.log), "logA/logB/logC selected by acc_st");
            trace_embedded( 7, "u_exp.dout/lin", $isunknown(dut.gen_ssg.u_psg.lin), $sformatf("%h", dut.gen_ssg.u_psg.lin), "LUT[{COMP,log}]");
            trace_embedded( 8, "acc", $isunknown(dut.gen_ssg.u_psg.acc), $sformatf("%h", dut.gen_ssg.u_psg.acc), "acc+lin");
            trace_embedded( 9, "sound", $isunknown(dut.gen_ssg.u_psg.sound), $sformatf("%h", dut.gen_ssg.u_psg.sound), "acc captured at acc_st=0001");
            trace_embedded(10, "A", $isunknown(dut.gen_ssg.u_psg.A), $sformatf("%h", dut.gen_ssg.u_psg.A), "lin captured at acc_st=0010");
            trace_embedded(11, "B", $isunknown(dut.gen_ssg.u_psg.B), $sformatf("%h", dut.gen_ssg.u_psg.B), "lin captured at acc_st=0100");
            trace_embedded(12, "C", $isunknown(dut.gen_ssg.u_psg.C), $sformatf("%h", dut.gen_ssg.u_psg.C), "lin captured at acc_st=1000");
            trace_embedded(13, "u_ng.last_en", $isunknown(dut.gen_ssg.u_psg.u_ng.last_en), $sformatf("%b", dut.gen_ssg.u_psg.u_ng.last_en), "noise_en on cen16");
            trace_embedded(14, "u_ng.noise", $isunknown(dut.gen_ssg.u_psg.u_ng.noise), $sformatf("%b", dut.gen_ssg.u_psg.u_ng.noise), "~poly17[0] on cen16");
            trace_embedded(15, "u_env.env", $isunknown(dut.gen_ssg.u_psg.u_env.env), $sformatf("%h", dut.gen_ssg.u_psg.u_env.env), "inv/gain on cen256");
            trace_embedded(16, "u_env.last_step", $isunknown(dut.gen_ssg.u_psg.u_env.last_step), $sformatf("%b", dut.gen_ssg.u_psg.u_env.last_step), "eg_step on cen256");
            trace_embedded(17, "u_env.rst_latch", $isunknown(dut.gen_ssg.u_psg.u_env.rst_latch), $sformatf("%b", dut.gen_ssg.u_psg.u_env.rst_latch), "restart/rst_clr");
            trace_embedded(18, "u_cen.cen16", $isunknown(dut.gen_ssg.u_psg.cen16), $sformatf("%b", dut.gen_ssg.u_psg.cen16), "clk_en & toggle16");
            trace_embedded(19, "u_cen.cen256", $isunknown(dut.gen_ssg.u_psg.cen256), $sformatf("%b", dut.gen_ssg.u_psg.cen256), "clk_en & toggle256");
            trace_embedded(20, "u_chA.count/div", $isunknown({dut.gen_ssg.u_psg.u_chA.count,dut.gen_ssg.u_psg.u_chA.div}), $sformatf("%h/%b", dut.gen_ssg.u_psg.u_chA.count,dut.gen_ssg.u_psg.u_chA.div), "cen16/periodA");
            trace_embedded(21, "u_ng.poly17", $isunknown(dut.gen_ssg.u_psg.u_ng.poly17), $sformatf("%h", dut.gen_ssg.u_psg.u_ng.poly17), "noise_up");
            trace_embedded(22, "u_env.gain/inv/stop/rst_clr", $isunknown({dut.gen_ssg.u_psg.u_env.gain,dut.gen_ssg.u_psg.u_env.inv,dut.gen_ssg.u_psg.u_env.stop,dut.gen_ssg.u_psg.u_env.rst_clr}), $sformatf("%h/%b/%b/%b", dut.gen_ssg.u_psg.u_env.gain,dut.gen_ssg.u_psg.u_env.inv,dut.gen_ssg.u_psg.u_env.stop,dut.gen_ssg.u_psg.u_env.rst_clr), "asynchronous reset or cen256 update");
            trace_embedded(23, "regarray", $isunknown({dut.gen_ssg.u_psg.regarray[0],dut.gen_ssg.u_psg.regarray[1],dut.gen_ssg.u_psg.regarray[2],dut.gen_ssg.u_psg.regarray[3],dut.gen_ssg.u_psg.regarray[4],dut.gen_ssg.u_psg.regarray[5],dut.gen_ssg.u_psg.regarray[6],dut.gen_ssg.u_psg.regarray[7],dut.gen_ssg.u_psg.regarray[8],dut.gen_ssg.u_psg.regarray[9],dut.gen_ssg.u_psg.regarray[10],dut.gen_ssg.u_psg.regarray[11],dut.gen_ssg.u_psg.regarray[12],dut.gen_ssg.u_psg.regarray[13],dut.gen_ssg.u_psg.regarray[14],dut.gen_ssg.u_psg.regarray[15]}), "array", "bus/reset");
        end
    endtask

    task automatic trace_standalone_state;
        begin
            trace_standalone( 0, "Amix", $isunknown(u_standalone.Amix), $sformatf("%b", u_standalone.Amix), "noise/use_noA/bitA/regarray[7][0]");
            trace_standalone( 1, "Bmix", $isunknown(u_standalone.Bmix), $sformatf("%b", u_standalone.Bmix), "noise/use_noB/bitB/regarray[7][1]");
            trace_standalone( 2, "Cmix", $isunknown(u_standalone.Cmix), $sformatf("%b", u_standalone.Cmix), "noise/use_noC/bitC/regarray[7][2]");
            trace_standalone( 3, "logA", $isunknown(u_standalone.logA), $sformatf("%h", u_standalone.logA), "Amix/use_envA/envelope/volA");
            trace_standalone( 4, "logB", $isunknown(u_standalone.logB), $sformatf("%h", u_standalone.logB), "Bmix/use_envB/envelope/volB");
            trace_standalone( 5, "logC", $isunknown(u_standalone.logC), $sformatf("%h", u_standalone.logC), "Cmix/use_envC/envelope/volC");
            trace_standalone( 6, "log", $isunknown(u_standalone.log), $sformatf("%h", u_standalone.log), "logA/logB/logC selected by acc_st");
            trace_standalone( 7, "u_exp.dout/lin", $isunknown(u_standalone.lin), $sformatf("%h", u_standalone.lin), "LUT[{COMP,log}]");
            trace_standalone( 8, "acc", $isunknown(u_standalone.acc), $sformatf("%h", u_standalone.acc), "acc+lin");
            trace_standalone( 9, "sound", $isunknown(u_standalone.sound), $sformatf("%h", u_standalone.sound), "acc captured at acc_st=0001");
            trace_standalone(10, "A", $isunknown(u_standalone.A), $sformatf("%h", u_standalone.A), "lin captured at acc_st=0010");
            trace_standalone(11, "B", $isunknown(u_standalone.B), $sformatf("%h", u_standalone.B), "lin captured at acc_st=0100");
            trace_standalone(12, "C", $isunknown(u_standalone.C), $sformatf("%h", u_standalone.C), "lin captured at acc_st=1000");
            trace_standalone(13, "u_ng.last_en", $isunknown(u_standalone.u_ng.last_en), $sformatf("%b", u_standalone.u_ng.last_en), "noise_en on cen16");
            trace_standalone(14, "u_ng.noise", $isunknown(u_standalone.u_ng.noise), $sformatf("%b", u_standalone.u_ng.noise), "~poly17[0] on cen16");
            trace_standalone(15, "u_env.env", $isunknown(u_standalone.u_env.env), $sformatf("%h", u_standalone.u_env.env), "inv/gain on cen256");
            trace_standalone(16, "u_env.last_step", $isunknown(u_standalone.u_env.last_step), $sformatf("%b", u_standalone.u_env.last_step), "eg_step on cen256");
            trace_standalone(17, "u_env.rst_latch", $isunknown(u_standalone.u_env.rst_latch), $sformatf("%b", u_standalone.u_env.rst_latch), "restart/rst_clr");
            trace_standalone(18, "u_cen.cen16", $isunknown(u_standalone.cen16), $sformatf("%b", u_standalone.cen16), "clk_en & toggle16");
            trace_standalone(19, "u_cen.cen256", $isunknown(u_standalone.cen256), $sformatf("%b", u_standalone.cen256), "clk_en & toggle256");
            trace_standalone(20, "u_chA.count/div", $isunknown({u_standalone.u_chA.count,u_standalone.u_chA.div}), $sformatf("%h/%b", u_standalone.u_chA.count,u_standalone.u_chA.div), "cen16/periodA");
            trace_standalone(21, "u_ng.poly17", $isunknown(u_standalone.u_ng.poly17), $sformatf("%h", u_standalone.u_ng.poly17), "noise_up");
            trace_standalone(22, "u_env.gain/inv/stop/rst_clr", $isunknown({u_standalone.u_env.gain,u_standalone.u_env.inv,u_standalone.u_env.stop,u_standalone.u_env.rst_clr}), $sformatf("%h/%b/%b/%b", u_standalone.u_env.gain,u_standalone.u_env.inv,u_standalone.u_env.stop,u_standalone.u_env.rst_clr), "asynchronous reset or cen256 update");
            trace_standalone(23, "regarray", $isunknown({u_standalone.regarray[0],u_standalone.regarray[1],u_standalone.regarray[2],u_standalone.regarray[3],u_standalone.regarray[4],u_standalone.regarray[5],u_standalone.regarray[6],u_standalone.regarray[7],u_standalone.regarray[8],u_standalone.regarray[9],u_standalone.regarray[10],u_standalone.regarray[11],u_standalone.regarray[12],u_standalone.regarray[13],u_standalone.regarray[14],u_standalone.regarray[15]}), "array", "bus/reset");
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (!reset) begin
            trace_embedded_state();
            trace_standalone_state();

            if ((^{dut.gen_ssg.u_psg.Amix,dut.gen_ssg.u_psg.Bmix,
                   dut.gen_ssg.u_psg.Cmix,dut.gen_ssg.u_psg.logA,
                   dut.gen_ssg.u_psg.logB,dut.gen_ssg.u_psg.logC,
                   dut.gen_ssg.u_psg.log,dut.gen_ssg.u_psg.lin,
                   dut.gen_ssg.u_psg.acc,dut.gen_ssg.u_psg.A,
                   dut.gen_ssg.u_psg.B,dut.gen_ssg.u_psg.C,
                   dut.gen_ssg.u_psg.sound,dut.gen_ssg.u_psg.noise,
                   dut.gen_ssg.u_psg.u_ng.last_en,
                   dut.gen_ssg.u_psg.envelope,
                   dut.gen_ssg.u_psg.u_env.last_step,
                   dut.gen_ssg.u_psg.u_env.rst_latch,
                   dut.gen_ssg.u_psg.cen16,dut.gen_ssg.u_psg.cen256,
                   dut.gen_ssg.u_psg.sample}) === 1'bx)
                $fatal(1, "embedded JT49 audio state became X/Z");
            if ((^{u_standalone.Amix,u_standalone.Bmix,u_standalone.Cmix,
                   u_standalone.logA,u_standalone.logB,u_standalone.logC,
                   u_standalone.log,u_standalone.lin,u_standalone.acc,
                   u_standalone.A,u_standalone.B,u_standalone.C,
                   u_standalone.sound,u_standalone.noise,
                   u_standalone.u_ng.last_en,u_standalone.envelope,
                   u_standalone.u_env.last_step,
                   u_standalone.u_env.rst_latch,u_standalone.cen16,
                   u_standalone.cen256,u_standalone.sample}) === 1'bx)
                $fatal(1, "standalone JT49 audio state became X/Z");

            if (dut.gen_ssg.u_psg.sample === 1'b1 && embedded_first_sample < 0) begin
                embedded_first_sample = sys_cycle;
                $display("FIRST_SAMPLE scope=embedded cycle=%0d time=%0t", sys_cycle, $time);
            end
            if (dut.gen_ssg.u_psg.sample === 1'b1)
                known_sample_count = known_sample_count + 1;
            if (standalone_sample === 1'b1 && standalone_first_sample < 0) begin
                standalone_first_sample = sys_cycle;
                $display("FIRST_SAMPLE scope=standalone cycle=%0d time=%0t", sys_cycle, $time);
            end
            if ($isunknown(top_sound) && embedded_first_public_x < 0) begin
                embedded_first_public_x = sys_cycle;
                $display("FIRST_PUBLIC_X scope=embedded cycle=%0d time=%0t sound=%h", sys_cycle, $time, top_sound);
            end
            if ($isunknown(standalone_sound) && standalone_first_public_x < 0) begin
                standalone_first_public_x = sys_cycle;
                $display("FIRST_PUBLIC_X scope=standalone cycle=%0d time=%0t sound=%h", sys_cycle, $time, standalone_sound);
            end

            if ({top_sound,top_A,top_B,top_C,top_dout,
                 dut.gen_ssg.u_psg.sample} !==
                {standalone_sound,standalone_A,standalone_B,standalone_C,
                 standalone_dout,standalone_sample}) begin
                comparison_mismatches = comparison_mismatches + 1;
                $display("COMPARE_MISMATCH cycle=%0d embedded=%h/%h/%h/%h/%h standalone=%h/%h/%h/%h/%h",
                         sys_cycle, top_sound, top_A, top_B, top_C, top_dout,
                         standalone_sound, standalone_A, standalone_B,
                         standalone_C, standalone_dout);
            end

            if (known_sample_count >= 8) begin
                $display("TRACE_PASS cycle=%0d known_samples=%0d embedded_first_public_x=%0d standalone_first_public_x=%0d embedded_first_sample=%0d standalone_first_sample=%0d comparison_mismatches=%0d",
                         sys_cycle, known_sample_count,
                         embedded_first_public_x, standalone_first_public_x,
                         embedded_first_sample, standalone_first_sample,
                         comparison_mismatches);
                $finish;
            end
        end
    end

    initial begin
        $dumpfile("/tmp/tb_jt49_reset_trace.vcd");
        $dumpvars(0, clk, reset, cen, dut.clk_en_ssg, top_sound,
                  top_A, top_B, top_C, standalone_sound, standalone_A,
                  standalone_B, standalone_C);
        $dumpvars(0, dut.gen_ssg.u_psg);
        $dumpvars(0, u_standalone);

        #1;
        $display("TRACE_INPUTS phase=raw_startup time=%0t rst_n=%b clk_en=%b addr=%h cs_n=%b wr_n=%b din=%h sel=%b IOA=%h IOB=%h",
                 $time, dut.gen_ssg.u_psg.rst_n, dut.clk_en_ssg,
                 dut.psg_addr, dut.gen_ssg.u_psg.cs_n, dut.psg_wr_n,
                 dut.psg_data, dut.gen_ssg.u_psg.sel,
                 dut.gen_ssg.u_psg.IOA_in, dut.gen_ssg.u_psg.IOB_in);

        repeat (24) @(posedge clk);
        #1;
        $display("TRACE_INPUTS phase=reset_asserted cycle=%0d rst_n=%b clk_en=%b addr=%h cs_n=%b wr_n=%b din=%h sel=%b IOA=%h IOB=%h",
                 sys_cycle, dut.gen_ssg.u_psg.rst_n, dut.clk_en_ssg,
                 dut.psg_addr, dut.gen_ssg.u_psg.cs_n, dut.psg_wr_n,
                 dut.psg_data, dut.gen_ssg.u_psg.sel,
                 dut.gen_ssg.u_psg.IOA_in, dut.gen_ssg.u_psg.IOB_in);
        if ((^{reset,cen,dut.clk_en_ssg,dut.psg_addr,
               dut.gen_ssg.u_psg.cs_n,dut.psg_wr_n,dut.psg_data,
               dut.gen_ssg.u_psg.sel,dut.gen_ssg.u_psg.IOA_in,
               dut.gen_ssg.u_psg.IOB_in}) === 1'bx)
            $fatal(1, "JT49 input unknown during stable reset");
        if ((^{dut.gen_ssg.u_psg.Amix,dut.gen_ssg.u_psg.Bmix,
               dut.gen_ssg.u_psg.Cmix,dut.gen_ssg.u_psg.logA,
               dut.gen_ssg.u_psg.logB,dut.gen_ssg.u_psg.logC,
               dut.gen_ssg.u_psg.log,dut.gen_ssg.u_psg.lin,
               dut.gen_ssg.u_psg.acc,dut.gen_ssg.u_psg.A,
               dut.gen_ssg.u_psg.B,dut.gen_ssg.u_psg.C,
               dut.gen_ssg.u_psg.sound,dut.gen_ssg.u_psg.noise,
               dut.gen_ssg.u_psg.u_ng.last_en,
               dut.gen_ssg.u_psg.envelope,
               dut.gen_ssg.u_psg.u_env.last_step,
               dut.gen_ssg.u_psg.u_env.rst_latch,
               dut.gen_ssg.u_psg.cen16,dut.gen_ssg.u_psg.cen256,
               dut.gen_ssg.u_psg.sample}) === 1'bx)
            $fatal(1, "JT49 audio state unknown during reset with clk_en=0");

        @(negedge clk);
        reset = 1'b0;
        #1;
        $display("TRACE_INPUTS phase=immediate_release cycle=%0d rst_n=%b clk_en=%b addr=%h cs_n=%b wr_n=%b din=%h sel=%b IOA=%h IOB=%h",
                 sys_cycle, dut.gen_ssg.u_psg.rst_n, dut.clk_en_ssg,
                 dut.psg_addr, dut.gen_ssg.u_psg.cs_n, dut.psg_wr_n,
                 dut.psg_data, dut.gen_ssg.u_psg.sel,
                 dut.gen_ssg.u_psg.IOA_in, dut.gen_ssg.u_psg.IOB_in);
        if ((^{reset,cen,dut.clk_en_ssg,dut.psg_addr,
               dut.gen_ssg.u_psg.cs_n,dut.psg_wr_n,dut.psg_data,
               dut.gen_ssg.u_psg.sel,dut.gen_ssg.u_psg.IOA_in,
               dut.gen_ssg.u_psg.IOB_in}) === 1'bx)
            $fatal(1, "JT49 input unknown immediately after reset release");
    end

endmodule
