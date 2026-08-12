`timescale 1ns/1ps
module jt10_final_public_zero_targeted;
 import semantic_timeline_authority_pkg::*;
 jt10_final_public_zero_v3_wrapper core();
 logic ev,eloop; logic [3:0] fam; logic [2:0] att; logic [1:0] kind; logic [6:0] es; logic [3:0] ep; logic epa; logic [4:0] epr; integer as,at,az,af; logic [7:0] ac;
 semantic_timeline_adapter a1(.clk(core.base.clk),.reset(core.base.reset),.loop_epoch(core.epoch),.state(core.base.debug_segment_state),.phase(core.base.debug_phase),.raw_attempt(core.base.dut.u_sequencer.diag_attempt_index),.program_active(core.base.dut.u_sequencer.program_active),.program_id(core.base.dut.u_sequencer.program_id),.external_mute(core.base.debug_external_mute),.event_valid(ev),.event_loop(eloop),.event_family(fam),.event_attempt(att),.event_kind(kind),.event_state(es),.event_phase(ep),.event_program_active(epa),.event_program(epr),.start_events(as),.stop_events(at),.zero_events(az),.failures(af),.first_failure_code(ac));
 always @(posedge core.base.clk) begin #6;
  if(!core.base.reset && core.base.final_dwell_complete) begin
   if(core.base.final_dwell_count!=512 || core.base.final_dwell_break || core.base.semantic_silence_errors!=0 || core.base.cadence_errors!=0 || af!=0 || core.p_failures!=0 || core.r_failures!=0 || core.h_failures!=0 || core.epoch_errors!=0 || core.selector_failures!=0 || core.seam_xz!=0) $fatal(1,"target regression");
   $display("FINAL_DWELL_TARGETED_PASS count=512 A1=0 P=0 R=0 S3=0 V3=0 H4=0"); $finish;
  end
 end
 initial begin wait(!core.base.reset); wait(core.base.system_cycle>45000000); $fatal(1,"dwell timeout count=%0d",core.base.final_dwell_count); end
endmodule
