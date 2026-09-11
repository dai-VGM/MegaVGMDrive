`timescale 1ns/1ps
module tb_owner;
    logic clk=0,reset=1,ioctl_download=0,ioctl_wr=0;
    logic [15:0] ioctl_index=1;
    logic [26:0] ioctl_addr=0;
    logic [7:0] ioctl_dout=0;
    logic playback_started=0,player_busy=0,loaded_player_done=0;
    logic [31:0] session_id=0,vgm_wait_ticks_consumed_debug=0;
    logic vgm_load_busy=0,vgm_load_error=0,vgm_load_overflow=0,vgm_player_error=0;
    logic audio_runtime_open=0,mode5_backend_ioctl_wait=0;
    logic mode5_player_loop_entry_pulse=0,mode5_player_loop_boundary_pulse=0;
    wire mode5_ioctl_download,mode5_ioctl_wr,ioctl_wait,mode5_load_begin_pulse,halt_loop;
    wire [8:0] gain;
    wire fade_active,released,end_pulse,loop_limit_active;
    integer loads=0,ends=0;
    always #5 clk=~clk;
    megavgm_transport_owner #(.MODE5_TRACK_FADE_CYCLES(256)) dut(.*);
    always @(posedge clk) if(!reset) begin
        if(mode5_load_begin_pulse) loads++;
        if(end_pulse) ends++;
        if((^{gain,ioctl_wait,fade_active,released,end_pulse})===1'bx) $fatal(1,"owner X");
    end
    task tick;@(posedge clk);#1;endtask
    task policy(input logic [7:0] enabled,input integer bytes=4,input bit malformed=0);
        ioctl_index=2;ioctl_download=1;tick();
        for(integer n=0;n<bytes;n++) begin
            ioctl_wr=1;ioctl_addr=n;
            case(n) 0:ioctl_dout=malformed?0:8'h4d;1:ioctl_dout=8'h56;2:ioctl_dout=2;3:ioctl_dout=enabled;default:ioctl_dout=0;endcase
            tick();
            if(mode5_ioctl_download || mode5_load_begin_pulse || ioctl_wait) $fatal(1,"policy blocked/loaded");
        end
        ioctl_wr=0;ioctl_download=0;repeat(4)tick();
    endtask
    task load_track;
        ioctl_index=1;ioctl_download=1;#1;
        for(integer t=0;t<1024 && ioctl_wait;t++)tick();
        if(ioctl_wait) $fatal(1,"load stuck");
        tick();playback_started=0;player_busy=0;audio_runtime_open=0;loaded_player_done=0;
        session_id++;vgm_wait_ticks_consumed_debug=0;
        repeat(3)tick();ioctl_download=0;repeat(5)tick();
        playback_started=1;player_busy=1;audio_runtime_open=1;repeat(5)tick();
        if(gain!=256 || released || fade_active) $fatal(1,"new session not rearmed loads=%0d gain=%d released=%b fade=%b",loads,gain,released,fade_active);
        if(dut.mode5_loop_first_boundary_seen || dut.mode5_loop_region_started) $fatal(1,"predictor stale");
    endtask
    task eof_track;
        integer old_ends;
        old_ends=ends;loaded_player_done=1;tick();
        if(!fade_active) $fatal(1,"natural EOF did not fade");
        for(integer t=0;t<300 && fade_active;t++) tick();
        repeat(3)tick();
        if(gain!=0 || ends!=old_ends+1) $fatal(1,"natural EOF completion ownership");
        player_busy=0;audio_runtime_open=0;
        policy(0);repeat(8)tick();
        if(gain || !released || ends!=old_ends+1) $fatal(1,"index2 resurrected old session");
    endtask
    task wait_sample;
        vgm_wait_ticks_consumed_debug++;
        // Give the reference fractional DDA idle cycles, as real 44.1k waits do.
        repeat(5)tick();
    endtask
    task loop_track(input integer length);
        integer start_count,old_ends;
        policy(1);load_track();old_ends=ends;
        // Intro is deliberately not part of L.
        vgm_wait_ticks_consumed_debug=100000;repeat(3)tick();
        mode5_player_loop_entry_pulse=1;tick();mode5_player_loop_entry_pulse=0;
        for(integer i=0;i<length;i++)wait_sample();
        mode5_player_loop_boundary_pulse=1;tick();mode5_player_loop_boundary_pulse=0;
        if(dut.mode5_loop_length_samples!=length || !halt_loop) $fatal(1,"first-loop measurement");
        for(integer i=0;i<length;i++) begin
            if(i < (length>88200?length-88200:0) && fade_active) $fatal(1,"predicted fade too early");
            wait_sample();
        end
        if(!fade_active || !loop_limit_active) $fatal(1,"predicted fade absent");
        mode5_player_loop_boundary_pulse=1;tick();mode5_player_loop_boundary_pulse=0;
        loaded_player_done=1;
        if(gain!=0 || fade_active || !end_pulse) $fatal(1,"boundary not exactly zero/END");
        repeat(4)tick();player_busy=0;audio_runtime_open=0;
        if(ends!=old_ends+1) $fatal(1,"double loop END");
        policy(1);if(gain!=0 || !released) $fatal(1,"ended loop rearmed by policy");
    endtask
    task finish_fade(input integer old_ends, old_session, old_loads);
        for(integer i=0;i<400 && fade_active;i++)tick();
        repeat(3)tick();
        if(fade_active || gain || !released || ends!=old_ends+1 ||
           session_id!=old_session || loads!=old_loads)
            $fatal(1,"fade-only failed ends=%d gain=%d",ends,gain);
        // Deliberately leave busy=true and parser done=false: ownership must
        // hold mute independently of delayed endpoint teardown feedback.
        repeat(600)tick();
        policy(0);policy(1);policy(2);
        if(gain || ends!=old_ends+1 || loads!=old_loads)
            $fatal(1,"held mute/idempotence");
    endtask
    initial begin
        integer e,s,l,g,elapsed;
        repeat(3)tick();reset=0;repeat(3)tick();
        // IDLE / malformed / unknown commands have no effect.
        policy(2);if(fade_active || ends || loads) $fatal(1,"idle command");
        load_track();
        policy(2,3);policy(2,5);policy(2,4,1);policy(3);policy(255);
        if(fade_active || gain!=256) $fatal(1,"invalid command");
        e=ends;s=session_id;l=loads;
        policy(2);
        if(!fade_active || !dut.mode5_fade_only_owned ||
           dut.mode5_loop_limit_policy_pending) $fatal(1,"accept/policy isolation");
        g=gain;policy(2);if(gain>=g) $fatal(1,"duplicate restarted/paused fade");
        finish_fade(e,s,l);
        // New accepted index-1 is the only rearm.
        load_track();if(dut.mode5_fade_only_owned) $fatal(1,"new ownership");
        // EOF after command and command while EOF fade both share one end.
        e=ends;s=session_id;l=loads;policy(2);
        loaded_player_done=1;tick();finish_fade(e,s,l);
        load_track();e=ends;s=session_id;l=loads;
        loaded_player_done=1;tick();policy(2);finish_fade(e,s,l);
        // Fatal wins even immediately before completion.
        load_track();policy(2);
        while(gain>1)tick();
        e=ends;vgm_player_error=1;tick();repeat(5)tick();
        if(gain || fade_active || ends!=e) $fatal(1,"fatal race");
        policy(2);if(ends!=e || gain) $fatal(1,"fatal retrigger");
        reset=1;tick();reset=0;vgm_player_error=0;
        playback_started=0;player_busy=0;audio_runtime_open=0;loaded_player_done=0;
        load_track();policy(2);e=ends;
        reset=1;tick();playback_started=0;player_busy=0;audio_runtime_open=0;
        repeat(5)tick();reset=0;repeat(400)tick();
        if(fade_active || ends!=e) $fatal(1,"Stop race");
        load_track();e=ends;s=session_id;l=loads;policy(2);finish_fade(e,s,l);
        // A real incoming replacement joins FADE_ONLY, not a second engine.
        load_track();e=ends;l=loads;policy(2);load_track();
        if(ends!=e+1 || loads!=l+1) $fatal(1,"replacement join");
        // Explicit fade-only takes over a predicted ramp like manual Next,
        // without restoring gain; later Repeat policy cannot cancel that owner.
        policy(1);load_track();
        mode5_player_loop_entry_pulse=1;tick();mode5_player_loop_entry_pulse=0;
        repeat(80)wait_sample();
        mode5_player_loop_boundary_pulse=1;tick();mode5_player_loop_boundary_pulse=0;
        repeat(20)wait_sample();g=gain;
        e=ends;s=session_id;l=loads;policy(2);policy(0);
        if(loop_limit_active || gain>g || !fade_active) $fatal(1,"loop takeover");
        finish_fade(e,s,l);
        $display("PASS FADE_ONLY valid/invalid, session/index isolation, duplicate, >100ms held zero, policy, EOF, Stop, FATAL, replacement, loop takeover");
        $finish;
    end
endmodule
