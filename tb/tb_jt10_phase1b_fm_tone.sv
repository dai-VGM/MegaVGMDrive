`timescale 1ns/1ps

module tb_jt10_phase1b_fm_tone;
    tb_jt10_phase1a_fm_tone #(
        .TARGET_PORT(1),
        .PHASE1B_MODE(1)
    ) test();
endmodule
