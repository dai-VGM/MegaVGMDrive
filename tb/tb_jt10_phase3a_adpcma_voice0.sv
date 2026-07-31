`timescale 1ns/1ps

module tb_jt10_phase3a_adpcma_voice0 #(
    parameter integer TARGET_VOICE = 0
);
    localparam [63:0] FNV_OFFSET = 64'hcbf29ce484222325;
    localparam integer PRIMARY_SAMPLES = 4096;
    localparam integer ATTACK_SAMPLES = 256;
    localparam integer ALIGNED_SAMPLES = 2048;
    localparam integer CONTROL_SAMPLES = 512;
    localparam integer NATURAL_TIMEOUT_SAMPLES = 4096;
    localparam integer ADPCMA_SCHEDULER_PERIOD = 432;
    localparam integer CANONICAL_KEYON_PHASE = 230;
    localparam integer TARGET_KEYON_PHASE =
        TARGET_VOICE == 0 ? CANONICAL_KEYON_PHASE :
        (CANONICAL_KEYON_PHASE -
         ((TARGET_VOICE - 1) * 60) +
         ADPCMA_SCHEDULER_PERIOD) % ADPCMA_SCHEDULER_PERIOD;
    localparam integer KEYON_ISSUE_PIPELINE = 7;
    localparam [7:0] TARGET_KEY_MASK = 8'h01 << TARGET_VOICE;
    localparam [7:0] TARGET_KEYOFF_MASK =
        8'h80 | (8'h01 << TARGET_VOICE);
    localparam [5:0] TARGET_SLOT_MASK = 6'h01 << TARGET_VOICE;
    localparam [7:0] TARGET_LEVEL_REGISTER = 8'h08 + TARGET_VOICE;
    localparam [7:0] TARGET_START_LOW = 8'h10 + TARGET_VOICE;
    localparam [7:0] TARGET_START_HIGH = 8'h18 + TARGET_VOICE;
    localparam [7:0] TARGET_END_LOW = 8'h20 + TARGET_VOICE;
    localparam [7:0] TARGET_END_HIGH = 8'h28 + TARGET_VOICE;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cen = 1'b0;
    logic session_start = 1'b1;
    logic loop_event = 1'b0;
    logic changed_pattern = 1'b0;
    logic [7:0] adpcmb_data = 8'h00;

    wire [1:0] addr;
    wire [7:0] din;
    wire cs_n;
    wire wr_n;
    wire [7:0] dout;
    wire irq_n;
    wire [19:0] adpcma_addr;
    wire [3:0] adpcma_bank;
    wire adpcma_roe_n;
    wire [7:0] adpcma_data;
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
    wire clk_en_666 = dut.u_jt10.u_jt12.clk_en_666;
    wire [7:0] adpcma_command = dut.u_jt10.u_jt12.aon_a;
    wire adpcma_command_update = dut.u_jt10.u_jt12.up_aon;
    wire [5:0] adpcma_total_level = dut.u_jt10.u_jt12.atl_a;
    wire [7:0] adpcma_pan_level = dut.u_jt10.u_jt12.lracl;
    wire [15:0] adpcma_address_latch = dut.u_jt10.u_jt12.addr_a;
    wire [5:0] adpcma_flags = dut.u_jt10.u_jt12.adpcma_flags;
    wire [5:0] adpcma_cur_ch =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.cur_ch;
    wire [5:0] adpcma_en_ch =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.en_ch;
    wire adpcma_match =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.match;
    wire [5:0] adpcma_aon_sr =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.aon_sr;
    wire [5:0] adpcma_aoff_sr =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.aoff_sr;
    wire adpcma_on1 =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on1;
    wire adpcma_on2 =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on2;
    wire adpcma_on3 =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on3;
    wire adpcma_on4 =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on4;
    wire adpcma_on5 =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on5;
    wire adpcma_on6 =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on6;
    wire [5:0] adpcma_active_mask =
        (adpcma_on1 ? adpcma_cur_ch : 6'd0) |
        (adpcma_on2 ?
            {adpcma_cur_ch[0], adpcma_cur_ch[5:1]} : 6'd0) |
        (adpcma_on3 ?
            {adpcma_cur_ch[1:0], adpcma_cur_ch[5:2]} : 6'd0) |
        (adpcma_on4 ?
            {adpcma_cur_ch[2:0], adpcma_cur_ch[5:3]} : 6'd0) |
        (adpcma_on5 ?
            {adpcma_cur_ch[3:0], adpcma_cur_ch[5:4]} : 6'd0) |
        (adpcma_on6 ?
            {adpcma_cur_ch[4:0], adpcma_cur_ch[5]} : 6'd0);
    wire [3:0] captured_nibble =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.data;
    wire nibble_select =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.nibble_sel;
    wire adpcma_decon =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.decon;
    wire signed [15:0] decoded_pcm =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.pcmdec;
    wire signed [15:0] attenuated_pcm =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.pcm_att;
    wire [1:0] internal_pan =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.lr;
    wire adpcma_active_any =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on1 |
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on2 |
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on3 |
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on4 |
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on5 |
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on6;
    wire signed [15:0] accumulator_input_l =
        dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_input_l;
    wire signed [15:0] accumulator_input_r =
        dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_input_r;
    wire [2:0] accumulator_cur_ch =
        dut.u_jt10.u_jt12.cur_ch;
    wire [1:0] accumulator_cur_op =
        dut.u_jt10.u_jt12.cur_op;
    wire signed [13:0] fm_operator_result =
        dut.u_jt10.u_jt12.op_result_hd;
    wire adpcmb_active =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.chon;
    wire adpcmb_start_state = dut.u_jt10.u_jt12.acmd_on_b;
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
    integer current_expected_voice = TARGET_VOICE;
    integer failures = 0;
    integer system_cycle = 0;
    integer post_reset_cycle = 0;
    integer internal_pulse_count = 0;
    integer public_pulse_count = 0;
    integer warmup_ready_cycle = -1;
    integer first_public_cycle = -1;
    integer cadence_error_count = 0;
    integer width_error_count = 0;
    integer sample_drop_count = 0;
    integer sample_duplicate_count = 0;
    integer sample_mismatch_count = 0;
    integer public_x_count = 0;
    integer clipping_count = 0;
    integer global_fetch_count = 0;
    integer last_valid_fetch_cycle = -1;
    integer adpcma_command_update_count = 0;
    integer adpcma_register_write_count = 0;
    integer voice_other_keyon_count = 0;
    integer voice_other_fetch_count = 0;
    integer voice_other_decode_nonzero_count = 0;
    integer voice_other_active_count = 0;
    integer target_decode_event_count = 0;
    integer target_accumulator_nonidle_count = 0;
    integer command_mask_error_count = 0;
    integer adpcmb_fetch_count = 0;
    integer adpcmb_nonidle_count = 0;
    integer fm_nonidle_count = 0;
    integer ssg_nonidle_count = 0;
    integer noise_enable_event_count = 0;
    integer envelope_enable_event_count = 0;
    integer last_public_rise_cycle = -1;
    integer public_pulse_width = 0;
    integer keyoff_command_cycle = -1;
    integer keyoff_fetch_snapshot = 0;
    integer last_active_clear_cycle = -1;
    logic previous_internal_sample = 1'b0;
    logic previous_public_sample = 1'b0;
    logic previous_ready = 1'b0;
    logic previous_up_aon = 1'b0;
    logic previous_active_any = 1'b0;
    logic audit_active = 1'b0;

    integer record_kind = 0;
    reg [8*32-1:0] record_label;
    integer record_goal = 0;
    integer record_samples = 0;
    integer record_fetch_count = 0;
    integer record_unique_addresses = 0;
    integer record_out_of_range = 0;
    integer record_progression_errors = 0;
    integer record_nibble_errors = 0;
    integer record_nonzero_count = 0;
    integer record_peak = 0;
    integer record_minimum = 32767;
    integer record_maximum = -32768;
    integer record_zero_crossings = 0;
    integer record_first_nonzero_index = -1;
    integer record_keyon_cycle = -1;
    integer record_keyon_issue_cycle = -1;
    integer record_target_slot_cycle = -1;
    integer record_target_slot_delay = -1;
    integer record_aon_pulse_cycle = -1;
    logic [5:0] record_keyon_cur_ch = 6'd0;
    logic [5:0] record_keyon_en_ch = 6'd0;
    integer record_active_cycle = -1;
    integer record_first_fetch_cycle = -1;
    integer record_first_capture_cycle = -1;
    integer record_first_decode_cycle = -1;
    integer record_first_lane_cycle = -1;
    integer record_first_final_cycle = -1;
    integer record_first_gain_cycle = -1;
    integer record_first_accumulator_cycle = -1;
    integer record_first_bank = -1;
    integer record_first_address = -1;
    integer record_previous_sign = 0;
    integer record_previous_sign_valid = 0;
    integer record_aligned_samples = 0;
    longint signed record_dc_sum_l = 0;
    longint signed record_dc_sum_r = 0;
    logic [23:0] record_start_byte = 24'h000000;
    logic [23:0] record_end_byte = 24'h000fff;
    logic [23:0] record_last_logical_address = 24'h000000;
    logic record_last_nibble = 1'b0;
    logic record_have_last_address = 1'b0;
    logic [63:0] record_fetch_hash = FNV_OFFSET;
    logic [63:0] record_address_hash = FNV_OFFSET;
    logic [63:0] record_rom_hash = FNV_OFFSET;
    logic [63:0] record_decode_hash = FNV_OFFSET;
    logic [63:0] record_audio_hash = FNV_OFFSET;
    logic [63:0] record_attack_hash = FNV_OFFSET;
    logic [63:0] record_left_hash = FNV_OFFSET;
    logic [63:0] record_right_hash = FNV_OFFSET;
    logic [63:0] record_accumulator_hash = FNV_OFFSET;
    logic [63:0] record_aligned_hash = FNV_OFFSET;
    logic record_alignment_started = 1'b0;
    logic record_armed = 1'b0;
    logic record_active = 1'b0;
    logic record_started = 1'b0;

    logic [63:0] initial_silence_hash;
    logic [63:0] explicit_silence_hash;
    logic [63:0] prekey_silence_hash;
    logic [63:0] primary_fetch_hash;
    logic [63:0] primary_address_hash;
    logic [63:0] primary_rom_hash;
    logic [63:0] primary_decode_hash;
    logic [63:0] primary_audio_hash;
    logic [63:0] primary_attack_hash;
    logic [63:0] primary_left_hash;
    logic [63:0] primary_right_hash;
    logic [63:0] primary_accumulator_hash;
    logic [63:0] primary_aligned_hash;
    integer primary_fetch_count;
    integer primary_unique_addresses;
    integer primary_keyon_issue_cycle;
    integer primary_keyon_cycle;
    integer primary_target_slot_cycle;
    integer primary_target_slot_delay;
    integer primary_aon_pulse_cycle;
    logic [5:0] primary_keyon_cur_ch;
    logic [5:0] primary_keyon_en_ch;
    integer primary_active_cycle;
    integer primary_first_fetch_cycle;
    integer primary_first_capture_cycle;
    integer primary_first_decode_cycle;
    integer primary_first_lane_cycle;
    integer primary_first_final_cycle;
    integer primary_first_nonzero_index;
    integer primary_first_address;
    integer primary_first_bank;
    integer primary_peak;
    integer primary_minimum;
    integer primary_maximum;
    integer primary_zero_crossings;
    integer primary_nonzero_count;
    longint signed primary_dc_sum_l;
    longint signed primary_dc_sum_r;

    logic [63:0] left_fetch_hash;
    logic [63:0] left_address_hash;
    logic [63:0] left_rom_hash;
    logic [63:0] left_decode_hash;
    logic [63:0] left_audio_hash;
    logic [63:0] left_left_hash;
    logic [63:0] left_right_hash;
    logic [63:0] right_fetch_hash;
    logic [63:0] right_address_hash;
    logic [63:0] right_rom_hash;
    logic [63:0] right_decode_hash;
    logic [63:0] right_audio_hash;
    logic [63:0] right_left_hash;
    logic [63:0] right_right_hash;
    logic [63:0] mute_audio_hash;
    logic [63:0] mute_fetch_hash;
    logic [63:0] mute_decode_hash;
    logic [63:0] shifted_fetch_hash;
    logic [63:0] shifted_address_hash;
    logic [63:0] shifted_rom_hash;
    logic [63:0] shifted_decode_hash;
    logic [63:0] shifted_audio_hash;
    integer shifted_first_address;
    logic [63:0] changed_fetch_hash;
    logic [63:0] changed_address_hash;
    logic [63:0] changed_rom_hash;
    logic [63:0] changed_decode_hash;
    logic [63:0] changed_audio_hash;
    logic [63:0] retrigger_fetch_hash;
    logic [63:0] retrigger_address_hash;
    logic [63:0] retrigger_rom_hash;
    logic [63:0] retrigger_decode_hash;
    logic [63:0] retrigger_attack_hash;
    logic [63:0] retrigger_accumulator_hash;
    logic [63:0] retrigger_aligned_hash;
    logic [63:0] retrigger_audio_hash;
    logic [63:0] keyoff_zero_hash;
    logic [63:0] natural_playback_hash;
    logic [63:0] natural_zero_hash;
    integer mid_keyoff_issue_cycle;
    integer mid_active_clear_cycle;
    integer mid_fetch_stop_cycle;
    integer mid_additional_fetches;
    integer mid_zero_settle_samples;
    integer natural_active_clear_cycle;
    integer natural_fetch_stop_cycle;
    integer natural_end_fetch_count;
    integer natural_end_last_address;
    integer natural_zero_settle_samples;
    integer dummy_issue_cycle;
    integer dummy_active_clear_cycle;
    integer dummy_fetch_stop_cycle;
    integer dummy_additional_fetches;
    logic [63:0] sentinel_audio_hash [0:5];
    integer sentinel_first_address [0:5];

    function automatic [63:0] hash_byte(
        input [63:0] hash_in,
        input [7:0] value
    );
        hash_byte = (hash_in ^ value) * 64'h00000100000001b3;
    endfunction

    function automatic [63:0] hash_u16(
        input [63:0] hash_in,
        input [15:0] value
    );
        reg [63:0] work;
        begin
            work = hash_byte(hash_in, value[7:0]);
            hash_u16 = hash_byte(work, value[15:8]);
        end
    endfunction

    function automatic [63:0] hash_u24(
        input [63:0] hash_in,
        input [23:0] value
    );
        reg [63:0] work;
        begin
            work = hash_byte(hash_in, value[7:0]);
            work = hash_byte(work, value[15:8]);
            hash_u24 = hash_byte(work, value[23:16]);
        end
    endfunction

    function automatic [63:0] hash_stereo(
        input [63:0] hash_in,
        input [15:0] left_value,
        input [15:0] right_value
    );
        reg [63:0] work;
        begin
            work = hash_u16(hash_in, left_value);
            hash_stereo = hash_u16(work, right_value);
        end
    endfunction

    function automatic integer sample_abs(input signed [15:0] value);
        integer signed extended;
        begin
            extended = value;
            sample_abs = extended < 0 ? -extended : extended;
        end
    endfunction

    task automatic reset_record_statistics;
        begin
            record_samples = 0;
            record_fetch_count = 0;
            record_unique_addresses = 0;
            record_out_of_range = 0;
            record_progression_errors = 0;
            record_nibble_errors = 0;
            record_nonzero_count = 0;
            record_peak = 0;
            record_minimum = 32767;
            record_maximum = -32768;
            record_zero_crossings = 0;
            record_first_nonzero_index = -1;
            record_active_cycle = -1;
            record_keyon_issue_cycle = -1;
            record_target_slot_cycle = -1;
            record_target_slot_delay = -1;
            record_aon_pulse_cycle = -1;
            record_keyon_cur_ch = 6'd0;
            record_keyon_en_ch = 6'd0;
            record_first_fetch_cycle = -1;
            record_first_capture_cycle = -1;
            record_first_decode_cycle = -1;
            record_first_lane_cycle = -1;
            record_first_final_cycle = -1;
            record_first_gain_cycle = -1;
            record_first_accumulator_cycle = -1;
            record_first_bank = -1;
            record_first_address = -1;
            record_previous_sign = 0;
            record_previous_sign_valid = 0;
            record_aligned_samples = 0;
            record_dc_sum_l = 0;
            record_dc_sum_r = 0;
            record_have_last_address = 1'b0;
            record_last_logical_address = 24'h000000;
            record_last_nibble = 1'b0;
            record_fetch_hash = FNV_OFFSET;
            record_address_hash = FNV_OFFSET;
            record_rom_hash = FNV_OFFSET;
            record_decode_hash = FNV_OFFSET;
            record_audio_hash = FNV_OFFSET;
            record_attack_hash = FNV_OFFSET;
            record_left_hash = FNV_OFFSET;
            record_right_hash = FNV_OFFSET;
            record_accumulator_hash = FNV_OFFSET;
            record_aligned_hash = FNV_OFFSET;
            record_alignment_started = 1'b0;
        end
    endtask

    always #5 clk = ~clk;

    always @(posedge clk) begin : contract_monitor
        logic pre_valid_fetch;
        logic [19:0] pre_fetch_address;
        logic [3:0] pre_fetch_bank;
        logic pre_fetch_nibble;
        logic [7:0] pre_fetch_data;
        logic [23:0] logical_address;
        logic [3:0] expected_nibble;
        logic internal_rise;
        logic public_rise;
        integer relative_cycle;
        integer magnitude;
        integer sample_integer;
        integer current_sign;

        system_cycle = system_cycle + 1;
        if (!rst)
            post_reset_cycle = post_reset_cycle + 1;
        pre_valid_fetch =
            !rst && clk_en_666 === 1'b1 &&
            adpcma_roe_n === 1'b0 && adpcma_decon === 1'b1;
        pre_fetch_address = adpcma_addr;
        pre_fetch_bank = adpcma_bank;
        pre_fetch_nibble = nibble_select;
        pre_fetch_data = adpcma_data;
        #1;

        internal_rise =
            internal_snd_sample === 1'b1 &&
            previous_internal_sample !== 1'b1;
        public_rise =
            snd_sample === 1'b1 && previous_public_sample !== 1'b1;

        if (rst || session_start) begin
            previous_internal_sample = 1'b0;
            previous_public_sample = 1'b0;
            previous_ready = 1'b0;
            previous_up_aon = 1'b0;
            previous_active_any = 1'b0;
            internal_pulse_count = 0;
            public_pulse_count = 0;
            public_pulse_width = 0;
            last_public_rise_cycle = -1;
        end else begin
            if (internal_rise)
                internal_pulse_count = internal_pulse_count + 1;
            if (warmup_ready === 1'b1 && previous_ready !== 1'b1)
                warmup_ready_cycle = system_cycle;

            if (!warmup_ready &&
                (snd_sample !== 1'b0 || snd_left !== 16'sd0 ||
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
                    sample_mismatch_count = sample_mismatch_count + 1;
                    $display("FAIL INTERNAL_PUBLIC_MISMATCH cycle=%0d",
                             system_cycle);
                end
            end

            if (public_rise) begin
                public_pulse_count = public_pulse_count + 1;
                if (!internal_rise) begin
                    sample_duplicate_count = sample_duplicate_count + 1;
                    $display("FAIL SAMPLE_DUPLICATE cycle=%0d", system_cycle);
                end
                if (public_pulse_count == 1) begin
                    first_public_cycle = system_cycle;
                    if (internal_pulse_count != 6) begin
                        failures = failures + 1;
                        $display("FAIL FIRST_PUBLIC_INTERNAL actual=%0d",
                                 internal_pulse_count);
                    end
                end
                if (last_public_rise_cycle >= 0 &&
                    system_cycle - last_public_rise_cycle != 144) begin
                    cadence_error_count = cadence_error_count + 1;
                    $display("FAIL SAMPLE_CADENCE delta=%0d",
                             system_cycle - last_public_rise_cycle);
                end
                last_public_rise_cycle = system_cycle;
            end

            if (snd_sample === 1'b1)
                public_pulse_width = public_pulse_width + 1;
            else if (previous_public_sample === 1'b1) begin
                if (public_pulse_width != 6) begin
                    width_error_count = width_error_count + 1;
                    $display("FAIL SAMPLE_WIDTH width=%0d", public_pulse_width);
                end
                public_pulse_width = 0;
            end

            if (adpcma_command_update === 1'b1 &&
                previous_up_aon !== 1'b1) begin
                adpcma_command_update_count =
                    adpcma_command_update_count + 1;
                if (!adpcma_command[7] &&
                    adpcma_command[5:0] !=
                        (6'h01 << current_expected_voice)) begin
                    voice_other_keyon_count =
                        voice_other_keyon_count + 1;
                    command_mask_error_count =
                        command_mask_error_count + 1;
                end
                if (adpcma_command[7]) begin
                    keyoff_command_cycle = system_cycle;
                    keyoff_fetch_snapshot = global_fetch_count;
                    if (adpcma_command[5:0] != 6'h3f &&
                        adpcma_command[5:0] !=
                            (6'h01 << current_expected_voice))
                        command_mask_error_count =
                            command_mask_error_count + 1;
                end else if (
                    adpcma_command[current_expected_voice] &&
                    record_armed
                ) begin
                    reset_record_statistics();
                    record_keyon_cycle = system_cycle;
                    record_keyon_issue_cycle = last_issue_cycle;
                    record_keyon_cur_ch = adpcma_cur_ch;
                    record_keyon_en_ch = adpcma_en_ch;
                    record_armed = 1'b0;
                    record_active = 1'b1;
                    record_started = 1'b1;
                end
            end

            if (record_active && record_active_cycle < 0 &&
                adpcma_active_any === 1'b1)
                record_active_cycle = system_cycle;
            if (record_active && record_target_slot_cycle < 0 &&
                clk_en_666 && adpcma_match &&
                adpcma_en_ch ==
                    (6'h01 << current_expected_voice)) begin
                record_target_slot_cycle = system_cycle;
                record_target_slot_delay =
                    system_cycle - record_keyon_cycle;
            end
            if (record_active && record_aon_pulse_cycle < 0 &&
                clk_en_666 && adpcma_aon_sr[0])
                record_aon_pulse_cycle = system_cycle;
            if (previous_active_any === 1'b1 &&
                adpcma_active_any === 1'b0)
                last_active_clear_cycle = system_cycle;
            if (record_active && record_first_gain_cycle < 0 &&
                attenuated_pcm != 16'sd0)
                record_first_gain_cycle = system_cycle;
            if (record_active && record_first_accumulator_cycle < 0 &&
                accumulator_cur_op == 2'd0 &&
                accumulator_cur_ch == 3'd0 &&
                (accumulator_input_l != 16'sd0 ||
                 accumulator_input_r != 16'sd0))
                record_first_accumulator_cycle = system_cycle;

            if (pre_valid_fetch) begin
                global_fetch_count = global_fetch_count + 1;
                last_valid_fetch_cycle = system_cycle;
                if ($isunknown(pre_fetch_address) ||
                    $isunknown(pre_fetch_bank) ||
                    $isunknown(pre_fetch_data) ||
                    $isunknown(pre_fetch_nibble)) begin
                    failures = failures + 1;
                    $display("FAIL VALID_FETCH_X cycle=%0d", system_cycle);
                end
                if (|(adpcma_active_mask &
                      ~(6'h01 << current_expected_voice)))
                    voice_other_fetch_count =
                        voice_other_fetch_count + 1;

                expected_nibble = pre_fetch_nibble ?
                    pre_fetch_data[3:0] : pre_fetch_data[7:4];
                if ($isunknown(captured_nibble) ||
                    captured_nibble !== expected_nibble) begin
                    failures = failures + 1;
                    $display(
                        "FAIL CAPTURE_NIBBLE cycle=%0d address=%h sel=%0d byte=%02h expected=%h actual=%h",
                        system_cycle, {pre_fetch_bank, pre_fetch_address},
                        pre_fetch_nibble, pre_fetch_data,
                        expected_nibble, captured_nibble
                    );
                end
                if ($isunknown(decoded_pcm) ||
                    $isunknown(attenuated_pcm)) begin
                    failures = failures + 1;
                    $display("FAIL DECODE_X cycle=%0d", system_cycle);
                end

                if (record_active) begin
                    logical_address =
                        {pre_fetch_bank, pre_fetch_address};
                    if (record_first_fetch_cycle < 0) begin
                        record_first_fetch_cycle = system_cycle;
                        record_first_capture_cycle = system_cycle;
                        record_first_decode_cycle = system_cycle;
                        record_first_address = pre_fetch_address;
                        record_first_bank = pre_fetch_bank;
                    end
                    relative_cycle =
                        system_cycle - record_first_fetch_cycle;
                    record_fetch_hash =
                        hash_u16(record_fetch_hash, relative_cycle[15:0]);
                    record_fetch_hash =
                        hash_byte(record_fetch_hash,
                                  {7'd0, pre_fetch_nibble});
                    record_address_hash =
                        hash_u24(record_address_hash, logical_address);
                    record_address_hash =
                        hash_byte(record_address_hash,
                                  {7'd0, pre_fetch_nibble});
                    record_rom_hash =
                        hash_byte(record_rom_hash, pre_fetch_data);
                    record_decode_hash =
                        hash_byte(record_decode_hash,
                                  {4'd0, captured_nibble});
                    record_decode_hash =
                        hash_u16(record_decode_hash, decoded_pcm);

                    if (logical_address < record_start_byte ||
                        logical_address > record_end_byte)
                        record_out_of_range =
                            record_out_of_range + 1;
                    if (!record_have_last_address) begin
                        if (logical_address !== record_start_byte ||
                            pre_fetch_nibble !== 1'b0)
                            record_progression_errors =
                                record_progression_errors + 1;
                        record_unique_addresses =
                            record_unique_addresses + 1;
                    end else if (!record_last_nibble) begin
                        if (logical_address !==
                                record_last_logical_address ||
                            pre_fetch_nibble !== 1'b1)
                            record_progression_errors =
                                record_progression_errors + 1;
                    end else begin
                        if (logical_address !==
                                record_last_logical_address + 24'd1 ||
                            pre_fetch_nibble !== 1'b0)
                            record_progression_errors =
                                record_progression_errors + 1;
                        if (logical_address !==
                            record_last_logical_address)
                            record_unique_addresses =
                                record_unique_addresses + 1;
                    end
                    record_have_last_address = 1'b1;
                    record_last_logical_address = logical_address;
                    record_last_nibble = pre_fetch_nibble;
                    record_fetch_count = record_fetch_count + 1;

                    if (record_kind == 1 && run_id == 1 &&
                        record_fetch_count <= 64)
                        $display(
                            "PRIMARY_FETCH64 index=%0d cycle=%0d address=%06h bank=%h public_address=%05h nibble=%0s byte=%02h captured=%h decoded=%0d",
                            record_fetch_count, system_cycle,
                            logical_address, pre_fetch_bank,
                            pre_fetch_address,
                            pre_fetch_nibble ? "low" : "high",
                            pre_fetch_data, captured_nibble,
                            decoded_pcm
                        );
                end
            end

            if (clk_en_666 && adpcma_match &&
                decoded_pcm != 16'sd0) begin
                if (adpcma_en_ch !=
                    (6'h01 << current_expected_voice))
                    voice_other_decode_nonzero_count =
                        voice_other_decode_nonzero_count + 1;
                else
                    target_decode_event_count =
                        target_decode_event_count + 1;
            end
            if (record_active && TARGET_VOICE != 0 &&
                |(adpcma_active_mask &
                  ~(6'h01 << current_expected_voice)))
                voice_other_active_count =
                    voice_other_active_count + 1;

            if (record_active && public_rise) begin
                if ($isunknown(snd_left) || $isunknown(snd_right) ||
                    $isunknown(adpcmA_l) || $isunknown(adpcmA_r) ||
                    $isunknown(adpcmB_l) || $isunknown(adpcmB_r) ||
                    $isunknown(psg_A) || $isunknown(psg_B) ||
                    $isunknown(psg_C) || $isunknown(psg_snd)) begin
                    public_x_count = public_x_count + 1;
                    failures = failures + 1;
                    $display("FAIL PUBLIC_AUDIO_X label=%0s index=%0d",
                             record_label, record_samples);
                end else begin
                    record_audio_hash =
                        hash_stereo(record_audio_hash,
                                    snd_left, snd_right);
                    record_left_hash =
                        hash_u16(record_left_hash, snd_left);
                    record_right_hash =
                        hash_u16(record_right_hash, snd_right);
                    record_accumulator_hash =
                        hash_stereo(record_accumulator_hash,
                                    adpcmA_l, adpcmA_r);
                    if (!record_alignment_started &&
                        (snd_left != 16'sd0 ||
                         snd_right != 16'sd0))
                        record_alignment_started = 1'b1;
                    if (record_alignment_started &&
                        record_aligned_samples <
                            ALIGNED_SAMPLES) begin
                        record_aligned_hash =
                            hash_stereo(record_aligned_hash,
                                        snd_left, snd_right);
                        record_aligned_samples =
                            record_aligned_samples + 1;
                    end
                    if (record_samples < ATTACK_SAMPLES)
                        record_attack_hash =
                            hash_stereo(record_attack_hash,
                                        snd_left, snd_right);
                    if (snd_left != 16'sd0 ||
                        snd_right != 16'sd0) begin
                        record_nonzero_count =
                            record_nonzero_count + 1;
                        if (record_first_nonzero_index < 0)
                            record_first_nonzero_index =
                                record_samples;
                        if (record_first_final_cycle < 0)
                            record_first_final_cycle =
                                system_cycle;
                    end
                    if (record_first_lane_cycle < 0 &&
                        (adpcmA_l != 16'sd0 ||
                         adpcmA_r != 16'sd0))
                        record_first_lane_cycle =
                            system_cycle;
                    if (adpcmA_l != 16'sd0 ||
                        adpcmA_r != 16'sd0)
                        target_accumulator_nonidle_count =
                            target_accumulator_nonidle_count + 1;

                    magnitude = sample_abs(snd_left);
                    if (sample_abs(snd_right) > magnitude)
                        magnitude = sample_abs(snd_right);
                    if (magnitude > record_peak)
                        record_peak = magnitude;
                    sample_integer = snd_left;
                    if (sample_integer < record_minimum)
                        record_minimum = sample_integer;
                    if (sample_integer > record_maximum)
                        record_maximum = sample_integer;
                    sample_integer = snd_right;
                    if (sample_integer < record_minimum)
                        record_minimum = sample_integer;
                    if (sample_integer > record_maximum)
                        record_maximum = sample_integer;
                    record_dc_sum_l = record_dc_sum_l + snd_left;
                    record_dc_sum_r = record_dc_sum_r + snd_right;

                    if (snd_left != 16'sd0)
                        current_sign = snd_left < 0 ? -1 : 1;
                    else if (snd_right != 16'sd0)
                        current_sign = snd_right < 0 ? -1 : 1;
                    else
                        current_sign = 0;
                    if (current_sign != 0) begin
                        if (record_previous_sign_valid &&
                            current_sign != record_previous_sign)
                            record_zero_crossings =
                                record_zero_crossings + 1;
                        record_previous_sign = current_sign;
                        record_previous_sign_valid = 1;
                    end

                    if (snd_left == 16'sh7fff ||
                        snd_left == 16'sh8000 ||
                        snd_right == 16'sh7fff ||
                        snd_right == 16'sh8000) begin
                        clipping_count = clipping_count + 1;
                        $display("FAIL CLIPPING label=%0s index=%0d",
                                 record_label, record_samples);
                    end
                end

                record_samples = record_samples + 1;
                if (record_samples >= record_goal)
                    record_active = 1'b0;
            end

            if (audit_active && public_rise) begin
                if (psg_A != 8'd0 || psg_B != 8'd0 ||
                    psg_C != 8'd0 || psg_snd != 10'd0)
                    ssg_nonidle_count = ssg_nonidle_count + 1;
                if (fm_operator_result != 14'sd0)
                    fm_nonidle_count = fm_nonidle_count + 1;
                if (adpcmB_l != 16'sd0 || adpcmB_r != 16'sd0 ||
                    adpcmb_active !== 1'b0 ||
                    adpcmb_start_state !== 1'b0)
                    adpcmb_nonidle_count =
                        adpcmb_nonidle_count + 1;
                if (adpcmb_roe_n === 1'b0 && adpcmb_active === 1'b1)
                    adpcmb_fetch_count = adpcmb_fetch_count + 1;
                if (internal_mixer[5:3] !== 3'b111)
                    noise_enable_event_count =
                        noise_enable_event_count + 1;
                if (internal_volume_a[4] ||
                    internal_volume_b[4] ||
                    internal_volume_c[4])
                    envelope_enable_event_count =
                        envelope_enable_event_count + 1;
            end

            previous_internal_sample = internal_snd_sample;
            previous_public_sample = snd_sample;
            previous_ready = warmup_ready;
            previous_up_aon = adpcma_command_update;
            previous_active_any = adpcma_active_any;
        end
    end

    task automatic wait_clocks(input integer count);
        repeat (count) @(posedge clk);
    endtask

    task automatic capture_zero_window(
        input integer sample_total,
        input [8*32-1:0] label,
        input integer allow_adpcma_fetch,
        output reg [63:0] hash_value
    );
        integer index;
        integer fetch_before;
        begin
            hash_value = FNV_OFFSET;
            fetch_before = global_fetch_count;
            for (index = 0; index < sample_total; index = index + 1) begin
                @(posedge snd_sample);
                #1;
                hash_value = hash_stereo(hash_value,
                                         snd_left, snd_right);
                if ($isunknown(snd_left) ||
                    $isunknown(snd_right) ||
                    snd_left != 16'sd0 || snd_right != 16'sd0 ||
                    adpcmA_l != 16'sd0 || adpcmA_r != 16'sd0 ||
                    adpcmB_l != 16'sd0 || adpcmB_r != 16'sd0 ||
                    psg_A != 8'd0 || psg_B != 8'd0 ||
                    psg_C != 8'd0 || psg_snd != 10'd0) begin
                    failures = failures + 1;
                    $display("FAIL ZERO_WINDOW label=%0s index=%0d",
                             label, index);
                end
            end
            if (!allow_adpcma_fetch &&
                global_fetch_count != fetch_before) begin
                failures = failures + 1;
                $display(
                    "FAIL ZERO_WINDOW_FETCH label=%0s before=%0d after=%0d",
                    label, fetch_before, global_fetch_count
                );
            end
            $display(
                "ZERO_WINDOW label=%0s samples=%0d hash=%016h fetch_delta=%0d",
                label, sample_total, hash_value,
                global_fetch_count - fetch_before
            );
        end
    endtask

    task automatic wait_for_voice_idle(
        input [8*32-1:0] label,
        output integer samples_used
    );
        integer consecutive;
        begin
            samples_used = 0;
            consecutive = 0;
            while (consecutive < 16 && samples_used < 512) begin
                @(posedge snd_sample);
                #1;
                samples_used = samples_used + 1;
                if (!$isunknown(snd_left) &&
                    !$isunknown(snd_right) &&
                    adpcma_active_any === 1'b0 &&
                    adpcmA_l == 16'sd0 &&
                    adpcmA_r == 16'sd0 &&
                    snd_left == 16'sd0 &&
                    snd_right == 16'sd0)
                    consecutive = consecutive + 1;
                else
                    consecutive = 0;
            end
            $display(
                "VOICE_IDLE label=%0s samples=%0d consecutive=%0d timeout=%0d",
                label, samples_used, consecutive, consecutive < 16
            );
            if (consecutive < 16) begin
                failures = failures + 1;
                $display("FAIL VOICE_IDLE_TIMEOUT label=%0s", label);
            end
        end
    endtask

    task automatic write_adpcma_register(
        input [7:0] register_address,
        input [7:0] register_data
    );
        begin
            bus.jt10_write_port1(register_address, register_data);
            adpcma_register_write_count =
                adpcma_register_write_count + 1;
            #1;
            if (dut.u_jt10.u_jt12.u_mmr.part !== 1'b1 ||
                dut.u_jt10.u_jt12.u_mmr.selected_register !==
                    register_address ||
                dut.u_jt10.u_jt12.u_mmr.din_copy !==
                    register_data) begin
                failures = failures + 1;
                $display(
                    "FAIL ADPCMA_TRANSPORT register=%02h data=%02h part=%0d selected=%02h captured=%02h",
                    register_address, register_data,
                    dut.u_jt10.u_jt12.u_mmr.part,
                    dut.u_jt10.u_jt12.u_mmr.selected_register,
                    dut.u_jt10.u_jt12.u_mmr.din_copy
                );
            end
            if (register_address == 8'h01) begin
                if (adpcma_total_level !== register_data[5:0]) begin
                    failures = failures + 1;
                    $display("FAIL ADPCMA_TL_CAPTURE");
                end
            end else if (
                register_address >= 8'h08 &&
                register_address <= 8'h0d
            ) begin
                if (adpcma_pan_level !== register_data) begin
                    failures = failures + 1;
                    $display("FAIL ADPCMA_LR_CAPTURE");
                end
            end else if (
                register_address >= 8'h10 &&
                register_address <= 8'h15
            ) begin
                if (adpcma_address_latch[7:0] !== register_data) begin
                    failures = failures + 1;
                    $display("FAIL ADPCMA_START_LOW_CAPTURE");
                end
            end else if (
                register_address >= 8'h18 &&
                register_address <= 8'h1d
            ) begin
                if (adpcma_address_latch[15:8] !== register_data) begin
                    failures = failures + 1;
                    $display("FAIL ADPCMA_START_HIGH_CAPTURE");
                end
            end else if (
                register_address >= 8'h20 &&
                register_address <= 8'h25
            ) begin
                if (adpcma_address_latch[7:0] !== register_data) begin
                    failures = failures + 1;
                    $display("FAIL ADPCMA_END_LOW_CAPTURE");
                end
            end else if (
                register_address >= 8'h28 &&
                register_address <= 8'h2d
            ) begin
                if (adpcma_address_latch[15:8] !== register_data) begin
                    failures = failures + 1;
                    $display("FAIL ADPCMA_END_HIGH_CAPTURE");
                end
            end
            $display(
                "ADPCMA_TRANSPORT register=%02h data=%02h issue_cycle=%0d busy_assert_cycle=%0d busy_clear_cycle=%0d busy_duration=%0d result=PASS",
                register_address, register_data,
                last_issue_cycle, last_busy_assert_cycle,
                last_busy_clear_cycle,
                last_busy_clear_cycle - last_issue_cycle
            );
        end
    endtask

    task automatic arm_and_play(
        input integer kind,
        input [8*32-1:0] label,
        input integer sample_goal,
        input [23:0] start_byte,
        input [23:0] end_byte
    );
        integer timeout;
        begin
            record_kind = kind;
            record_label = label;
            record_goal = sample_goal;
            record_start_byte = start_byte;
            record_end_byte = end_byte;
            record_started = 1'b0;
            record_armed = 1'b1;
            if (TARGET_VOICE != 0) begin
                do begin
                    @(posedge clk);
                    #1;
                end while (
                    (system_cycle + KEYON_ISSUE_PIPELINE) %
                        ADPCMA_SCHEDULER_PERIOD !=
                    TARGET_KEYON_PHASE
                );
            end
            write_adpcma_register(
                8'h00, 8'h01 << current_expected_voice
            );
            timeout = 0;
            while (!record_started && timeout < 4096) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!record_started) begin
                failures = failures + 1;
                $display("FAIL RECORD_START_TIMEOUT label=%0s", label);
            end
            wait (record_active === 1'b0);
            $display(
                "PLAYBACK_WINDOW label=%0s samples=%0d fetches=%0d unique=%0d first_address=%05h first_bank=%h fetch_hash=%016h address_hash=%016h rom_hash=%016h decode_hash=%016h attack_hash=%016h audio_hash=%016h left_hash=%016h right_hash=%016h nonzero=%0d first_nonzero=%0d peak=%0d min=%0d max=%0d zero_crossings=%0d dc_l=%0d dc_r=%0d out_of_range=%0d progression_errors=%0d nibble_errors=%0d",
                label, record_samples, record_fetch_count,
                record_unique_addresses, record_first_address,
                record_first_bank, record_fetch_hash,
                record_address_hash, record_rom_hash,
                record_decode_hash, record_attack_hash,
                record_audio_hash, record_left_hash,
                record_right_hash, record_nonzero_count,
                record_first_nonzero_index, record_peak,
                record_minimum, record_maximum,
                record_zero_crossings, record_dc_sum_l,
                record_dc_sum_r, record_out_of_range,
                record_progression_errors, record_nibble_errors
            );
            if (record_fetch_count == 0 ||
                record_out_of_range != 0 ||
                (record_kind < 20 &&
                 record_progression_errors != 0) ||
                record_nibble_errors != 0) begin
                failures = failures + 1;
                $display("FAIL PLAYBACK_CONTRACT label=%0s", label);
            end
        end
    endtask

    task automatic keyoff_voice(
        input [8*32-1:0] label,
        output integer issue_cycle,
        output integer active_clear_cycle,
        output integer fetch_stop_cycle,
        output integer additional_fetches,
        output integer zero_settle_samples
    );
        integer timeout;
        begin
            keyoff_command_cycle = -1;
            write_adpcma_register(
                8'h00, 8'h80 | (8'h01 << current_expected_voice)
            );
            issue_cycle = last_issue_cycle;
            timeout = 0;
            while (adpcma_active_any !== 1'b0 &&
                   timeout < 20000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            active_clear_cycle = last_active_clear_cycle;
            fetch_stop_cycle = last_valid_fetch_cycle;
            additional_fetches =
                global_fetch_count - keyoff_fetch_snapshot;
            if (timeout >= 20000) begin
                failures = failures + 1;
                $display("FAIL KEYOFF_ACTIVE_TIMEOUT label=%0s", label);
            end
            wait_for_voice_idle(label, zero_settle_samples);
            $display(
                "KEYOFF_RESULT label=%0s issue_cycle=%0d command_cycle=%0d active_clear_cycle=%0d fetch_stop_cycle=%0d additional_fetches=%0d settle_samples=%0d timeout=%0d",
                label, issue_cycle, keyoff_command_cycle,
                active_clear_cycle, fetch_stop_cycle,
                additional_fetches, zero_settle_samples,
                timeout >= 20000
            );
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

    jt10_phase3a_adpcma_rom rom (
        .address(adpcma_addr),
        .bank(adpcma_bank),
        .changed_pattern(changed_pattern),
        .data(adpcma_data)
    );

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
        .session_start(session_start), .loop_event(loop_event),
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

    initial begin : phase3a_sequence
        integer unused_settle;
        integer natural_timeout;
        integer natural_fetch_before;
        integer sentinel_voice;
        integer sentinel_start_register;
        reg [23:0] sentinel_start_byte;
        reg [23:0] sentinel_end_byte;

        if (!$value$plusargs("RUN_ID=%d", run_id))
            run_id = 1;
        $display("ADPCMA_VOICE_BEGIN voice=%0d run=%0d",
                 TARGET_VOICE, run_id);

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
        capture_zero_window(
            16, "initial_silence", 0, initial_silence_hash
        );

        keyoff_all_fm();
        bus.jt10_write_port0(8'h22, 8'h00);
        bus.jt10_write_port0(8'h27, 8'h00);
        bus.jt10_write_port0(8'h2b, 8'h00);
        write_adpcma_register(8'h00, 8'hbf);
        bus.jt10_write_port0(8'h10, 8'h01);
        bus.jt10_write_port0(8'h10, 8'h00);
        bus.jt10_write_port0(8'h08, 8'h00);
        bus.jt10_write_port0(8'h09, 8'h00);
        bus.jt10_write_port0(8'h0a, 8'h00);
        bus.jt10_write_port0(8'h06, 8'h00);
        bus.jt10_write_port0(8'h07, 8'h3f);
        capture_zero_window(
            16, "explicit_silence", 0, explicit_silence_hash
        );
        audit_active = 1'b1;

        if (TARGET_VOICE == 0) begin
            write_adpcma_register(8'h10, 8'h00);
            write_adpcma_register(8'h18, 8'h00);
            write_adpcma_register(8'h20, 8'h0f);
            write_adpcma_register(8'h28, 8'h00);
            write_adpcma_register(8'h01, 8'h3f);
            write_adpcma_register(8'h08, 8'hf5);
            write_adpcma_register(8'h09, 8'h00);
            write_adpcma_register(8'h0a, 8'h00);
            write_adpcma_register(8'h0b, 8'h00);
            write_adpcma_register(8'h0c, 8'h00);
            write_adpcma_register(8'h0d, 8'h00);
        end else begin
            write_adpcma_register(8'h01, 8'h3f);
            for (sentinel_voice = 0;
                 sentinel_voice < 6;
                 sentinel_voice = sentinel_voice + 1) begin
                sentinel_start_register = sentinel_voice * 16;
                write_adpcma_register(
                    8'h10 + sentinel_voice,
                    sentinel_start_register[7:0]
                );
                write_adpcma_register(
                    8'h18 + sentinel_voice, 8'h00
                );
                write_adpcma_register(
                    8'h20 + sentinel_voice,
                    sentinel_start_register[7:0] + 8'h0f
                );
                write_adpcma_register(
                    8'h28 + sentinel_voice, 8'h00
                );
                write_adpcma_register(
                    8'h08 + sentinel_voice, 8'h00
                );
            end
            for (sentinel_voice = 0;
                 sentinel_voice < 6;
                 sentinel_voice = sentinel_voice + 1) begin
                sentinel_start_register = sentinel_voice * 16;
                current_expected_voice = sentinel_voice;
                sentinel_start_byte =
                    (sentinel_voice * 24'h001000);
                sentinel_end_byte =
                    sentinel_start_byte + 24'h000fff;
                write_adpcma_register(
                    8'h08 + sentinel_voice, 8'hf5
                );
                arm_and_play(
                    20 + sentinel_voice, "mapping_sentinel",
                    64, sentinel_start_byte, sentinel_end_byte
                );
                sentinel_audio_hash[sentinel_voice] =
                    record_audio_hash;
                sentinel_first_address[sentinel_voice] =
                    record_first_address;
                if (record_first_address !==
                        sentinel_start_byte[19:0] ||
                    record_first_bank !==
                        sentinel_start_byte[23:20]) begin
                    failures = failures + 1;
                    $display(
                        "FAIL MAPPING_SENTINEL voice=%0d expected=%06h actual_bank=%h actual_address=%05h",
                        sentinel_voice, sentinel_start_byte,
                        record_first_bank, record_first_address
                    );
                end
                $display(
                    "MAPPING_SENTINEL voice=%0d start_reg=%03h end_reg=%03h first_address=%06h fetch_hash=%016h audio_hash=%016h result=PASS",
                    sentinel_voice, sentinel_start_register,
                    sentinel_start_register + 15,
                    {record_first_bank[3:0],
                     record_first_address[19:0]},
                    record_fetch_hash, record_audio_hash
                );
                keyoff_voice(
                    "sentinel_stop", dummy_issue_cycle,
                    dummy_active_clear_cycle,
                    dummy_fetch_stop_cycle,
                    dummy_additional_fetches, unused_settle
                );
                write_adpcma_register(
                    8'h08 + sentinel_voice, 8'h00
                );
            end
            current_expected_voice = TARGET_VOICE;
            write_adpcma_register(TARGET_START_LOW, 8'h00);
            write_adpcma_register(TARGET_START_HIGH, 8'h00);
            write_adpcma_register(TARGET_END_LOW, 8'h0f);
            write_adpcma_register(TARGET_END_HIGH, 8'h00);
            write_adpcma_register(TARGET_LEVEL_REGISTER, 8'hf5);
        end
        capture_zero_window(
            16, "prekey_silence", 0, prekey_silence_hash
        );

        arm_and_play(
            1, "primary", PRIMARY_SAMPLES,
            24'h000000, 24'h000fff
        );
        primary_fetch_hash = record_fetch_hash;
        primary_address_hash = record_address_hash;
        primary_rom_hash = record_rom_hash;
        primary_decode_hash = record_decode_hash;
        primary_audio_hash = record_audio_hash;
        primary_attack_hash = record_attack_hash;
        primary_left_hash = record_left_hash;
        primary_right_hash = record_right_hash;
        primary_accumulator_hash = record_accumulator_hash;
        primary_aligned_hash = record_aligned_hash;
        primary_fetch_count = record_fetch_count;
        primary_unique_addresses = record_unique_addresses;
        primary_keyon_issue_cycle = record_keyon_issue_cycle;
        primary_keyon_cycle = record_keyon_cycle;
        primary_target_slot_cycle = record_target_slot_cycle;
        primary_target_slot_delay = record_target_slot_delay;
        primary_aon_pulse_cycle = record_aon_pulse_cycle;
        primary_keyon_cur_ch = record_keyon_cur_ch;
        primary_keyon_en_ch = record_keyon_en_ch;
        primary_active_cycle = record_active_cycle;
        primary_first_fetch_cycle = record_first_fetch_cycle;
        primary_first_capture_cycle = record_first_capture_cycle;
        primary_first_decode_cycle = record_first_decode_cycle;
        primary_first_lane_cycle = record_first_lane_cycle;
        primary_first_final_cycle = record_first_final_cycle;
        primary_first_nonzero_index =
            record_first_nonzero_index;
        primary_first_address = record_first_address;
        primary_first_bank = record_first_bank;
        primary_peak = record_peak;
        primary_minimum = record_minimum;
        primary_maximum = record_maximum;
        primary_zero_crossings = record_zero_crossings;
        primary_nonzero_count = record_nonzero_count;
        primary_dc_sum_l = record_dc_sum_l;
        primary_dc_sum_r = record_dc_sum_r;
        if (primary_nonzero_count == 0 ||
            primary_first_lane_cycle < 0 ||
            primary_first_final_cycle < 0) begin
            failures = failures + 1;
            $display("FAIL PRIMARY_AUDIO_ZERO");
        end
        keyoff_voice(
            "primary_stop", dummy_issue_cycle,
            dummy_active_clear_cycle, dummy_fetch_stop_cycle,
            dummy_additional_fetches, unused_settle
        );

        write_adpcma_register(TARGET_LEVEL_REGISTER, 8'hb5);
        arm_and_play(
            2, "left_only", PRIMARY_SAMPLES,
            24'h000000, 24'h000fff
        );
        left_fetch_hash = record_fetch_hash;
        left_address_hash = record_address_hash;
        left_rom_hash = record_rom_hash;
        left_decode_hash = record_decode_hash;
        left_audio_hash = record_audio_hash;
        left_left_hash = record_left_hash;
        left_right_hash = record_right_hash;
        if (record_nonzero_count == 0 ||
            left_right_hash != 64'hb9d103fd6854a325 ||
            left_left_hash != primary_left_hash ||
            left_fetch_hash != primary_fetch_hash ||
            left_address_hash != primary_address_hash ||
            left_rom_hash != primary_rom_hash ||
            left_decode_hash != primary_decode_hash) begin
            failures = failures + 1;
            $display("FAIL LEFT_ONLY_CONTROL");
        end
        keyoff_voice(
            "left_stop", dummy_issue_cycle,
            dummy_active_clear_cycle, dummy_fetch_stop_cycle,
            dummy_additional_fetches, unused_settle
        );

        write_adpcma_register(TARGET_LEVEL_REGISTER, 8'h75);
        arm_and_play(
            3, "right_only", PRIMARY_SAMPLES,
            24'h000000, 24'h000fff
        );
        right_fetch_hash = record_fetch_hash;
        right_address_hash = record_address_hash;
        right_rom_hash = record_rom_hash;
        right_decode_hash = record_decode_hash;
        right_audio_hash = record_audio_hash;
        right_left_hash = record_left_hash;
        right_right_hash = record_right_hash;
        if (record_nonzero_count == 0 ||
            right_left_hash != 64'hb9d103fd6854a325 ||
            right_right_hash != primary_right_hash ||
            right_fetch_hash != primary_fetch_hash ||
            right_address_hash != primary_address_hash ||
            right_rom_hash != primary_rom_hash ||
            right_decode_hash != primary_decode_hash ||
            right_right_hash != left_left_hash) begin
            failures = failures + 1;
            $display("FAIL RIGHT_ONLY_CONTROL");
        end
        keyoff_voice(
            "right_stop", dummy_issue_cycle,
            dummy_active_clear_cycle, dummy_fetch_stop_cycle,
            dummy_additional_fetches, unused_settle
        );

        write_adpcma_register(TARGET_LEVEL_REGISTER, 8'hf5);
        write_adpcma_register(8'h01, 8'h00);
        arm_and_play(
            4, "level_mute", CONTROL_SAMPLES,
            24'h000000, 24'h000fff
        );
        mute_audio_hash = record_audio_hash;
        mute_fetch_hash = record_fetch_hash;
        mute_decode_hash = record_decode_hash;
        if (record_nonzero_count != 0 ||
            mute_audio_hash != 64'h28c31cf8df2ec325 ||
            record_fetch_count == 0) begin
            failures = failures + 1;
            $display("FAIL LEVEL_MUTE");
        end
        keyoff_voice(
            "mute_stop", dummy_issue_cycle,
            dummy_active_clear_cycle, dummy_fetch_stop_cycle,
            dummy_additional_fetches, unused_settle
        );
        write_adpcma_register(8'h01, 8'h3f);

        write_adpcma_register(
            TARGET_START_LOW,
            TARGET_VOICE == 0 ? 8'h01 : TARGET_VOICE[7:0]
        );
        if (TARGET_VOICE != 0)
            write_adpcma_register(
                TARGET_END_LOW, TARGET_VOICE[7:0] + 8'h0f
            );
        arm_and_play(
            5, "shifted_start", PRIMARY_SAMPLES,
            TARGET_VOICE == 0 ?
                24'h000100 : TARGET_VOICE * 24'h000100,
            TARGET_VOICE == 0 ?
                24'h000fff :
                (TARGET_VOICE + 15) * 24'h000100 + 24'h0000ff
        );
        shifted_fetch_hash = record_fetch_hash;
        shifted_address_hash = record_address_hash;
        shifted_rom_hash = record_rom_hash;
        shifted_decode_hash = record_decode_hash;
        shifted_audio_hash = record_audio_hash;
        shifted_first_address = record_first_address;
        if (shifted_first_address !=
                (TARGET_VOICE == 0 ?
                    20'h00100 : TARGET_VOICE * 20'h00100) ||
            shifted_address_hash == primary_address_hash ||
            shifted_rom_hash == primary_rom_hash ||
            shifted_decode_hash == primary_decode_hash ||
            shifted_audio_hash == primary_audio_hash) begin
            failures = failures + 1;
            $display("FAIL SHIFTED_START_CONTROL");
        end
        keyoff_voice(
            "shift_stop", dummy_issue_cycle,
            dummy_active_clear_cycle, dummy_fetch_stop_cycle,
            dummy_additional_fetches, unused_settle
        );
        write_adpcma_register(TARGET_START_LOW, 8'h00);
        if (TARGET_VOICE != 0)
            write_adpcma_register(TARGET_END_LOW, 8'h0f);

        if (TARGET_VOICE == 0) begin
            changed_pattern = 1'b1;
            arm_and_play(
                6, "changed_rom", PRIMARY_SAMPLES,
                24'h000000, 24'h000fff
            );
            changed_fetch_hash = record_fetch_hash;
            changed_address_hash = record_address_hash;
            changed_rom_hash = record_rom_hash;
            changed_decode_hash = record_decode_hash;
            changed_audio_hash = record_audio_hash;
            if (changed_fetch_hash != primary_fetch_hash ||
                changed_address_hash != primary_address_hash ||
                changed_rom_hash == primary_rom_hash ||
                changed_decode_hash == primary_decode_hash ||
                changed_audio_hash == primary_audio_hash) begin
                failures = failures + 1;
                $display("FAIL CHANGED_ROM_CONTROL");
            end
            keyoff_voice(
                "changed_stop", dummy_issue_cycle,
                dummy_active_clear_cycle, dummy_fetch_stop_cycle,
                dummy_additional_fetches, unused_settle
            );
            changed_pattern = 1'b0;
        end else begin
            changed_fetch_hash = 64'd0;
            changed_address_hash = 64'd0;
            changed_rom_hash = 64'd0;
            changed_decode_hash = 64'd0;
            changed_audio_hash = 64'd0;
        end

        arm_and_play(
            7, "midstream_prefix", CONTROL_SAMPLES,
            24'h000000, 24'h000fff
        );
        keyoff_voice(
            "midstream_keyoff", mid_keyoff_issue_cycle,
            mid_active_clear_cycle, mid_fetch_stop_cycle,
            mid_additional_fetches, mid_zero_settle_samples
        );
        capture_zero_window(
            CONTROL_SAMPLES, "midstream_keyoff_zero", 0,
            keyoff_zero_hash
        );
        if (keyoff_zero_hash != 64'h28c31cf8df2ec325)
            failures = failures + 1;

        write_adpcma_register(TARGET_END_LOW, 8'h00);
        bus.jt10_write_port0(
            8'h1c, 8'h01 << TARGET_VOICE
        );
        record_kind = 8;
        record_label = "natural_end";
        record_goal = 1000000;
        record_start_byte = 24'h000000;
        record_end_byte = 24'h0000ff;
        record_started = 1'b0;
        record_armed = 1'b1;
        natural_fetch_before = global_fetch_count;
        if (TARGET_VOICE != 0) begin
            do begin
                @(posedge clk);
                #1;
            end while (
                (system_cycle + KEYON_ISSUE_PIPELINE) %
                    ADPCMA_SCHEDULER_PERIOD !=
                TARGET_KEYON_PHASE
            );
        end
        write_adpcma_register(8'h00, TARGET_KEY_MASK);
        wait (record_started);
        natural_timeout = 0;
        while (adpcma_flags[TARGET_VOICE] !== 1'b1 &&
               natural_timeout < NATURAL_TIMEOUT_SAMPLES) begin
            @(posedge snd_sample);
            natural_timeout = natural_timeout + 1;
        end
        if (natural_timeout >= NATURAL_TIMEOUT_SAMPLES) begin
            failures = failures + 1;
            $display("FAIL NATURAL_END_TIMEOUT");
        end
        @(negedge clk);
        record_active = 1'b0;
        natural_playback_hash = record_audio_hash;
        natural_end_fetch_count =
            global_fetch_count - natural_fetch_before;
        natural_end_last_address = last_valid_fetch_cycle < 0 ?
            -1 : record_last_logical_address;
        natural_fetch_stop_cycle = last_valid_fetch_cycle;
        natural_active_clear_cycle = last_active_clear_cycle;
        wait_for_voice_idle(
            "natural_end", natural_zero_settle_samples
        );
        capture_zero_window(
            CONTROL_SAMPLES, "natural_end_zero", 0,
            natural_zero_hash
        );
        if (natural_zero_hash != 64'h28c31cf8df2ec325 ||
            natural_end_fetch_count != 512 ||
            record_last_logical_address != 24'h0000ff ||
            record_last_nibble != 1'b1 ||
            record_out_of_range != 0 ||
            adpcma_active_any !== 1'b0) begin
            failures = failures + 1;
            $display("FAIL NATURAL_END_CONTRACT");
        end
        write_adpcma_register(TARGET_END_LOW, 8'h0f);
        // Re-enter the same 432-system-cycle ADPCM-A channel scheduler phase
        // used by the primary key-on.  This makes the retrigger comparison
        // cover the same public-sample and serialized-channel alignment.
        if (TARGET_VOICE == 0)
            wait_clocks(89);

        arm_and_play(
            9, "retrigger", PRIMARY_SAMPLES,
            24'h000000, 24'h000fff
        );
        retrigger_fetch_hash = record_fetch_hash;
        retrigger_address_hash = record_address_hash;
        retrigger_rom_hash = record_rom_hash;
        retrigger_decode_hash = record_decode_hash;
        retrigger_attack_hash = record_attack_hash;
        retrigger_accumulator_hash = record_accumulator_hash;
        retrigger_aligned_hash = record_aligned_hash;
        retrigger_audio_hash = record_audio_hash;
        if (retrigger_fetch_hash != primary_fetch_hash ||
            retrigger_address_hash != primary_address_hash ||
            retrigger_rom_hash != primary_rom_hash ||
            retrigger_decode_hash != primary_decode_hash ||
            retrigger_attack_hash != primary_attack_hash ||
            retrigger_accumulator_hash !=
                primary_accumulator_hash ||
            retrigger_aligned_hash != primary_aligned_hash ||
            retrigger_audio_hash != primary_audio_hash ||
            record_active_cycle - record_keyon_cycle !=
                primary_active_cycle - primary_keyon_cycle ||
            record_first_fetch_cycle - record_keyon_cycle !=
                primary_first_fetch_cycle - primary_keyon_cycle ||
            record_first_capture_cycle - record_keyon_cycle !=
                primary_first_capture_cycle - primary_keyon_cycle ||
            record_first_decode_cycle - record_keyon_cycle !=
                primary_first_decode_cycle - primary_keyon_cycle ||
            record_first_lane_cycle - record_keyon_cycle !=
                primary_first_lane_cycle - primary_keyon_cycle ||
            record_first_final_cycle - record_keyon_cycle !=
                primary_first_final_cycle - primary_keyon_cycle ||
            record_target_slot_delay !=
                primary_target_slot_delay) begin
            failures = failures + 1;
            $display("FAIL RETRIGGER_DETERMINISM");
        end
        keyoff_voice(
            "retrigger_stop", dummy_issue_cycle,
            dummy_active_clear_cycle, dummy_fetch_stop_cycle,
            dummy_additional_fetches, unused_settle
        );
        write_adpcma_register(8'h00, 8'hbf);

        if (busy_timeout_count != 0 ||
            busy_while_write_count != 0 ||
            busy_min_cycles < 190 ||
            busy_max_cycles > 192 ||
            cadence_error_count != 0 ||
            width_error_count != 0 ||
            sample_drop_count != 0 ||
            sample_duplicate_count != 0 ||
            sample_mismatch_count != 0 ||
            public_x_count != 0 ||
            clipping_count != 0 ||
            voice_other_keyon_count != 0 ||
            voice_other_fetch_count != 0 ||
            voice_other_decode_nonzero_count != 0 ||
            (TARGET_VOICE != 0 &&
             voice_other_active_count != 0) ||
            (TARGET_VOICE != 0 &&
             target_decode_event_count == 0) ||
            (TARGET_VOICE != 0 &&
             target_accumulator_nonidle_count == 0) ||
            command_mask_error_count != 0 ||
            adpcmb_fetch_count != 0 ||
            adpcmb_nonidle_count != 0 ||
            fm_nonidle_count != 0 ||
            ssg_nonidle_count != 0 ||
            noise_enable_event_count != 0 ||
            envelope_enable_event_count != 0 ||
            adpcmb_start_state !== 1'b0 ||
            adpcmb_active !== 1'b0 ||
            internal_volume_a !== 8'h00 ||
            internal_volume_b !== 8'h00 ||
            internal_volume_c !== 8'h00 ||
            internal_mixer !== 8'h3f ||
            internal_envelope_low !== 8'h00 ||
            internal_envelope_high !== 8'h00 ||
            internal_envelope_shape !== 8'h00) begin
            failures = failures + 1;
            $display("FAIL FINAL_AUDIT");
        end

        $display(
            "BUS_RESULT port0=%0d port1=%0d accepted=%0d adpcma_register_writes=%0d adpcma_command_updates=%0d timeout=%0d write_while_busy=%0d busy_min=%0d busy_max=%0d busy_hash=%016h",
            port0_write_count, port1_write_count,
            accepted_write_count, adpcma_register_write_count,
            adpcma_command_update_count,
            busy_timeout_count, busy_while_write_count,
            busy_min_cycles, busy_max_cycles,
            busy_duration_hash
        );
        $display(
            "SAMPLE_RESULT cadence=144 width=6 ready_cycle=%0d first_public_cycle=%0d internal_pulses_at_first=6 public_samples=%0d cadence_errors=%0d width_errors=%0d drops=%0d duplicates=%0d mismatches=%0d",
            warmup_ready_cycle, first_public_cycle,
            public_pulse_count, cadence_error_count,
            width_error_count, sample_drop_count,
            sample_duplicate_count, sample_mismatch_count
        );
        $display(
            "ADPCMA_LANDMARKS keyon_issue_cycle=%0d active_cycle=%0d first_fetch_cycle=%0d first_capture_cycle=%0d first_decode_cycle=%0d first_lane_cycle=%0d first_final_cycle=%0d first_nonzero_index=%0d first_address=%05h first_bank=%h",
            primary_keyon_cycle, primary_active_cycle,
            primary_first_fetch_cycle,
            primary_first_capture_cycle,
            primary_first_decode_cycle,
            primary_first_lane_cycle,
            primary_first_final_cycle,
            primary_first_nonzero_index,
            primary_first_address, primary_first_bank
        );
        $display(
            "ADPCMA_PRIMARY fetch_count=%0d unique_addresses=%0d fetch_hash=%016h address_hash=%016h rom_hash=%016h decode_hash=%016h attack_hash=%016h audio_hash=%016h left_hash=%016h right_hash=%016h nonzero=%0d peak=%0d min=%0d max=%0d zero_crossings=%0d dc_l=%0d dc_r=%0d",
            primary_fetch_count, primary_unique_addresses,
            primary_fetch_hash, primary_address_hash,
            primary_rom_hash, primary_decode_hash,
            primary_attack_hash, primary_audio_hash,
            primary_left_hash, primary_right_hash,
            primary_nonzero_count, primary_peak,
            primary_minimum, primary_maximum,
            primary_zero_crossings, primary_dc_sum_l,
            primary_dc_sum_r
        );
        $display(
            "ADPCMA_CONTROLS left_audio=%016h left_l=%016h left_r=%016h right_audio=%016h right_l=%016h right_r=%016h mute_audio=%016h mute_fetch=%016h mute_decode=%016h shifted_first=%05h shifted_fetch=%016h shifted_address=%016h shifted_rom=%016h shifted_decode=%016h shifted_audio=%016h changed_fetch=%016h changed_address=%016h changed_rom=%016h changed_decode=%016h changed_audio=%016h",
            left_audio_hash, left_left_hash, left_right_hash,
            right_audio_hash, right_left_hash, right_right_hash,
            mute_audio_hash, mute_fetch_hash, mute_decode_hash,
            shifted_first_address, shifted_fetch_hash,
            shifted_address_hash, shifted_rom_hash,
            shifted_decode_hash, shifted_audio_hash,
            changed_fetch_hash, changed_address_hash,
            changed_rom_hash, changed_decode_hash,
            changed_audio_hash
        );
        $display(
            "ADPCMA_STOP keyoff_issue=%0d keyoff_active_clear=%0d keyoff_fetch_stop=%0d keyoff_additional_fetches=%0d keyoff_settle=%0d keyoff_zero_hash=%016h natural_active_clear=%0d natural_fetch_stop=%0d natural_fetch_count=%0d natural_last_address=%06h natural_settle=%0d natural_playback_hash=%016h natural_zero_hash=%016h retrigger_fetch=%016h retrigger_address=%016h retrigger_rom=%016h retrigger_decode=%016h retrigger_audio=%016h",
            mid_keyoff_issue_cycle, mid_active_clear_cycle,
            mid_fetch_stop_cycle, mid_additional_fetches,
            mid_zero_settle_samples, keyoff_zero_hash,
            natural_active_clear_cycle, natural_fetch_stop_cycle,
            natural_end_fetch_count, natural_end_last_address,
            natural_zero_settle_samples, natural_playback_hash,
            natural_zero_hash, retrigger_fetch_hash,
            retrigger_address_hash, retrigger_rom_hash,
            retrigger_decode_hash, retrigger_audio_hash
        );
        $display(
            "ISOLATION_RESULT voice_other_keyon=%0d voice_other_fetch=%0d voice_other_decode_nonzero=%0d adpcmb_fetch=%0d adpcmb_nonidle=%0d fm_nonidle=%0d ssg_nonidle=%0d noise_enable=%0d envelope_enable=%0d x_count=%0d clipping=%0d",
            voice_other_keyon_count, voice_other_fetch_count,
            voice_other_decode_nonzero_count,
            adpcmb_fetch_count, adpcmb_nonidle_count,
            fm_nonidle_count, ssg_nonidle_count,
            noise_enable_event_count,
            envelope_enable_event_count,
            public_x_count, clipping_count
        );
        $display(
            "ADPCMA_RESULT run=%0d failures=%0d busy_hash=%016h ready_cycle=%0d first_public_cycle=%0d keyon_cycle=%0d active_cycle=%0d first_fetch_cycle=%0d first_capture_cycle=%0d first_decode_cycle=%0d first_lane_cycle=%0d first_final_cycle=%0d first_nonzero_index=%0d fetch_count=%0d unique_addresses=%0d fetch_hash=%016h address_hash=%016h rom_hash=%016h decode_hash=%016h attack_hash=%016h audio_hash=%016h peak=%0d min=%0d max=%0d zero_crossings=%0d dc_l=%0d dc_r=%0d left_hash=%016h right_hash=%016h mute_hash=%016h shifted_hash=%016h changed_hash=%016h keyoff_hash=%016h natural_hash=%016h retrigger_hash=%016h x_count=%0d clipping=%0d drops=%0d duplicates=%0d",
            run_id, failures, busy_duration_hash,
            warmup_ready_cycle, first_public_cycle,
            primary_keyon_cycle, primary_active_cycle,
            primary_first_fetch_cycle,
            primary_first_capture_cycle,
            primary_first_decode_cycle,
            primary_first_lane_cycle,
            primary_first_final_cycle,
            primary_first_nonzero_index,
            primary_fetch_count, primary_unique_addresses,
            primary_fetch_hash, primary_address_hash,
            primary_rom_hash, primary_decode_hash,
            primary_attack_hash, primary_audio_hash,
            primary_peak, primary_minimum, primary_maximum,
            primary_zero_crossings, primary_dc_sum_l,
            primary_dc_sum_r, left_audio_hash,
            right_audio_hash, mute_audio_hash,
            shifted_audio_hash, changed_audio_hash,
            keyoff_zero_hash, natural_zero_hash,
            retrigger_audio_hash, public_x_count,
            clipping_count, sample_drop_count,
            sample_duplicate_count
        );
        $display(
            "ADPCMA_ALIGNMENT voice=%0d aligned_samples=%0d aligned_hash=%016h accumulator_hash=%016h retrigger_aligned=%016h",
            TARGET_VOICE, ALIGNED_SAMPLES,
            primary_aligned_hash, primary_accumulator_hash,
            retrigger_aligned_hash
        );
        if (TARGET_VOICE != 0) begin
            $display(
                "PHASE3B_MAPPING voice=%0d level_reg=%02h start_low=%02h start_high=%02h end_low=%02h end_high=%02h keyon=%02h keyoff=%02h scheduler_slot=%0d slot_mask=%06b",
                TARGET_VOICE, TARGET_LEVEL_REGISTER,
                TARGET_START_LOW, TARGET_START_HIGH,
                TARGET_END_LOW, TARGET_END_HIGH,
                TARGET_KEY_MASK, TARGET_KEYOFF_MASK,
                TARGET_VOICE, TARGET_SLOT_MASK
            );
            $display(
                "PHASE3B_SCHEDULER voice=%0d period=432 target_issue_phase=%0d keyon_issue=%0d keyon_accept=%0d accept_cur_ch=%06b accept_en_ch=%06b target_slot_cycle=%0d target_slot_delay=%0d aon_pulse_cycle=%0d active_cycle=%0d first_fetch_cycle=%0d first_decode_cycle=%0d first_lane_cycle=%0d first_final_cycle=%0d",
                TARGET_VOICE, TARGET_KEYON_PHASE,
                primary_keyon_issue_cycle,
                primary_keyon_cycle, primary_keyon_cur_ch,
                primary_keyon_en_ch, primary_target_slot_cycle,
                primary_target_slot_delay,
                primary_aon_pulse_cycle, primary_active_cycle,
                primary_first_fetch_cycle,
                primary_first_decode_cycle,
                primary_first_lane_cycle,
                primary_first_final_cycle
            );
            $display(
                "PHASE3B_PRIMARY voice=%0d run=%0d fetch_count=%0d unique_addresses=%0d first_address=%05h first_bank=%h fetch_hash=%016h address_hash=%016h rom_hash=%016h decode_hash=%016h attack_hash=%016h accumulator_hash=%016h aligned_samples=%0d aligned_hash=%016h audio_hash=%016h left_hash=%016h right_hash=%016h nonzero=%0d first_nonzero=%0d peak=%0d min=%0d max=%0d zero_crossings=%0d dc_l=%0d dc_r=%0d",
                TARGET_VOICE, run_id, primary_fetch_count,
                primary_unique_addresses,
                primary_first_address, primary_first_bank,
                primary_fetch_hash, primary_address_hash,
                primary_rom_hash, primary_decode_hash,
                primary_attack_hash,
                primary_accumulator_hash,
                ALIGNED_SAMPLES, primary_aligned_hash,
                primary_audio_hash, primary_left_hash,
                primary_right_hash, primary_nonzero_count,
                primary_first_nonzero_index, primary_peak,
                primary_minimum, primary_maximum,
                primary_zero_crossings, primary_dc_sum_l,
                primary_dc_sum_r
            );
            $display(
                "PHASE3B_CONTROLS voice=%0d left_audio=%016h left_l=%016h left_r=%016h right_audio=%016h right_l=%016h right_r=%016h mute_audio=%016h mute_fetch=%016h mute_decode=%016h unique_first=%05h unique_fetch=%016h unique_address=%016h unique_rom=%016h unique_decode=%016h unique_audio=%016h",
                TARGET_VOICE, left_audio_hash, left_left_hash,
                left_right_hash, right_audio_hash,
                right_left_hash, right_right_hash,
                mute_audio_hash, mute_fetch_hash,
                mute_decode_hash, shifted_first_address,
                shifted_fetch_hash, shifted_address_hash,
                shifted_rom_hash, shifted_decode_hash,
                shifted_audio_hash
            );
            $display(
                "PHASE3B_STOP voice=%0d keyoff_issue=%0d active_clear=%0d fetch_stop=%0d additional_fetches=%0d settle=%0d keyoff_zero=%016h natural_active_clear=%0d natural_fetch_stop=%0d natural_fetch_count=%0d natural_last_address=%06h natural_settle=%0d natural_playback=%016h natural_zero=%016h retrigger_fetch=%016h retrigger_address=%016h retrigger_rom=%016h retrigger_decode=%016h retrigger_attack=%016h retrigger_accumulator=%016h retrigger_aligned=%016h retrigger_audio=%016h",
                TARGET_VOICE, mid_keyoff_issue_cycle,
                mid_active_clear_cycle, mid_fetch_stop_cycle,
                mid_additional_fetches,
                mid_zero_settle_samples, keyoff_zero_hash,
                natural_active_clear_cycle,
                natural_fetch_stop_cycle,
                natural_end_fetch_count,
                natural_end_last_address,
                natural_zero_settle_samples,
                natural_playback_hash, natural_zero_hash,
                retrigger_fetch_hash,
                retrigger_address_hash,
                retrigger_rom_hash,
                retrigger_decode_hash,
                retrigger_attack_hash,
                retrigger_accumulator_hash,
                retrigger_aligned_hash,
                retrigger_audio_hash
            );
            $display(
                "PHASE3B_ISOLATION voice=%0d other_active=%0d other_keyon=%0d other_fetch=%0d other_decode=%0d target_decode=%0d target_accumulator_nonidle=%0d command_mask_errors=%0d adpcmb_fetch=%0d adpcmb_nonidle=%0d fm_nonidle=%0d ssg_nonidle=%0d noise_enable=%0d envelope_enable=%0d x_count=%0d clipping=%0d drops=%0d duplicates=%0d",
                TARGET_VOICE, voice_other_active_count,
                voice_other_keyon_count,
                voice_other_fetch_count,
                voice_other_decode_nonzero_count,
                target_decode_event_count,
                target_accumulator_nonidle_count,
                command_mask_error_count,
                adpcmb_fetch_count, adpcmb_nonidle_count,
                fm_nonidle_count, ssg_nonidle_count,
                noise_enable_event_count,
                envelope_enable_event_count,
                public_x_count, clipping_count,
                sample_drop_count, sample_duplicate_count
            );
            $display(
                "PHASE3B_RESULT voice=%0d run=%0d failures=%0d accepted=%0d port0=%0d port1=%0d busy_hash=%016h ready_cycle=%0d first_public_cycle=%0d cadence_errors=%0d width_errors=%0d result=%0s",
                TARGET_VOICE, run_id, failures,
                accepted_write_count, port0_write_count,
                port1_write_count, busy_duration_hash,
                warmup_ready_cycle, first_public_cycle,
                cadence_error_count, width_error_count,
                failures == 0 ? "PASS" : "FAIL"
            );
        end

        if (failures != 0)
            $fatal(1, "JT10 ADPCM-A voice %0d test failed (%0d)",
                   TARGET_VOICE, failures);
        if (TARGET_VOICE == 0)
            $display("ADPCMA_VOICE0_PASS run=%0d", run_id);
        else
            $display("ADPCMA_VOICE_PASS voice=%0d run=%0d",
                     TARGET_VOICE, run_id);
        $finish;
    end
endmodule
