// Qualify a non-reset audio lane against the currently loaded VGM session.
//
// Some sound cores intentionally keep running across mode-5 file loads so
// timestamp-zero setup writes are not lost. Their held output therefore still
// belongs to the previous session until the new command stream has completed
// its initial setup and that same core produces a fresh sample.
module mode5_audio_session_lane_gate (
    input  logic               clk,
    input  logic               reset,
    input  logic               session_begin,
    input  logic               command_valid,
    input  logic               setup_complete,
    input  logic               sample_valid,
    input  logic signed [15:0] raw_audio_l,
    input  logic signed [15:0] raw_audio_r,
    output logic               session_ready,
    output logic signed [15:0] session_audio_l,
    output logic signed [15:0] session_audio_r
);

    logic command_seen = 1'b0;

    always_ff @(posedge clk) begin
        if (reset || session_begin) begin
            command_seen <= 1'b0;
            session_ready <= 1'b0;
        end else begin
            if (command_valid)
                command_seen <= 1'b1;
            if (!session_ready &&
                (command_seen || command_valid) &&
                setup_complete && sample_valid)
                session_ready <= 1'b1;
        end
    end

    always_comb begin
        session_audio_l = session_ready ? raw_audio_l : 16'sd0;
        session_audio_r = session_ready ? raw_audio_r : 16'sd0;
    end

endmodule
