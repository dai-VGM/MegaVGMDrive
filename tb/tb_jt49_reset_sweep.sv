`timescale 1ps/1ps

module tb_jt49_reset_sweep #(
    parameter integer SCENARIO_ID = 0,
    parameter integer RESET_CYCLES = 24,
    parameter integer ENABLE_DURING_RESET = 0
);

    localparam integer SYS_HALF_PERIOD_PS = 15_625;
    localparam integer JT49_CLK_EN_PERIOD = 32;
    localparam integer JT49_CLK_EN_PHASE = 2;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic clk_en = 1'b0;
    integer sys_cycle = 0;
    integer release_cycle = -1;
    integer first_sample_cycle = -1;
    integer first_sound_x_cycle = -1;
    integer first_state_x_cycle = -1;
    integer pulse_count_after_release = 0;
    integer known_sample_count = 0;

    wire [7:0] dout;
    wire [9:0] sound;
    wire [7:0] A, B, C;
    wire sample;

    always #(SYS_HALF_PERIOD_PS) clk = ~clk;

    always @(posedge clk)
        sys_cycle <= sys_cycle + 1;

    // One-system-clock-wide pulse every 32 cycles, matching the embedded
    // 4 MHz /4 clk_en_ssg cadence in the 32 MHz smoke test.
    always @(negedge clk) begin
        if ((ENABLE_DURING_RESET || rst_n) &&
            (sys_cycle >= JT49_CLK_EN_PHASE) &&
            ((sys_cycle + 1 - JT49_CLK_EN_PHASE) % JT49_CLK_EN_PERIOD == 0))
            clk_en = 1'b1;
        else
            clk_en = 1'b0;
    end

    jt49 #(.COMP(2'b01), .CLKDIV(2)) dut (
        .rst_n(rst_n), .clk(clk), .clk_en(clk_en), .addr(4'h0),
        .cs_n(1'b0), .wr_n(1'b1), .din(8'h00), .sel(1'b1),
        .dout(dout), .sound(sound), .A(A), .B(B), .C(C),
        .sample(sample), .IOA_in(8'h00), .IOA_out(),
        .IOB_in(8'h00), .IOB_out()
    );

    always @(posedge clk) begin
        #1;
        if (rst_n) begin
            if ((^{dut.Amix,dut.Bmix,dut.Cmix,dut.logA,dut.logB,dut.logC,
                   dut.log,dut.lin,dut.acc,dut.A,dut.B,dut.C,dut.sound,
                   dut.noise,dut.u_ng.last_en,dut.envelope,
                   dut.u_env.last_step,dut.u_env.rst_latch,dut.cen16,
                   dut.cen256,dut.sample}) === 1'bx)
                $fatal(1, "JT49 audio state became X/Z in sweep scenario %0d",
                       SCENARIO_ID);
            if (clk_en)
                pulse_count_after_release = pulse_count_after_release + 1;
            if (sample === 1'b1) begin
                if (first_sample_cycle < 0)
                    first_sample_cycle = sys_cycle;
                known_sample_count = known_sample_count + 1;
            end
            if (first_state_x_cycle < 0 &&
                ((^{dut.Amix,dut.Bmix,dut.Cmix,dut.logA,dut.logB,
                     dut.logC,dut.log,dut.lin}) === 1'bx))
                first_state_x_cycle = sys_cycle;
            if ($isunknown(sound) && first_sound_x_cycle < 0) begin
                first_sound_x_cycle = sys_cycle;
                $display("SWEEP_FIRST_X scenario=%0d cycle=%0d relative_cycle=%0d time=%0t signal=jt49.sound value=%h rst_n=%b clk_en=%b sample=%b acc_st=%b acc=%h log=%h lin=%h",
                         SCENARIO_ID, sys_cycle, sys_cycle-release_cycle,
                         $time, sound, rst_n, clk_en, sample,
                         dut.acc_st, dut.acc, dut.log, dut.lin);
            end
            if (known_sample_count >= 8) begin
                $display("SWEEP_PASS scenario=%0d reset_cycles=%0d enable_during_reset=%0d release_cycle=%0d initial_sound=%h first_state_x_cycle=%0d first_sound_x_cycle=%0d first_sound_x_relative=%0d first_sample_cycle=%0d first_sample_relative=%0d known_samples=%0d post_release_clk_en_pulses=%0d final_sound=%h final_A=%h final_B=%h final_C=%h",
                         SCENARIO_ID, RESET_CYCLES, ENABLE_DURING_RESET,
                         release_cycle, 10'd0, first_state_x_cycle,
                         first_sound_x_cycle,
                         first_sound_x_cycle < 0 ? -1 : first_sound_x_cycle-release_cycle,
                         first_sample_cycle,
                         first_sample_cycle < 0 ? -1 : first_sample_cycle-release_cycle,
                         known_sample_count, pulse_count_after_release,
                         sound, A, B, C);
                $finish;
            end
        end
    end

    initial begin
        repeat (RESET_CYCLES) @(posedge clk);
        #1;
        if (sound !== 10'd0 || A !== 8'd0 || B !== 8'd0 || C !== 8'd0)
            $fatal(1, "reset did not force public outputs to zero");
        if ((^{rst_n,clk_en,dout,sound,A,B,C,sample}) === 1'bx)
            $fatal(1, "public/input X during stable reset");
        if ((^{dut.Amix,dut.Bmix,dut.Cmix,dut.logA,dut.logB,dut.logC,
               dut.log,dut.lin,dut.acc,dut.A,dut.B,dut.C,dut.sound,
               dut.noise,dut.u_ng.last_en,dut.envelope,
               dut.u_env.last_step,dut.u_env.rst_latch,dut.cen16,
               dut.cen256,dut.sample}) === 1'bx)
            $fatal(1, "audio state X during stable reset in scenario %0d",
                   SCENARIO_ID);
        @(negedge clk);
        rst_n = 1'b1;
        release_cycle = sys_cycle;
        #1;
        $display("SWEEP_RELEASE scenario=%0d reset_cycles=%0d enable_during_reset=%0d cycle=%0d time=%0t clk_en=%b initial_sound=%h initial_A=%h initial_B=%h initial_C=%h Amix=%b logA=%h log=%h lin=%h",
                 SCENARIO_ID, RESET_CYCLES, ENABLE_DURING_RESET,
                 release_cycle, $time, clk_en, sound, A, B, C,
                 dut.Amix, dut.logA, dut.log, dut.lin);
    end

endmodule
