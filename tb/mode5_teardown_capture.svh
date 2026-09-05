// Passive, cycle-correlated common output observer. Full valid stream is
// retained so the last 64 samples can be selected without guessing EOF time.
longint teardown_cycle = 0;
integer teardown_ordinal = 0;
integer teardown_prev_l = 0, teardown_prev_r = 0;
logic [8:0] teardown_previous_flags = '0;
logic teardown_zero_owned = 0;
integer teardown_zero_cycles = 0, teardown_zero_violations = 0;
wire [8:0] teardown_flags = {
    dut.loaded_vgm_mode.mode5_load_begin_pulse,
    dut.loaded_vgm_mode.mode5_done_edge,
    dut.loaded_vgm_mode.mode5_parser_done_edge,
    dut.loaded_vgm_mode.mode5_transition_fade_active,
    dut.audio_runtime_open, player_busy, player_done,
    dut.loaded_vgm_mode.mode5_sound_core_reset,
    dut.loaded_vgm_mode.mode5_transition_released
};
always @(posedge clk) begin
    teardown_cycle = teardown_cycle + 1;
    #2;
    if (teardown_flags != teardown_previous_flags) begin
        $display("TEARDOWN_EVENT cycle=%0d session=%0d n=%0d load=%0b ended=%0b eof=%0b fade=%0b open=%0b busy=%0b done=%0b reset=%0b released=%0b gain=%0d raw_l=%0d raw_r=%0d out_l=%0d out_r=%0d waits=%0d",
            teardown_cycle, mode5_playback_session_id, teardown_ordinal,
            teardown_flags[8], teardown_flags[7], teardown_flags[6],
            teardown_flags[5], teardown_flags[4], teardown_flags[3],
            teardown_flags[2], teardown_flags[1], teardown_flags[0],
            dut.audio_runtime_gain, dut.raw_audio_l, dut.raw_audio_r,
            audio_l, audio_r, vgm_wait_ticks_consumed_debug);
    end
    teardown_previous_flags = teardown_flags;
    if (mode5_playback_session_id == 1 && dut.audio_runtime_gain == 0)
        teardown_zero_owned = 1;
    if (mode5_playback_session_id == 1 && teardown_zero_owned) begin
        teardown_zero_cycles = teardown_zero_cycles + 1;
        if (audio_l !== 16'sd0 || audio_r !== 16'sd0) begin
            if (teardown_zero_violations == 0)
                $display("TEARDOWN_ZERO_VIOLATION cycle=%0d l=%0d r=%0d load=%0b",
                    teardown_cycle, audio_l, audio_r, teardown_flags[8]);
            teardown_zero_violations = teardown_zero_violations + 1;
        end
    end
    if (mode5_playback_session_id == 1 && dut.raw_audio_sample_valid) begin
        $display("TEARDOWN_SAMPLE cycle=%0d session=%0d n=%0d raw_l=%0d raw_r=%0d gain=%0d post_l=%0d post_r=%0d open=%0b out_l=%0d out_r=%0d delta_l=%0d delta_r=%0d busy=%0b done=%0b fade=%0b ended=%0b load=%0b ym2203_l=%0d ym2203_r=%0d",
            teardown_cycle, mode5_playback_session_id, teardown_ordinal,
            dut.raw_audio_l, dut.raw_audio_r, dut.audio_runtime_gain,
            dut.scale_audio_256(dut.raw_audio_l, dut.audio_runtime_gain),
            dut.scale_audio_256(dut.raw_audio_r, dut.audio_runtime_gain),
            dut.audio_runtime_open, audio_l, audio_r,
            $signed(audio_l)-teardown_prev_l, $signed(audio_r)-teardown_prev_r,
            player_busy, player_done,
            dut.loaded_vgm_mode.mode5_transition_fade_active,
            dut.loaded_vgm_mode.mode5_done_edge,
            dut.loaded_vgm_mode.mode5_load_begin_pulse,
            dut.loaded_vgm_mode.ym2203_audio_l_held,
            dut.loaded_vgm_mode.ym2203_audio_r_held);
        teardown_prev_l = $signed(audio_l);
        teardown_prev_r = $signed(audio_r);
        teardown_ordinal = teardown_ordinal + 1;
    end
end
