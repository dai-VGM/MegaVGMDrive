// Versioned audit candidate B7: G=1 C=1 L=1.
// Derived only from frozen A6 and pinned 6d51e0b6 lower modules.
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

// HW-0-only name-separated derivative of the pristine pinned ADPCM-A
// driver.  Its logic is unchanged; only the gain child name is local.
module ym2610_hw0_jt10_adpcm_drvA(
    input           rst_n,
    input           clk,    // CPU clock
    input           cen,    // same cen as MMR
    input           cen6,   // clk & cen = 666 kHz
    input           cen1,   // clk & cen = 111 kHz

    output  [19:0]  addr,  // real hardware has 10 pins multiplexed through RMPX pin
    output  [3:0]   bank,
    output          roe_n, // ADPCM-A ROM output enable

    // Control Registers
    input   [5:0]   atl,        // ADPCM Total Level
    input   [7:0]   lracl_in,
    input   [95:0]  start_addr_in,
    input   [95:0]  end_addr_in,

    input   [2:0]   up_lracl,
    input   [5:0]   up_start,
    input   [5:0]   up_end,

    input   [7:0]   aon_cmd,    // ADPCM ON equivalent to key on for FM
    input           up_aon,

    input   [7:0]   datain,

    // Flags
    output  [5:0]   flags,
    input   [5:0]   clr_flags,

    output signed [15:0]  pcm55_l,
    output signed [15:0]  pcm55_r,
	 input   [5:0]   ch_enable
);

/* verilator tracing_on */

reg  [5:0] cur_ch;
reg  [5:0] en_ch;
reg  [3:0] data;
wire nibble_sel;
wire signed [15:0] pcm_att;

always @(posedge clk or negedge rst_n)
    if( !rst_n ) begin
        data <= 4'd0;
    end else if(cen) begin
        data <= !nibble_sel ? datain[7:4] : datain[3:0];
    end

reg [ 5:0] aon_sr, aoff_sr;

reg [7:0] aon_cmd_cpy;
reg aon_cmd_valid;
reg up_aon_armed;

// One held-high MMR update level is one command capture.  A low interval
// rearms the mailbox even when external CEN is sparse; the actual capture
// remains qualified by CEN.
always @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
        aon_cmd_cpy <= 8'd0;
        aon_cmd_valid <= 1'b0;
        up_aon_armed <= 1'b1;
    end else begin
        if( !up_aon )
            up_aon_armed <= 1'b1;
        else if( cen && up_aon_armed )
            up_aon_armed <= 1'b0;

        if( cen && up_aon && up_aon_armed ) begin
            aon_cmd_cpy <= aon_cmd;
            aon_cmd_valid <= 1'b1;
        end else if( cur_ch[5] && cen6 && aon_cmd_valid ) begin
            aon_cmd_valid <= 1'b0;
        end
    end
end

wire audit_command_valid = aon_cmd_valid;
wire audit_pending_ack = 1'b0;
wire audit_command_consume = cur_ch[5] && cen6 && aon_cmd_valid;

