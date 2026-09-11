`timescale 1ns/1ps
// Actual Golden upload/backend, byte addressing, arbiter and descriptor DDR.
module tb_fault;
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
    integer n,fd,remaining=0,latency=0,beat_address=0,cycles=0;
    integer descriptor_writes=0,raw_writes=0;
    string filename;
    logic rejecting;
    logic drop_reads=0, stuck_busy=0, corrupt_reads=0;
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
                dout<=ram[beat_address] | ((corrupt_reads && beat_address[0]) ? 64'h8000000000000000 : 64'd0);dv<=!drop_reads;
                beat_address<=beat_address+1;remaining<=remaining-1;
            end
        end
        if(dre||dwe) begin
            assert(!dbusy && da>=29'h06000000 && da<29'h06180000) else $fatal(1,"DDR range/busy");
            if(dre) begin
                assert(remaining==0 && burst!=0) else $fatal(1,"DDR overlapping burst");
                remaining<=int'(burst);latency<=4;beat_address<=int'(da-29'h06000000);
            end else begin
                assert(burst==1) else $fatal(1,"write burst");
                for(integer i=0;i<8;i++) if(be[i]) ram[da-29'h06000000][8*i+:8]<=din[8*i+:8];
                if(da>=29'h06100000) descriptor_writes<=descriptor_writes+1;
                else raw_writes<=raw_writes+1;
            end
        end
    end
    task tick; @(posedge clk); #1; @(negedge clk); endtask
    initial begin
        integer fault_code;
        assert($value$plusargs("STREAM=%s",filename)) else $fatal;
        fault_code=$test$plusargs("CORRUPT")?8'h81:8'h80;
        fd=$fopen(filename,"rb");assert(fd) else $fatal;
        n=$fread(file_bytes,fd);$fclose(fd);rejecting=0;
        repeat(4) tick();reset=0;index=1;download=1;tick();
        for(integer i=0;i<n;i++) begin
            while(wait_io) tick();wr=1;address=27'(i);data=file_bytes[i];tick();wr=0;tick();
        end
        download=0;
        while(!busy && !err) tick();
        assert(busy && !err) else $fatal;
        // Inject the I/O fault while the real common owner is fading.
        index=2;download=1;tick();
        for(integer i=0;i<4;i++) begin
            address=27'(i);wr=1;
            case(i) 0:data=8'h4d;1:data=8'h56;2:data=2;3:data=2;endcase
            tick();wr=0;tick();
        end
        download=0;repeat(5)tick();
        assert(dut.transition_fade) else $fatal(1,"fault test did not enter fade");
        if(fault_code==8'h81) corrupt_reads=1;else drop_reads=1;
        while(dut.transport_state!=4) tick();
        assert(dut.published_error==fault_code)
            else $fatal(1,"first profile fault code=%h expected=%h",dut.published_error,fault_code);
        // A later physical return timeout may supersede the parser code with
        // reference publisher's higher-priority common load/I/O error F1.
        repeat(10000) tick();
        assert(err && dut.transport_state==4 &&
               (dut.published_error==fault_code || dut.published_error==8'hf1) &&
               dut.transport_session==1 && dut.end_count==0 && !dut.transition_fade &&
               dut.transition_gain==0 && al==0 && ar==0)
            else $fatal(1,"profile I/O fault not published code=%h expected=%h",dut.published_error,fault_code);
        $display("FULL SHELL FATAL code=%h, same accepted session, no ENDED, zero audio PASS",fault_code);
        $finish;
    end
    initial begin #20000000000;$fatal(1,"fault timeout");end
endmodule
