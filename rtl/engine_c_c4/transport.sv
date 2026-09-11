// Golden profile adapter to PlaylistLoopLab's transport/status ABI.
// The publisher is the unmodified reference at 294d63e, not a second status FSM.
module golden_shell_transport (
    input logic clk, reset,
    input logic download, write_byte,
    input logic [15:0] index,
    input logic [26:0] address,
    input logic [7:0] data,
    input logic upload_busy, upload_done, upload_error, upload_overflow,
    input logic profile_started, profile_busy, profile_done, profile_fatal,
    input logic [7:0] profile_error,
    input logic profile_loop_valid,
    input logic [31:0] profile_loop_count,
    input logic [127:0] hps_status,
    output wire [127:0] status_in,
    output wire status_set,
    output wire playback_busy, player_error,
    output wire vgm_download,
    output wire policy_download,
    output wire load_begin, load_accepted, session_start,
    output logic load_complete, playback_start,
    output logic [31:0] session_id,
    output wire [2:0] state,
    output logic done,
    output logic [31:0] done_session_id,
    output wire [31:0] error_session_id,
    output wire [7:0] error_code,
    output wire loop_valid,
    output wire [15:0] loop_count
);
    logic download_d, pending, upload_finished, playback_owned;
    logic [31:0] profile_loop_count_d;
    assign vgm_download = !reset && download && index == 16'd1;
    assign policy_download = !reset && download && index == 16'd2;
    // Same pre-edge admission event as PlaylistLoopLab load_begin_pulse.
    // Validation failure belongs to this NEW generation and publishes FATAL.
    assign load_begin = vgm_download && !download_d;
    assign load_accepted = load_begin;
    assign session_start = load_begin;
    assign error_session_id = session_id;
    wire owned_busy = upload_finished && profile_busy && !vgm_download;
    // Scanner state can still describe the old file until the upload drains.
    wire owned_fatal = upload_finished && !vgm_download && profile_fatal;
    assign playback_busy = owned_busy;
    assign player_error = owned_fatal;
    wire owned_loop_valid = upload_finished && !vgm_download && profile_loop_valid;
    // Adapt the real parser boundary counter to the reference pulse interface.
    // This is not inferred from header samples, wall time, or status polling.
    wire loop_boundary = owned_busy && profile_loop_valid &&
                         (profile_loop_count != profile_loop_count_d);
    always_ff @(posedge clk) begin
        if (reset) begin
            download_d <= 0; pending <= 0; upload_finished <= 0;
            playback_owned <= 0; profile_loop_count_d <= 0;
            load_complete <= 0; playback_start <= 0;
            session_id <= 0; done <= 0; done_session_id <= 0;
        end else begin
            download_d <= vgm_download;
            profile_loop_count_d <= profile_loop_count;
            load_complete <= 0; playback_start <= 0;
            if (load_begin) begin
                session_id <= session_id + 1;
                pending <= 1; upload_finished <= 0; playback_owned <= 0;
                done <= 0; done_session_id <= 0;
            end else if (!vgm_download) begin
                if (pending && upload_done && !upload_finished &&
                    !upload_error && !upload_overflow) begin
                    upload_finished <= 1; load_complete <= 1;
                end
                if (pending && upload_finished &&
                    !upload_error && !upload_overflow && !profile_fatal && profile_started) begin
                    playback_start <= 1; playback_owned <= 1; pending <= 0;
                end
                if (playback_owned && profile_done && !done && !profile_fatal) begin
                    done <= 1; done_session_id <= session_id;
                end
            end
        end
    end
    megavgm_playlist_status_export publisher (
        .clk(clk), .reset(reset), .hps_status(hps_status),
        .playback_session_id(session_id), .vgm_load_busy(upload_busy),
        .player_busy(owned_busy), .player_done(done), .done_session_id(done_session_id),
        .vgm_load_error(upload_error && !vgm_download),
        .vgm_load_overflow(upload_overflow && !vgm_download),
        .vgm_player_error(owned_fatal), .vgm_player_error_code(profile_error),
        .error_session_id(error_session_id),
        .player_loop_valid(owned_loop_valid), .player_loop_boundary_pulse(loop_boundary),
        .status_in(status_in), .status_set(status_set),
        .exported_session_id(), .exported_state(state), .exported_error_code(error_code),
        .exported_loop_valid(loop_valid), .exported_loop_count(loop_count)
    );
endmodule
