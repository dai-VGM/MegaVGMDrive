`timescale 1ns/1ps

module tb_jt10_phase0a_diagnostic;
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
    wire [7:0] psg_A;
    wire [7:0] psg_B;
    wire [7:0] psg_C;
    wire signed [15:0] fm_snd;
    wire [9:0] psg_snd;
    wire signed [15:0] snd_right;
    wire signed [15:0] snd_left;
    wire snd_sample;

    integer reset_cen_count = 64;
    integer do_legal = 0;
    integer expect_patch = 0;
    integer system_cycle = 0;
    integer post_reset_cen = 0;
    integer fetch_count = 0;
    integer first_fetch_cycle = -1;
    integer first_capture_cycle = -1;
    integer first_decode_cycle = -1;
    integer first_sample_cycle = -1;
    integer first_addr_x_cycle = -1;
    integer first_bank_x_cycle = -1;
    integer first_strobe_x_cycle = -1;
    integer fetch_x_count = 0;
    integer capture_x_count = 0;
    integer capture_addr_x_count = 0;
    integer capture_data_x_count = 0;
    integer decode_x_count = 0;
    integer accumulator_x_count = 0;
    integer strobe_x_count = 0;
    integer sample_x_count = 0;
    integer public_sample_x_count = 0;
    integer inactive_addr_x_count = 0;
    integer sequence_updates = 0;
    integer sequence_errors = 0;
    integer zero_pulses = 0;
    integer first_zero_cycle = -1;
    integer last_zero_cycle = -1;
    integer zero_interval_updates = -1;
    integer zero_interval_cycles = -1;
    integer last_zero_update = -1;
    integer sample_width_cycles = -1;
    integer pulse_width_counter = 0;
    integer legal_fetch_x_base = 0;
    integer legal_capture_x_base = 0;
    integer legal_capture_addr_x_base = 0;
    integer legal_capture_data_x_base = 0;
    integer legal_decode_x_base = 0;
    integer legal_accumulator_x_base = 0;
    integer legal_sample_x_base = 0;
    integer legal_public_sample_x_base = 0;
    integer failures = 0;
    logic [4:0] previous_sequence = 5'd0;
    logic previous_sequence_valid = 1'b0;
    logic previous_sample = 1'bx;
    logic pulse_width_active = 1'b0;

    wire [5:0] diag_cur_ch =
        dut.u_jt12.gen_adpcm.u_adpcm_a.cur_ch;
    wire [5:0] diag_en_ch =
        dut.u_jt12.gen_adpcm.u_adpcm_a.en_ch;
    wire [5:0] diag_aon_sr =
        dut.u_jt12.gen_adpcm.u_adpcm_a.aon_sr;
    wire [5:0] diag_aoff_sr =
        dut.u_jt12.gen_adpcm.u_adpcm_a.aoff_sr;
    wire diag_cen6 = dut.u_jt12.clk_en_666;
    wire diag_cen1 = dut.u_jt12.clk_en_111;
    wire diag_nibble_sel =
        dut.u_jt12.gen_adpcm.u_adpcm_a.nibble_sel;
    wire diag_decoder_active =
        dut.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.decon;
    wire diag_sumup6 =
        dut.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.sumup6;
    wire diag_active5 =
        dut.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.active5;
    wire diag_on1 =
        dut.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on1;
    wire diag_acc_left_en =
        dut.u_jt12.gen_adpcm.u_adpcm_a.u_acc_left.en_sum;
    wire diag_acc_right_en =
        dut.u_jt12.gen_adpcm.u_adpcm_a.u_acc_right.en_sum;
    wire [20:0] diag_addr1 =
        dut.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.addr1;
    wire [3:0] diag_bank1 =
        dut.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.bank1;
    wire [3:0] diag_captured_nibble =
        dut.u_jt12.gen_adpcm.u_adpcm_a.data;
    wire diag_zero = dut.u_jt12.u_mmr.u_reg.zero;
    wire [2:0] diag_fm_cur_ch = dut.u_jt12.u_mmr.u_reg.cur_ch;
    wire [1:0] diag_fm_cur_op = dut.u_jt12.u_mmr.u_reg.cur_op;
    wire diag_fm_clk_en = dut.u_jt12.clk_en;

    function automatic [4:0] expected_sequence_next(input [4:0] current);
        logic [1:0] op_now;
        logic [2:0] ch_now;
        logic [1:0] op_next;
        logic [2:0] ch_next;
        begin
            op_now = current[4:3];
            ch_now = current[2:0];
            op_next = ch_now == 3'd6 ? op_now + 1'b1 : op_now;
            ch_next = ch_now[1:0] == 2'b10 ?
                ch_now + 2'd2 : ch_now + 1'd1;
            expected_sequence_next = {op_next, ch_next};
        end
    endfunction

    function automatic logic public_sample_unknown;
        begin
            public_sample_unknown =
                $isunknown(dout) ||
                $isunknown(irq_n) ||
                $isunknown(adpcma_roe_n) ||
                $isunknown(adpcmb_addr) ||
                $isunknown(adpcmb_roe_n) ||
                $isunknown(psg_A) ||
                $isunknown(psg_B) ||
                $isunknown(psg_C) ||
                $isunknown(fm_snd) ||
                $isunknown(psg_snd) ||
                $isunknown(snd_left) ||
                $isunknown(snd_right) ||
                $isunknown(snd_sample);
        end
    endfunction

    always #5 clk = ~clk;

    always @(posedge clk) begin
        logic fetch_was_valid;
        logic decode_was_enabled;
        logic capture_addr_was_unknown;
        logic capture_data_was_unknown;
        fetch_was_valid =
            adpcma_roe_n === 1'b0 && diag_decoder_active === 1'b1;
        decode_was_enabled =
            diag_cen6 === 1'b1 && diag_decoder_active === 1'b1;
        capture_addr_was_unknown =
            $isunknown(adpcma_addr) || $isunknown(adpcma_bank);
        capture_data_was_unknown = $isunknown(adpcma_data);
        system_cycle = system_cycle + 1;
        #1;
        if (first_addr_x_cycle < 0 && $isunknown(adpcma_addr))
            first_addr_x_cycle = system_cycle;
        if (first_bank_x_cycle < 0 && $isunknown(adpcma_bank))
            first_bank_x_cycle = system_cycle;
        if (first_strobe_x_cycle < 0 && $isunknown(snd_sample))
            first_strobe_x_cycle = system_cycle;
        if (rst) begin
            if (!$isunknown(diag_fm_cur_op) &&
                !$isunknown(diag_fm_cur_ch)) begin
                previous_sequence = {diag_fm_cur_op, diag_fm_cur_ch};
                previous_sequence_valid = 1'b1;
            end
            previous_sample = snd_sample;
            pulse_width_active = 1'b0;
            pulse_width_counter = 0;
        end else begin
            if (cen && $isunknown(snd_sample))
                strobe_x_count = strobe_x_count + 1;

            if (previous_sample === 1'b0 && snd_sample === 1'b1) begin
                pulse_width_active = 1'b1;
                pulse_width_counter = 1;
            end else if (pulse_width_active && snd_sample === 1'b1) begin
                pulse_width_counter = pulse_width_counter + 1;
            end else if (pulse_width_active && previous_sample === 1'b1 &&
                         snd_sample === 1'b0) begin
                sample_width_cycles = pulse_width_counter;
                pulse_width_active = 1'b0;
                pulse_width_counter = 0;
            end
            previous_sample = snd_sample;

            if (diag_fm_clk_en === 1'b1) begin
                sequence_updates = sequence_updates + 1;
                if (previous_sequence_valid &&
                    {diag_fm_cur_op, diag_fm_cur_ch} !==
                    expected_sequence_next(previous_sequence)) begin
                    sequence_errors = sequence_errors + 1;
                    if (sequence_errors <= 8)
                        $display(
                            "SEQUENCE_FAIL cycle=%0d previous=%02x expected=%02x actual=%02x",
                            system_cycle, previous_sequence,
                            expected_sequence_next(previous_sequence),
                            {diag_fm_cur_op, diag_fm_cur_ch}
                        );
                end
                if (!$isunknown(diag_fm_cur_op) &&
                    !$isunknown(diag_fm_cur_ch)) begin
                    previous_sequence = {diag_fm_cur_op, diag_fm_cur_ch};
                    previous_sequence_valid = 1'b1;
                end
                if (diag_zero !==
                    ({diag_fm_cur_op, diag_fm_cur_ch} == 5'd0)) begin
                    sequence_errors = sequence_errors + 1;
                    if (sequence_errors <= 8)
                        $display(
                            "ZERO_BOUNDARY_FAIL cycle=%0d op=%x ch=%x zero=%b",
                            system_cycle, diag_fm_cur_op, diag_fm_cur_ch,
                            diag_zero
                        );
                end
                if (diag_zero === 1'b1) begin
                    zero_pulses = zero_pulses + 1;
                    if (first_zero_cycle < 0)
                        first_zero_cycle = system_cycle;
                    if (last_zero_update >= 0) begin
                        zero_interval_updates =
                            sequence_updates - last_zero_update;
                        zero_interval_cycles =
                            system_cycle - last_zero_cycle;
                    end
                    last_zero_update = sequence_updates;
                    last_zero_cycle = system_cycle;
                end
            end
        end
        if (!rst && cen) begin
            post_reset_cen = post_reset_cen + 1;
            if (!(adpcma_roe_n === 1'b0 &&
                  diag_decoder_active === 1'b1) &&
                ($isunknown(adpcma_addr) ||
                 $isunknown(adpcma_bank)))
                inactive_addr_x_count = inactive_addr_x_count + 1;
            if (adpcma_roe_n === 1'b0 && diag_decoder_active === 1'b1) begin
                fetch_count = fetch_count + 1;
                if (first_fetch_cycle < 0)
                    first_fetch_cycle = system_cycle;
                if ($isunknown(adpcma_addr) || $isunknown(adpcma_bank)) begin
                    fetch_x_count = fetch_x_count + 1;
                    if (fetch_x_count <= 12)
                        $display(
                            "FETCH_X cycle=%0d count=%0d addr=%05x bank=%x cur_ch=%02x en_ch=%02x on1=%b sumup6=%b decon=%b cen6=%b",
                            system_cycle, fetch_x_count, adpcma_addr,
                            adpcma_bank, diag_cur_ch, diag_en_ch, diag_on1,
                            diag_sumup6, diag_decoder_active, diag_cen6
                        );
                end
            end
            if (fetch_was_valid) begin
                if (capture_addr_was_unknown)
                    capture_addr_x_count = capture_addr_x_count + 1;
                if (capture_data_was_unknown)
                    capture_data_x_count = capture_data_x_count + 1;
                if (first_capture_cycle < 0) begin
                    first_capture_cycle = system_cycle;
                    $display(
                        "FIRST_CAPTURE cycle=%0d captured=%x known=%0d addr=%05x bank=%x",
                        system_cycle, diag_captured_nibble,
                        !$isunknown(diag_captured_nibble),
                        adpcma_addr, adpcma_bank
                    );
                end
                if ($isunknown(diag_captured_nibble))
                    capture_x_count = capture_x_count + 1;
            end
            if (decode_was_enabled) begin
                if (first_decode_cycle < 0) begin
                    first_decode_cycle = system_cycle;
                    $display(
                        "FIRST_DECODE cycle=%0d data=%x pcmdec=%04x pcmatt=%04x known=%0d",
                        system_cycle, diag_captured_nibble,
                        dut.u_jt12.gen_adpcm.u_adpcm_a.pcmdec,
                        dut.u_jt12.gen_adpcm.u_adpcm_a.pcm_att,
                        !$isunknown(diag_captured_nibble) &&
                        !$isunknown(dut.u_jt12.gen_adpcm.u_adpcm_a.pcmdec)
                    );
                end
                if ($isunknown(diag_captured_nibble) ||
                    $isunknown(dut.u_jt12.gen_adpcm.u_adpcm_a.pcmdec) ||
                    $isunknown(dut.u_jt12.gen_adpcm.u_adpcm_a.pcm_att))
                    decode_x_count = decode_x_count + 1;
            end
            if ((diag_acc_left_en === 1'b1 ||
                 diag_acc_right_en === 1'b1) &&
                ($isunknown(
                    dut.u_jt12.gen_adpcm.u_adpcm_a.pre_pcm55_l) ||
                 $isunknown(
                    dut.u_jt12.gen_adpcm.u_adpcm_a.pre_pcm55_r)))
                accumulator_x_count = accumulator_x_count + 1;
            if (snd_sample === 1'b1) begin
                if (first_sample_cycle < 0)
                    first_sample_cycle = system_cycle;
                if ($isunknown(snd_left) || $isunknown(snd_right)) begin
                    sample_x_count = sample_x_count + 1;
                    if (sample_x_count <= 24)
                        $display(
                            "SAMPLE_X cycle=%0d count=%0d fm=%04x snd_l=%04x snd_r=%04x op=%x ch=%x zero=%b",
                            system_cycle, sample_x_count, fm_snd,
                            snd_left, snd_right, diag_fm_cur_op,
                            diag_fm_cur_ch, diag_zero
                        );
                end
                if (public_sample_unknown())
                    public_sample_x_count = public_sample_x_count + 1;
            end
        end
    end

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
                $display("FAIL BUSY timeout reg=%02x data=%02x", reg_addr, reg_data);
            end
        end
    endtask

    task automatic report_sources(input string phase);
        begin
            $display(
                "SOURCE phase=%s cycle=%0d aon_copy=%02x aon_sr=%02x aoff_sr=%02x cur_ch=%02x en_ch=%02x on1=%b active5=%b sumup6=%b decon=%b addr1=%06x bank1=%x roe_n=%b fm_op=%x fm_ch=%x zero=%b",
                phase, system_cycle,
                dut.u_jt12.gen_adpcm.u_adpcm_a.aon_cmd_cpy,
                diag_aon_sr, diag_aoff_sr, diag_cur_ch, diag_en_ch,
                diag_on1, diag_active5, diag_sumup6, diag_decoder_active,
                diag_addr1, diag_bank1, adpcma_roe_n,
                diag_fm_cur_op, diag_fm_cur_ch, diag_zero
            );
        end
    endtask

    task automatic report_row(input string phase);
        begin
            $display(
                "SWEEP phase=%s reset_cen=%0d cycle=%0d post_cen=%0d fm_op=%x fm_ch=%x zero=%b addr=%05x bank=%x active=%b fetch=%b cen6=%b nibble=%b captured=%x acc_en=%b/%b sample=%b snd_l=%04x snd_r=%04x dout=%02x irq_n=%b",
                phase, reset_cen_count, system_cycle, post_reset_cen,
                diag_fm_cur_op, diag_fm_cur_ch, diag_zero,
                adpcma_addr, adpcma_bank, diag_on1,
                (adpcma_roe_n === 1'b0 && diag_decoder_active === 1'b1),
                diag_cen6, diag_nibble_sel, diag_captured_nibble,
                diag_acc_left_en, diag_acc_right_en, snd_sample,
                snd_left, snd_right, dout, irq_n
            );
        end
    endtask

    task automatic audit_input_meter;
        integer individual_unknowns;
        begin
            individual_unknowns = 0;
            if ($isunknown(din)) begin
                individual_unknowns = individual_unknowns + 1;
                $display("INPUT_X din");
            end
            if ($isunknown(addr)) begin
                individual_unknowns = individual_unknowns + 1;
                $display("INPUT_X addr");
            end
            if ($isunknown(cs_n)) begin
                individual_unknowns = individual_unknowns + 1;
                $display("INPUT_X cs_n");
            end
            if ($isunknown(wr_n)) begin
                individual_unknowns = individual_unknowns + 1;
                $display("INPUT_X wr_n");
            end
            if ($isunknown(adpcma_data)) begin
                individual_unknowns = individual_unknowns + 1;
                $display("INPUT_X adpcma_data");
            end
            if ($isunknown(adpcmb_data)) begin
                individual_unknowns = individual_unknowns + 1;
                $display("INPUT_X adpcmb_data");
            end
            $display(
                "INPUT_METER bundle_width=28 bundle_unknown=%0d individual_unknowns=%0d values=%02x/%x/%b/%b/%02x/%02x",
                $isunknown({din, addr, cs_n, wr_n, adpcma_data, adpcmb_data}),
                individual_unknowns, din, addr, cs_n, wr_n,
                adpcma_data, adpcmb_data
            );
        end
    endtask

    task automatic require_sequencer_known(input string phase);
        begin
            if ($isunknown(diag_fm_cur_op) ||
                $isunknown(diag_fm_cur_ch) ||
                $isunknown(diag_zero) ||
                $isunknown(snd_sample)) begin
                failures = failures + 1;
                $display(
                    "FAIL phase=%s sequencer contains X op=%x ch=%x zero=%b sample=%b",
                    phase, diag_fm_cur_op, diag_fm_cur_ch,
                    diag_zero, snd_sample
                );
            end
        end
    endtask

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
        if (!$value$plusargs("LEGAL=%d", do_legal))
            do_legal = 0;
        if (!$value$plusargs("EXPECT_PATCH=%d", expect_patch))
            expect_patch = 0;

        // Establish reset with no chip CEN, then apply the requested count.
        wait_clocks(16);
        report_row("RESET_NO_CEN");
        report_sources("RESET_NO_CEN");
        if (expect_patch != 0)
            require_sequencer_known("RESET_NO_CEN");
        if (reset_cen_count > 0) begin
            cen = 1'b1;
            wait_clocks(reset_cen_count);
            cen = 1'b0;
        end
        report_row("RESET_REQUESTED_CEN");
        report_sources("RESET_REQUESTED_CEN");
        if (expect_patch != 0)
            require_sequencer_known("RESET_REQUESTED_CEN");

        @(negedge clk);
        rst = 1'b0;
        cen = 1'b1;
        wait_clocks(256);
        #1;
        report_row("POST_RESET_256_CEN");
        report_sources("POST_RESET_256_CEN");
        if (expect_patch != 0)
            require_sequencer_known("POST_RESET_256_CEN");

        wait_clocks(19744);
        #1;
        report_row("POST_RESET_20000_SYS");
        report_sources("POST_RESET_20000_SYS");
        audit_input_meter();
        if (expect_patch != 0)
            require_sequencer_known("POST_RESET_20000_SYS");

        if (do_legal != 0) begin
            legal_fetch_x_base = fetch_x_count;
            legal_capture_x_base = capture_x_count;
            legal_capture_addr_x_base = capture_addr_x_count;
            legal_capture_data_x_base = capture_data_x_count;
            legal_decode_x_base = decode_x_count;
            legal_accumulator_x_base = accumulator_x_count;
            legal_sample_x_base = sample_x_count;
            legal_public_sample_x_base = public_sample_x_count;
            // Official adpcma.jtt-derived channel-0 setup.  Bit 7 selects
            // key-off; bits 5:0 select voices.  Stop every voice first.
            write_reg(1'b1, 8'h00, 8'hbf);
            write_reg(1'b1, 8'h10, 8'h00);
            write_reg(1'b1, 8'h18, 8'h00);
            write_reg(1'b1, 8'h20, 8'h0f);
            write_reg(1'b1, 8'h28, 8'h00);
            write_reg(1'b1, 8'h01, 8'h3f);
            write_reg(1'b1, 8'h08, 8'hf5);
            wait_clocks(512);
            #1;
            report_row("LEGAL_INITIALIZED_KEYOFF");
            report_sources("LEGAL_INITIALIZED_KEYOFF");
            if (expect_patch != 0)
                require_sequencer_known("LEGAL_INITIALIZED_KEYOFF");

            write_reg(1'b1, 8'h00, 8'h01);
            if (expect_patch != 0)
                require_sequencer_known("LEGAL_KEYON");
            begin : wait_first_fetch
                integer guard;
                guard = 0;
                while (!(adpcma_roe_n === 1'b0 &&
                         diag_decoder_active === 1'b1) && guard < 4096) begin
                    @(posedge clk);
                    #1;
                    guard = guard + 1;
                end
                report_row("FIRST_VALID_FETCH");
                report_sources("FIRST_VALID_FETCH");
                if (expect_patch != 0)
                    require_sequencer_known("FIRST_VALID_FETCH");
                $display(
                    "FETCH_CHECK found=%0d addr_known=%0d bank_known=%0d rom_data_known=%0d captured_known=%0d accum_known=%0d snd_known=%0d",
                    guard < 4096, !$isunknown(adpcma_addr),
                    !$isunknown(adpcma_bank), !$isunknown(adpcma_data),
                    !$isunknown(diag_captured_nibble),
                    !$isunknown(dut.u_jt12.gen_adpcm.u_adpcm_a.pcm_att) &&
                    !$isunknown(dut.u_jt12.gen_adpcm.u_adpcm_a.pre_pcm55_l) &&
                    !$isunknown(dut.u_jt12.gen_adpcm.u_adpcm_a.pre_pcm55_r),
                    !$isunknown(snd_left) && !$isunknown(snd_right)
                );
            end

            wait_clocks(512);
            #1;
            report_row("ACTIVE_SETTLED");
            $display(
                "ACTIVE_CHECK pcmdec_known=%0d pcmatt_known=%0d adpcm_acc_known=%0d snd_known=%0d fetch_x=%0d capture_x=%0d decode_x=%0d",
                !$isunknown(dut.u_jt12.gen_adpcm.u_adpcm_a.pcmdec),
                !$isunknown(dut.u_jt12.gen_adpcm.u_adpcm_a.pcm_att),
                !$isunknown(dut.u_jt12.gen_adpcm.u_adpcm_a.pre_pcm55_l) &&
                !$isunknown(dut.u_jt12.gen_adpcm.u_adpcm_a.pre_pcm55_r),
                !$isunknown(snd_left) && !$isunknown(snd_right), fetch_x_count,
                capture_x_count, decode_x_count
            );

            begin : wait_first_sample
                integer guard;
                guard = 0;
                while (snd_sample !== 1'b1 && guard < 4096) begin
                    @(posedge clk);
                    #1;
                    guard = guard + 1;
                end
                report_row("FIRST_VALID_SND_SAMPLE");
                if (expect_patch != 0)
                    require_sequencer_known("FIRST_VALID_SND_SAMPLE");
                $display(
                    "SAMPLE_CHECK found=%0d sample_known=%0d snd_known=%0d zero=%b cur_ch=%x cur_op=%x",
                    guard < 4096, !$isunknown(snd_sample),
                    !$isunknown(snd_left) && !$isunknown(snd_right), diag_zero,
                    dut.u_jt12.u_mmr.u_reg.cur_ch,
                    dut.u_jt12.u_mmr.u_reg.cur_op
                );
            end
        end

        $display(
            "DIAG_RESULT reset_cen=%0d legal=%0d fetches=%0d first_fetch_cycle=%0d first_capture_cycle=%0d first_decode_cycle=%0d first_sample_cycle=%0d fetch_x=%0d capture_x=%0d decode_x=%0d sample_x=%0d failures=%0d",
            reset_cen_count, do_legal, fetch_count, first_fetch_cycle,
            first_capture_cycle, first_decode_cycle, first_sample_cycle,
            fetch_x_count, capture_x_count, decode_x_count,
            sample_x_count, failures
        );
        $display(
            "FIRST_X addr_cycle=%0d bank_cycle=%0d snd_sample_cycle=%0d",
            first_addr_x_cycle, first_bank_x_cycle, first_strobe_x_cycle
        );
        $display(
            "X_RESULT strobe_x=%0d capture_addr_x=%0d capture_data_x=%0d accumulator_x=%0d public_sample_x=%0d inactive_addr_x=%0d",
            strobe_x_count, capture_addr_x_count, capture_data_x_count,
            accumulator_x_count, public_sample_x_count,
            inactive_addr_x_count
        );
        $display(
            "CADENCE_RESULT updates=%0d errors=%0d zero_pulses=%0d first_zero_cycle=%0d interval_updates=%0d interval_cycles=%0d sample_width_cycles=%0d",
            sequence_updates, sequence_errors, zero_pulses,
            first_zero_cycle, zero_interval_updates,
            zero_interval_cycles, sample_width_cycles
        );
        if (do_legal != 0)
            $display(
                "LEGAL_X_RESULT fetch_x=%0d capture_x=%0d capture_addr_x=%0d capture_data_x=%0d decode_x=%0d accumulator_x=%0d sample_x=%0d public_sample_x=%0d",
                fetch_x_count - legal_fetch_x_base,
                capture_x_count - legal_capture_x_base,
                capture_addr_x_count - legal_capture_addr_x_base,
                capture_data_x_count - legal_capture_data_x_base,
                decode_x_count - legal_decode_x_base,
                accumulator_x_count - legal_accumulator_x_base,
                sample_x_count - legal_sample_x_base,
                public_sample_x_count - legal_public_sample_x_base
            );
        if (expect_patch != 0) begin
            if (sequence_errors != 0 ||
                strobe_x_count != 0 ||
                first_sample_cycle < 0 ||
                zero_pulses < 2 ||
                zero_interval_updates != 24 ||
                zero_interval_cycles != 144 ||
                sample_width_cycles != 6) begin
                failures = failures + 1;
                $display("FAIL sequencer reset/cadence contract");
            end
            if (do_legal != 0 &&
                (fetch_x_count - legal_fetch_x_base != 0 ||
                 capture_x_count - legal_capture_x_base != 0 ||
                 capture_addr_x_count - legal_capture_addr_x_base != 0 ||
                 capture_data_x_count - legal_capture_data_x_base != 0 ||
                 decode_x_count - legal_decode_x_base != 0 ||
                 accumulator_x_count - legal_accumulator_x_base != 0 ||
                 sample_x_count - legal_sample_x_base != 0 ||
                 public_sample_x_count -
                    legal_public_sample_x_base != 0)) begin
                failures = failures + 1;
                $display("FAIL legal ADPCM-A X contract");
            end
            if (failures != 0)
                $fatal(1, "JT10 Phase 0B failed (%0d)", failures);
        end
        $finish;
    end

    initial begin
        #3000000;
        $fatal(1, "timeout");
    end
endmodule
