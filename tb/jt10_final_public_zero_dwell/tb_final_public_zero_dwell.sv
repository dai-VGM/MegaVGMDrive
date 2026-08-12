`timescale 1ns/1ps
`ifndef SMODE
`define SMODE 3
`endif
module tb_final_public_zero_dwell;
 logic clk=0,reset=1,public_sample=0,mute=0,term=0; logic signed [15:0] l=0,r=0; logic [31:0] ma=0,ps=0; logic [3:0] phase=0; logic [6:0] state=0; logic armed,complete,short,br; logic [31:0] count;
 always #5 clk=~clk;
 final_public_zero_dwell #(.MODE(`SMODE)) dut(.clk(clk),.reset(reset),.public_sample(public_sample),.external_mute(mute),.public_left(l),.public_right(r),.semantic_mute_assertions(ma),.semantic_post_samples(ps),.phase(phase),.state(state),.terminal_check(term),.armed(armed),.complete(complete),.short(short),.nonzero_break(br),.count(count));
 task sample_edge(input integer a,input integer b); begin @(negedge clk); l=a;r=b;public_sample=1;@(negedge clk);public_sample=0; end endtask
 integer i;
 initial begin
  repeat(2) @(negedge clk); reset=0;
  for(i=0;i<1000;i=i+1) sample_edge(0,0); if(count!=0) $fatal(1,"P1");
  ma=64; mute=1; ps=64; @(negedge clk);
  for(i=0;i<511;i=i+1) sample_edge(0,0); if(complete||count!=511) $fatal(1,"P2");
  sample_edge(0,0); if(!complete||count!=512) $fatal(1,"P3"); sample_edge(0,0); if(count!=512) $fatal(1,"P4");
  reset=1;@(negedge clk);reset=0;ma=64;mute=1;ps=64;@(negedge clk);
  for(i=0;i<300;i=i+1) sample_edge(0,0); sample_edge(1,0); for(i=0;i<511;i=i+1) sample_edge(0,0); if(complete||count!=511||!br) $fatal(1,"P5"); sample_edge(0,0); if(!complete) $fatal(1,"P6");
  $display("FINAL_DWELL_UNIT_PASS mode=%0d count=%0d",`SMODE,count);$finish;
 end
endmodule
