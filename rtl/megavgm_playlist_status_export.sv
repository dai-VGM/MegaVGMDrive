module megavgm_playlist_status_export (
    input  logic         clk,
    input  logic         reset,
    input  logic [127:0] hps_status,

    input  logic [31:0]  playback_session_id,
    input  logic         vgm_load_busy,
    input  logic         player_busy,
    input  logic         player_done,
    input  logic [31:0]  done_session_id,
    input  logic         vgm_load_error,
    input  logic         vgm_load_overflow,
    input  logic         vgm_player_error,
    input  logic [7:0]   vgm_player_error_code,
    input  logic [31:0]  error_session_id,
`ifdef MEGAVGMDRIVE_PLAYLIST_LOOP_PHASE1E
    input  logic         player_loop_valid,
    input  logic         player_loop_jump_pulse,
`endif

    output logic [127:0] status_in,
    output logic         status_set,
    output logic [31:0]  exported_session_id,
    output logic [2:0]   exported_state,
    output logic [7:0]   exported_error_code
`ifdef MEGAVGMDRIVE_PLAYLIST_LOOP_PHASE1E
    , output logic        exported_loop_valid
    , output logic [15:0] exported_loop_count
`endif
);
    localparam logic [7:0] INTERFACE_MAGIC   = 8'h4d;
    localparam logic [7:0] INTERFACE_VERSION = 8'd1;

    localparam logic [2:0] STATE_IDLE    = 3'd0;
    localparam logic [2:0] STATE_LOADING = 3'd1;
    localparam logic [2:0] STATE_PLAYING = 3'd2;
    localparam logic [2:0] STATE_ENDED   = 3'd3;
    localparam logic [2:0] STATE_FATAL   = 3'd4;

    localparam logic [7:0] LOAD_ERROR_CODE     = 8'hf1;
    localparam logic [7:0] LOAD_OVERFLOW_CODE  = 8'hf2;

    logic [63:0] published_record = 64'd0;
    logic        published_valid = 1'b0;

    wire current_done =
        player_done &&
        (done_session_id == playback_session_id);
    wire current_player_error =
        vgm_player_error &&
        (error_session_id == playback_session_id);
    wire [7:0] current_fatal_code =
        vgm_load_overflow ? LOAD_OVERFLOW_CODE :
        vgm_load_error ? LOAD_ERROR_CODE :
        vgm_player_error_code;

`ifdef MEGAVGMDRIVE_PLAYLIST_LOOP_PHASE1E
    localparam logic [3:0] INTERFACE_V2_VERSION = 4'd2;

    // Phase 1E v2 owns only status[127:64]:
    // [127:120] existing magic 0x4d, [119:116] version 2
    // [115:84]  full playback session, [83:81] playback state
    // [80:64]   state-dependent payload. Keeping FATAL error and normal
    // loop telemetry in a union is what lets the record retain the complete
    // 32-bit session without touching HPS-owned status[63:0].
    // FATAL payload:     [80:73] error[7:0], [72:64] reserved
    // non-FATAL payload: [80] loop_valid, [79:64] loop_count[15:0]
    wire [16:0] v2_payload =
        (exported_state == STATE_FATAL) ?
            {exported_error_code, 9'd0} :
            {exported_loop_valid, exported_loop_count};
    wire [63:0] live_record = {
        INTERFACE_MAGIC,
        INTERFACE_V2_VERSION,
        exported_session_id,
        exported_state,
        v2_payload
    };
`else
    wire [63:0] live_record = {
        INTERFACE_MAGIC,
        INTERFACE_VERSION,
        exported_session_id,
        exported_state,
        exported_error_code,
        5'd0
    };
`endif

    // hps_io captures status_in on the rising edge of status_set. Keep a
    // complete low cycle between notifications so its edge detector can
    // observe every meaningful record transition.
    always_ff @(posedge clk) begin
        if (reset) begin
            status_set <= 1'b0;
            published_record <= 64'd0;
            published_valid <= 1'b0;
        end else begin
            status_set <= 1'b0;
            if (!status_set &&
                (!published_valid || (live_record != published_record))) begin
                published_record <= live_record;
                published_valid <= 1'b1;
                status_set <= 1'b1;
            end
        end
    end

    // Bits 63:0 remain owned by Main/OSD. The Phase 1B lab owns only the
    // audited-unused upper half of the 128-bit MiSTer status vector.
    assign status_in = {published_record, hps_status[63:0]};

`ifdef MEGAVGMDRIVE_PLAYLIST_LOOP_PHASE1E
    // The authoritative session transition wins over an old player's final
    // loop pulse and metadata. The parser pulse is asserted only on the same
    // accepted 0x66 transition that redirects PC to loop_pc.
    always_ff @(posedge clk) begin
        if (reset) begin
            exported_loop_valid <= 1'b0;
            exported_loop_count <= 16'd0;
        end else if (playback_session_id != exported_session_id) begin
            exported_loop_valid <= 1'b0;
            exported_loop_count <= 16'd0;
        end else begin
            exported_loop_valid <= player_loop_valid;
            if (player_loop_jump_pulse && player_loop_valid &&
                !vgm_load_busy && !vgm_load_error && !vgm_load_overflow &&
                !current_player_error && (exported_state != STATE_FATAL) &&
                (exported_loop_count != 16'hffff)) begin
                exported_loop_count <= exported_loop_count + 16'd1;
            end
        end
    end
`endif

    // The existing mode-5 session counter is the sole session authority.
    // A session change is observed one clock after the loader increments it,
    // preventing a transient LOADING record carrying the previous session.
    always_ff @(posedge clk) begin
        if (reset) begin
            exported_session_id <= 32'd0;
            exported_state <= STATE_IDLE;
            exported_error_code <= 8'd0;
        end else if (playback_session_id != exported_session_id) begin
            exported_session_id <= playback_session_id;
            exported_state <= STATE_LOADING;
            exported_error_code <= 8'd0;
        end else if (vgm_load_error || vgm_load_overflow) begin
            exported_state <= STATE_FATAL;
            exported_error_code <= current_fatal_code;
        end else if (current_player_error) begin
            exported_state <= STATE_FATAL;
            exported_error_code <= current_fatal_code;
        end else begin
            unique case (exported_state)
                STATE_IDLE: begin
                    // This fallback covers a loader already active as reset
                    // releases; normal loads enter via the session change.
                    if (vgm_load_busy && (playback_session_id != 32'd0))
                        exported_state <= STATE_LOADING;
                end

                STATE_LOADING: begin
                    if (player_busy)
                        exported_state <= STATE_PLAYING;
                end

                STATE_PLAYING: begin
                    if (current_done)
                        exported_state <= STATE_ENDED;
                end

                STATE_FATAL: begin
                    if (current_player_error)
                        exported_error_code <= current_fatal_code;
                end

                default: begin
                    // ENDED and valid unknown-free states remain latched until
                    // the authoritative session ID changes.
                end
            endcase
        end
    end
endmodule
