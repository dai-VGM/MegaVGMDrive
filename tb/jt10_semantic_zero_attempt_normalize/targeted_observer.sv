`timescale 1ns/1ps

// Read-only early-stop observer layered on the frozen epoch-rearm graph.
module jt10_semantic_zero_attempt_targeted_top;
    import semantic_timeline_authority_pkg::*;

    semantic_timeline_epoch_rearm_integrated_check #(
        .TARGETED_ONLY(0)
    ) check();

    logic fm_start_seen = 1'b0;
    logic fm_stop_seen = 1'b0;
    logic fm_zero_seen = 1'b0;
    logic ssg_start_seen = 1'b0;
    logic ssg_stop_seen = 1'b0;
    logic ssg_zero_seen = 1'b0;
    integer observed_events = 0;

    task automatic check_frozen_errors;
        begin
            if (check.core.p_failures != 0 || check.core.r_failures != 0 ||
                check.core.selector_failures != 0 ||
                check.core.epoch_errors != 0 || check.core.h_failures != 0 ||
                check.core.if_failures != 0 ||
                check.core.global_id_mismatches != 0 ||
                check.core.target_duplicate_drop != 0 ||
                check.core.seam_xz != 0 ||
                check.core.base.semantic_silence_errors != 0 ||
                check.core.base.semantic_missing_pulses != 0 ||
                check.core.base.semantic_duplicate_pulses != 0 ||
                check.core.base.semantic_overlap_pulses != 0 ||
                check.core.base.semantic_order_errors != 0 ||
                check.core.base.cadence_errors != 0 ||
                check.core.base.width_errors != 0 ||
                check.core.base.drops != 0 ||
                check.core.base.duplicates != 0 ||
                check.core.base.tick_missed != 0 ||
                check.core.base.tick_duplicates != 0 ||
                check.core.base.debug_busy_timeout ||
                check.core.base.debug_write_while_busy ||
                check.core.base.debug_phase_error ||
                check.core.base.debug_zero_timeout ||
                check.core.base.unexpected_adpcm_requests != 0 ||
                check.core.base.x_count != 0 || check.timeline_xz != 0)
                $fatal(1, "targeted frozen graph regression");
        end
    endtask

    always @(posedge check.core.base.clk) begin
        #6;
        if (!check.core.base.reset && check.event_valid && check.event_loop &&
            (check.event_family == F_FM || check.event_family == F_SSG)) begin
            observed_events = observed_events + 1;
            if (check.event_attempt != 0 ||
                check.core.base.dut.u_sequencer.diag_attempt_index != 2 ||
                check.adapter_failures != 0 || check.timeline_failures != 0)
                $fatal(1, "targeted normalized tuple mismatch family=%0d kind=%0d attempt=%0d raw=%0d A1=%0d R3=%0d",
                       check.event_family, check.event_kind,
                       check.event_attempt,
                       check.core.base.dut.u_sequencer.diag_attempt_index,
                       check.adapter_failures, check.timeline_failures);

            if (check.event_family == F_FM) begin
                case (check.event_kind)
                    K_START: begin
                        fm_start_seen = 1'b1;
                        if (check.timeline_start != 33)
                            $fatal(1, "FM START was not accepted");
                    end
                    K_STOP: begin
                        fm_stop_seen = 1'b1;
                        if (!fm_start_seen || check.timeline_stop != 33)
                            $fatal(1, "FM STOP was not accepted");
                    end
                    K_ZERO: begin
                        fm_zero_seen = 1'b1;
                        if (!fm_stop_seen || check.timeline_zero != 33 ||
                            check.u_timeline.stage != 3'd0 ||
                            check.u_timeline.expected_family != F_SSG)
                            $fatal(1, "FM ZERO was not accepted");
                        $display("TARGETED_FM_ZERO_PASS cycle=%0d raw=2 semantic=0 code4=0 publish=1 R3_accept=1",
                                 check.core.base.system_cycle);
                    end
                endcase
            end else begin
                case (check.event_kind)
                    K_START: begin
                        ssg_start_seen = 1'b1;
                        if (!fm_zero_seen || check.timeline_start != 34 ||
                            check.timeline_first_failure == 13)
                            $fatal(1, "SSG START derivative code13 remains");
                    end
                    K_STOP: begin
                        ssg_stop_seen = 1'b1;
                        if (!ssg_start_seen || check.timeline_stop != 34)
                            $fatal(1, "SSG STOP was not accepted");
                    end
                    K_ZERO: begin
                        ssg_zero_seen = 1'b1;
                        if (!ssg_stop_seen || check.timeline_zero != 34 ||
                            check.u_timeline.stage != 3'd0 ||
                            check.u_timeline.expected_family != F_A0)
                            $fatal(1, "SSG ZERO was not accepted");
                        check_frozen_errors();
                        if (!fm_start_seen || !fm_stop_seen || !fm_zero_seen ||
                            !ssg_start_seen || !ssg_stop_seen ||
                            observed_events != 6)
                            $fatal(1, "targeted six-event inventory mismatch");
                        $display("TARGETED_SSG_ZERO_PASS cycle=%0d raw=2 semantic=0 code4=0 publish=1 R3_accept=1",
                                 check.core.base.system_cycle);
                        $display("ZERO_ATTEMPT_TARGETED_PASS FM=3/3 SSG=3/3 A1=0 R3=0 code13=0 P=0 R=0 S3=0 V3=0 H4=0 XZ=0");
                        $finish;
                    end
                endcase
            end
        end
    end

    initial begin
        wait (!check.core.base.reset);
        wait (check.core.base.system_cycle >= 26_000_000);
        $fatal(1, "targeted observer timeout events=%0d", observed_events);
    end
endmodule
