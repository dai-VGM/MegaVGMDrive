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
*/

// Versioned sparse-CEN successor of the formal PC-GATE ADPCM-B driver.
// The external CEN event which creates pre_clk_en_55 is published as cen55
// half a cycle later.  Delay that same external event by one system cycle so
// the decoder/interpolator pipeline keeps the original event count and sees
// adv && cen55 in the same enabled cycle.  Counter, request, gain, global CEN,
// JT12 division, FM, SSG and ADPCM-A are unchanged.
module jt10_adpcm_drvB(
    input           rst_n,
    input           clk,
    input           cen,      // 8MHz cen
    input           cen55,    // clk & cen55  =  55 kHz
    // Control
    input           acmd_on_b,  // Control - Process start, Key On
    input           acmd_rep_b, // Control - Repeat
    input           acmd_rst_b, // Control - Reset
    input           acmd_up_b, // Control - New command received
    input    [ 1:0] alr_b,      // Left / Right
    input    [15:0] astart_b,   // Start address
    input    [15:0] aend_b,     // End   address
    input    [15:0] adeltan_b,  // Delta-N
    input    [ 7:0] aeg_b,      // Envelope Generator Control
    output          flag,
    input           clr_flag,
    // memory
    output   [23:0] addr,
    input    [ 7:0] data,
    output reg roe_n,

    output reg signed [15:0]  pcm55_l,
    output reg signed [15:0]  pcm55_r
);

wire nibble_sel;
wire adv;           // advance to next reading
wire restart;
wire chon;
wire start_accept = acmd_up_b && acmd_on_b;

// `ifdef SIMULATION
// real fsample;
// always @(posedge acmd_on_b) begin
//     fsample = adeltan_b;
//     fsample = fsample/65536;
//     fsample = fsample * 55.5;
//     $display("\nINFO: ADPCM-B ON: %X delta N = %6d (%2.1f kHz)", astart_b, adeltan_b, fsample );
// end
// `endif

reg decoder_cen;

always @(posedge clk or negedge rst_n)
    if(!rst_n) decoder_cen <= 1'b0;
    else decoder_cen <= cen;

always @(posedge clk) roe_n <= ~(adv & cen55 & (chon | restart));

jt10_adpcmb_cnt u_cnt(
    .rst_n       ( rst_n           ),
    .clk         ( clk             ),
    .cen         ( cen55           ),
    .delta_n     ( adeltan_b       ),
	 .acmd_up_b   ( acmd_up_b       ),
    .clr         ( acmd_rst_b      ),
    .on          ( acmd_on_b       ),
    .astart      ( astart_b        ),
    .aend        ( aend_b          ),
    .arepeat     ( acmd_rep_b      ),
    .addr        ( addr            ),
    .nibble_sel  ( nibble_sel      ),
    // Flag control
    .chon        ( chon            ),
    .clr_flag    ( clr_flag        ),
    .flag        ( flag            ),
    .restart     ( restart         ),
    .adv         ( adv             )
);

reg [3:0] din;

always @(posedge clk) din <= !nibble_sel ? data[7:4] : data[3:0];

wire signed [15:0] pcmdec, pcminter, pcmgain;

jt10_adpcmb u_decoder(
    .rst_n  ( rst_n          ),
    .clk    ( clk            ),
    .cen    ( decoder_cen    ),
    .adv    ( adv & cen55    ),
    .data   ( din            ),
    .chon   ( chon           ),
    .clr    ( flag | restart ),
    .pcm    ( pcmdec         )
);

`ifndef NOBINTERPOL
jt10_adpcmb_interpol u_interpol(
    .rst_n  ( rst_n          ),
    .clk    ( clk            ),
    .cen    ( decoder_cen    ),
    .cen55  ( cen55  && chon ),
    .start_clr( start_accept    ),
    .adv    ( adv            ),
    .pcmdec ( pcmdec         ),
    .pcmout ( pcminter       )
);
`else 
assign pcminter = pcmdec;
`endif

jt10_adpcmb_gain u_gain(
    .rst_n  ( rst_n          ),
    .clk    ( clk            ),
    .cen55  ( cen55          ),
    .start_clr( start_accept  ),
    .tl     ( aeg_b          ),
    .pcm_in ( pcminter       ),
    .pcm_out( pcmgain        )
);

always @(posedge clk) begin
    if(start_accept) begin
        pcm55_l <= 'd0;
        pcm55_r <= 'd0;
    end else if(cen55) begin
        pcm55_l <= chon && alr_b[1] ? pcmgain : 16'd0;
        pcm55_r <= chon && alr_b[0] ? pcmgain : 16'd0;
    end
end

endmodule // jt10_adpcm_drvB
