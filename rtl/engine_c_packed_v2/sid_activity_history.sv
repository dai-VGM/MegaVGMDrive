// SPDX-License-Identifier: GPL-2.0-or-later
// Display-only SID write activity. No audio or transport signal depends on it.
module sid_activity_history (
    input  logic                            clk,
    input  logic                            reset,
    input  logic                            vblank_start,
    input  logic                            reg_write,
    input  logic [4:0]                      reg_addr,
    output logic [23:0]                     history
);
    logic [3:0] frame_activity;
    wire [3:0] write_activity = {
        reg_write && (reg_addr == 5'h18),
        reg_write && (reg_addr >= 5'h0e) && (reg_addr <= 5'h14),
        reg_write && (reg_addr >= 5'h07) && (reg_addr <= 5'h0d),
        reg_write && (reg_addr <= 5'h06)
    };

    always @(posedge clk) begin
        if (reset) begin
            frame_activity <= 4'b0000;
            history <= '0;
        end else if (vblank_start) begin
            history <= {
                history[22:18], frame_activity[3] | write_activity[3],
                history[16:12], frame_activity[2] | write_activity[2],
                history[10:6],  frame_activity[1] | write_activity[1],
                history[4:0],   frame_activity[0] | write_activity[0]
            };
            frame_activity <= 4'b0000;
        end else begin
            frame_activity <= frame_activity | write_activity;
        end
    end
endmodule
