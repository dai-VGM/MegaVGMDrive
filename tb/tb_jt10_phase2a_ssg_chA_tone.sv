`timescale 1ns/1ps

module tb_jt10_phase2a_ssg_chA_tone;
    localparam [63:0] FNV_OFFSET = 64'hcbf29ce484222325;
    localparam integer START_SAMPLES = 256;
    localparam integer TONE_SAMPLES = 4096;
    localparam integer CONTROL_SAMPLES = 512;

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
    wire adpcma_decoder_active =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.decon;
    wire adpcmb_channel_on =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.chon;
    wire [7:0] adpcma_command =
        dut.u_jt10.u_jt12.aon_a;
    wire adpcma_command_update =
        dut.u_jt10.u_jt12.up_aon;
    wire adpcmb_start_state =
        dut.u_jt10.u_jt12.acmd_on_b;

    wire [3:0] internal_psg_addr =
        dut.u_jt10.u_jt12.psg_addr;
    wire [7:0] internal_psg_data =
        dut.u_jt10.u_jt12.psg_data;
    wire internal_psg_register_edge =
        dut.u_jt10.u_jt12.gen_ssg.u_psg.wr_edge;
    wire internal_tone_a =
        dut.u_jt10.u_jt12.gen_ssg.u_psg.bitA;
    wire [7:0] internal_mixer =
        dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[7];
    wire [7:0] internal_volume_a =
        dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[8];
    wire [7:0] internal_volume_b =
        dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[9];
    wire [7:0] internal_volume_c =
        dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[10];
    wire [7:0] internal_envelope_low =
        dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[11];
    wire [7:0] internal_envelope_high =
        dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[12];
    wire [7:0] internal_envelope_shape =
        dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[13];

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
    integer tone_enable_cycle = -1;
    integer first_nonzero_index = -1;
    integer cadence_error_count = 0;
    integer width_error_count = 0;
    integer sample_drop_count = 0;
    integer sample_duplicate_count = 0;
    integer sample_mismatch_count = 0;
    integer public_x_count = 0;
    integer clipping_count = 0;
    integer adpcma_fetch_count = 0;
    integer adpcmb_fetch_count = 0;
    integer adpcma_keyon_command_count = 0;
    integer ssg_register_update_count = 0;
    integer ssg_transport_error_count = 0;
    integer noise_enable_event_count = 0;
    integer bc_enable_event_count = 0;
    integer envelope_enable_event_count = 0;
    integer failures = 0;
    integer last_public_rise_cycle = -1;
    integer public_pulse_width = 0;
    logic previous_internal_sample = 1'b0;
    logic previous_public_sample = 1'b0;
    logic previous_ready = 1'b0;
    logic ssg_expect_pending = 1'b0;
    logic [3:0] expected_ssg_addr = 4'd0;
    logic [7:0] expected_ssg_data = 8'd0;
    logic audit_active = 1'b0;

    logic [63:0] initial_hash;
    logic [63:0] explicit_silence_hash;
    logic [63:0] start_final_hash;
    logic [63:0] start_raw_a_hash;
    logic [63:0] start_psg_hash;
    logic [63:0] primary_final_hash;
    logic [63:0] primary_raw_a_hash;
    logic [63:0] primary_psg_hash;
    logic [63:0] volume_mute_hash;
    logic [63:0] mixer_dc_hash;
    logic [63:0] mixer_dc_raw_a_hash;
    logic [63:0] mixer_dc_psg_hash;
    logic [63:0] changed_final_hash;
    logic [63:0] changed_raw_a_hash;
    logic [63:0] changed_psg_hash;
    logic [63:0] final_stop_hash;
    integer primary_nonzero;
    integer primary_peak;
    integer primary_min;
    integer primary_max;
    integer primary_transitions;
    integer primary_raw_nonzero;
    integer primary_psg_nonzero;
    integer primary_oscillator_toggles;
    longint signed primary_dc_sum;
    integer mixer_dc_nonzero;
    integer mixer_dc_peak;
    integer mixer_dc_min;
    integer mixer_dc_max;
    integer mixer_dc_transitions;
    integer mixer_dc_raw_nonzero;
    integer mixer_dc_psg_nonzero;
    integer mixer_dc_oscillator_toggles;
    longint signed mixer_dc_sum;
    integer changed_nonzero;
    integer changed_peak;
    integer changed_min;
    integer changed_max;
    integer changed_transitions;
    integer changed_raw_nonzero;
    integer changed_psg_nonzero;
    integer changed_oscillator_toggles;
    longint signed changed_dc_sum;
    integer volume_mute_settle_samples;
    integer mixer_dc_lock_samples;
    integer final_stop_settle_samples;

    function automatic [63:0] hash_byte(
        input [63:0] hash_in,
        input [7:0] value
    );
        hash_byte =
            (hash_in ^ value) * 64'h00000100000001b3;
    endfunction

    function automatic [63:0] hash_stereo(
        input [63:0] hash_in,
        input [15:0] left_sample,
        input [15:0] right_sample
    );
        reg [63:0] hash_work;
        begin
            hash_work = hash_byte(hash_in, left_sample[7:0]);
            hash_work = hash_byte(hash_work, left_sample[15:8]);
            hash_work = hash_byte(hash_work, right_sample[7:0]);
            hash_stereo =
                hash_byte(hash_work, right_sample[15:8]);
        end
    endfunction

    function automatic integer sample_abs(input signed [15:0] value);
        integer signed extended;
        begin
            extended = value;
            sample_abs = extended < 0 ? -extended : extended;
        end
    endfunction

    always #5 clk = ~clk;

    always @(posedge clk) begin : register_update_monitor
        if (rst) begin
            ssg_register_update_count = 0;
        end else if (internal_psg_register_edge) begin
            ssg_register_update_count =
                ssg_register_update_count + 1;
            if (!ssg_expect_pending ||
                internal_psg_addr !== expected_ssg_addr ||
                internal_psg_data !== expected_ssg_data) begin
                ssg_transport_error_count =
                    ssg_transport_error_count + 1;
                $display(
                    "FAIL SSG_REGISTER_PULSE pending=%0d expected=%h/%h actual=%h/%h",
                    ssg_expect_pending, expected_ssg_addr,
                    expected_ssg_data, internal_psg_addr,
                    internal_psg_data
                );
            end
            ssg_expect_pending = 1'b0;
        end
    end

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

            if (!warmup_ready &&
                (snd_sample !== 1'b0 ||
                 snd_left !== 16'sd0 ||
                 snd_right !== 16'sd0)) begin
                failures = failures + 1;
                $display("FAIL WARMUP_LEAK cycle=%0d", system_cycle);
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
                        "FAIL INTERNAL_PUBLIC_MISMATCH cycle=%0d",
                        system_cycle
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
            end

            if (snd_sample === 1'b1)
                public_pulse_width = public_pulse_width + 1;
            else if (previous_public_sample === 1'b1) begin
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

        if (!rst && adpcma_roe_n === 1'b0 &&
            adpcma_decoder_active === 1'b1)
            adpcma_fetch_count = adpcma_fetch_count + 1;
        if (!rst && adpcmb_roe_n === 1'b0 &&
            adpcmb_channel_on === 1'b1)
            adpcmb_fetch_count = adpcmb_fetch_count + 1;
        if (!rst && adpcma_command_update &&
            !adpcma_command[7] && |adpcma_command[5:0])
            adpcma_keyon_command_count =
                adpcma_keyon_command_count + 1;

        if (audit_active) begin
            if (internal_mixer[5:3] !== 3'b111)
                noise_enable_event_count =
                    noise_enable_event_count + 1;
            if (internal_mixer[2:1] !== 2'b11 ||
                internal_volume_b !== 8'h00 ||
                internal_volume_c !== 8'h00)
                bc_enable_event_count =
                    bc_enable_event_count + 1;
            if (internal_volume_a[4] !== 1'b0 ||
                internal_volume_b[4] !== 1'b0 ||
                internal_volume_c[4] !== 1'b0)
                envelope_enable_event_count =
                    envelope_enable_event_count + 1;
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

    task automatic capture_ssg_window(
        input integer sample_total,
        input [127:0] label,
        output reg [63:0] final_hash,
        output reg [63:0] raw_a_hash,
        output reg [63:0] combined_hash,
        output integer nonzero_count,
        output integer peak,
        output integer minimum,
        output integer maximum,
        output integer zero_transitions,
        output longint signed dc_sum,
        output integer raw_a_nonzero,
        output integer combined_nonzero,
        output integer oscillator_toggles
    );
        integer index;
        integer left_integer;
        integer magnitude;
        integer previous_active;
        integer current_active;
        integer previous_oscillator;
        integer local_x_count;
        integer raw_b_nonzero;
        integer raw_c_nonzero;
        integer fm_nonzero;
        integer pcm_nonzero;
        reg signed [15:0] left_value;
        reg signed [15:0] right_value;
        reg [15:0] combined_value;
        begin
            final_hash = FNV_OFFSET;
            raw_a_hash = FNV_OFFSET;
            combined_hash = FNV_OFFSET;
            nonzero_count = 0;
            peak = 0;
            minimum = 32767;
            maximum = -32768;
            zero_transitions = 0;
            dc_sum = 0;
            raw_a_nonzero = 0;
            combined_nonzero = 0;
            oscillator_toggles = 0;
            previous_active = -1;
            previous_oscillator = -1;
            local_x_count = 0;
            raw_b_nonzero = 0;
            raw_c_nonzero = 0;
            fm_nonzero = 0;
            pcm_nonzero = 0;

            for (index = 0; index < sample_total;
                 index = index + 1) begin
                next_public_sample(left_value, right_value);
                if ($isunknown(left_value) ||
                    $isunknown(right_value) ||
                    $isunknown(psg_A) ||
                    $isunknown(psg_B) ||
                    $isunknown(psg_C) ||
                    $isunknown(psg_snd) ||
                    $isunknown(internal_fm_snd) ||
                    $isunknown(adpcmA_l) ||
                    $isunknown(adpcmA_r) ||
                    $isunknown(adpcmB_l) ||
                    $isunknown(adpcmB_r) ||
                    $isunknown(internal_tone_a)) begin
                    local_x_count = local_x_count + 1;
                    public_x_count = public_x_count + 1;
                    $display("FAIL WINDOW_X label=%0s index=%0d",
                             label, index);
                end else begin
                    final_hash =
                        hash_stereo(final_hash,
                                    left_value, right_value);
                    raw_a_hash = hash_byte(raw_a_hash, psg_A);
                    combined_value = {6'd0, psg_snd};
                    combined_hash =
                        hash_byte(
                            hash_byte(combined_hash,
                                      combined_value[7:0]),
                            combined_value[15:8]);

                    left_integer = left_value;
                    dc_sum = dc_sum + left_integer;
                    if (left_value != 16'sd0 ||
                        right_value != 16'sd0) begin
                        nonzero_count = nonzero_count + 1;
                        if (label == "tone_start" &&
                            first_nonzero_index < 0)
                            first_nonzero_index = index;
                    end
                    if (psg_A != 8'd0)
                        raw_a_nonzero = raw_a_nonzero + 1;
                    if (psg_snd != 10'd0)
                        combined_nonzero = combined_nonzero + 1;
                    if (psg_B != 8'd0)
                        raw_b_nonzero = raw_b_nonzero + 1;
                    if (psg_C != 8'd0)
                        raw_c_nonzero = raw_c_nonzero + 1;
                    if (internal_fm_snd != 16'sd0)
                        fm_nonzero = fm_nonzero + 1;
                    if (adpcmA_l != 16'sd0 ||
                        adpcmA_r != 16'sd0 ||
                        adpcmB_l != 16'sd0 ||
                        adpcmB_r != 16'sd0)
                        pcm_nonzero = pcm_nonzero + 1;

                    magnitude = sample_abs(left_value);
                    if (sample_abs(right_value) > magnitude)
                        magnitude = sample_abs(right_value);
                    if (magnitude > peak)
                        peak = magnitude;
                    if (left_integer < minimum)
                        minimum = left_integer;
                    if (left_integer > maximum)
                        maximum = left_integer;

                    current_active = left_value != 16'sd0;
                    if (previous_active >= 0 &&
                        current_active != previous_active)
                        zero_transitions = zero_transitions + 1;
                    previous_active = current_active;

                    if (previous_oscillator >= 0 &&
                        internal_tone_a != previous_oscillator)
                        oscillator_toggles =
                            oscillator_toggles + 1;
                    previous_oscillator = internal_tone_a;

                    if (left_value !== right_value) begin
                        failures = failures + 1;
                        $display(
                            "FAIL SSG_STEREO_RELATION label=%0s index=%0d left=%0d right=%0d",
                            label, index, left_value, right_value
                        );
                    end
                    if (internal_fm_snd == 16'sd0 &&
                        adpcmA_l == 16'sd0 &&
                        adpcmA_r == 16'sd0 &&
                        adpcmB_l == 16'sd0 &&
                        adpcmB_r == 16'sd0 &&
                        (left_value !== {1'b0, psg_snd, 5'd0} ||
                         right_value !== {1'b0, psg_snd, 5'd0})) begin
                        failures = failures + 1;
                        $display(
                            "FAIL SSG_FINAL_MIX label=%0s index=%0d psg=%0d left=%0d right=%0d",
                            label, index, psg_snd,
                            left_value, right_value
                        );
                    end
                    if (left_value == 16'sh7fff ||
                        left_value == 16'sh8000 ||
                        right_value == 16'sh7fff ||
                        right_value == 16'sh8000) begin
                        clipping_count = clipping_count + 1;
                        $display("FAIL CLIPPING label=%0s index=%0d",
                                 label, index);
                    end
                end
            end

            if (raw_b_nonzero != 0 || raw_c_nonzero != 0 ||
                fm_nonzero != 0 || pcm_nonzero != 0 ||
                local_x_count != 0) begin
                failures = failures + 1;
                $display(
                    "FAIL WINDOW_IDLE_LANES label=%0s rawB=%0d rawC=%0d fm=%0d pcm=%0d x=%0d",
                    label, raw_b_nonzero, raw_c_nonzero,
                    fm_nonzero, pcm_nonzero, local_x_count
                );
            end

            $display(
                "SSG_WINDOW label=%0s samples=%0d final_hash=%016h raw_a_hash=%016h psg_hash=%016h nonzero=%0d raw_a_nonzero=%0d psg_nonzero=%0d peak=%0d min=%0d max=%0d zero_transitions=%0d dc_sum=%0d dc_mean=%0d oscillator_toggles=%0d raw_b_nonzero=%0d raw_c_nonzero=%0d fm_nonzero=%0d pcm_nonzero=%0d x_count=%0d clipping=%0d",
                label, sample_total, final_hash, raw_a_hash,
                combined_hash, nonzero_count, raw_a_nonzero,
                combined_nonzero, peak, minimum, maximum,
                zero_transitions, dc_sum, dc_sum / sample_total,
                oscillator_toggles, raw_b_nonzero,
                raw_c_nonzero, fm_nonzero, pcm_nonzero,
                local_x_count, clipping_count
            );
        end
    endtask

    task automatic wait_for_zero(
        input [127:0] label,
        output integer samples_used
    );
        integer consecutive;
        reg signed [15:0] left_value;
        reg signed [15:0] right_value;
        begin
            samples_used = 0;
            consecutive = 0;
            while (consecutive < 16 && samples_used < 256) begin
                next_public_sample(left_value, right_value);
                samples_used = samples_used + 1;
                if (!$isunknown(left_value) &&
                    !$isunknown(right_value) &&
                    !$isunknown(psg_A) &&
                    !$isunknown(psg_snd) &&
                    left_value == 16'sd0 &&
                    right_value == 16'sd0 &&
                    psg_A == 8'd0 &&
                    psg_snd == 10'd0)
                    consecutive = consecutive + 1;
                else
                    consecutive = 0;
            end
            $display(
                "SSG_ZERO_SETTLE label=%0s samples=%0d consecutive=%0d timeout=%0d",
                label, samples_used, consecutive,
                consecutive < 16
            );
            if (consecutive < 16) begin
                failures = failures + 1;
                $display("FAIL SSG_ZERO_TIMEOUT label=%0s", label);
            end
        end
    endtask

    task automatic lock_and_soak_mixer_dc(
        output integer lock_samples
    );
        integer index;
        integer consecutive;
        reg signed [15:0] left_value;
        reg signed [15:0] right_value;
        begin
            consecutive = 0;
            lock_samples = -1;
            for (index = 0; index < 256; index = index + 1) begin
                next_public_sample(left_value, right_value);
                if (!$isunknown(left_value) &&
                    !$isunknown(right_value) &&
                    !$isunknown(psg_A) &&
                    !$isunknown(psg_snd) &&
                    left_value == 16'sd8160 &&
                    right_value == 16'sd8160 &&
                    psg_A == 8'hff &&
                    psg_snd == 10'd255) begin
                    consecutive = consecutive + 1;
                    if (consecutive == 16 && lock_samples < 0)
                        lock_samples = index + 1;
                end else begin
                    consecutive = 0;
                    failures = failures + 1;
                    $display(
                        "FAIL MIXER_DC_SOAK index=%0d left=%0d right=%0d rawA=%0d psg=%0d",
                        index, left_value, right_value,
                        psg_A, psg_snd
                    );
                end
            end
            $display(
                "MIXER_DC_LOCK samples_to_16=%0d soak_samples=256 expected_raw_a=255 expected_psg=255 expected_final=8160 result=%0s",
                lock_samples, lock_samples >= 0 ? "PASS" : "FAIL"
            );
            if (lock_samples < 0) begin
                failures = failures + 1;
                $display("FAIL MIXER_DC_NO_LOCK");
            end
        end
    endtask

    task automatic keyoff_all_fm;
        begin
            bus.jt10_write_port0(8'h28, 8'h00);
            bus.jt10_write_port0(8'h28, 8'h01);
            bus.jt10_write_port0(8'h28, 8'h02);
            bus.jt10_write_port0(8'h28, 8'h04);
            bus.jt10_write_port0(8'h28, 8'h05);
            bus.jt10_write_port0(8'h28, 8'h06);
        end
    endtask

    task automatic write_ssg(
        input [3:0] reg_addr,
        input [7:0] reg_data
    );
        integer update_count_before;
        begin
            update_count_before = ssg_register_update_count;
            expected_ssg_addr = reg_addr;
            expected_ssg_data = reg_data;
            ssg_expect_pending = 1'b1;
            bus.jt10_write_port0({4'd0, reg_addr}, reg_data);
            #1;
            if (ssg_expect_pending ||
                ssg_register_update_count !=
                    update_count_before + 1 ||
                dut.u_jt10.u_jt12.u_mmr.part !== 1'b0 ||
                dut.u_jt10.u_jt12.u_mmr.selected_register !==
                    {4'd0, reg_addr} ||
                dut.u_jt10.u_jt12.u_mmr.din_copy !== reg_data ||
                dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[reg_addr]
                    !== reg_data) begin
                failures = failures + 1;
                ssg_transport_error_count =
                    ssg_transport_error_count + 1;
                $display(
                    "FAIL SSG_TRANSPORT register=%02h data=%02h pending=%0d updates=%0d before=%0d",
                    reg_addr, reg_data, ssg_expect_pending,
                    ssg_register_update_count, update_count_before
                );
            end
            $display(
                "SSG_TRANSPORT register=%02h data=%02h issue_cycle=%0d busy_assert_cycle=%0d busy_clear_cycle=%0d busy_duration=%0d update_count=%0d result=PASS",
                reg_addr, reg_data, last_issue_cycle,
                last_busy_assert_cycle, last_busy_clear_cycle,
                last_busy_clear_cycle - last_issue_cycle,
                ssg_register_update_count
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
        logic [63:0] unused_raw_hash;
        logic [63:0] unused_psg_hash;
        integer unused_nonzero;
        integer unused_peak;
        integer unused_min;
        integer unused_max;
        integer unused_transitions;
        integer unused_raw_nonzero;
        integer unused_psg_nonzero;
        integer unused_oscillator_toggles;
        longint signed unused_dc_sum;

        if (!$value$plusargs("RUN_ID=%d", run_id))
            run_id = 1;
        $display("PHASE2A_BEGIN run=%0d", run_id);

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
        capture_ssg_window(
            16, "initial_silence", initial_hash,
            unused_raw_hash, unused_psg_hash,
            unused_nonzero, unused_peak, unused_min,
            unused_max, unused_transitions, unused_dc_sum,
            unused_raw_nonzero, unused_psg_nonzero,
            unused_oscillator_toggles
        );
        if (unused_nonzero != 0) begin
            failures = failures + 1;
            $display("FAIL INITIAL_SILENCE_NONZERO count=%0d",
                     unused_nonzero);
        end

        keyoff_all_fm();
        bus.jt10_write_port0(8'h22, 8'h00);
        bus.jt10_write_port0(8'h27, 8'h00);
        bus.jt10_write_port0(8'h2b, 8'h00);
        bus.jt10_write_port1(8'h00, 8'hbf);
        bus.jt10_write_port0(8'h10, 8'h01);
        bus.jt10_write_port0(8'h10, 8'h00);

        write_ssg(4'h8, 8'h00);
        write_ssg(4'h9, 8'h00);
        write_ssg(4'ha, 8'h00);
        write_ssg(4'h6, 8'h00);
        write_ssg(4'h7, 8'h3f);

        capture_ssg_window(
            16, "explicit_silence", explicit_silence_hash,
            unused_raw_hash, unused_psg_hash,
            unused_nonzero, unused_peak, unused_min,
            unused_max, unused_transitions, unused_dc_sum,
            unused_raw_nonzero, unused_psg_nonzero,
            unused_oscillator_toggles
        );
        if (unused_nonzero != 0 ||
            internal_envelope_low !== 8'h00 ||
            internal_envelope_high !== 8'h00 ||
            internal_envelope_shape !== 8'h00) begin
            failures = failures + 1;
            $display("FAIL EXPLICIT_SILENCE_OR_ENVELOPE_STATE");
        end
        audit_active = 1'b1;

        write_ssg(4'h0, 8'h20);
        write_ssg(4'h1, 8'h00);
        write_ssg(4'h7, 8'h3e);
        write_ssg(4'h8, 8'h0f);
        tone_enable_cycle = last_issue_cycle;

        capture_ssg_window(
            START_SAMPLES, "tone_start", start_final_hash,
            start_raw_a_hash, start_psg_hash,
            unused_nonzero, unused_peak, unused_min,
            unused_max, unused_transitions, unused_dc_sum,
            unused_raw_nonzero, unused_psg_nonzero,
            unused_oscillator_toggles
        );
        if (unused_nonzero == 0 || first_nonzero_index < 0) begin
            failures = failures + 1;
            $display("FAIL SSG_START_ALL_ZERO");
        end

        capture_ssg_window(
            TONE_SAMPLES, "primary", primary_final_hash,
            primary_raw_a_hash, primary_psg_hash,
            primary_nonzero, primary_peak, primary_min,
            primary_max, primary_transitions, primary_dc_sum,
            primary_raw_nonzero, primary_psg_nonzero,
            primary_oscillator_toggles
        );
        if (primary_nonzero == 0 ||
            primary_raw_nonzero == 0 ||
            primary_psg_nonzero == 0) begin
            failures = failures + 1;
            $display("FAIL PRIMARY_SSG_LANE_ZERO");
        end

        write_ssg(4'h8, 8'h00);
        wait_for_zero("volume_mute", volume_mute_settle_samples);
        capture_ssg_window(
            CONTROL_SAMPLES, "volume_mute", volume_mute_hash,
            unused_raw_hash, unused_psg_hash,
            unused_nonzero, unused_peak, unused_min,
            unused_max, unused_transitions, unused_dc_sum,
            unused_raw_nonzero, unused_psg_nonzero,
            unused_oscillator_toggles
        );
        if (unused_nonzero != 0 ||
            volume_mute_hash != 64'h28c31cf8df2ec325) begin
            failures = failures + 1;
            $display(
                "FAIL VOLUME_MUTE nonzero=%0d hash=%016h",
                unused_nonzero, volume_mute_hash
            );
        end

        // Pinned JT49 semantics: disabling both tone and noise gates forces
        // their mixer inputs high.  Fixed volume 0F therefore produces
        // maximum constant DC; channel silence is controlled by volume zero.
        write_ssg(4'h8, 8'h0f);
        write_ssg(4'h7, 8'h3f);
        lock_and_soak_mixer_dc(mixer_dc_lock_samples);
        capture_ssg_window(
            CONTROL_SAMPLES, "mixer_dc", mixer_dc_hash,
            mixer_dc_raw_a_hash, mixer_dc_psg_hash,
            mixer_dc_nonzero, mixer_dc_peak, mixer_dc_min,
            mixer_dc_max, mixer_dc_transitions, mixer_dc_sum,
            mixer_dc_raw_nonzero, mixer_dc_psg_nonzero,
            mixer_dc_oscillator_toggles
        );
        if (mixer_dc_nonzero != CONTROL_SAMPLES ||
            mixer_dc_raw_nonzero != CONTROL_SAMPLES ||
            mixer_dc_psg_nonzero != CONTROL_SAMPLES ||
            mixer_dc_peak != 8160 ||
            mixer_dc_min != 8160 ||
            mixer_dc_max != 8160 ||
            mixer_dc_transitions != 0 ||
            mixer_dc_oscillator_toggles == 0) begin
            failures = failures + 1;
            $display(
                "FAIL MIXER_DC_CONTROL nonzero=%0d raw=%0d psg=%0d peak=%0d min=%0d max=%0d transitions=%0d oscillator_toggles=%0d",
                mixer_dc_nonzero, mixer_dc_raw_nonzero,
                mixer_dc_psg_nonzero, mixer_dc_peak,
                mixer_dc_min, mixer_dc_max,
                mixer_dc_transitions,
                mixer_dc_oscillator_toggles
            );
        end

        write_ssg(4'h0, 8'h10);
        write_ssg(4'h1, 8'h00);
        write_ssg(4'h7, 8'h3e);
        capture_ssg_window(
            TONE_SAMPLES, "period_change", changed_final_hash,
            changed_raw_a_hash, changed_psg_hash,
            changed_nonzero, changed_peak, changed_min,
            changed_max, changed_transitions, changed_dc_sum,
            changed_raw_nonzero, changed_psg_nonzero,
            changed_oscillator_toggles
        );
        if (changed_nonzero == 0 ||
            changed_final_hash == primary_final_hash ||
            changed_transitions <= primary_transitions) begin
            failures = failures + 1;
            $display(
                "FAIL PERIOD_CONTROL primary_hash=%016h changed_hash=%016h primary_transitions=%0d changed_transitions=%0d",
                primary_final_hash, changed_final_hash,
                primary_transitions, changed_transitions
            );
        end

        write_ssg(4'h8, 8'h00);
        write_ssg(4'h7, 8'h3f);
        wait_for_zero("final_stop", final_stop_settle_samples);
        capture_ssg_window(
            CONTROL_SAMPLES, "final_stop", final_stop_hash,
            unused_raw_hash, unused_psg_hash,
            unused_nonzero, unused_peak, unused_min,
            unused_max, unused_transitions, unused_dc_sum,
            unused_raw_nonzero, unused_psg_nonzero,
            unused_oscillator_toggles
        );
        if (unused_nonzero != 0) begin
            failures = failures + 1;
            $display("FAIL FINAL_STOP_NONZERO count=%0d",
                     unused_nonzero);
        end

        if (accepted_write_count != 29 ||
            port0_write_count != 28 ||
            port1_write_count != 1 ||
            ssg_register_update_count != 17 ||
            ssg_transport_error_count != 0 ||
            busy_timeout_count != 0 ||
            busy_while_write_count != 0 ||
            cadence_error_count != 0 ||
            width_error_count != 0 ||
            sample_drop_count != 0 ||
            sample_duplicate_count != 0 ||
            sample_mismatch_count != 0 ||
            public_x_count != 0 ||
            clipping_count != 0 ||
            adpcma_fetch_count != 0 ||
            adpcmb_fetch_count != 0 ||
            adpcma_keyon_command_count != 0 ||
            adpcmb_start_state !== 1'b0 ||
            noise_enable_event_count != 0 ||
            bc_enable_event_count != 0 ||
            envelope_enable_event_count != 0 ||
            internal_envelope_low !== 8'h00 ||
            internal_envelope_high !== 8'h00 ||
            internal_envelope_shape !== 8'h00) begin
            failures = failures + 1;
            $display("FAIL PHASE2A_AUDIT_COUNTER_OR_STATE");
        end

        $display(
            "BUS_RESULT port0=%0d port1=%0d accepted=%0d ssg_updates=%0d timeout=%0d write_while_busy=%0d busy_min=%0d busy_max=%0d busy_hash=%016h",
            port0_write_count, port1_write_count,
            accepted_write_count, ssg_register_update_count,
            busy_timeout_count, busy_while_write_count,
            busy_min_cycles, busy_max_cycles, busy_duration_hash
        );
        $display(
            "SAMPLE_RESULT cadence=144 width=6 ready_cycle=%0d first_public_cycle=%0d internal_pulses_at_first=6 tone_enable_cycle=%0d first_nonzero_index=%0d public_samples=%0d cadence_errors=%0d width_errors=%0d drops=%0d duplicates=%0d mismatches=%0d",
            warmup_ready_cycle, first_public_cycle,
            tone_enable_cycle, first_nonzero_index,
            public_pulse_count, cadence_error_count,
            width_error_count, sample_drop_count,
            sample_duplicate_count, sample_mismatch_count
        );
        $display(
            "SSG_RESULT run=%0d failures=%0d start_final_hash=%016h start_raw_a_hash=%016h start_psg_hash=%016h primary_final_hash=%016h primary_raw_a_hash=%016h primary_psg_hash=%016h primary_nonzero=%0d primary_raw_nonzero=%0d primary_psg_nonzero=%0d peak=%0d min=%0d max=%0d zero_transitions=%0d dc_sum=%0d volume_mute_hash=%016h volume_mute_settle=%0d mixer_dc_hash=%016h mixer_dc_raw_a_hash=%016h mixer_dc_psg_hash=%016h mixer_dc_lock=%0d mixer_dc_nonzero=%0d mixer_dc_peak=%0d mixer_dc_min=%0d mixer_dc_max=%0d mixer_dc_transitions=%0d mixer_dc_sum=%0d changed_final_hash=%016h changed_raw_a_hash=%016h changed_psg_hash=%016h changed_nonzero=%0d changed_peak=%0d changed_min=%0d changed_max=%0d changed_zero_transitions=%0d changed_dc_sum=%0d final_stop_hash=%016h final_stop_settle=%0d x_count=%0d clipping=%0d drops=%0d duplicates=%0d fm_nonidle=0 adpcm_fetch=%0d raw_b_nonidle=0 raw_c_nonidle=0 noise_enable_events=%0d envelope_enable_events=%0d",
            run_id, failures, start_final_hash,
            start_raw_a_hash, start_psg_hash,
            primary_final_hash, primary_raw_a_hash,
            primary_psg_hash, primary_nonzero,
            primary_raw_nonzero, primary_psg_nonzero,
            primary_peak, primary_min, primary_max,
            primary_transitions, primary_dc_sum,
            volume_mute_hash, volume_mute_settle_samples,
            mixer_dc_hash, mixer_dc_raw_a_hash,
            mixer_dc_psg_hash, mixer_dc_lock_samples,
            mixer_dc_nonzero, mixer_dc_peak,
            mixer_dc_min, mixer_dc_max,
            mixer_dc_transitions, mixer_dc_sum,
            changed_final_hash, changed_raw_a_hash,
            changed_psg_hash, changed_nonzero,
            changed_peak, changed_min, changed_max,
            changed_transitions, changed_dc_sum,
            final_stop_hash, final_stop_settle_samples,
            public_x_count, clipping_count,
            sample_drop_count, sample_duplicate_count,
            adpcma_fetch_count + adpcmb_fetch_count,
            noise_enable_event_count,
            envelope_enable_event_count
        );
        $display(
            "IDLE_RESULT raw_b_nonidle=0 raw_c_nonidle=0 noise_enable_events=%0d envelope_enable_events=%0d fm_nonidle=0 adpcma_fetch=%0d adpcmb_fetch=%0d pcm_nonidle=0 adpcma_keyon=%0d adpcmb_start=%0d",
            noise_enable_event_count,
            envelope_enable_event_count,
            adpcma_fetch_count, adpcmb_fetch_count,
            adpcma_keyon_command_count, adpcmb_start_state
        );

        if (failures != 0)
            $fatal(1, "JT10 SSG channel A test failed (%0d)",
                   failures);
        $display("PHASE2A_PASS run=%0d", run_id);
        $finish;
    end
endmodule
