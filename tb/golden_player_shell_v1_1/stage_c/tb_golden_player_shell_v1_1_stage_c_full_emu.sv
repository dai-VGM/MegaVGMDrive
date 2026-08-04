`timescale 1ns/1ps

module tb_golden_player_shell_v1_1_stage_c_full_emu;
    localparam int MAX_FILE = 1 << 20;
    localparam logic [28:0] DDR_BASE = {4'b0011, 25'd0};
    localparam logic [63:0] FNV_OFFSET = 64'hcbf29ce484222325;

    logic clk = 1'b0;
    logic reset = 1'b1;
    always #25 clk = ~clk;

    tri [48:0] hps_bus;
    wire [15:0] audio_l, audio_r;
    wire audio_s;
    wire [1:0] audio_mix;
    logic ddram_busy = 1'b0;
    wire [7:0] ddram_burstcnt;
    wire [28:0] ddram_addr;
    logic [63:0] ddram_dout = 64'd0;
    logic ddram_dout_ready = 1'b0;
    wire ddram_rd;
    wire [63:0] ddram_din;
    wire [7:0] ddram_be;
    wire ddram_we;

    logic [7:0] ddr_memory [0:MAX_FILE-1];
    logic read_pending = 1'b0;
    logic [28:0] read_word_address = 29'd0;
    integer read_delay = 0;
    integer word_byte;
    integer lane;
    integer writes = 0;
    integer reads = 0;
    integer gate_rises = 0;
    integer final_nonzero = 0;
    integer xz_count = 0;
    integer pcm_count = 0;
    integer pre_gate_nonzero = 0;
    integer pre_fm_nonzero = 0;
    integer timeout;
    logic gate_d = 1'b0;
    logic sample_valid_d = 1'b0;
    logic first_fm_seen = 1'b0;
    logic first_adpcmb_seen = 1'b0;
    logic first_adpcma_seen = 1'b0;
    logic hash_started = 1'b0;
    integer hash_samples = 0;
    logic [63:0] final_hash = FNV_OFFSET;
    integer olga_mode;
    integer ssg_mode;
    integer suppressed_mode;

    emu dut (
        .CLK_50M(clk), .RESET(reset), .HPS_BUS(hps_bus),
        .HDMI_WIDTH(12'd0), .HDMI_HEIGHT(12'd0),
`ifdef MISTER_FB
        .FB_VBL(1'b0), .FB_LL(1'b0),
