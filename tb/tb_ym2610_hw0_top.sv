`timescale 1ns/1ps

module tb_ym2610_hw0_top;
    localparam logic [63:0] FNV_OFFSET = 64'hcbf29ce484222325;
    logic clk = 1'b0;
    logic reset = 1'b1;
    integer run_id = 1;
    integer failures = 0;
    integer system_cycle = 0;
    integer public_samples = 0;
    integer internal_samples = 0;
    integer last_public_cycle = -1;
    integer cadence_errors = 0;
    integer width_errors = 0;
    integer drops = 0;
    integer duplicates = 0;
    integer x_count = 0;
    integer public_width = 0;
    integer cold_zero_samples = 0;
    integer final_zero_samples = 0;
    integer phase_order_index = 0;
    integer pan_leak = 0;
    integer left_nonzero = 0;
    integer right_nonzero = 0;
    integer natural_logical [0:1];
    integer natural_zero_latency [0:1];
    integer natural_run = -1;
    integer zero_wait_samples = 0;
    integer stale_prefix = 0;
    integer x_audio = 0;
    integer x_control = 0;
    integer x_psg = 0;
    integer x_rom_a = 0;
    integer x_rom_b = 0;
    integer pre_ready_x = 0;
    integer pre_ready_nonzero = 0;
    integer phase5_zero_latency = -1;
    integer phase5_zero_wait = 0;
    integer phase5_request_after_stop = 0;
    integer psg_bc_spurious = 0;
    integer psg_a_nonzero = 0;
    integer unexpected_adpcm_requests = 0;
    integer a6_overflow_events = 0;
    logic phase5_stop_seen = 1'b0;
    logic previous_public = 1'b0;
    logic previous_internal = 1'b0;
    logic previous_measurement = 1'b0;
    logic previous_b_active = 1'b0;
    logic previous_b_eos = 1'b0;
    logic [3:0] last_audible_phase = 4'd0;
    logic [15:0] first_prefix_l [0:15];
    logic [15:0] first_prefix_r [0:15];
    integer prefix_count [0:1];
    logic [63:0] phase_hash [1:5];
    integer phase_hash_count [1:5];
    logic [63:0] natural_hash [0:1];

    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire audio_sample;
    wire video_ce, video_hs, video_vs, video_de;
    wire [7:0] video_r, video_g, video_b;
    wire [3:0] debug_phase;
    wire [7:0] debug_microcode_index;
    wire [31:0] debug_accepted_writes;
    wire debug_busy_timeout, debug_write_while_busy;
    wire [15:0] debug_restart_count;
    wire debug_measurement_active;
    wire [3:0] debug_measurement_phase;
    wire debug_adpcma_request, debug_adpcmb_request;
    wire [5:0] debug_adpcma_eos;
    wire debug_adpcmb_eos, debug_adpcmb_active;
    wire [19:0] debug_adpcma_addr;
    wire [3:0] debug_adpcma_bank;
    wire [23:0] debug_adpcmb_addr;
    wire [7:0] debug_psg_a, debug_psg_b, debug_psg_c;
    wire [9:0] debug_psg_snd;
    wire debug_core_ready;
    wire [2:0] debug_reset_cen_count;
    wire debug_halted;

    wire internal_sample = dut.internal_sample;
    wire b_chon = dut.u_jt10.u_core.gen_adpcm.u_adpcm_b.chon;
    wire b_restart = dut.u_jt10.u_core.gen_adpcm.u_adpcm_b.restart;
    wire b_adv = dut.u_jt10.u_core.gen_adpcm.u_adpcm_b.adv;
    wire b_nibble = dut.u_jt10.u_core.gen_adpcm.u_adpcm_b.nibble_sel;
    wire clk_en_55 = dut.u_jt10.u_core.clk_en_55;
    wire [1:0] b_pan = dut.u_jt10.u_core.alr_b;
    wire b_logical = dut.jt10_cen && clk_en_55 && b_adv && b_chon &&
                     !b_restart && !debug_adpcmb_eos;

    function automatic [63:0] hash_byte(
        input [63:0] hash_in, input [7:0] value
    );
        hash_byte = (hash_in ^ value) * 64'h00000100000001b3;
    endfunction
    function automatic [63:0] hash_u16(
        input [63:0] hash_in, input [15:0] value
    );
        hash_u16 = hash_byte(hash_byte(hash_in, value[7:0]), value[15:8]);
    endfunction
    function automatic [63:0] hash_stereo(
        input [63:0] hash_in,
        input [15:0] left_value, input [15:0] right_value
    );
        hash_stereo = hash_u16(hash_u16(hash_in, left_value), right_value);
    endfunction

    task automatic fail(input [8*64-1:0] message);
        begin
            failures = failures + 1;
            $display("HW0_FAIL run=%0d cycle=%0d reason=%0s",
                     run_id, system_cycle, message);
        end
    endtask

    always #5 clk = ~clk;

    always @(posedge clk) begin : monitor
        logic public_rise;
        logic internal_rise;
        integer p;
        system_cycle = system_cycle + 1;
        #1;
        public_rise = audio_sample && !previous_public;
        internal_rise = internal_sample && !previous_internal;

        if (!debug_core_ready) begin
            if ($isunknown(audio_l) || $isunknown(audio_r) ||
                $isunknown(audio_sample)) pre_ready_x = pre_ready_x + 1;
            else if (audio_l != 0 || audio_r != 0 || audio_sample != 0)
                pre_ready_nonzero = pre_ready_nonzero + 1;
        end
        if (debug_phase == 4 &&
            (dut.u_jt10.u_core.gen_adpcm.u_acc.u_left.overflow ||
             dut.u_jt10.u_core.gen_adpcm.u_acc.u_right.overflow))
            a6_overflow_events = a6_overflow_events + 1;
        if ((debug_phase == 1 || debug_phase == 2) &&
            (debug_adpcma_request === 1'b1 ||
             debug_adpcmb_request === 1'b1))
            unexpected_adpcm_requests = unexpected_adpcm_requests + 1;

        if (!reset && debug_core_ready) begin
            if ($isunknown(audio_l) || $isunknown(audio_r) ||
                $isunknown(audio_sample)) begin
                if (x_audio == 0)
                    $display("HW0_FIRST_X_AUDIO cycle=%0d l=%h r=%h sample=%b bits=%0d/%0d/%0d",
                        system_cycle,audio_l,audio_r,audio_sample,
                        $isunknown(audio_l),$isunknown(audio_r),
                        $isunknown(audio_sample));
                x_audio=x_audio+1;
            end
            if ($isunknown(debug_phase) || $isunknown(debug_busy_timeout) ||
                $isunknown(debug_write_while_busy)) begin
                x_control=x_control+1;
            end
            if ($isunknown(debug_psg_a) || $isunknown(debug_psg_b) ||
                $isunknown(debug_psg_c) || $isunknown(debug_psg_snd)) begin
                if (x_psg == 0)
                    $display("HW0_FIRST_X_PSG cycle=%0d a=%h b=%h c=%h snd=%h bits=%0d/%0d/%0d/%0d",
                        system_cycle,debug_psg_a,debug_psg_b,debug_psg_c,
                        debug_psg_snd,$isunknown(debug_psg_a),
                        $isunknown(debug_psg_b),$isunknown(debug_psg_c),
                        $isunknown(debug_psg_snd));
                x_psg=x_psg+1;
            end
            if (debug_adpcma_request &&
                ($isunknown(debug_adpcma_addr) ||
                 $isunknown(debug_adpcma_bank) ||
                 $isunknown(dut.adpcma_data))) x_rom_a=x_rom_a+1;
            if (debug_adpcmb_request &&
                ($isunknown(debug_adpcmb_addr) ||
                 $isunknown(dut.adpcmb_data))) x_rom_b=x_rom_b+1;
            x_count = x_audio + x_control + x_psg + x_rom_a + x_rom_b;
            if (internal_rise) internal_samples = internal_samples + 1;
            if (internal_rise && !audio_sample) drops = drops + 1;
            if (public_rise) begin
                public_samples = public_samples + 1;
                if (!internal_rise) duplicates = duplicates + 1;
                if (last_public_cycle >= 0 &&
                    system_cycle - last_public_cycle != 144)
                    cadence_errors = cadence_errors + 1;
                last_public_cycle = system_cycle;
            end
            if (audio_sample) public_width = public_width + 1;
            else if (previous_public) begin
                if (public_width != 6) width_errors = width_errors + 1;
                public_width = 0;
            end
        end

        if (!reset && debug_phase != 0 &&
            debug_phase != last_audible_phase) begin
            if (debug_phase != phase_order_index + 1)
                fail("PHASE_ORDER");
            phase_order_index = debug_phase;
            last_audible_phase = debug_phase;
            $display("HW0_PHASE run=%0d phase=%0d cycle=%0d writes=%0d",
                     run_id, debug_phase, system_cycle,
                     debug_accepted_writes);
        end

        if (public_rise) begin
            if (debug_phase == 2) begin
                if (debug_psg_a != 0) psg_a_nonzero = psg_a_nonzero + 1;
                if (debug_psg_b != 0 || debug_psg_c != 0)
                    psg_bc_spurious = psg_bc_spurious + 1;
            end
            if (phase_order_index == 0 && debug_phase == 0 &&
                dut.u_sequencer.high_state == 6'd1 &&
                !dut.u_sequencer.program_active) begin
                if (audio_l != 0 || audio_r != 0) fail("COLD_NONZERO");
                cold_zero_samples = cold_zero_samples + 1;
            end
            if (phase_order_index == 7 && debug_phase == 0 &&
                dut.u_sequencer.high_state == 6'd46) begin
                if (audio_l != 0 || audio_r != 0) fail("FINAL_NONZERO");
                final_zero_samples = final_zero_samples + 1;
            end

            p = debug_measurement_phase;
            if (debug_measurement_active && p >= 1 && p <= 5 &&
                phase_hash_count[p] < (p == 4 ? 8192 :
                                       p == 5 ? 4097 : 4096)) begin
                // Phase 4A's 4096-sample post-START goal includes one active
                // boundary sample already seen by its monitor, hence 4097
                // active-lane samples in the published hash.
                if (p != 5 || b_chon) begin
                    phase_hash[p] = hash_stereo(phase_hash[p],
                                                audio_l, audio_r);
                    phase_hash_count[p] = phase_hash_count[p] + 1;
                end
            end

            if (debug_phase == 6 && b_chon) begin
                if (b_pan == 2'b10) begin
                    if (audio_r != 0) pan_leak = pan_leak + 1;
                    if (audio_l != 0) left_nonzero = left_nonzero + 1;
                end else if (b_pan == 2'b01) begin
                    if (audio_l != 0) pan_leak = pan_leak + 1;
                    if (audio_r != 0) right_nonzero = right_nonzero + 1;
                end
            end
            if (natural_run >= 0 && natural_run <= 1 && b_chon) begin
                natural_hash[natural_run] = hash_stereo(
                    natural_hash[natural_run], audio_l, audio_r);
                if (prefix_count[natural_run] < 16) begin
                    if (natural_run == 0) begin
                        first_prefix_l[prefix_count[0]] = audio_l;
                        first_prefix_r[prefix_count[0]] = audio_r;
                    end else if (audio_l !==
                                 first_prefix_l[prefix_count[1]] ||
                                 audio_r !==
                                 first_prefix_r[prefix_count[1]]) begin
                        stale_prefix = stale_prefix + 1;
                    end
                    prefix_count[natural_run] =
                        prefix_count[natural_run] + 1;
                end
            end
            if (natural_run >= 0 && natural_run <= 1 &&
                !b_chon && debug_adpcmb_eos &&
                natural_zero_latency[natural_run] < 0) begin
                if (audio_l == 0 && audio_r == 0)
                    natural_zero_latency[natural_run] = zero_wait_samples;
                else zero_wait_samples = zero_wait_samples + 1;
            end
            if (phase5_stop_seen && phase5_zero_latency < 0) begin
                if (audio_l == 0 && audio_r == 0)
                    phase5_zero_latency = phase5_zero_wait;
                else phase5_zero_wait = phase5_zero_wait + 1;
            end
        end

        if (debug_phase == 5 && !b_chon && previous_b_active) begin
            phase5_stop_seen = 1'b1;
            phase5_zero_wait = 0;
            phase5_zero_latency = -1;
        end
        if (phase5_stop_seen && debug_phase == 0 &&
            dut.u_sequencer.high_state == 6'd28 &&
            debug_adpcmb_request === 1'b1)
            phase5_request_after_stop = phase5_request_after_stop + 1;

        if (debug_phase == 7 && b_chon && !previous_b_active) begin
            natural_run = natural_run + 1;
            if (natural_run > 1) fail("NATURAL_EXTRA_START");
            $display("HW0_NATURAL_START run=%0d playback=%0d address=%06h",
                     run_id, natural_run, debug_adpcmb_addr);
        end
        if (debug_phase == 7 && !b_chon && previous_b_active &&
            natural_run >= 0 && natural_run <= 1) begin
            zero_wait_samples = 0;
            natural_zero_latency[natural_run] = -1;
        end
        if (debug_phase == 7 && b_logical && natural_run >= 0 &&
            natural_run <= 1)
            natural_logical[natural_run] = natural_logical[natural_run] + 1;

        previous_public = audio_sample;
        previous_internal = internal_sample;
        previous_measurement = debug_measurement_active;
        previous_b_active = b_chon;
        previous_b_eos = debug_adpcmb_eos;
    end

    ym2610_hw0_top #(
        .FAST_SIM(1'b1),
`ifdef HW0_TUNE
        .BOOT_SAMPLES(1024)
