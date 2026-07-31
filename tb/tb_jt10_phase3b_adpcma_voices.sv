`timescale 1ns/1ps

// Thin tops around the single TARGET_VOICE-parameterized Phase 3 fixture.
// Each simulation contains exactly one active top and never keys on two
// ADPCM-A voices at the same time.
module tb_jt10_phase3b_adpcma_voice1;
    tb_jt10_phase3a_adpcma_voice0 #(
        .TARGET_VOICE(1)
    ) fixture();
endmodule

module tb_jt10_phase3b_adpcma_voice2;
    tb_jt10_phase3a_adpcma_voice0 #(
        .TARGET_VOICE(2)
    ) fixture();
endmodule

module tb_jt10_phase3b_adpcma_voice3;
    tb_jt10_phase3a_adpcma_voice0 #(
        .TARGET_VOICE(3)
    ) fixture();
endmodule

module tb_jt10_phase3b_adpcma_voice4;
    tb_jt10_phase3a_adpcma_voice0 #(
        .TARGET_VOICE(4)
    ) fixture();
endmodule

module tb_jt10_phase3b_adpcma_voice5;
    tb_jt10_phase3a_adpcma_voice0 #(
        .TARGET_VOICE(5)
    ) fixture();
endmodule
