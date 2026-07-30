`timescale 1ns/1ps

module tb_jt10_phase0d_warmup;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cen = 1'b0;
    logic session_start = 1'b1;
    logic [7:0] din = 8'h00;
    logic [1:0] addr = 2'b00;
    logic cs_n = 1'b1;
    logic wr_n = 1'b1;
    logic [7:0] adpcma_data = 8'ha5;
    logic [7:0] adpcmb_data = 8'h5a;
    logic loop_event = 1'b0;

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
    wire [2:0] reset_cen_count_observed;
    wire reset_cen_valid;

    wire diag_decoder_active =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.decon;
    wire diag_cen6 = dut.u_jt10.u_jt12.clk_en_666;
    wire diag_acc_left_en =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_acc_left.en_sum;
    wire diag_acc_right_en =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_acc_right.en_sum;
    wire [3:0] diag_captured_nibble =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.data;
    wire signed [15:0] diag_pcmdec =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.pcmdec;
    wire signed [15:0] diag_pcmatt =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.pcm_att;
    wire signed [15:0] diag_pre_pcm_l =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.pre_pcm55_l;
    wire signed [15:0] diag_pre_pcm_r =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.pre_pcm55_r;

    integer requested_reset_cen = 64;
    integer expect_valid = 1;
    integer expect_startup_x = 0;
    integer scenario = 0;
    integer rearm_mode = 0;
    integer system_cycle = 0;
    integer post_reset_cycle = 0;
    integer session_number = 0;
    integer session_internal_pulses = 0;
    integer session_public_pulses = 0;
    integer total_internal_pulses = 0;
    integer total_public_pulses = 0;
    integer suppressed_internal_x_pulses = 0;
    integer suppressed_public_nonzero_cycles = 0;
    integer public_x_cycles = 0;
    integer public_sample_x = 0;
    integer public_left_x = 0;
    integer public_right_x = 0;
    integer sample_drop_count = 0;
    integer sample_duplicate_count = 0;
    integer sample_mismatch_count = 0;
    integer cadence_error_count = 0;
    integer public_width_error_count = 0;
    integer last_public_rise_cycle = -1;
    integer public_width = 0;
    integer session_ready_cycle = -1;
    integer session_first_public_cycle = -1;
    integer phase_samples = 0;
    integer legal_fetches = 0;
    integer legal_fetch_x = 0;
    integer legal_fetch_addr_x = 0;
    integer legal_fetch_bank_x = 0;
    integer legal_rom_data_x = 0;
    integer legal_capture_x = 0;
    integer legal_pcmdec_x = 0;
    integer legal_pcmatt_x = 0;
    integer legal_decode_x = 0;
    integer legal_accumulator_left_x = 0;
    integer legal_accumulator_right_x = 0;
    integer legal_accumulator_x = 0;
    integer failures = 0;
    logic previous_internal_sample = 1'b0;
    logic previous_public_sample = 1'b0;
    logic previous_warmup_ready = 1'b0;
    logic hash_enabled = 1'b0;
    logic legal_active = 1'b0;
    logic [63:0] internal_hash10 = 64'hcbf29ce484222325;
    logic [63:0] public_hash10 = 64'hcbf29ce484222325;
    logic [63:0] internal_hash100 = 64'hcbf29ce484222325;
    logic [63:0] public_hash100 = 64'hcbf29ce484222325;

    function automatic [63:0] hash_sample(
        input [63:0] hash_in,
        input [31:0] sample_in
    );
        integer index;
        reg [63:0] hash_work;
        begin
            hash_work = hash_in;
            for (index = 0; index < 4; index = index + 1) begin
                hash_work =
                    (hash_work ^ sample_in[index*8 +: 8]) *
                    64'h00000100000001b3;
            end
            hash_sample = hash_work;
        end
    endfunction

    always #5 clk = ~clk;

    always @(posedge clk) begin : monitor
        logic fetch_was_valid;
        logic fetch_addr_was_unknown;
        logic fetch_bank_was_unknown;
        logic rom_data_was_unknown;
        logic decode_was_enabled;
        logic acc_was_enabled;
        logic internal_rise;
        logic public_rise;
        logic reset_was_active;
        logic session_was_active;
        reset_was_active = rst;
        session_was_active = session_start;
        fetch_was_valid =
            adpcma_roe_n === 1'b0 && diag_decoder_active === 1'b1;
        fetch_addr_was_unknown = $isunknown(adpcma_addr);
        fetch_bank_was_unknown = $isunknown(adpcma_bank);
        rom_data_was_unknown = $isunknown(adpcma_data);
        decode_was_enabled =
            diag_cen6 === 1'b1 && diag_decoder_active === 1'b1;
        acc_was_enabled =
            diag_acc_left_en === 1'b1 || diag_acc_right_en === 1'b1;

        system_cycle = system_cycle + 1;
        if (!rst)
            post_reset_cycle = post_reset_cycle + 1;
        #1;

        if (reset_was_active || session_was_active) begin
            previous_internal_sample = 1'b0;
            previous_public_sample = 1'b0;
            previous_warmup_ready = 1'b0;
            session_internal_pulses = 0;
            session_public_pulses = 0;
            session_ready_cycle = -1;
            session_first_public_cycle = -1;
            public_width = 0;
            last_public_rise_cycle = -1;
        end else begin
            if ($isunknown(snd_sample))
                public_sample_x = public_sample_x + 1;
            if (snd_sample === 1'b1 && $isunknown(snd_left))
                public_left_x = public_left_x + 1;
            if (snd_sample === 1'b1 && $isunknown(snd_right))
                public_right_x = public_right_x + 1;

            internal_rise =
                internal_snd_sample === 1'b1 &&
                previous_internal_sample !== 1'b1;
            public_rise =
                snd_sample === 1'b1 &&
                previous_public_sample !== 1'b1;

            if (warmup_ready === 1'b1 &&
                previous_warmup_ready !== 1'b1) begin
                session_ready_cycle = system_cycle;
                $display(
                    "READY_EDGE session=%0d system_cycle=%0d post_reset_cycle=%0d internal_pulses=%0d count=%0d",
                    session_number, system_cycle, post_reset_cycle,
                    session_internal_pulses, warmup_count
                );
            end

            if (!warmup_ready) begin
                if (snd_sample !== 1'b0 ||
                    snd_left !== 16'sd0 || snd_right !== 16'sd0) begin
                    suppressed_public_nonzero_cycles =
                        suppressed_public_nonzero_cycles + 1;
                    if (suppressed_public_nonzero_cycles <= 8)
                        $display(
                            "FAIL WARMUP_LEAK cycle=%0d sample=%b left=%h right=%h",
                            post_reset_cycle, snd_sample, snd_left, snd_right
                        );
                end
            end

            if (internal_rise) begin
                session_internal_pulses = session_internal_pulses + 1;
                total_internal_pulses = total_internal_pulses + 1;

                if (!warmup_ready &&
                    ($isunknown(internal_snd_left) ||
                     $isunknown(internal_snd_right)))
                    suppressed_internal_x_pulses =
                        suppressed_internal_x_pulses + 1;

                if (session_internal_pulses <= 6)
                    $display(
                        "WARMUP_TRACE session=%0d reset_cen=%0d system_cycle=%0d post_reset_cycle=%0d internal_n=%0d public_n=%0d count=%0d ready=%0d internal_sample=%b public_sample=%b internal_l=%h internal_r=%h public_l=%h public_r=%h internal_x=%0d",
                        session_number, requested_reset_cen,
                        system_cycle, post_reset_cycle,
                        session_internal_pulses,
                        session_public_pulses +
                            (snd_sample === 1'b1 ? 1 : 0),
                        warmup_count,
                        warmup_ready, internal_snd_sample, snd_sample,
                        internal_snd_left, internal_snd_right,
                        snd_left, snd_right,
                        $isunknown(internal_snd_left) ||
                        $isunknown(internal_snd_right)
                    );

                if (expect_startup_x != 0 && session_number == 0 &&
                    (session_internal_pulses == 3 ||
                     session_internal_pulses == 5)) begin
                    if (!$isunknown(internal_snd_left) ||
                        !$isunknown(internal_snd_right) ||
                        (session_internal_pulses == 3 &&
                         system_cycle != 367) ||
                        (session_internal_pulses == 5 &&
                         system_cycle != 655)) begin
                        failures = failures + 1;
                        $display(
                            "FAIL startup-X landmark pulse=%0d system_cycle=%0d",
                            session_internal_pulses, system_cycle
                        );
                    end
                end

                if (expect_valid != 0) begin
                    if (session_internal_pulses <= 5) begin
                        if (warmup_ready !== 1'b0 ||
                            snd_sample !== 1'b0 ||
                            snd_left !== 16'sd0 ||
                            snd_right !== 16'sd0) begin
                            failures = failures + 1;
                            $display(
                                "FAIL first five were not suppressed pulse=%0d",
                                session_internal_pulses
                            );
                        end
                    end else if (session_internal_pulses == 6) begin
                        if (warmup_ready !== 1'b1 ||
                            snd_sample !== 1'b1) begin
                            failures = failures + 1;
                            $display("FAIL sixth pulse did not open gate");
                        end
                    end
                end

                if (warmup_ready) begin
                    if (snd_sample !== 1'b1) begin
                        sample_drop_count = sample_drop_count + 1;
                        $display(
                            "FAIL SAMPLE_DROP cycle=%0d internal_n=%0d",
                            post_reset_cycle, session_internal_pulses
                        );
                    end
                    if ($isunknown(internal_snd_left) ||
                        $isunknown(internal_snd_right) ||
                        $isunknown(snd_left) || $isunknown(snd_right)) begin
                        public_x_cycles = public_x_cycles + 1;
                        $display(
                            "FAIL READY_X cycle=%0d internal=%h/%h public=%h/%h",
                            post_reset_cycle, internal_snd_left,
                            internal_snd_right, snd_left, snd_right
                        );
                    end else if (snd_left !== internal_snd_left ||
                                 snd_right !== internal_snd_right) begin
                        sample_mismatch_count = sample_mismatch_count + 1;
                        $display(
                            "FAIL SAMPLE_MISMATCH cycle=%0d internal=%h/%h public=%h/%h",
                            post_reset_cycle, internal_snd_left,
                            internal_snd_right, snd_left, snd_right
                        );
                    end
                end
            end

            if (public_rise) begin
                session_public_pulses = session_public_pulses + 1;
                total_public_pulses = total_public_pulses + 1;
                if (session_public_pulses == 1) begin
                    session_first_public_cycle = system_cycle;
                    $display(
                        "PUBLIC_START session=%0d system_cycle=%0d post_reset_cycle=%0d internal_n=%0d ready_cycle=%0d",
                        session_number, system_cycle, post_reset_cycle,
                        session_internal_pulses, session_ready_cycle
                    );
                end
                if (!internal_rise) begin
                    sample_duplicate_count = sample_duplicate_count + 1;
                    $display("FAIL SAMPLE_DUPLICATE cycle=%0d",
                             post_reset_cycle);
                end
                if (session_public_pulses == 1 &&
                    session_internal_pulses != 6) begin
                    failures = failures + 1;
                    $display(
                        "FAIL first public pulse internal_n=%0d expected=6",
                        session_internal_pulses
                    );
                end
                if (last_public_rise_cycle >= 0 &&
                    post_reset_cycle - last_public_rise_cycle != 144) begin
                    cadence_error_count = cadence_error_count + 1;
                    $display(
                        "FAIL CADENCE previous=%0d current=%0d interval=%0d",
                        last_public_rise_cycle, post_reset_cycle,
                        post_reset_cycle - last_public_rise_cycle
                    );
                end
                last_public_rise_cycle = post_reset_cycle;
            end

            if (snd_sample === 1'b1) begin
                if ($isunknown(snd_left) || $isunknown(snd_right) ||
                    $isunknown(snd_sample))
                    public_x_cycles = public_x_cycles + 1;
                if (previous_public_sample === 1'b1)
                    public_width = public_width + 1;
                else
                    public_width = 1;
            end else if (previous_public_sample === 1'b1) begin
                if (public_width != 6) begin
                    public_width_error_count =
                        public_width_error_count + 1;
                    $display("FAIL PULSE_WIDTH width=%0d", public_width);
                end
                public_width = 0;
            end

            if (hash_enabled && internal_rise && warmup_ready) begin
                if (phase_samples < 10) begin
                    internal_hash10 =
                        hash_sample(internal_hash10,
                                    {internal_snd_left, internal_snd_right});
                    public_hash10 =
                        hash_sample(public_hash10, {snd_left, snd_right});
                end
                if (phase_samples < 100) begin
                    internal_hash100 =
                        hash_sample(internal_hash100,
                                    {internal_snd_left, internal_snd_right});
                    public_hash100 =
                        hash_sample(public_hash100, {snd_left, snd_right});
                end
                phase_samples = phase_samples + 1;
            end

            previous_internal_sample = internal_snd_sample;
            previous_public_sample = snd_sample;
            previous_warmup_ready = warmup_ready;
        end

        if (legal_active) begin
            if (fetch_was_valid) begin
                legal_fetches = legal_fetches + 1;
                if (fetch_addr_was_unknown) begin
                    legal_fetch_addr_x = legal_fetch_addr_x + 1;
                    legal_fetch_x = legal_fetch_x + 1;
                end
                if (fetch_bank_was_unknown) begin
                    legal_fetch_bank_x = legal_fetch_bank_x + 1;
                    legal_fetch_x = legal_fetch_x + 1;
                end
                if (rom_data_was_unknown) begin
                    legal_rom_data_x = legal_rom_data_x + 1;
                    legal_fetch_x = legal_fetch_x + 1;
                end
                if ($isunknown(diag_captured_nibble))
                    legal_capture_x = legal_capture_x + 1;
            end
            if (decode_was_enabled) begin
                if ($isunknown(diag_pcmdec)) begin
                    legal_pcmdec_x = legal_pcmdec_x + 1;
                    legal_decode_x = legal_decode_x + 1;
                end
                if ($isunknown(diag_pcmatt)) begin
                    legal_pcmatt_x = legal_pcmatt_x + 1;
                    legal_decode_x = legal_decode_x + 1;
                end
            end
            if (acc_was_enabled) begin
                if ($isunknown(diag_pre_pcm_l)) begin
                    legal_accumulator_left_x =
                        legal_accumulator_left_x + 1;
                    legal_accumulator_x = legal_accumulator_x + 1;
                end
                if ($isunknown(diag_pre_pcm_r)) begin
                    legal_accumulator_right_x =
                        legal_accumulator_right_x + 1;
                    legal_accumulator_x = legal_accumulator_x + 1;
                end
            end
        end
    end

    task automatic wait_clocks(input integer count);
        repeat (count) @(posedge clk);
    endtask

    task automatic account_reset_release_level;
        begin
            #1;
            if (internal_snd_sample === 1'b1) begin
                session_internal_pulses = 1;
                total_internal_pulses = total_internal_pulses + 1;
                previous_internal_sample = 1'b1;
                if ($isunknown(internal_snd_left) ||
                    $isunknown(internal_snd_right))
                    suppressed_internal_x_pulses =
                        suppressed_internal_x_pulses + 1;
                $display(
                    "WARMUP_TRACE session=%0d reset_cen=%0d system_cycle=%0d post_reset_cycle=0 internal_n=1 public_n=0 count=%0d ready=%0d internal_sample=%b public_sample=%b internal_l=%h internal_r=%h public_l=%h public_r=%h internal_x=%0d reset_release_level=1",
                    session_number, requested_reset_cen, system_cycle,
                    warmup_count, warmup_ready, internal_snd_sample,
                    snd_sample, internal_snd_left, internal_snd_right,
                    snd_left, snd_right,
                    $isunknown(internal_snd_left) ||
                    $isunknown(internal_snd_right)
                );
            end
        end
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
                $display("FAIL BUSY timeout reg=%02x data=%02x",
                         reg_addr, reg_data);
            end
        end
    endtask

    task automatic start_hash_phase(input integer phase_id);
        begin
            @(negedge clk);
            phase_samples = 0;
            internal_hash10 = 64'hcbf29ce484222325;
            public_hash10 = 64'hcbf29ce484222325;
            internal_hash100 = 64'hcbf29ce484222325;
            public_hash100 = 64'hcbf29ce484222325;
            hash_enabled = 1'b1;
            $display("HASH_BEGIN phase=%0d session=%0d",
                     phase_id, session_number);
        end
    endtask

    task automatic finish_hash_phase(
        input integer phase_id,
        input integer target_samples
    );
        integer guard;
        begin
            guard = 0;
            while (phase_samples < target_samples && guard < 40000) begin
                @(posedge clk);
                #2;
                guard = guard + 1;
            end
            @(negedge clk);
            hash_enabled = 1'b0;
            $display(
                "HASH_RESULT phase=%0d samples=%0d internal10=%016h public10=%016h internal100=%016h public100=%016h",
                phase_id, phase_samples, internal_hash10, public_hash10,
                internal_hash100, public_hash100
            );
            if (guard >= 40000 || phase_samples < target_samples) begin
                failures = failures + 1;
                $display("FAIL hash sample timeout phase=%0d samples=%0d",
                         phase_id, phase_samples);
            end
            if (target_samples >= 10 &&
                internal_hash10 !== public_hash10) begin
                failures = failures + 1;
                $display("FAIL 10-sample hash mismatch phase=%0d",
                         phase_id);
            end
            if (target_samples >= 100 &&
                internal_hash100 !== public_hash100) begin
                failures = failures + 1;
                $display("FAIL 100-sample hash mismatch phase=%0d",
                         phase_id);
            end
        end
    endtask

    task automatic run_legal_adpcm(input integer phase_id);
        integer guard;
        begin
            // Official adpcma.jtt-derived channel-0 sequence.
            write_reg(1'b1, 8'h00, 8'hbf);
            write_reg(1'b1, 8'h10, 8'h00);
            write_reg(1'b1, 8'h18, 8'h00);
            write_reg(1'b1, 8'h20, 8'h0f);
            write_reg(1'b1, 8'h28, 8'h00);
            write_reg(1'b1, 8'h01, 8'h3f);
            write_reg(1'b1, 8'h08, 8'hf5);
            wait_clocks(512);

            legal_fetches = 0;
            legal_fetch_x = 0;
            legal_fetch_addr_x = 0;
            legal_fetch_bank_x = 0;
            legal_rom_data_x = 0;
            legal_capture_x = 0;
            legal_pcmdec_x = 0;
            legal_pcmatt_x = 0;
            legal_decode_x = 0;
            legal_accumulator_left_x = 0;
            legal_accumulator_right_x = 0;
            legal_accumulator_x = 0;
            legal_active = 1'b1;
            write_reg(1'b1, 8'h00, 8'h01);

            guard = 0;
            while (legal_fetches == 0 && guard < 4096) begin
                @(posedge clk);
                #2;
                guard = guard + 1;
            end
            if (legal_fetches == 0) begin
                failures = failures + 1;
                $display("FAIL legal ADPCM-A fetch timeout");
            end

            start_hash_phase(phase_id);
            finish_hash_phase(phase_id, 100);
            legal_active = 1'b0;
            $display(
                "LEGAL_RESULT phase=%0d fetches=%0d fetch_addr_x=%0d fetch_bank_x=%0d rom_data_x=%0d capture_x=%0d pcmdec_x=%0d pcmatt_x=%0d accumulator_left_x=%0d accumulator_right_x=%0d",
                phase_id, legal_fetches, legal_fetch_addr_x,
                legal_fetch_bank_x, legal_rom_data_x,
                legal_capture_x, legal_pcmdec_x, legal_pcmatt_x,
                legal_accumulator_left_x,
                legal_accumulator_right_x
            );
            if (legal_fetch_x != 0 || legal_capture_x != 0 ||
                legal_decode_x != 0 || legal_accumulator_x != 0) begin
                failures = failures + 1;
                $display("FAIL legal ADPCM-A individual X contract");
            end
        end
    endtask

    task automatic test_loop_no_rearm;
        integer ready_before;
        integer count_before;
        integer public_before;
        integer guard;
        begin
            while (internal_snd_sample !== 1'b0)
                @(posedge clk);
            ready_before = warmup_ready;
            count_before = warmup_count;
            public_before = total_public_pulses;
            @(negedge clk);
            loop_event = 1'b1;
            @(posedge clk);
            #2;
            if (warmup_ready !== 1'b1 ||
                warmup_count !== count_before[2:0]) begin
                failures = failures + 1;
                $display("FAIL loop event changed warm-up state");
            end
            @(negedge clk);
            loop_event = 1'b0;
            guard = 0;
            while (total_public_pulses < public_before + 10 &&
                   guard < 4000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            $display(
                "LOOP_RESULT event_pulsed=1 ready_before=%0d ready_after=%0d count_before=%0d count_after=%0d samples_after=%0d",
                ready_before, warmup_ready,
                count_before, warmup_count,
                total_public_pulses - public_before
            );
            if (guard >= 4000 || warmup_ready !== ready_before[0] ||
                warmup_count !== count_before[2:0]) begin
                failures = failures + 1;
                $display("FAIL loop/wait/stall/refill rearmed gate");
            end
        end
    endtask

    task automatic rearm_session(input integer phase_id);
        begin
            while (internal_snd_sample !== 1'b0)
                @(posedge clk);
            @(negedge clk);
            hash_enabled = 1'b0;
            session_start = 1'b1;
            session_number = session_number + 1;
            @(posedge clk);
            #2;
            if (warmup_ready !== 1'b0 || snd_sample !== 1'b0 ||
                snd_left !== 16'sd0 || snd_right !== 16'sd0) begin
                failures = failures + 1;
                $display("FAIL session restart did not rearm/mute");
            end
            @(negedge clk);
            session_start = 1'b0;
            start_hash_phase(phase_id);
            finish_hash_phase(phase_id, 100);
            $display("REARM_RESULT kind=session session=%0d ready=%0d",
                     session_number, warmup_ready);
        end
    endtask

    task automatic rearm_functional_reset(
        input integer phase_id,
        input integer reset_cens
    );
        begin
            while (internal_snd_sample !== 1'b0)
                @(posedge clk);
            @(negedge clk);
            hash_enabled = 1'b0;
            rst = 1'b1;
            cen = 1'b0;
            session_number = session_number + 1;
            wait_clocks(4);
            @(negedge clk);
            cen = 1'b1;
            wait_clocks(reset_cens);
            @(negedge clk);
            cen = 1'b0;
            #1;
            if (reset_cen_count_observed !== 3'd6) begin
                failures = failures + 1;
                $display(
                    "FAIL functional reset CEN count=%0d expected=6",
                    reset_cen_count_observed
                );
            end
            rst = 1'b0;
            cen = 1'b1;
            post_reset_cycle = 0;
            account_reset_release_level();
            start_hash_phase(phase_id);
            finish_hash_phase(phase_id, 100);
            $display(
                "REARM_RESULT kind=functional_reset session=%0d ready=%0d",
                session_number, warmup_ready
            );
        end
    endtask

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
        .reset_cen_count(reset_cen_count_observed),
        .reset_cen_valid(reset_cen_valid)
    );

    initial begin
        integer phase_id;
        if (!$value$plusargs("RESET_CEN=%d", requested_reset_cen))
            requested_reset_cen = 64;
        if (!$value$plusargs("EXPECT_VALID=%d", expect_valid))
            expect_valid = requested_reset_cen >= 6;
        if (!$value$plusargs("EXPECT_STARTUP_X=%d", expect_startup_x))
            expect_startup_x = 0;
        if (!$value$plusargs("SCENARIO=%d", scenario))
            scenario = 0;
        if (!$value$plusargs("REARM=%d", rearm_mode))
            rearm_mode = 0;

        $display(
            "PHASE0D_BEGIN reset_cen=%0d expect_valid=%0d scenario=%0d rearm=%0d",
            requested_reset_cen, expect_valid, scenario, rearm_mode
        );

        // Establish a deterministic session while reset CEN is low.
        wait_clocks(4);
        @(negedge clk);
        session_start = 1'b0;
        wait_clocks(12);
        if (requested_reset_cen > 0) begin
            @(negedge clk);
            cen = 1'b1;
            wait_clocks(requested_reset_cen);
            @(negedge clk);
            cen = 1'b0;
        end
        #1;
        $display(
            "RESET_CONTRACT requested=%0d observed=%0d valid=%0d",
            requested_reset_cen, reset_cen_count_observed,
            reset_cen_valid
        );
        if ((requested_reset_cen >= 6) != reset_cen_valid) begin
            failures = failures + 1;
            $display("FAIL reset CEN validity mismatch");
        end

        rst = 1'b0;
        cen = 1'b1;
        post_reset_cycle = 0;
        account_reset_release_level();

        if (expect_valid == 0) begin
            wait_clocks(2500);
            #2;
            $display(
                "INVALID_RESET_RESULT reset_cen=%0d internal_pulses=%0d public_pulses=%0d ready=%0d public_leaks=%0d",
                requested_reset_cen, total_internal_pulses,
                total_public_pulses, warmup_ready,
                suppressed_public_nonzero_cycles
            );
            if (warmup_ready !== 1'b0 ||
                total_public_pulses != 0 ||
                suppressed_public_nonzero_cycles != 0) begin
                failures = failures + 1;
                $display("FAIL invalid reset contract escaped mute");
            end
        end else begin
            phase_id = 10 + scenario;
            start_hash_phase(phase_id);
            finish_hash_phase(phase_id, 100);
            if (post_reset_cycle < 20000)
                wait_clocks(20000 - post_reset_cycle);
            #2;
            $display(
                "READY_STABILITY_RESULT cycles=%0d public_x=%0d drops=%0d duplicates=%0d mismatches=%0d",
                post_reset_cycle, public_x_cycles, sample_drop_count,
                sample_duplicate_count, sample_mismatch_count
            );

            if (expect_startup_x != 0 &&
                suppressed_internal_x_pulses < 2) begin
                failures = failures + 1;
                $display(
                    "FAIL expected startup X pulses were not observed count=%0d",
                    suppressed_internal_x_pulses
                );
            end

            case (scenario)
                0: $display("SCENARIO_RESULT kind=combined_idle");
                1: $display(
                    "SCENARIO_RESULT kind=fm_only_adpcm_legally_keyoff");
                2: run_legal_adpcm(22);
                3: run_legal_adpcm(23);
                default: begin
                    failures = failures + 1;
                    $display("FAIL unknown scenario=%0d", scenario);
                end
            endcase

            if (rearm_mode != 0)
                test_loop_no_rearm();
            if (rearm_mode == 1 || rearm_mode == 3)
                rearm_session(31);
            if (rearm_mode == 2 || rearm_mode == 3)
                rearm_functional_reset(32, 6);
        end

        if (suppressed_public_nonzero_cycles != 0 ||
            public_x_cycles != 0 ||
            public_sample_x != 0 ||
            public_left_x != 0 ||
            public_right_x != 0 ||
            sample_drop_count != 0 ||
            sample_duplicate_count != 0 ||
            sample_mismatch_count != 0 ||
            cadence_error_count != 0 ||
            public_width_error_count != 0) begin
            failures = failures + 1;
            $display("FAIL output audit counters are nonzero");
        end

        $display(
            "PHASE0D_RESULT reset_cen=%0d valid=%0d internal_pulses=%0d public_pulses=%0d hidden_x_pulses=%0d leaks=%0d public_sample_x=%0d public_left_x=%0d public_right_x=%0d drops=%0d duplicates=%0d mismatches=%0d cadence_errors=%0d width_errors=%0d failures=%0d",
            requested_reset_cen, reset_cen_valid,
            total_internal_pulses, total_public_pulses,
            suppressed_internal_x_pulses,
            suppressed_public_nonzero_cycles, public_sample_x,
            public_left_x, public_right_x,
            sample_drop_count, sample_duplicate_count,
            sample_mismatch_count, cadence_error_count,
            public_width_error_count, failures
        );
        if (failures != 0)
            $fatal(1, "JT10 Phase 0D failed (%0d)", failures);
        $display("PHASE0D_PASS");
        $finish;
    end

endmodule
