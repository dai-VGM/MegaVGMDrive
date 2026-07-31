`timescale 1ns/1ps

module tb_jt10_phase1a_fm_tone #(
    parameter integer TARGET_PORT = 0,
    parameter integer TARGET_ENCODING =
        TARGET_PORT == 0 ? 1 : 5,
    parameter integer PHASE1B_MODE = 0,
    parameter integer PHASE1C_MODE = 0
);
    localparam [63:0] FNV_OFFSET = 64'hcbf29ce484222325;
    localparam integer ATTACK_SAMPLES = 4096;
    localparam integer STEADY_SAMPLES = 4096;
    localparam integer MUTE_SAMPLES = 512;
    localparam integer POST_KEYOFF_SAMPLES = 512;
    localparam integer SILENCE_CONSECUTIVE = 256;
    localparam integer SILENCE_TIMEOUT = 8192;
    localparam [7:0] TARGET_CHANNEL_OFFSET =
        TARGET_ENCODING & 3;
    localparam [7:0] TARGET_FNUM_HIGH =
        8'ha4 + TARGET_CHANNEL_OFFSET;
    localparam [7:0] TARGET_FNUM_LOW =
        8'ha0 + TARGET_CHANNEL_OFFSET;
    localparam [7:0] TARGET_ALGORITHM =
        8'hb0 + TARGET_CHANNEL_OFFSET;
    localparam [7:0] TARGET_PAN =
        8'hb4 + TARGET_CHANNEL_OFFSET;
    localparam [7:0] TARGET_CARRIER_TL =
        8'h40 + TARGET_CHANNEL_OFFSET;
    localparam [7:0] TARGET_KEYON =
        8'h10 | TARGET_ENCODING;
    localparam [7:0] TARGET_KEYOFF = TARGET_ENCODING;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cen = 1'b0;
    logic session_start = 1'b1;
    logic loop_event = 1'b0;
    logic [7:0] adpcma_data = 8'ha5;
    logic [7:0] adpcmb_data = 8'h5a;

    wire [1:0] addr;
    wire [7:0] din;
    wire cs_n;
    wire wr_n;
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
    wire [9:0] psg_snd;
    wire signed [15:0] snd_left;
    wire signed [15:0] snd_right;
    wire snd_sample;
    wire signed [15:0] internal_snd_left;
    wire signed [15:0] internal_snd_right;
    wire internal_snd_sample;
    wire signed [15:0] internal_fm_snd;
    wire [2:0] warmup_count;
    wire warmup_ready;
    wire [2:0] reset_cen_count;
    wire reset_cen_valid;

    wire signed [15:0] adpcmA_l =
        dut.u_jt10.u_jt12.adpcmA_l;
    wire signed [15:0] adpcmA_r =
        dut.u_jt10.u_jt12.adpcmA_r;
    wire signed [15:0] adpcmB_l =
        dut.u_jt10.u_jt12.adpcmB_l;
    wire signed [15:0] adpcmB_r =
        dut.u_jt10.u_jt12.adpcmB_r;
    wire [2:0] cur_ch = dut.u_jt10.u_jt12.cur_ch;
    wire [1:0] cur_op = dut.u_jt10.u_jt12.cur_op;
    wire [1:0] current_rl = dut.u_jt10.u_jt12.rl;
    wire synth_clk_en = dut.u_jt10.u_jt12.clk_en;
    wire signed [15:0] accumulator_input_left =
        dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_input_l;
    wire signed [15:0] accumulator_fm_expected =
        dut.u_jt10.u_jt12.gen_adpcm.u_acc.opext >>> 1;
    wire signed [15:0] accumulator_adpcma_expected =
        (adpcmA_l <<< 2) + (adpcmA_l <<< 1);
    wire signed [15:0] accumulator_adpcmb_expected =
        adpcmB_l >>> 1;
    wire adpcma_decoder_active =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.decon;
    wire adpcmb_channel_on =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.chon;
    wire [7:0] adpcma_keyon_state =
        dut.u_jt10.u_jt12.aon_a;
    wire adpcmb_start_state =
        dut.u_jt10.u_jt12.acmd_on_b;

    wire [31:0] accepted_write_count;
    wire [31:0] port0_write_count;
    wire [31:0] port1_write_count;
    wire [31:0] busy_timeout_count;
    wire [31:0] busy_while_write_count;
    wire [31:0] busy_min_cycles;
    wire [31:0] busy_max_cycles;
    wire [31:0] last_issue_cycle;
    wire [31:0] last_busy_assert_cycle;
    wire [31:0] last_busy_clear_cycle;
    wire [63:0] busy_duration_hash;

    integer run_id = 1;
    integer system_cycle = 0;
    integer post_reset_cycle = 0;
    integer internal_pulse_count = 0;
    integer public_pulse_count = 0;
    integer warmup_ready_cycle = -1;
    integer first_public_cycle = -1;
    integer keyon_cycle = -1;
    integer first_nonzero_index = -1;
    integer cadence_error_count = 0;
    integer width_error_count = 0;
    integer sample_drop_count = 0;
    integer sample_duplicate_count = 0;
    integer sample_mismatch_count = 0;
    integer sample_x_count = 0;
    integer public_control_x_count = 0;
    integer psg_x_count = 0;
    integer psg_nonidle_count = 0;
    integer pcm_x_count = 0;
    integer pcm_nonidle_count = 0;
    integer selector_x_count = 0;
    integer adpcma_fetch_count = 0;
    integer adpcmb_fetch_count = 0;
    integer adpcma_inactive_strobe_count = 0;
    integer adpcmb_inactive_strobe_count = 0;
    integer adpcm_control_error_count = 0;
    integer accumulator_target_match_count = 0;
    integer accumulator_adpcma_match_count = 0;
    integer accumulator_adpcmb_match_count = 0;
    integer accumulator_select_mismatch_count = 0;
    integer failures = 0;
    integer last_public_rise_cycle = -1;
    integer public_pulse_width = 0;
    logic previous_internal_sample = 1'b0;
    logic previous_public_sample = 1'b0;
    logic previous_ready = 1'b0;

    logic [63:0] initial_silence_hash;
    logic [63:0] pre_keyon_hash;
    logic [63:0] attack_hash;
    logic [63:0] primary_attack_hash;
    logic [63:0] steady_hash;
    logic [63:0] keyoff_hash;
    logic [63:0] mute_hash;
    logic [63:0] frequency_hash;
    integer attack_nonzero;
    integer primary_attack_nonzero;
    integer steady_nonzero;
    integer steady_peak;
    integer steady_min;
    integer steady_max;
    integer steady_crossings;
    integer mute_nonzero;
    integer frequency_nonzero;
    integer frequency_peak;
    integer frequency_min;
    integer frequency_max;
    integer frequency_crossings;
    integer keyoff_nonzero;
    integer keyoff_settle_samples;
    integer mute_settle_samples = 0;
    integer last_dc_sum;
    integer steady_dc_sum;
    integer frequency_dc_sum;

    function automatic [63:0] hash_stereo(
        input [63:0] hash_in,
        input [15:0] left_sample,
        input [15:0] right_sample
    );
        integer byte_index;
        reg [31:0] stereo_sample;
        reg [63:0] hash_work;
        begin
            stereo_sample = {right_sample, left_sample};
            hash_work = hash_in;
            for (byte_index = 0; byte_index < 4;
                 byte_index = byte_index + 1)
                hash_work =
                    (hash_work ^
                     stereo_sample[byte_index*8 +: 8]) *
                    64'h00000100000001b3;
            hash_stereo = hash_work;
        end
    endfunction

    function automatic integer sample_abs(input signed [15:0] value);
        integer signed extended;
        begin
            extended = value;
            if (extended < 0)
                sample_abs = -extended;
            else
                sample_abs = extended;
        end
    endfunction

    always #5 clk = ~clk;

    always @(posedge clk) begin : sample_contract_monitor
        logic internal_rise;
        logic public_rise;
        logic reset_was_active;
        reset_was_active = rst;
        system_cycle = system_cycle + 1;
        if (!rst)
            post_reset_cycle = post_reset_cycle + 1;
        #1;

        internal_rise =
            internal_snd_sample === 1'b1 &&
            previous_internal_sample !== 1'b1;
        public_rise =
            snd_sample === 1'b1 &&
            previous_public_sample !== 1'b1;

        if (reset_was_active || session_start) begin
            previous_internal_sample = 1'b0;
            previous_public_sample = 1'b0;
            previous_ready = 1'b0;
            internal_pulse_count = 0;
            public_pulse_count = 0;
            public_pulse_width = 0;
            last_public_rise_cycle = -1;
        end else begin
            if ($isunknown(snd_sample))
                public_control_x_count =
                    public_control_x_count + 1;

            if (internal_rise)
                internal_pulse_count = internal_pulse_count + 1;

            if (warmup_ready === 1'b1 &&
                previous_ready !== 1'b1) begin
                warmup_ready_cycle = system_cycle;
                $display(
                    "WARMUP_READY system_cycle=%0d post_reset_cycle=%0d internal_pulses=%0d count=%0d",
                    system_cycle, post_reset_cycle,
                    internal_pulse_count, warmup_count
                );
            end

            if (!warmup_ready) begin
                if (snd_sample !== 1'b0 ||
                    snd_left !== 16'sd0 ||
                    snd_right !== 16'sd0) begin
                    failures = failures + 1;
                    $display(
                        "FAIL WARMUP_LEAK cycle=%0d sample=%b left=%h right=%h",
                        system_cycle, snd_sample, snd_left, snd_right
                    );
                end
            end

            if (internal_rise && warmup_ready) begin
                if (snd_sample !== 1'b1) begin
                    sample_drop_count = sample_drop_count + 1;
                    $display("FAIL SAMPLE_DROP cycle=%0d", system_cycle);
                end
                if (snd_left !== internal_snd_left ||
                    snd_right !== internal_snd_right) begin
                    sample_mismatch_count =
                        sample_mismatch_count + 1;
                    $display(
                        "FAIL INTERNAL_PUBLIC_MISMATCH cycle=%0d internal=%h/%h public=%h/%h",
                        system_cycle, internal_snd_left,
                        internal_snd_right, snd_left, snd_right
                    );
                end
            end

            if (public_rise) begin
                public_pulse_count = public_pulse_count + 1;
                if (!internal_rise) begin
                    sample_duplicate_count =
                        sample_duplicate_count + 1;
                    $display("FAIL SAMPLE_DUPLICATE cycle=%0d",
                             system_cycle);
                end
                if (public_pulse_count == 1) begin
                    first_public_cycle = system_cycle;
                    $display(
                        "FIRST_PUBLIC system_cycle=%0d post_reset_cycle=%0d internal_pulses=%0d",
                        system_cycle, post_reset_cycle,
                        internal_pulse_count
                    );
                    if (internal_pulse_count != 6) begin
                        failures = failures + 1;
                        $display(
                            "FAIL FIRST_PUBLIC_INTERNAL expected=6 actual=%0d",
                            internal_pulse_count
                        );
                    end
                end
                if (last_public_rise_cycle >= 0 &&
                    system_cycle - last_public_rise_cycle != 144) begin
                    cadence_error_count =
                        cadence_error_count + 1;
                    $display(
                        "FAIL SAMPLE_CADENCE previous=%0d current=%0d delta=%0d",
                        last_public_rise_cycle, system_cycle,
                        system_cycle - last_public_rise_cycle
                    );
                end
                last_public_rise_cycle = system_cycle;

                if ($isunknown(snd_left) ||
                    $isunknown(snd_right)) begin
                    sample_x_count = sample_x_count + 1;
                    $display(
                        "FAIL PUBLIC_SAMPLE_X cycle=%0d left=%h right=%h",
                        system_cycle, snd_left, snd_right
                    );
                end
                if ($isunknown(internal_fm_snd))
                    selector_x_count = selector_x_count + 1;

                if ($isunknown(psg_A) ||
                    $isunknown(psg_B) ||
                    $isunknown(psg_C) ||
                    $isunknown(psg_snd))
                    psg_x_count = psg_x_count + 1;
                else if (psg_A != 8'd0 || psg_B != 8'd0 ||
                         psg_C != 8'd0 || psg_snd != 10'd0)
                    psg_nonidle_count = psg_nonidle_count + 1;

                if ($isunknown(adpcmA_l) ||
                    $isunknown(adpcmA_r) ||
                    $isunknown(adpcmB_l) ||
                    $isunknown(adpcmB_r))
                    pcm_x_count = pcm_x_count + 1;
                else if (adpcmA_l != 16'sd0 ||
                         adpcmA_r != 16'sd0 ||
                         adpcmB_l != 16'sd0 ||
                         adpcmB_r != 16'sd0)
                    pcm_nonidle_count = pcm_nonidle_count + 1;
            end

            if (snd_sample === 1'b1) begin
                public_pulse_width = public_pulse_width + 1;
            end else if (previous_public_sample === 1'b1) begin
                if (public_pulse_width != 6) begin
                    width_error_count = width_error_count + 1;
                    $display("FAIL SAMPLE_WIDTH width=%0d cycle=%0d",
                             public_pulse_width, system_cycle);
                end
                public_pulse_width = 0;
            end

            previous_internal_sample = internal_snd_sample;
            previous_public_sample = snd_sample;
            previous_ready = warmup_ready;
        end

        if (!rst && adpcma_roe_n === 1'b0) begin
            if (adpcma_decoder_active === 1'b1)
                adpcma_fetch_count = adpcma_fetch_count + 1;
            else
                adpcma_inactive_strobe_count =
                    adpcma_inactive_strobe_count + 1;
        end
        if (!rst && adpcmb_roe_n === 1'b0) begin
            if (adpcmb_channel_on === 1'b1)
                adpcmb_fetch_count = adpcmb_fetch_count + 1;
            else
                // jt10_adpcmb_cnt advances its reset pipeline while off;
                // roe_n mirrors that internal flush, not a valid ROM fetch.
                adpcmb_inactive_strobe_count =
                    adpcmb_inactive_strobe_count + 1;
        end
        if (!rst &&
            (adpcma_keyon_state !== 8'h00 ||
             adpcmb_start_state !== 1'b0 ||
             adpcmb_channel_on !== 1'b0))
            adpcm_control_error_count =
                adpcm_control_error_count + 1;

        if (PHASE1C_MODE && !rst && synth_clk_en === 1'b1 &&
            cur_op == 2'd0) begin
            if (cur_ch == TARGET_ENCODING[2:0]) begin
                if (accumulator_input_left ===
                    accumulator_fm_expected)
                    accumulator_target_match_count =
                        accumulator_target_match_count + 1;
                else
                    accumulator_select_mismatch_count =
                        accumulator_select_mismatch_count + 1;
            end
            if (cur_ch == 3'd0) begin
                if (accumulator_input_left ===
                    accumulator_adpcma_expected)
                    accumulator_adpcma_match_count =
                        accumulator_adpcma_match_count + 1;
                else
                    accumulator_select_mismatch_count =
                        accumulator_select_mismatch_count + 1;
            end
            if (cur_ch == 3'd4) begin
                if (accumulator_input_left ===
                    accumulator_adpcmb_expected)
                    accumulator_adpcmb_match_count =
                        accumulator_adpcmb_match_count + 1;
                else
                    accumulator_select_mismatch_count =
                        accumulator_select_mismatch_count + 1;
            end
        end
    end

    task automatic wait_clocks(input integer count);
        repeat (count) @(posedge clk);
    endtask

    task automatic next_public_sample(
        output reg signed [15:0] left_value,
        output reg signed [15:0] right_value
    );
        begin
            @(posedge snd_sample);
            #1;
            left_value = snd_left;
            right_value = snd_right;
        end
    endtask

    task automatic capture_window(
        input integer sample_total,
        input [127:0] label,
        output reg [63:0] result_hash,
        output integer nonzero_count,
        output integer peak,
        output integer minimum,
        output integer maximum,
        output integer zero_crossings
    );
        integer index;
        integer left_integer;
        integer magnitude;
        integer previous_sign;
        integer current_sign;
        reg signed [15:0] left_value;
        reg signed [15:0] right_value;
        begin
            result_hash = FNV_OFFSET;
            nonzero_count = 0;
            peak = 0;
            minimum = 32767;
            maximum = -32768;
            zero_crossings = 0;
            previous_sign = 0;
            last_dc_sum = 0;
            for (index = 0; index < sample_total;
                 index = index + 1) begin
                next_public_sample(left_value, right_value);
                if ($isunknown(left_value) ||
                    $isunknown(right_value)) begin
                    failures = failures + 1;
                    $display("FAIL WINDOW_X label=%0s index=%0d",
                             label, index);
                end else begin
                    result_hash =
                        hash_stereo(result_hash,
                                    left_value, right_value);
                    left_integer = left_value;
                    last_dc_sum = last_dc_sum + left_integer;
                    if (left_value != 16'sd0 ||
                        right_value != 16'sd0) begin
                        nonzero_count = nonzero_count + 1;
                        if (label == "attack" &&
                            first_nonzero_index < 0)
                            first_nonzero_index = index;
                    end
                    magnitude = sample_abs(left_value);
                    if (sample_abs(right_value) > magnitude)
                        magnitude = sample_abs(right_value);
                    if (magnitude > peak)
                        peak = magnitude;
                    if (left_integer < minimum)
                        minimum = left_integer;
                    if (left_integer > maximum)
                        maximum = left_integer;
                    if (left_integer > 0)
                        current_sign = 1;
                    else if (left_integer < 0)
                        current_sign = -1;
                    else
                        current_sign = 0;
                    if (current_sign != 0) begin
                        if (previous_sign != 0 &&
                            previous_sign != current_sign)
                            zero_crossings =
                                zero_crossings + 1;
                        previous_sign = current_sign;
                    end
                    if (left_value == 16'sh7fff ||
                        left_value == 16'sh8000 ||
                        right_value == 16'sh7fff ||
                        right_value == 16'sh8000) begin
                        failures = failures + 1;
                        $display(
                            "FAIL CLIPPING label=%0s index=%0d left=%0d right=%0d",
                            label, index, left_value, right_value
                        );
                    end
                end
            end
            $display(
                "AUDIO_WINDOW label=%0s samples=%0d hash=%016h nonzero=%0d peak=%0d min=%0d max=%0d zero_crossings=%0d dc_sum=%0d dc_mean=%0d",
                label, sample_total, result_hash, nonzero_count,
                peak, minimum, maximum, zero_crossings,
                last_dc_sum, last_dc_sum / sample_total
            );
        end
    endtask

    task automatic wait_for_silence(output integer samples_used);
        integer consecutive;
        reg signed [15:0] left_value;
        reg signed [15:0] right_value;
        begin
            samples_used = 0;
            consecutive = 0;
            while (consecutive < SILENCE_CONSECUTIVE &&
                   samples_used < SILENCE_TIMEOUT) begin
                next_public_sample(left_value, right_value);
                samples_used = samples_used + 1;
                if ($isunknown(left_value) ||
                    $isunknown(right_value)) begin
                    failures = failures + 1;
                    consecutive = 0;
                end else if (left_value == 16'sd0 &&
                             right_value == 16'sd0) begin
                    consecutive = consecutive + 1;
                end else begin
                    consecutive = 0;
                end
            end
            $display(
                "KEYOFF_SETTLE samples=%0d consecutive_zero=%0d timeout=%0d",
                samples_used, consecutive,
                samples_used >= SILENCE_TIMEOUT
            );
            if (consecutive < SILENCE_CONSECUTIVE) begin
                failures = failures + 1;
                $display("FAIL KEYOFF_SETTLE_TIMEOUT samples=%0d",
                         samples_used);
            end
        end
    endtask

    task automatic wait_for_mute_silence(output integer samples_used);
        integer consecutive;
        reg signed [15:0] left_value;
        reg signed [15:0] right_value;
        begin
            samples_used = 0;
            consecutive = 0;
            while (consecutive < 16 && samples_used < 256) begin
                next_public_sample(left_value, right_value);
                samples_used = samples_used + 1;
                if ($isunknown(left_value) ||
                    $isunknown(right_value)) begin
                    failures = failures + 1;
                    consecutive = 0;
                end else if (left_value == 16'sd0 &&
                             right_value == 16'sd0) begin
                    consecutive = consecutive + 1;
                end else begin
                    consecutive = 0;
                end
            end
            $display(
                "MUTE_SETTLE samples=%0d consecutive_zero=%0d timeout=%0d keyon_maintained=1",
                samples_used, consecutive, samples_used >= 256
            );
            if (consecutive < 16) begin
                failures = failures + 1;
                $display("FAIL MUTE_SETTLE_TIMEOUT samples=%0d",
                         samples_used);
            end
        end
    endtask

    task automatic keyoff_all_channels;
        begin
            bus.jt10_write_port0(8'h28, 8'h00);
            bus.jt10_write_port0(8'h28, 8'h01);
            bus.jt10_write_port0(8'h28, 8'h02);
            bus.jt10_write_port0(8'h28, 8'h04);
            bus.jt10_write_port0(8'h28, 8'h05);
            bus.jt10_write_port0(8'h28, 8'h06);
        end
    endtask

    task automatic configure_operator(
        input [7:0] offset,
        input [7:0] total_level
    );
        begin
            // addr[1] selects the lower/upper part and the register's
            // low two bits select the channel within that part.
            write_target(
                8'h30 + TARGET_CHANNEL_OFFSET + offset, 8'h01);
            write_target(
                8'h40 + TARGET_CHANNEL_OFFSET + offset, total_level);
            write_target(
                8'h50 + TARGET_CHANNEL_OFFSET + offset, 8'h1f);
            write_target(
                8'h60 + TARGET_CHANNEL_OFFSET + offset, 8'h00);
            write_target(
                8'h70 + TARGET_CHANNEL_OFFSET + offset, 8'h00);
            write_target(
                8'h80 + TARGET_CHANNEL_OFFSET + offset, 8'haf);
            write_target(
                8'h90 + TARGET_CHANNEL_OFFSET + offset, 8'h00);
        end
    endtask

    task automatic write_target(
        input [7:0] reg_addr,
        input [7:0] reg_data
    );
        begin
            if (TARGET_PORT == 0)
                bus.jt10_write_port0(reg_addr, reg_data);
            else
                bus.jt10_write_port1(reg_addr, reg_data);
        end
    endtask

    task automatic configure_primary_tone;
        begin
            // Official fixture order: high latch, low commit, algorithm,
            // pan/AMS/PMS, then S1/S3/S2/S4 operator registers.
            write_target(TARGET_FNUM_HIGH, 8'h22);
            write_target(TARGET_FNUM_LOW, 8'h00);
            write_target(TARGET_ALGORITHM, 8'h07);
            write_target(TARGET_PAN, 8'hc0);
            configure_operator(8'h00, 8'h00);
            configure_operator(8'h08, 8'h7f);
            configure_operator(8'h04, 8'h7f);
            configure_operator(8'h0c, 8'h7f);
        end
    endtask

    task automatic audit_target_capture;
        integer guard;
        begin
            // A legal pan write proves the selected port/channel mapping
            // before key-on, so it cannot add audio to the idle window.
            write_target(TARGET_PAN, 8'hc0);
            #1;
            if (dut.u_jt10.u_jt12.u_mmr.part !== TARGET_PORT[0] ||
                dut.u_jt10.u_jt12.u_mmr.selected_register !==
                    TARGET_PAN ||
                dut.u_jt10.u_jt12.u_mmr.din_copy !== 8'hc0 ||
                dut.u_jt10.u_jt12.u_mmr.up_ch !==
                    TARGET_ENCODING[2:0] ||
                dut.u_jt10.u_jt12.u_mmr.up_chreg !== 3'b100) begin
                failures = failures + 1;
                $display(
                    "FAIL CHANNEL_CAPTURE target=%0d part=%b selected=%h data=%h ch=%0d chreg=%b",
                    TARGET_ENCODING,
                    dut.u_jt10.u_jt12.u_mmr.part,
                    dut.u_jt10.u_jt12.u_mmr.selected_register,
                    dut.u_jt10.u_jt12.u_mmr.din_copy,
                    dut.u_jt10.u_jt12.u_mmr.up_ch,
                    dut.u_jt10.u_jt12.u_mmr.up_chreg
                );
            end
            guard = 0;
            while (!(cur_ch == TARGET_ENCODING[2:0] &&
                     cur_op == 2'd0) &&
                   guard < 256) begin
                @(posedge clk);
                guard = guard + 1;
            end
            #1;
            if (guard >= 256 || current_rl !== 2'b11) begin
                failures = failures + 1;
                $display(
                    "FAIL CHANNEL_STATE target=%0d cur_ch=%0d cur_op=%0d rl=%b guard=%0d",
                    TARGET_ENCODING, cur_ch, cur_op,
                    current_rl, guard
                );
            end
            $display(
                "CHANNEL_AUDIT port=%0d address_phase=%02b data_phase=%02b selected=%02h data=c0 captured_part=%0d captured_ch=%0d rl=%0d result=%0s",
                TARGET_PORT, {TARGET_PORT[0], 1'b0},
                {TARGET_PORT[0], 1'b1}, TARGET_PAN,
                TARGET_PORT, TARGET_ENCODING, current_rl,
                (guard < 256 && current_rl === 2'b11) ?
                    "PASS" : "FAIL"
            );
        end
    endtask

    task automatic audit_port1_capture;
        integer guard;
        begin
            // Port 1 channel encoding 5: legal FM pan write, left/right on,
            // channel remains key-off and therefore cannot add audio.
            bus.jt10_write_port1(8'hb5, 8'hc0);
            #1;
            if (dut.u_jt10.u_jt12.u_mmr.part !== 1'b1 ||
                dut.u_jt10.u_jt12.u_mmr.selected_register !==
                    8'hb5 ||
                dut.u_jt10.u_jt12.u_mmr.din_copy !== 8'hc0 ||
                dut.u_jt10.u_jt12.u_mmr.up_ch !== 3'd5 ||
                dut.u_jt10.u_jt12.u_mmr.up_chreg !== 3'b100) begin
                failures = failures + 1;
                $display(
                    "FAIL PORT1_CAPTURE part=%b selected=%h data=%h ch=%0d chreg=%b",
                    dut.u_jt10.u_jt12.u_mmr.part,
                    dut.u_jt10.u_jt12.u_mmr.selected_register,
                    dut.u_jt10.u_jt12.u_mmr.din_copy,
                    dut.u_jt10.u_jt12.u_mmr.up_ch,
                    dut.u_jt10.u_jt12.u_mmr.up_chreg
                );
            end
            guard = 0;
            while (!(cur_ch == 3'd5 && cur_op == 2'd0) &&
                   guard < 256) begin
                @(posedge clk);
                guard = guard + 1;
            end
            #1;
            if (guard >= 256 || current_rl !== 2'b11) begin
                failures = failures + 1;
                $display(
                    "FAIL PORT1_STATE cur_ch=%0d cur_op=%0d rl=%b guard=%0d",
                    cur_ch, cur_op, current_rl, guard
                );
            end
            $display(
                "PORT1_AUDIT address_phase=10 data_phase=11 selected=b5 data=c0 captured_part=1 captured_ch=5 rl=%0d result=%0s",
                current_rl,
                (guard < 256 && current_rl === 2'b11) ?
                    "PASS" : "FAIL"
            );
        end
    endtask

    jt10_cpu_bus_bfm bus (
        .rst(rst), .clk(clk), .dout(dout),
        .addr(addr), .din(din), .cs_n(cs_n), .wr_n(wr_n),
        .accepted_write_count(accepted_write_count),
        .port0_write_count(port0_write_count),
        .port1_write_count(port1_write_count),
        .busy_timeout_count(busy_timeout_count),
        .busy_while_write_count(busy_while_write_count),
        .busy_min_cycles(busy_min_cycles),
        .busy_max_cycles(busy_max_cycles),
        .last_issue_cycle(last_issue_cycle),
        .last_busy_assert_cycle(last_busy_assert_cycle),
        .last_busy_clear_cycle(last_busy_clear_cycle),
        .busy_duration_hash(busy_duration_hash)
    );

    jt10_phase0_warmup_wrapper dut (
        .rst(rst), .clk(clk), .cen(cen),
        .session_start(session_start),
        .loop_event(loop_event),
        .addr(addr), .din(din), .cs_n(cs_n), .wr_n(wr_n),
        .irq_n(irq_n), .dout(dout),
        .snd_left(snd_left), .snd_right(snd_right),
        .snd_sample(snd_sample),
        .psg_A(psg_A), .psg_B(psg_B), .psg_C(psg_C),
        .psg_snd(psg_snd),
        .adpcma_addr(adpcma_addr), .adpcma_bank(adpcma_bank),
        .adpcma_roe_n(adpcma_roe_n), .adpcma_data(adpcma_data),
        .adpcmb_addr(adpcmb_addr), .adpcmb_roe_n(adpcmb_roe_n),
        .adpcmb_data(adpcmb_data),
        .internal_snd_left(internal_snd_left),
        .internal_snd_right(internal_snd_right),
        .internal_snd_sample(internal_snd_sample),
        .internal_fm_snd(internal_fm_snd),
        .warmup_count(warmup_count), .warmup_ready(warmup_ready),
        .reset_cen_count(reset_cen_count),
        .reset_cen_valid(reset_cen_valid)
    );

    initial begin : tone_sequence
        integer unused_peak;
        integer unused_min;
        integer unused_max;
        integer unused_crossings;
        integer initial_nonzero;
        integer no_keyon_nonzero;
        integer release_samples_frequency;

        if (!$value$plusargs("RUN_ID=%d", run_id))
            run_id = 1;
        if (PHASE1C_MODE)
            $display(
                "PHASE1C_BEGIN run=%0d target_port=%0d encoding=%0d",
                run_id, TARGET_PORT, TARGET_ENCODING);
        else if (PHASE1B_MODE)
            $display("PHASE1B_BEGIN run=%0d target_port=1 encoding=5",
                     run_id);
        else
            $display("PHASE1A_BEGIN run=%0d target_port=0 encoding=1",
                     run_id);

        // Phase 0 reset contract: establish session with CEN low, then give
        // reset 64 enabled chip clocks (minimum contract is six).
        wait_clocks(4);
        @(negedge clk);
        session_start = 1'b0;
        wait_clocks(12);
        @(negedge clk);
        cen = 1'b1;
        wait_clocks(64);
        @(negedge clk);
        cen = 1'b0;
        #1;
        $display(
            "RESET_CONTRACT requested=64 observed=%0d valid=%0d",
            reset_cen_count, reset_cen_valid
        );
        if (reset_cen_count !== 3'd6 ||
            reset_cen_valid !== 1'b1) begin
            failures = failures + 1;
            $display("FAIL RESET_CEN_CONTRACT");
        end

        rst = 1'b0;
        cen = 1'b1;
        post_reset_cycle = 0;

        wait (warmup_ready === 1'b1);
        wait (public_pulse_count >= 1);
        if ($isunknown(snd_left) ||
            $isunknown(snd_right)) begin
            failures = failures + 1;
            $display("FAIL READY_AUDIO_X");
        end
        capture_window(
            16, "initial_silence", initial_silence_hash,
            initial_nonzero, unused_peak, unused_min,
            unused_max, unused_crossings
        );
        if (initial_nonzero != 0) begin
            failures = failures + 1;
            $display("FAIL INITIAL_SILENCE_NONZERO count=%0d",
                     initial_nonzero);
        end

        keyoff_all_channels();
        bus.jt10_write_port0(8'h22, 8'h00);
        bus.jt10_write_port0(8'h27, 8'h00);
        bus.jt10_write_port0(8'h2b, 8'h00);
        if (PHASE1C_MODE)
            audit_target_capture();
        else
            // Preserve the exact Phase 1A/1B audit transaction.
            audit_port1_capture();
        configure_primary_tone();

        capture_window(
            16, "pre_keyon", pre_keyon_hash, no_keyon_nonzero,
            unused_peak, unused_min, unused_max, unused_crossings
        );
        if (no_keyon_nonzero != 0) begin
            failures = failures + 1;
            $display("FAIL PRE_KEYON_NONZERO count=%0d",
                     no_keyon_nonzero);
        end

        // Register 28 is a port-0 global register even when the channel
        // configuration belongs to port 1.
        bus.jt10_write_port0(8'h28, TARGET_KEYON);
        keyon_cycle = last_issue_cycle;
        capture_window(
            ATTACK_SAMPLES, "attack", attack_hash, attack_nonzero,
            unused_peak, unused_min, unused_max, unused_crossings
        );
        primary_attack_hash = attack_hash;
        primary_attack_nonzero = attack_nonzero;
        if (attack_nonzero == 0 || first_nonzero_index < 0) begin
            failures = failures + 1;
            $display("FAIL ATTACK_ALL_ZERO");
        end
        capture_window(
            STEADY_SAMPLES, "steady", steady_hash, steady_nonzero,
            steady_peak, steady_min, steady_max, steady_crossings
        );
        steady_dc_sum = last_dc_sum;
        if (steady_nonzero == 0 ||
            steady_hash == pre_keyon_hash) begin
            failures = failures + 1;
            $display("FAIL STEADY_TONE_CONTROL");
        end

        if (!PHASE1B_MODE && !PHASE1C_MODE) begin
            // Preserve the exact Phase 1A order and landmarks.
            bus.jt10_write_port0(8'h28, TARGET_KEYOFF);
            wait_for_silence(keyoff_settle_samples);
            capture_window(
                POST_KEYOFF_SAMPLES, "post_keyoff", keyoff_hash,
                keyoff_nonzero, unused_peak, unused_min,
                unused_max, unused_crossings
            );
            if (keyoff_nonzero != 0) begin
                failures = failures + 1;
                $display("FAIL KEYOFF_NONZERO count=%0d",
                         keyoff_nonzero);
            end

            write_target(8'h41, 8'h7f);
            bus.jt10_write_port0(8'h28, TARGET_KEYON);
            capture_window(
                MUTE_SAMPLES, "tl_mute", mute_hash, mute_nonzero,
                unused_peak, unused_min, unused_max, unused_crossings
            );
            if (mute_nonzero != 0) begin
                failures = failures + 1;
                $display("FAIL TL_MUTE_NONZERO count=%0d",
                         mute_nonzero);
            end
            bus.jt10_write_port0(8'h28, TARGET_KEYOFF);
            wait_for_silence(release_samples_frequency);

            write_target(8'h41, 8'h00);
            write_target(8'ha5, 8'h22);
            write_target(8'ha1, 8'hde);
            bus.jt10_write_port0(8'h28, TARGET_KEYON);
            capture_window(
                ATTACK_SAMPLES, "frequency_attack", attack_hash,
                attack_nonzero, unused_peak, unused_min,
                unused_max, unused_crossings
            );
            capture_window(
                STEADY_SAMPLES, "frequency_steady", frequency_hash,
                frequency_nonzero, frequency_peak, frequency_min,
                frequency_max, frequency_crossings
            );
            frequency_dc_sum = last_dc_sum;
            bus.jt10_write_port0(8'h28, TARGET_KEYOFF);
            wait_for_silence(release_samples_frequency);
        end else begin
            // Phase 1B/1C keep the target keyed while its carrier TL is
            // raised to maximum, proving that silence is TL-driven.
            write_target(TARGET_CARRIER_TL, 8'h7f);
            wait_for_mute_silence(mute_settle_samples);
            capture_window(
                MUTE_SAMPLES, "tl_mute", mute_hash, mute_nonzero,
                unused_peak, unused_min, unused_max, unused_crossings
            );
            if (mute_nonzero != 0) begin
                failures = failures + 1;
                $display("FAIL TL_MUTE_NONZERO count=%0d",
                         mute_nonzero);
            end

            // Restore the carrier and change the target FNUM while the
            // envelope remains keyed and at its steady level.
            write_target(TARGET_CARRIER_TL, 8'h00);
            write_target(TARGET_FNUM_HIGH, 8'h22);
            write_target(TARGET_FNUM_LOW, 8'hde);
            capture_window(
                STEADY_SAMPLES, "frequency_steady", frequency_hash,
                frequency_nonzero, frequency_peak, frequency_min,
                frequency_max, frequency_crossings
            );
            frequency_dc_sum = last_dc_sum;

            // Stage G is the only Phase 1B/1C key-off.
            bus.jt10_write_port0(8'h28, TARGET_KEYOFF);
            wait_for_silence(keyoff_settle_samples);
            capture_window(
                POST_KEYOFF_SAMPLES, "post_keyoff", keyoff_hash,
                keyoff_nonzero, unused_peak, unused_min,
                unused_max, unused_crossings
            );
            if (keyoff_nonzero != 0) begin
                failures = failures + 1;
                $display("FAIL KEYOFF_NONZERO count=%0d",
                         keyoff_nonzero);
            end
        end

        if (frequency_nonzero == 0 ||
            frequency_hash == steady_hash ||
            frequency_crossings == steady_crossings) begin
            failures = failures + 1;
            $display(
                "FAIL FREQUENCY_CONTROL primary_hash=%016h changed_hash=%016h primary_zc=%0d changed_zc=%0d",
                steady_hash, frequency_hash,
                steady_crossings, frequency_crossings
            );
        end

        if (PHASE1C_MODE) begin
            $display(
                "ACCUMULATOR_TRACE target_encoding=%0d target_default_matches=%0d encoding0_adpcma_matches=%0d encoding4_adpcmb_matches=%0d selector_mismatches=%0d predicate0={cur_op=0,cur_ch=0} predicate4={cur_op=0,cur_ch=4}",
                TARGET_ENCODING, accumulator_target_match_count,
                accumulator_adpcma_match_count,
                accumulator_adpcmb_match_count,
                accumulator_select_mismatch_count
            );
            if (accumulator_target_match_count == 0 ||
                accumulator_adpcma_match_count == 0 ||
                accumulator_adpcmb_match_count == 0 ||
                accumulator_select_mismatch_count != 0) begin
                failures = failures + 1;
                $display("FAIL ACCUMULATOR_SELECTION_TRACE");
            end
        end

        if (busy_timeout_count != 0 ||
            busy_while_write_count != 0 ||
            cadence_error_count != 0 ||
            width_error_count != 0 ||
            sample_drop_count != 0 ||
            sample_duplicate_count != 0 ||
            sample_mismatch_count != 0 ||
            sample_x_count != 0 ||
            public_control_x_count != 0 ||
            psg_x_count != 0 ||
            psg_nonidle_count != 0 ||
            pcm_x_count != 0 ||
            pcm_nonidle_count != 0 ||
            selector_x_count != 0 ||
            adpcma_fetch_count != 0 ||
            adpcmb_fetch_count != 0 ||
            adpcm_control_error_count != 0) begin
            failures = failures + 1;
            $display("FAIL AUDIT_COUNTER_NONZERO");
        end

        $display(
            "BUS_RESULT port0=%0d port1=%0d accepted=%0d timeout=%0d write_while_busy=%0d busy_min=%0d busy_max=%0d busy_hash=%016h",
            port0_write_count, port1_write_count,
            accepted_write_count, busy_timeout_count,
            busy_while_write_count, busy_min_cycles,
            busy_max_cycles, busy_duration_hash
        );
        $display(
            "SAMPLE_RESULT cadence=144 width=6 ready_cycle=%0d first_public_cycle=%0d internal_pulses_at_first=6 keyon_cycle=%0d first_nonzero_index=%0d public_samples=%0d cadence_errors=%0d width_errors=%0d drops=%0d duplicates=%0d mismatches=%0d",
            warmup_ready_cycle, first_public_cycle, keyon_cycle,
            first_nonzero_index, public_pulse_count,
            cadence_error_count, width_error_count,
            sample_drop_count, sample_duplicate_count,
            sample_mismatch_count
        );
        $display(
            "TONE_RESULT steady_samples=%0d attack_hash=%016h attack_nonzero=%0d steady_hash=%016h steady_nonzero=%0d peak=%0d min=%0d max=%0d zero_crossings=%0d dc_sum=%0d dc_mean=%0d initial_hash=%016h pre_hash=%016h mute_hash=%016h mute_nonzero=%0d mute_settle_samples=%0d frequency_hash=%016h frequency_nonzero=%0d frequency_peak=%0d frequency_min=%0d frequency_max=%0d frequency_zero_crossings=%0d frequency_dc_sum=%0d frequency_dc_mean=%0d keyoff_hash=%016h keyoff_nonzero=%0d keyoff_settle_samples=%0d",
            STEADY_SAMPLES, primary_attack_hash,
            primary_attack_nonzero,
            steady_hash, steady_nonzero,
            steady_peak, steady_min, steady_max, steady_crossings,
            steady_dc_sum, steady_dc_sum / STEADY_SAMPLES,
            initial_silence_hash, pre_keyon_hash,
            mute_hash, mute_nonzero, mute_settle_samples,
            frequency_hash, frequency_nonzero, frequency_peak,
            frequency_min, frequency_max, frequency_crossings,
            frequency_dc_sum, frequency_dc_sum / STEADY_SAMPLES,
            keyoff_hash, keyoff_nonzero, keyoff_settle_samples
        );
        $display(
            "TONE_COMPARE target_port=%0d target_encoding=%0d phase1a_hash=8aadd7a6819038e5 target_hash=%016h hash_equal=%0d phase1a_peak=4084 target_peak=%0d peak_delta=%0d phase1a_zero_crossings=32 target_zero_crossings=%0d crossing_delta=%0d",
            TARGET_PORT, TARGET_ENCODING,
            steady_hash, steady_hash == 64'h8aadd7a6819038e5,
            steady_peak, steady_peak - 4084,
            steady_crossings, steady_crossings - 32
        );
        $display(
            "IDLE_RESULT adpcma_fetch=%0d adpcmb_fetch=%0d adpcma_inactive_strobe=%0d adpcmb_inactive_strobe=%0d adpcm_control_errors=%0d psg_x=%0d psg_nonidle=%0d pcm_x=%0d pcm_nonidle=%0d selector_x=%0d sample_x=%0d",
            adpcma_fetch_count, adpcmb_fetch_count,
            adpcma_inactive_strobe_count,
            adpcmb_inactive_strobe_count,
            adpcm_control_error_count,
            psg_x_count, psg_nonidle_count,
            pcm_x_count, pcm_nonidle_count,
            selector_x_count, sample_x_count
        );
        if (PHASE1C_MODE)
            $display(
                "PHASE1C_RESULT run=%0d target_port=%0d target_encoding=%0d failures=%0d port0=%0d port1=%0d accepted=%0d busy_hash=%016h busy_min=%0d busy_max=%0d ready_cycle=%0d first_public_cycle=%0d keyon_cycle=%0d first_nonzero_index=%0d attack_hash=%016h steady_hash=%016h mute_hash=%016h mute_settle_samples=%0d frequency_hash=%016h keyoff_hash=%016h keyoff_settle_samples=%0d peak=%0d min=%0d max=%0d nonzero=%0d zero_crossings=%0d dc_sum=%0d cadence_errors=%0d width_errors=%0d x_count=%0d clipping=0 drops=%0d duplicates=%0d adpcm_fetch=%0d ssg_nonidle=%0d",
                run_id, TARGET_PORT, TARGET_ENCODING, failures,
                port0_write_count, port1_write_count,
                accepted_write_count, busy_duration_hash,
                busy_min_cycles, busy_max_cycles,
                warmup_ready_cycle, first_public_cycle,
                keyon_cycle, first_nonzero_index,
                primary_attack_hash, steady_hash, mute_hash,
                mute_settle_samples, frequency_hash, keyoff_hash,
                keyoff_settle_samples, steady_peak,
                steady_min, steady_max, steady_nonzero,
                steady_crossings, steady_dc_sum,
                cadence_error_count, width_error_count,
                sample_x_count + public_control_x_count +
                    psg_x_count + pcm_x_count + selector_x_count,
                sample_drop_count, sample_duplicate_count,
                adpcma_fetch_count + adpcmb_fetch_count,
                psg_nonidle_count
            );
        else if (PHASE1B_MODE)
            $display(
                "PHASE1B_RESULT run=%0d failures=%0d port0=%0d port1=%0d accepted=%0d busy_hash=%016h ready_cycle=%0d first_public_cycle=%0d keyon_cycle=%0d first_nonzero_index=%0d attack_hash=%016h steady_hash=%016h mute_hash=%016h frequency_hash=%016h keyoff_hash=%016h peak=%0d min=%0d max=%0d nonzero=%0d zero_crossings=%0d dc_sum=%0d cadence_errors=%0d width_errors=%0d x_count=%0d drops=%0d duplicates=%0d adpcm_fetch=%0d",
                run_id, failures, port0_write_count,
                port1_write_count, accepted_write_count,
                busy_duration_hash, warmup_ready_cycle,
                first_public_cycle, keyon_cycle,
                first_nonzero_index, primary_attack_hash, steady_hash,
                mute_hash, frequency_hash, keyoff_hash,
                steady_peak, steady_min, steady_max,
                steady_nonzero, steady_crossings, steady_dc_sum,
                cadence_error_count, width_error_count,
                sample_x_count + public_control_x_count +
                    psg_x_count + pcm_x_count + selector_x_count,
                sample_drop_count, sample_duplicate_count,
                adpcma_fetch_count + adpcmb_fetch_count
            );
        else
            $display(
                "PHASE1A_RESULT run=%0d failures=%0d accepted=%0d busy_hash=%016h ready_cycle=%0d first_public_cycle=%0d keyon_cycle=%0d first_nonzero_index=%0d steady_hash=%016h keyoff_hash=%016h cadence_errors=%0d width_errors=%0d x_count=%0d drops=%0d duplicates=%0d adpcm_fetch=%0d",
                run_id, failures, accepted_write_count,
                busy_duration_hash, warmup_ready_cycle,
                first_public_cycle, keyon_cycle,
                first_nonzero_index, steady_hash, keyoff_hash,
                cadence_error_count, width_error_count,
                sample_x_count + public_control_x_count +
                    psg_x_count + pcm_x_count + selector_x_count,
                sample_drop_count, sample_duplicate_count,
                adpcma_fetch_count + adpcmb_fetch_count
            );
        if (failures != 0)
            $fatal(1, "JT10 FM tone test failed (%0d)", failures);
        if (PHASE1C_MODE)
            $display(
                "PHASE1C_PASS run=%0d target_encoding=%0d",
                run_id, TARGET_ENCODING);
        else if (PHASE1B_MODE)
            $display("PHASE1B_PASS run=%0d", run_id);
        else
            $display("PHASE1A_PASS run=%0d", run_id);
        $finish;
    end
endmodule
