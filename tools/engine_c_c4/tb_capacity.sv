`timescale 1ns/1ps
// Actual Golden upload/backend, byte addressing, arbiter and descriptor DDR.
module tb_shell;
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
        .transport_hps_status(128'd0),.transport_status_in(),.transport_status_set(),
        .ddram_busy(dbusy),.ddram_burstcnt(burst),.ddram_addr(da),.ddram_dout(dout),
        .ddram_dout_ready(dv),.ddram_rd(dre),.ddram_din(din),.ddram_be(be),.ddram_we(dwe)
    );
    always @(posedge clk) begin
        if(dut.v1_1_profile.engine.reg_write && !reset && !(download && index==1)) begin
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
        cycles<=cycles+1;dbusy<=cycles%19==0;
        dv<=0;
        if(remaining!=0) begin
            if(latency!=0) latency<=latency-1;
            else begin
                dout<=ram[beat_address];dv<=1;
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
        assert($value$plusargs("STREAM=%s",filename)) else $fatal;
        rejecting=$test$plusargs("REJECT");
        model_sequence=$test$plusargs("MODEL_SEQUENCE");
        fd=$fopen(filename,"rb");assert(fd) else $fatal;
        n=$fread(file_bytes,fd);$fclose(fd);
        repeat(4) tick();reset=0;
        for(integer session=1;session<=3;session++) begin
            if(model_sequence) begin
                expected_model=session==2?2:1;expected_timing=session==2?2:1;
                expected_hz=session==2?1022727:985248;
                file_bytes[28]=8'(expected_model);file_bytes[29]=8'(expected_timing);
                for(integer j=0;j<4;j++) file_bytes[20+j]=expected_hz[8*j+:8];
            end
            if(session==3) begin
                // Shrink to a legal EOF-only session without clearing DDR RAM.
                // This also proves recovery from a preceding oversize rejection.
                n=144;rejecting=0;
                for(integer i=40;i<64;i++) file_bytes[i]=0;
                file_bytes[40]=1;file_bytes[48]=16;
                for(integer i=128;i<144;i++) file_bytes[i]=0;
                file_bytes[128]=8'hff;
            end
            expected_event=128;expected_cycle=0;observed_writes=0;
            index=1;download=1;tick();
            for(integer i=0;i<n;i++) begin
                while(wait_io) tick();
                wr=1;address=27'(i);data=file_bytes[i];tick();wr=0;tick();
            end
            download=0;
            while(!busy && !done && !err) tick();
            assert(dut.parser_start_count==32'(session)) else $fatal(1,"session start count");
            if(rejecting) begin
                assert(err && !busy && !done && !gate && al==0) else $fatal(1,"oversize not rejected");
                $display("SHELL reject session=%0d bytes=%0d",session,n);
            end else begin
                assert(!err) else $fatal(1,"preflight error");
                for(integer t=0;t<10000000 && !done && !err;t++) begin
                    if(t==1000) begin index=2;download=1;data=0; end
                    if(t>=1001 && t<1005) begin wr=1;address=27'(t-1001); end
                    if(t==1005) begin wr=0;download=0; end
                    tick();
                    assert(al==ar) else $fatal(1,"stereo mirror");
                end
                assert(done && !err) else $fatal(1,"shell EOF");
                consume_waits();
                assert(expected_event==n-16 && file_bytes[expected_event]==8'hff &&
                       dut.v1_1_profile.engine.native_cycle==expected_cycle)
                    else $fatal(1,"uploaded EOF/missing WRITE mismatch");
                assert(dut.parser_start_count==32'(session)) else $fatal(1,"index2 rearm");
                $display("SHELL accepted session=%0d bytes=%0d raw_word_writes=%0d descriptor_word_writes=%0d",session,n,raw_writes,descriptor_writes);
            end
            repeat(1000) begin tick();assert(al==0 && ar==0 && !gate) else $fatal(1,"EOF/reject leak"); end
            assert(dut.transport_state==(rejecting?4:3) && dut.transport_session==32'(session))
                else $fatal(1,"completion/fatal did not reach published session ABI");
        end
        // Upload address bit 23 MUST reject, never alias byte zero. This is
        // beyond both the new logical limit and the frozen physical window.
        index=1;download=1;tick();
        while(wait_io) tick();
        wr=1;address=27'h0800000;data=8'haa;tick();wr=0;tick();download=0;
        repeat(100) tick();
        assert(dut.upload_load_overflow && !dut.upload_load_done &&
               dut.parser_start_count==3 && al==0 && ar==0)
            else $fatal(1,"physical 8MiB boundary wrapped/accepted");
        $display("SHELL physical address 0x800000 rejected without parser start");
        $finish;
    end
    initial begin #20000000000; $fatal(1,"shell timeout"); end
endmodule
