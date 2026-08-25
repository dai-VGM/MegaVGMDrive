`timescale 1ns/1ps

// Register-semantic classifier for the standard-YM2610 profile.  The decode
// intentionally mirrors ym2610_hw0_jt12_mmr.v instead of treating bit 31 in
// the VGM clock field as an instruction to silently enable six FM channels.
module ym2610_player_compat (
    input  logic       port,
    input  logic [7:0] address,
    input  logic [7:0] data,
    output logic       accepted,
    output logic       b_only,
    output logic       unknown,
    output logic [3:0] semantic,
    output logic [2:0] target
);
    localparam logic [3:0] SEM_NONE    = 4'd0;
    localparam logic [3:0] SEM_SSG     = 4'd1;
    localparam logic [3:0] SEM_GLOBAL  = 4'd2;
    localparam logic [3:0] SEM_ADPCMA  = 4'd3;
    localparam logic [3:0] SEM_ADPCMB  = 4'd4;
    localparam logic [3:0] SEM_FM_OP   = 4'd5;
    localparam logic [3:0] SEM_FM_FREQ = 4'd6;
    localparam logic [3:0] SEM_FM_CTRL = 4'd7;
    localparam logic [3:0] SEM_FM_KEY  = 4'd8;
    localparam logic [3:0] SEM_FM_CH3  = 4'd9;

    logic [2:0] selector;

    always_comb begin
        accepted = 1'b0;
        b_only = 1'b0;
        unknown = 1'b0;
        semantic = SEM_NONE;
        target = 3'd7;
        selector = {1'b0, address[1:0]};

        if (!port && address <= 8'h0f) begin
            accepted = 1'b1;
            semantic = SEM_SSG;
            target = {2'b00, address[1]};
        end else if (!port &&
                     (address == 8'h10 || address == 8'h11 ||
                      address == 8'h12 || address == 8'h13 ||
                      address == 8'h14 || address == 8'h15 ||
                      address == 8'h19 || address == 8'h1a ||
                      address == 8'h1b || address == 8'h1c)) begin
            accepted = 1'b1;
            semantic = SEM_ADPCMB;
            target = 3'd0;
        end else if (port &&
                     (address == 8'h00 || address == 8'h01 ||
                      // JT10 names 02 as the ADPCM-A test register and
                      // deliberately gives it no state-update action.
                      address == 8'h02 ||
                      (address >= 8'h08 && address <= 8'h0d) ||
                      (address >= 8'h10 && address <= 8'h15) ||
                      (address >= 8'h18 && address <= 8'h1d) ||
                      (address >= 8'h20 && address <= 8'h25) ||
                      (address >= 8'h28 && address <= 8'h2d))) begin
            accepted = 1'b1;
            semantic = SEM_ADPCMA;
            target = address[2:0];
        end else if (!port &&
                     (address == 8'h21 || address == 8'h22 ||
                      (address >= 8'h24 && address <= 8'h27) ||
                      address == 8'h29 ||
                      (address >= 8'h2d && address <= 8'h2f))) begin
            accepted = 1'b1;
            semantic = SEM_GLOBAL;
            target = 3'd0;
        end else if (!port && address == 8'h28) begin
            semantic = SEM_FM_KEY;
            selector = data[2:0];
            target = data[2:0];
            if (selector == 3'd1 || selector == 3'd2 ||
                selector == 3'd5 || selector == 3'd6)
                accepted = 1'b1;
            else if (selector == 3'd0 || selector == 3'd4)
                b_only = 1'b1;
            else
                unknown = 1'b1;
        end else if (address >= 8'h30 && address <= 8'h9f) begin
            semantic = SEM_FM_OP;
            target = {port, address[1:0]};
            if (address[1:0] == 2'd0 ||
                address[1:0] == 2'd1 || address[1:0] == 2'd2)
                accepted = 1'b1;
            else begin
                // Low selector 0 addresses the two FM slots that share the
                // YM2610 output timeslots with ADPCM-A/B.  JT10 retains their
                // register state, but its standard-YM2610 accumulator discards
                // their FM output.  Operator writes are therefore harmless;
                // key/frequency/channel-control access remains B-only below.
                // Low selector 3 is the physical FM channel hole.  JT10
                // explicitly clears every operator/channel update pulse for
                // it, so real chip-initialization writes are harmless.
                accepted = 1'b1;
            end
        end else if ((address == 8'ha0 || address == 8'ha1 || address == 8'ha2 ||
                      address == 8'ha4 || address == 8'ha5 || address == 8'ha6 ||
                      address == 8'hb0 || address == 8'hb1 || address == 8'hb2 ||
                      address == 8'hb4 || address == 8'hb5 || address == 8'hb6)) begin
            semantic = (address[7:4] == 4'ha) ? SEM_FM_FREQ : SEM_FM_CTRL;
            target = {port, address[1:0]};
            if (address[1:0] == 2'd1 || address[1:0] == 2'd2)
                accepted = 1'b1;
            else
                b_only = 1'b1;
        end else if (!port &&
                     (address == 8'ha8 || address == 8'ha9 || address == 8'haa ||
                      address == 8'hac || address == 8'had || address == 8'hae)) begin
            accepted = 1'b1;
            semantic = SEM_FM_CH3;
            target = 3'd2;
        end else begin
            unknown = 1'b1;
        end
    end
endmodule
