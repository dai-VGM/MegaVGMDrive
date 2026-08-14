`timescale 1ns/1ps
module tb_natural_start_matrix;
    import semantic_timeline_authority_pkg::*;
    logic clk=0, reset=1, phase7=0, b_chon=0, terminal=0;
    logic valid=0, loop=0; logic [3:0] family=0; logic [2:0] attempt=0; logic [1:0] kind=K_START;
    integer b0_fail,b0_starts,b1_fail,b1_starts,b2_fail,b2_starts,b2_dup,b2_miss,b2_ord,b2_third,b2_n1,b2_n2,b2_l0,b2_l1;
    logic b2_complete;
    natural_start_legacy_monitor #(.LIMIT(4)) b0(.clk,.reset,.phase7,.b_chon,.failures(b0_fail),.starts(b0_starts));
    natural_start_legacy_monitor #(.LIMIT(12)) b1(.clk,.reset,.phase7,.b_chon,.failures(b1_fail),.starts(b1_starts));
    natural_start_tuple_monitor b2(.clk,.reset,.terminal,.token_valid(valid),.token_loop(loop),.token_family(family),.token_attempt(attempt),.token_kind(kind),.failures(b2_fail),.starts(b2_starts),.duplicate_errors(b2_dup),.missing_errors(b2_miss),.order_errors(b2_ord),.third_loop_errors(b2_third),.n1_starts(b2_n1),.n2_starts(b2_n2),.loop0_starts(b2_l0),.loop1_starts(b2_l1),.complete(b2_complete));
    always #5 clk=~clk;
    task automatic raw_start; begin phase7=1; b_chon=1; @(posedge clk); #1; b_chon=0; @(posedge clk); #1; end endtask
    task automatic token(input logic lp,input logic [3:0] fam,input logic [2:0] att); begin loop=lp;family=fam;attempt=att;kind=K_START;valid=1;@(posedge clk);#1;valid=0;@(posedge clk);#1;end endtask
    task automatic legal12; integer a; begin for(a=0;a<3;a=a+1) token(0,F_NATURAL1,a); for(a=0;a<3;a=a+1) token(0,F_NATURAL2,a); for(a=0;a<3;a=a+1) token(1,F_NATURAL1,a); for(a=0;a<3;a=a+1) token(1,F_NATURAL2,a); end endtask
    initial begin
      repeat(2) @(posedge clk); reset=0;
      repeat(12) raw_start();
      legal12();
      if(b0_fail!=8 || b1_fail!=0 || b2_fail!=0 || !b2_complete || b2_starts!=12 || b2_n1!=6 || b2_n2!=6 || b2_l0!=6 || b2_l1!=6) $fatal(1,"B matrix positive mismatch");
      $display("LB_MATRIX_POSITIVE B0=8 B1=0 B2=0 starts=12 n1=6 n2=6 l0=6 l1=6");
      // B2 negatives are isolated with reset changes away from its sampling edge.
      @(negedge clk); reset=1; @(posedge clk); @(negedge clk); reset=0; token(0,F_NATURAL1,0); token(0,F_NATURAL1,0); if(b2_dup!=1) $fatal(1,"duplicate missed");
      @(negedge clk); reset=1; @(posedge clk); @(negedge clk); reset=0; token(0,F_NATURAL1,3); if(b2_ord!=1) $fatal(1,"bad attempt missed");
      @(negedge clk); reset=1; @(posedge clk); @(negedge clk); reset=0; token(1,F_NATURAL2,0); terminal=1; @(posedge clk); #1; terminal=0; if(b2_miss==0) $fatal(1,"missing missed");
      $display("LB_MATRIX_NEGATIVE duplicate=1 bad_attempt=1 missing=1");
      $finish;
    end
endmodule
