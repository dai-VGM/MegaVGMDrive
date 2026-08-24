/* This file is part of JT12.


    JT12 program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JT12 program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JT12.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 21-03-2019

    Each channel can use the full range of the DAC as they do not
    get summed in the real chip.

    Operator data is summed up without adding extra bits. This is
    the case of real YM3438, which was used on Megadrive 2 models.


*/

// YM2610
// ADPCM inputs
// Full OP resolution
// No PCM
// 4 OP channels in YM2610 mode; six in YM2610B mode

// ADPCM-A input is added for the time assigned to FM channel 0_10 (i.e. 3)

// HW-0 accumulator derivative.  The default mode preserves the pristine
// four-audible-FM-channel YM2610 mix.  YM2610B mode adds the existing FM
// carrier in the two ADPCM insertion slots, with saturation before the
// existing per-frame stereo accumulators.
module ym2610_hw0_jt10_acc(
    input               rst,
    input               clk,
    input               clk_en /* synthesis direct_enable */,
    input               ym2610b_mode,
    input signed [13:0] op_result,
    input        [ 1:0] rl,
    input               zero,
    input               s1_enters,
    input               s2_enters,
    input               s3_enters,
    input               s4_enters,
    input       [2:0]   cur_ch,
    input       [1:0]   cur_op,
    input   [2:0]       alg,
    input signed [15:0] adpcmA_l,
    input signed [15:0] adpcmA_r,
    input signed [15:0] adpcmB_l,
    input signed [15:0] adpcmB_r,
    // combined output
    output signed [15:0] left,
    output signed [15:0] right
);

reg sum_en;

always @(*) begin
    case ( alg )
        default: sum_en = s4_enters;
        3'd4: sum_en = s2_enters | s4_enters;
        3'd5,3'd6: sum_en = ~s1_enters;
        3'd7: sum_en = 1'b1;
    endcase
end

wire left_en = rl[1];
wire right_en= rl[0];
wire signed [15:0] opext = { {2{op_result[13]}}, op_result };
wire signed [15:0] fm_input = opext >>> 1;
wire signed [15:0] adpcmA_mix_l = (adpcmA_l <<< 2) + (adpcmA_l <<< 1);
wire signed [15:0] adpcmA_mix_r = (adpcmA_r <<< 2) + (adpcmA_r <<< 1);
wire signed [15:0] adpcmB_mix_l = adpcmB_l >>> 1;
wire signed [15:0] adpcmB_mix_r = adpcmB_r >>> 1;
reg  signed [15:0] acc_input_l, acc_input_r;
reg acc_en_l, acc_en_r;
wire fm_en_l = sum_en & left_en;
wire fm_en_r = sum_en & right_en;

