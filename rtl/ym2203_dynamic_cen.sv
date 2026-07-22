// Dynamic fractional chip-clock enable for the production YM2203 path.
// The maximum is clk_sys/2 so every one-cycle enable has a low cycle after it.
module ym2203_dynamic_cen #(
    parameter logic [31:0] CLK_SYS_HZ = 32'd20_000_000
) (
    input  logic        clk,
    input  logic        reset,
    input  logic [31:0] clock_raw,
    input  logic        clock_load,
    output logic [31:0] clock_raw_latched,
    output logic [31:0] effective_clock_hz,
    output logic        clock_present,
    output logic        cen
);
    localparam logic [31:0] MAX_NONCONSECUTIVE_HZ = CLK_SYS_HZ >> 1;

    logic [31:0] phase_accum;
    logic [32:0] phase_sum;
    logic [29:0] sanitized_clock;

    always @* begin
        sanitized_clock = clock_raw_latched[29:0];
        clock_present = (sanitized_clock != 30'd0);
        if (!clock_present) begin
            effective_clock_hz = 32'd0;
        end else if ({2'b00, sanitized_clock} > MAX_NONCONSECUTIVE_HZ) begin
            // A one-cycle pulse with a mandatory low cycle cannot represent a
            // target above clk_sys/2. Clamp malformed headers safely.
            effective_clock_hz = MAX_NONCONSECUTIVE_HZ;
        end else begin
            effective_clock_hz = {2'b00, sanitized_clock};
        end
        phase_sum = {1'b0, phase_accum} + {1'b0, effective_clock_hz};
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            clock_raw_latched <= 32'd0;
            phase_accum <= 32'd0;
            cen <= 1'b0;
        end else if (clock_load) begin
            clock_raw_latched <= clock_raw;
            phase_accum <= 32'd0;
            cen <= 1'b0;
        end else if (!clock_present) begin
            phase_accum <= 32'd0;
            cen <= 1'b0;
        end else if (phase_sum >= {1'b0, CLK_SYS_HZ}) begin
            phase_accum <= phase_sum[31:0] - CLK_SYS_HZ;
            cen <= 1'b1;
        end else begin
            phase_accum <= phase_sum[31:0];
            cen <= 1'b0;
        end
    end

`ifdef SIMULATION
    logic cen_previous;
    always_ff @(posedge clk) begin
        if (reset || clock_load) begin
            cen_previous <= 1'b0;
        end else begin
            if (cen && cen_previous) begin
                $fatal(1, "YM2203 CEN asserted on consecutive system clocks");
            end
            cen_previous <= cen;
        end
    end
`endif
endmodule
