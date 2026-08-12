#!/usr/bin/env python3
from pathlib import Path
import hashlib

root=Path(__file__).resolve().parents[2]
out=root/'tb/jt10_final_public_zero_dwell/candidates'; out.mkdir(exist_ok=True)
s4=(root/'tb/jt10_semantic_silence_contract_fix/s4_integrated_semantic.sv').read_text()
assert hashlib.sha256(s4.encode()).hexdigest()=='4f23bd41fedeb753af7e50a94d14a8ed5a72f2c2cf7a622d5f07cf9b2610eeef'
s4=s4.replace('module tb_ym2610_hw0_top;', 'module jt10_final_public_zero_s4_top;',1)
s4=s4.replace('    integer final_zero_samples = 0;', '    integer final_zero_samples = 0; // retained legacy diagnostic\n    logic final_dwell_armed, final_dwell_complete, final_dwell_short, final_dwell_break;\n    logic [31:0] final_dwell_count;',1)
anchor='    initial begin\n        integer i, j;'
inst='''    final_public_zero_dwell #(.MODE(3), .FINAL_POST_INDEX(64), .REQUIRED_SAMPLES(512)) u_final_dwell (
        .clk(clk), .reset(reset), .public_sample(audio_sample),
        .external_mute(debug_external_mute), .public_left(audio_l), .public_right(audio_r),
        .semantic_mute_assertions(semantic_mute_assertions), .semantic_post_samples(semantic_post_samples),
        .phase(4'd0), .state(7'd0), .terminal_check(1'b0),
        .armed(final_dwell_armed), .complete(final_dwell_complete), .short(final_dwell_short),
        .nonzero_break(final_dwell_break), .count(final_dwell_count));

'''
assert anchor in s4
s4=s4.replace(anchor,inst+anchor,1)
s4=s4.replace('        repeat (32) @(posedge clk);','        wait (final_dwell_complete);\n        repeat (1) @(posedge clk);',1)
s4=s4.replace('if (final_zero_samples < 2*SIM_FINAL) fail("FINAL_SILENCE_SHORT");','if (!final_dwell_complete) fail("FINAL_SILENCE_SHORT");',1)
(out/'s3_final_dwell_top.sv').write_text(s4)
v3=(root/'tb/jt10_gatee_v3_epoch_integration/v3_epoch_integrated_harness.sv').read_text()
v3=v3.replace('module jt10_gatee_v3_epoch_integration;', 'module jt10_final_public_zero_v3_wrapper;',1).replace('    tb_ym2610_hw0_top base();','    jt10_final_public_zero_s4_top base();',1)
(out/'s3_v3_wrapper.sv').write_text(v3)
