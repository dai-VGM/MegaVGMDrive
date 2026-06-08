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
    Date: 11-12-2018
    
    Each channel can use the full range of the DAC as they do not
    get summed in the real chip.

    Operator data is summed up without adding extra bits. This is
    the case of real YM3438, which was used on Megadrive 2 models.

*/

/* rate up-scaler for FM+PSG channel
*/

module jt12_fm_uprate(
    input               rst,
    input               clk,
    input signed [15:0] fm_snd,
    input signed [11:0] psg_snd,
    input fm_en,  // enable FM
    input cen_1008,
    input cen_252,
    input cen_63,
    input cen_9,
    output signed [15:0] snd,     // Mixed sound at clk sample rate
    output reg [15:0] mixed_wrap_count
);

wire signed [15:0] fm2,fm3,fm4;
integer debug_uprate_x_count = 0;

reg signed [15:0] mixed;
wire signed [16:0] fm_snd_wide = fm_en ? {fm_snd[15], fm_snd} : 17'sd0;
wire signed [16:0] psg_snd_wide = {{2{psg_snd[11]}}, psg_snd, 3'b0};
wire signed [16:0] mixed_wide = fm_snd_wide + psg_snd_wide;
wire mixed_wrap = (mixed_wide > 17'sd32767) || (mixed_wide < -17'sd32768);

always @(posedge clk) begin
    if (rst) begin
        mixed <= 16'sd0;
        mixed_wrap_count <= 16'd0;
    end else begin
        mixed <= mixed_wide[15:0];
        if (cen_1008 && mixed_wrap && !(&mixed_wrap_count)) begin
            mixed_wrap_count <= mixed_wrap_count + 16'd1;
        end
    end
end

// 1008 --> 252 x4
jt12_interpol #(.calcw(17),.inw(16),.rate(4),.m(1),.n(1)) 
u_fm2(
    .clk    ( clk      ),
    .rst    ( rst      ),
    .cen_in ( cen_1008 ),
    .cen_out( cen_252  ),
    .snd_in ( mixed    ),
    .snd_out( fm2      )
);

// 252 --> 63 x4
jt12_interpol #(.calcw(19),.inw(16),.rate(4),.m(1),.n(3)) 
u_fm3(
    .clk    ( clk      ),
    .rst    ( rst      ),    
    .cen_in ( cen_252  ),
    .cen_out( cen_63   ),
    .snd_in ( fm2      ),
    .snd_out( fm3      )
);

// 63 --> 9 x7
jt12_interpol #(.calcw(21),.inw(16),.rate(7),.m(2),.n(2)) 
u_fm4(
    .clk    ( clk      ),
    .rst    ( rst      ),        
    .cen_in ( cen_63   ),
    .cen_out( cen_9    ),
    .snd_in ( fm3      ),
    .snd_out( fm4      )
);

// 9 --> 1 x9
jt12_interpol #(.calcw(21),.inw(16),.rate(9),.m(2),.n(2)) 
u_fm5(
    .clk    ( clk      ),
    .rst    ( rst      ),        
    .cen_in ( cen_9    ),
    .cen_out( 1'b1     ),
    .snd_in ( fm4      ),
    .snd_out( snd      )
);

`ifdef VERBOSE_TB_LOG
always @(posedge clk) begin
    if (!rst && debug_uprate_x_count < 40 &&
        (((^fm_snd) === 1'bx) || ((^psg_snd) === 1'bx) ||
         ((^mixed) === 1'bx) || ((^fm2) === 1'bx) ||
         ((^fm3) === 1'bx) || ((^fm4) === 1'bx) ||
         ((^snd) === 1'bx))) begin
        debug_uprate_x_count = debug_uprate_x_count + 1;
        $display("FM_UPRATE_X %m count=%0d time=%0t fm_snd=%0d psg_snd=%0d fm_en=%0b cen1008=%0b cen252=%0b cen63=%0b cen9=%0b mixed=%0d fm2=%0d fm3=%0d fm4=%0d snd=%0d",
                 debug_uprate_x_count, $time, fm_snd, psg_snd, fm_en,
                 cen_1008, cen_252, cen_63, cen_9, mixed, fm2, fm3, fm4, snd);
    end
end
`endif

endmodule // jt12_fm_uprate
