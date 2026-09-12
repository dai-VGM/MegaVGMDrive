`timescale 1ns/1ps
// Actual Golden upload/backend, byte addressing, arbiter and descriptor DDR.
module tb_transport;
    logic clk=0,reset=1;
    always #25 clk=~clk;
    logic download=0,wr=0;
    logic [26:0] address=0;
    logic [7:0] data=0;
    logic [15:0] index=1;
    wire wait_io,busy,done,err,gate,sample_valid;
    wire signed [15:0] al,ar;
    wire [28:0] da;
    wire [63:0] din;
    logic [63:0] dout=0;
    wire [7:0] be,burst;
    wire dre,dwe;
    logic dv=0,dbusy=0;
    // Raw bytes 0x30000000..0x307fffff; descriptor bytes 0x30800000..0x30bfffff.
    logic [63:0] ram[0:1572863];
    byte unsigned file_bytes[0:4194319];
    byte unsigned upload_bytes[0:4194319];
    integer upload_n=0,upload_serial=0;
    task put_uleb(input logic [63:0] value);
        logic [63:0] v;
        v=value;
        while(v>=128) begin upload_bytes[upload_n]=8'(v)|8'h80;upload_n++;v=v>>7;end
        upload_bytes[upload_n]=8'(v);upload_n++;
    endtask
    task build_upload;
        logic [63:0] delta,count,packed_size;
        logic packing;
        packing=!$test$plusargs("V1_ONLY") && (!$test$plusargs("MIXED") || upload_serial%2==1);
        upload_serial++;
        for(integer j=0;j<128;j++) upload_bytes[j]=file_bytes[j];
        if(!packing) begin
            upload_n=n;for(integer j=128;j<n;j++) upload_bytes[j]=file_bytes[j];
        end else begin
            upload_n=128;delta=0;count=0;
            for(integer j=128;j<n;j+=16) begin
                if(file_bytes[j]==0) delta=delta+operand_at(j);
                else begin
                    put_uleb(delta);delta=0;
                    if(file_bytes[j]==1) begin
                        upload_bytes[upload_n]=file_bytes[j+1];upload_bytes[upload_n+1]=file_bytes[j+2];
                        upload_n+=2;count++;
                    end else begin upload_bytes[upload_n]=255;upload_n++;end
                end
            end
            upload_bytes[8]=2;upload_bytes[14]=1;packed_size=64'(upload_n-128);
            for(integer j=0;j<8;j++) begin
                upload_bytes[40+j]=count[8*j+:8];upload_bytes[48+j]=packed_size[8*j+:8];
            end
        end
    endtask
    integer n,fd,remaining=0,latency=0,beat_address=0,cycles=0,read_delay=4;
    integer descriptor_writes=0,raw_writes=0;
    string filename;
    logic rejecting;
    logic drop_reads=0, stuck_busy=0;
    wire [127:0] status_in;
    wire status_set;
    integer ce_total=0, publication_total=0, reset_edges=0;
    integer fade_start_cycle=0,fade_pauses=0,checked_fades=0;
    logic previous_fade=0;
    logic previous_reset=0;
    wire sid_reset=dut.v1_1_profile.session_reset;
    wire raw_ce=dut.v1_1_profile.engine.ce_sid;
    wire raw_valid=dut.v1_1_profile.engine.sample_valid;
    logic model_sequence;
    integer expected_model=1,expected_timing=1;
    logic [31:0] expected_hz=985248;
    integer expected_event=128,observed_writes=0;
    logic [63:0] expected_cycle=0;
    function automatic logic [63:0] operand_at(input integer at_byte);
        logic [63:0] value;
        value=0;
        for(integer j=0;j<8;j++) value[j*8+:8]=file_bytes[at_byte+8+j];
        return value;
    endfunction
    task consume_waits;
        while(expected_event<n && file_bytes[expected_event]==0) begin
            expected_cycle=expected_cycle+operand_at(expected_event);
            expected_event=expected_event+16;
        end
    endtask
    mister_vgm_md_top #(.VGM_LOAD_ADDR_WIDTH(23)) dut(
        .clk(clk),.reset_n(!reset),.audio_l(al),.audio_r(ar),.audio_sample_valid(sample_valid),
        .audio_lpf_mode(2'd0),.audio_gain_boost(1'b0),.audio_psg_level(2'd0),
        .player_busy(busy),.player_done(done),.audio_gate_open(gate),
        .ioctl_download(download),.ioctl_wr(wr),.ioctl_addr(address),.ioctl_dout(data),
        .ioctl_index(index),.ioctl_wait(wait_io),.vgm_player_error(err),
        .transport_hps_status(128'h1234),.transport_status_in(status_in),.transport_status_set(status_set),
        .ddram_busy(dbusy),.ddram_burstcnt(burst),.ddram_addr(da),.ddram_dout(dout),
        .ddram_dout_ready(dv),.ddram_rd(dre),.ddram_din(din),.ddram_be(be),.ddram_we(dwe)
    );
    always @(posedge clk) begin
        if(reset) previous_fade<=0;
        else begin
            previous_fade<=dut.transition_fade;
            if(dut.transition_fade && !previous_fade) begin
                fade_start_cycle=cycles;fade_pauses=0;
            end
            if(dut.transition_fade && dut.transition_owner.mode5_parser_done_edge)
                fade_pauses++;
            if(!dut.transition_fade && previous_fade && !err && !dut.io_fault) begin
                assert(cycles-fade_start_cycle==2000128+fade_pauses)
                    else $fatal(1,"production fade timing cycles=%0d pauses=%0d",cycles-fade_start_cycle,fade_pauses);
                checked_fades++;
                $display("FADE duration=%0d SYS clocks (%0d parser-EOF join clocks)",cycles-fade_start_cycle,fade_pauses);
            end
        end
        if(dut.v1_1_profile.engine.reg_write && !sid_reset) begin
            assert(dut.v1_1_profile.engine.sound.session_model==(expected_model==2) &&
                   dut.v1_1_profile.engine.session_timing==expected_timing &&
                   dut.v1_1_profile.engine.session_clock_num==expected_hz &&
                   dut.v1_1_profile.engine.session_clock_den==1)
                else $fatal(1,"shell model/timing publication mismatch");
            consume_waits();
            assert(!rejecting && expected_event<n && file_bytes[expected_event]==1 &&
                   dut.v1_1_profile.engine.reg_addr==file_bytes[expected_event+1] &&
                   dut.v1_1_profile.engine.reg_data==file_bytes[expected_event+2])
                else $fatal(1,"uploaded WRITE address/data/order mismatch");
            assert(expected_cycle==(dut.v1_1_profile.engine.scheduler.launched?dut.v1_1_profile.engine.native_cycle+1:64'd0))
                else $fatal(1,"uploaded WRITE native-cycle mismatch");
            expected_event=expected_event+16;observed_writes=observed_writes+1;
        end
        cycles<=cycles+1;dbusy<=stuck_busy || cycles%19==0;
        if(raw_ce) ce_total<=ce_total+1;
        if(raw_valid) publication_total<=publication_total+1;
        if(sid_reset && !previous_reset) reset_edges<=reset_edges+1;
        previous_reset<=sid_reset;
        if(!reset) begin
            assert(al==ar) else $fatal(1,"stereo");
            if(sid_reset || dut.transition_gain==0 || err || dut.io_fault)
                assert(al==0 && ar==0) else $fatal(1,"mute/fatal output leak");
            if(status_set) assert(status_in[127:120]==8'h4d && status_in[119:116]==2 && status_in[63:0]==64'h1234)
                else $fatal(1,"status v2 ABI corruption");
        end
        dv<=0;
        if(remaining!=0) begin
            if(latency!=0) latency<=latency-1;
            else begin
                dout<=ram[beat_address];dv<=!drop_reads;
                beat_address<=beat_address+1;remaining<=remaining-1;
            end
        end
        if(dre||dwe) begin
            assert(!dbusy && da>=29'h06000000 && da<29'h06180000) else $fatal(1,"DDR range/busy");
            if(dre) begin
                assert(remaining==0 && burst!=0) else $fatal(1,"DDR overlapping burst");
                remaining<=int'(burst);latency<=read_delay;beat_address<=int'(da-29'h06000000);
            end else begin
                assert(burst==1) else $fatal(1,"write burst");
                for(integer i=0;i<8;i++) if(be[i]) ram[da-29'h06000000][8*i+:8]<=din[8*i+:8];
                if(da>=29'h06100000) descriptor_writes<=descriptor_writes+1;
                else raw_writes<=raw_writes+1;
            end
        end
    end
    task tick; @(posedge clk); #1; @(negedge clk); endtask
    task settle; repeat(8) tick(); endtask
    task policy(input byte command);
        integer ss,sc,rs;
        logic ready_before;
        ss=dut.transport_session;sc=dut.parser_start_count;rs=reset_edges;
        ready_before=dut.profile_ready;
        index=2;download=1;tick();
        for(integer i=0;i<4;i++) begin
            address=27'(i);wr=1;
            case(i) 0:data=8'h4d;1:data=8'h56;2:data=2;3:data=command;endcase
            tick();wr=0;tick();
            assert(!dut.transport_load_begin && !dut.transport_vgm_download && !sid_reset)
                else $fatal(1,"index2 entered reset/load");
        end
        download=0;settle();
        assert(dut.transport_session==ss && dut.parser_start_count==sc && reset_edges==rs)
            else $fatal(1,"index2 changed session/reset/start");
        if(ready_before) assert(dut.profile_ready) else $fatal(1,"index2 lost audio_ready");
    endtask
    task configure(input integer model,timing);
        expected_model=model;expected_timing=timing;expected_hz=timing==1?985248:1022727;
        file_bytes[28]=8'(model);file_bytes[29]=8'(timing);
        for(integer j=0;j<4;j++) file_bytes[20+j]=expected_hz[8*j+:8];
    endtask
    task duration(input logic [63:0] end_cycle);
        logic [63:0] wait_cycles;
        wait_cycles=end_cycle-5;
        for(integer j=0;j<8;j++) begin
            file_bytes[56+j]=end_cycle[8*j+:8];
            file_bytes[n-24+j]=wait_cycles[8*j+:8];
        end
    endtask
    task upload;
        integer old_ss,old_start,old_reset,old_begin;
        logic old_model;
        logic [31:0] old_clock;
        old_ss=dut.transport_session;old_start=dut.parser_start_count;
        old_reset=reset_edges;old_begin=dut.begin_count;
        old_model=dut.v1_1_profile.engine.session_model;
        old_clock=dut.v1_1_profile.engine.session_clock_num;
        index=1;download=1;#1;
        // Host leaves TX enabled and waits. SID/parser/model stay old until zero.
        while(wait_io) begin
            assert(dut.transport_session==old_ss && dut.parser_start_count==old_start &&
                   reset_edges==old_reset && dut.v1_1_profile.engine.session_model==old_model &&
                   dut.v1_1_profile.engine.session_clock_num==old_clock)
                else $fatal(1,"replacement accepted/reset/config changed before fade zero");
            tick();
        end
        if(old_ss!=0 && dut.profile_started)
            assert(dut.transition_gain==0) else $fatal(1,"replacement admitted nonzero");
        // Set expected stream only AFTER the old fade and its native WRITEs.
        expected_event=128;expected_cycle=0;observed_writes=0;
        tick();
        build_upload();
        for(integer i=0;i<upload_n;i++) begin
            while(wait_io) tick();
            wr=1;address=27'(i);data=upload_bytes[i];tick();wr=0;tick();
        end
        download=0;settle();
        assert(dut.transport_session==old_ss+1 && dut.begin_count==old_begin+1)
            else $fatal(1,"accepted session increment");
        while(dut.transport_state==1 && !busy && !done && !err) tick();
        assert(dut.transport_session==old_ss+1) else $fatal(1,"double session");
    endtask
    task playing;
        while(!dut.profile_ready && !err) tick();
        settle();
        assert(busy && !done && !err && dut.transport_state==2 && dut.transition_gain==256)
            else $fatal(1,"not PLAYING state=%d error=%d",dut.transport_state,dut.profile_status[15:8]);
        repeat(20000) tick();
    endtask
    task hold_ended;
        integer ss,ec,pc,ce0;
        ss=dut.transport_session;ec=dut.end_count;pc=publication_total;ce0=ce_total;
        assert(done && !busy && !err && dut.transition_gain==0 && dut.transport_state==3)
            else $fatal(1,"ENDED ABI");
        policy(0);policy(1);policy(2);
        repeat(2001000) begin
            tick();
            assert(al==0 && ar==0 && dut.transition_gain==0 && !dut.transition_fade &&
                   !dut.v1_1_profile.engine.reg_write)
                else $fatal(1,"old session resurrection");
        end
        assert(dut.transport_session==ss && dut.end_count==ec &&
               publication_total>pc && ce_total>ce0) else $fatal(1,"ended SID clock stopped or duplicate");
    endtask
    task fade_to_end;
        integer e,c,p,tail_nonzero;
        e=dut.end_count;c=ce_total;p=publication_total;tail_nonzero=0;
        while(!done && !err) begin
            if(dut.transition_fade && dut.transition_gain>0 && al!=0) tail_nonzero++;
            tick();
        end
        settle();
        assert(!err && dut.end_count==e+1 && ce_total>c && publication_total>p)
            else $fatal(1,"fade/END clock contract");
        assert(tail_nonzero>10) else $fatal(1,"EOF/busy prematurely muted tail");
        hold_ended();
    endtask
    initial begin
        assert($value$plusargs("STREAM=%s",filename)) else $fatal;
        fd=$fopen(filename,"rb");assert(fd) else $fatal;
        n=$fread(file_bytes,fd);$fclose(fd);
        rejecting=0;repeat(4) tick();reset=0;settle();
        // An audible, sustained original synthetic tone (not silence after gate-off).
        for(integer t=0;t<4;t++) begin
            duration(t==0?50000:600000);
            configure((t%2)+1,(t/2)+1);upload();playing();
            if(t==0) begin
                // natural EOF; scheduler stops but SID must still ring through fade.
                while(!dut.parser_done) tick();
                assert(!dut.v1_1_profile.raw_busy && busy && !done) else $fatal(1,"parser vs session");
                fade_to_end();
            end else begin
                policy(2);
                assert(dut.transition_fade) else $fatal(1,"FADE_ONLY not accepted");
                policy(2);fade_to_end();
                assert(!dut.v1_1_profile.raw_done && dut.v1_1_profile.finished &&
                       dut.v1_1_profile.engine.native_cycle<600000)
                    else $fatal(1,"FADE_ONLY did not terminate before parser EOF");
            end
            $display("TRANSPORT model=%0d timing=%0d EOF/FADE_ONLY, held zero, policy isolation PASS",expected_model,expected_timing);
        end
        // Replacement PAL/6581 -> NTSC/8580: load/reset/config stay deferred. No old END
        // for a pure manual replacement (reference contract).
        configure(1,1);upload();playing();
        begin
            integer e;
            e=dut.end_count;
            configure(2,2);
            upload();playing();
            assert(dut.end_count==e) else $fatal(1,"manual replacement phantom END");
            policy(2);fade_to_end();
        end
        // EOF arrives during FADE_ONLY; exactly one completion, no restart.
        duration(50000);
        upload();playing();
        while(dut.v1_1_profile.engine.native_cycle<45000) tick();
        policy(2);fade_to_end();
        // Stop during audible fade: immediate reset/mute, no synthetic EOF.
        upload();playing();policy(2);
        reset=1;tick();
        assert(al==0 && ar==0 && !done) else $fatal(1,"Stop not immediate");
        reset=0;settle();repeat(2100000) tick();
        assert(dut.transport_session==0 && !done && dut.end_count==0 && al==0 &&
               dut.transport_state==0) else $fatal(1,"phantom END after Stop");
        // Recovery starts from a clean generation.
        upload();playing();policy(2);fade_to_end();
        // Validation rejection belongs to accepted new session, no rollback.
        file_bytes[28]=0;rejecting=1;upload();settle();
        assert(err && dut.transport_state==4 && !done && al==0) else $fatal(1,"malformed not FATAL");
        configure(2,2);rejecting=0;upload();playing();
        // Actual read-return loss (C2 store watchdog / native underflow) is
        // exercised by direct C3/C4 regressions; this is physical raw-read loss.
        policy(2);fade_to_end();
        drop_reads=1;index=1;download=1;tick();
        for(integer i=0;i<upload_n;i++) begin
            while(wait_io) tick();
            wr=1;address=27'(i);data=upload_bytes[i];tick();wr=0;tick();
        end
        download=0;repeat(3000) tick();
        assert(dut.io_fault && dut.transport_state==4 && al==0 && !done)
            else $fatal(1,"DDR return timeout not explicit FATAL");
        // Raw backend times out from its OWN issue, including arbiter queue
        // time. A late but otherwise valid physical response must not turn the
        // fabricated 0x66 into accepted MVGMSID bytes.
        reset=1;tick();reset=0;drop_reads=0;remaining=0;read_delay=400;settle();
        index=1;download=1;tick();
        for(integer i=0;i<upload_n;i++) begin
            while(wait_io) tick();
            wr=1;address=27'(i);data=upload_bytes[i];tick();wr=0;tick();
        end
        download=0;
        while(!dut.ua_rd) tick();
        stuck_busy=1;repeat(800) tick();stuck_busy=0;repeat(1500) tick();
        assert(dut.raw_response_fault && !dut.physical_io_fault &&
               dut.transport_state==4 && al==0 && !done)
            else $fatal(1,"queued/late raw response was not rejected by provenance");
        read_delay=4;
        // Permanent external BUSY during upload must not strand Main on
        // ioctl_wait: C4 reports the I/O failure and discards remaining bytes.
        reset=1;tick();reset=0;drop_reads=0;remaining=0;settle();
        stuck_busy=1;tick();index=1;download=1;tick();
        for(integer i=0;i<4096;i++) begin
            while(wait_io) tick();
            wr=1;address=27'(i);data=8'haa;tick();wr=0;tick();
        end
        download=0;settle();
        assert(dut.io_fault && dut.transport_state==4 && !wait_io &&
               dut.transport_session==1 && dut.parser_start_count==0 && !done)
            else $fatal(1,"stuck BUSY did not release Main and publish FATAL");
        $display("TRANSPORT full shell natural EOF, duplicate/EOF FADE_ONLY, replacement, Stop, FATAL, mixed sessions, >100ms silence PASS");
        $finish;
    end
    initial begin #20000000000; $fatal(1,"transport timeout"); end
endmodule
