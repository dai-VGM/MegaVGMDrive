// Exact failing D1 contract shape from 880bff0: the exporter exists, but its
// ready/reset release depends on upload completion and every session signal is
// tied to zero. Supervisor waits for IDLE before it permits that upload.
assign mode5_load_ready = profile_load_done && !profile_fatal;
assign mode5_playback_session_id = '0;
assign mode5_done_session_id = '0;
assign vgm_error_session_id = '0;
assign vgm_loop_valid_debug = '0;
assign vgm_loop_boundary_pulse_debug = '0;
