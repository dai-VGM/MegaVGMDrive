`timescale 1ps/1ps

module tb_jt2203_bus_smoke #(
    parameter integer SYS_CLK_HZ  = 32_000_000,
    parameter integer CHIP_CLK_HZ =  4_000_000
);

    localparam integer CEN_DIV = SYS_CLK_HZ / CHIP_CLK_HZ;
    localparam integer SYS_HALF_PERIOD_PS = 500_000_000_000 / SYS_CLK_HZ;
    localparam integer BUSY_TIMEOUT_CYCLES = 20_000;
    localparam integer AUDIO_TIMEOUT_CYCLES = 1_000_000;
    localparam integer GLOBAL_TIMEOUT_CYCLES = 5_000_000;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cen = 1'b0;
    integer cen_div_count = 0;
    integer sys_cycle = 0;
    integer cen_pulse_count = 0;
    integer fm_en_pulse_count = 0;
    integer last_cen_cycle = -1;
    logic cen_prev = 1'b0;

    logic [7:0] din = 8'h00;
    logic [1:0] addr = 2'b00;
    logic cs_n = 1'b1;
    logic wr_n = 1'b1;

    wire [7:0] dout;
    wire irq_n;
    wire [19:0] adpcma_addr;
    wire [3:0] adpcma_bank;
    wire adpcma_roe_n;
    wire [23:0] adpcmb_addr;
    wire adpcmb_roe_n;
    wire [7:0] psg_A;
    wire [7:0] psg_B;
    wire [7:0] psg_C;
    wire signed [15:0] fm_snd_left;
    wire signed [15:0] fm_snd_right;
    wire signed [15:0] adpcmA_l;
    wire signed [15:0] adpcmA_r;
    wire signed [15:0] adpcmB_l;
    wire signed [15:0] adpcmB_r;
    wire [9:0] psg_snd;
    wire signed [15:0] snd_right;
    wire signed [15:0] snd_left;
    wire snd_sample;
    wire [7:0] debug_view;

    integer address_write_count = 0;
    integer data_write_count = 0;
    integer busy_observed_count = 0;
    integer mono_mismatch_count = 0;
    integer unknown_count = 0;
    integer audio_update_total = 0;
    logic snd_sample_prev = 1'b0;
    logic monitor_enabled = 1'b0;

    logic measure_active = 1'b0;
    integer measure_samples = 0;
    integer measure_changes = 0;
    integer measure_unknowns = 0;
    integer measure_min = 32'h7fffffff;
    integer measure_max = -32'h7fffffff;
    logic signed [15:0] measure_prev = 16'sd0;
    logic measure_have_prev = 1'b0;

    integer ssg_on_samples;
    integer ssg_on_changes;
    integer ssg_on_min;
    integer ssg_on_max;
    integer ssg_on_unknowns;
    integer ssg_mute_samples;
    integer ssg_mute_changes;
    integer ssg_mute_min;
    integer ssg_mute_max;
    integer ssg_mute_unknowns;
    integer noise_on_samples;
    integer noise_on_changes;
    integer noise_on_min;
    integer noise_on_max;
    integer noise_on_unknowns;
    integer noise_mute_samples;
    integer noise_mute_changes;
    integer noise_mute_min;
    integer noise_mute_max;
    integer noise_mute_unknowns;
    integer envelope_on_samples;
    integer envelope_on_changes;
    integer envelope_on_min;
    integer envelope_on_max;
    integer envelope_on_unknowns;
    integer envelope_mute_samples;
    integer envelope_mute_changes;
    integer envelope_mute_min;
    integer envelope_mute_max;
    integer envelope_mute_unknowns;
    integer fm_pre_samples;
    integer fm_pre_changes;
    integer fm_pre_min;
    integer fm_pre_max;
    integer fm_pre_unknowns;
    integer fm_on_samples;
    integer fm_on_changes;
    integer fm_on_min;
    integer fm_on_max;
    integer fm_on_unknowns;
    integer fm_off_samples;
    integer fm_off_changes;
    integer fm_off_min;
    integer fm_off_max;
    integer fm_off_unknowns;

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
        .use_lfo   (0),
        .use_ssg   (1),
        .num_ch    (3),
        .use_pcm   (0),
        .use_adpcm (0),
        .JT49_DIV  (2),
        .mask_div  (0)
    ) dut (
        .rst            (reset),
        .clk            (clk),
        .cen            (cen),
        .din            (din),
        .addr           (addr),
        .cs_n           (cs_n),
        .wr_n           (wr_n),
        .ladder         (1'b0),
        .dout           (dout),
        .irq_n          (irq_n),
        .en_hifi_pcm    (1'b0),
        .adpcma_addr    (adpcma_addr),
        .adpcma_bank    (adpcma_bank),
        .adpcma_roe_n   (adpcma_roe_n),
        .adpcma_data    (8'h00),
        .adpcmb_addr    (adpcmb_addr),
        .adpcmb_data    (8'h00),
        .adpcmb_roe_n   (adpcmb_roe_n),
        .IOA_in         (8'h00),
        .IOB_in         (8'h00),
        .psg_A          (psg_A),
        .psg_B          (psg_B),
        .psg_C          (psg_C),
        .fm_snd_left    (fm_snd_left),
        .fm_snd_right   (fm_snd_right),
        .adpcmA_l       (adpcmA_l),
        .adpcmA_r       (adpcmA_r),
        .adpcmB_l       (adpcmB_l),
        .adpcmB_r       (adpcmB_r),
        .psg_snd        (psg_snd),
        .snd_right      (snd_right),
        .snd_left       (snd_left),
        .snd_sample     (snd_sample),
        .debug_bus      (8'h00),
        .debug_view     (debug_view)
    );

    task automatic fail_now(input string reason);
        begin
            $display("FAIL time=%0t cycle=%0d reason=%s", $time, sys_cycle, reason);
            $fatal(1);
        end
    endtask

    task automatic audit_jt49_inputs(input string phase);
        begin
            $display("JT49_INPUTS phase=%s time=%0t cycle=%0d top_rst=%b top_cen=%b top_din=%02h top_addr=%b top_cs_n=%b top_wr_n=%b jt49_rst_n=%b jt49_clk=%b jt49_clk_en=%b jt49_addr=%h jt49_cs_n=%b jt49_wr_n=%b jt49_din=%02h jt49_sel=%b IOA_in=%02h IOB_in=%02h",
                     phase, $time, sys_cycle, reset, cen, din, addr, cs_n, wr_n,
                     dut.gen_ssg.u_psg.rst_n, dut.gen_ssg.u_psg.clk,
                     dut.gen_ssg.u_psg.clk_en, dut.gen_ssg.u_psg.addr,
                     dut.gen_ssg.u_psg.cs_n, dut.gen_ssg.u_psg.wr_n,
                     dut.gen_ssg.u_psg.din, dut.gen_ssg.u_psg.sel,
                     dut.gen_ssg.u_psg.IOA_in, dut.gen_ssg.u_psg.IOB_in);
            if ((^{reset, cen, din, addr, cs_n, wr_n,
                   dut.ladder, dut.en_hifi_pcm, dut.adpcma_data,
                   dut.adpcmb_data, dut.IOA_in, dut.IOB_in, dut.debug_bus,
                   dut.gen_ssg.u_psg.rst_n, dut.gen_ssg.u_psg.clk,
                   dut.gen_ssg.u_psg.clk_en, dut.gen_ssg.u_psg.addr,
                   dut.gen_ssg.u_psg.cs_n, dut.gen_ssg.u_psg.wr_n,
                   dut.gen_ssg.u_psg.din, dut.gen_ssg.u_psg.sel,
                   dut.gen_ssg.u_psg.IOA_in,
                   dut.gen_ssg.u_psg.IOB_in}) === 1'bx)
                fail_now("X/Z detected on jt12_top or embedded JT49 input");
        end
    endtask

    task automatic wait_cen_pulses(input integer count);
        integer target;
        integer waited;
        begin
            target = cen_pulse_count + count;
            waited = 0;
            while (cen_pulse_count < target) begin
                @(posedge clk);
                waited = waited + 1;
                if (waited > AUDIO_TIMEOUT_CYCLES)
                    fail_now("timeout waiting for chip CEN pulses");
            end
        end
    endtask

    task automatic wait_audio_updates(input integer count);
        integer target;
        integer waited;
        begin
            target = audio_update_total + count;
            waited = 0;
            while (audio_update_total < target) begin
                @(posedge clk);
                waited = waited + 1;
                if (waited > AUDIO_TIMEOUT_CYCLES)
                    fail_now("timeout waiting for public snd_sample updates");
            end
        end
    endtask

    task automatic bus_write_pulse(
        input logic [1:0] bus_addr,
        input logic [7:0] bus_data,
        output integer write_cycle
    );
        begin
            @(negedge clk);
            addr = bus_addr;
            din = bus_data;
            cs_n = 1'b0;
            wr_n = 1'b0;
            @(posedge clk);
            #1;
            write_cycle = sys_cycle;
            @(negedge clk);
            addr = 2'b00;
            din = 8'h00;
            cs_n = 1'b1;
            wr_n = 1'b1;
        end
    endtask

    task automatic select_status;
        begin
            @(negedge clk);
            addr = 2'b00;
            din = 8'h00;
            cs_n = 1'b0;
            wr_n = 1'b1;
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

    task automatic ym2203_write(
        input logic [7:0] reg_addr,
        input logic [7:0] reg_data
    );
        integer address_cycle;
        integer data_cycle;
        integer assert_cycle;
        integer clear_cycle;
        integer start_cen_count;
        integer start_fm_en_count;
        integer assert_wait_cycles;
        integer clear_wait_cycles;
        begin
            bus_write_pulse(2'b00, reg_addr, address_cycle);
            address_write_count = address_write_count + 1;

            // Leave a full sampled idle cycle between address and data writes.
            @(posedge clk);
            select_status();
            repeat (2) begin
                @(posedge clk);
                #1;
                if (dout[7] !== 1'b0)
                    fail_now("busy asserted after address write");
            end
            bus_idle();

            start_cen_count = cen_pulse_count;
            start_fm_en_count = fm_en_pulse_count;
            bus_write_pulse(2'b01, reg_data, data_cycle);
            data_write_count = data_write_count + 1;
            select_status();

            assert_wait_cycles = 0;
            while (dout[7] !== 1'b1) begin
                @(posedge clk);
                #1;
                assert_wait_cycles = assert_wait_cycles + 1;
                if (assert_wait_cycles > BUSY_TIMEOUT_CYCLES)
                    fail_now("busy did not assert after data write");
            end
            assert_cycle = sys_cycle;
            busy_observed_count = busy_observed_count + 1;

            clear_wait_cycles = 0;
            while (dout[7] !== 1'b0) begin
                @(posedge clk);
                #1;
                clear_wait_cycles = clear_wait_cycles + 1;
                if (clear_wait_cycles > BUSY_TIMEOUT_CYCLES)
                    fail_now("busy did not clear after data write");
            end
            clear_cycle = sys_cycle;

            $display("BUS_WRITE reg=%02h data=%02h time=%0t data_cycle=%0d busy_assert_cycles=%0d busy_clear_cycles=%0d busy_clear_cen_pulses=%0d busy_clear_fm_en_pulses=%0d",
                     reg_addr, reg_data, $time, data_cycle,
                     assert_cycle-data_cycle, clear_cycle-data_cycle,
                     cen_pulse_count-start_cen_count,
                     fm_en_pulse_count-start_fm_en_count);
            bus_idle();
        end
    endtask

    task automatic begin_measurement;
        begin
            @(negedge clk);
            measure_samples = 0;
            measure_changes = 0;
            measure_unknowns = 0;
            measure_min = 32'h7fffffff;
            measure_max = -32'h7fffffff;
            measure_prev = 16'sd0;
            measure_have_prev = 1'b0;
            measure_active = 1'b1;
        end
    endtask

    task automatic finish_measurement(
        input string label,
        input integer wanted_samples,
        output integer samples,
        output integer changes,
        output integer min_value,
        output integer max_value,
        output integer unknowns
    );
        integer waited;
        begin
            waited = 0;
            while (measure_samples < wanted_samples) begin
                @(posedge clk);
                waited = waited + 1;
                if (waited > AUDIO_TIMEOUT_CYCLES)
                    fail_now("audio measurement timeout");
            end
            @(negedge clk);
            measure_active = 1'b0;
            samples = measure_samples;
            changes = measure_changes;
            min_value = measure_min;
            max_value = measure_max;
            unknowns = measure_unknowns;
            $display("AUDIO_STATS phase=%s updates=%0d min=%0d max=%0d changes=%0d unknowns=%0d",
                     label, samples, min_value, max_value, changes, unknowns);
        end
    endtask

    task automatic measure_phase(
        input string label,
        input integer wanted_samples,
        output integer samples,
        output integer changes,
        output integer min_value,
        output integer max_value,
        output integer unknowns
    );
        begin
            begin_measurement();
            finish_measurement(label, wanted_samples, samples, changes,
                               min_value, max_value, unknowns);
        end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            cen_pulse_count <= 0;
            fm_en_pulse_count <= 0;
            last_cen_cycle <= -1;
            cen_prev <= 1'b0;
            snd_sample_prev <= 1'b0;
        end else begin
            if (cen) begin
                cen_pulse_count <= cen_pulse_count + 1;
                if (cen_prev)
                    fail_now("chip CEN wider than one system-clock cycle");
                if (last_cen_cycle >= 0 && sys_cycle-last_cen_cycle != CEN_DIV)
                    fail_now("chip CEN interval is not the configured integer ratio");
                last_cen_cycle <= sys_cycle;
            end
            if (dut.clk_en)
                fm_en_pulse_count <= fm_en_pulse_count + 1;
            cen_prev <= cen;

            if (monitor_enabled &&
                ((^{reset, cen, din, addr, cs_n, wr_n,
                    dut.ladder, dut.en_hifi_pcm, dut.adpcma_data,
                    dut.adpcmb_data, dut.IOA_in, dut.IOB_in, dut.debug_bus,
                    dut.gen_ssg.u_psg.rst_n, dut.gen_ssg.u_psg.clk_en,
                    dut.gen_ssg.u_psg.addr, dut.gen_ssg.u_psg.cs_n,
                    dut.gen_ssg.u_psg.wr_n, dut.gen_ssg.u_psg.din,
                    dut.gen_ssg.u_psg.sel, dut.gen_ssg.u_psg.IOA_in,
                    dut.gen_ssg.u_psg.IOB_in}) === 1'bx)) begin
                audit_jt49_inputs("continuous_assert");
                fail_now("X/Z detected on jt12_top or embedded JT49 input");
            end

            if (monitor_enabled &&
                ((^dout === 1'bx) || (^snd_left === 1'bx) ||
                (^snd_right === 1'bx) || (^fm_snd_left === 1'bx) ||
                (^fm_snd_right === 1'bx) || (^psg_snd === 1'bx) ||
                (snd_sample !== 1'b0 && snd_sample !== 1'b1))) begin
                unknown_count <= unknown_count + 1;
                $display("UNKNOWN_DETAIL dout=%02h snd_l=%h snd_r=%h fm_l=%h fm_r=%h psg=%h sample=%b",
                         dout, snd_left, snd_right, fm_snd_left, fm_snd_right,
                         psg_snd, snd_sample);
                audit_jt49_inputs("first_public_x");
                $display("JT49_STATE cen16=%b cen256=%b acc_st=%b acc=%h sound=%h A=%h B=%h C=%h Amix=%b Bmix=%b Cmix=%b logA=%h logB=%h logC=%h log=%h lin=%h noise=%b envelope=%h",
                         dut.gen_ssg.u_psg.cen16, dut.gen_ssg.u_psg.cen256,
                         dut.gen_ssg.u_psg.acc_st, dut.gen_ssg.u_psg.acc,
                         dut.gen_ssg.u_psg.sound, dut.gen_ssg.u_psg.A,
                         dut.gen_ssg.u_psg.B, dut.gen_ssg.u_psg.C,
                         dut.gen_ssg.u_psg.Amix, dut.gen_ssg.u_psg.Bmix,
                         dut.gen_ssg.u_psg.Cmix, dut.gen_ssg.u_psg.logA,
                         dut.gen_ssg.u_psg.logB, dut.gen_ssg.u_psg.logC,
                         dut.gen_ssg.u_psg.log, dut.gen_ssg.u_psg.lin,
                         dut.gen_ssg.u_psg.noise,
                         dut.gen_ssg.u_psg.envelope);
                $display("FM_STATE clk_en=%b zero=%b cur_ch=%h cur_op=%h alg=%h s1=%b s2=%b s3=%b s4=%b sum_en=%b op_result=%h op_result_hd=%h mono_current=%h mono_next=%h mono_acc=%h mono_snd=%h",
                         dut.clk_en, dut.zero, dut.cur_ch, dut.cur_op,
                         dut.alg_I, dut.s1_enters, dut.s2_enters,
                         dut.s3_enters, dut.s4_enters,
                         dut.gen_2203_acc.u_acc.sum_en, dut.op_result,
                         dut.op_result_hd,
                         dut.gen_2203_acc.u_acc.u_mono.current,
                         dut.gen_2203_acc.u_acc.u_mono.next,
                         dut.gen_2203_acc.u_acc.u_mono.acc,
                         dut.gen_2203_acc.u_acc.u_mono.snd);
                fail_now("X/Z detected on public status or audio signal");
            end

            if (monitor_enabled &&
                (snd_left !== snd_right || fm_snd_left !== fm_snd_right)) begin
                mono_mismatch_count <= mono_mismatch_count + 1;
                fail_now("YM2203 left/right public outputs differ");
            end

            if (snd_sample && !snd_sample_prev) begin
                audio_update_total <= audio_update_total + 1;
                if (measure_active) begin
                    if ((^snd_left === 1'bx)) begin
                        measure_unknowns = measure_unknowns + 1;
                    end else begin
                        measure_samples = measure_samples + 1;
                        if ($signed(snd_left) < measure_min)
                            measure_min = $signed(snd_left);
                        if ($signed(snd_left) > measure_max)
                            measure_max = $signed(snd_left);
                        if (measure_have_prev && snd_left !== measure_prev)
                            measure_changes = measure_changes + 1;
                        measure_prev = snd_left;
                        measure_have_prev = 1'b1;
                    end
                end
            end
            snd_sample_prev <= snd_sample;
        end
    end

    initial begin
        if (SYS_CLK_HZ % CHIP_CLK_HZ != 0)
            fail_now("SYS_CLK_HZ must be an integer multiple of CHIP_CLK_HZ");
        if (CEN_DIV < 2)
            fail_now("CEN_DIV must leave a one-cycle pulse and at least one idle cycle");

        repeat (24) @(posedge clk);
        #1;
        if (cen !== 1'b0)
            fail_now("external chip CEN was not disabled during reset check");
        if (dut.gen_2203_acc.u_acc.u_mono.acc !== 18'd0)
            fail_now("YM2203 mono acc did not reset with clk_en disabled");
        if (dut.gen_2203_acc.u_acc.hires !== 18'd0)
            fail_now("YM2203 mono snd did not reset with clk_en disabled");
        $display("RESET_STATE clk_en=%b mono_acc=%h mono_snd=%h",
                 dut.clk_en, dut.gen_2203_acc.u_acc.u_mono.acc,
                 dut.gen_2203_acc.u_acc.hires);
        audit_jt49_inputs("reset_asserted_stable");

        @(negedge clk);
        monitor_enabled = 1'b1;
        reset = 1'b0;
        #1;
        audit_jt49_inputs("immediate_after_reset_release");
        if ((^dout === 1'bx) || (^snd_left === 1'bx) ||
            (^snd_right === 1'bx) || (^fm_snd_left === 1'bx) ||
            (^fm_snd_right === 1'bx) || (^psg_snd === 1'bx))
            fail_now("initial public output check failed immediately after reset release");
        if (snd_left !== snd_right || fm_snd_left !== fm_snd_right)
            fail_now("initial public mono outputs differ after reset release");
        $display("INITIAL_PUBLIC_OUTPUT dout=%02h fm_l=%0d fm_r=%0d snd_l=%0d snd_r=%0d psg=%0d",
                 dout, fm_snd_left, fm_snd_right, snd_left, snd_right, psg_snd);
        wait_cen_pulses(256);

        $display("CLOCK_CONFIG sys_hz=%0d chip_hz=%0d cen_div=%0d cen_width_sys_cycles=1",
                 SYS_CLK_HZ, CHIP_CLK_HZ, CEN_DIV);
        $display("STATUS_INTERFACE addr=0 cs_n=0 wr_n=1 busy_bit=7 busy_set=data_write_edge busy_clear=32_internal_fm_enables");

        // SSG channel A only. Tone A enabled, all noise and B/C tones disabled.
        ym2203_write(8'h08, 8'h00); // A mute while configuring
        ym2203_write(8'h09, 8'h00); // B mute
        ym2203_write(8'h0A, 8'h00); // C mute
        ym2203_write(8'h00, 8'h10); // tone A period low
        ym2203_write(8'h01, 8'h00); // tone A period high
        ym2203_write(8'h07, 8'h3E); // tone A on; noise and B/C tones off
        ym2203_write(8'h08, 8'h0F); // fixed maximum volume, envelope disabled
        wait_audio_updates(32);
        measure_phase("SSG_ON", 256, ssg_on_samples, ssg_on_changes,
                      ssg_on_min, ssg_on_max, ssg_on_unknowns);

        ym2203_write(8'h08, 8'h00); // mute channel A
        wait_audio_updates(64);
        measure_phase("SSG_MUTED", 128, ssg_mute_samples, ssg_mute_changes,
                      ssg_mute_min, ssg_mute_max, ssg_mute_unknowns);

        // Channel A noise only: tone disabled, A noise enabled, B/C muted.
        ym2203_write(8'h06, 8'h03); // explicit noise period
        ym2203_write(8'h07, 8'h37); // A noise on, all tones and B/C noise off
        ym2203_write(8'h08, 8'h0F); // fixed maximum volume
        wait_audio_updates(32);
        measure_phase("SSG_NOISE_ON", 256,
                      noise_on_samples, noise_on_changes,
                      noise_on_min, noise_on_max, noise_on_unknowns);
        ym2203_write(8'h08, 8'h00);
        wait_audio_updates(64);
        measure_phase("SSG_NOISE_MUTED", 128,
                      noise_mute_samples, noise_mute_changes,
                      noise_mute_min, noise_mute_max, noise_mute_unknowns);

        // Channel A tone with the JT49 envelope generator selected.
        ym2203_write(8'h00, 8'h10);
        ym2203_write(8'h01, 8'h00);
        ym2203_write(8'h07, 8'h3E); // A tone on, noise and B/C tones off
        ym2203_write(8'h0B, 8'h10); // envelope period low
        ym2203_write(8'h0C, 8'h00); // envelope period high
        ym2203_write(8'h0D, 8'h0A); // continue, alternate, repeating decay
        ym2203_write(8'h08, 8'h10); // channel A uses envelope volume
        wait_audio_updates(32);
        measure_phase("SSG_ENVELOPE_ON", 512,
                      envelope_on_samples, envelope_on_changes,
                      envelope_on_min, envelope_on_max, envelope_on_unknowns);
        ym2203_write(8'h08, 8'h00);
        wait_audio_updates(64);
        measure_phase("SSG_ENVELOPE_MUTED", 128,
                      envelope_mute_samples, envelope_mute_changes,
                      envelope_mute_min, envelope_mute_max,
                      envelope_mute_unknowns);

        // Reuse tb_md_sound_module.run_ym_tone_test's channel-0 OPN patch.
        // YM2612-only writes removed: 0x22 LFO, 0x2B DAC and 0xB4 pan.
        ym2203_write(8'h27, 8'h00); // timers off, normal channel mode
        ym2203_write(8'h28, 8'h00); // channel 0 key off

        ym2203_write(8'h30, 8'h01);
        ym2203_write(8'h34, 8'h01);
        ym2203_write(8'h38, 8'h01);
        ym2203_write(8'h3C, 8'h01);
        ym2203_write(8'h40, 8'h28);
        ym2203_write(8'h44, 8'h28);
        ym2203_write(8'h48, 8'h28);
        ym2203_write(8'h4C, 8'h28);
        ym2203_write(8'h50, 8'h1F);
        ym2203_write(8'h54, 8'h1F);
        ym2203_write(8'h58, 8'h1F);
        ym2203_write(8'h5C, 8'h1F);
        ym2203_write(8'h60, 8'h00);
        ym2203_write(8'h64, 8'h00);
        ym2203_write(8'h68, 8'h00);
        ym2203_write(8'h6C, 8'h00);
        ym2203_write(8'h70, 8'h00);
        ym2203_write(8'h74, 8'h00);
        ym2203_write(8'h78, 8'h00);
        ym2203_write(8'h7C, 8'h00);
        ym2203_write(8'h80, 8'h0F);
        ym2203_write(8'h84, 8'h0F);
        ym2203_write(8'h88, 8'h0F);
        ym2203_write(8'h8C, 8'h0F);
        ym2203_write(8'h90, 8'h00);
        ym2203_write(8'h94, 8'h00);
        ym2203_write(8'h98, 8'h00);
        ym2203_write(8'h9C, 8'h00);
        ym2203_write(8'hA4, 8'h22);
        ym2203_write(8'hA0, 8'h69);
        ym2203_write(8'hB0, 8'h07); // feedback 0, algorithm 7

        wait_audio_updates(32);
        measure_phase("FM_PRE_KEYON", 64, fm_pre_samples, fm_pre_changes,
                      fm_pre_min, fm_pre_max, fm_pre_unknowns);

        ym2203_write(8'h28, 8'hF0); // channel 0, all four operators on
        wait_audio_updates(64);
        measure_phase("FM_KEYON", 256, fm_on_samples, fm_on_changes,
                      fm_on_min, fm_on_max, fm_on_unknowns);

        ym2203_write(8'h28, 8'h00); // channel 0 key off
        wait_audio_updates(256);    // allow the configured release to settle
        measure_phase("FM_KEYOFF_SETTLED", 128, fm_off_samples, fm_off_changes,
                      fm_off_min, fm_off_max, fm_off_unknowns);

        if (address_write_count == 0 || address_write_count != data_write_count)
            fail_now("address/data write counts do not match");
        if (busy_observed_count != data_write_count)
            fail_now("busy was not observed for every data write");
        if (ssg_on_unknowns != 0 || noise_on_unknowns != 0 ||
            envelope_on_unknowns != 0 || fm_on_unknowns != 0 ||
            unknown_count != 0)
            fail_now("unknown audio/status value counted");
        if (ssg_on_changes < 8 || ssg_on_max <= ssg_on_min)
            fail_now("SSG tone did not produce public audio activity");
        if (ssg_mute_changes * 4 >= ssg_on_changes)
            fail_now("SSG mute did not reduce public audio activity");
        if (noise_on_changes < 8 || noise_on_max <= noise_on_min)
            fail_now("SSG noise did not produce public audio activity");
        if (noise_mute_changes * 4 >= noise_on_changes)
            fail_now("SSG noise mute did not reduce public audio activity");
        if (envelope_on_changes < 8 || envelope_on_max <= envelope_on_min)
            fail_now("SSG envelope did not produce public audio activity");
        if (envelope_mute_changes * 4 >= envelope_on_changes)
            fail_now("SSG envelope mute did not reduce public audio activity");
        if (fm_on_changes < 8 || fm_on_max <= fm_on_min)
            fail_now("FM key-on did not produce public audio activity");
        if (fm_pre_changes * 4 >= fm_on_changes)
            fail_now("FM key-on activity did not exceed pre-key-on activity");
        if (fm_off_changes * 4 >= fm_on_changes)
            fail_now("FM key-off did not reduce public audio activity");
        if (mono_mismatch_count != 0)
            fail_now("mono left/right mismatch counted");

        $display("PASS writes=%0d busy_observed=%0d audio_updates=%0d mono_mismatches=%0d unknowns=%0d",
                 data_write_count, busy_observed_count, audio_update_total,
                 mono_mismatch_count, unknown_count);
        $finish;
    end

    initial begin
        repeat (GLOBAL_TIMEOUT_CYCLES) @(posedge clk);
        fail_now("global simulation timeout");
    end

endmodule
