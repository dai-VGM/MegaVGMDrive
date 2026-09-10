`timescale 1ns/1ps
module tb_shell;
    logic clk=0, reset=1;
    always #25 clk=~clk;
    logic download=0, wr=0;
    logic [26:0] address=0;
    logic [7:0] data=0;
    logic [15:0] index=1;
    wire wait_io, busy, done, err, gate, sample_valid;
    wire signed [15:0] al, ar;
    wire [28:0] da;
    wire [63:0] din;
    logic [63:0] dout=0;
    wire [7:0] be, burst;
    wire dre, dwe;
    logic dv=0;
    logic [63:0] ram[0:16383];
    byte unsigned file_bytes[0:131199];
    integer n, fd, publications, changes;
    string filename;
    mister_vgm_md_top #(.VGM_LOAD_ADDR_WIDTH(23)) dut(
        .clk(clk),.reset_n(!reset),.audio_l(al),.audio_r(ar),.audio_sample_valid(sample_valid),
        .audio_lpf_mode(2'd0),.audio_gain_boost(1'b0),.audio_psg_level(2'd0),
        .player_busy(busy),.player_done(done),.audio_gate_open(gate),
        .ioctl_download(download),.ioctl_wr(wr),.ioctl_addr(address),.ioctl_dout(data),
        .ioctl_index(index),.ioctl_wait(wait_io),.vgm_player_error(err),
        .ddram_busy(1'b0),.ddram_burstcnt(burst),.ddram_addr(da),.ddram_dout(dout),
        .ddram_dout_ready(dv),.ddram_rd(dre),.ddram_din(din),.ddram_be(be),.ddram_we(dwe)
    );
    always @(posedge clk) begin
        dv<=dre;
        if(dre) dout<=ram[da[13:0]];
        if(dwe) begin
            assert(burst==1) else $fatal(1,"unexpected DDR burst");
            for(integer i=0;i<8;i++) if(be[i]) ram[da[13:0]][8*i+:8]<=din[8*i+:8];
        end
    end
    task tick; @(posedge clk); #1; @(negedge clk); endtask
    logic signed [15:0] previous;
    initial begin
        assert($value$plusargs("STREAM=%s",filename)) else $fatal;
        fd=$fopen(filename,"rb"); assert(fd) else $fatal;
        n=$fread(file_bytes,fd); $fclose(fd);
        repeat(4) tick(); reset=0;
        for(integer session=1;session<=2;session++) begin
            index=1; download=1; tick();
            for(integer i=0;i<n;i++) begin
                while(wait_io) tick();
                wr=1; address=27'(i); data=file_bytes[i]; tick(); wr=0; tick();
            end
            download=0;
            while(!busy && !err) tick();
            assert(!err && dut.parser_start_count==32'(session)) else $fatal(1,"upload/preflight start");
            publications=0; changes=0; previous=0;
            for(integer t=0;t<250000 && !done && !err;t++) begin
                // Index 2 is intentionally inert in C2; it must not reset/restart.
                if(t==1000) begin index=2; download=1; data=0; end
                if(t>=1001 && t<1005) begin wr=1; address=27'(t-1001); end
                if(t==1005) begin wr=0; download=0; end
                tick();
                if(sample_valid) begin
                    publications++;
                    if(al!=previous) changes++;
                    previous=al;
                end
                assert(al==ar) else $fatal(1,"single SID stereo mirror");
            end
            assert(done && !err && publications>100 && changes>50) else $fatal(1,"shell audio/EOF");
            assert(dut.parser_start_count==32'(session)) else $fatal(1,"index2 rearmed profile");
            repeat(1000) begin tick(); assert(al==0 && ar==0 && !gate) else $fatal(1,"EOF leak"); end
            $display("SHELL session=%0d DDR upload, index2 inert, publications=%0d changes=%0d EOF",session,publications,changes);
        end
        $finish;
    end
    initial begin #50000000; $fatal(1,"shell timeout"); end
endmodule
