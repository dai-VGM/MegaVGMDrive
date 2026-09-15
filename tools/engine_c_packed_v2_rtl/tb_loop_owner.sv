`timescale 1ns/1ps
module tb_loop_owner;
    logic clk=0,reset=1,download=0,write_byte=0;
    logic [15:0] index=0;logic [26:0] address=0;logic [7:0] data=0;
    logic playback_started=0,player_busy=0,parser_done=0;
    logic [31:0] session=1,ticks=0;logic loop_entry=0,loop_boundary=0;
    wire admitted_download,admitted_write,wait_io,load_begin,halt_loop;
    wire [8:0] gain;wire fade,released,end_pulse,limit_active;
    integer ended=0;
    always #5 clk=~clk;
    always @(posedge clk)if(end_pulse)ended<=ended+1;
    megavgm_transport_owner #(.MODE5_TRACK_FADE_CYCLES(256),.MODE5_LOOP_LIMIT_FADE_SAMPLES(64)) dut(
        .clk(clk),.reset(reset),.ioctl_download(download),.ioctl_wr(write_byte),
        .ioctl_index(index),.ioctl_addr(address),.ioctl_dout(data),
        .mode5_backend_ioctl_wait(1'b0),.playback_started(playback_started),
        .player_busy(player_busy),.loaded_player_done(parser_done),.session_id(session),
        .vgm_load_busy(1'b0),.vgm_load_error(1'b0),.vgm_load_overflow(1'b0),
        .vgm_player_error(1'b0),.audio_runtime_open(playback_started),
        .vgm_wait_ticks_consumed_debug(ticks),.mode5_player_loop_entry_pulse(loop_entry),
        .mode5_player_loop_boundary_pulse(loop_boundary),.mode5_ioctl_download(admitted_download),
        .mode5_ioctl_wr(admitted_write),.ioctl_wait(wait_io),.mode5_load_begin_pulse(load_begin),
        .halt_loop(halt_loop),.gain(gain),.fade_active(fade),.released(released),
        .end_pulse(end_pulse),.loop_limit_active(limit_active));
    task tick;@(posedge clk);#1;@(negedge clk);endtask
    task policy(input logic [7:0] command);
        index=2;download=1;tick();
        for(integer i=0;i<4;i++)begin address=i;write_byte=1;
            case(i)0:data=8'h4d;1:data=8'h56;2:data=2;default:data=command;endcase
            tick();write_byte=0;tick();
        end
        download=0;tick();tick();
    endtask
    task load;
        index=1;download=1;tick();download=0;tick();
    endtask
    task advance(input integer count);
        repeat(count)begin ticks=ticks+1;tick();end
    endtask
    initial begin
        repeat(3)tick();reset=0;tick();
        // Finite TWO_LOOPS: the first boundary arms loop two; the second is
        // authoritative and emits one END without a reload/session change.
        policy(1);load();playback_started=1;player_busy=1;advance(10);
        loop_entry=1;tick();loop_entry=0;advance(100);loop_boundary=1;tick();loop_boundary=0;tick();
        assert(halt_loop)else $fatal(1,"finite policy did not arm second-boundary halt");
        advance(100);loop_boundary=1;tick();loop_boundary=0;tick();
        assert(ended==1 && released && gain==0 && session==1)else $fatal(1,"finite loop completion");
        repeat(20)tick();assert(ended==1)else $fatal(1,"duplicate finite END");
        // Stop/reset clears the retained owner. Repeat One never asserts halt.
        reset=1;tick();reset=0;ticks=0;ended=0;playback_started=0;player_busy=0;tick();
        policy(0);load();playback_started=1;player_busy=1;loop_entry=1;tick();loop_entry=0;
        advance(50);loop_boundary=1;tick();loop_boundary=0;advance(50);
        loop_boundary=1;tick();loop_boundary=0;repeat(5)tick();
        assert(!halt_loop && ended==0 && gain==256)else $fatal(1,"Repeat One policy changed");
        // FADE_ONLY retains the session and emits one END. A duplicate cannot
        // restart the envelope or create a second END.
        policy(2);policy(2);repeat(400)tick();
        assert(ended==1 && session==1 && gain==0)else $fatal(1,"FADE_ONLY loop session");
        repeat(100)tick();assert(ended==1)else $fatal(1,"duplicate FADE_ONLY END");
        // Replacement owns the same fade but does not manufacture ENDED.
        reset=1;tick();reset=0;ended=0;playback_started=1;player_busy=1;advance(1);
        index=1;download=1;tick();assert(wait_io && fade)else $fatal(1,"replacement fade missing");
        while(wait_io)tick();assert(gain==0 && ended==0)else $fatal(1,"replacement phantom END");
        download=0;tick();
        $display("C7.2 LOOP OWNER Repeat One/TWO_LOOPS/FADE_ONLY/Stop/replacement PASS");
        $finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
