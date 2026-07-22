// Final signed mixer used by the production mode-5 JT51/SegaPCM path when a
// YM2203 is present. The two existing lanes arrive after the established OSD
// selector and SegaPCM gain handling. YM2203 is sampled independently, held
// between core sample strobes, and added at unity gain before one final clamp.
module mode5_ym2203_audio_mixer (
    input  logic               clk,
    input  logic               reset,
    input  logic signed [15:0] existing_nonpcm_l,
    input  logic signed [15:0] existing_nonpcm_r,
    input  logic signed [15:0] segapcm_l,
    input  logic signed [15:0] segapcm_r,
    input  logic signed [15:0] ym2203_raw_l,
    input  logic signed [15:0] ym2203_raw_r,
    input  logic               ym2203_raw_sample_valid,
    input  logic               ym2203_chip_present,
    input  logic               ym2203_lane_enable,
    output logic signed [15:0] ym2203_held_l,
    output logic signed [15:0] ym2203_held_r,
    output wire signed [15:0]  ym2203_selected_l,
    output wire signed [15:0]  ym2203_selected_r,
    output wire signed [17:0]  mix_sum_l,
    output wire signed [17:0]  mix_sum_r,
    output wire                mix_clipped_l,
    output wire                mix_clipped_r,
    output wire signed [15:0]  audio_l,
    output wire signed [15:0]  audio_r
);
    function automatic logic signed [15:0] saturate_18_to_16(
        input logic signed [17:0] value
    );
        begin
            if (value[17:15] == 3'b000 || value[17:15] == 3'b111) begin
                saturate_18_to_16 = value[15:0];
            end else begin
                saturate_18_to_16 = value[17] ? 16'sh8000 : 16'sh7fff;
            end
        end
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            ym2203_held_l <= 16'sd0;
            ym2203_held_r <= 16'sd0;
        end else if (ym2203_raw_sample_valid) begin
            ym2203_held_l <= ym2203_raw_l;
            ym2203_held_r <= ym2203_raw_r;
        end
    end

    assign ym2203_selected_l =
        (ym2203_chip_present && ym2203_lane_enable) ?
        ym2203_held_l : 16'sd0;
    assign ym2203_selected_r =
        (ym2203_chip_present && ym2203_lane_enable) ?
        ym2203_held_r : 16'sd0;
    assign mix_sum_l = {{2{existing_nonpcm_l[15]}}, existing_nonpcm_l} +
                       {{2{segapcm_l[15]}}, segapcm_l} +
                       {{2{ym2203_selected_l[15]}}, ym2203_selected_l};
    assign mix_sum_r = {{2{existing_nonpcm_r[15]}}, existing_nonpcm_r} +
                       {{2{segapcm_r[15]}}, segapcm_r} +
                       {{2{ym2203_selected_r[15]}}, ym2203_selected_r};
    assign mix_clipped_l = !(mix_sum_l[17:15] == 3'b000 ||
                             mix_sum_l[17:15] == 3'b111);
    assign mix_clipped_r = !(mix_sum_r[17:15] == 3'b000 ||
                             mix_sum_r[17:15] == 3'b111);
    assign audio_l = saturate_18_to_16(mix_sum_l);
    assign audio_r = saturate_18_to_16(mix_sum_r);
endmodule
