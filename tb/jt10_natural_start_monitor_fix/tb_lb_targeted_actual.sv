`timescale 1ns/1ps
module jt10_lb_targeted_actual;
    import semantic_timeline_authority_pkg::*;
    jt10_final_public_zero_v3_wrapper core();
    logic event_valid,event_loop; logic [3:0] event_family; logic [2:0] event_attempt; logic [1:0] event_kind;
    logic [6:0] event_state; logic [3:0] event_phase; logic event_active; logic [4:0] event_program;
    integer a_start,a_stop,a_zero,a_fail; logic [7:0] a_first;
    integer lb_fail,lb_starts,lb_dup,lb_miss,lb_order,lb_third,lb_n1,lb_n2,lb_l0,lb_l1;
    logic lb_complete,reported;
    // This is the pre-R3 validated semantic token seam; the L-B monitor never
    // derives family/attempt/loop from raw b_chon or sequencer state.
    semantic_timeline_adapter u_adapter(
      .clk(core.base.clk),.reset(core.base.reset),.loop_epoch(core.epoch),
      .state(core.base.debug_segment_state),.phase(core.base.debug_phase),.raw_attempt(core.base.dut.u_sequencer.diag_attempt_index),
      .program_active(core.base.dut.u_sequencer.program_active),.program_id(core.base.dut.u_sequencer.program_id),.external_mute(core.base.debug_external_mute),
      .event_valid,.event_loop,.event_family,.event_attempt,.event_kind,.event_state,.event_phase,.event_program_active(event_active),.event_program,
      .start_events(a_start),.stop_events(a_stop),.zero_events(a_zero),.failures(a_fail),.first_failure_code(a_first));
    natural_start_tuple_monitor b3(.clk(core.base.clk),.reset(core.base.reset),.terminal(1'b0),.token_valid(event_valid),.token_loop(event_loop),.token_family(event_family),.token_attempt(event_attempt),.token_kind(event_kind),.failures(lb_fail),.starts(lb_starts),.duplicate_errors(lb_dup),.missing_errors(lb_miss),.order_errors(lb_order),.third_loop_errors(lb_third),.n1_starts(lb_n1),.n2_starts(lb_n2),.loop0_starts(lb_l0),.loop1_starts(lb_l1),.complete(lb_complete));
    always @(posedge core.base.clk) begin
      #5;
      if(core.base.reset) reported=0;
      else if(lb_complete && !reported) begin
        reported=1;
        if(lb_fail!=0 || lb_starts!=12 || lb_n1!=6 || lb_n2!=6 || lb_l0!=6 || lb_l1!=6 || lb_dup!=0 || lb_miss!=0 || lb_order!=0 || lb_third!=0 || a_fail!=0 || core.p_failures!=0 || core.r_failures!=0 || core.h_failures!=0 || core.epoch_errors!=0 || core.base.semantic_silence_errors!=0 || core.base.cadence_errors!=0 || core.base.final_dwell_break) begin
          $display("LB_NATURAL_TARGETED_FAIL natural_starts=%0d N1_attempts=%0d N2_attempts=%0d loop0=%0d loop1=%0d duplicate=%0d missing=%0d order=%0d third_loop=%0d LB_failures=%0d A1=%0d P3_errors=%0d R3=%0d S3=%0d V3=%0d H4=%0d FINAL_DWELL=%0d",lb_starts,lb_n1,lb_n2,lb_l0,lb_l1,lb_dup,lb_miss,lb_order,lb_third,lb_fail,a_fail,0,core.r_failures,core.base.semantic_silence_errors,core.epoch_errors,core.h_failures,core.base.final_dwell_break);
          #1; $fatal(1,"L-B targeted failure");
        end else begin
          $display("LB_NATURAL_TARGETED_PASS natural_starts=12 N1_attempts=6 N2_attempts=6 loop0=6 loop1=6 duplicate=0 missing=0 order=0 third_loop=0 LB_failures=0 P3_errors=0 A1=0 R3=0 S3=0 V3=0 H4=0 FINAL_DWELL=0");
          #1; $finish;
        end
      end
    end
    initial begin wait(!core.base.reset); wait(core.base.system_cycle>45000000); if(!reported) begin $display("LB_NATURAL_TARGETED_FAIL reason=TIMEOUT starts=%0d",lb_starts); #1;$fatal(1,"L-B timeout");end end
endmodule
