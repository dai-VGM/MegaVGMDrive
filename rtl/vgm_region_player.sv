// Synthesizable fixed-region VGM player for first MiSTer hardware bring-up.
//
// This is intentionally tiny: it does not load files, parse VGZ, handle loops,
// or expose an SD/HPS interface. It only plays one built-in VGM-like command
// region after reset/start, then stops.
//
// Connect this module to md_sound_module like this:
//
//   vgm_region_player -> ym_cmd_valid/port/reg/data -> md_sound_module
//                     -> psg_cmd_valid/data          -> md_sound_module
//
// Wait commands count audio_sample_valid rising edges, so the timing is tied
// to the same sample strobe used by the simulation WAV dumper.

module vgm_region_player (
    input  logic       clk,
    input  logic       reset,

    // Hold high to auto-start after reset, or pulse high to start once.
    input  logic       start,

    // New sample strobe from md_sound_module. Used for VGM wait timing.
    input  logic       audio_sample_valid,

    // Command-ready handshakes from md_sound_module.
    input  logic       ym_cmd_ready,
    input  logic       psg_cmd_ready,

    // YM2612 command output, matching md_sound_module inputs.
    output logic       ym_cmd_valid,
    output logic       ym_cmd_port,
    output logic [7:0] ym_cmd_reg,
    output logic [7:0] ym_cmd_data,

    // SN76489 command output, matching md_sound_module inputs.
    output logic       psg_cmd_valid,
    output logic [7:0] psg_cmd_data,

    // Bring-up status.
    output logic       busy,
    output logic       done,
    output logic [9:0] pc_debug,
    output logic [7:0] last_cmd_debug
);

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_FETCH,
        ST_DECODE,
        ST_YM_WAIT_READY,
        ST_YM_PULSE,
        ST_PSG_WAIT_READY,
        ST_PSG_PULSE,
        ST_WAIT_SAMPLES,
        ST_DONE
    } state_t;

    state_t state;

    logic [9:0] pc;
    logic [7:0] cmd;

    logic [15:0] wait_remaining;
    logic        audio_sample_valid_d;

    logic [9:0] pcm_pos;

    assign pc_debug = pc;

    // Small fixed command ROM.
    //
    // Supported opcodes in this bring-up ROM:
    //   0x52 rr dd       YM2612 port 0 write
    //   0x50 dd          SN76489 write
    //   0x61 ll hh       wait n samples
    //   0x70-0x7f        short wait 1..16 samples
    //   0xe0 oooo        PCM bank seek, used by following 0x80-0x8f commands
    //   0x80-0x8f        generate YM 0x2A DAC data write, then wait low nibble
    //   0x66             end
    //
    // The YM register sequence is a compact channel-1 tone based on the
    // successful TEST_YM_TONE setup, plus a short PSG tone and tiny DAC blip.
    function automatic logic [7:0] rom_byte(input logic [9:0] addr);
        unique case (addr)
            // YM setup: LFO/timer/DAC off/key off.
            10'd0:   rom_byte = 8'h52; 10'd1:   rom_byte = 8'h28; 10'd2:   rom_byte = 8'h00;
            10'd3:   rom_byte = 8'h52; 10'd4:   rom_byte = 8'h22; 10'd5:   rom_byte = 8'h00;
            10'd6:   rom_byte = 8'h52; 10'd7:   rom_byte = 8'h27; 10'd8:   rom_byte = 8'h00;
            10'd9:   rom_byte = 8'h52; 10'd10:  rom_byte = 8'h2B; 10'd11:  rom_byte = 8'h00;

            // Detune/multiple.
            10'd12:  rom_byte = 8'h52; 10'd13:  rom_byte = 8'h30; 10'd14:  rom_byte = 8'h01;
            10'd15:  rom_byte = 8'h52; 10'd16:  rom_byte = 8'h34; 10'd17:  rom_byte = 8'h01;
            10'd18:  rom_byte = 8'h52; 10'd19:  rom_byte = 8'h38; 10'd20:  rom_byte = 8'h01;
            10'd21:  rom_byte = 8'h52; 10'd22:  rom_byte = 8'h3C; 10'd23:  rom_byte = 8'h01;

            // Total level.
            10'd24:  rom_byte = 8'h52; 10'd25:  rom_byte = 8'h40; 10'd26:  rom_byte = 8'h28;
            10'd27:  rom_byte = 8'h52; 10'd28:  rom_byte = 8'h44; 10'd29:  rom_byte = 8'h28;
            10'd30:  rom_byte = 8'h52; 10'd31:  rom_byte = 8'h48; 10'd32:  rom_byte = 8'h28;
            10'd33:  rom_byte = 8'h52; 10'd34:  rom_byte = 8'h4C; 10'd35:  rom_byte = 8'h28;

            // Attack rate.
            10'd36:  rom_byte = 8'h52; 10'd37:  rom_byte = 8'h50; 10'd38:  rom_byte = 8'h1F;
            10'd39:  rom_byte = 8'h52; 10'd40:  rom_byte = 8'h54; 10'd41:  rom_byte = 8'h1F;
            10'd42:  rom_byte = 8'h52; 10'd43:  rom_byte = 8'h58; 10'd44:  rom_byte = 8'h1F;
            10'd45:  rom_byte = 8'h52; 10'd46:  rom_byte = 8'h5C; 10'd47:  rom_byte = 8'h1F;

            // Decay/sustain/release.
            10'd48:  rom_byte = 8'h52; 10'd49:  rom_byte = 8'h60; 10'd50:  rom_byte = 8'h00;
            10'd51:  rom_byte = 8'h52; 10'd52:  rom_byte = 8'h64; 10'd53:  rom_byte = 8'h00;
            10'd54:  rom_byte = 8'h52; 10'd55:  rom_byte = 8'h68; 10'd56:  rom_byte = 8'h00;
            10'd57:  rom_byte = 8'h52; 10'd58:  rom_byte = 8'h6C; 10'd59:  rom_byte = 8'h00;
            10'd60:  rom_byte = 8'h52; 10'd61:  rom_byte = 8'h80; 10'd62:  rom_byte = 8'h0F;
            10'd63:  rom_byte = 8'h52; 10'd64:  rom_byte = 8'h84; 10'd65:  rom_byte = 8'h0F;
            10'd66:  rom_byte = 8'h52; 10'd67:  rom_byte = 8'h88; 10'd68:  rom_byte = 8'h0F;
            10'd69:  rom_byte = 8'h52; 10'd70:  rom_byte = 8'h8C; 10'd71:  rom_byte = 8'h0F;

            // Frequency, algorithm, pan, key on.
            10'd72:  rom_byte = 8'h52; 10'd73:  rom_byte = 8'hA4; 10'd74:  rom_byte = 8'h22;
            10'd75:  rom_byte = 8'h52; 10'd76:  rom_byte = 8'hA0; 10'd77:  rom_byte = 8'h69;
            10'd78:  rom_byte = 8'h52; 10'd79:  rom_byte = 8'hB0; 10'd80:  rom_byte = 8'h07;
            10'd81:  rom_byte = 8'h52; 10'd82:  rom_byte = 8'hB4; 10'd83:  rom_byte = 8'hC0;
            10'd84:  rom_byte = 8'h52; 10'd85:  rom_byte = 8'h28; 10'd86:  rom_byte = 8'hF0;

            // PSG tone, same basic command shape as TEST_PSG_TONE.
            10'd87:  rom_byte = 8'h50; 10'd88:  rom_byte = 8'h9F;
            10'd89:  rom_byte = 8'h50; 10'd90:  rom_byte = 8'hBF;
            10'd91:  rom_byte = 8'h50; 10'd92:  rom_byte = 8'hDF;
            10'd93:  rom_byte = 8'h50; 10'd94:  rom_byte = 8'hFF;
            10'd95:  rom_byte = 8'h50; 10'd96:  rom_byte = 8'h80;
            10'd97:  rom_byte = 8'h50; 10'd98:  rom_byte = 8'h10;
            10'd99:  rom_byte = 8'h50; 10'd100: rom_byte = 8'h90;

            // Let FM+PSG ring for about 2048 samples.
            10'd101: rom_byte = 8'h61; 10'd102: rom_byte = 8'h00; 10'd103: rom_byte = 8'h08;

            // Tiny DAC exercise: enable DAC, seek mini PCM bank, stream bytes.
            10'd104: rom_byte = 8'h52; 10'd105: rom_byte = 8'h2B; 10'd106: rom_byte = 8'h80;
            10'd107: rom_byte = 8'hE0; 10'd108: rom_byte = 8'h00; 10'd109: rom_byte = 8'h00;
            10'd110: rom_byte = 8'h00; 10'd111: rom_byte = 8'h00;
            10'd112: rom_byte = 8'h84;
            10'd113: rom_byte = 8'h84;
            10'd114: rom_byte = 8'h84;
            10'd115: rom_byte = 8'h84;
            10'd116: rom_byte = 8'h84;
            10'd117: rom_byte = 8'h84;
            10'd118: rom_byte = 8'h84;
            10'd119: rom_byte = 8'h84;
            10'd120: rom_byte = 8'h52; 10'd121: rom_byte = 8'h2B; 10'd122: rom_byte = 8'h00;

            // Explicit silence sequence for hardware bring-up:
            // key off FM ch1, clear DAC data, keep DAC disabled, mute all PSG
            // channels, then wait briefly before reporting end.
            10'd123: rom_byte = 8'h52; 10'd124: rom_byte = 8'h28; 10'd125: rom_byte = 8'h00;
            10'd126: rom_byte = 8'h52; 10'd127: rom_byte = 8'h2A; 10'd128: rom_byte = 8'h00;
            10'd129: rom_byte = 8'h52; 10'd130: rom_byte = 8'h2B; 10'd131: rom_byte = 8'h00;
            10'd132: rom_byte = 8'h50; 10'd133: rom_byte = 8'h9F;
            10'd134: rom_byte = 8'h50; 10'd135: rom_byte = 8'hBF;
            10'd136: rom_byte = 8'h50; 10'd137: rom_byte = 8'hDF;
            10'd138: rom_byte = 8'h50; 10'd139: rom_byte = 8'hFF;

            // Let the silence writes settle, then stop.
            10'd140: rom_byte = 8'h61; 10'd141: rom_byte = 8'h00; 10'd142: rom_byte = 8'h04;
            10'd143: rom_byte = 8'h66;

            default: rom_byte = 8'h66;
        endcase
    endfunction

    function automatic logic [7:0] pcm_byte(input logic [9:0] index);
        unique case (index[3:0])
            4'h0: pcm_byte = 8'h80;
            4'h1: pcm_byte = 8'h98;
            4'h2: pcm_byte = 8'hB0;
            4'h3: pcm_byte = 8'hD0;
            4'h4: pcm_byte = 8'hF0;
            4'h5: pcm_byte = 8'hD0;
            4'h6: pcm_byte = 8'hB0;
            4'h7: pcm_byte = 8'h98;
            4'h8: pcm_byte = 8'h80;
            4'h9: pcm_byte = 8'h68;
            4'hA: pcm_byte = 8'h50;
            4'hB: pcm_byte = 8'h30;
            4'hC: pcm_byte = 8'h10;
            4'hD: pcm_byte = 8'h30;
            4'hE: pcm_byte = 8'h50;
            default: pcm_byte = 8'h68;
        endcase
    endfunction

    wire audio_sample_edge = audio_sample_valid && !audio_sample_valid_d;

    always_ff @(posedge clk) begin
        if (reset) begin
            state                <= ST_IDLE;
            pc                   <= 10'd0;
            cmd                  <= 8'h00;
            wait_remaining       <= 16'd0;
            pcm_pos              <= 10'd0;
            audio_sample_valid_d <= 1'b0;

            ym_cmd_valid         <= 1'b0;
            ym_cmd_port          <= 1'b0;
            ym_cmd_reg           <= 8'h00;
            ym_cmd_data          <= 8'h00;
            psg_cmd_valid        <= 1'b0;
            psg_cmd_data         <= 8'h00;

            busy                 <= 1'b0;
            done                 <= 1'b0;
            last_cmd_debug       <= 8'h00;
        end else begin
            audio_sample_valid_d <= audio_sample_valid;
            ym_cmd_valid         <= 1'b0;
            psg_cmd_valid        <= 1'b0;

            unique case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    done <= 1'b0;
                    if (start) begin
                        pc    <= 10'd0;
                        busy  <= 1'b1;
                        state <= ST_FETCH;
                    end
                end

                ST_FETCH: begin
                    cmd            <= rom_byte(pc);
                    last_cmd_debug <= rom_byte(pc);
                    state          <= ST_DECODE;
                end

                ST_DECODE: begin
                    unique case (cmd)
                        8'h52: begin
                            ym_cmd_port <= 1'b0;
                            ym_cmd_reg  <= rom_byte(pc + 10'd1);
                            ym_cmd_data <= rom_byte(pc + 10'd2);
                            state       <= ST_YM_WAIT_READY;
                        end

                        8'h53: begin
                            ym_cmd_port <= 1'b1;
                            ym_cmd_reg  <= rom_byte(pc + 10'd1);
                            ym_cmd_data <= rom_byte(pc + 10'd2);
                            state       <= ST_YM_WAIT_READY;
                        end

                        8'h50: begin
                            psg_cmd_data <= rom_byte(pc + 10'd1);
                            state        <= ST_PSG_WAIT_READY;
                        end

                        8'h61: begin
                            wait_remaining <= {rom_byte(pc + 10'd2), rom_byte(pc + 10'd1)};
                            pc             <= pc + 10'd3;
                            state          <= ST_WAIT_SAMPLES;
                        end

                        8'h62: begin
                            wait_remaining <= 16'd735;
                            pc             <= pc + 10'd1;
                            state          <= ST_WAIT_SAMPLES;
                        end

                        8'h63: begin
                            wait_remaining <= 16'd882;
                            pc             <= pc + 10'd1;
                            state          <= ST_WAIT_SAMPLES;
                        end

                        8'h66: begin
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            state <= ST_DONE;
                        end

                        8'hE0: begin
                            // Only a tiny local PCM bank is implemented here,
                            // so the high offset bits are intentionally ignored.
                            pcm_pos <= {2'b00, rom_byte(pc + 10'd1)};
                            pc      <= pc + 10'd5;
                            state   <= ST_FETCH;
                        end

                        default: begin
                            if (cmd[7:4] == 4'h7) begin
                                wait_remaining <= {12'd0, cmd[3:0]} + 16'd1;
                                pc             <= pc + 10'd1;
                                state          <= ST_WAIT_SAMPLES;
                            end else if (cmd[7:4] == 4'h8) begin
                                ym_cmd_port <= 1'b0;
                                ym_cmd_reg  <= 8'h2A;
                                ym_cmd_data <= pcm_byte(pcm_pos);
                                pcm_pos     <= pcm_pos + 10'd1;
                                state       <= ST_YM_WAIT_READY;
                            end else begin
                                // Unknown command in this fixed region:
                                // stop rather than running off into garbage.
                                busy  <= 1'b0;
                                done  <= 1'b1;
                                state <= ST_DONE;
                            end
                        end
                    endcase
                end

                ST_YM_WAIT_READY: begin
                    if (ym_cmd_ready) begin
                        ym_cmd_valid <= 1'b1;
                        state        <= ST_YM_PULSE;
                    end
                end

                ST_YM_PULSE: begin
                    if (cmd[7:4] == 4'h8) begin
                        wait_remaining <= {12'd0, cmd[3:0]};
                        pc             <= pc + 10'd1;
                        state          <= ST_WAIT_SAMPLES;
                    end else begin
                        pc    <= pc + 10'd3;
                        state <= ST_FETCH;
                    end
                end

                ST_PSG_WAIT_READY: begin
                    if (psg_cmd_ready) begin
                        psg_cmd_valid <= 1'b1;
                        state         <= ST_PSG_PULSE;
                    end
                end

                ST_PSG_PULSE: begin
                    pc    <= pc + 10'd2;
                    state <= ST_FETCH;
                end

                ST_WAIT_SAMPLES: begin
                    if (wait_remaining == 16'd0) begin
                        state <= ST_FETCH;
                    end else if (audio_sample_edge) begin
                        wait_remaining <= wait_remaining - 16'd1;
                    end
                end

                ST_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    if (!start) begin
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_DONE;
                    busy  <= 1'b0;
                    done  <= 1'b1;
                end
            endcase
        end
    end

endmodule

// Convenience wrapper for the first hardware smoke test.
//
// A MiSTer/top-level experiment can instantiate this wrapper directly and route
// audio_l/audio_r to the platform audio output. For a larger design, instantiate
// vgm_region_player and md_sound_module separately and keep the same wiring.
module md_sound_fixed_region_test (
    input  logic              clk,
    input  logic              reset,
    input  logic              start,

    output signed      [15:0] audio_l,
    output signed      [15:0] audio_r,
    output logic              audio_sample_valid,

    output logic              player_busy,
    output logic              player_done,
    output logic        [9:0] player_pc_debug,
    output logic        [7:0] player_last_cmd_debug
);

    logic       ym_cmd_valid;
    logic       ym_cmd_port;
    logic [7:0] ym_cmd_reg;
    logic [7:0] ym_cmd_data;
    logic       psg_cmd_valid;
    logic [7:0] psg_cmd_data;
    logic       ym_cmd_ready;
    logic       psg_cmd_ready;

    vgm_region_player player (
        .clk                   (clk),
        .reset                 (reset),
        .start                 (start),
        .audio_sample_valid    (audio_sample_valid),
        .ym_cmd_ready          (ym_cmd_ready),
        .psg_cmd_ready         (psg_cmd_ready),
        .ym_cmd_valid          (ym_cmd_valid),
        .ym_cmd_port           (ym_cmd_port),
        .ym_cmd_reg            (ym_cmd_reg),
        .ym_cmd_data           (ym_cmd_data),
        .psg_cmd_valid         (psg_cmd_valid),
        .psg_cmd_data          (psg_cmd_data),
        .busy                  (player_busy),
        .done                  (player_done),
        .pc_debug              (player_pc_debug),
        .last_cmd_debug        (player_last_cmd_debug)
    );

    md_sound_module sound (
        .clk                   (clk),
        .reset                 (reset),
        .ym_cmd_valid          (ym_cmd_valid),
        .ym_cmd_port           (ym_cmd_port),
        .ym_cmd_reg            (ym_cmd_reg),
        .ym_cmd_data           (ym_cmd_data),
        .psg_cmd_valid         (psg_cmd_valid),
        .psg_cmd_data          (psg_cmd_data),
        .ym_cmd_ready          (ym_cmd_ready),
        .psg_cmd_ready         (psg_cmd_ready),
        .audio_l               (audio_l),
        .audio_r               (audio_r),
        .audio_sample_valid    (audio_sample_valid)
    );

endmodule
