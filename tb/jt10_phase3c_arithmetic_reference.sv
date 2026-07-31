`timescale 1ns/1ps

// Test-only arithmetic references for the pinned standard JT10 path.
//
// These modules intentionally expose the fixed-width operations as small,
// independent state machines.  They are compiled only by the Phase 3C
// manifest and are never part of a production build.

module jt10_phase3c_adpcma_acc_reference (
    input                         rst_n,
    input                         clk,
    input                         cen,
    input                  [5:0]  cur_ch,
    input                  [5:0]  en_ch,
    input                         match,
    input                         en_sum,
    input signed          [15:0]  pcm_in,
    output logic signed   [15:0]  pcm_out,
    output logic signed   [17:0]  acc_state,
    output logic signed   [17:0]  last_state,
    output logic signed   [17:0]  step_state,
    output logic signed   [17:0]  full_state,
    output logic                  full_overflow
);
    logic signed [17:0] pcm_in_long;
    logic signed [17:0] diff;
    logic signed [22:0] diff_ext;
    logic signed [22:0] step_full;
    logic               adv;

    always @(*) begin
        pcm_in_long = en_sum ? {{2{pcm_in[15]}}, pcm_in} : 18'sd0;
        diff = acc_state - last_state;
        diff_ext = {{5{diff[17]}}, diff};
        step_full = diff_ext + (diff_ext <<< 1) +
                    (diff_ext <<< 3) + (diff_ext <<< 5);
        adv = en_ch[0] & cur_ch[0];
        full_overflow = (|full_state[17:15]) &
                        (~&full_state[17:15]);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_state  <= 18'sd0;
            last_state <= 18'sd0;
            step_state <= 18'sd0;
        end else if (cen) begin
            if (match)
                acc_state <= cur_ch[0] ?
                    pcm_in_long : pcm_in_long + acc_state;
            if (adv) begin
                step_state <= {{2{step_full[22]}}, step_full[22:7]};
                last_state <= acc_state;
            end
        end
    end

    // pcm_out deliberately has no reset assignment.  That mirrors the pinned
    // source contract; comparison begins only after the warm-up has made it
    // known.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            full_state <= 18'sd0;
        end else if (cen && cur_ch[0]) begin
            case (en_ch)
                6'b000001: full_state <= last_state;
                6'b000100,
                6'b010000: full_state <= full_state + step_state;
                default: ;
            endcase
            if (full_overflow)
                pcm_out <= full_state[17] ? 16'sh8000 : 16'sh7fff;
            else
                pcm_out <= full_state[15:0];
        end
    end
endmodule

module jt10_phase3c_final_acc_reference (
    input                         rst,
    input                         clk,
    input                         clk_en,
    input signed          [13:0]  op_result,
    input                  [1:0]  rl,
    input                         zero,
    input                         s1_enters,
    input                         s2_enters,
    input                         s3_enters,
    input                         s4_enters,
    input                  [2:0]  cur_ch,
    input                  [1:0]  cur_op,
    input                  [2:0]  alg,
    input signed          [15:0]  adpcma_l,
    input signed          [15:0]  adpcma_r,
    input signed          [15:0]  adpcmb_l,
    input signed          [15:0]  adpcmb_r,
    output logic signed   [15:0]  expected_input_l,
    output logic signed   [15:0]  expected_input_r,
    output logic                  expected_enable_l,
    output logic                  expected_enable_r,
    output logic signed   [15:0]  expected_left,
    output logic signed   [15:0]  expected_right,
    output logic                  overflow_l,
    output logic                  overflow_r,
    output logic                  adpcma_wrap_l,
    output logic                  adpcma_wrap_r
);
    logic                         sum_en;
    logic signed          [15:0]  op_ext;
    logic signed          [15:0]  adpcma_l_shift2;
    logic signed          [15:0]  adpcma_l_shift1;
    logic signed          [15:0]  adpcma_r_shift2;
    logic signed          [15:0]  adpcma_r_shift1;
    logic signed          [18:0]  adpcma_math_l;
    logic signed          [18:0]  adpcma_math_r;
    logic signed          [15:0]  current_l;
    logic signed          [15:0]  current_r;
    logic signed          [15:0]  next_l;
    logic signed          [15:0]  next_r;
    logic signed          [15:0]  acc_l;
    logic signed          [15:0]  acc_r;

    always @(*) begin
        case (alg)
            3'd4: sum_en = s2_enters | s4_enters;
            3'd5,
            3'd6: sum_en = ~s1_enters;
            3'd7: sum_en = 1'b1;
            default: sum_en = s4_enters;
        endcase

        op_ext = {{2{op_result[13]}}, op_result};
        adpcma_l_shift2 = adpcma_l <<< 2;
        adpcma_l_shift1 = adpcma_l <<< 1;
        adpcma_r_shift2 = adpcma_r <<< 2;
        adpcma_r_shift1 = adpcma_r <<< 1;
        adpcma_math_l = $signed(adpcma_l) * 19'sd6;
        adpcma_math_r = $signed(adpcma_r) * 19'sd6;
        adpcma_wrap_l = adpcma_math_l > 19'sd32767 ||
                        adpcma_math_l < -19'sd32768;
        adpcma_wrap_r = adpcma_math_r > 19'sd32767 ||
                        adpcma_math_r < -19'sd32768;

        case ({cur_op, cur_ch})
            {2'd0, 3'd0}: begin
                expected_input_l = adpcma_l_shift2 + adpcma_l_shift1;
                expected_input_r = adpcma_r_shift2 + adpcma_r_shift1;
                expected_enable_l = 1'b1;
                expected_enable_r = 1'b1;
            end
            {2'd0, 3'd4}: begin
                expected_input_l = adpcmb_l >>> 1;
                expected_input_r = adpcmb_r >>> 1;
                expected_enable_l = 1'b1;
                expected_enable_r = 1'b1;
            end
            default: begin
                expected_input_l = op_ext >>> 1;
                expected_input_r = op_ext >>> 1;
                expected_enable_l = sum_en & rl[1];
                expected_enable_r = sum_en & rl[0];
            end
        endcase

        current_l = expected_enable_l ? expected_input_l : 16'sd0;
        current_r = expected_enable_r ? expected_input_r : 16'sd0;
        next_l = zero ? current_l : current_l + acc_l;
        next_r = zero ? current_r : current_r + acc_r;
        overflow_l = !zero && current_l[15] == acc_l[15] &&
                     acc_l[15] != next_l[15];
        overflow_r = !zero && current_r[15] == acc_r[15] &&
                     acc_r[15] != next_r[15];
    end

    always @(posedge clk) begin
        if (rst) begin
            acc_l <= 16'sd0;
            acc_r <= 16'sd0;
            expected_left <= 16'sd0;
            expected_right <= 16'sd0;
        end else if (clk_en) begin
            if (overflow_l)
                acc_l <= acc_l[15] ? 16'sh8000 : 16'sh7fff;
            else
                acc_l <= next_l;
            if (overflow_r)
                acc_r <= acc_r[15] ? 16'sh8000 : 16'sh7fff;
            else
                acc_r <= next_r;
            if (zero) begin
                expected_left <= acc_l;
                expected_right <= acc_r;
            end
        end
    end
endmodule
