`timescale 1ns/1ps
module jt10_p3_clean_isolated_target;
    import semantic_timeline_authority_pkg::*;
    jt10_p3_clean_isolated_v3_wrapper core();
    integer failures, phase_events, order_errors, missing_errors, duplicate_errors, third_loop_errors, visit_errors;
    integer v1,v2,v3,v4,v5,v6,v7,v8;
    logic terminal_checked, terminal_pass, reported;
    jt10_phase_monitor_contract #(.CORRECT_TOKEN(1'b1),.CORRECT_TERMINAL(1'b1)) p3 (
      .clk(core.base.clk),.reset(core.base.reset),.phase(core.base.debug_phase),.terminal(core.base.debug_restart_count>=2),.failures,
      .phase_events,.order_errors,.missing_errors,.duplicate_errors,.third_loop_errors,.visit_errors,.terminal_checked,.terminal_pass);
    logic event_valid,event_loop; logic [3:0] event_family; logic [2:0] event_attempt; logic [1:0] event_kind; logic [6:0] event_state; logic [3:0] event_phase; logic event_active; logic [4:0] event_program;
    integer a_start,a_stop,a_zero,a_fail; logic [7:0] a_first;
    integer b3_fail,b3_starts,b3_dup,b3_miss,b3_order,b3_third,b3_n1,b3_n2,b3_l0,b3_l1; logic b3_complete;
    semantic_timeline_adapter a1 (
      .clk(core.base.clk),.reset(core.base.reset),.loop_epoch(core.epoch),.state(core.base.debug_segment_state),.phase(core.base.debug_phase),.raw_attempt(core.base.dut.u_sequencer.diag_attempt_index),.program_active(core.base.dut.u_sequencer.program_active),.program_id(core.base.dut.u_sequencer.program_id),.external_mute(core.base.debug_external_mute),
      .event_valid,.event_loop,.event_family,.event_attempt,.event_kind,.event_state,.event_phase,.event_program_active(event_active),.event_program,.start_events(a_start),.stop_events(a_stop),.zero_events(a_zero),.failures(a_fail),.first_failure_code(a_first));
    natural_start_tuple_monitor b3 (
      .clk(core.base.clk),.reset(core.base.reset),.terminal(1'b0),.token_valid(event_valid),.token_loop(event_loop),.token_family(event_family),.token_attempt(event_attempt),.token_kind(event_kind),.failures(b3_fail),.starts(b3_starts),.duplicate_errors(b3_dup),.missing_errors(b3_miss),.order_errors(b3_order),.third_loop_errors(b3_third),.n1_starts(b3_n1),.n2_starts(b3_n2),.loop0_starts(b3_l0),.loop1_starts(b3_l1),.complete(b3_complete));
    always_comb begin v1=p3.visits[1];v2=p3.visits[2];v3=p3.visits[3];v4=p3.visits[4];v5=p3.visits[5];v6=p3.visits[6];v7=p3.visits[7];v8=p3.visits[8]; end
    always @(posedge core.base.clk) begin
      #6;
      if(core.base.reset) reported=0;
      else if(terminal_checked && !reported) begin
        reported=1;
        if(!terminal_pass || failures!=0 || phase_events!=16 || order_errors!=0 || missing_errors!=0 || duplicate_errors!=0 || third_loop_errors!=0 || visit_errors!=0 || v1!=2 || v2!=2 || v3!=2 || v4!=2 || v5!=2 || v6!=2 || v7!=2 || v8!=2 || a_fail!=0 || !b3_complete || b3_fail!=0 || b3_starts!=12 || b3_n1!=6 || b3_n2!=6 || b3_l0!=6 || b3_l1!=6 || b3_dup!=0 || b3_miss!=0 || core.p_failures!=0 || core.r_failures!=0 || core.h_failures!=0 || core.epoch_errors!=0 || core.selector_failures!=0 || core.base.semantic_silence_errors!=0 || core.base.cadence_errors!=0 || core.base.final_dwell_break || core.base.final_dwell_short) begin
          $display("P3_PHASE_TARGETED_FAIL events=%0d LP_A=%0d LP_C=%0d missing=%0d duplicate=%0d order=%0d third_loop=%0d terminal_checked=%0d terminal_pass=%0d A1=%0d R3=%0d B3=%0d S3=%0d V3=%0d H4=%0d FINAL_DWELL=%0d",phase_events,order_errors,missing_errors+visit_errors,missing_errors,duplicate_errors,order_errors,third_loop_errors,terminal_checked,terminal_pass,a_fail,core.r_failures,b3_fail,core.base.semantic_silence_errors,core.epoch_errors,core.h_failures,core.base.final_dwell_break||core.base.final_dwell_short);
          #1;$fatal(1,"P3 clean target failure");
        end else begin
          $display("P3_PHASE_TARGETED_PASS phase_events=16 visit1=2 visit2=2 visit3=2 visit4=2 visit5=2 visit6=2 visit7=2 visit8=2 LP_A=0 LP_C=0 missing=0 duplicate=0 order=0 third_loop=0 terminal_checked=1 terminal_pass=1 A1=0 R3=0 B3=0 S3=0 V3=0 H4=0 FINAL_DWELL=0");
          #1;$finish;
        end
      end
    end
    initial begin wait(!core.base.reset);wait(core.base.system_cycle>45000000);if(!reported) begin $display("P3_PHASE_TARGETED_FAIL reason=TIMEOUT events=%0d missing=%0d duplicate=%0d order=%0d third_loop=%0d terminal_checked=%0d terminal_pass=%0d",phase_events,missing_errors,duplicate_errors,order_errors,third_loop_errors,terminal_checked,terminal_pass);#1;$fatal(1,"P3 clean target timeout");end end
endmodule
