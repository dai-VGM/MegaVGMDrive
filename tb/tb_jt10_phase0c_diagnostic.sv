`timescale 1ns/1ps

module tb_jt10_phase0c_diagnostic;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cen = 1'b0;
    logic [7:0] din = 8'h00;
    logic [1:0] addr = 2'b00;
    logic cs_n = 1'b1;
    logic wr_n = 1'b1;
    logic [7:0] adpcma_data = 8'ha5;
    logic [7:0] adpcmb_data = 8'h5a;

    wire [7:0] dout;
    wire irq_n;
    wire [19:0] adpcma_addr;
    wire [3:0] adpcma_bank;
    wire adpcma_roe_n;
    wire [23:0] adpcmb_addr;
    wire adpcmb_roe_n;
    wire [7:0] psg_A, psg_B, psg_C;
    wire signed [15:0] fm_snd;
    wire [9:0] psg_snd;
    wire signed [15:0] snd_right, snd_left;
    wire snd_sample;

    integer reset_cen_count = 64;
    integer run_cycles = 20000;
    integer trace_pulses = 0;
    integer trace_slots = 0;
    integer diag_mode = 0;
    integer root_mask = 0;
    integer fm_init_mode = 0;
    integer start_delay = 0;
    integer system_cycle = 0;
    integer measurement_cycle = 0;
    integer operator_updates = 0;
    integer sample_pulses = 0;
    integer audio_x_pulses = 0;
    integer audio_x_cycles = 0;
    integer operator_x_updates = 0;
    integer acc_input_x_updates = 0;
    integer acc_enabled_x_updates = 0;
    integer first_known_strobe_pulse = -1;
    integer first_known_audio_pulse = -1;
    integer first_known_audio_cycle = -1;
    integer last_audio_x_cycle = -1;
    integer last_audio_x_pulse = -1;
    integer stable_audio_cycle = -1;
    integer first_fm_x = -1, last_fm_x = -1, known_fm_cycle = -1;
    integer first_public_x = -1, last_public_x = -1;
    integer known_public_cycle = -1;
    integer first_permanent_known_audio_pulse = -1;
    integer first_sample_start = -1;
    integer last_sample_start = -1;
    integer sample_interval = -1;
    integer pulse_width = -1;
    integer pulse_width_count = 0;
    integer pulse_start_cycle = -1;
    integer pulse_start_op = -1;
    integer pulse_start_ch = -1;
    integer pulse_had_audio_x = 0;
    integer sequence_errors = 0;
    integer init_start_cycle = -1;
    integer init_done_cycle = -1;
    integer failures = 0;
    logic measurement_enabled = 1'b0;
    logic previous_sample = 1'b0;
    logic pulse_active = 1'b0;
    logic [4:0] previous_sequence = 5'd0;
    logic previous_sequence_valid = 1'b0;
    logic [23:0] frame_op_x_mask = 24'd0;
    logic [23:0] frame_acc_x_mask = 24'd0;

    integer first_prev_x = -1, last_prev_x = -1, known_prev_cycle = -1;
    integer first_pm_x = -1, last_pm_x = -1, known_pm_cycle = -1;
    integer first_egpad_x = -1, last_egpad_x = -1, known_egpad_cycle = -1;
    integer first_float_x = -1, last_float_x = -1, known_float_cycle = -1;
    integer first_opxii_x = -1, last_opxii_x = -1, known_opxii_cycle = -1;
    integer first_opresult_x = -1, last_opresult_x = -1;
    integer known_opresult_cycle = -1;
    integer first_accin_x = -1, last_accin_x = -1, known_accin_cycle = -1;
    integer first_accstate_x = -1, last_accstate_x = -1;
    integer known_accstate_cycle = -1;

    wire diag_clk_en = dut.u_jt12.clk_en;
    wire [1:0] diag_cur_op = dut.u_jt12.cur_op;
    wire [2:0] diag_cur_ch = dut.u_jt12.cur_ch;
    wire diag_zero = dut.u_jt12.zero;
    wire signed [8:0] diag_op_result = dut.u_jt12.op_result;
    wire signed [13:0] diag_op_result_hd = dut.u_jt12.op_result_hd;
    wire signed [13:0] diag_op_internal =
        dut.u_jt12.u_op.op_result_internal;
    wire signed [13:0] diag_op_xii = dut.u_jt12.u_op.op_XII;
    wire [13:0] diag_prev1 = dut.u_jt12.u_op.prev1;
    wire [13:0] diag_prevprev1 = dut.u_jt12.u_op.prevprev1;
    wire [13:0] diag_prev2 = dut.u_jt12.u_op.prev2;
    wire [14:0] diag_pm_preshift = dut.u_jt12.u_op.pm_preshift_II;
    wire [9:0] diag_phasemod = dut.u_jt12.u_op.phasemod_VIII;
    wire [9:0] diag_phase = dut.u_jt12.u_op.phase;
    wire diag_sign_ix = dut.u_jt12.u_op.signbit_IX;
    wire [3:0] diag_exp_x = dut.u_jt12.u_op.exponent_X;
    wire [3:0] diag_exp_xi = dut.u_jt12.u_op.exponent_XI;
    wire [9:0] diag_mantissa_xi = dut.u_jt12.u_op.mantissa_XI;
    wire diag_sign_x = dut.u_jt12.u_op.signbit_X;
    wire diag_sign_xi = dut.u_jt12.u_op.signbit_XI;
    wire [9:0] diag_pg_phase = dut.u_jt12.phase_VIII;
    wire [9:0] diag_eg_pad = dut.u_jt12.eg_IX;
    wire [9:0] diag_eg = dut.u_jt12.eg_V;
    wire [2:0] diag_alg = dut.u_jt12.alg_I;
    wire [2:0] diag_fb = dut.u_jt12.fb_II;
    wire [1:0] diag_rl = dut.u_jt12.rl;
    wire [10:0] diag_fnum = dut.u_jt12.fnum_I;
    wire [2:0] diag_block = dut.u_jt12.block_I;
    wire [3:0] diag_mul = dut.u_jt12.mul_II;
    wire [6:0] diag_tl = dut.u_jt12.tl_IV;
    wire diag_keyon = dut.u_jt12.keyon_I;
    wire [6:0] diag_lfo = dut.u_jt12.lfo_mod;
    wire signed [15:0] diag_acc_input_l =
        dut.u_jt12.gen_adpcm.u_acc.acc_input_l;
    wire signed [15:0] diag_acc_input_r =
        dut.u_jt12.gen_adpcm.u_acc.acc_input_r;
    wire diag_acc_en_l = dut.u_jt12.gen_adpcm.u_acc.acc_en_l;
    wire diag_acc_en_r = dut.u_jt12.gen_adpcm.u_acc.acc_en_r;
    wire signed [15:0] diag_acc_l =
        dut.u_jt12.gen_adpcm.u_acc.u_left.acc;
    wire signed [15:0] diag_acc_r =
        dut.u_jt12.gen_adpcm.u_acc.u_right.acc;
    wire signed [15:0] diag_acc_next_l =
        dut.u_jt12.gen_adpcm.u_acc.u_left.next;
    wire signed [15:0] diag_acc_next_r =
        dut.u_jt12.gen_adpcm.u_acc.u_right.next;
    wire signed [15:0] diag_acc_snd_l =
        dut.u_jt12.gen_adpcm.u_acc.u_left.snd;
    wire signed [15:0] diag_acc_snd_r =
        dut.u_jt12.gen_adpcm.u_acc.u_right.snd;
    wire signed [15:0] diag_adpcma_l = dut.u_jt12.adpcmA_l;
    wire signed [15:0] diag_adpcma_r = dut.u_jt12.adpcmA_r;
    wire signed [15:0] diag_adpcmb_l = dut.u_jt12.adpcmB_l;
    wire signed [15:0] diag_adpcmb_r = dut.u_jt12.adpcmB_r;
    wire signed [15:0] diag_operator_direct = {
        {2{diag_op_result_hd[13]}}, diag_op_result_hd
    };
    wire signed [15:0] diag_fm_observed =
        diag_mode == 4 ? diag_operator_direct : fm_snd;
    wire signed [15:0] diag_snd_left_observed =
        diag_mode == 4 ? diag_operator_direct : snd_left;
    wire signed [15:0] diag_snd_right_observed =
        diag_mode == 4 ? diag_operator_direct : snd_right;

    logic signed [8:0] pulse_op_result;
    logic signed [13:0] pulse_op_result_hd;
    logic signed [15:0] pulse_acc_input;
    logic signed [15:0] pulse_acc_state;
    logic signed [15:0] pulse_fm;
    logic signed [15:0] pulse_adpcma;
    logic signed [15:0] pulse_adpcmb;
    logic signed [15:0] pulse_snd_l;
    logic signed [15:0] pulse_snd_r;
    logic [8:0] pulse_x_flags;
    logic [23:0] pulse_frame_op_x;
    logic [23:0] pulse_frame_acc_x;

    always #5 clk = ~clk;

    function automatic integer channel_index(input [2:0] channel_code);
        begin
            case (channel_code)
                3'd0: channel_index = 0;
                3'd1: channel_index = 1;
                3'd2: channel_index = 2;
                3'd4: channel_index = 3;
                3'd5: channel_index = 4;
                3'd6: channel_index = 5;
                default: channel_index = -1;
            endcase
        end
    endfunction

    function automatic integer slot_index(
        input [1:0] op_code,
        input [2:0] channel_code
    );
        integer ci;
        begin
            ci = channel_index(channel_code);
            slot_index = ci < 0 ? -1 : op_code * 6 + ci;
        end
    endfunction

    function automatic [4:0] expected_sequence_next(input [4:0] current);
        logic [1:0] op_now, op_next;
        logic [2:0] ch_now, ch_next;
        begin
            op_now = current[4:3];
            ch_now = current[2:0];
            op_next = ch_now == 3'd6 ? op_now + 1'b1 : op_now;
            ch_next = ch_now[1:0] == 2'b10 ?
                ch_now + 2'd2 : ch_now + 1'd1;
            expected_sequence_next = {op_next, ch_next};
        end
    endfunction

    task automatic update_convergence(
        input logic unknown_now,
        input integer cycle_now,
        inout integer first_x,
        inout integer last_x,
        inout integer known_cycle
    );
        begin
            if (unknown_now) begin
                if (first_x < 0)
                    first_x = cycle_now;
                last_x = cycle_now;
                known_cycle = -1;
            end else if (last_x >= 0 && known_cycle < 0) begin
                known_cycle = cycle_now;
            end
        end
    endtask

    task automatic wait_clocks(input integer count);
        repeat (count) @(posedge clk);
    endtask

    task automatic write_reg(
        input logic port1,
        input logic [7:0] reg_addr,
        input logic [7:0] reg_data
    );
        integer guard;
        begin
            @(negedge clk);
            cs_n = 1'b0;
            addr = port1 ? 2'b10 : 2'b00;
            din = reg_addr;
            wr_n = 1'b0;
            @(negedge clk);
            wr_n = 1'b1;
            @(negedge clk);
            addr = port1 ? 2'b11 : 2'b01;
            din = reg_data;
            wr_n = 1'b0;
            @(negedge clk);
            wr_n = 1'b1;
            cs_n = 1'b1;
            addr = 2'b00;
            din = 8'h00;
            guard = 0;
            @(posedge clk);
            #1;
            while (dout[7] !== 1'b0 && guard < 512) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end
            if (dout[7] !== 1'b0) begin
                failures = failures + 1;
                $display(
                    "FAIL BUSY timeout reg=%02x data=%02x",
                    reg_addr, reg_data
                );
            end
        end
    endtask

    task automatic keyoff_all;
        begin
            write_reg(1'b0, 8'h28, 8'h00);
            write_reg(1'b0, 8'h28, 8'h01);
            write_reg(1'b0, 8'h28, 8'h02);
            write_reg(1'b0, 8'h28, 8'h04);
            write_reg(1'b0, 8'h28, 8'h05);
            write_reg(1'b0, 8'h28, 8'h06);
        end
    endtask

    function automatic [7:0] operator_offset(input integer logical_op);
        begin
            case (logical_op)
                0: operator_offset = 8'h00;
                1: operator_offset = 8'h08;
                2: operator_offset = 8'h04;
                default: operator_offset = 8'h0c;
            endcase
        end
    endfunction

    task automatic full_fm_init;
        integer port_i, ch_i, op_i;
        logic port_bit;
        logic [7:0] op_addr;
        begin
            keyoff_all();
            for (port_i = 0; port_i < 2; port_i = port_i + 1) begin
                port_bit = port_i != 0;
                for (ch_i = 0; ch_i < 3; ch_i = ch_i + 1) begin
                    write_reg(port_bit, 8'hb0 + ch_i, 8'h00);
                    write_reg(port_bit, 8'hb4 + ch_i, 8'hc0);
                    write_reg(port_bit, 8'ha4 + ch_i, 8'h00);
                    write_reg(port_bit, 8'ha0 + ch_i, 8'h00);
                    for (op_i = 0; op_i < 4; op_i = op_i + 1) begin
                        op_addr = operator_offset(op_i) + ch_i;
                        write_reg(port_bit, 8'h30 + op_addr, 8'h01);
                        write_reg(port_bit, 8'h40 + op_addr, 8'h7f);
                        write_reg(port_bit, 8'h50 + op_addr, 8'h00);
                        write_reg(port_bit, 8'h60 + op_addr, 8'h00);
                        write_reg(port_bit, 8'h70 + op_addr, 8'h00);
                        write_reg(port_bit, 8'h80 + op_addr, 8'h0f);
                        write_reg(port_bit, 8'h90 + op_addr, 8'h00);
                    end
                end
            end
        end
    endtask

    always @(posedge clk) begin
        integer slot_before;
        logic [1:0] op_before;
        logic [2:0] ch_before;
        logic op_x_before;
        logic acc_x_before;
        logic acc_enabled_x_before;
        logic clk_en_before;

        clk_en_before = diag_clk_en;
        op_before = diag_cur_op;
        ch_before = diag_cur_ch;
        slot_before = slot_index(op_before, ch_before);
        op_x_before = $isunknown(diag_op_result_hd);
        acc_x_before =
            $isunknown(diag_acc_input_l) ||
            $isunknown(diag_acc_input_r);
        acc_enabled_x_before =
            (diag_acc_en_l === 1'b1 &&
             $isunknown(diag_acc_input_l)) ||
            (diag_acc_en_r === 1'b1 &&
             $isunknown(diag_acc_input_r));

        system_cycle = system_cycle + 1;
        #1;

        if (rst) begin
            previous_sequence = {diag_cur_op, diag_cur_ch};
            previous_sequence_valid =
                !$isunknown(diag_cur_op) &&
                !$isunknown(diag_cur_ch);
            previous_sample = snd_sample;
        end else if (measurement_enabled) begin
            measurement_cycle = measurement_cycle + 1;

            update_convergence(
                $isunknown(diag_prev1) ||
                $isunknown(diag_prevprev1) ||
                $isunknown(diag_prev2),
                system_cycle,
                first_prev_x, last_prev_x, known_prev_cycle
            );
            update_convergence(
                $isunknown(diag_pm_preshift) ||
                $isunknown(diag_phasemod),
                system_cycle,
                first_pm_x, last_pm_x, known_pm_cycle
            );
            update_convergence(
                $isunknown(diag_eg_pad),
                system_cycle,
                first_egpad_x, last_egpad_x, known_egpad_cycle
            );
            update_convergence(
                $isunknown(diag_sign_ix) ||
                $isunknown(diag_exp_x) ||
                $isunknown(diag_exp_xi) ||
                $isunknown(diag_mantissa_xi) ||
                $isunknown(diag_sign_x) ||
                $isunknown(diag_sign_xi),
                system_cycle,
                first_float_x, last_float_x, known_float_cycle
            );
            update_convergence(
                $isunknown(diag_op_xii),
                system_cycle,
                first_opxii_x, last_opxii_x, known_opxii_cycle
            );
            update_convergence(
                $isunknown(diag_op_result_hd),
                system_cycle,
                first_opresult_x, last_opresult_x,
                known_opresult_cycle
            );
            update_convergence(
                $isunknown(diag_acc_input_l) ||
                $isunknown(diag_acc_input_r),
                system_cycle,
                first_accin_x, last_accin_x, known_accin_cycle
            );
            update_convergence(
                $isunknown(diag_acc_l) ||
                $isunknown(diag_acc_r),
                system_cycle,
                first_accstate_x, last_accstate_x,
                known_accstate_cycle
            );
            update_convergence(
                $isunknown(diag_fm_observed),
                system_cycle,
                first_fm_x, last_fm_x, known_fm_cycle
            );
            update_convergence(
                $isunknown(diag_snd_left_observed) ||
                $isunknown(diag_snd_right_observed),
                system_cycle,
                first_public_x, last_public_x, known_public_cycle
            );

            if (clk_en_before === 1'b1) begin
                operator_updates = operator_updates + 1;
                if (op_x_before)
                    operator_x_updates = operator_x_updates + 1;
                if (acc_x_before)
                    acc_input_x_updates = acc_input_x_updates + 1;
                if (acc_enabled_x_before)
                    acc_enabled_x_updates = acc_enabled_x_updates + 1;
                if (slot_before >= 0) begin
                    if (op_x_before)
                        frame_op_x_mask[slot_before] = 1'b1;
                    if (acc_enabled_x_before)
                        frame_acc_x_mask[slot_before] = 1'b1;
                end
                if (previous_sequence_valid &&
                    {diag_cur_op, diag_cur_ch} !==
                    expected_sequence_next(previous_sequence))
                    sequence_errors = sequence_errors + 1;
                if (!$isunknown(diag_cur_op) &&
                    !$isunknown(diag_cur_ch)) begin
                    previous_sequence = {diag_cur_op, diag_cur_ch};
                    previous_sequence_valid = 1'b1;
                end
                if ((op_x_before || acc_enabled_x_before) &&
                    operator_updates <= trace_slots)
                    $display(
                        "SLOT_X update=%0d cycle=%0d op=%0d ch=%0d opres=%04x opXII=%04x prev=%04x/%04x/%04x pm=%04x/%03x pg=%03x eg=%03x float=%x/%x/%03x acc_in=%04x/%04x acc_en=%b/%b acc=%04x/%04x",
                        operator_updates, system_cycle,
                        op_before, ch_before,
                        diag_op_result_hd, diag_op_xii,
                        diag_prev1, diag_prevprev1, diag_prev2,
                        diag_pm_preshift, diag_phasemod,
                        diag_pg_phase, diag_eg_pad,
                        diag_exp_x, diag_exp_xi, diag_mantissa_xi,
                        diag_acc_input_l, diag_acc_input_r,
                        diag_acc_en_l, diag_acc_en_r,
                        diag_acc_l, diag_acc_r
                    );
            end

            if (!pulse_active &&
                previous_sample !== 1'b1 &&
                snd_sample === 1'b1) begin
                pulse_active = 1'b1;
                pulse_width_count = 1;
                pulse_start_cycle = system_cycle;
                pulse_had_audio_x =
                    $isunknown(diag_fm_observed) ||
                    $isunknown(diag_snd_left_observed) ||
                    $isunknown(diag_snd_right_observed);
                pulse_start_op = diag_cur_op;
                pulse_start_ch = diag_cur_ch;
                pulse_op_result = diag_op_result;
                pulse_op_result_hd = diag_op_result_hd;
                pulse_acc_input = diag_acc_input_l;
                pulse_acc_state = diag_acc_l;
                pulse_fm = diag_fm_observed;
                pulse_adpcma = diag_adpcma_l;
                pulse_adpcmb = diag_adpcmb_l;
                pulse_snd_l = diag_snd_left_observed;
                pulse_snd_r = diag_snd_right_observed;
                pulse_x_flags = {
                    $isunknown(diag_op_result),
                    $isunknown(diag_op_result_hd),
                    $isunknown(diag_acc_input_l),
                    $isunknown(diag_acc_l),
                    $isunknown(diag_fm_observed),
                    $isunknown(diag_adpcma_l),
                    $isunknown(diag_adpcmb_l),
                    $isunknown(diag_snd_left_observed),
                    $isunknown(diag_snd_right_observed)
                };
                pulse_frame_op_x = frame_op_x_mask;
                pulse_frame_acc_x = frame_acc_x_mask;
                frame_op_x_mask = 24'd0;
                frame_acc_x_mask = 24'd0;
            end else if (pulse_active && snd_sample === 1'b1) begin
                pulse_width_count = pulse_width_count + 1;
                if ($isunknown(diag_fm_observed) ||
                    $isunknown(diag_snd_left_observed) ||
                    $isunknown(diag_snd_right_observed))
                    pulse_had_audio_x = 1;
            end

            if (snd_sample === 1'b1 &&
                ($isunknown(diag_fm_observed) ||
                 $isunknown(diag_snd_left_observed) ||
                 $isunknown(diag_snd_right_observed))) begin
                audio_x_cycles = audio_x_cycles + 1;
                last_audio_x_cycle = system_cycle;
                stable_audio_cycle = -1;
            end else if (last_audio_x_cycle >= 0 &&
                         stable_audio_cycle < 0) begin
                stable_audio_cycle = system_cycle;
            end

            if (pulse_active && previous_sample === 1'b1 &&
                snd_sample === 1'b0) begin
                sample_pulses = sample_pulses + 1;
                pulse_width = pulse_width_count;
                if (pulse_had_audio_x != 0) begin
                    audio_x_pulses = audio_x_pulses + 1;
                    last_audio_x_pulse = sample_pulses;
                end
                if (first_known_strobe_pulse < 0)
                    first_known_strobe_pulse = sample_pulses;
                if (pulse_had_audio_x == 0 &&
                    first_known_audio_pulse < 0) begin
                    first_known_audio_pulse = sample_pulses;
                    first_known_audio_cycle = pulse_start_cycle;
                end
                if (last_sample_start >= 0)
                    sample_interval = pulse_start_cycle - last_sample_start;
                if (first_sample_start < 0)
                    first_sample_start = pulse_start_cycle;
                last_sample_start = pulse_start_cycle;
                if (sample_pulses <= trace_pulses)
                    $display(
                        "PULSE n=%0d range=%0d-%0d op=%0d ch=%0d zero=1 sample=1 opres9=%03x opres14=%04x acc_in=%04x acc=%04x fm=%04x adpcma=%04x adpcmb=%04x snd=%04x/%04x xflags=%03x frame_op_x=%06x frame_acc_x=%06x",
                        sample_pulses, pulse_start_cycle,
                        system_cycle-1, pulse_start_op, pulse_start_ch,
                        pulse_op_result, pulse_op_result_hd,
                        pulse_acc_input,
                        pulse_acc_state, pulse_fm,
                        pulse_adpcma, pulse_adpcmb,
                        pulse_snd_l, pulse_snd_r, pulse_x_flags,
                        pulse_frame_op_x, pulse_frame_acc_x
                    );
                pulse_active = 1'b0;
                pulse_width_count = 0;
            end
            previous_sample = snd_sample;
        end
    end

    jt10 dut (
        .rst(rst), .clk(clk), .cen(cen),
        .din(din), .addr(addr), .cs_n(cs_n), .wr_n(wr_n),
        .dout(dout), .irq_n(irq_n),
        .adpcma_addr(adpcma_addr), .adpcma_bank(adpcma_bank),
        .adpcma_roe_n(adpcma_roe_n), .adpcma_data(adpcma_data),
        .adpcmb_addr(adpcmb_addr), .adpcmb_roe_n(adpcmb_roe_n),
        .adpcmb_data(adpcmb_data),
        .psg_A(psg_A), .psg_B(psg_B), .psg_C(psg_C),
        .fm_snd(fm_snd), .psg_snd(psg_snd),
        .snd_right(snd_right), .snd_left(snd_left),
        .snd_sample(snd_sample)
    );

    initial begin
        if (!$value$plusargs("RESET_CEN=%d", reset_cen_count))
            reset_cen_count = 64;
        if (!$value$plusargs("RUN_CYCLES=%d", run_cycles))
            run_cycles = 20000;
        if (!$value$plusargs("TRACE_PULSES=%d", trace_pulses))
            trace_pulses = 0;
        if (!$value$plusargs("TRACE_SLOTS=%d", trace_slots))
            trace_slots = 0;
        if (!$value$plusargs("MODE=%d", diag_mode))
            diag_mode = 0;
        if (!$value$plusargs("ROOT_MASK=%d", root_mask))
            root_mask = 0;
        if (!$value$plusargs("FM_INIT=%d", fm_init_mode))
            fm_init_mode = 0;
        if (!$value$plusargs("START_DELAY=%d", start_delay))
            start_delay = 0;

        case (diag_mode)
            1: begin
                force dut.u_jt12.op_result_hd = 14'sd0;
            end
            2: begin
                force dut.u_jt12.adpcmA_l = 16'sd0;
                force dut.u_jt12.adpcmA_r = 16'sd0;
                force dut.u_jt12.adpcmB_l = 16'sd0;
                force dut.u_jt12.adpcmB_r = 16'sd0;
            end
            3: begin
                force dut.u_jt12.op_result_hd = 14'sd0;
                force dut.u_jt12.adpcmA_l = 16'sd0;
                force dut.u_jt12.adpcmA_r = 16'sd0;
                force dut.u_jt12.adpcmB_l = 16'sd0;
                force dut.u_jt12.adpcmB_r = 16'sd0;
            end
            4: begin
                // The monitor selects diag_operator_direct instead of the
                // accumulator/public output for this diagnostic mode.
            end
        endcase
        if ((root_mask & 1) != 0)
            force dut.u_jt12.u_op.prev1 = 14'd0;
        if ((root_mask & 2) != 0)
            force dut.u_jt12.u_op.prevprev1 = 14'd0;
        if ((root_mask & 4) != 0)
            force dut.u_jt12.u_op.prev2 = 14'd0;
        if ((root_mask & 8) != 0)
            force dut.u_jt12.u_op.pm_preshift_II = 15'd0;
        if ((root_mask & 16) != 0)
            force dut.u_jt12.u_op.phasemod_VIII = 10'd0;

        wait_clocks(16);
        if (reset_cen_count > 0) begin
            cen = 1'b1;
            wait_clocks(reset_cen_count);
            cen = 1'b0;
        end
        @(negedge clk);
        rst = 1'b0;
        cen = 1'b1;

        init_start_cycle = system_cycle;
        if (fm_init_mode == 1)
            keyoff_all();
        else if (fm_init_mode == 2)
            full_fm_init();
        if (start_delay > 0)
            wait_clocks(start_delay);
        init_done_cycle = system_cycle;

        previous_sample = 1'b0;
        measurement_enabled = 1'b1;
        wait_clocks(run_cycles);
        #1;
        if (last_audio_x_pulse < 0)
            first_permanent_known_audio_pulse =
                sample_pulses > 0 ? 1 : -1;
        else if (sample_pulses > last_audio_x_pulse)
            first_permanent_known_audio_pulse =
                last_audio_x_pulse + 1;

        $display(
            "PHASE0C_RESULT reset_cen=%0d mode=%0d root_mask=%0d fm_init=%0d init_cycles=%0d run=%0d pulses=%0d audio_x_pulses=%0d audio_x_cycles=%0d first_known_strobe_pulse=%0d first_known_audio_pulse=%0d first_known_audio_cycle=%0d last_audio_x_pulse=%0d last_audio_x_cycle=%0d first_permanent_known_audio_pulse=%0d updates=%0d sequence_errors=%0d sample_interval=%0d pulse_width=%0d",
            reset_cen_count, diag_mode, root_mask, fm_init_mode,
            init_done_cycle-init_start_cycle, run_cycles,
            sample_pulses, audio_x_pulses, audio_x_cycles,
            first_known_strobe_pulse, first_known_audio_pulse,
            first_known_audio_cycle, last_audio_x_pulse,
            last_audio_x_cycle, first_permanent_known_audio_pulse,
            operator_updates, sequence_errors,
            sample_interval, pulse_width
        );
        $display(
            "ROOT_RESULT prev=%0d/%0d/%0d pm=%0d/%0d/%0d egpad=%0d/%0d/%0d float=%0d/%0d/%0d opxii=%0d/%0d/%0d opresult=%0d/%0d/%0d accin=%0d/%0d/%0d accstate=%0d/%0d/%0d op_x_updates=%0d acc_input_x_updates=%0d acc_enabled_x_updates=%0d",
            first_prev_x, last_prev_x, known_prev_cycle,
            first_pm_x, last_pm_x, known_pm_cycle,
            first_egpad_x, last_egpad_x, known_egpad_cycle,
            first_float_x, last_float_x, known_float_cycle,
            first_opxii_x, last_opxii_x, known_opxii_cycle,
            first_opresult_x, last_opresult_x, known_opresult_cycle,
            first_accin_x, last_accin_x, known_accin_cycle,
            first_accstate_x, last_accstate_x, known_accstate_cycle,
            operator_x_updates, acc_input_x_updates,
            acc_enabled_x_updates
        );
        $display(
            "OUTPUT_RESULT fm=%0d/%0d/%0d public=%0d/%0d/%0d sample_valid_stable_hint=%0d",
            first_fm_x, last_fm_x, known_fm_cycle,
            first_public_x, last_public_x, known_public_cycle,
            stable_audio_cycle
        );
        $display(
            "STATE_RESULT op=%x ch=%x zero=%b sample=%b pg=%03x eg=%03x keyon=%b alg=%x fb=%x rl=%x fnum=%03x block=%x mul=%x tl=%02x lfo=%02x opres=%04x acc=%04x/%04x fm=%04x snd=%04x/%04x",
            diag_cur_op, diag_cur_ch, diag_zero, snd_sample,
            diag_pg_phase, diag_eg_pad, diag_keyon,
            diag_alg, diag_fb, diag_rl, diag_fnum,
            diag_block, diag_mul, diag_tl, diag_lfo,
            diag_op_result_hd, diag_acc_l, diag_acc_r,
            fm_snd, snd_left, snd_right
        );
        $display(
            "INPUT_RESULT unknowns=%0d values=%02x/%x/%b/%b/%02x/%02x failures=%0d",
            $isunknown(din) + $isunknown(addr) +
            $isunknown(cs_n) + $isunknown(wr_n) +
            $isunknown(adpcma_data) + $isunknown(adpcmb_data),
            din, addr, cs_n, wr_n, adpcma_data, adpcmb_data,
            failures
        );
        $finish;
    end

    initial begin
        #5000000;
        $fatal(1, "timeout");
    end
endmodule