function signed [15:0] saturate_17_to_16;
    input signed [16:0] value;
    begin
        if (value > 17'sd32767)
            saturate_17_to_16 = 16'sh7fff;
        else if (value < -17'sd32768)
            saturate_17_to_16 = 16'sh8000;
        else
            saturate_17_to_16 = value[15:0];
    end
endfunction

// YM2610 mode:
// uses channels 0 and 4 for ADPCM data, throwing away FM data for those channels
// reference: YM2610 Application Notes.
always @(*)
    case( {cur_op,cur_ch} )
        {2'd0,3'd0}: begin // ADPCM-A:
            if (ym2610b_mode) begin
                acc_input_l = saturate_17_to_16(
                    $signed({adpcmA_mix_l[15], adpcmA_mix_l}) +
                    (fm_en_l ? $signed({fm_input[15], fm_input}) : 17'sd0));
                acc_input_r = saturate_17_to_16(
                    $signed({adpcmA_mix_r[15], adpcmA_mix_r}) +
                    (fm_en_r ? $signed({fm_input[15], fm_input}) : 17'sd0));
            end else begin
                acc_input_l = adpcmA_mix_l;
                acc_input_r = adpcmA_mix_r;
            end
            `ifndef NOMIX
            acc_en_l    = 1'b1;
            acc_en_r    = 1'b1;
            `else
            acc_en_l    = ym2610b_mode && fm_en_l;
            acc_en_r    = ym2610b_mode && fm_en_r;
            if (ym2610b_mode) begin
                acc_input_l = fm_input;
                acc_input_r = fm_input;
            end
            `endif
        end
        {2'd0,3'd4}: begin // ADPCM-B:
            if (ym2610b_mode) begin
                acc_input_l = saturate_17_to_16(
                    $signed({adpcmB_mix_l[15], adpcmB_mix_l}) +
                    (fm_en_l ? $signed({fm_input[15], fm_input}) : 17'sd0));
                acc_input_r = saturate_17_to_16(
                    $signed({adpcmB_mix_r[15], adpcmB_mix_r}) +
                    (fm_en_r ? $signed({fm_input[15], fm_input}) : 17'sd0));
            end else begin
                acc_input_l = adpcmB_mix_l;
                acc_input_r = adpcmB_mix_r;
            end
            `ifndef NOMIX
            acc_en_l    = 1'b1;
            acc_en_r    = 1'b1;
            `else
            acc_en_l    = ym2610b_mode && fm_en_l;
            acc_en_r    = ym2610b_mode && fm_en_r;
            if (ym2610b_mode) begin
                acc_input_l = fm_input;
                acc_input_r = fm_input;
            end
            `endif
        end
        default: begin
            // Note by Jose Tejada:
            // I don't think we should divide down the FM output
            // but someone was looking at the balance of the different
            // channels and made this arrangement
            // I suppose ADPCM-A would saturate if taken up a factor of 8 instead of 4
            // I'll leave it as it is but I think it is worth revisiting this:
            acc_input_l = fm_input;
            acc_input_r = fm_input;
            acc_en_l    = fm_en_l;
            acc_en_r    = fm_en_r;
        end
    endcase

// Continuous output

jt12_single_acc #(.win(16),.wout(16),.use_rst(1)) u_left(
    .rst        ( rst            ),
    .clk        ( clk            ),
    .clk_en     ( clk_en         ),
    .op_result  ( acc_input_l    ),
    .sum_en     ( acc_en_l       ),
    .zero       ( zero           ),
    .snd        ( left           )
);

jt12_single_acc #(.win(16),.wout(16),.use_rst(1)) u_right(
    .rst        ( rst            ),
    .clk        ( clk            ),
    .clk_en     ( clk_en         ),
    .op_result  ( acc_input_r    ),
    .sum_en     ( acc_en_r       ),
    .zero       ( zero           ),
    .snd        ( right          )
);

`ifdef SIMULATION
// Dump each channel independently
// It dumps values in decimal, left and right
integer f0,f1,f2,f4,f5,f6;
reg signed [15:0] sum_l[7], sum_r[7];

initial begin
    f0=$fopen("fm0.raw","w");
    f1=$fopen("fm1.raw","w");
    f2=$fopen("fm2.raw","w");
    f4=$fopen("fm4.raw","w");
    f5=$fopen("fm5.raw","w");
    f6=$fopen("fm6.raw","w");
end

always @(posedge clk) begin
    if(cur_op==2'b0) begin
        sum_l[cur_ch] <= acc_en_l ? acc_input_l : 16'd0;
        sum_r[cur_ch] <= acc_en_r ? acc_input_r : 16'd0;
    end else begin
        sum_l[cur_ch] <= sum_l[cur_ch] + (acc_en_l ? acc_input_l : 16'd0);
        sum_r[cur_ch] <= sum_r[cur_ch] + (acc_en_r ? acc_input_r : 16'd0);
    end
end

always @(posedge zero) begin
    $fwrite(f0,"%d,%d\n", sum_l[0], sum_r[0]);
    $fwrite(f1,"%d,%d\n", sum_l[1], sum_r[1]);
    $fwrite(f2,"%d,%d\n", sum_l[2], sum_r[2]);
    $fwrite(f4,"%d,%d\n", sum_l[4], sum_r[4]);
    $fwrite(f5,"%d,%d\n", sum_l[5], sum_r[5]);
    $fwrite(f6,"%d,%d\n", sum_l[6], sum_r[6]);
end
`endif

endmodule
