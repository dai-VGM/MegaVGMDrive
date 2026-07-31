`timescale 1ns/1ps

module tb_jt10_phase2b_ssg_chB_tone;
    tb_jt10_phase2a_ssg_chA_tone #(
        .TARGET_CHANNEL(1)
    ) fixture();
endmodule

module tb_jt10_phase2b_ssg_chC_tone;
    tb_jt10_phase2a_ssg_chA_tone #(
        .TARGET_CHANNEL(2)
    ) fixture();
endmodule
