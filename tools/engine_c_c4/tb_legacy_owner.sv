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
    task policy(input bit enabled,input integer bytes=4,input bit malformed=0);
        ioctl_index=2;ioctl_download=1;tick();
        for(integer n=0;n<bytes;n++) begin
            ioctl_wr=1;ioctl_addr=n;
            case(n) 0:ioctl_dout=malformed?0:8'h4d;1:ioctl_dout=8'h56;2:ioctl_dout=2;3:ioctl_dout={7'd0,enabled};default:ioctl_dout=0;endcase
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
    initial begin
        repeat(3)tick();reset=0;repeat(3)tick();
        load_track();eof_track();
        policy(1,3);policy(1,5);policy(1,4,1);
        if(dut.mode5_loop_limit_policy_pending || dut.mode5_loop_limit_policy_active || gain)
            $fatal(1,"malformed policy was applied/rearmed");
        loop_track(100000);loop_track(80);
        // Repeat One disables finite-loop stop, without a second transition owner.
        policy(0);load_track();
        for(integer i=0;i<3;i++)begin mode5_player_loop_boundary_pulse=1;tick();mode5_player_loop_boundary_pulse=0;tick();end
        if(halt_loop || fade_active) $fatal(1,"Repeat One policy");
        // A replacement arriving during an EOF fade must join its owner.
        loaded_player_done=1;tick();repeat(20)tick();
        begin
            integer before_end,before_load;
            before_end=ends;before_load=loads;load_track();
            if(ends!=before_end+1 || loads!=before_load+1) $fatal(1,"EOF/replacement double owner");
        end
        // Repeat One update while a short-loop fade is active cancels only it.
        policy(1);load_track();
        mode5_player_loop_entry_pulse=1;tick();mode5_player_loop_entry_pulse=0;
        repeat(80)wait_sample();
        mode5_player_loop_boundary_pulse=1;tick();mode5_player_loop_boundary_pulse=0;
        repeat(20)wait_sample();
        if(!loop_limit_active || !fade_active) $fatal(1,"loop fade setup");
        policy(0);
        if(fade_active || halt_loop || gain!=256 || end_pulse) $fatal(1,"Repeat One cancellation");
        // Mixed natural/replacement generations; loads during a fade join it.
        for(integer n=0;n<100;n++)begin
            if(n%2==0)eof_track();
            load_track();
        end
        loaded_player_done=1;tick();vgm_player_error=1;tick();
        if(gain!=0 || fade_active || end_pulse) $fatal(1,"FATAL overwritten by END");
        reset=1;tick();reset=0;vgm_player_error=0;
        playback_started=0;player_busy=0;audio_runtime_open=0;loaded_player_done=0;
        load_track();
        reset=1;tick();if(fade_active || end_pulse) $fatal(1,"Stop did not clear owner");
        $display("PASS reference owner cold/warm100 EOF/manual/loop/Repeat/policy/FATAL/Stop loads=%0d ends=%0d",loads,ends);
        $finish;
    end
endmodule
