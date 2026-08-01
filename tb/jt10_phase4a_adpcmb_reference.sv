`timescale 1ns/1ps

// Source-derived arithmetic helpers for the Phase 4A testbench.  These are
// deliberately independent of DUT procedural state.  The testbench supplies
// pre-edge state and checks the returned value against post-edge DUT state.
package jt10_phase4a_adpcmb_reference;
    localparam logic [63:0] FNV_OFFSET = 64'hcbf29ce484222325;

    function automatic logic [63:0] hash_byte(
        input logic [63:0] hash_in,
        input logic [7:0] value
    );
        hash_byte = (hash_in ^ value) * 64'h00000100000001b3;
    endfunction

    function automatic logic [63:0] hash_u16(
        input logic [63:0] hash_in,
        input logic [15:0] value
    );
        logic [63:0] work;
        begin
            work = hash_byte(hash_in, value[7:0]);
            hash_u16 = hash_byte(work, value[15:8]);
        end
    endfunction

    function automatic logic [63:0] hash_u24(
        input logic [63:0] hash_in,
        input logic [23:0] value
    );
        logic [63:0] work;
        begin
            work = hash_byte(hash_in, value[7:0]);
            work = hash_byte(work, value[15:8]);
            hash_u24 = hash_byte(work, value[23:16]);
        end
    endfunction

    function automatic logic [63:0] hash_stereo(
        input logic [63:0] hash_in,
        input logic [15:0] left_value,
        input logic [15:0] right_value
    );
        logic [63:0] work;
        begin
            work = hash_u16(hash_in, left_value);
            hash_stereo = hash_u16(work, right_value);
        end
    endfunction

    function automatic logic [7:0] rom_primary(input logic [23:0] address);
        logic [18:0] mixed;
        begin
            mixed = address[7:0] * 19'd73 +
                    address[15:8] * 19'd29 + 19'd41;
            rom_primary = mixed[7:0];
        end
    endfunction

    function automatic logic [7:0] rom_changed(input logic [23:0] address);
        logic [18:0] mixed;
        begin
            mixed = address[7:0] * 19'd151 +
                    address[15:8] * 19'd67 + 19'd109;
            rom_changed = mixed[7:0];
        end
    endfunction

    function automatic logic [16:0] delta_sum(
        input logic [15:0] count,
        input logic [15:0] delta_n
    );
        delta_sum = {1'b0, count} + {1'b0, delta_n};
    endfunction

    function automatic logic [7:0] decoder_step_factor(
        input logic [3:0] nibble
    );
        casez (nibble[3:1])
            3'b0_??: decoder_step_factor = 8'd57;
            3'b1_00: decoder_step_factor = 8'd77;
            3'b1_01: decoder_step_factor = 8'd102;
            3'b1_10: decoder_step_factor = 8'd128;
            default: decoder_step_factor = 8'd153;
        endcase
    endfunction

    function automatic logic signed [15:0] decoder_next_sample(
        input logic signed [15:0] old_sample,
        input logic signed [15:0] candidate,
        input logic candidate_sign
    );
        begin
            if (candidate_sign == old_sample[15] &&
                old_sample[15] != candidate[15])
                decoder_next_sample = old_sample[15] ?
                    -16'sd32768 : 16'sd32767;
            else
                decoder_next_sample = candidate;
        end
    endfunction

    function automatic logic [14:0] decoder_next_step(
        input logic [16:0] candidate
    );
        begin
            if (candidate < 17'd127)
                decoder_next_step = 15'd127;
            else if (candidate > 17'd24576)
                decoder_next_step = 15'd24576;
            else
                decoder_next_step = candidate[14:0];
        end
    endfunction

    function automatic logic signed [15:0] interpolation_next(
        input logic signed [15:0] current,
        input logic signed [15:0] last,
        input logic [15:0] step,
        input logic step_sign,
        input logic advance
    );
        begin
            if (advance)
                interpolation_next = last;
            else if ((current < last) == step_sign)
                interpolation_next = current;
            else if (step_sign)
                interpolation_next = current - $signed(step);
            else
                interpolation_next = current + $signed(step);
        end
    endfunction

    function automatic logic signed [15:0] gain_next(
        input logic signed [15:0] pcm,
        input logic [7:0] level
    );
        logic signed [15:0] signed_level;
        logic signed [31:0] product;
        begin
            signed_level = $signed({8'd0, level});
            product = pcm * signed_level;
            gain_next = product[23:8];
        end
    endfunction

    function automatic logic signed [15:0] lane_next(
        input logic active,
        input logic pan_enable,
        input logic signed [15:0] gain
    );
        lane_next = active && pan_enable ? gain : 16'sd0;
    endfunction

    function automatic logic signed [15:0] accumulator_b_input(
        input logic signed [15:0] lane
    );
        accumulator_b_input = lane >>> 1;
    endfunction

    function automatic logic signed [15:0] accumulator_next(
        input logic signed [15:0] accumulator,
        input logic signed [15:0] current,
        input logic zero
    );
        logic signed [15:0] sum;
        logic overflow;
        begin
            sum = zero ? current : current + accumulator;
            overflow = !zero && current[15] == accumulator[15] &&
                       accumulator[15] != sum[15];
            if (overflow)
                accumulator_next = accumulator[15] ?
                    -16'sd32768 : 16'sd32767;
            else
                accumulator_next = sum;
        end
    endfunction
endpackage
