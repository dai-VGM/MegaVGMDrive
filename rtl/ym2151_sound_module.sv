// Minimal JT51/YM2151 sound wrapper for experimental MegaVGMDrive mode.
//
// JT51 is GPL-3.0-or-later and is included as third_party/jt51. This wrapper
// keeps the project-side interface small: one VGM 0x54 register/data command
// is translated into the YM2151 address write followed by data write.

module ym2151_sound_module #(
    parameter logic [31:0] CLK_SYS_HZ = 32'd20_000_000,
    parameter logic [31:0] YM2151_CLK_HZ = 32'd4_000_000,
    // Test-only compatibility switch for measuring the former 2x-pitch path.
    parameter logic LEGACY_FULL_RATE_CEN_P1 = 1'b0
) (
    input  logic              clk,
    input  logic              reset,

    input  logic              ym2151_cmd_valid,
    input  logic [7:0]        ym2151_cmd_reg,
    input  logic [7:0]        ym2151_cmd_data,
    output logic              ym2151_cmd_ready,

    output logic signed [15:0] audio_l,
    output logic signed [15:0] audio_r,
    output logic              audio_sample_valid
);

    typedef enum logic [1:0] {
        WR_IDLE,
        WR_ADDR_WAIT,
        WR_DATA_WAIT,
        WR_BUSY_WAIT
    } write_state_t;

    write_state_t write_state = WR_IDLE;

    logic [31:0] cen_accum = 32'd0;
    logic jt51_cen = 1'b0;
    logic jt51_cen_p1 = 1'b0;
    logic jt51_cen_phase = 1'b0;
    logic [7:0] latched_reg = 8'd0;
    logic [7:0] latched_data = 8'd0;
    logic jt51_cs_n;
    logic jt51_wr_n;
    logic jt51_a0;
    logic [7:0] jt51_din;
    wire [7:0] jt51_dout;
    wire jt51_ct1;
    wire jt51_ct2;
    wire jt51_irq_n;
    wire jt51_sample;
    wire signed [15:0] jt51_left;
    wire signed [15:0] jt51_right;
    wire signed [15:0] jt51_xleft;
    wire signed [15:0] jt51_xright;
    wire jt51_busy = jt51_dout[7];
    wire jt51_addr_write =
        (write_state == WR_ADDR_WAIT) && jt51_cen_p1;
    wire jt51_data_write =
        (write_state == WR_DATA_WAIT) && jt51_cen_p1 && !jt51_busy;

    assign ym2151_cmd_ready = (write_state == WR_IDLE) && !jt51_busy;
    assign audio_l = jt51_xleft;
    assign audio_r = jt51_xright;
    assign audio_sample_valid = jt51_sample;

    always_ff @(posedge clk) begin
        if (reset) begin
            cen_accum <= 32'd0;
            jt51_cen <= 1'b0;
            jt51_cen_p1 <= 1'b0;
            jt51_cen_phase <= 1'b0;
        end else if (cen_accum >= (CLK_SYS_HZ - YM2151_CLK_HZ)) begin
            cen_accum <= cen_accum + YM2151_CLK_HZ - CLK_SYS_HZ;
            jt51_cen <= 1'b1;
            jt51_cen_phase <= ~jt51_cen_phase;
            jt51_cen_p1 <= LEGACY_FULL_RATE_CEN_P1 || jt51_cen_phase;
        end else begin
            cen_accum <= cen_accum + YM2151_CLK_HZ;
            jt51_cen <= 1'b0;
            jt51_cen_p1 <= 1'b0;
        end
    end

    always_comb begin
        jt51_cs_n = 1'b1;
        jt51_wr_n = 1'b1;
        jt51_a0 = 1'b0;
        jt51_din = latched_reg;

        if (jt51_addr_write) begin
            jt51_cs_n = 1'b0;
            jt51_wr_n = 1'b0;
            jt51_a0 = 1'b0;
            jt51_din = latched_reg;
        end else if (jt51_data_write) begin
            jt51_cs_n = 1'b0;
            jt51_wr_n = 1'b0;
            jt51_a0 = 1'b1;
            jt51_din = latched_data;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            write_state <= WR_IDLE;
            latched_reg <= 8'd0;
            latched_data <= 8'd0;
        end else begin
            unique case (write_state)
                WR_IDLE: begin
                    if (ym2151_cmd_valid && !jt51_busy) begin
                        latched_reg <= ym2151_cmd_reg;
                        latched_data <= ym2151_cmd_data;
                        write_state <= WR_ADDR_WAIT;
                    end
                end
                WR_ADDR_WAIT: begin
                    if (jt51_cen_p1) begin
                        write_state <= WR_DATA_WAIT;
                    end
                end
                WR_DATA_WAIT: begin
                    if (jt51_cen_p1 && !jt51_busy) begin
                        write_state <= WR_BUSY_WAIT;
                    end
                end
                WR_BUSY_WAIT: begin
                    if (!jt51_busy) begin
                        write_state <= WR_IDLE;
                    end
                end
                default: begin
                    write_state <= WR_IDLE;
                end
            endcase
        end
    end

    /*
     * JT51 samples write on clk and updates its busy flag only on cen_p1. The
     * write strobes above are therefore one clk_sys cycle wide and aligned
     * with jt51_cen_p1, avoiding repeated register writes while waiting for
     * the 2 MHz P1 enable used by the synthesis pipeline.
     */
    jt51 jt51_core (
        .rst    (reset),
        .clk    (clk),
        .cen    (jt51_cen),
        .cen_p1 (jt51_cen_p1),
        .cs_n   (jt51_cs_n),
        .wr_n   (jt51_wr_n),
        .a0     (jt51_a0),
        .din    (jt51_din),
        .dout   (jt51_dout),
        .ct1    (jt51_ct1),
        .ct2    (jt51_ct2),
        .irq_n  (jt51_irq_n),
        .sample (jt51_sample),
        .left   (jt51_left),
        .right  (jt51_right),
        .xleft  (jt51_xleft),
        .xright (jt51_xright)
    );

endmodule