`endif
        .CLK_AUDIO(clk), .AUDIO_L(audio_l), .AUDIO_R(audio_r),
        .AUDIO_S(audio_s), .AUDIO_MIX(audio_mix),
        .SD_MISO(1'b0), .SD_CD(1'b0),
        .DDRAM_BUSY(ddram_busy), .DDRAM_BURSTCNT(ddram_burstcnt),
        .DDRAM_ADDR(ddram_addr), .DDRAM_DOUT(ddram_dout),
        .DDRAM_DOUT_READY(ddram_dout_ready), .DDRAM_RD(ddram_rd),
        .DDRAM_DIN(ddram_din), .DDRAM_BE(ddram_be), .DDRAM_WE(ddram_we),
        .UART_CTS(1'b0), .UART_RXD(1'b0), .UART_DSR(1'b0),
        .USER_IN(7'd0), .OSD_STATUS(1'b0)
    );

    function automatic [63:0] hash_stereo(
        input logic [63:0] hash,
        input logic [15:0] left_sample,
        input logic [15:0] right_sample
    );
        integer byte_index;
        logic [31:0] sample_word;
        logic [63:0] next_hash;
        begin
            sample_word = {right_sample, left_sample};
            next_hash = hash;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                next_hash = (next_hash ^ sample_word[byte_index*8 +: 8]) *
                    64'h0000_0100_0000_01b3;
            hash_stereo = next_hash;
        end
    endfunction

    always_ff @(posedge clk) begin
        ddram_dout_ready <= 1'b0;
        if (ddram_we && !ddram_busy) begin
            word_byte = (ddram_addr - DDR_BASE) * 8;
            if (word_byte < 0 || word_byte + 7 >= MAX_FILE)
                $fatal(1, "DDRAM write outside model %08x", ddram_addr);
            for (lane = 0; lane < 8; lane = lane + 1)
                if (ddram_be[lane])
                    ddr_memory[word_byte + lane] <=
                        ddram_din[lane*8 +: 8];
            writes <= writes + 1;
        end
        if (ddram_rd && !ddram_busy) begin
            if (read_pending)
                $fatal(1, "DDRAM model received a second read");
            read_pending <= 1'b1;
            read_word_address <= ddram_addr;
            read_delay <= ddram_addr[1:0] + 1;
            reads <= reads + 1;
        end
        if (read_pending) begin
            if (read_delay == 0) begin
                word_byte = (read_word_address - DDR_BASE) * 8;
                if (word_byte < 0 || word_byte + 7 >= MAX_FILE)
                    $fatal(1, "DDRAM read outside model %08x",
                           read_word_address);
                for (lane = 0; lane < 8; lane = lane + 1)
                    ddram_dout[lane*8 +: 8] <=
                        ddr_memory[word_byte + lane];
                ddram_dout_ready <= 1'b1;
                read_pending <= 1'b0;
            end else begin
                read_delay <= read_delay - 1;
            end
        end
    end

    always @(posedge clk) begin
        #1;
        if (!reset) begin
            if (dut.md_sound.profile_file_read_valid &&
                dut.md_sound.profile_file_read_address == 0 &&
                dut.md_sound.profile_file_read_data != 8'h56)
                $fatal(1, "physical reader returned bad magic byte %02x",
                       dut.md_sound.profile_file_read_data);
            if (!gate_d && dut.audio_gate_open)
                gate_rises = gate_rises + 1;
            gate_d = dut.audio_gate_open;

            if (!dut.audio_gate_open &&
                (audio_l != 0 || audio_r != 0 || dut.audio_sample_valid))
                pre_gate_nonzero = pre_gate_nonzero + 1;
            if (olga_mode && dut.audio_gate_open && !first_fm_seen &&
                (audio_l != 0 || audio_r != 0))
                pre_fm_nonzero = pre_fm_nonzero + 1;
            if (dut.audio_gate_open && dut.audio_sample_valid &&
                (audio_l != 0 || audio_r != 0))
                final_nonzero = final_nonzero + 1;

            if (dut.md_sound.v1_1_profile.stage_c_core.parser_trace_valid &&
                !dut.md_sound.v1_1_profile.stage_c_core.parser_trace_forwarded &&
                dut.md_sound.v1_1_profile.stage_c_core.parser_trace_semantic == 4'd4 &&
                dut.md_sound.v1_1_profile.stage_c_core.parser_trace_port == 1'b0 &&
                dut.md_sound.v1_1_profile.stage_c_core.parser_trace_address == 8'h10 &&
                dut.md_sound.v1_1_profile.stage_c_core.parser_trace_data[7] &&
                !first_adpcmb_seen) begin
                first_adpcmb_seen = 1'b1;
                if (olga_mode &&
                    dut.md_sound.v1_1_profile.stage_c_core.parser_trace_sample !=
                        32'd4625)
                    $fatal(1, "Olga first ADPCM-B timestamp mismatch %0d",
                        dut.md_sound.v1_1_profile.stage_c_core.parser_trace_sample);
            end
            if (dut.md_sound.v1_1_profile.stage_c_core.parser_trace_valid &&
                dut.md_sound.v1_1_profile.stage_c_core.parser_trace_forwarded &&
                dut.md_sound.v1_1_profile.stage_c_core.parser_trace_port == 1'b0 &&
                dut.md_sound.v1_1_profile.stage_c_core.parser_trace_address == 8'h28 &&
                dut.md_sound.v1_1_profile.stage_c_core.parser_trace_data == 8'hf1 &&
                !first_fm_seen) begin
                first_fm_seen = 1'b1;
                if (olga_mode &&
                    dut.md_sound.v1_1_profile.stage_c_core.parser_trace_sample !=
                    32'd120851)
                    $fatal(1, "Olga first FM timestamp mismatch %0d",
                        dut.md_sound.v1_1_profile.stage_c_core.parser_trace_sample);
            end
            if (dut.md_sound.v1_1_profile.stage_c_core.parser_trace_valid &&
                !dut.md_sound.v1_1_profile.stage_c_core.parser_trace_forwarded &&
                dut.md_sound.v1_1_profile.stage_c_core.parser_trace_semantic == 4'd3 &&
                dut.md_sound.v1_1_profile.stage_c_core.parser_trace_port == 1'b1 &&
                dut.md_sound.v1_1_profile.stage_c_core.parser_trace_address == 8'h00 &&
                !dut.md_sound.v1_1_profile.stage_c_core.parser_trace_data[7] &&
                dut.md_sound.v1_1_profile.stage_c_core.parser_trace_data[5:0] != 0 &&
                !first_adpcma_seen) begin
                first_adpcma_seen = 1'b1;
                if (olga_mode &&
                    dut.md_sound.v1_1_profile.stage_c_core.parser_trace_sample !=
                    32'd121270)
                    $fatal(1, "Olga first ADPCM-A timestamp mismatch %0d",
                        dut.md_sound.v1_1_profile.stage_c_core.parser_trace_sample);
            end

            if (!sample_valid_d && dut.audio_sample_valid && first_fm_seen &&
                hash_samples < 512 &&
                (hash_started || audio_l != 0 || audio_r != 0)) begin
                hash_started = 1'b1;
                final_hash = hash_stereo(final_hash, audio_l, audio_r);
                hash_samples = hash_samples + 1;
            end
            sample_valid_d = dut.audio_sample_valid;

            if (dut.md_sound.profile_pcm_a_read_request ||
                dut.md_sound.profile_pcm_b_read_request ||
                (dut.md_sound.v1_1_profile.stage_c_core.sound_core_ready &&
                 (dut.md_sound.v1_1_profile.stage_c_core.sound_adpcma_request ||
                  dut.md_sound.v1_1_profile.stage_c_core.sound_adpcmb_request ||
                  dut.md_sound.v1_1_profile.stage_c_core.sound_adpcma_l != 0 ||
                  dut.md_sound.v1_1_profile.stage_c_core.sound_adpcma_r != 0 ||
                  dut.md_sound.v1_1_profile.stage_c_core.sound_adpcmb_l != 0 ||
                  dut.md_sound.v1_1_profile.stage_c_core.sound_adpcmb_r != 0)))
                pcm_count = pcm_count + 1;

            if (dut.audio_gate_open) begin
                if (dut.audio_muted ||
                    dut.md_sound.profile_audio_enable !== dut.audio_gate_open ||
                    dut.md_sound.profile_audio_l !== dut.md_audio_l ||
                    dut.md_sound.profile_audio_r !== dut.md_audio_r ||
                    dut.md_audio_l !== $signed(audio_l) ||
                    dut.md_audio_r !== $signed(audio_r) ||
                    dut.md_sound.profile_audio_sample_valid !==
                        dut.audio_sample_valid)
                    $fatal(1, "full audio path signed/sample-valid mismatch");
            end else if (!dut.audio_muted) begin
                $fatal(1, "gate/mute polarity mismatch");
            end

            if ((^{audio_l, audio_r, dut.audio_sample_valid,
                    dut.audio_gate_open, dut.audio_muted,
                    dut.md_sound.profile_audio_enable,
                    dut.md_sound.profile_audio_l,
                    dut.md_sound.profile_audio_r,
                    dut.md_sound.profile_audio_sample_valid,
                    dut.md_sound.profile_status,
                    dut.VGM_PLAYER_STATE}) === 1'bx)
                xz_count = xz_count + 1;
        end
    end

    initial begin
        olga_mode = $test$plusargs("OLGA");
        ssg_mode = $test$plusargs("SSG");
        suppressed_mode = $test$plusargs("SUPPRESSED");
        repeat (8) @(posedge clk);
        reset = 1'b0;

        timeout = 0;
        while (!dut.vgm_load_done && timeout < 25_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!dut.vgm_load_done || dut.vgm_load_error ||
            dut.vgm_load_overflow)
            $fatal(1, "physical upload did not complete");
        if (ddr_memory[0] != 8'h56 || ddr_memory[1] != 8'h67 ||
            ddr_memory[2] != 8'h6d || ddr_memory[3] != 8'h20)
            $fatal(1, "physical DDR magic mismatch %02x%02x%02x%02x",
                   ddr_memory[0], ddr_memory[1], ddr_memory[2],
                   ddr_memory[3]);
        $display("V1_1_STAGE_C_FULL_EMU_PROGRESS upload_done writes=%0d magic=%08x",
                 writes, dut.md_sound.upload_magic); $fflush();

        timeout = 0;
        while (!dut.audio_gate_open &&
               dut.md_sound.v1_1_profile.stage_c_core.lifecycle_state != 5'd12 &&
               dut.md_sound.v1_1_profile.stage_c_core.lifecycle_state != 5'd14 &&
               timeout < 25_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        repeat (2) @(posedge clk);
        #1;
        if (!dut.audio_gate_open || dut.audio_muted || gate_rises != 1 ||
            dut.md_sound.v1_1_profile.stage_c_core.parser_start_count != 1 ||
            dut.md_sound.v1_1_profile.stage_c_core.scanner_start_count != 1)
            $fatal(1, "full emu playback arm failed gate=%0d mute=%0d rises=%0d starts=%0d/%0d state=%0d class=%0d reject=%02x bad_pc=%08x bad=%02x/%02x",
                   dut.audio_gate_open, dut.audio_muted, gate_rises,
                   dut.md_sound.v1_1_profile.stage_c_core.scanner_start_count,
                   dut.md_sound.v1_1_profile.stage_c_core.parser_start_count,
                   dut.md_sound.v1_1_profile.stage_c_core.lifecycle_state,
                   dut.md_sound.v1_1_profile.stage_c_core.scan_classification,
                   dut.md_sound.v1_1_profile.stage_c_core.profile_reject_code,
                   dut.md_sound.v1_1_profile.stage_c_core.scan_first_bad_pc,
                   dut.md_sound.v1_1_profile.stage_c_core.scan_first_bad_address,
                   dut.md_sound.v1_1_profile.stage_c_core.scan_first_bad_data);
        if (olga_mode &&
            (!dut.title_valid || dut.title_directory_length != 18 ||
             dut.title_basename_length != 14))
            $fatal(1, "Olga title surface mismatch");
        $display("V1_1_STAGE_C_FULL_EMU_PROGRESS gate_open"); $fflush();

        if (olga_mode) begin
            timeout = 0;
            while ((!first_adpcma_seen || final_nonzero == 0) &&
                   timeout < 70_000_000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 70_000_000 || !first_adpcmb_seen ||
                !first_fm_seen || !first_adpcma_seen || final_nonzero == 0 ||
                pre_fm_nonzero != 0)
                $fatal(1, "Olga full-audio boundary failure B/FM/A=%0d/%0d/%0d nonzero=%0d pre=%0d",
                       first_adpcmb_seen, first_fm_seen, first_adpcma_seen,
                       final_nonzero, pre_fm_nonzero);
            if (dut.md_sound.v1_1_profile.stage_c_core.scan_command_count !=
                    171869 ||
                dut.md_sound.v1_1_profile.stage_c_core.scan_total_writes !=
                    81272 ||
                dut.md_sound.v1_1_profile.stage_c_core.scan_trace_hash !=
                    64'h7c3088bd1d4eea6f)
                $fatal(1, "Olga scan reference mismatch");
        end else begin
            timeout = 0;
            while (dut.md_sound.v1_1_profile.stage_c_core.lifecycle_state !=
                       5'd13 && timeout < 2_000_000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            repeat (2) @(posedge clk);
            if (timeout >= 2_000_000 || dut.audio_gate_open ||
                audio_l != 0 || audio_r != 0 ||
                dut.audio_sample_valid || final_nonzero == 0)
                $fatal(1, "synthetic final/end contract failed");
            if (!ssg_mode && !suppressed_mode &&
                (hash_samples != 512 ||
                 final_hash != 64'h2a1aa6dc21860dfd))
                $fatal(1, "full emu FM hash mismatch samples=%0d hash=%016x",
                       hash_samples, final_hash);
            if (ssg_mode &&
                (dut.md_sound.v1_1_profile.stage_c_core.
                    parser_forwarded_ssg_count != 13 ||
                 dut.md_sound.v1_1_profile.stage_c_core.
                    parser_forwarded_fm_count != 0))
                $fatal(1, "full emu SSG accounting mismatch");
            if (suppressed_mode &&
                (dut.md_sound.v1_1_profile.stage_c_core.
                    parser_suppressed_a_count != 4 ||
                 dut.md_sound.v1_1_profile.stage_c_core.
                    parser_suppressed_b_count != 5 ||
                 dut.md_sound.v1_1_profile.stage_c_core.
                    parser_forwarded_fm_count != 34))
                $fatal(1, "full emu suppressed accounting mismatch");
        end

        if (pre_gate_nonzero != 0 || pcm_count != 0 || xz_count != 0 ||
            gate_rises != 1 || reads == 0)
            $fatal(1, "full emu global contract failure pre=%0d pcm=%0d xz=%0d gate=%0d reads=%0d",
                   pre_gate_nonzero, pcm_count, xz_count, gate_rises, reads);
        $display("V1_1_STAGE_C_FULL_EMU_RESULT PASS olga=%0d ssg=%0d suppressed=%0d gate_rises=1 final_nonzero=%0d hash_samples=%0d hash=%016x pcm=0 xz=0 reads=%0d",
                 olga_mode, ssg_mode, suppressed_mode, final_nonzero,
                 hash_samples, final_hash, reads);
        $finish;
    end
endmodule
