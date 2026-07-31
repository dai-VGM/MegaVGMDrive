`timescale 1ns/1ps

module tb_jt10_phase1c_ch2_fm_tone;
    tb_jt10_phase1a_fm_tone #(
        .TARGET_PORT(0),
        .TARGET_ENCODING(2),
        .PHASE1C_MODE(1)
    ) test();
endmodule