`else
        .BOOT_SAMPLES(32768)
`endif
    ) dut (
        .clk_sys(clk), .reset(reset),
        .audio_l(audio_l), .audio_r(audio_r), .audio_sample(audio_sample),
        .video_ce(video_ce), .video_hs(video_hs), .video_vs(video_vs),
        .video_de(video_de), .video_r(video_r), .video_g(video_g),
        .video_b(video_b), .debug_phase(debug_phase),
        .debug_microcode_index(debug_microcode_index),
        .debug_accepted_writes(debug_accepted_writes),
        .debug_busy_timeout(debug_busy_timeout),
        .debug_write_while_busy(debug_write_while_busy),
        .debug_restart_count(debug_restart_count),
        .debug_measurement_active(debug_measurement_active),
        .debug_measurement_phase(debug_measurement_phase),
        .debug_adpcma_request(debug_adpcma_request),
        .debug_adpcmb_request(debug_adpcmb_request),
        .debug_adpcma_eos(debug_adpcma_eos),
        .debug_adpcmb_eos(debug_adpcmb_eos),
        .debug_adpcmb_active(debug_adpcmb_active),
        .debug_adpcma_addr(debug_adpcma_addr),
        .debug_adpcma_bank(debug_adpcma_bank),
        .debug_adpcmb_addr(debug_adpcmb_addr),
        .debug_psg_a(debug_psg_a), .debug_psg_b(debug_psg_b),
        .debug_psg_c(debug_psg_c), .debug_psg_snd(debug_psg_snd),
        .debug_core_ready(debug_core_ready),
        .debug_reset_cen_count(debug_reset_cen_count),
        .debug_halted(debug_halted)
    );

    initial begin
        integer i;
        if (!$value$plusargs("RUN_ID=%d", run_id)) run_id = 1;
        for (i = 1; i <= 5; i = i + 1) begin
            phase_hash[i] = FNV_OFFSET;
            phase_hash_count[i] = 0;
        end
        for (i = 0; i < 2; i = i + 1) begin
            natural_hash[i] = FNV_OFFSET;
            natural_logical[i] = 0;
            natural_zero_latency[i] = -1;
            prefix_count[i] = 0;
        end

        repeat (4) @(posedge clk);
        repeat (64) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        fork
            begin
                wait (debug_restart_count >= 1);
            end
            begin
                repeat (22000000) @(posedge clk);
                fail("FULL_LOOP_TIMEOUT");
            end
        join_any
        disable fork;
        repeat (32) @(posedge clk);

        if (debug_halted || debug_busy_timeout ||
            debug_write_while_busy) fail("SEQUENCER_ERROR");
        if (debug_reset_cen_count != 6) fail("RESET_CEN_COUNT");
        if (phase_order_index != 7) fail("PHASES_INCOMPLETE");