always @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
        aon_sr <= 6'd0;
        aoff_sr <= 6'd0;
    end else if( cen6 ) begin
    if( cur_ch[5] ) begin
        if( audit_command_valid ) begin
            aon_sr  <= ~{6{aon_cmd_cpy[7]}} & aon_cmd_cpy[5:0];
            aoff_sr <=  {6{aon_cmd_cpy[7]}} & aon_cmd_cpy[5:0];
        end else begin
            aon_sr <= 6'd0;
            aoff_sr <= 6'd0;
        end
    end else begin
        aon_sr  <= { 1'b0,  aon_sr[5:1] };
        aoff_sr <= { 1'b0, aoff_sr[5:1] };
    end
end
end

reg match; // high when cur_ch==en_ch, but calculated one clock cycle ahead
    // so it can be latched
wire [5:0] cur_next = { cur_ch[4:0], cur_ch[5] };
wire [5:0]  en_next = {  en_ch[0],  en_ch[5:1] };

always @(posedge clk or negedge rst_n)
    if( !rst_n ) begin
        cur_ch <= 6'b1;  en_ch  <= 6'b1;
        match  <= 0;
    end else if( cen6 ) begin
        cur_ch <= cur_next;
        if( cur_ch[5] ) en_ch <= en_next;
        match <= cur_next == (cur_ch[5] ? en_next : en_ch);
    end

function [15:0] select_addr;
    input [95:0] addresses;
    input [5:0] channel;
    begin
        case(channel)
            6'b000001: select_addr = addresses[15:0];
            6'b000010: select_addr = addresses[31:16];
            6'b000100: select_addr = addresses[47:32];
            6'b001000: select_addr = addresses[63:48];
            6'b010000: select_addr = addresses[79:64];
            6'b100000: select_addr = addresses[95:80];
            default:   select_addr = 16'd0;
        endcase
    end
endfunction

wire [15:0] start_addr_current = select_addr(start_addr_in, cur_ch);
wire [15:0] end_addr_current   = select_addr(end_addr_in, cur_ch);
wire up_start_current = |(up_start & cur_ch);
wire up_end_current   = |(up_end & cur_ch);

wire [15:0] start_top, end_top;

wire clr_dec, decon;

ym2610_adpcma_candidate_jt10_adpcm_cnt u_cnt(
    .rst_n       ( rst_n           ),
    .clk         ( clk             ),
    .cen         ( cen6            ),
    // Pipeline
    .cur_ch      ( cur_ch          ),
    .en_ch       ( en_ch           ),
    // START/END update
    .start_addr_in( start_addr_current ),
    .end_addr_in  ( end_addr_current   ),
    .up_start    ( up_start_current ),
    .up_end      ( up_end_current   ),
    // Control
    .aon         ( aon_sr[0]       ),
    .aoff        ( aoff_sr[0]      ),
    .clr         ( clr_dec         ),
    // ROM driver
    .addr_out    ( addr            ),
    .bank        ( bank            ),
    .sel         ( nibble_sel      ),
    .roe_n       ( roe_n           ),
    .decon       ( decon           ),
    // Flags
    .flags       ( flags           ),
    .clr_flags   ( clr_flags       ),
    .start_top   ( start_top       ),
    .end_top     ( end_top         )
);

// wire chactive = chon & cen6;
wire signed [15:0] pcmdec;

jt10_adpcm u_decoder(
    .rst_n  ( rst_n     ),
    .clk    ( clk       ),
    .cen    ( cen6      ),
    .data   ( data      ),
    .chon   ( decon     ),
    .clr    ( clr_dec   ),
    .pcm    ( pcmdec    )
);
/*

always @(posedge clk) begin
    if( cen3 && chon ) begin
        pcm55_l <= pre_pcm55_l;
        pcm55_r <= pre_pcm55_r;
    end
end
*/

wire [1:0] lr;

ym2610_hw0_jt10_adpcm_gain u_gain(
    .rst_n  ( rst_n          ),
    .clk    ( clk            ),
    .cen    ( cen6           ),
    // Pipeline
    .cur_ch ( cur_ch         ),
    .en_ch  ( en_ch          ),
    .match  ( match          ),
    // Gain control
    .atl    ( atl            ),        // ADPCM Total Level
    .lracl  ( lracl_in       ),
    .up_ch  ( up_lracl       ),

    .lr     ( lr             ),
    .pcm_in ( pcmdec         ),
    .pcm_att( pcm_att        )
);

wire signed [15:0] pre_pcm55_l, pre_pcm55_r;

assign pcm55_l = pre_pcm55_l;
assign pcm55_r = pre_pcm55_r;

ym2610_adpcma_candidate_jt10_adpcm_acc u_acc_left(
    .rst_n  ( rst_n     ),
    .clk    ( clk       ),
    .cen    ( cen6      ),
    // Pipeline
    .cur_ch ( cur_ch    ),
    .en_ch  ( en_ch     ),
    .match  ( match     ),
    // left/right enable
    .en_sum ( lr[1] && (ch_enable & cur_ch) ),

    .pcm_in ( pcm_att   ),    // 18.5 kHz
    .pcm_out( pre_pcm55_l   )     // 55.5 kHz
);

ym2610_adpcma_candidate_jt10_adpcm_acc u_acc_right(
    .rst_n  ( rst_n     ),
    .clk    ( clk       ),
    .cen    ( cen6      ),
    // Pipeline
    .cur_ch ( cur_ch    ),
    .en_ch  ( en_ch     ),
    .match  ( match     ),
    // left/right enable
    .en_sum ( lr[0] && (ch_enable & cur_ch) ),

    .pcm_in ( pcm_att   ),    // 18.5 kHz
    .pcm_out( pre_pcm55_r   )     // 55.5 kHz
);


`ifdef SIMULATION
integer fch0, fch1, fch2, fch3, fch4, fch5;
initial begin
    fch0 = $fopen("ch0.dec","w");
    fch1 = $fopen("ch1.dec","w");
    fch2 = $fopen("ch2.dec","w");
    fch3 = $fopen("ch3.dec","w");
    fch4 = $fopen("ch4.dec","w");
    fch5 = $fopen("ch5.dec","w");
end

reg signed [15:0] pcm_ch0, pcm_ch1, pcm_ch2, pcm_ch3, pcm_ch4, pcm_ch5;
always @(posedge cen6) if(en_ch[0]) begin
    if(cur_ch[0]) begin
        pcm_ch0 <= pcmdec;
        $fwrite( fch0, "%d\n", pcmdec );
    end
    if(cur_ch[1]) begin
        pcm_ch1 <= pcmdec;
        $fwrite( fch1, "%d\n", pcmdec );
    end
    if(cur_ch[2]) begin
        pcm_ch2 <= pcmdec;
        $fwrite( fch2, "%d\n", pcmdec );
    end
    if(cur_ch[3]) begin
        pcm_ch3 <= pcmdec;
        $fwrite( fch3, "%d\n", pcmdec );
    end
    if(cur_ch[4]) begin
        pcm_ch4 <= pcmdec;
        $fwrite( fch4, "%d\n", pcmdec );
    end
    if(cur_ch[5]) begin
        pcm_ch5 <= pcmdec;
        $fwrite( fch5, "%d\n", pcmdec );
    end
end

reg [15:0] sim_start0, sim_start1, sim_start2, sim_start3, sim_start4, sim_start5;
reg [15:0] sim_end0, sim_end1, sim_end2, sim_end3, sim_end4, sim_end5;
reg [ 7:0] sim_lracl0, sim_lracl1, sim_lracl2, sim_lracl3, sim_lracl4, sim_lracl5;
/*
reg div3b;
reg [2:0] chframe;
always @(posedge clk) div3b<=div3;
always @(negedge div3b) chframe <= chfast;


reg [7:0] aon_cpy, aon_cpy2;
always @(posedge clk) begin
    aon_cpy<=aon_cmd; // This prevents a Verilator circular-logic warning
    aon_cpy2 <= aon_cmd;
end

always @(posedge aon_cpy[0]) if(!aon_cpy2[7]) $display("INFO: ADPCM-A ON 0 - %X",sim_start0);
always @(posedge aon_cpy[1]) if(!aon_cpy2[7]) $display("INFO: ADPCM-A ON 1 - %X",sim_start1);
always @(posedge aon_cpy[2]) if(!aon_cpy2[7]) $display("INFO: ADPCM-A ON 2 - %X",sim_start2);
always @(posedge aon_cpy[3]) if(!aon_cpy2[7]) $display("INFO: ADPCM-A ON 3 - %X",sim_start3);
always @(posedge aon_cpy[4]) if(!aon_cpy2[7]) $display("INFO: ADPCM-A ON 4 - %X",sim_start4);
always @(posedge aon_cpy[5]) if(!aon_cpy2[7]) $display("INFO: ADPCM-A ON 5 - %X",sim_start5);
*/
always @(posedge cen6) if(up_start)
    case(up_addr)
        3'd0: sim_start0 <= addr_in;
        3'd1: sim_start1 <= addr_in;
        3'd2: sim_start2 <= addr_in;
        3'd3: sim_start3 <= addr_in;
        3'd4: sim_start4 <= addr_in;
        3'd5: sim_start5 <= addr_in;
        default:;
    endcase // up_addr

always @(posedge cen6) if(up_end)
    case(up_addr)
        3'd0: sim_end0 <= addr_in;
        3'd1: sim_end1 <= addr_in;
        3'd2: sim_end2 <= addr_in;
        3'd3: sim_end3 <= addr_in;
        3'd4: sim_end4 <= addr_in;
        3'd5: sim_end5 <= addr_in;
        default:;
    endcase // up_addr

always @(posedge cen6)
    case(up_lracl)
        3'd0: sim_lracl0 <= lracl_in;
        3'd1: sim_lracl1 <= lracl_in;
        3'd2: sim_lracl2 <= lracl_in;
        3'd3: sim_lracl3 <= lracl_in;
        3'd4: sim_lracl4 <= lracl_in;
        3'd5: sim_lracl5 <= lracl_in;
        default:;
    endcase // up_addr

    /*
reg start_error, end_error;
always @(posedge cen6) begin
    case(chframe)
        3'd0: start_error <= start_top != sim_start0;
        3'd1: start_error <= start_top != sim_start1;
        3'd2: start_error <= start_top != sim_start2;
        3'd3: start_error <= start_top != sim_start3;
        3'd4: start_error <= start_top != sim_start4;
        3'd5: start_error <= start_top != sim_start5;
        default:;
    endcase
    case(chframe)
        3'd0: end_error <= end_top != sim_end0;
        3'd1: end_error <= end_top != sim_end1;
        3'd2: end_error <= end_top != sim_end2;
        3'd3: end_error <= end_top != sim_end3;
        3'd4: end_error <= end_top != sim_end4;
        3'd5: end_error <= end_top != sim_end5;
        default:;
    endcase
end
*/
`endif

endmodule // ym2610_hw0_jt10_adpcm_drvA

// Candidate-local T4 counter reset derivative.
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

module ym2610_adpcma_candidate_jt10_adpcm_cnt(
    input             rst_n,
    input             clk,        // CPU clock
    input             cen,        // 666 kHz
    // pipeline channel
    input      [ 5:0] cur_ch,
    input      [ 5:0] en_ch,
    // Address writes from CPU
    input      [15:0] start_addr_in,
    input      [15:0] end_addr_in,
    input             up_start,
    input             up_end,
    // Counter control
    input             aon,
    input             aoff,
    // ROM driver
    output     [19:0] addr_out,
    output     [ 3:0] bank,
    output            sel,
    output            roe_n,
    output            decon,
    output            clr,      // inform the decoder that a new section begins
    // Flags
    output reg [ 5:0] flags,
    input      [ 5:0] clr_flags,
    //
    output [15:0] start_top,
    output [15:0]   end_top
);

reg [20:0] addr1, addr2, addr3, addr4, addr5, addr6;
reg [3:0] bank1, bank2, bank3, bank4, bank5, bank6;
reg [11:0] start1, start2, start3, start4, start5, start6,
           end1,   end2,   end3,   end4,   end5,   end6;
reg on1, on2, on3, on4, on5, on6;
reg done5, done6, done1;
reg [5:0] done_sr, zero;

reg roe_n1, decon1;

reg clr1, clr2, clr3, clr4, clr5, clr6;
reg skip1, skip2, skip3, skip4, skip5, skip6;

// All outputs from stage 1
assign addr_out = addr1[20:1];
assign sel      = addr1[0];
assign bank     = bank1;
assign roe_n    = roe_n1;
assign clr      = clr1;
assign decon    = decon1;

// Two cycles early:  0            0             1            1             2            2             3            3             4            4             5            5
wire active5 = (en_ch[1] && cur_ch[4]) || (en_ch[2] && cur_ch[5]) || (en_ch[2] && cur_ch[0]) || (en_ch[3] && cur_ch[1]) || (en_ch[4] && cur_ch[2]) || (en_ch[5] && cur_ch[3]);//{ cur_ch[3:0], cur_ch[5:4] } == en_ch;
wire sumup5  = on5 && !done5 && active5;
reg  sumup6;

reg [5:0] last_done, set_flags;

always @(posedge clk or negedge rst_n)
    if( !rst_n ) begin
        zero      <= 6'd1;
        done_sr   <= ~6'd0;
        last_done <= ~6'd0;
        set_flags <= 6'd0;
    end else if(cen) begin
        zero    <= { zero[0], zero[5:1] };
        done_sr <= { done1, done_sr[5:1]};
        if( zero[0] ) begin
            last_done <= done_sr;
            set_flags <= ~last_done & done_sr;
        end
    end

always @(posedge clk or negedge rst_n)
    if( !rst_n ) begin
        flags <= 6'd0;
    end else begin
        flags <= ~clr_flags & (set_flags | flags);
    end

`ifdef SIMULATION
wire [11:0] addr1_cmp = addr1[20:9];
`endif

assign start_top = {bank1, start1};
assign   end_top =   {bank1, end1};

always @(posedge clk or negedge rst_n)
    if( !rst_n ) begin
        addr1  <= 'd0;    addr2 <= 'd0;    addr3 <= 'd0;
        addr4  <= 'd0;    addr5 <= 'd0;    addr6 <= 'd0;
        done1  <= 'd1;    done5 <= 'd1;    done6 <= 'd1;
        start1 <= 'd0;   start2 <= 'd0;   start3 <= 'd0;
        start4 <= 'd0;   start5 <= 'd0;   start6 <= 'd0;
        end1   <= 'd0;     end2 <= 'd0;     end3 <= 'd0;
        end4   <= 'd0;     end5 <= 'd0;     end6 <= 'd0;
        skip1  <= 'd0;    skip2 <= 'd0;    skip3 <= 'd0;
        skip4  <= 'd0;    skip5 <= 'd0;    skip6 <= 'd0;
        on1    <= 1'b0;   on2   <= 1'b0;   on3   <= 1'b0;
        on4    <= 1'b0;   on5   <= 1'b0;   on6   <= 1'b0;
        clr1   <= 1'b0;   clr2  <= 1'b0;   clr3  <= 1'b0;
        clr4   <= 1'b0;   clr5  <= 1'b0;   clr6  <= 1'b0;
        roe_n1 <= 1'b1;
        decon1 <= 1'b0;
        sumup6 <= 1'b0;
        bank1  <= 4'd0;   bank2 <= 4'd0;   bank3 <= 4'd0;
        bank4  <= 4'd0;   bank5 <= 4'd0;   bank6 <= 4'd0;
    end else if( cen ) begin
        addr2  <= addr1;
        on2    <= aoff ? 1'b0 : (aon | (on1 && ~done1));
        clr2   <= aoff || aon || done1; // Each time a A-ON is sent the address counter restarts
        start2 <=  up_start ? start_addr_in[11:0] : start1;
        end2   <=  up_end   ? end_addr_in[11:0] : end1;
        bank2  <=  up_start ? start_addr_in[15:12] : bank1;
        skip2  <= skip1;

        addr3  <= addr2; // clr2 ? {start2,9'd0} : addr2;
        on3    <= on2;
        clr3   <= clr2;
        start3 <= start2;
        end3   <= end2;
        bank3  <= bank2;
        skip3  <= skip2;

        addr4  <= addr3;
        on4    <= on3;
        clr4   <= clr3;
        start4 <= start3;
        end4   <= end3;
        bank4  <= bank3;
        skip4  <= skip3;

        addr5  <= addr4;
        on5    <= on4;
        clr5   <= clr4;
        done5  <= addr4[20:9] == end4 && addr4[8:0]==~9'b0 && ~(clr4 && on4);
        start5 <= start4;
        end5   <= end4;
        bank5  <= bank4;
        skip5  <= skip4;
        // V
        addr6  <= addr5;
        on6    <= on5;
        clr6   <= clr5;
        done6  <= done5;
        start6 <= start5;
        end6   <= end5;
        bank6  <= bank5;
        sumup6 <= sumup5;
        skip6  <= skip5;

        addr1  <= (clr6 && on6) ? {start6,9'd0} : (sumup6 && ~skip6 ? addr6+21'd1 :addr6);
        on1    <= on6;
        done1  <= done6;
        start1 <= start6;
        end1   <= end6;
        roe_n1 <= ~sumup6;
        decon1 <= sumup6;
        bank1  <= bank6;
        clr1   <= clr6;
        skip1  <= (clr6 && on6) ? 1'b1 : sumup6 ? 1'b0 : skip6;
    end

endmodule // jt10_adpcm_cnt

// Candidate-local T4 lane publication reset derivative.
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

// Adds all 6 channels and apply linear interpolation to rise
// sampling frequency to 55.5 kHz

module ym2610_adpcma_candidate_jt10_adpcm_acc(
    input           rst_n,
    input           clk,        // CPU clock
    input           cen,        // 111 kHz
    // pipeline channel
    input   [5:0]   cur_ch,
    input   [5:0]   en_ch,
    input           match,

    input           en_sum,
    input  signed [15:0] pcm_in,    // 18.5 kHz
    output reg signed [15:0] pcm_out    // 55.5 kHz
);

wire signed [17:0] pcm_in_long = en_sum ? { {2{pcm_in[15]}}, pcm_in } : 18'd0;
reg  signed [17:0] acc, last, pcm_full;
reg  signed [17:0] step;

reg signed [17:0] diff;
reg signed [22:0] diff_ext, step_full;

always @(*) begin
    diff = acc-last;
    diff_ext = { {5{diff[17]}}, diff };
    step_full = diff_ext        // 1/128
        + ( diff_ext << 1 )     // 1/64
        + ( diff_ext << 3 )     // 1/16
        + ( diff_ext << 5 );    // 1/4

end

wire adv = en_ch[0] & cur_ch[0];

always @(posedge clk or negedge rst_n)
    if( !rst_n ) begin
        step <= 'd0;
        acc  <= 18'd0;
        last <= 18'd0;
    end else if(cen) begin
        if( match )
            acc <= cur_ch[0] ? pcm_in_long : ( pcm_in_long + acc );
        if( adv ) begin
            // step = diff * (1/4+1/16+1/64+1/128)
            step <= { {2{step_full[22]}}, step_full[22:7] }; // >>>7;
            last <= acc;
        end
    end
wire overflow = |pcm_full[17:15] & ~&pcm_full[17:15];

always @(posedge clk or negedge rst_n)
    if( !rst_n ) begin
        pcm_full <= 18'd0;
        pcm_out  <= 16'sd0;
    end else if(cen && cur_ch[0]) begin
        case( en_ch )
            6'b000_001: pcm_full <= last;
            6'b000_100,
            6'b010_000: pcm_full <= pcm_full + step;
            default:;
        endcase
        if( overflow )
            pcm_out <= pcm_full[17] ? 16'h8000 : 16'h7fff; // saturate
        else
            pcm_out <= pcm_full[15:0];
    end

endmodule // jt10_adpcm_acc
