`timescale 1ns/1ps

module tb_stage_c_sound_adapter;
    localparam logic [63:0] FNV_OFFSET = 64'hcbf29ce484222325;
    localparam logic [63:0] EXPECT_FM_HASH = 64'h2a1aa6dc21860dfd;
    localparam logic [63:0] EXPECT_SSG_HASH = 64'h2d7fa36247dc0e75;
    localparam logic [63:0] EXPECT_MUTE_HASH = 64'h28c31cf8df2ec325;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic core_reset = 1'b1;
    logic publish_enable = 1'b1;
    logic [31:0] chip_clock = 32'd8_000_000;
    logic write_req = 1'b0;
    logic write_port = 1'b0;
    logic [7:0] write_address = 8'd0;
    logic [7:0] write_data = 8'd0;
    logic write_accept, write_busy, busy_timeout, write_while_busy;
    logic [31:0] accepted_write_count;
    logic signed [15:0] audio_l, audio_r, fm_l, fm_r;
    logic audio_sample_valid;
    logic [7:0] psg_a, psg_b, psg_c;
    logic [9:0] psg_snd;
    logic signed [15:0] adpcma_l, adpcma_r, adpcmb_l, adpcmb_r;
    logic adpcma_request, adpcmb_request;
    logic [19:0] adpcma_addr;
    logic [3:0] adpcma_bank;
    logic [23:0] adpcmb_addr;
    logic unexpected_pcm_request, unexpected_pcm_activity;
    logic core_ready, public_sample_rise, cen, clock_invalid;
    logic [31:0] cen_accumulator;

    integer xz_count = 0;
    integer xz_ready_count = 0;
    integer pcm_request_cycles = 0;
    integer pcm_nonzero_cycles = 0;
    integer cen_pulses;
    integer nonzero;
    integer transitions;
    integer lane_a_nonzero;
    integer lane_b_nonzero;
    integer lane_c_nonzero;
    integer sample_index;
    integer timeout;
    logic signed [15:0] previous_l;
    logic signed [15:0] previous_r;
    logic [63:0] fm_hash;
    logic [63:0] ssg_hash;
    logic [63:0] mute_hash;

    always #5 clk = ~clk;

    ym2610_golden_stage_c_sound_adapter #(
        .CLK_SYS_HZ(20_000_000),
        .BUSY_TIMEOUT_CYCLES(100_000)
    ) dut (.*);

    function automatic [63:0] hash_stereo(
        input logic [63:0] hash,
        input logic [15:0] left_sample,
        input logic [15:0] right_sample
    );
        integer byte_index;
        logic [31:0] sample_word;
        logic [63:0] next;
        begin
            sample_word = {right_sample, left_sample};
            next = hash;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                next = (next ^ sample_word[byte_index*8 +: 8]) *
                       64'h0000_0100_0000_01b3;
            hash_stereo = next;
        end
    endfunction

    always @(posedge clk) begin
        #1;
        if (!reset && !core_reset) begin
            if ((^{write_accept, write_busy, busy_timeout,
                    write_while_busy}) === 1'bx ||
                (^{audio_l, audio_r, audio_sample_valid,
                    fm_l, fm_r}) === 1'bx ||
                (^{psg_a, psg_b, psg_c, psg_snd}) === 1'bx ||
                (^{adpcma_l, adpcma_r, adpcmb_l,
                    adpcmb_r, adpcma_request, adpcmb_request,
                    core_ready, public_sample_rise, cen,
                    cen_accumulator, clock_invalid}) === 1'bx) begin
                xz_count = xz_count + 1;
                if (core_ready)
                    xz_ready_count = xz_ready_count + 1;
            end
            if (adpcma_request || adpcmb_request)
                pcm_request_cycles = pcm_request_cycles + 1;
            if (adpcma_l != 0 || adpcma_r != 0 ||
                adpcmb_l != 0 || adpcmb_r != 0)
                pcm_nonzero_cycles = pcm_nonzero_cycles + 1;
        end
    end

    task automatic reset_core;
        begin
            write_req = 1'b0;
            core_reset = 1'b1;
            repeat (32) @(posedge clk);
            core_reset = 1'b0;
            timeout = 0;
            while (!core_ready && timeout < 2_000_000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!core_ready)
                $fatal(1, "sound core warmup timeout");
            @(posedge clk);
        end
    endtask

    task automatic write_reg(
        input logic port,
        input logic [7:0] address,
        input logic [7:0] data
    );
        begin
            while (write_busy) @(posedge clk);
            write_port = port;
            write_address = address;
            write_data = data;
            write_req = 1'b1;
            timeout = 0;
            while (!write_accept && timeout < 500_000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!write_accept)
                $fatal(1, "sound write timeout port=%0d address=%02x", port, address);
            @(posedge clk);
            write_req = 1'b0;
            while (write_busy) @(posedge clk);
        end
    endtask

    task automatic configure_operator(
        input logic [7:0] offset,
        input logic [7:0] total_level
    );
        begin
            write_reg(1'b0, 8'h31 + offset, 8'h01);
            write_reg(1'b0, 8'h41 + offset, total_level);
            write_reg(1'b0, 8'h51 + offset, 8'h1f);
            write_reg(1'b0, 8'h61 + offset, 8'h00);
            write_reg(1'b0, 8'h71 + offset, 8'h00);
            write_reg(1'b0, 8'h81 + offset, 8'haf);
            write_reg(1'b0, 8'h91 + offset, 8'h00);
        end
    endtask

    task automatic keyoff_all_fm;
        begin
            write_reg(1'b0, 8'h28, 8'h01);
            write_reg(1'b0, 8'h28, 8'h02);
            write_reg(1'b0, 8'h28, 8'h05);
            write_reg(1'b0, 8'h28, 8'h06);
        end
    endtask

    task automatic capture(
        input integer count,
        output logic [63:0] hash,
        output integer nonzero_count,
        output integer transition_count,
        output integer a_nonzero,
        output integer b_nonzero,
        output integer c_nonzero
    );
        begin
            hash = FNV_OFFSET;
            nonzero_count = 0;
            transition_count = 0;
            a_nonzero = 0;
            b_nonzero = 0;
            c_nonzero = 0;
            previous_l = audio_l;
            previous_r = audio_r;
            for (sample_index = 0; sample_index < count; sample_index = sample_index + 1) begin
                @(posedge public_sample_rise);
                #1;
                hash = hash_stereo(hash, audio_l, audio_r);
                if (audio_l != 0 || audio_r != 0)
                    nonzero_count = nonzero_count + 1;
                if (audio_l != previous_l || audio_r != previous_r)
                    transition_count = transition_count + 1;
                if (psg_a != 0) a_nonzero = a_nonzero + 1;
                if (psg_b != 0) b_nonzero = b_nonzero + 1;
                if (psg_c != 0) c_nonzero = c_nonzero + 1;
                previous_l = audio_l;
                previous_r = audio_r;
            end
        end
    endtask

    task automatic capture_after_nonzero(
        input integer count,
        output logic [63:0] hash,
        output integer nonzero_count,
        output integer transition_count,
        output integer a_nonzero,
        output integer b_nonzero,
        output integer c_nonzero
    );
        integer guard;
        begin
            hash = FNV_OFFSET;
            nonzero_count = 0;
            transition_count = 0;
            a_nonzero = 0;
            b_nonzero = 0;
            c_nonzero = 0;
            guard = 0;
            do begin
                @(posedge public_sample_rise);
                #1;
                guard = guard + 1;
            end while (audio_l == 0 && audio_r == 0 && guard < 4096);
            if (audio_l == 0 && audio_r == 0)
                $fatal(1, "audio did not become nonzero");
            previous_l = audio_l;
            previous_r = audio_r;
            for (sample_index = 0; sample_index < count;
                 sample_index = sample_index + 1) begin
                if (sample_index != 0) begin
                    @(posedge public_sample_rise);
                    #1;
                end
                hash = hash_stereo(hash, audio_l, audio_r);
                if (audio_l != 0 || audio_r != 0)
                    nonzero_count = nonzero_count + 1;
                if (audio_l != previous_l || audio_r != previous_r)
                    transition_count = transition_count + 1;
                if (psg_a != 0) a_nonzero = a_nonzero + 1;
                if (psg_b != 0) b_nonzero = b_nonzero + 1;
                if (psg_c != 0) c_nonzero = c_nonzero + 1;
                previous_l = audio_l;
                previous_r = audio_r;
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        reset = 1'b0;

        // The 8 MHz/20 MHz fractional contract is exactly two enables per
        // five clk cycles, and reset must restart the same phase.
        core_reset = 1'b0;
        cen_pulses = 0;
        repeat (100) begin
            @(posedge clk);
            #1;
            if (cen) cen_pulses = cen_pulses + 1;
        end
        if (cen_pulses != 40)
            $fatal(1, "CEN ratio mismatch pulses=%0d", cen_pulses);

        reset_core();
        @(posedge public_sample_rise);
        repeat (24) @(posedge clk);
        write_reg(1'b0, 8'ha5, 8'h22);
        write_reg(1'b0, 8'ha1, 8'h00);
        write_reg(1'b0, 8'hb1, 8'h07);
        write_reg(1'b0, 8'hb5, 8'hc0);
        configure_operator(8'h00, 8'h00);
        configure_operator(8'h08, 8'h7f);
        configure_operator(8'h04, 8'h7f);
        configure_operator(8'h0c, 8'h7f);
        write_reg(1'b0, 8'h28, 8'hf1);
        capture_after_nonzero(512, fm_hash, nonzero, transitions,
                lane_a_nonzero, lane_b_nonzero, lane_c_nonzero);
        if (nonzero == 0 || transitions == 0)
            $fatal(1, "FM fixture silent nonzero=%0d transitions=%0d", nonzero, transitions);
        write_reg(1'b0, 8'h28, 8'h01);

        reset_core();
        @(posedge public_sample_rise);
        repeat (24) @(posedge clk);
        write_reg(1'b0, 8'h00, 8'h20);
        write_reg(1'b0, 8'h01, 8'h01);
        write_reg(1'b0, 8'h02, 8'h30);
        write_reg(1'b0, 8'h03, 8'h01);
        write_reg(1'b0, 8'h04, 8'h40);
        write_reg(1'b0, 8'h05, 8'h01);
        write_reg(1'b0, 8'h07, 8'h38);
        write_reg(1'b0, 8'h08, 8'h0f);
        write_reg(1'b0, 8'h09, 8'h0f);
        write_reg(1'b0, 8'h0a, 8'h0f);
        capture_after_nonzero(512, ssg_hash, nonzero, transitions,
                lane_a_nonzero, lane_b_nonzero, lane_c_nonzero);
        if (nonzero == 0 || transitions == 0 ||
            lane_a_nonzero == 0 || lane_b_nonzero == 0 ||
            lane_c_nonzero == 0)
            $fatal(1, "SSG fixture failure nonzero=%0d transitions=%0d lanes=%0d/%0d/%0d",
                   nonzero, transitions, lane_a_nonzero,
                   lane_b_nonzero, lane_c_nonzero);

        write_reg(1'b0, 8'h08, 8'h00);
        write_reg(1'b0, 8'h09, 8'h00);
        write_reg(1'b0, 8'h0a, 8'h00);
        capture(512, mute_hash, nonzero, transitions,
                lane_a_nonzero, lane_b_nonzero, lane_c_nonzero);
        if (nonzero != 0)
            $fatal(1, "SSG volume mute is not zero count=%0d", nonzero);

        if (busy_timeout || write_while_busy ||
            unexpected_pcm_request || unexpected_pcm_activity ||
            pcm_request_cycles != 0 || pcm_nonzero_cycles != 0 ||
            xz_ready_count != 0 || clock_invalid)
            $fatal(1, "sound contract failure timeout=%0d while_busy=%0d pcm=%0d/%0d cycles=%0d/%0d xz=%0d clock=%0d",
                   busy_timeout, write_while_busy,
                   unexpected_pcm_request, unexpected_pcm_activity,
                   pcm_request_cycles, pcm_nonzero_cycles, xz_ready_count,
                   clock_invalid);
        if (fm_hash != EXPECT_FM_HASH || ssg_hash != EXPECT_SSG_HASH ||
            mute_hash != EXPECT_MUTE_HASH)
            $fatal(1, "sound hash mismatch fm=%016x ssg=%016x mute=%016x",
                   fm_hash, ssg_hash, mute_hash);

        $display("STAGE_C_SOUND PASS fm_hash=%016x ssg_hash=%016x mute_hash=%016x writes=%0d cen=8000000/20000000 pcm_request=0 pcm_lane=0 xz=0",
                 fm_hash, ssg_hash, mute_hash, accepted_write_count);
        $finish;
    end
endmodule
