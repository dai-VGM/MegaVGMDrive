// Hold only the audible YM2151 contribution at zero while a newly loaded VGM
// executes its timestamp-zero setup burst. JT51 clocks, writes, busy handling,
// and sample-valid timing remain unchanged.
module ym2151_prewait_audio_gate (
    input  logic                      clk,
    input  logic                      reset_or_rearm,
    input  logic                      positive_wait_active,
    input  logic signed [15:0]         raw_audio_l,
    input  logic signed [15:0]         raw_audio_r,
    output logic signed [15:0]         audible_audio_l,
    output logic signed [15:0]         audible_audio_r,
    output logic                      mute_active
);

    always_ff @(posedge clk) begin
        if (reset_or_rearm) begin
            mute_active <= 1'b1;
        end else if (positive_wait_active) begin
            mute_active <= 1'b0;
        end
    end

    always_comb begin
        audible_audio_l = mute_active ? 16'sd0 : raw_audio_l;
        audible_audio_r = mute_active ? 16'sd0 : raw_audio_r;
    end

endmodule
