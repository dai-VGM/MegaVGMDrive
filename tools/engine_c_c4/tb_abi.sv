`timescale 1ns/1ps
module tb_transport;
    logic clk=0, reset=1, download=0, write_byte=0;
    logic [15:0] index=1;
    logic [26:0] address=0;
    logic [7:0] data=0;
    logic upload_done=0, upload_error=0, upload_overflow=0;
    logic profile_started=0, profile_busy=0, profile_done=0, profile_fatal=0;
    logic [7:0] profile_error=8'h0d;
    logic profile_loop_valid=0;
    logic [31:0] profile_loop_count=0;
    wire vgm_download, policy_download,load_begin,load_complete,load_accepted,session_start,playback_start,done;
    wire [31:0] session_id,done_session_id,error_session_id;
    wire upload_busy = vgm_download || (!upload_done && session_id!=0);
    wire [2:0] state;
    wire [7:0] error_code;
    wire loop_valid;
    wire [15:0] loop_count;
    wire [127:0] status_in;
    wire status_set;
    wire playback_busy,player_error;
    logic [127:0] hps_status=128'h000000000000000012345678abcdef01;
    integer begins=0,completes=0,accepts=0,starts=0,plays=0;
    logic last_set=0;
    always #5 clk=~clk;
    golden_shell_transport dut(.*);
    always @(posedge clk) if(!reset) begin
        if(load_begin) begins++;
        if(load_complete) completes++;
        if(load_accepted) accepts++;
        if(session_start) starts++;
        if(playback_start) plays++;
        if(status_set && last_set) $fatal(1,"status_set missing full low cycle");
        last_set<=status_set;
        if(status_in[63:0] !== hps_status[63:0]) $fatal(1,"HPS low bits changed");
        if((^{status_set,status_in,session_id,done})===1'bx) $fatal(1,"unknown ABI");
    end
    task tick; @(posedge clk); #1; endtask
    task record(input integer id,input integer st);
        repeat(8)tick();
        if(status_in[127:120]!=8'h4d || status_in[119:116]!=2 ||
           status_in[115:84]!=id || status_in[83:81]!=st)
            $fatal(1,"record mismatch expected session=%d state=%d actual=%h",id,st,status_in[127:64]);
    endtask
    task begin_upload(input integer id);
        @(negedge clk);index=1;download=1;upload_done=0;
        tick();
        if(session_id!=id) $fatal(1,"session did not increment at first admitted edge");
        record(id,1);
        // Old profile busy/done/fatal must not be mistaken for new ownership.
        @(negedge clk);profile_busy=0;profile_done=0;profile_fatal=0;
        profile_loop_valid=0;profile_loop_count=0;upload_error=0;upload_overflow=0;
        download=0;repeat(3)tick();
    endtask
    task finish_upload;
        upload_done=1;repeat(4)tick();
        if(plays!=0 && done) $fatal(1,"stale done survived admitted load");
    endtask
    task start_profile;
        profile_started=1;profile_busy=1;tick();profile_started=0;repeat(3)tick();
    endtask
    task policy;
        @(negedge clk);index=2;download=1;write_byte=1;
        repeat(4)tick();
        if(vgm_download || !policy_download || load_begin || load_accepted || session_start)
            $fatal(1,"policy entered VGM lifecycle");
        download=0;write_byte=0;repeat(4)tick();
    endtask
    initial begin
        repeat(3)tick();reset=0;record(0,0);
        for(integer n=1;n<=25;n++) begin
            begin_upload(n);finish_upload();record(n,1);
            start_profile();record(n,2);
            if(starts!=n || accepts!=n || begins!=n || plays!=n) $fatal(1,"generation/start count");
            policy();record(n,2);
            profile_loop_valid=1;repeat(3)tick();
            for(integer k=1;k<=3;k++) begin
                profile_loop_count=k;repeat(4)tick();
                if(loop_count!=k) $fatal(1,"boundary counter adapter");
            end
            profile_done=1;profile_busy=0;record(n,3);
            if(!done || done_session_id!=n) $fatal(1,"session-qualified completion");
            policy();record(n,3);
        end
        begin_upload(26);upload_error=1;record(26,4);
        if(error_code!=8'hf1 || plays!=25) $fatal(1,"load error ownership");
        begin_upload(27);upload_overflow=1;record(27,4);
        if(error_code!=8'hf2) $fatal(1,"overflow mapping");
        begin_upload(28);finish_upload();profile_fatal=1;record(28,4);
        if(error_code!=8'h0d || error_session_id!=28) $fatal(1,"scan reject ownership");
        // Leave old fatal high across next admission to expose stale relabelling.
        begin_upload(29);finish_upload();start_profile();record(29,2);
        profile_loop_valid=1;repeat(3)tick();
        for(integer k=1;k<=65538;k++) begin profile_loop_count=k;tick();end
        repeat(5)tick();if(loop_count!=16'hffff) $fatal(1,"reference loop saturation");
        policy();record(29,2);
        if(begins!=29 || starts!=29 || accepts!=29 || plays!=26) $fatal(1,"duplicate admission");
        // Reset rejects all transfers and resets the public generation, as Main expects.
        reset=1;download=1;index=1;repeat(3)tick();
        if(vgm_download || session_id || status_set) $fatal(1,"reset admission");
        download=0;profile_busy=0;profile_loop_valid=0;upload_done=0;reset=0;
        record(0,0);
        $display("PASS ABI 29 admitted generations/26 plays, reset/index-2 isolation, stale ownership, FATAL, saturation");
        $finish;
    end
endmodule
