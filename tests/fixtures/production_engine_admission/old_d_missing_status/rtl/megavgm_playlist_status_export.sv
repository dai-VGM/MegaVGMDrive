module megavgm_playlist_status_export;
    localparam INTERFACE_MAGIC = 8'h4d;
    localparam INTERFACE_V2_VERSION = 4'd2;
    localparam STATE_IDLE = 0;
    localparam STATE_LOADING = 1;
    localparam STATE_PLAYING = 2;
    localparam STATE_ENDED = 3;
    localparam STATE_FATAL = 4;
    wire current_done = done_session_id == playback_session_id;
    wire current_error = error_session_id == playback_session_id;
    wire player_loop_valid;
    wire player_loop_boundary_pulse;
    always_ff @(posedge clk) begin
        if (reset) begin
            exported_session_id <= 32'd0;
            exported_state <= STATE_IDLE;
        end else if (new_session) exported_state <= STATE_LOADING;
        else if (player_busy) exported_state <= STATE_PLAYING;
        else if (current_done) exported_state <= STATE_ENDED;
        else if (current_error) exported_state <= STATE_FATAL;
    end
endmodule
