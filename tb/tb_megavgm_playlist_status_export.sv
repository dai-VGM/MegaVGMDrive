`timescale 1ns/1ps

module tb_megavgm_playlist_status_export;
    localparam logic [2:0] STATE_IDLE    = 3'd0;
    localparam logic [2:0] STATE_LOADING = 3'd1;
    localparam logic [2:0] STATE_PLAYING = 3'd2;
    localparam logic [2:0] STATE_ENDED   = 3'd3;
    localparam logic [2:0] STATE_FATAL   = 3'd4;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [127:0] hps_status = 128'd0;
    logic [31:0] playback_session_id = 32'd0;
    logic vgm_load_busy = 1'b0;
    logic player_busy = 1'b0;
    logic player_done = 1'b0;
    logic [31:0] done_session_id = 32'd0;
    logic vgm_load_error = 1'b0;
    logic vgm_load_overflow = 1'b0;
    logic vgm_player_error = 1'b0;
    logic [7:0] vgm_player_error_code = 8'd0;
    logic [31:0] error_session_id = 32'd0;

    wire [127:0] status_in;
    wire status_set;
    wire [31:0] exported_session_id;
    wire [2:0] exported_state;
    wire [7:0] exported_error_code;

    integer pulse_count = 0;
    logic previous_status_set = 1'b0;

    always #5 clk = ~clk;

    megavgm_playlist_status_export dut (
        .clk(clk),
        .reset(reset),
        .hps_status(hps_status),
        .playback_session_id(playback_session_id),
        .vgm_load_busy(vgm_load_busy),
        .player_busy(player_busy),
        .player_done(player_done),
        .done_session_id(done_session_id),
        .vgm_load_error(vgm_load_error),
        .vgm_load_overflow(vgm_load_overflow),
        .vgm_player_error(vgm_player_error),
        .vgm_player_error_code(vgm_player_error_code),
        .error_session_id(error_session_id),
        .status_in(status_in),
        .status_set(status_set),
        .exported_session_id(exported_session_id),
        .exported_state(exported_state),
        .exported_error_code(exported_error_code)
    );

    always @(posedge clk) begin
        #1;
        if (status_set) begin
            pulse_count = pulse_count + 1;
            if (previous_status_set) begin
                $display("FAIL status_set remained high for consecutive clocks");
                $fatal(1);
            end
            if (status_in[127:120] != 8'h4d ||
                status_in[119:112] != 8'd1) begin
                $display("FAIL bad interface header record=%016h",
                         status_in[127:64]);
                $fatal(1);
            end
        end
        previous_status_set = status_set;
    end

    task automatic wait_record(
        input logic [31:0] expected_session,
        input logic [2:0] expected_state,
        input logic [7:0] expected_error,
        input logic [63:0] expected_low,
        input string label
    );
        integer timeout;
        begin : wait_loop
            timeout = 0;
            while (timeout < 30) begin
                @(posedge clk);
                #2;
                if (status_set &&
                    status_in[111:80] == expected_session &&
                    status_in[79:77] == expected_state &&
                    status_in[76:69] == expected_error) begin
                    if (status_in[63:0] != expected_low) begin
                        $display("FAIL %s low status clobbered got=%016h expected=%016h",
                                 label, status_in[63:0], expected_low);
                        $fatal(1);
                    end
                    disable wait_loop;
                end
                timeout = timeout + 1;
            end
            $display("FAIL timeout %s session=%0d state=%0d error=%02h current=%016h",
                     label, expected_session, expected_state, expected_error,
                     status_in[127:64]);
            $fatal(1);
        end
    endtask

    task automatic assert_no_pulse(input integer cycles, input string label);
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge clk);
                #2;
                if (status_set) begin
                    $display("FAIL unexpected status_set %s", label);
                    $fatal(1);
                end
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;
        wait_record(32'd0, STATE_IDLE, 8'h00, 64'd0, "initial IDLE");

        // Test 1: a genuine non-looping session reaches ENDED.
        @(negedge clk);
        playback_session_id = 32'd1;
        vgm_load_busy = 1'b1;
        wait_record(32'd1, STATE_LOADING, 8'h00, 64'd0,
                    "session 1 LOADING");

        @(negedge clk);
        vgm_load_busy = 1'b0;
        player_busy = 1'b1;
        wait_record(32'd1, STATE_PLAYING, 8'h00, 64'd0,
                    "session 1 PLAYING");

        @(negedge clk);
        player_busy = 1'b0;
        player_done = 1'b1;
        done_session_id = 32'd1;
        wait_record(32'd1, STATE_ENDED, 8'h00, 64'd0,
                    "session 1 ENDED");

        // Test 2: a new session clears stale ENDED.
        @(negedge clk);
        player_done = 1'b0;
        playback_session_id = 32'd2;
        vgm_load_busy = 1'b1;
        wait_record(32'd2, STATE_LOADING, 8'h00, 64'd0,
                    "session 2 clears stale ENDED");

        @(negedge clk);
        vgm_load_busy = 1'b0;
        player_busy = 1'b1;
        wait_record(32'd2, STATE_PLAYING, 8'h00, 64'd0,
                    "session 2 PLAYING");

        // Test 3: replacement while PLAYING still emits the new LOADING.
        @(negedge clk);
        playback_session_id = 32'd3;
        vgm_load_busy = 1'b1;
        wait_record(32'd3, STATE_LOADING, 8'h00, 64'd0,
                    "load while playing LOADING");
        wait_record(32'd3, STATE_PLAYING, 8'h00, 64'd0,
                    "replacement PLAYING");

        // Test 4: current-session player fatal and changing error code.
        @(negedge clk);
        player_busy = 1'b0;
        vgm_load_busy = 1'b0;
        vgm_player_error_code = 8'h0d;
        error_session_id = 32'd3;
        vgm_player_error = 1'b1;
        wait_record(32'd3, STATE_FATAL, 8'h0d, 64'd0,
                    "player FATAL");

        @(negedge clk);
        vgm_player_error_code = 8'h2a;
        wait_record(32'd3, STATE_FATAL, 8'h2a, 64'd0,
                    "fatal code change");

        // A new load owns the new session even while stale error inputs from
        // session 3 remain asserted.
        @(negedge clk);
        playback_session_id = 32'd4;
        vgm_load_busy = 1'b1;
        wait_record(32'd4, STATE_LOADING, 8'h00, 64'd0,
                    "new session clears stale FATAL");

        // Test 5: changing ordinary OSD status alone emits no core update;
        // the next record transition merges every low bit unchanged.
        @(negedge clk);
        hps_status[63:0] = 64'ha5a5_0123_89ab_cdef;
        assert_no_pulse(3, "OSD-only change");

        @(negedge clk);
        vgm_player_error = 1'b0;
        error_session_id = 32'd0;
        vgm_load_busy = 1'b0;
        player_busy = 1'b1;
        wait_record(32'd4, STATE_PLAYING, 8'h00,
                    64'ha5a5_0123_89ab_cdef,
                    "OSD status preservation");

        // Exercise both loader synthetic error mappings.
        @(negedge clk);
        vgm_load_error = 1'b1;
        wait_record(32'd4, STATE_FATAL, 8'hf1,
                    64'ha5a5_0123_89ab_cdef, "load error");

        @(negedge clk);
        vgm_load_error = 1'b0;
        vgm_load_overflow = 1'b1;
        wait_record(32'd4, STATE_FATAL, 8'hf2,
                    64'ha5a5_0123_89ab_cdef, "load overflow");

        $display("PASS tb_megavgm_playlist_status_export pulses=%0d",
                 pulse_count);
        $finish;
    end
endmodule
