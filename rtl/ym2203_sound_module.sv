// Production YM2203 transport for the loaded-VGM path.
//
// The VGM clock is the chip input clock. jt12_top performs the YM2203 FM /6
// and SSG /4 division internally, so the generated enable is not pre-divided.

module ym2203_sound_module #(
    parameter logic [31:0] CLK_SYS_HZ = 32'd20_000_000,
    parameter integer BUSY_TIMEOUT_CYCLES = 1_000_000
) (
    input  logic               clk,
    input  logic               reset,

    input  logic [31:0]        ym2203_clock,
    input  logic               ym2203_clock_load,
    output logic [31:0]        clock_raw_debug,
    output logic [31:0]        effective_clock_hz_debug,
    output logic               clock_present_debug,
    output logic               chip_cen_debug,

    input  logic               write_valid,
    input  logic [7:0]         write_reg,
    input  logic [7:0]         write_data,
    output logic               write_ready,
    output logic               write_accepted,
    output logic               write_completed,
    output logic [31:0]        write_accepted_count,
    output logic [31:0]        write_completed_count,
    output logic               transport_busy,
    output logic               core_busy,

    output logic signed [15:0] raw_audio_l,
    output logic signed [15:0] raw_audio_r,
    output logic signed [15:0] raw_fm_audio,
    output logic        [9:0]  raw_psg_audio,
    output logic               raw_sample_valid
);
    typedef enum logic [2:0] {
        WR_IDLE,
        WR_ADDR,
        WR_ADDR_IDLE,
        WR_DATA,
        WR_DATA_IDLE,
        WR_WAIT_BUSY_ASSERT,
        WR_WAIT_BUSY_CLEAR
    } write_state_t;

    write_state_t write_state;
    logic [7:0] latched_reg;
    logic [7:0] latched_data;

    logic [7:0] jt12_din;
    logic [1:0] jt12_addr;
    logic jt12_cs_n;
    logic jt12_wr_n;
    wire [7:0] jt12_dout;
    wire jt12_irq_n;
    wire chip_cen;
    wire clock_present;
    wire [31:0] clock_raw_latched;
    wire [31:0] effective_clock_hz;

    wire [19:0] adpcma_addr_unused;
    wire [3:0] adpcma_bank_unused;
    wire adpcma_roe_n_unused;
    wire [23:0] adpcmb_addr_unused;
    wire adpcmb_roe_n_unused;
    wire [7:0] psg_a_unused;
    wire [7:0] psg_b_unused;
    wire [7:0] psg_c_unused;
    wire signed [15:0] fm_left;
    wire signed [15:0] fm_right;
    wire signed [15:0] adpcma_l_unused;
    wire signed [15:0] adpcma_r_unused;
    wire signed [15:0] adpcmb_l_unused;
    wire signed [15:0] adpcmb_r_unused;
    wire [9:0] psg_sound;
    wire signed [15:0] sound_left;
    wire signed [15:0] sound_right;
    wire sound_sample;
    wire [7:0] debug_view_unused;

    assign clock_raw_debug = clock_raw_latched;
    assign effective_clock_hz_debug = effective_clock_hz;
    assign clock_present_debug = clock_present;
    assign chip_cen_debug = chip_cen;
    assign write_ready = (write_state == WR_IDLE);
    assign transport_busy = (write_state != WR_IDLE);
    assign core_busy = jt12_dout[7];
    assign raw_audio_l = sound_left;
    assign raw_audio_r = sound_right;
    assign raw_fm_audio = fm_left;
    assign raw_psg_audio = psg_sound;
    assign raw_sample_valid = sound_sample;

    ym2203_dynamic_cen #(
        .CLK_SYS_HZ (CLK_SYS_HZ)
    ) clock_enable (
        .clk                 (clk),
        .reset               (reset),
        .clock_raw           (ym2203_clock),
        .clock_load          (ym2203_clock_load),
        .clock_raw_latched   (clock_raw_latched),
        .effective_clock_hz  (effective_clock_hz),
        .clock_present       (clock_present),
        .cen                 (chip_cen)
    );

    always_comb begin
        jt12_din = 8'd0;
        jt12_addr = 2'b00;
        jt12_cs_n = 1'b1;
        jt12_wr_n = 1'b1;

        case (write_state)
            WR_ADDR: begin
                jt12_din = latched_reg;
                jt12_addr = 2'b00;
                jt12_cs_n = 1'b0;
                jt12_wr_n = 1'b0;
            end
            WR_DATA: begin
                jt12_din = latched_data;
                jt12_addr = 2'b01;
                jt12_cs_n = 1'b0;
                jt12_wr_n = 1'b0;
            end
            WR_WAIT_BUSY_ASSERT,
            WR_WAIT_BUSY_CLEAR: begin
                // YM2203 status read: A1:A0=0, CS active, WR inactive.
                jt12_addr = 2'b00;
                jt12_cs_n = 1'b0;
                jt12_wr_n = 1'b1;
            end
            default: begin
                // Full bus-idle cycle between the address and data phases.
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            write_state <= WR_IDLE;
            latched_reg <= 8'd0;
            latched_data <= 8'd0;
            write_accepted <= 1'b0;
            write_completed <= 1'b0;
            write_accepted_count <= 32'd0;
            write_completed_count <= 32'd0;
        end else begin
            write_accepted <= 1'b0;
            write_completed <= 1'b0;
            unique case (write_state)
                WR_IDLE: begin
                    if (write_valid) begin
                        latched_reg <= write_reg;
                        latched_data <= write_data;
                        write_accepted <= 1'b1;
                        if (write_accepted_count != 32'hffff_ffff) begin
                            write_accepted_count <= write_accepted_count + 32'd1;
                        end
                        if (clock_present) begin
                            write_state <= WR_ADDR;
                        end else begin
                            // A VGM may contain writes for an absent chip. They
                            // are consumed once so the parser cannot deadlock.
                            write_completed <= 1'b1;
                            if (write_completed_count != 32'hffff_ffff) begin
                                write_completed_count <= write_completed_count + 32'd1;
                            end
                        end
                    end
                end
                WR_ADDR: write_state <= WR_ADDR_IDLE;
                WR_ADDR_IDLE: write_state <= WR_DATA;
                WR_DATA: write_state <= WR_DATA_IDLE;
                WR_DATA_IDLE: write_state <= WR_WAIT_BUSY_ASSERT;
                WR_WAIT_BUSY_ASSERT: begin
                    if (core_busy) begin
                        write_state <= WR_WAIT_BUSY_CLEAR;
                    end
                end
                WR_WAIT_BUSY_CLEAR: begin
                    if (!core_busy) begin
                        write_completed <= 1'b1;
                        if (write_completed_count != 32'hffff_ffff) begin
                            write_completed_count <= write_completed_count + 32'd1;
                        end
                        write_state <= WR_IDLE;
                    end
                end
                default: write_state <= WR_IDLE;
            endcase
        end
    end

`ifdef SIMULATION
    integer busy_timeout_count;
    always_ff @(posedge clk) begin
        if (reset || (write_state != WR_WAIT_BUSY_ASSERT &&
                      write_state != WR_WAIT_BUSY_CLEAR)) begin
            busy_timeout_count <= 0;
        end else if (busy_timeout_count >= BUSY_TIMEOUT_CYCLES) begin
            $fatal(1, "YM2203 busy handshake timeout state=%0d", write_state);
        end else begin
            busy_timeout_count <= busy_timeout_count + 1;
        end
    end
`endif

    jt12_top #(
        .use_lfo   (0),
        .use_ssg   (1),
        .num_ch    (3),
        .use_pcm   (0),
        .use_adpcm (0),
        .JT49_DIV  (2),
        .mask_div  (0)
    ) ym2203_core (
        .rst            (reset),
        .clk            (clk),
        .cen            (chip_cen),
        .din            (jt12_din),
        .addr           (jt12_addr),
        .cs_n           (jt12_cs_n),
        .wr_n           (jt12_wr_n),
        .ladder         (1'b0),
        .dout           (jt12_dout),
        .irq_n          (jt12_irq_n),
        .en_hifi_pcm    (1'b0),
        .adpcma_addr    (adpcma_addr_unused),
        .adpcma_bank    (adpcma_bank_unused),
        .adpcma_roe_n   (adpcma_roe_n_unused),
        .adpcma_data    (8'd0),
        .adpcmb_addr    (adpcmb_addr_unused),
        .adpcmb_data    (8'd0),
        .adpcmb_roe_n   (adpcmb_roe_n_unused),
        .IOA_in         (8'd0),
        .IOB_in         (8'd0),
        .psg_A          (psg_a_unused),
        .psg_B          (psg_b_unused),
        .psg_C          (psg_c_unused),
        .fm_snd_left    (fm_left),
        .fm_snd_right   (fm_right),
        .adpcmA_l       (adpcma_l_unused),
        .adpcmA_r       (adpcma_r_unused),
        .adpcmB_l       (adpcmb_l_unused),
        .adpcmB_r       (adpcmb_r_unused),
        .psg_snd        (psg_sound),
        .snd_right      (sound_right),
        .snd_left       (sound_left),
        .snd_sample     (sound_sample),
        .debug_bus      (8'd0),
        .debug_view     (debug_view_unused)
    );
endmodule
