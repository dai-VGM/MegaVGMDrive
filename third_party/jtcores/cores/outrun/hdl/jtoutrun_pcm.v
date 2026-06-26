/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTCORES program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 16-7-2022 */

// This module represents the 315-5218
// Clock input 16.000MHz on pin 80
// Clock outputs: pin 2 - 4.000MHz, pin 80 - 500.000kHz, pin 89 - 62.500KHz
// Sample rate = clk/4/128 = 31.25 kHz

module jtoutrun_pcm #(parameter
    WD        = 12,     // DAC bit width (AD7121) = 12 bits plus bits dropped internally
    SIMHEXFILE= ""
)(
    input              rst,
    input              clk,
    input              cen, // original clock was 16MHz

    input        [7:0] debug_bus,
    output reg   [7:0] st_dout,

    // CPU interface
    input        [7:0] cpu_addr,
    input        [7:0] cpu_dout,
    output       [7:0] cpu_din,
    input              cpu_rnw,
    input              cpu_cs,
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
    input        [2:0] smoke_variant,
`endif

    // ROM interface
    output reg  [18:0] rom_addr,
    input       [ 7:0] rom_data,
    input              rom_ok,
    output reg         rom_cs,

    // sound output
    output reg signed [15:0] snd_left,
    output reg signed [15:0] snd_right,
    output reg           sample,

    // Debug: latched on the cycle that issues rom_cs/rom_addr
    output      [15:0] dbg_bank_channel_state,
    output      [15:0] dbg_cur_addr_high,
    output      [15:0] dbg_cur_addr_low_state,
    output      [15:0] dbg_38686_en_addr,
    output      [15:0] dbg_38686_en_value,
    output      [15:0] dbg_38686_d0_addr,
    output      [15:0] dbg_38686_d0_value,
    output      [15:0] dbg_38686_d1_addr,
    output      [15:0] dbg_38686_d1_value,
    output      [15:0] dbg_38686_d2_addr,
    output      [15:0] dbg_38686_d2_value,
    output      [15:0] dbg_38686_cfg_en,
    output      [15:0] dbg_38686_cur_23,
    output      [15:0] dbg_38686_cur_15,
    output      [15:0] dbg_38686_cur_07,
    output      [15:0] dbg_38686_delta,
    output      [15:0] dbg_ch3_evolution_flags,
    output      [15:0] dbg_ch3_delta,
    output      [15:0] dbg_ch1_first_high,
    output      [15:0] dbg_ch1_first_low,
    output      [15:0] dbg_ch1_first_raw_high,
    output      [15:0] dbg_ch1_first_raw_low,
    output      [15:0] dbg_ch3_first_high,
    output      [15:0] dbg_ch3_first_low,
    output      [15:0] dbg_ch3_first_raw_high,
    output      [15:0] dbg_ch3_first_raw_low,
    output      [15:0] dbg_ch3_r0_high,
    output      [15:0] dbg_ch3_r0_low,
    output      [15:0] dbg_ch3_r1_high,
    output      [15:0] dbg_ch3_r1_low,
    output      [15:0] dbg_ch3_r2_high,
    output      [15:0] dbg_ch3_r2_low,
    output      [15:0] dbg_update_state_channel,
    output      [15:0] dbg_update_before_23,
    output      [15:0] dbg_update_before_15,
    output      [15:0] dbg_update_before_07,
    output      [15:0] dbg_update_addend,
    output      [15:0] dbg_update_after_23,
    output      [15:0] dbg_update_after_15,
    output      [15:0] dbg_update_after_07,
    output      [15:0] dbg_ch3_load_after_23,
    output      [15:0] dbg_ch3_load_after_15,
    output      [15:0] dbg_ch3_load_after_07,
    output      [15:0] dbg_update_reason
);

wire        we = cpu_cs & ~cpu_rnw;
reg  [ 3:0] st;
reg  [ 8:0] cfg_ram_addr_d;
wire [ 2:0] bank;
wire [ 7:0] cfg_data;
reg  [ 3:0] cur_ch;
reg  [ 4:0] cfg_addr;
wire [ 8:0] cfg_ram_addr = { cfg_addr[4:3], cur_ch, cfg_addr[2:0] };
reg  [15:0] active;     // high for active channels, debug only
reg  [ 7:0] cfg_en;
reg  [ 7:0] delta, cfg_din;
reg         cfg_we, was_enb;

reg  [ 2:0] dbg_last_bank;
reg  [ 3:0] dbg_last_ch;
reg  [ 3:0] dbg_last_st;
reg  [23:0] dbg_last_cur_addr;
reg  [ 8:0] dbg_seq_en_addr;
reg  [ 7:0] dbg_seq_en_value;
reg  [ 8:0] dbg_seq_d0_addr;
reg  [ 7:0] dbg_seq_d0_value;
reg  [ 8:0] dbg_seq_d1_addr;
reg  [ 7:0] dbg_seq_d1_value;
reg  [ 8:0] dbg_seq_d2_addr;
reg  [ 7:0] dbg_seq_d2_value;
reg  [ 8:0] dbg_38686_en_addr_i;
reg  [ 7:0] dbg_38686_en_value_i;
reg  [ 8:0] dbg_38686_d0_addr_i;
reg  [ 7:0] dbg_38686_d0_value_i;
reg  [ 8:0] dbg_38686_d1_addr_i;
reg  [ 7:0] dbg_38686_d1_value_i;
reg  [ 8:0] dbg_38686_d2_addr_i;
reg  [ 7:0] dbg_38686_d2_value_i;
reg  [ 7:0] dbg_38686_cfg_en_i;
reg  [ 7:0] dbg_38686_cur_23_i;
reg  [ 7:0] dbg_38686_cur_15_i;
reg  [ 7:0] dbg_38686_cur_07_i;
reg  [ 7:0] dbg_38686_delta_i;
reg         dbg_ch3_enabled_seen_i;
reg         dbg_ch3_rom_seen_i;
reg         dbg_ch3_second_jump_i;
reg         dbg_ch3_jump_seen_i;
reg         dbg_ch1_rom_seen_i;
reg  [ 2:0] dbg_ch1_first_bank_i;
reg  [23:0] dbg_ch1_first_addr_i;
reg  [ 1:0] dbg_ch3_rom_count_i;
reg  [ 2:0] dbg_ch3_first_bank_i;
reg  [23:0] dbg_ch3_first_addr_i;
reg  [23:0] dbg_ch3_prev_addr_i;
reg  [23:0] dbg_ch3_r0_addr_i;
reg  [23:0] dbg_ch3_r1_addr_i;
reg  [23:0] dbg_ch3_r2_addr_i;
reg  [ 7:0] dbg_ch3_delta_i;
reg  [ 3:0] dbg_update_state_i;
reg  [ 3:0] dbg_update_channel_i;
reg  [23:0] dbg_update_before_i;
reg  [23:0] dbg_update_after_i;
reg  [ 7:0] dbg_update_addend_i;
reg  [ 7:0] dbg_update_reason_i;
reg  [ 7:0] dbg_writer_bits_i;
reg         dbg_update_exact_seen_i;
reg  [ 8:0] dbg_ch3_roll_d0_addr_i;
reg  [ 7:0] dbg_ch3_roll_d0_value_i;
reg  [ 8:0] dbg_ch3_roll_d1_addr_i;
reg  [ 7:0] dbg_ch3_roll_d1_value_i;
reg  [ 8:0] dbg_ch3_roll_d2_addr_i;
reg  [ 7:0] dbg_ch3_roll_d2_value_i;
reg  [23:0] dbg_ch3_roll_load_after_i;
reg  [ 2:0] dbg_ch3_roll_seen_i;
reg  [23:0] dbg_ch3_load_after_i;
reg  [ 2:0] dbg_ch3_load_seen_i;
reg  [ 8:0] dbg_ch3_w9_addr_i;
reg  [ 7:0] dbg_ch3_w9_value_i;
reg  [ 8:0] dbg_ch3_wa_addr_i;
reg  [ 7:0] dbg_ch3_wa_value_i;
reg  [ 8:0] dbg_ch3_wb_addr_i;
reg  [ 7:0] dbg_ch3_wb_value_i;
reg  [23:0] dbg_ch3_wb_cur_addr_i;
reg  [ 2:0] dbg_ch3_wb_seen_i;
reg         dbg_ch3_wb_after_event_i;
reg  [ 8:0] dbg_prior_w9_addr_i;
reg  [ 7:0] dbg_prior_w9_value_i;
reg  [ 8:0] dbg_prior_wa_addr_i;
reg  [ 7:0] dbg_prior_wa_value_i;
reg  [ 8:0] dbg_prior_wb_addr_i;
reg  [ 7:0] dbg_prior_wb_value_i;
reg  [23:0] dbg_prior_wb_cur_addr_i;
reg  [ 7:0] dbg_prior_flags_i;
reg  [ 8:0] dbg_cpu_roll_u1_addr_i;
reg  [ 7:0] dbg_cpu_roll_u1_value_i;
reg  [ 8:0] dbg_cpu_roll_u2_addr_i;
reg  [ 7:0] dbg_cpu_roll_u2_value_i;
reg  [ 8:0] dbg_cpu_roll_u3_addr_i;
reg  [ 7:0] dbg_cpu_roll_u3_value_i;
reg  [ 2:0] dbg_cpu_roll_seen_i;
reg  [ 8:0] dbg_cpu_u1_addr_i;
reg  [ 7:0] dbg_cpu_u1_value_i;
reg  [ 8:0] dbg_cpu_u2_addr_i;
reg  [ 7:0] dbg_cpu_u2_value_i;
reg  [ 8:0] dbg_cpu_u3_addr_i;
reg  [ 7:0] dbg_cpu_u3_value_i;
reg  [ 7:0] dbg_cpu_flags_i;
reg  [ 7:0] dbg_target_order_i;
reg  [ 8:0] dbg_target1_addr_i;
reg  [ 7:0] dbg_target1_value_i;
reg  [15:0] dbg_target1_info_i;
reg  [ 8:0] dbg_target2_addr_i;
reg  [ 7:0] dbg_target2_value_i;
reg  [15:0] dbg_target2_info_i;
reg  [ 8:0] dbg_target3_addr_i;
reg  [ 7:0] dbg_target3_value_i;
reg  [15:0] dbg_target3_info_i;
reg  [ 7:0] dbg_target_flags_i;
reg  [ 7:0] dbg_read_flags_i;
reg  [15:0] dbg_last_cpu_port_i;
reg  [15:0] dbg_last_int_port_i;
reg  [15:0] dbg_write_source_i;
reg         dbg_fs_start_seen_i;
reg         dbg_fs_arm_i;
reg  [ 2:0] dbg_fs_load_seen_i;
reg  [ 7:0] dbg_fs_f1_data_i;
reg  [ 7:0] dbg_fs_f2_data_i;
reg  [ 7:0] dbg_fs_f3_data_i;
reg  [23:0] dbg_fs_load_addr_i;
reg         dbg_fs_rom_seen_i;
reg  [ 2:0] dbg_fs_rom_bank_i;
reg  [23:0] dbg_fs_rom_addr_i;
reg  [ 2:0] dbg_fs_wb_seen_i;
reg  [ 7:0] dbg_fs_w9_data_i;
reg  [ 7:0] dbg_fs_wa_data_i;
reg  [ 7:0] dbg_fs_wb_data_i;
reg  [23:0] dbg_fs_wb_addr_i;
reg  [ 7:0] dbg_fs_delta_i;
reg  [ 7:0] dbg_start_mirror_c0_i;
reg  [ 7:0] dbg_start_mirror_c1_i;
reg  [ 7:0] dbg_start_mirror_c2_i;
reg  [ 7:0] dbg_start_mirror_ctl_i;
reg  [ 7:0] dbg_start_sc0_i;
reg  [ 7:0] dbg_start_sc1_i;
reg  [ 7:0] dbg_start_sc2_i;
reg  [ 7:0] dbg_start_ctl_i;
reg  [ 7:0] dbg_start_ac0_i;
reg  [ 7:0] dbg_start_ac1_i;
reg  [ 7:0] dbg_start_ac2_i;
reg  [ 7:0] dbg_start_actl_i;
reg  [ 7:0] dbg_start_flags_i;
// Experimental MegaVGMDrive probe: force ch3 current-address loads.
reg         dbg_start_init_ch3_pending_i;

reg  [23: 0] cur_addr;
reg  [23: 8] loop_addr;
reg  [23:16] end_addr;

`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
localparam [3:0] SMOKE_CH = 4'd3;
localparam [2:0] SMOKE_BANK = 3'd3;
localparam [7:0] SMOKE_CFG = 8'h30;
localparam [23:0] SMOKE_CUR = 24'h002600;
wire [7:0] smoke_delta = 8'h20;
wire [6:0] smoke_vol_l =
    (smoke_variant == 3'd4) ? 7'h20 :
    (smoke_variant == 3'd6) ? 7'h00 :
    7'h40;
wire [6:0] smoke_vol_r =
    (smoke_variant == 3'd4) ? 7'h20 :
    (smoke_variant == 3'd5) ? 7'h00 :
    7'h40;
`endif

reg  signed [ 7:0] vol_left, vol_right, vol_mux;
wire signed [ 7:0] pcm_data;
reg  signed [15:0] mul_data;
reg  signed [15:0] acc_l, acc_r;
reg  signed [WD-1:0] mul_clip, buf_r;


assign bank     = cfg_en[6:4];
assign pcm_data = rom_data - 8'h80;
assign dbg_bank_channel_state = {5'd0, dbg_last_bank, dbg_last_ch, dbg_last_st};
assign dbg_cur_addr_high = dbg_last_cur_addr[23:8];
assign dbg_cur_addr_low_state = {dbg_last_cur_addr[7:0], dbg_last_st, dbg_last_ch};
assign dbg_38686_en_addr = {7'd0, dbg_38686_en_addr_i};
assign dbg_38686_en_value = {8'd0, dbg_38686_en_value_i};
assign dbg_38686_d0_addr = {7'd0, dbg_38686_d0_addr_i};
assign dbg_38686_d0_value = {8'd0, dbg_38686_d0_value_i};
assign dbg_38686_d1_addr = {7'd0, dbg_38686_d1_addr_i};
assign dbg_38686_d1_value = {8'd0, dbg_38686_d1_value_i};
assign dbg_38686_d2_addr = {7'd0, dbg_38686_d2_addr_i};
assign dbg_38686_d2_value = {8'd0, dbg_38686_d2_value_i};
assign dbg_38686_cfg_en = {8'd0, dbg_38686_cfg_en_i};
assign dbg_38686_cur_23 = {8'd0, dbg_38686_cur_23_i};
assign dbg_38686_cur_15 = {8'd0, dbg_38686_cur_15_i};
assign dbg_38686_cur_07 = {8'd0, dbg_38686_cur_07_i};
assign dbg_38686_delta = {8'd0, dbg_38686_delta_i};
assign dbg_ch3_evolution_flags = {
    8'hef,
    dbg_update_exact_seen_i,
    (dbg_ch3_load_after_i == 24'h868636),
    (dbg_38686_d2_value_i == 8'h86),
    (dbg_38686_d1_value_i == 8'h86),
    (dbg_38686_d0_value_i == 8'h36),
    dbg_ch3_load_seen_i[2],
    dbg_ch3_load_seen_i[1],
    dbg_ch3_load_seen_i[0]
};
assign dbg_ch3_delta = {
    8'hf7,
    dbg_read_flags_i[7],
    dbg_read_flags_i[6],
    dbg_read_flags_i[5],
    dbg_read_flags_i[4],
    dbg_read_flags_i[3],
    dbg_read_flags_i[2],
    dbg_read_flags_i[1],
    dbg_read_flags_i[0]
};
assign dbg_ch1_first_high = dbg_last_cpu_port_i;
assign dbg_ch1_first_low = dbg_last_int_port_i;
assign dbg_ch1_first_raw_high = dbg_write_source_i;
assign dbg_ch1_first_raw_low = {7'd0, dbg_target2_addr_i};
assign dbg_ch3_first_high = {8'd0, dbg_target2_value_i};
assign dbg_ch3_first_low = dbg_target2_info_i;
assign dbg_ch3_first_raw_high = {7'd0, dbg_target3_addr_i};
assign dbg_ch3_first_raw_low = {8'd0, dbg_target3_value_i};
assign dbg_ch3_r0_high = dbg_target3_info_i;
assign dbg_ch3_r0_low = dbg_38686_d0_value;
assign dbg_ch3_r1_high = dbg_38686_d1_value;
assign dbg_ch3_r1_low = dbg_38686_d2_value;
assign dbg_ch3_r2_high = dbg_38686_d2_value;
assign dbg_ch3_r2_low = dbg_38686_d1_value;
assign dbg_update_state_channel = {8'd0, dbg_update_state_i, dbg_update_channel_i};
assign dbg_update_before_23 = {8'd0, dbg_update_before_i[23:16]};
assign dbg_update_before_15 = {8'd0, dbg_update_before_i[15:8]};
assign dbg_update_before_07 = {8'd0, dbg_update_before_i[7:0]};
assign dbg_update_addend = {8'd0, dbg_update_addend_i};
assign dbg_update_after_23 = {8'd0, dbg_prior_wb_cur_addr_i[7:0]};
assign dbg_update_after_15 = {8'd0, dbg_fs_wb_addr_i[15:8]};
assign dbg_update_after_07 = {8'd0, dbg_fs_wb_addr_i[7:0]};
assign dbg_ch3_load_after_23 = {8'd0, dbg_ch3_load_after_i[23:16]};
assign dbg_ch3_load_after_15 = {8'd0, dbg_ch3_load_after_i[15:8]};
assign dbg_ch3_load_after_07 = {8'd0, dbg_ch3_load_after_i[7:0]};
assign dbg_update_reason = {8'hee, dbg_writer_bits_i};

// only AW=8 is needed for the CPU. Using AW=9
// to store the scratch value for lower
// 8-bit address of the current sample
// so it does not overwrite any register the CPU has
// access too.
// That register may actually be visible by
// the CPU, using cfg_addr=4'o17 for AW=8 seems to work fine too
jtframe_dual_ram #(.AW(9),.SIMHEXFILE(SIMHEXFILE)) u_ram(
    // Port 0: CPU
    .clk0   ( clk       ),
    .data0  ( cpu_dout  ),
    .addr0  ({1'b0,cpu_addr}),
    .we0    ( we        ),
    .q0     ( cpu_din   ),
    // Port 1
    .clk1   ( clk       ),
    .data1  ( cfg_din   ),
    .addr1  ( cfg_ram_addr ),
    .we1    ( cfg_we    ),
    .q1     ( cfg_data  )
);

always @(posedge clk) begin
    sample <= st==0 && cur_ch==0 && cen;
end

function signed [WD-1:0] clipDAC( input [15:0]s );
    clipDAC = (|s[15:WD-1] & ~&s[15:WD-1]) ? {s[15],{WD-1{~s[15]}}} : s[WD-1:0];
endfunction

function signed [15:0] clip_sum( input signed [15:0] a, input signed [WD-1:0] b );
    begin : clip_sum_func
        reg signed [16:0] full;
        full = { a[15],a } + { {17-WD{b[WD-1]}},b};
        clip_sum = full[16]==full[15] ? full[15:0] :
            full[16] ? 16'h8000 : 16'h7fff; // clip
    end
endfunction

always @* begin
    case( st )
         0: cfg_addr = 5'o16; // enable
         1: cfg_addr = 5'o20; // addr 7-0
         2: cfg_addr = 5'o14; // addr 15-8
         3: cfg_addr = 5'o15; // addr 23-16
         4: cfg_addr = 5'o07; // addr delta
         5: cfg_addr = 5'o04; // loop addr 15-8
         6: cfg_addr = 5'o05; // loop addr 23-16
         7: cfg_addr = 5'o06; // end addr
         8: cfg_addr = 5'o16; // enable (wr)
         9: cfg_addr = 5'o20; // addr  7- 0 (wr)
        10: cfg_addr = 5'o14; // addr 15- 8 (wr)
        11: cfg_addr = 5'o15; // addr 23-16 (wr)
        12: cfg_addr = 5'o02; // vol. left
        13: cfg_addr = 5'o03; // vol. right
        default: cfg_addr = 0;
    endcase

    vol_mux = st[0] ? vol_left : vol_right;
    case( st )
         8: begin cfg_we = 1;        cfg_din = cfg_en; end
         9: begin cfg_we = 1;        cfg_din = cur_addr[ 7: 0]; end
        10: begin cfg_we = !was_enb; cfg_din = cur_addr[15: 8]; end
        11: begin cfg_we = !was_enb; cfg_din = cur_addr[23:16]; end
        default: begin cfg_we = 0; cfg_din = 0; end
    endcase
end

always @(posedge clk) begin
    mul_data <= vol_mux * pcm_data;
end

// multiply by 2 and clip if needed
function signed [15:0] clip2x( input signed [15:0] s);
    clip2x = s[15]==s[14] ? {s[14:0],s[15]} : {s[15],{15{~s[15]}}};
endfunction

always @(posedge clk) begin
    st_dout <= debug_bus[0] ? active[15:8] : active[7:0];
end

always @(posedge clk) begin
    if( rst ) begin
        st        <= 0;
        cur_ch    <= 0;
        rom_cs    <= 0;
        rom_addr  <= 0;
        snd_left  <= 0;
        snd_right <= 0;
        acc_l     <= 0;
        acc_r     <= 0;
        cur_addr  <= 0;
        delta     <= 0;
        loop_addr <= 0;
        cfg_en    <= 0;
        vol_left  <= 0;
        vol_right <= 0;
        was_enb   <= 0;
        dbg_last_bank <= 0;
        dbg_last_ch <= 0;
        dbg_last_st <= 0;
        dbg_last_cur_addr <= 0;
        cfg_ram_addr_d <= 0;
        dbg_seq_en_addr <= 0;
        dbg_seq_en_value <= 0;
        dbg_seq_d0_addr <= 0;
        dbg_seq_d0_value <= 0;
        dbg_seq_d1_addr <= 0;
        dbg_seq_d1_value <= 0;
        dbg_seq_d2_addr <= 0;
        dbg_seq_d2_value <= 0;
        dbg_38686_en_addr_i <= 0;
        dbg_38686_en_value_i <= 0;
        dbg_38686_d0_addr_i <= 0;
        dbg_38686_d0_value_i <= 0;
        dbg_38686_d1_addr_i <= 0;
        dbg_38686_d1_value_i <= 0;
        dbg_38686_d2_addr_i <= 0;
        dbg_38686_d2_value_i <= 0;
        dbg_38686_cfg_en_i <= 0;
        dbg_38686_cur_23_i <= 0;
        dbg_38686_cur_15_i <= 0;
        dbg_38686_cur_07_i <= 0;
        dbg_38686_delta_i <= 0;
        dbg_ch3_enabled_seen_i <= 0;
        dbg_ch1_rom_seen_i <= 0;
        dbg_ch1_first_bank_i <= 0;
        dbg_ch1_first_addr_i <= 0;
        dbg_ch3_rom_seen_i <= 0;
        dbg_ch3_second_jump_i <= 0;
        dbg_ch3_jump_seen_i <= 0;
        dbg_ch3_rom_count_i <= 0;
        dbg_ch3_first_bank_i <= 0;
        dbg_ch3_first_addr_i <= 0;
        dbg_ch3_prev_addr_i <= 0;
        dbg_ch3_r0_addr_i <= 0;
        dbg_ch3_r1_addr_i <= 0;
        dbg_ch3_r2_addr_i <= 0;
        dbg_ch3_delta_i <= 0;
        dbg_update_state_i <= 0;
        dbg_update_channel_i <= 0;
        dbg_update_before_i <= 0;
        dbg_update_after_i <= 0;
        dbg_update_addend_i <= 0;
        dbg_update_reason_i <= 0;
        dbg_writer_bits_i <= 0;
        dbg_update_exact_seen_i <= 1'b0;
        dbg_ch3_roll_d0_addr_i <= 0;
        dbg_ch3_roll_d0_value_i <= 0;
        dbg_ch3_roll_d1_addr_i <= 0;
        dbg_ch3_roll_d1_value_i <= 0;
        dbg_ch3_roll_d2_addr_i <= 0;
        dbg_ch3_roll_d2_value_i <= 0;
        dbg_ch3_roll_load_after_i <= 0;
        dbg_ch3_roll_seen_i <= 3'd0;
        dbg_ch3_load_after_i <= 0;
        dbg_ch3_load_seen_i <= 3'd0;
        dbg_ch3_w9_addr_i <= 0;
        dbg_ch3_w9_value_i <= 0;
        dbg_ch3_wa_addr_i <= 0;
        dbg_ch3_wa_value_i <= 0;
        dbg_ch3_wb_addr_i <= 0;
        dbg_ch3_wb_value_i <= 0;
        dbg_ch3_wb_cur_addr_i <= 0;
        dbg_ch3_wb_seen_i <= 3'd0;
        dbg_ch3_wb_after_event_i <= 1'b0;
        dbg_prior_w9_addr_i <= 0;
        dbg_prior_w9_value_i <= 0;
        dbg_prior_wa_addr_i <= 0;
        dbg_prior_wa_value_i <= 0;
        dbg_prior_wb_addr_i <= 0;
        dbg_prior_wb_value_i <= 0;
        dbg_prior_wb_cur_addr_i <= 0;
        dbg_prior_flags_i <= 0;
        dbg_cpu_roll_u1_addr_i <= 0;
        dbg_cpu_roll_u1_value_i <= 0;
        dbg_cpu_roll_u2_addr_i <= 0;
        dbg_cpu_roll_u2_value_i <= 0;
        dbg_cpu_roll_u3_addr_i <= 0;
        dbg_cpu_roll_u3_value_i <= 0;
        dbg_cpu_roll_seen_i <= 3'd0;
        dbg_cpu_u1_addr_i <= 0;
        dbg_cpu_u1_value_i <= 0;
        dbg_cpu_u2_addr_i <= 0;
        dbg_cpu_u2_value_i <= 0;
        dbg_cpu_u3_addr_i <= 0;
        dbg_cpu_u3_value_i <= 0;
        dbg_cpu_flags_i <= 0;
        dbg_target_order_i <= 0;
        dbg_target1_addr_i <= 0;
        dbg_target1_value_i <= 0;
        dbg_target1_info_i <= 0;
        dbg_target2_addr_i <= 0;
        dbg_target2_value_i <= 0;
        dbg_target2_info_i <= 0;
        dbg_target3_addr_i <= 0;
        dbg_target3_value_i <= 0;
        dbg_target3_info_i <= 0;
        dbg_target_flags_i <= 0;
        dbg_read_flags_i <= 0;
        dbg_last_cpu_port_i <= 0;
        dbg_last_int_port_i <= 0;
        dbg_write_source_i <= 0;
        dbg_fs_start_seen_i <= 1'b0;
        dbg_fs_arm_i <= 1'b0;
        dbg_fs_load_seen_i <= 3'd0;
        dbg_fs_f1_data_i <= 0;
        dbg_fs_f2_data_i <= 0;
        dbg_fs_f3_data_i <= 0;
        dbg_fs_load_addr_i <= 0;
        dbg_fs_rom_seen_i <= 1'b0;
        dbg_fs_rom_bank_i <= 0;
        dbg_fs_rom_addr_i <= 0;
        dbg_fs_wb_seen_i <= 3'd0;
        dbg_fs_w9_data_i <= 0;
        dbg_fs_wa_data_i <= 0;
        dbg_fs_wb_data_i <= 0;
        dbg_fs_wb_addr_i <= 0;
        dbg_fs_delta_i <= 0;
        dbg_start_mirror_c0_i <= 0;
        dbg_start_mirror_c1_i <= 0;
        dbg_start_mirror_c2_i <= 0;
        dbg_start_mirror_ctl_i <= 0;
        dbg_start_sc0_i <= 0;
        dbg_start_sc1_i <= 0;
        dbg_start_sc2_i <= 0;
        dbg_start_ctl_i <= 0;
        dbg_start_ac0_i <= 0;
        dbg_start_ac1_i <= 0;
        dbg_start_ac2_i <= 0;
        dbg_start_actl_i <= 0;
        dbg_start_flags_i <= 0;
        dbg_start_init_ch3_pending_i <= 1'b0;
    end else begin
        if( we ) begin
`ifdef MEGAVGMDRIVE_SEGAPCM_START_INIT_TEST
            if( cpu_addr == 8'h9e && !cpu_dout[0] ) begin
                dbg_start_init_ch3_pending_i <= 1'b1;
            end
`endif
            if( !dbg_target_flags_i[7] ) begin
                case( {1'b0, cpu_addr} )
                    9'h118: begin
                        dbg_target1_addr_i <= {1'b0, cpu_addr};
                        dbg_target1_value_i <= cpu_dout;
                        dbg_target1_info_i <= {1'b0, dbg_target_order_i[6:0], 4'd0, 4'd0};
                        dbg_target_flags_i[0] <= 1'b1;
                        dbg_target_flags_i[3] <= (cpu_dout == 8'h36);
                        dbg_target_order_i <= dbg_target_order_i + 8'd1;
                    end
                    9'h09c: begin
                        dbg_target2_addr_i <= {1'b0, cpu_addr};
                        dbg_target2_value_i <= cpu_dout;
                        dbg_target2_info_i <= {1'b0, dbg_target_order_i[6:0], 4'd0, 4'd0};
                        dbg_last_cpu_port_i <= {cpu_addr, cpu_dout};
                        dbg_write_source_i <= {8'hc0, dbg_target_order_i};
                        dbg_target_flags_i[1] <= 1'b1;
                        dbg_target_flags_i[4] <= (cpu_dout == 8'h86);
                        dbg_target_order_i <= dbg_target_order_i + 8'd1;
                    end
                    9'h09d: begin
                        dbg_target3_addr_i <= {1'b0, cpu_addr};
                        dbg_target3_value_i <= cpu_dout;
                        dbg_target3_info_i <= {1'b0, dbg_target_order_i[6:0], 4'd0, 4'd0};
                        dbg_last_cpu_port_i <= {cpu_addr, cpu_dout};
                        dbg_write_source_i <= {8'hc0, dbg_target_order_i};
                        dbg_target_flags_i[2] <= 1'b1;
                        dbg_target_flags_i[5] <= (cpu_dout == 8'h86);
                        dbg_target_order_i <= dbg_target_order_i + 8'd1;
                    end
                    default: begin end
                endcase
            end
        end
        if(cen) begin
        if( we ) begin
            case( cpu_addr )
                8'h18: dbg_start_mirror_c0_i <= cpu_dout;
                8'h9c: dbg_start_mirror_c1_i <= cpu_dout;
                8'h9d: dbg_start_mirror_c2_i <= cpu_dout;
                8'h9e: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_START_INIT_TEST
                    if( !cpu_dout[0] ) begin
                        dbg_start_init_ch3_pending_i <= 1'b1;
                    end
`endif
                    if( !cpu_dout[0] && !dbg_fs_start_seen_i ) begin
                        dbg_fs_start_seen_i <= 1'b1;
                        dbg_fs_arm_i <= 1'b1;
                        dbg_fs_load_seen_i <= 3'd0;
                        dbg_fs_rom_seen_i <= 1'b0;
                        dbg_fs_wb_seen_i <= 3'd0;
                        dbg_start_sc0_i <= dbg_start_mirror_c0_i;
                        dbg_start_sc1_i <= dbg_start_mirror_c1_i;
                        dbg_start_sc2_i <= dbg_start_mirror_c2_i;
                        dbg_start_ctl_i <= dbg_start_mirror_ctl_i;
                        dbg_start_ac0_i <= dbg_start_mirror_c0_i;
                        dbg_start_ac1_i <= dbg_start_mirror_c1_i;
                        dbg_start_ac2_i <= dbg_start_mirror_c2_i;
                        dbg_start_actl_i <= cpu_dout;
                        dbg_start_flags_i[0] <= 1'b1;
                        dbg_start_flags_i[1] <= ({dbg_start_mirror_c2_i, dbg_start_mirror_c1_i, dbg_start_mirror_c0_i} == 24'h868636);
                        dbg_start_flags_i[2] <= ({dbg_start_mirror_c2_i, dbg_start_mirror_c1_i, dbg_start_mirror_c0_i} == 24'h868636);
                        dbg_start_flags_i[3] <= ({dbg_start_mirror_c2_i, dbg_start_mirror_c1_i} == 16'h0026);
                        dbg_start_flags_i[4] <= (cpu_dout[6:4] == 3'd3);
                        dbg_start_flags_i[5] <= dbg_start_mirror_ctl_i[0] && !cpu_dout[0];
                        dbg_start_flags_i[6] <= ({dbg_start_mirror_c2_i, dbg_start_mirror_c1_i, dbg_start_mirror_c0_i} == {dbg_start_mirror_c2_i, dbg_start_mirror_c1_i, 8'd0});
                    end
                    dbg_start_mirror_ctl_i <= cpu_dout;
                end
                default: begin end
            endcase
        end
        cfg_ram_addr_d <= cfg_ram_addr;
        st <= st + 1'd1;
        if( !dbg_target_flags_i[7] && cfg_we ) begin
            case( cfg_ram_addr )
                9'h118: begin
                    dbg_target1_addr_i <= cfg_ram_addr;
                    dbg_target1_value_i <= cfg_din;
                    dbg_target1_info_i <= {1'b1, dbg_target_order_i[6:0], st, cur_ch};
                    dbg_last_int_port_i <= {cfg_ram_addr[7:0], cfg_din};
                    dbg_write_source_i <= {1'b1, dbg_target_order_i[6:0], st, cur_ch};
                    dbg_target_flags_i[0] <= 1'b1;
                    dbg_target_flags_i[3] <= (cfg_din == 8'h36);
                    dbg_target_order_i <= dbg_target_order_i + 8'd1;
                end
                9'h09c: begin
                    dbg_target2_addr_i <= cfg_ram_addr;
                    dbg_target2_value_i <= cfg_din;
                    dbg_target2_info_i <= {1'b1, dbg_target_order_i[6:0], st, cur_ch};
                    dbg_last_int_port_i <= {cfg_ram_addr[7:0], cfg_din};
                    dbg_write_source_i <= {1'b1, dbg_target_order_i[6:0], st, cur_ch};
                    dbg_target_flags_i[1] <= 1'b1;
                    dbg_target_flags_i[4] <= (cfg_din == 8'h86);
                    dbg_target_order_i <= dbg_target_order_i + 8'd1;
                end
                9'h09d: begin
                    dbg_target3_addr_i <= cfg_ram_addr;
                    dbg_target3_value_i <= cfg_din;
                    dbg_target3_info_i <= {1'b1, dbg_target_order_i[6:0], st, cur_ch};
                    dbg_last_int_port_i <= {cfg_ram_addr[7:0], cfg_din};
                    dbg_write_source_i <= {1'b1, dbg_target_order_i[6:0], st, cur_ch};
                    dbg_target_flags_i[2] <= 1'b1;
                    dbg_target_flags_i[5] <= (cfg_din == 8'h86);
                    dbg_target_order_i <= dbg_target_order_i + 8'd1;
                end
                default: begin end
            endcase
        end
        case( st )
            0: begin
                dbg_seq_en_addr <= cfg_ram_addr_d;
                dbg_seq_en_value <= cfg_data;
`ifdef MEGAVGMDRIVE_SEGAPCM_START_INIT_TEST
                if( cur_ch == 4'd3 && !cfg_data[0] && !active[3] ) begin
                    dbg_start_init_ch3_pending_i <= 1'b1;
                end
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                if( cur_ch == SMOKE_CH ) begin
                    cfg_en  <= SMOKE_CFG;
                    was_enb <= 1'b0;
                end else begin
                    cfg_en  <= 8'h01;
                    was_enb <= 1'b1;
                end
`else
                cfg_en  <= cfg_data;
                was_enb <= cfg_data[0];
`endif
                if( cur_ch==0 ) begin
                    snd_left  <= acc_l;
                    snd_right <= acc_r;
                    acc_l     <= 0;
                    acc_r     <= 0;
                end
            end
            1: begin : st_load_low
                reg [23:0] next_cur_addr;
                reg [ 7:0] load_byte;
                load_byte = was_enb ? 8'd0 : cfg_data;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                load_byte = (cur_ch == SMOKE_CH) ? SMOKE_CUR[7:0] : 8'd0;
`elsif MEGAVGMDRIVE_SEGAPCM_START_INIT_TEST
                if( cur_ch == 4'd3 ) begin
                    load_byte = 8'h00;
                end
`endif
                next_cur_addr = {cur_addr[23:8], load_byte};
                dbg_seq_d0_addr <= cfg_ram_addr_d;
                dbg_seq_d0_value <= cfg_data;
                if( cur_ch == 4'd3 ) begin
                    dbg_ch3_roll_d0_addr_i <= cfg_ram_addr;
                    dbg_ch3_roll_d0_value_i <= load_byte;
                    dbg_ch3_roll_seen_i[0] <= 1'b1;
                    if( dbg_fs_arm_i && !dbg_fs_load_seen_i[0] ) begin
                        dbg_fs_f1_data_i <= load_byte;
                        dbg_fs_load_seen_i[0] <= 1'b1;
                    end
                    dbg_update_state_i <= st;
                    dbg_update_channel_i <= cur_ch;
                    dbg_update_before_i <= cur_addr;
                    dbg_update_after_i <= next_cur_addr;
                    dbg_update_addend_i <= load_byte;
                    dbg_update_reason_i <= 8'b0000_0001; // load low/start
                    dbg_writer_bits_i <= dbg_writer_bits_i | 8'b0000_0001;
                end
                cur_addr[ 7: 0]  <= load_byte;
            end
            2: begin : st_load_mid
                reg [23:0] next_cur_addr;
                reg [ 7:0] load_byte;
                load_byte = cfg_data;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                load_byte = (cur_ch == SMOKE_CH) ? SMOKE_CUR[15:8] : 8'd0;
`elsif MEGAVGMDRIVE_SEGAPCM_START_INIT_TEST
                if( cur_ch == 4'd3 ) begin
                    load_byte = 8'h26;
                end
`endif
                next_cur_addr = {cur_addr[23:16], load_byte, cur_addr[7:0]};
                dbg_seq_d1_addr <= cfg_ram_addr_d;
                dbg_seq_d1_value <= cfg_data;
                if( cur_ch == 4'd3 ) begin
                    dbg_ch3_roll_d1_addr_i <= cfg_ram_addr;
                    dbg_ch3_roll_d1_value_i <= load_byte;
                    dbg_ch3_roll_seen_i[1] <= 1'b1;
                    if( dbg_fs_arm_i && !dbg_fs_load_seen_i[1] ) begin
                        dbg_fs_f2_data_i <= load_byte;
                        dbg_fs_load_seen_i[1] <= 1'b1;
                    end
                    dbg_update_state_i <= st;
                    dbg_update_channel_i <= cur_ch;
                    dbg_update_before_i <= cur_addr;
                    dbg_update_after_i <= next_cur_addr;
                    dbg_update_addend_i <= load_byte;
                    dbg_update_reason_i <= 8'b0000_0010; // load mid/start
                    dbg_writer_bits_i <= dbg_writer_bits_i | 8'b0000_0010;
                end
                cur_addr[15: 8]  <= load_byte;
            end
            3: begin : st_load_high
                reg [23:0] next_cur_addr;
                reg [ 7:0] load_byte;
                load_byte = cfg_data;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                load_byte = (cur_ch == SMOKE_CH) ? SMOKE_CUR[23:16] : 8'd0;
`elsif MEGAVGMDRIVE_SEGAPCM_START_INIT_TEST
                if( cur_ch == 4'd3 ) begin
                    load_byte = 8'h00;
                end
`endif
                next_cur_addr = {load_byte, cur_addr[15:0]};
                dbg_seq_d2_addr <= cfg_ram_addr_d;
                dbg_seq_d2_value <= cfg_data;
                if( cur_ch == 4'd3 ) begin
                    dbg_ch3_roll_d2_addr_i <= cfg_ram_addr;
                    dbg_ch3_roll_d2_value_i <= load_byte;
                    dbg_ch3_roll_load_after_i <= next_cur_addr;
                    dbg_ch3_roll_seen_i[2] <= 1'b1;
                    if( dbg_fs_arm_i && !dbg_fs_load_seen_i[2] ) begin
                        dbg_fs_f3_data_i <= load_byte;
                        dbg_fs_load_addr_i <= next_cur_addr;
                        dbg_fs_load_seen_i[2] <= 1'b1;
                    end
`ifdef MEGAVGMDRIVE_SEGAPCM_START_INIT_TEST
                    begin
                        dbg_38686_d0_addr_i <= 9'h118;
                        dbg_38686_d0_value_i <= 8'h00;
                        dbg_38686_d1_addr_i <= 9'h09c;
                        dbg_38686_d1_value_i <= 8'h26;
                        dbg_38686_d2_addr_i <= 9'h09d;
                        dbg_38686_d2_value_i <= 8'h00;
                        dbg_ch3_load_after_i <= 24'h002600;
                        dbg_ch3_load_seen_i <= 3'b111;
                        dbg_read_flags_i <= {
                            1'b1,
                            (next_cur_addr == 24'h002600),
                            (load_byte == 8'h00),
                            (cur_addr[15:8] == 8'h26),
                            (cur_addr[7:0] == 8'h00),
                            (cfg_ram_addr == 9'h09d),
                            (dbg_ch3_roll_d1_addr_i == 9'h09c),
                            (dbg_ch3_roll_d0_addr_i == 9'h118)
                        };
                        dbg_start_init_ch3_pending_i <= 1'b0;
                    end
`endif
                    dbg_update_state_i <= st;
                    dbg_update_channel_i <= cur_ch;
                    dbg_update_before_i <= cur_addr;
                    dbg_update_after_i <= next_cur_addr;
                    dbg_update_addend_i <= load_byte;
                    dbg_update_reason_i <= 8'b0000_0100; // load high/start
                    dbg_writer_bits_i <= dbg_writer_bits_i | 8'b0000_0100;
                end
                cur_addr[23:16]  <= load_byte;
            end
            4: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                delta <= (cur_ch == SMOKE_CH) ? smoke_delta : 8'd0;
`else
                delta <= cfg_data;
`endif
            end
            5: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                loop_addr[15: 8] <= (cur_ch == SMOKE_CH) ? SMOKE_CUR[15:8] : 8'd0;
`else
                loop_addr[15: 8] <= cfg_data;
`endif
            end
            6: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                loop_addr[23:16] <= (cur_ch == SMOKE_CH) ? SMOKE_CUR[23:16] : 8'd0;
`else
                loop_addr[23:16] <= cfg_data;
`endif
            end
            7: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                if( cur_ch != SMOKE_CH && cur_addr[23:16] == (cfg_data + 8'b1) ) begin
`else
                if( cur_addr[23:16] == (cfg_data + 8'b1) ) begin
`endif
                if( cfg_en[1] ) begin : st_end_no_loop
                    reg [23:0] next_cur_addr;
                    next_cur_addr = {cur_addr[23:8], 8'd0};
                    if( !dbg_update_exact_seen_i && cur_ch == 4'd3 ) begin
                        dbg_update_state_i <= st;
                        dbg_update_channel_i <= cur_ch;
                        dbg_update_before_i <= cur_addr;
                        dbg_update_after_i <= next_cur_addr;
                        dbg_update_addend_i <= cfg_data;
                        dbg_update_reason_i <= 8'b0001_0000; // end/no-loop
                        dbg_writer_bits_i <= dbg_writer_bits_i | 8'b0001_0000;
                    end
                    cfg_en[0]     <= 1; // no loop
                    cur_addr[7:0] <= 0;
                end else begin : st_loop_reload
                    reg [23:0] next_cur_addr;
                    next_cur_addr = {loop_addr,8'd0};
                    if( !dbg_update_exact_seen_i && cur_ch == 4'd3 ) begin
                        dbg_update_state_i <= st;
                        dbg_update_channel_i <= cur_ch;
                        dbg_update_before_i <= cur_addr;
                        dbg_update_after_i <= next_cur_addr;
                        dbg_update_addend_i <= cfg_data;
                        dbg_update_reason_i <= 8'b0000_1000; // loop reload
                        dbg_writer_bits_i <= dbg_writer_bits_i | 8'b0000_1000;
                    end
                    cur_addr <= next_cur_addr; // loop around
                end
            end
            end
            8: if( !cfg_en[0] ) begin
                rom_cs   <= 1;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                rom_addr <= (cur_ch == SMOKE_CH) ?
                            { SMOKE_BANK, cur_addr[23:8] } :
                            { bank, cur_addr[23:8] };
`else
                rom_addr <= { bank, cur_addr[23:8] };
`endif
                if( cur_ch == 4'd1 && !dbg_ch1_rom_seen_i ) begin
                    dbg_ch1_rom_seen_i <= 1'b1;
                    dbg_ch1_first_bank_i <= bank;
                    dbg_ch1_first_addr_i <= cur_addr;
                end
                if( !dbg_update_exact_seen_i && cur_ch == 4'd3 ) begin
                    if( dbg_fs_arm_i && (dbg_fs_load_seen_i == 3'b111) && !dbg_fs_rom_seen_i ) begin
                        dbg_fs_rom_seen_i <= 1'b1;
                        dbg_fs_rom_bank_i <= bank;
                        dbg_fs_rom_addr_i <= cur_addr;
                        dbg_fs_delta_i <= delta;
                    end
                    dbg_ch3_enabled_seen_i <= 1'b1;
                    dbg_ch3_rom_seen_i <= 1'b1;
                    dbg_ch3_delta_i <= delta;
                    if( !dbg_ch3_enabled_seen_i ) begin
                        dbg_ch3_first_bank_i <= bank;
                        dbg_ch3_first_addr_i <= cur_addr;
                    end
                    if( dbg_ch3_rom_seen_i ) begin
                        if( (cur_addr[23:8] > (dbg_ch3_prev_addr_i[23:8] + 16'h0100)) ||
                            (dbg_ch3_prev_addr_i[23:8] > (cur_addr[23:8] + 16'h0100)) ) begin
                            dbg_ch3_jump_seen_i <= 1'b1;
                            if( dbg_ch3_rom_count_i == 2'd1 ) begin
                                dbg_ch3_second_jump_i <= 1'b1;
                            end
                        end
                    end
                    dbg_ch3_prev_addr_i <= cur_addr;
                    case( dbg_ch3_rom_count_i )
                        2'd0: begin
                            dbg_ch3_r0_addr_i <= cur_addr;
                            dbg_ch3_rom_count_i <= 2'd1;
                        end
                        2'd1: begin
                            dbg_ch3_r1_addr_i <= cur_addr;
                            dbg_ch3_rom_count_i <= 2'd2;
                        end
                        2'd2: begin
                            dbg_ch3_r2_addr_i <= cur_addr;
                            dbg_ch3_rom_count_i <= 2'd3;
                        end
                        default: begin
                            dbg_ch3_rom_count_i <= dbg_ch3_rom_count_i;
                        end
                    endcase
                end
                dbg_last_bank <= bank;
                dbg_last_ch <= cur_ch;
                dbg_last_st <= st;
                dbg_last_cur_addr <= cur_addr;
                begin : st_advance_addr
                    reg [23:0] next_cur_addr;
                    next_cur_addr = cur_addr + { 16'd0, delta };
                    if( (cur_ch == 4'd3) && ({ bank, cur_addr[23:8] } == 19'h38686) ) begin
                        dbg_update_exact_seen_i <= 1'b1;
                        if( !dbg_prior_flags_i[7] ) begin
                            dbg_prior_w9_addr_i <= dbg_ch3_w9_addr_i;
                            dbg_prior_w9_value_i <= dbg_ch3_w9_value_i;
                            dbg_prior_wa_addr_i <= dbg_ch3_wa_addr_i;
                            dbg_prior_wa_value_i <= dbg_ch3_wa_value_i;
                            dbg_prior_wb_addr_i <= dbg_ch3_wb_addr_i;
                            dbg_prior_wb_value_i <= dbg_ch3_wb_value_i;
                            dbg_prior_wb_cur_addr_i <= dbg_ch3_wb_cur_addr_i;
                            dbg_prior_flags_i <= {
                                1'b1,
                                (dbg_ch3_wb_cur_addr_i == 24'h868636),
                                (dbg_ch3_wb_value_i == 8'h86),
                                (dbg_ch3_wa_value_i == 8'h86),
                                (dbg_ch3_w9_value_i == 8'h36),
                                dbg_ch3_wb_seen_i[2],
                                dbg_ch3_wb_seen_i[1],
                                dbg_ch3_wb_seen_i[0]
                            };
                            dbg_target_flags_i[6] <= dbg_target_flags_i[0] && dbg_target_flags_i[1] && dbg_target_flags_i[2];
                            dbg_target_flags_i[7] <= 1'b1;
                            dbg_read_flags_i <= {
                                1'b1,
                                ((dbg_ch3_roll_d0_value_i != dbg_target1_value_i) ||
                                 (dbg_ch3_roll_d1_value_i != dbg_target2_value_i) ||
                                 (dbg_ch3_roll_d2_value_i != dbg_target3_value_i)),
                                (dbg_ch3_roll_d2_value_i == 8'h86),
                                (dbg_ch3_roll_d1_value_i == 8'h86),
                                (dbg_ch3_roll_d0_value_i == 8'h36),
                                (dbg_ch3_roll_d2_addr_i == 9'h09d),
                                (dbg_ch3_roll_d1_addr_i == 9'h09c),
                                (dbg_ch3_roll_d0_addr_i == 9'h118)
                            };
                        end
                        dbg_38686_d0_addr_i <= dbg_ch3_roll_d0_addr_i;
                        dbg_38686_d0_value_i <= dbg_ch3_roll_d0_value_i;
                        dbg_38686_d1_addr_i <= dbg_ch3_roll_d1_addr_i;
                        dbg_38686_d1_value_i <= dbg_ch3_roll_d1_value_i;
                        dbg_38686_d2_addr_i <= dbg_ch3_roll_d2_addr_i;
                        dbg_38686_d2_value_i <= dbg_ch3_roll_d2_value_i;
                        dbg_ch3_load_after_i <= dbg_ch3_roll_load_after_i;
                        dbg_ch3_load_seen_i <= dbg_ch3_roll_seen_i;
                        dbg_38686_en_addr_i <= dbg_seq_en_addr;
                        dbg_38686_en_value_i <= dbg_seq_en_value;
                        dbg_38686_cfg_en_i <= cfg_en;
                        dbg_38686_cur_23_i <= cur_addr[23:16];
                        dbg_38686_cur_15_i <= cur_addr[15:8];
                        dbg_38686_cur_07_i <= cur_addr[7:0];
                        dbg_38686_delta_i <= delta;
                        dbg_update_state_i <= st;
                        dbg_update_channel_i <= cur_ch;
                        dbg_update_before_i <= cur_addr;
                        dbg_update_after_i <= next_cur_addr;
                        dbg_update_addend_i <= delta;
                        dbg_update_reason_i <= 8'b0010_0000; // exact 0x38686 advance
                        dbg_writer_bits_i <= dbg_writer_bits_i | 8'b0010_0000;
                    end else if( !dbg_update_exact_seen_i && cur_ch == 4'd3 ) begin
                        dbg_update_state_i <= st;
                        dbg_update_channel_i <= cur_ch;
                        dbg_update_before_i <= cur_addr;
                        dbg_update_after_i <= next_cur_addr;
                        dbg_update_addend_i <= delta;
                        dbg_update_reason_i <= 8'b0010_0000; // advance
                        dbg_writer_bits_i <= dbg_writer_bits_i | 8'b0010_0000;
                    end
                    cur_addr <= next_cur_addr;
                end
            end

            9: begin
                if( cur_ch == 4'd3 && cfg_we ) begin
                    dbg_ch3_w9_addr_i <= cfg_ram_addr;
                    dbg_ch3_w9_value_i <= cfg_din;
                    dbg_start_mirror_c0_i <= cfg_din;
                    dbg_ch3_wb_cur_addr_i <= cur_addr;
                    dbg_ch3_wb_seen_i[0] <= 1'b1;
                    dbg_ch3_wb_after_event_i <= dbg_ch3_wb_after_event_i | dbg_update_exact_seen_i;
                    if( dbg_fs_rom_seen_i && !dbg_fs_wb_seen_i[0] ) begin
                        dbg_fs_w9_data_i <= cfg_din;
                        dbg_fs_wb_addr_i <= cur_addr;
                        dbg_fs_wb_seen_i[0] <= 1'b1;
                    end
                    dbg_update_after_i <= cur_addr;
                end
            end
            10: begin
                if( cur_ch == 4'd3 && cfg_we ) begin
                    dbg_ch3_wa_addr_i <= cfg_ram_addr;
                    dbg_ch3_wa_value_i <= cfg_din;
                    dbg_start_mirror_c1_i <= cfg_din;
                    dbg_ch3_wb_cur_addr_i <= cur_addr;
                    dbg_ch3_wb_seen_i[1] <= 1'b1;
                    dbg_ch3_wb_after_event_i <= dbg_ch3_wb_after_event_i | dbg_update_exact_seen_i;
                    if( dbg_fs_rom_seen_i && !dbg_fs_wb_seen_i[1] ) begin
                        dbg_fs_wa_data_i <= cfg_din;
                        dbg_fs_wb_addr_i <= cur_addr;
                        dbg_fs_wb_seen_i[1] <= 1'b1;
                    end
                    dbg_update_after_i <= cur_addr;
                end
            end
            11: begin
                if( cur_ch == 4'd3 && cfg_we ) begin
                    dbg_ch3_wb_addr_i <= cfg_ram_addr;
                    dbg_ch3_wb_value_i <= cfg_din;
                    dbg_start_mirror_c2_i <= cfg_din;
                    dbg_ch3_wb_cur_addr_i <= cur_addr;
                    dbg_ch3_wb_seen_i[2] <= 1'b1;
                    dbg_ch3_wb_after_event_i <= dbg_ch3_wb_after_event_i | dbg_update_exact_seen_i;
                    if( dbg_fs_rom_seen_i && !dbg_fs_wb_seen_i[2] ) begin
                        dbg_fs_wb_data_i <= cfg_din;
                        dbg_fs_wb_addr_i <= cur_addr;
                        dbg_fs_wb_seen_i[2] <= 1'b1;
                    end
                    dbg_update_after_i <= cur_addr;
                end
            end
            12: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                vol_left <= (cur_ch == SMOKE_CH) ? {1'b0, smoke_vol_l} : 8'sd0;
`else
                vol_left <= {1'b0, cfg_data[6:0]};
`endif
            end
            13: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                vol_right <= (cur_ch == SMOKE_CH) ? {1'b0, smoke_vol_r} : 8'sd0;
`else
                vol_right <= {1'b0, cfg_data[6:0]};
`endif
            end
            14: begin
                rom_cs  <= 0; // ROM data must be good by now
                buf_r   <= clipDAC(mul_data);
            end
            15: begin
                active[cur_ch] <= ~was_enb;
                cur_ch <= cur_ch + 1'd1;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                if( !cfg_en[0] && cur_ch == SMOKE_CH ) begin
                    acc_r <= clip_sum( acc_r, buf_r);
                    acc_l <= clip_sum( acc_l, clipDAC(mul_data));
                end
`else
                if( !cfg_en[0] ) begin
                    acc_r <= clip_sum( acc_r, buf_r);
                    acc_l <= clip_sum( acc_l, clipDAC(mul_data));
                end
`endif
            end
        endcase
        end
    end
end

endmodule
