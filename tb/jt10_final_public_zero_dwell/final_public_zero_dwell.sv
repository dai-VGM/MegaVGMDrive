`timescale 1ns/1ps

// Versioned S4-side checker.  It consumes only public S3 summary counters;
// it neither changes nor reproduces semantic-silence authority.
module final_public_zero_dwell #(
    parameter integer MODE = 3,
    parameter integer FINAL_POST_INDEX = 64,
    parameter integer REQUIRED_SAMPLES = 512
) (
    input logic clk, input logic reset,
    input logic public_sample, input logic external_mute,
    input logic signed [15:0] public_left, public_right,
    input logic [31:0] semantic_mute_assertions,
    input logic [31:0] semantic_post_samples,
    input logic [3:0] phase, input logic [6:0] state,
    input logic terminal_check,
    output logic armed, output logic complete, output logic short,
    output logic nonzero_break, output logic [31:0] count
);
    logic previous_public;
    logic previous_mute;
    logic [31:0] previous_post;
    logic public_rise;
    always @(posedge clk) begin
        public_rise = public_sample && !previous_public;
        if (reset) begin
            armed <= 0; complete <= 0; short <= 0; nonzero_break <= 0;
            count <= 0; previous_public <= 0; previous_mute <= 1;
            previous_post <= 0;
        end else begin
            if (MODE == 0) begin
                if (public_rise && phase == 0 && state == 65) count <= count + 1;
                if (terminal_check && count < REQUIRED_SAMPLES) short <= 1;
            end else begin
                if (!armed && ((MODE == 1 || MODE == 2) ?
                    (semantic_mute_assertions >= FINAL_POST_INDEX && external_mute) :
                    (semantic_post_samples >= FINAL_POST_INDEX))) armed <= 1;
                if (armed && public_rise && !complete) begin
                    if (MODE == 1 || (public_left == 0 && public_right == 0)) begin
                        if (count + 1 >= REQUIRED_SAMPLES) complete <= 1;
                        count <= count + 1;
                    end else begin
                        count <= 0; nonzero_break <= 1;
                    end
                end
                if (terminal_check && !complete) short <= 1;
            end
            previous_public <= public_sample;
            previous_mute <= external_mute;
            previous_post <= semantic_post_samples;
        end
    end
endmodule
