`timescale 1ns/1ps

module tb_megavgm_playlist_loop_status_export;
    localparam logic [2:0] STATE_IDLE    = 3'd0;
    localparam logic [2:0] STATE_LOADING = 3'd1;
    localparam logic [2:0] STATE_PLAYING = 3'd2;
    localparam logic [2:0] STATE_ENDED   = 3'd3;
    localparam logic [2:0] STATE_FATAL   = 3'd4;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [127:0] hps_status =
        128'h0123456789abcdef_fedcba9876543210;
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
    logic player_loop_valid = 1'b0;
    logic player_loop_boundary_pulse = 1'b0;

    wire [127:0] status_in;
    wire status_set;
    wire [31:0] exported_session_id;
    wire [2:0] exported_state;
    wire [7:0] exported_error_code;
    wire exported_loop_valid;
    wire [15:0] exported_loop_count;

    logic status_set_d = 1'b0;
    integer status_pulses = 0;

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
        .player_loop_valid(player_loop_valid),
        .player_loop_boundary_pulse(player_loop_boundary_pulse),
        .status_in(status_in),
        .status_set(status_set),
        .exported_session_id(exported_session_id),
        .exported_state(exported_state),
        .exported_error_code(exported_error_code),
        .exported_loop_valid(exported_loop_valid),
        .exported_loop_count(exported_loop_count)
    );

    always @(posedge clk) begin
        #1;
        if (status_set) begin
            if (status_set_d) begin
                $display("FAIL status_set was high on consecutive clocks");
                $fatal(1);
            end
            if (status_in[127:120] != 8'h4d ||
                status_in[119:116] != 4'd2 ||
                status_in[63:0] != 64'hfedcba9876543210) begin
                $display("FAIL v2 header or HPS merge record=%032h", status_in);
                $fatal(1);
            end
            status_pulses = status_pulses + 1;
        end
        status_set_d = status_set;
    end

    task automatic wait_record(
        input logic [31:0] expected_session,
        input logic [2:0] expected_state,
        input logic expected_loop_valid,
        input logic [15:0] expected_loop_count,
        input logic [7:0] expected_error,
        input string label
    );
        integer timeout;
        logic record_loop_valid;
        logic [15:0] record_loop_count;
        logic [7:0] record_error;
        begin : wait_loop
            timeout = 0;
            while (timeout < 40) begin
                @(posedge clk);
                #2;
                if (status_set &&
                    status_in[115:84] == expected_session &&
                    status_in[83:81] == expected_state) begin
                    if (expected_state == STATE_FATAL) begin
                        record_error = status_in[80:73];
                        record_loop_valid = 1'b0;
                        record_loop_count = 16'd0;
                        if (status_in[72:64] != 9'd0) begin
                            $display("FAIL %s fatal reserved=%h", label,
                                     status_in[72:64]);
                            $fatal(1);
                        end
                    end else begin
                        record_error = 8'd0;
                        record_loop_valid = status_in[80];
                        record_loop_count = status_in[79:64];
                    end
                    if (record_loop_valid != expected_loop_valid ||
                        record_loop_count != expected_loop_count ||
                        record_error != expected_error) begin
                        $display("FAIL %s loop_valid=%0b count=%0d error=%02h",
                                 label, record_loop_valid, record_loop_count,
                                 record_error);
                        $fatal(1);
                    end
                    disable wait_loop;
                end
                timeout = timeout + 1;
            end
            $display("FAIL timeout %s record=%032h", label, status_in);
            $fatal(1);
        end
    endtask

    task automatic pulse_loop_jump;
        begin
            @(negedge clk);
            player_loop_boundary_pulse = 1'b1;
            @(negedge clk);
            player_loop_boundary_pulse = 1'b0;
        end
    endtask

    integer i;
    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;
        wait_record(32'd0, STATE_IDLE, 1'b0, 16'd0, 8'd0,
                    "initial IDLE");

        // Native-loop session starts with clean metadata.
        @(negedge clk);
        playback_session_id = 32'd10;
        vgm_load_busy = 1'b1;
        wait_record(32'd10, STATE_LOADING, 1'b0, 16'd0, 8'd0,
                    "loop session LOADING reset");

        @(negedge clk);
        vgm_load_busy = 1'b0;
        player_busy = 1'b1;
        player_loop_valid = 1'b1;
        wait_record(32'd10, STATE_PLAYING, 1'b1, 16'd0, 8'd0,
                    "loop session PLAYING zero");

        pulse_loop_jump();
        wait_record(32'd10, STATE_PLAYING, 1'b1, 16'd1, 8'd0,
                    "first accepted native loop");
        pulse_loop_jump();
        wait_record(32'd10, STATE_PLAYING, 1'b1, 16'd2, 8'd0,
                    "second accepted native loop");

        // A new session wins over stale metadata and a simultaneous old pulse.
        @(negedge clk);
        player_busy = 1'b0;
        player_loop_boundary_pulse = 1'b1;
        playback_session_id = 32'd11;
        vgm_load_busy = 1'b1;
        wait_record(32'd11, STATE_LOADING, 1'b0, 16'd0, 8'd0,
                    "new session clears old loop data");
        @(negedge clk);
        player_loop_boundary_pulse = 1'b0;
        player_loop_valid = 1'b0;
        vgm_load_busy = 1'b0;
        player_busy = 1'b1;
        wait_record(32'd11, STATE_PLAYING, 1'b0, 16'd0, 8'd0,
                    "non-loop PLAYING");

        @(negedge clk);
        player_busy = 1'b0;
        player_done = 1'b1;
        done_session_id = 32'd11;
        wait_record(32'd11, STATE_ENDED, 1'b0, 16'd0, 8'd0,
                    "non-loop normal ENDED");

        // Start another loop session and prove 16-bit saturation.
        @(negedge clk);
        player_done = 1'b0;
        playback_session_id = 32'd12;
        vgm_load_busy = 1'b1;
        wait_record(32'd12, STATE_LOADING, 1'b0, 16'd0, 8'd0,
                    "saturation session reset");
        @(negedge clk);
        vgm_load_busy = 1'b0;
        player_busy = 1'b1;
        player_loop_valid = 1'b1;
        wait_record(32'd12, STATE_PLAYING, 1'b1, 16'd0, 8'd0,
                    "saturation session PLAYING");

        for (i = 0; i < 65535; i = i + 1)
            pulse_loop_jump();
        repeat (4) @(posedge clk);
        if (exported_loop_count != 16'hffff) begin
            $display("FAIL saturation reach count=%h", exported_loop_count);
            $fatal(1);
        end
        repeat (3) pulse_loop_jump();
        repeat (4) @(posedge clk);
        if (exported_loop_count != 16'hffff) begin
            $display("FAIL saturation hold count=%h", exported_loop_count);
            $fatal(1);
        end

        // FATAL uses the v2 payload for the full existing 8-bit error.
        @(negedge clk);
        player_busy = 1'b0;
        vgm_player_error = 1'b1;
        vgm_player_error_code = 8'h0d;
        error_session_id = 32'd12;
        wait_record(32'd12, STATE_FATAL, 1'b0, 16'd0, 8'h0d,
                    "FATAL payload union");

        $display("PASS tb_megavgm_playlist_loop_status_export pulses=%0d",
                 status_pulses);
        $finish;
    end
endmodule
