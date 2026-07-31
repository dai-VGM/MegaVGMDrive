`timescale 1ns/1ps

module tb_jt10_phase1c_ch6_fm_tone;
    tb_jt10_phase1a_fm_tone #(
        .TARGET_PORT(1),
        .TARGET_ENCODING(6),
        .PHASE1C_MODE(1)
    ) test();
endmodule
