`timescale 1ns/1ps
module tb_contracts;
    logic clk=0;
    always #5 clk=~clk;
    logic reset=1, enable=0, mv=0;
    logic [77:0] md=0;
    wire req, ce, wr, busy, done, fatal, launched;
    wire [3:0] addr;
    wire [4:0] reg_addr;
    wire [7:0] reg_data;
    wire [63:0] cycle;
    sid_native_scheduler #(.RW(4)) scheduler(
        .clk(clk),.reset(reset),.enable(enable),.mem_req(req),.mem_addr(addr),
        .mem_valid(mv),.mem_data(md),.ce_sid(ce),.reg_write(wr),
        .reg_addr(reg_addr),.reg_data(reg_data),.busy(busy),.done(done),
        .fatal(fatal),.native_cycle(cycle),.launched(launched)
    );
    logic sr=1, rr=1, sce=0, sw=0;
    logic [4:0] sa=0;
    logic [7:0] sd=0;
    wire signed [17:0] sound, clean;
    wire sv, cv, ready;
    sid_session_wrapper dirty(.clk(clk),.reset(sr),.ce_sid(sce),.model(1'b0),
        .reg_addr(sa),.reg_data(sd),.reg_write(sw),.audio(sound),
        .sample_valid(sv),.audio_ready(ready),.pipeline_running());
    sid_session_wrapper fresh(.clk(clk),.reset(rr),.ce_sid(sce),.model(1'b0),
        .reg_addr(sa),.reg_data(sd),.reg_write(sw),.audio(clean),
        .sample_valid(cv),.audio_ready(),.pipeline_running());
    task tick;
        @(posedge clk); #1; @(negedge clk);
    endtask
    integer ce_after, publications, nonzero, phase;
    initial begin
        tick(); reset=0; enable=1;
        wait(req); tick(); md={1'b0,64'd0,5'd0,8'd1}; mv=1;
        tick(); mv=0;
        wait(launched); // Drop the next RAM response deliberately.
        repeat(24) tick();
        assert(fatal && !wr && !done) else $fatal(1,"underflow must be fatal, not catch-up");
        ce_after=0;
        repeat(200) begin if(ce) ce_after++; tick(); end
        assert(ce_after>=9) else $fatal(1,"underflow paused SID clock");
        $display("CONTRACT underflow fatal; CE continues: %0d pulses",ce_after);

        // Dirty every voice with noise/saw/pulse and resonant filter activity.
        sr=0; phase=0; nonzero=0;
        for(integer t=0;t<200000;t++) begin
            phase=phase+985248;
            sce=phase>=20000000;
            if(sce) phase=phase-20000000;
            sw=t<25*40 && t%40==0;
            sa=5'(t/40);
            case(sa)
                0,7,14: sd=8'h80;
                1,8,15: sd=8'h20;
                2,9,16: sd=8'hf0;
                3,10,17: sd=8'h08;
                4: sd=8'h21;
                11: sd=8'h81;
                18: sd=8'h41;
                5,12,19: sd=8'h00;
                6,13,20: sd=8'hf0;
                21: sd=8'h07;
                22: sd=8'h70;
                23: sd=8'hf7;
                24: sd=8'h7f;
                default: sd=0;
            endcase
            tick();
            if(sv && sound!=0) nonzero++;
        end
        assert(nonzero>100) else $fatal(1,"dirty history not exercised");
        // ONE reset edge, no CE required, no wait-N qualification.
        sw=0; sce=0; sr=1; rr=1; tick();
        assert(sound==0 && clean==0 && !sv && !ready) else $fatal(1,"reset leak");
        sr=0; rr=0; phase=0; publications=0;
        for(integer t=0;t<100000;t++) begin
            phase=phase+985248; sce=phase>=20000000;
            if(sce) phase=phase-20000000;
            tick();
            assert(sound==clean && sv==cv) else $fatal(1,"old-session pipeline history survived reset");
            assert(sound==0) else $fatal(1,"silent new session emitted stale audio");
            if(sv) publications++;
        end
        assert(publications>100) else $fatal(1,"permanent mute/publication missing");
        $display("CONTRACT dirty/reset/clean exact: dirty_nonzero=%0d clean_publications=%0d",nonzero,publications);
        $finish;
    end
    initial begin #10000000; $fatal(1,"timeout"); end
endmodule
