`timescale 1ps/1ps

// Investigation-only startup trace.  This file intentionally performs no
// register writes and is not part of the production file list.
module tb_jt12_fm_startup_trace;
    localparam integer SYS_CLK_HZ = 32_000_000;
    localparam integer CHIP_CLK_HZ = 4_000_000;
    localparam integer CEN_DIV = SYS_CLK_HZ / CHIP_CLK_HZ;
    localparam integer HALF_PS = 500_000_000_000 / SYS_CLK_HZ;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cen = 1'b0;
    integer cen_count = 0;
    integer sys_cycle = 0;
    logic monitor = 1'b0;

    wire signed [15:0] fm_ssg_l, fm_ssg_r;
    wire signed [15:0] fm_nossg_l, fm_nossg_r;
    wire signed [15:0] fm_2612_l, fm_2612_r;

    integer update_count = 0;
    integer first_op_x_3 = -1;
    integer first_acc_x_3 = -1;
    integer first_snd_x_3 = -1;
    integer first_public_x_3 = -1;
    integer acc_known_again_3 = -1;
    integer snd_known_again_3 = -1;
    integer first_op_x_nossg = -1;
    integer first_acc_x_nossg = -1;
    integer first_snd_x_nossg = -1;
    integer first_public_x_nossg = -1;
    integer first_op_x_6 = -1;
    integer first_acc_x_6 = -1;
    integer first_public_x_6 = -1;
    integer first_zero_3 = -1;
    integer first_sum_3 = -1;
    integer first_op_known_3 = -1;
    bit acc_was_x_3 = 0;
    bit snd_was_x_3 = 0;
    bit prev_acc_x_3 = 0;
    bit prev_snd_x_3 = 0;
    bit prev_op_x_3 = 1;
    bit mismatch_3ch = 0;

    bit sx_zero, sx_sum, sx_strobes, sx_alg, sx_curch, sx_curop;
    bit sx_selected, sx_keyon, sx_fb, sx_freq, sx_opparams;
    bit sx_opresult, sx_ophd, sx_opinternal, sx_opxii;
    bit sx_exp, sx_logsin, sx_egatten, sx_pgphase;
    bit sx_pm_in, sx_pm_out, sx_feedback, sx_modinput;
    bit sx_opdelay, sx_pgstate, sx_egstate;
    bit sx_current, sx_next, sx_acc, sx_snd, sx_clken;
    bit sx_public, sx_combined;
    bit public_mismatch = 0;

    always #(HALF_PS) clk = ~clk;

    always @(posedge clk) begin
        sys_cycle <= sys_cycle + 1;
        if (rst) begin
            cen <= 1'b0;
            cen_count <= 0;
        end else if (cen_count == CEN_DIV-1) begin
            cen <= 1'b1;
            cen_count <= 0;
        end else begin
            cen <= 1'b0;
            cen_count <= cen_count + 1;
        end
    end

    jt12_top #(
        .use_lfo(0), .use_ssg(1), .num_ch(3), .use_pcm(0),
        .use_adpcm(0), .JT49_DIV(2), .mask_div(0)
    ) dut_ssg (
        .rst(rst), .clk(clk), .cen(cen), .din(8'h00), .addr(2'b00),
        .cs_n(1'b1), .wr_n(1'b1), .ladder(1'b0), .en_hifi_pcm(1'b0),
        .adpcma_data(8'h00), .adpcmb_data(8'h00),
        .IOA_in(8'h00), .IOB_in(8'h00), .debug_bus(8'h00),
        .fm_snd_left(fm_ssg_l), .fm_snd_right(fm_ssg_r)
    );

    jt12_top #(
        .use_lfo(0), .use_ssg(0), .num_ch(3), .use_pcm(0),
        .use_adpcm(0), .JT49_DIV(2), .mask_div(0)
    ) dut_nossg (
        .rst(rst), .clk(clk), .cen(cen), .din(8'h00), .addr(2'b00),
        .cs_n(1'b1), .wr_n(1'b1), .ladder(1'b0), .en_hifi_pcm(1'b0),
        .adpcma_data(8'h00), .adpcmb_data(8'h00),
        .IOA_in(8'h00), .IOB_in(8'h00), .debug_bus(8'h00),
        .fm_snd_left(fm_nossg_l), .fm_snd_right(fm_nossg_r)
    );

    // Existing YM2612 parameter set (jt12_top defaults made explicit).
    jt12_top #(
        .use_lfo(1), .use_ssg(0), .num_ch(6), .use_pcm(1),
        .use_adpcm(0), .JT49_DIV(2), .mask_div(1)
    ) dut_2612 (
        .rst(rst), .clk(clk), .cen(cen), .din(8'h00), .addr(2'b00),
        .cs_n(1'b1), .wr_n(1'b1), .ladder(1'b0), .en_hifi_pcm(1'b0),
        .adpcma_data(8'h00), .adpcmb_data(8'h00),
        .IOA_in(8'h00), .IOB_in(8'h00), .debug_bus(8'h00),
        .fm_snd_left(fm_2612_l), .fm_snd_right(fm_2612_r)
    );

    task automatic first_x(
        input string signal_name,
        input logic is_unknown,
        inout bit seen,
        input string edge_name,
        input integer edge_cycle
    );
        begin
            if (!seen && is_unknown) begin
                seen = 1'b1;
                $display("FIRST_X cycle=%0d time=%0t edge=%s signal=%s rst=%b cen=%b internal_clk_en=%b cur_ch=%h cur_op=%h zero=%b sum_en=%b op_hd=%h",
                         edge_cycle, $time, edge_name, signal_name, rst, cen,
                         dut_ssg.clk_en, dut_ssg.cur_ch, dut_ssg.cur_op,
                         dut_ssg.zero, dut_ssg.gen_2203_acc.u_acc.sum_en,
                         dut_ssg.op_result_hd);
            end
        end
    endtask

    task automatic check_detailed_x(input string edge_name, input integer edge_cycle);
        begin
            first_x("clk_en", (^dut_ssg.clk_en) === 1'bx, sx_clken, edge_name, edge_cycle);
            first_x("zero", (^dut_ssg.zero) === 1'bx, sx_zero, edge_name, edge_cycle);
            first_x("sum_en", (^dut_ssg.gen_2203_acc.u_acc.sum_en) === 1'bx, sx_sum, edge_name, edge_cycle);
            first_x("strobes", (^{dut_ssg.s1_enters,dut_ssg.s2_enters,dut_ssg.s3_enters,dut_ssg.s4_enters}) === 1'bx, sx_strobes, edge_name, edge_cycle);
            first_x("alg_I", (^dut_ssg.alg_I) === 1'bx, sx_alg, edge_name, edge_cycle);
            first_x("cur_ch", (^dut_ssg.cur_ch) === 1'bx, sx_curch, edge_name, edge_cycle);
            first_x("cur_op", (^dut_ssg.cur_op) === 1'bx, sx_curop, edge_name, edge_cycle);
            first_x("mmr.selected_register/up_ch/up_op", (^{dut_ssg.u_mmr.selected_register,dut_ssg.u_mmr.up_ch,dut_ssg.u_mmr.up_op}) === 1'bx, sx_selected, edge_name, edge_cycle);
            first_x("keyon_I", (^dut_ssg.keyon_I) === 1'bx, sx_keyon, edge_name, edge_cycle);
            first_x("fb_II", (^dut_ssg.fb_II) === 1'bx, sx_fb, edge_name, edge_cycle);
            first_x("fnum_I/block_I", (^{dut_ssg.fnum_I,dut_ssg.block_I}) === 1'bx, sx_freq, edge_name, edge_cycle);
            first_x("operator_parameter_readout", (^{dut_ssg.mul_II,dut_ssg.dt1_I,dut_ssg.tl_IV,dut_ssg.ar_I,dut_ssg.d1r_I,dut_ssg.d2r_I,dut_ssg.rr_I,dut_ssg.sl_I}) === 1'bx, sx_opparams, edge_name, edge_cycle);
            first_x("op_result", (^dut_ssg.op_result) === 1'bx, sx_opresult, edge_name, edge_cycle);
            first_x("op_result_hd", (^dut_ssg.op_result_hd) === 1'bx, sx_ophd, edge_name, edge_cycle);
            first_x("u_op.op_result_internal", (^dut_ssg.u_op.op_result_internal) === 1'bx, sx_opinternal, edge_name, edge_cycle);
            first_x("u_op.op_XII", (^dut_ssg.u_op.op_XII) === 1'bx, sx_opxii, edge_name, edge_cycle);
            first_x("u_op.mantissa_X/XI/exponent", (^{dut_ssg.u_op.mantissa_X,dut_ssg.u_op.mantissa_XI,dut_ssg.u_op.exponent_X,dut_ssg.u_op.exponent_XI}) === 1'bx, sx_exp, edge_name, edge_cycle);
            first_x("u_op.logsin_IX", (^dut_ssg.u_op.logsin_IX) === 1'bx, sx_logsin, edge_name, edge_cycle);
            first_x("eg_atten/eg_pipeline", (^{dut_ssg.eg_IX,dut_ssg.eg_V,dut_ssg.u_op.atten_internal_IX}) === 1'bx, sx_egatten, edge_name, edge_cycle);
            first_x("phase_VIII/pg_phase_state", (^{dut_ssg.phase_VIII,dut_ssg.u_pg.phase_drop,dut_ssg.u_pg.phase_in}) === 1'bx, sx_pgphase, edge_name, edge_cycle);
            first_x("pm_preshift_II/phasemod_II", (^{dut_ssg.u_op.pm_preshift_II,dut_ssg.u_op.phasemod_II}) === 1'bx, sx_pm_in, edge_name, edge_cycle);
            first_x("phasemod_VIII/phase", (^{dut_ssg.u_op.phasemod_VIII,dut_ssg.u_op.phase}) === 1'bx, sx_pm_out, edge_name, edge_cycle);
            first_x("feedback_values", (^{dut_ssg.u_op.prev1,dut_ssg.u_op.prevprev1,dut_ssg.u_op.prev2,dut_ssg.fb_II}) === 1'bx, sx_feedback, edge_name, edge_cycle);
            first_x("modulation_select/x/y", (^{dut_ssg.xuse_prevprev1,dut_ssg.xuse_prev2,dut_ssg.xuse_internal,dut_ssg.yuse_prev1,dut_ssg.yuse_prev2,dut_ssg.yuse_internal,dut_ssg.u_op.x,dut_ssg.u_op.y}) === 1'bx, sx_modinput, edge_name, edge_cycle);
            first_x("operator_delay_state", (^{dut_ssg.u_op.gen_feedback_rst.prev1_buffer.bits[0],dut_ssg.u_op.gen_feedback_rst.prevprev1_buffer.bits[0],dut_ssg.u_op.gen_feedback_rst.prev2_buffer.bits[0],dut_ssg.u_op.gen_phasemod_rst.phasemod_sh.bits[0]}) === 1'bx, sx_opdelay, edge_name, edge_cycle);
            first_x("pg_pipeline_state", (^{dut_ssg.u_pg.keycode_II,dut_ssg.u_pg.detune_mod_II,dut_ssg.u_pg.phinc_II}) === 1'bx, sx_pgstate, edge_name, edge_cycle);
            first_x("eg_pipeline_state", (^{dut_ssg.u_eg.eg_in_II,dut_ssg.u_eg.eg_in_III,dut_ssg.u_eg.eg_in_IV,dut_ssg.u_eg.attack_II,dut_ssg.u_eg.attack_III,dut_ssg.u_eg.base_rate_II,dut_ssg.u_eg.rate_in_III,dut_ssg.u_eg.step_III,dut_ssg.u_eg.sum_in_III}) === 1'bx, sx_egstate, edge_name, edge_cycle);
            first_x("mono.current", (^dut_ssg.gen_2203_acc.u_acc.u_mono.current) === 1'bx, sx_current, edge_name, edge_cycle);
            first_x("mono.next", (^dut_ssg.gen_2203_acc.u_acc.u_mono.next) === 1'bx, sx_next, edge_name, edge_cycle);
            first_x("mono.acc", (^dut_ssg.gen_2203_acc.u_acc.u_mono.acc) === 1'bx, sx_acc, edge_name, edge_cycle);
            first_x("mono.snd", (^dut_ssg.gen_2203_acc.u_acc.u_mono.snd) === 1'bx, sx_snd, edge_name, edge_cycle);
            first_x("fm_public", (^{fm_ssg_l,fm_ssg_r}) === 1'bx, sx_public, edge_name, edge_cycle);
            first_x("combined_public", (^{dut_ssg.snd_left,dut_ssg.snd_right,dut_ssg.psg_snd}) === 1'bx, sx_combined, edge_name, edge_cycle);
        end
    endtask

    task automatic trace_acc(input string edge_name, input integer edge_cycle);
        begin
            $display("ACC_EVENT cycle=%0d time=%0t edge=%s update=%0d clk_en=%b ch=%0d op=%0d zero=%b alg=%h s=%b%b%b%b sum_en=%b op=%h current=%h next=%h acc=%h snd=%h",
                     edge_cycle, $time, edge_name, update_count,
                     dut_ssg.clk_en, dut_ssg.cur_ch, dut_ssg.cur_op,
                     dut_ssg.zero, dut_ssg.alg_I,
                     dut_ssg.s4_enters, dut_ssg.s3_enters,
                     dut_ssg.s2_enters, dut_ssg.s1_enters,
                     dut_ssg.gen_2203_acc.u_acc.sum_en,
                     dut_ssg.op_result_hd,
                     dut_ssg.gen_2203_acc.u_acc.u_mono.current,
                     dut_ssg.gen_2203_acc.u_acc.u_mono.next,
                     dut_ssg.gen_2203_acc.u_acc.u_mono.acc,
                     dut_ssg.gen_2203_acc.u_acc.u_mono.snd);
        end
    endtask

    always @(posedge clk) begin : monitor_edges
        integer edge_cycle;
        edge_cycle = sys_cycle;
        if (monitor) begin
            check_detailed_x("PRE_NBA", edge_cycle);

            if (dut_ssg.clk_en && edge_cycle <= 650) begin
                update_count = update_count + 1;
                trace_acc("PRE_NBA", edge_cycle);
            end
            if (dut_ssg.clk_en && (edge_cycle <= 650 ||
                                   (edge_cycle >= 5000 && edge_cycle <= 5800))) begin
                $display("PIPE_EVENT cycle=%0d time=%0t edge=PRE_NBA ch=%0d op=%0d s=%b%b%b%b ophd=%h opXII=%h sh3=%h signXI=%b manXI=%h expXI=%h expX=%h logsin=%h atten=%h phase=%h pmVIII=%h pmII=%h pm_pre=%h prev1=%h prevprev1=%h prev2=%h egIX=%h pgVIII=%h egV=%h egin1=%h egin2=%h egin3=%h egin4=%h egpure=%h egout=%h cntin=%b cntlsb=%b step=%b sumin=%b rate=%h keyon=%b keylast=%b",
                         edge_cycle, $time, dut_ssg.cur_ch, dut_ssg.cur_op,
                         dut_ssg.s4_enters, dut_ssg.s3_enters,
                         dut_ssg.s2_enters, dut_ssg.s1_enters,
                         dut_ssg.op_result_hd, dut_ssg.u_op.op_XII,
                         dut_ssg.u_op.shifter_3, dut_ssg.u_op.signbit_XI,
                         dut_ssg.u_op.mantissa_XI, dut_ssg.u_op.exponent_XI,
                         dut_ssg.u_op.exponent_X, dut_ssg.u_op.logsin_IX,
                         dut_ssg.u_op.atten_internal_IX, dut_ssg.u_op.phase,
                         dut_ssg.u_op.phasemod_VIII, dut_ssg.u_op.phasemod_II,
                         dut_ssg.u_op.pm_preshift_II, dut_ssg.u_op.prev1,
                         dut_ssg.u_op.prevprev1, dut_ssg.u_op.prev2,
                         dut_ssg.eg_IX, dut_ssg.phase_VIII,
                         dut_ssg.eg_V, dut_ssg.u_eg.eg_in_I,
                         dut_ssg.u_eg.eg_in_II, dut_ssg.u_eg.eg_in_III,
                         dut_ssg.u_eg.eg_in_IV, dut_ssg.u_eg.pure_eg_out_III,
                         dut_ssg.u_eg.eg_out_IV, dut_ssg.u_eg.cnt_in_II,
                         dut_ssg.u_eg.cnt_lsb_II, dut_ssg.u_eg.step_II,
                         dut_ssg.u_eg.sum_in_III, dut_ssg.u_eg.rate_in_III,
                         dut_ssg.keyon_I, dut_ssg.u_eg.keyon_last_I);
            end

            if (first_zero_3 < 0 && dut_ssg.zero === 1'b1)
                first_zero_3 = edge_cycle;
            if (first_sum_3 < 0 && dut_ssg.gen_2203_acc.u_acc.sum_en === 1'b1)
                first_sum_3 = edge_cycle;
            if (first_op_known_3 < 0 && (^dut_ssg.op_result_hd) !== 1'bx)
                first_op_known_3 = edge_cycle;

            if (first_op_x_3 < 0 && (^dut_ssg.op_result_hd) === 1'bx)
                first_op_x_3 = edge_cycle;
            if (first_acc_x_3 < 0 && (^dut_ssg.gen_2203_acc.u_acc.u_mono.acc) === 1'bx)
                first_acc_x_3 = edge_cycle;
            if (first_snd_x_3 < 0 && (^dut_ssg.gen_2203_acc.u_acc.u_mono.snd) === 1'bx)
                first_snd_x_3 = edge_cycle;
            if (first_public_x_3 < 0 && (^fm_ssg_l) === 1'bx)
                first_public_x_3 = edge_cycle;

            if (first_op_x_nossg < 0 && (^dut_nossg.op_result_hd) === 1'bx)
                first_op_x_nossg = edge_cycle;
            if (first_acc_x_nossg < 0 && (^dut_nossg.gen_2203_acc.u_acc.u_mono.acc) === 1'bx)
                first_acc_x_nossg = edge_cycle;
            if (first_snd_x_nossg < 0 && (^dut_nossg.gen_2203_acc.u_acc.u_mono.snd) === 1'bx)
                first_snd_x_nossg = edge_cycle;
            if (first_public_x_nossg < 0 && (^fm_nossg_l) === 1'bx)
                first_public_x_nossg = edge_cycle;

            if (first_op_x_6 < 0 && (^dut_2612.op_result_hd) === 1'bx)
                first_op_x_6 = edge_cycle;
            if (first_acc_x_6 < 0 && (^(dut_2612.gen_pcm_acc.accumulator_block[0].u_acc.u_acc.acc)) === 1'bx)
                first_acc_x_6 = edge_cycle;
            if (first_public_x_6 < 0 && ((^fm_2612_l) === 1'bx || (^fm_2612_r) === 1'bx))
                first_public_x_6 = edge_cycle;

            if (!mismatch_3ch && (dut_ssg.op_result_hd !== dut_nossg.op_result_hd ||
                                  dut_ssg.gen_2203_acc.u_acc.u_mono.acc !== dut_nossg.gen_2203_acc.u_acc.u_mono.acc ||
                                  dut_ssg.gen_2203_acc.u_acc.u_mono.snd !== dut_nossg.gen_2203_acc.u_acc.u_mono.snd)) begin
                mismatch_3ch = 1'b1;
                $display("THREE_CH_MISMATCH cycle=%0d time=%0t edge=PRE_NBA", edge_cycle, $time);
            end

            #1;
            check_detailed_x("POST_NBA", edge_cycle);
            if (fm_ssg_l !== fm_ssg_r || dut_ssg.snd_left !== dut_ssg.snd_right)
                public_mismatch = 1'b1;
            if (edge_cycle == 465 &&
                (^dut_ssg.gen_2203_acc.u_acc.u_mono.acc) === 1'bx)
                $fatal(1, "mono accumulator unknown at cycle 465");
            if (edge_cycle == 609 &&
                (^dut_ssg.gen_2203_acc.u_acc.u_mono.snd) === 1'bx)
                $fatal(1, "mono snd unknown at cycle 609");
            if (edge_cycle == 610 &&
                (^{fm_ssg_l,fm_ssg_r,dut_ssg.snd_left,dut_ssg.snd_right}) === 1'bx)
                $fatal(1, "public output unknown at cycle 610");
            if (dut_ssg.clk_en && edge_cycle <= 650)
                trace_acc("POST_NBA", edge_cycle);

            if (first_acc_x_3 < 0 && (^dut_ssg.gen_2203_acc.u_acc.u_mono.acc) === 1'bx)
                first_acc_x_3 = edge_cycle;
            if (first_snd_x_3 < 0 && (^dut_ssg.gen_2203_acc.u_acc.u_mono.snd) === 1'bx)
                first_snd_x_3 = edge_cycle;
            if (first_public_x_3 < 0 && (^fm_ssg_l) === 1'bx)
                first_public_x_3 = edge_cycle;
            if (acc_was_x_3 && acc_known_again_3 < 0 && (^dut_ssg.gen_2203_acc.u_acc.u_mono.acc) !== 1'bx)
                acc_known_again_3 = edge_cycle;
            if ((^dut_ssg.gen_2203_acc.u_acc.u_mono.acc) === 1'bx)
                acc_was_x_3 = 1'b1;
            if (snd_was_x_3 && snd_known_again_3 < 0 && (^dut_ssg.gen_2203_acc.u_acc.u_mono.snd) !== 1'bx)
                snd_known_again_3 = edge_cycle;
            if ((^dut_ssg.gen_2203_acc.u_acc.u_mono.snd) === 1'bx)
                snd_was_x_3 = 1'b1;

            if (dut_ssg.clk_en &&
                (prev_acc_x_3 != ((^dut_ssg.gen_2203_acc.u_acc.u_mono.acc) === 1'bx) ||
                 prev_snd_x_3 != ((^dut_ssg.gen_2203_acc.u_acc.u_mono.snd) === 1'bx) ||
                 prev_op_x_3 != ((^dut_ssg.op_result_hd) === 1'bx))) begin
                $display("KNOWNNESS_CHANGE cycle=%0d time=%0t edge=POST_NBA op_x=%0d acc_x=%0d snd_x=%0d op=%h acc=%h snd=%h",
                         edge_cycle, $time,
                         ((^dut_ssg.op_result_hd) === 1'bx),
                         ((^dut_ssg.gen_2203_acc.u_acc.u_mono.acc) === 1'bx),
                         ((^dut_ssg.gen_2203_acc.u_acc.u_mono.snd) === 1'bx),
                         dut_ssg.op_result_hd,
                         dut_ssg.gen_2203_acc.u_acc.u_mono.acc,
                         dut_ssg.gen_2203_acc.u_acc.u_mono.snd);
            end
            if (dut_ssg.clk_en) begin
                prev_acc_x_3 = ((^dut_ssg.gen_2203_acc.u_acc.u_mono.acc) === 1'bx);
                prev_snd_x_3 = ((^dut_ssg.gen_2203_acc.u_acc.u_mono.snd) === 1'bx);
                prev_op_x_3 = ((^dut_ssg.op_result_hd) === 1'bx);
            end

            if (first_acc_x_nossg < 0 && (^dut_nossg.gen_2203_acc.u_acc.u_mono.acc) === 1'bx)
                first_acc_x_nossg = edge_cycle;
            if (first_snd_x_nossg < 0 && (^dut_nossg.gen_2203_acc.u_acc.u_mono.snd) === 1'bx)
                first_snd_x_nossg = edge_cycle;
            if (first_public_x_nossg < 0 && (^fm_nossg_l) === 1'bx)
                first_public_x_nossg = edge_cycle;

            if (first_acc_x_6 < 0 && (^(dut_2612.gen_pcm_acc.accumulator_block[0].u_acc.u_acc.acc)) === 1'bx)
                first_acc_x_6 = edge_cycle;
            if (first_public_x_6 < 0 && ((^fm_2612_l) === 1'bx || (^fm_2612_r) === 1'bx))
                first_public_x_6 = edge_cycle;
        end
    end

    initial begin
        $display("WIDTH_AUDIT bits_top_op_result_hd=%0d bits_op_full_result=%0d",
                 $bits(dut_ssg.op_result_hd),
                 $bits(dut_ssg.u_op.full_result));
        repeat (24) @(posedge clk);
        @(negedge clk);
        monitor = 1'b1;
        rst = 1'b0;
        #1;
        $display("RESET_RELEASE cycle=%0d time=%0t op_hd=%h acc=%h snd=%h fm=%h",
                 sys_cycle, $time, dut_ssg.op_result_hd,
                 dut_ssg.gen_2203_acc.u_acc.u_mono.acc,
                 dut_ssg.gen_2203_acc.u_acc.u_mono.snd, fm_ssg_l);
        repeat (6000) @(posedge clk);
        #2;
        $display("SUMMARY 3CH_SSG op_x=%0d acc_x=%0d snd_x=%0d public_x=%0d acc_known_again=%0d snd_known_again=%0d first_zero=%0d first_sum=%0d first_op_known=%0d",
                 first_op_x_3, first_acc_x_3, first_snd_x_3,
                 first_public_x_3, acc_known_again_3, snd_known_again_3, first_zero_3,
                 first_sum_3, first_op_known_3);
        $display("SUMMARY 3CH_NOSSG op_x=%0d acc_x=%0d snd_x=%0d public_x=%0d",
                 first_op_x_nossg, first_acc_x_nossg,
                 first_snd_x_nossg, first_public_x_nossg);
        $display("SUMMARY 6CH op_x=%0d acc0_x=%0d public_x=%0d final_op=%h final_acc0=%h final_left=%h final_right=%h",
                 first_op_x_6, first_acc_x_6, first_public_x_6,
                 dut_2612.op_result_hd,
                 dut_2612.gen_pcm_acc.accumulator_block[0].u_acc.u_acc.acc,
                 fm_2612_l, fm_2612_r);
        $display("SUMMARY three_ch_internal_mismatch=%0d", mismatch_3ch);
        if ({sx_zero,sx_sum,sx_strobes,sx_alg,sx_curch,sx_curop,
             sx_selected,sx_keyon,sx_fb,sx_freq,sx_opparams,
             sx_opresult,sx_ophd,sx_opinternal,sx_opxii,sx_exp,sx_logsin,
             sx_egatten,sx_pgphase,sx_pm_in,sx_pm_out,sx_feedback,
             sx_modinput,sx_opdelay,sx_pgstate,sx_egstate,sx_current,
             sx_next,sx_acc,sx_snd,sx_clken,sx_public,sx_combined} != 0)
            $fatal(1, "YM2203 startup first-X closure failed");
        if (first_op_x_3 != -1 || first_acc_x_3 != -1 ||
            first_snd_x_3 != -1 || first_public_x_3 != -1 ||
            first_op_x_nossg != -1 || first_acc_x_nossg != -1 ||
            first_snd_x_nossg != -1 || first_public_x_nossg != -1 ||
            mismatch_3ch || public_mismatch)
            $fatal(1, "YM2203 startup regression failed");
        $display("PASS_STARTUP no_x_cycles=6000 mono_lr_match=1");
        $finish;
    end
endmodule