`ifndef HW0_TUNE
        if (cold_zero_samples < 32768) fail("COLD_SILENCE_SHORT");
        if (final_zero_samples < 32768) fail("FINAL_SILENCE_SHORT");
`endif
        if (cadence_errors != 0 || width_errors != 0 ||
            drops != 0 || duplicates != 0) fail("SAMPLE_CONTRACT");
        if (pre_ready_x != 0 || pre_ready_nonzero != 0)
            fail("PRE_READY_AUDIO");
        if (x_count != 0) fail("PUBLIC_X");
        if (phase_hash_count[1] != 4096 ||
            phase_hash[1] != 64'h8aadd7a6819038e5) fail("FM_HASH");
        if (phase_hash_count[2] != 4096 ||
            phase_hash[2] != 64'h54730095b12b6325) fail("SSG_HASH");
        if (phase_hash_count[3] != 4096 ||
            phase_hash[3] != 64'hadf8cc2f2f81c1b9) fail("ADPCMA0_HASH");
        if (phase_hash_count[4] != 8192 ||
            phase_hash[4] != 64'h32cb891931682fe9) fail("ADPCMA6_HASH");
        if (a6_overflow_events != 0) fail("ADPCMA6_OVERFLOW");
        if (phase_hash_count[5] != 4097 ||
            phase_hash[5] != 64'h1207d84363d4ed39) fail("ADPCMB_HASH");
        if (!phase5_stop_seen || phase5_zero_latency < 0 ||
            phase5_zero_latency > 3 || phase5_request_after_stop != 0)
            fail("ADPCMB_RESET_STOP");
        if (pan_leak != 0 || left_nonzero == 0 || right_nonzero == 0)
            fail("PAN_ISOLATION");
        if (psg_a_nonzero == 0 || psg_bc_spurious != 0)
            fail("SSG_ISOLATION");
        if (unexpected_adpcm_requests != 0)
            fail("ADPCM_IDLE_FETCH");
        if (natural_logical[0] != 512 || natural_logical[1] != 512)
            fail("NATURAL_LOGICAL_COUNT");
        if (natural_zero_latency[0] < 0 || natural_zero_latency[0] > 4 ||
            natural_zero_latency[1] < 0 || natural_zero_latency[1] > 4)
            fail("NATURAL_ZERO_LATENCY");
        if (natural_hash[0] != natural_hash[1] || stale_prefix != 0)
            fail("NATURAL_RESTART");

        $display("HW0_HASH run=%0d fm=%016h ssg=%016h a0=%016h a6=%016h b=%016h counts=%0d/%0d/%0d/%0d/%0d",
            run_id, phase_hash[1], phase_hash[2], phase_hash[3],
            phase_hash[4], phase_hash[5], phase_hash_count[1],
            phase_hash_count[2], phase_hash_count[3],
            phase_hash_count[4], phase_hash_count[5]);
        $display("HW0_CONTRACT run=%0d writes=%0d timeout=%0d busy_write=%0d cadence_errors=%0d width_errors=%0d drops=%0d duplicates=%0d x=%0d cold=%0d final=%0d b_reset_zero=%0d b_post_request=%0d pan_leak=%0d pan_nonzero=%0d/%0d natural=%0d/%0d zero=%0d/%0d restart_hash=%016h/%016h stale=%0d loops=%0d",
            run_id, debug_accepted_writes, debug_busy_timeout,
            debug_write_while_busy, cadence_errors, width_errors, drops,
            duplicates, x_count, cold_zero_samples, final_zero_samples,
            phase5_zero_latency, phase5_request_after_stop,
            pan_leak, left_nonzero, right_nonzero,
            natural_logical[0], natural_logical[1],
            natural_zero_latency[0], natural_zero_latency[1],
            natural_hash[0], natural_hash[1], stale_prefix,
            debug_restart_count);
        $display("HW0_X run=%0d pre_ready=%0d/%0d audio=%0d control=%0d psg=%0d rom_a=%0d rom_b=%0d ssg_bc=%0d adpcm_idle=%0d a6_overflow=%0d",
            run_id,pre_ready_x,pre_ready_nonzero,x_audio,x_control,x_psg,
            x_rom_a,x_rom_b,psg_bc_spurious,unexpected_adpcm_requests,
            a6_overflow_events);
        if (failures != 0) $fatal(1, "HW0 failed (%0d)", failures);
        $display("HW0_PASS run=%0d", run_id);
        $finish;
    end
endmodule
