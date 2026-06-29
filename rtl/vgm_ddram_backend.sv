// Minimal DDRAM backend for mode5 VGM loading/playback.
//
// The write side packs sequential ioctl bytes into 64-bit DDRAM words before
// enqueueing writes. The read side keeps the byte-read behavior expected by
// vgm_loaded_player.

module vgm_ddram_backend #(
    parameter int ADDR_WIDTH        = 18,
    parameter bit ACCEPT_ANY_INDEX  = 1'b0,
    parameter logic [7:0] FILE_INDEX = 8'd0,
    parameter int DDRAM_ADDR_WIDTH  = 29,
    parameter logic [28:0] DDRAM_BASE_ADDR = 29'd0,
    parameter logic [28:0] SEGAPCM_ROM_BASE_ADDR = 29'd0,
    parameter int WRITE_FIFO_DEPTH  = 64,
    parameter int READ_TIMEOUT_CYCLES = 1024
) (
    input  logic                     clk,
    input  logic                     reset,

    input  logic                     ioctl_download,
    input  logic                     ioctl_wr,
    input  logic [31:0]              ioctl_addr,
    input  logic [7:0]               ioctl_dout,
    input  logic [7:0]               ioctl_index,
    output logic                     ioctl_wait,

    input  logic                     mem_rd_req,
    input  logic [ADDR_WIDTH-1:0]    mem_rd_addr,
    output logic                     mem_rd_ready,
    output logic                     mem_rd_valid,
    output logic [7:0]               mem_rd_data,

    input  logic                     segapcm_copy_wr_req,
    output logic                     segapcm_copy_wr_ready,
    input  logic [18:0]              segapcm_copy_wr_addr,
    input  logic [7:0]               segapcm_copy_wr_data,
    input  logic                     segapcm_copy_flush_req,
    output logic                     segapcm_copy_flush_done,
    output logic [15:0]              segapcm_copy_accept_count_debug,
    output logic [15:0]              segapcm_copy_write_count_debug,
    output logic [15:0]              segapcm_copy_fifo_debug,
    output logic [15:0]              segapcm_copy_ready_debug,
    output logic [15:0]              segapcm_copy_write_req_debug,
    output logic [15:0]              segapcm_copy_word_debug,
    output logic [15:0]              segapcm_copy_flush_debug,
    output logic [15:0]              segapcm_copy_full_detect_count_debug,
    output logic [15:0]              segapcm_copy_push_req_count_debug,
    output logic [15:0]              segapcm_copy_push_fire_count_debug,
    output logic [15:0]              segapcm_copy_fifo_push_count_debug,
    output logic [15:0]              segapcm_copy_pack_ready_debug,
    output logic [15:0]              segapcm_copy_post_push_debug,
    output logic [15:0]              segapcm_read_gate_debug,
    output logic [15:0]              segapcm_read_after_copy_count_debug,
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    input  logic                     smoke_ddr_payload_tap_valid,
    input  logic [18:0]              smoke_ddr_payload_tap_addr,
    input  logic [7:0]               smoke_ddr_payload_tap_data,
    input  logic [18:0]              smoke_ddr_capture_limit,
    input  logic                     smoke_ddr_rd_req,
    output logic                     smoke_ddr_rd_ready,
    input  logic [18:0]              smoke_ddr_rd_addr,
    output logic                     smoke_ddr_rd_valid,
    output logic [7:0]               smoke_ddr_rd_data,
    output logic                     smoke_ddr_payload_present,
    output logic [18:0]              smoke_ddr_payload_length,
    output logic [15:0]              smoke_ddr_write_req_count_debug,
    output logic [15:0]              smoke_ddr_write_count_debug,
    output logic [15:0]              smoke_ddr_write_blocked_count_debug,
    output logic [15:0]              smoke_ddr_write_status_debug,
    output logic [15:0]              smoke_ddr_header_skip_count_debug,
    output logic [15:0]              smoke_ddr_last_write_index_debug,
    output logic [15:0]              smoke_ddr_last_write_addr_debug,
    output logic [15:0]              smoke_ddr_last_write_lane_debug,
    output logic [7:0]               smoke_ddr_last_write_data_debug,
    output logic [15:0]              smoke_ddr_read_count_debug,
    output logic [15:0]              smoke_ddr_last_read_index_debug,
    output logic [15:0]              smoke_ddr_last_read_addr_debug,
    output logic [15:0]              smoke_ddr_last_read_lane_debug,
    output logic [15:0]              smoke_ddr_last_read_word0_debug,
    output logic [15:0]              smoke_ddr_last_read_word1_debug,
    output logic [7:0]               smoke_ddr_last_read_data_debug,
    output logic [15:0]              smoke_ddr_base_addr_debug,
`endif

    output logic                     load_busy,
    output logic                     load_done,
    output logic                     load_done_pulse,
    output logic                     play_ready_pulse,
    output logic                     load_error,
    output logic                     overflow_error,
    output logic [31:0]              file_size,
    output logic [31:0]              magic_debug,

    input  logic                     ddram_busy,
    output logic [7:0]               ddram_burstcnt,
    output logic [DDRAM_ADDR_WIDTH-1:0] ddram_addr,
    input  logic [63:0]              ddram_dout,
    input  logic                     ddram_dout_ready,
    output logic                     ddram_rd,
    output logic [63:0]              ddram_din,
    output logic [7:0]               ddram_be,
    output logic                     ddram_we
);

    localparam int FIFO_AW = (WRITE_FIFO_DEPTH <= 2) ? 1 : $clog2(WRITE_FIFO_DEPTH);
    localparam logic [FIFO_AW:0] FIFO_DEPTH_COUNT = WRITE_FIFO_DEPTH[FIFO_AW:0];
    localparam int BYTE_ADDR_WIDTH = DDRAM_ADDR_WIDTH + 3;
    localparam int RD_TIMEOUT_AW = (READ_TIMEOUT_CYCLES <= 2) ? 1 : $clog2(READ_TIMEOUT_CYCLES);
    localparam logic [RD_TIMEOUT_AW-1:0] RD_TIMEOUT_LAST = READ_TIMEOUT_CYCLES - 1;

    typedef enum logic [0:0] {
        RD_IDLE = 1'b0,
        RD_WAIT = 1'b1
    } rd_state_t;
    typedef enum logic [0:0] {
        RD_OWNER_FILE = 1'b0,
        RD_OWNER_SMOKE_DDR = 1'b1
    } rd_owner_t;

    logic ioctl_download_q;
    logic download_active;
    logic finish_pending;
    logic write_pending;

    logic [DDRAM_ADDR_WIDTH-1:0] fifo_addr [0:WRITE_FIFO_DEPTH-1];
    logic [63:0]                 fifo_din  [0:WRITE_FIFO_DEPTH-1];
    logic [7:0]                  fifo_be   [0:WRITE_FIFO_DEPTH-1];
    logic [FIFO_AW-1:0]          fifo_wr_ptr;
    logic [FIFO_AW-1:0]          fifo_rd_ptr;
    logic [FIFO_AW:0]            fifo_count;

    logic                        pack_valid;
    logic [DDRAM_ADDR_WIDTH-1:0] pack_addr;
    logic [63:0]                 pack_word;
    logic [7:0]                  pack_be;
    logic                        copy_pack_valid;
    logic [DDRAM_ADDR_WIDTH-1:0] copy_pack_addr;
    logic [63:0]                 copy_pack_word;
    logic [7:0]                  copy_pack_be;
    logic                        copy_flush_pending;
    logic [15:0]                 copy_full_detect_count;
    logic [15:0]                 copy_push_req_count;
    logic [15:0]                 copy_push_fire_count;
    logic [15:0]                 copy_fifo_push_count;
    logic [15:0]                 read_after_copy_count;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    logic                        smoke_ddr_pack_valid;
    logic [DDRAM_ADDR_WIDTH-1:0] smoke_ddr_pack_addr;
    logic [63:0]                 smoke_ddr_pack_word;
    logic [7:0]                  smoke_ddr_pack_be;
`endif

    logic [2:0]                  read_lane;
    rd_owner_t                   read_owner;
    logic [RD_TIMEOUT_AW-1:0]    rd_wait_count;
    rd_state_t                   rd_state;

    wire file_accept = ACCEPT_ANY_INDEX || (ioctl_index == FILE_INDEX);
    wire download_start = ioctl_download && !ioctl_download_q;
    wire download_end   = !ioctl_download && ioctl_download_q;

    wire fifo_empty = (fifo_count == '0);
    wire fifo_full  = (fifo_count >= FIFO_DEPTH_COUNT);

    wire accept_wr = ioctl_download && ioctl_wr && file_accept && download_active;
    wire write_pop = !fifo_empty && !ddram_busy;
    wire fifo_space_after_pop = !fifo_full || write_pop;

    wire [31:0] ioctl_addr_plus_one = ioctl_addr + 32'd1;
    wire ioctl_addr_in_range = ioctl_addr < (32'd1 << ADDR_WIDTH);

    wire [DDRAM_ADDR_WIDTH-1:0] ioctl_word_addr =
        DDRAM_BASE_ADDR + ioctl_addr[BYTE_ADDR_WIDTH-1:3];

    wire [31:0] mem_rd_addr32 =
        {{(32-ADDR_WIDTH){1'b0}}, mem_rd_addr};

    wire [DDRAM_ADDR_WIDTH-1:0] read_word_addr =
        DDRAM_BASE_ADDR + mem_rd_addr32[BYTE_ADDR_WIDTH-1:3];
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    localparam bit COPY_TO_DDR_ENABLED = 1'b0;
    wire [DDRAM_ADDR_WIDTH-1:0] segapcm_copy_word_addr =
        SEGAPCM_ROM_BASE_ADDR + 29'h0000_0800 + segapcm_copy_wr_addr[18:3];
    localparam logic [18:0] SMOKE_DDR_CAPTURE_BYTES = 19'h01000;
    logic [18:0] smoke_ddr_effective_capture_bytes;
    logic [18:0] smoke_ddr_effective_capture_words;
    always @* begin
        smoke_ddr_effective_capture_bytes = SMOKE_DDR_CAPTURE_BYTES;
        if (smoke_ddr_capture_limit != 19'd0) begin
            smoke_ddr_effective_capture_bytes = smoke_ddr_capture_limit;
        end
        smoke_ddr_effective_capture_words =
            {3'd0, smoke_ddr_effective_capture_bytes[18:3]} +
            {18'd0, |smoke_ddr_effective_capture_bytes[2:0]};
    end
    wire [DDRAM_ADDR_WIDTH-1:0] smoke_ddr_capture_word_end =
        SEGAPCM_ROM_BASE_ADDR +
        {{(DDRAM_ADDR_WIDTH-19){1'b0}}, smoke_ddr_effective_capture_words};
    wire smoke_ddr_tap_in_range =
        smoke_ddr_payload_tap_addr < smoke_ddr_effective_capture_bytes;
    wire [18:0] smoke_ddr_capture_index =
        {3'd0, smoke_ddr_write_count_debug};
    wire [DDRAM_ADDR_WIDTH-1:0] smoke_ddr_tap_word_addr =
        SEGAPCM_ROM_BASE_ADDR + smoke_ddr_capture_index[18:3];
    wire [DDRAM_ADDR_WIDTH-1:0] smoke_ddr_read_word_addr =
        SEGAPCM_ROM_BASE_ADDR + smoke_ddr_rd_addr[18:3];
    wire smoke_ddr_write_pop_live =
        write_pop &&
        (fifo_addr[fifo_rd_ptr] >= SEGAPCM_ROM_BASE_ADDR) &&
        (fifo_addr[fifo_rd_ptr] < smoke_ddr_capture_word_end);
    wire [3:0] smoke_ddr_write_pop_byte_count =
        be_popcount8(fifo_be[fifo_rd_ptr]);
    wire [2:0] smoke_ddr_write_pop_last_lane =
        be_last_lane(fifo_be[fifo_rd_ptr]);
    wire [15:0] smoke_ddr_write_commit_next =
        smoke_ddr_write_req_count_debug +
        {12'd0, smoke_ddr_write_pop_byte_count};
    assign smoke_ddr_base_addr_debug = SEGAPCM_ROM_BASE_ADDR[15:0];
`else
    localparam bit COPY_TO_DDR_ENABLED = 1'b1;
    wire [DDRAM_ADDR_WIDTH-1:0] segapcm_copy_word_addr =
        SEGAPCM_ROM_BASE_ADDR + segapcm_copy_wr_addr[18:3];
`endif
    wire copy_storage_enabled = COPY_TO_DDR_ENABLED;

    wire accept_wr_in_range = accept_wr && ioctl_addr_in_range;
    wire pack_word_changed =
        accept_wr_in_range && pack_valid && (pack_addr != ioctl_word_addr);
    wire download_end_flush = download_end && download_active && pack_valid;
    wire finish_flush = finish_pending && pack_valid;
    wire pack_flush_requested = pack_word_changed || download_end_flush || finish_flush;
    wire pack_flush_fire = pack_flush_requested && fifo_space_after_pop;
    wire pack_flush_blocked = pack_flush_requested && !fifo_space_after_pop;
    wire [7:0] copy_lane_be = lane_be(segapcm_copy_wr_addr[2:0]);
    wire [63:0] copy_lane_word =
        lane_din(segapcm_copy_wr_data, segapcm_copy_wr_addr[2:0]);
    wire [63:0] copy_merged_word =
        merge_lane(copy_pack_valid ? copy_pack_word : 64'd0,
                   segapcm_copy_wr_data,
                   segapcm_copy_wr_addr[2:0]);
    wire [7:0] copy_merged_be =
        (copy_pack_valid ? copy_pack_be : 8'd0) | copy_lane_be;
    wire copy_word_changed =
        copy_storage_enabled &&
        segapcm_copy_wr_req &&
        copy_pack_valid &&
        (copy_pack_addr != segapcm_copy_word_addr);
    wire copy_same_word_full =
        copy_storage_enabled &&
        segapcm_copy_wr_req &&
        copy_pack_valid &&
        !copy_word_changed &&
        (copy_merged_be == 8'hff);
    wire copy_flush_active = copy_flush_pending || segapcm_copy_flush_req;
    wire copy_flush_requested =
        copy_storage_enabled && copy_flush_active && copy_pack_valid;
    wire copy_push_requested =
        copy_storage_enabled &&
        (copy_word_changed || copy_flush_requested || copy_same_word_full);
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    wire smoke_ddr_capture_open =
        !smoke_ddr_payload_present &&
        ({3'd0, smoke_ddr_write_count_debug} <
         smoke_ddr_effective_capture_bytes);
    wire smoke_ddr_write_req_live =
        smoke_ddr_payload_tap_valid &&
        smoke_ddr_tap_in_range &&
        smoke_ddr_capture_open;
    wire [7:0] smoke_ddr_tap_lane_be =
        lane_be(smoke_ddr_capture_index[2:0]);
    wire [63:0] smoke_ddr_tap_lane_word =
        lane_din(smoke_ddr_payload_tap_data, smoke_ddr_capture_index[2:0]);
    wire [63:0] smoke_ddr_tap_merged_word =
        merge_lane(smoke_ddr_pack_valid ? smoke_ddr_pack_word : 64'd0,
                   smoke_ddr_payload_tap_data,
                   smoke_ddr_capture_index[2:0]);
    wire [7:0] smoke_ddr_tap_merged_be =
        (smoke_ddr_pack_valid ? smoke_ddr_pack_be : 8'd0) |
        smoke_ddr_tap_lane_be;
    wire smoke_ddr_tap_word_changed =
        smoke_ddr_write_req_live &&
        smoke_ddr_pack_valid &&
        (smoke_ddr_pack_addr != smoke_ddr_tap_word_addr);
    wire smoke_ddr_tap_word_full =
        smoke_ddr_write_req_live &&
        smoke_ddr_pack_valid &&
        !smoke_ddr_tap_word_changed &&
        (smoke_ddr_tap_merged_be == 8'hff);
    wire smoke_ddr_tap_push_requested =
        smoke_ddr_tap_word_changed || smoke_ddr_tap_word_full;
    wire smoke_ddr_tap_push_fire =
        !pack_flush_fire &&
        smoke_ddr_tap_push_requested &&
        fifo_space_after_pop;
`endif
    wire copy_push_fire =
        !pack_flush_fire &&
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
        !smoke_ddr_tap_push_fire &&
`endif
        copy_push_requested &&
        fifo_space_after_pop;
    wire copy_flush_blocked =
        copy_push_requested &&
        !fifo_space_after_pop;
    wire copy_accept =
        segapcm_copy_wr_req &&
        !ioctl_download &&
        !download_active &&
        !finish_pending &&
        !copy_flush_active &&
        (!(copy_word_changed || copy_same_word_full) || copy_push_fire);
    wire copy_backpressure_live = segapcm_copy_wr_req && !copy_accept;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    wire smoke_ddr_write_accept_live =
        smoke_ddr_write_req_live &&
        !ioctl_download &&
        !download_active &&
        !finish_pending &&
        (!(smoke_ddr_tap_word_changed || smoke_ddr_tap_word_full) ||
         smoke_ddr_tap_push_fire);
    wire smoke_ddr_write_blocked_live =
        smoke_ddr_write_req_live &&
        !smoke_ddr_write_accept_live;
`endif
    wire [DDRAM_ADDR_WIDTH-1:0] copy_push_addr = copy_pack_addr;
    wire [63:0] copy_push_word =
        copy_same_word_full ? copy_merged_word : copy_pack_word;
    wire [7:0] copy_push_be =
        copy_same_word_full ? copy_merged_be : copy_pack_be;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    wire [DDRAM_ADDR_WIDTH-1:0] smoke_ddr_tap_push_addr =
        smoke_ddr_pack_addr;
    wire [63:0] smoke_ddr_tap_push_word =
        smoke_ddr_tap_word_full ? smoke_ddr_tap_merged_word :
                                  smoke_ddr_pack_word;
    wire [7:0] smoke_ddr_tap_push_be =
        smoke_ddr_tap_word_full ? smoke_ddr_tap_merged_be :
                                  smoke_ddr_pack_be;
`endif
    wire write_waiting_for_ddram = !fifo_empty && ddram_busy;
    wire load_can_finish =
        finish_pending &&
        !pack_valid &&
        fifo_empty &&
        !write_pending &&
        !write_pop &&
        !ddram_busy;

    wire read_can_accept =
        (rd_state == RD_IDLE) &&
        !ioctl_download &&
        !download_active &&
        !finish_pending &&
        !pack_valid &&
        fifo_empty &&
        !ddram_busy;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    wire smoke_ddr_read_can_accept =
        read_can_accept &&
        !mem_rd_req &&
        smoke_ddr_payload_present;
    assign smoke_ddr_rd_ready = smoke_ddr_read_can_accept;
`endif
    wire copy_can_finish =
        copy_flush_active &&
        !copy_pack_valid &&
        fifo_empty &&
        !write_pending &&
        !write_pop &&
        !ddram_busy;

    assign mem_rd_ready = read_can_accept;
    assign segapcm_copy_wr_ready = copy_accept;
    // Hardware debug decode:
    // CF = {7'd0, fifo_full, fifo_empty, fifo_count[6:0]}
    // CR = live copy/backend blockers and accept bits below.
    // WF = {4'd0, copy_pack_be, copy_pack_valid, pack_valid,
    //       copy_word_changed, copy_push_requested}
    // PR = live pack-ready bits below, including next_be/full/push/fire.
    // PP = {copy_pack_be, copy_pack_valid, copy_push_requested,
    //       write_pending, fifo_empty, fifo_full, ddram_busy, write_pop,
    //       read_can_accept}
    // RC = {8'd0, write_pending, copy_push_requested, copy_pack_valid,
    //       fifo_full, copy_wr_ready, copy_backpressure, ddram_busy,
    //       read_can_accept}
    assign segapcm_copy_fifo_debug = {
        7'd0,
        fifo_full,
        fifo_empty,
        fifo_count[6:0]
    };
    assign segapcm_copy_ready_debug = {
        4'd0,
        copy_flush_active,
        finish_pending,
        download_active,
        ioctl_download,
        ddram_busy,
        write_pending,
        fifo_empty,
        fifo_full,
        copy_push_fire,
        copy_word_changed,
        copy_accept,
        segapcm_copy_wr_req
    };
    assign segapcm_copy_write_req_debug = {
        6'd0,
        write_pop,
        write_waiting_for_ddram,
        copy_flush_blocked,
        copy_push_requested,
        copy_push_fire,
        pack_flush_fire,
        copy_word_changed,
        copy_accept,
        segapcm_copy_wr_ready,
        segapcm_copy_wr_req
    };
    assign segapcm_copy_word_debug = {
        4'd0,
        copy_pack_be,
        copy_pack_valid,
        pack_valid,
        copy_word_changed,
        copy_push_requested
    };
    assign segapcm_copy_flush_debug = {
        8'd0,
        copy_can_finish,
        copy_flush_blocked,
        copy_push_fire,
        copy_flush_requested,
        copy_pack_valid,
        copy_flush_active,
        segapcm_copy_flush_done,
        segapcm_copy_flush_req
    };
    assign segapcm_copy_full_detect_count_debug = copy_full_detect_count;
    assign segapcm_copy_push_req_count_debug = copy_push_req_count;
    assign segapcm_copy_push_fire_count_debug = copy_push_fire_count;
    assign segapcm_copy_fifo_push_count_debug = copy_fifo_push_count;
    assign segapcm_copy_pack_ready_debug = {
        8'd0,
        copy_merged_be == 8'hff,
        copy_same_word_full,
        copy_push_requested,
        copy_push_fire,
        fifo_full,
        fifo_space_after_pop,
        copy_accept,
        segapcm_copy_wr_ready
    };
    assign segapcm_copy_post_push_debug = {
        copy_pack_be,
        copy_pack_valid,
        copy_push_requested,
        write_pending,
        fifo_empty,
        fifo_full,
        ddram_busy,
        write_pop,
        read_can_accept
    };
    assign segapcm_read_gate_debug = {
        8'd0,
        write_pending,
        copy_push_requested,
        copy_pack_valid,
        fifo_full,
        segapcm_copy_wr_ready,
        copy_backpressure_live,
        ddram_busy,
        read_can_accept
    };
    assign segapcm_read_after_copy_count_debug = read_after_copy_count;
    assign ioctl_wait =
        ioctl_download &&
        file_accept &&
        (fifo_full || pack_flush_blocked || write_waiting_for_ddram);

    // Report load busy only for the actual download/finalization window.
    // Keep post-load read/write internals from perturbing mode5 session control.
    assign load_busy = ioctl_download ||
                       download_active ||
                       finish_pending ||
                       write_pending;

    function automatic [7:0] lane_be(input logic [2:0] lane);
        begin
            case (lane)
                3'd0: lane_be = 8'h01;
                3'd1: lane_be = 8'h02;
                3'd2: lane_be = 8'h04;
                3'd3: lane_be = 8'h08;
                3'd4: lane_be = 8'h10;
                3'd5: lane_be = 8'h20;
                3'd6: lane_be = 8'h40;
                default: lane_be = 8'h80;
            endcase
        end
    endfunction

    function automatic [63:0] lane_din(
        input logic [7:0] byte_data,
        input logic [2:0] lane
    );
        begin
            lane_din = 64'd0;
            case (lane)
                3'd0: lane_din[7:0]   = byte_data;
                3'd1: lane_din[15:8]  = byte_data;
                3'd2: lane_din[23:16] = byte_data;
                3'd3: lane_din[31:24] = byte_data;
                3'd4: lane_din[39:32] = byte_data;
                3'd5: lane_din[47:40] = byte_data;
                3'd6: lane_din[55:48] = byte_data;
                default: lane_din[63:56] = byte_data;
            endcase
        end
    endfunction

    function automatic [63:0] merge_lane(
        input logic [63:0] word_data,
        input logic [7:0] byte_data,
        input logic [2:0] lane
    );
        begin
            merge_lane = word_data;
            case (lane)
                3'd0: merge_lane[7:0]   = byte_data;
                3'd1: merge_lane[15:8]  = byte_data;
                3'd2: merge_lane[23:16] = byte_data;
                3'd3: merge_lane[31:24] = byte_data;
                3'd4: merge_lane[39:32] = byte_data;
                3'd5: merge_lane[47:40] = byte_data;
                3'd6: merge_lane[55:48] = byte_data;
                default: merge_lane[63:56] = byte_data;
            endcase
        end
    endfunction

    function automatic [7:0] lane_dout(
        input logic [63:0] word_data,
        input logic [2:0] lane
    );
        begin
            case (lane)
                3'd0: lane_dout = word_data[7:0];
                3'd1: lane_dout = word_data[15:8];
                3'd2: lane_dout = word_data[23:16];
                3'd3: lane_dout = word_data[31:24];
                3'd4: lane_dout = word_data[39:32];
                3'd5: lane_dout = word_data[47:40];
                3'd6: lane_dout = word_data[55:48];
                default: lane_dout = word_data[63:56];
            endcase
        end
    endfunction

    function automatic [3:0] be_popcount8(input logic [7:0] be);
        begin
            be_popcount8 =
                {3'd0, be[0]} + {3'd0, be[1]} +
                {3'd0, be[2]} + {3'd0, be[3]} +
                {3'd0, be[4]} + {3'd0, be[5]} +
                {3'd0, be[6]} + {3'd0, be[7]};
        end
    endfunction

    function automatic [2:0] be_last_lane(input logic [7:0] be);
        begin
            if (be[7]) begin
                be_last_lane = 3'd7;
            end else if (be[6]) begin
                be_last_lane = 3'd6;
            end else if (be[5]) begin
                be_last_lane = 3'd5;
            end else if (be[4]) begin
                be_last_lane = 3'd4;
            end else if (be[3]) begin
                be_last_lane = 3'd3;
            end else if (be[2]) begin
                be_last_lane = 3'd2;
            end else if (be[1]) begin
                be_last_lane = 3'd1;
            end else begin
                be_last_lane = 3'd0;
            end
        end
    endfunction

    function automatic [FIFO_AW-1:0] fifo_ptr_inc(input logic [FIFO_AW-1:0] ptr);
        begin
            if (ptr == WRITE_FIFO_DEPTH[FIFO_AW-1:0] - {{(FIFO_AW-1){1'b0}}, 1'b1}) begin
                fifo_ptr_inc = '0;
            end else begin
                fifo_ptr_inc = ptr + {{(FIFO_AW-1){1'b0}}, 1'b1};
            end
        end
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            ioctl_download_q <= 1'b0;
            download_active <= 1'b0;
            finish_pending <= 1'b0;

            fifo_wr_ptr <= '0;
            fifo_rd_ptr <= '0;
            fifo_count <= '0;
            pack_valid <= 1'b0;
            pack_addr <= '0;
            pack_word <= 64'd0;
            pack_be <= 8'd0;
            copy_pack_valid <= 1'b0;
            copy_pack_addr <= '0;
            copy_pack_word <= 64'd0;
            copy_pack_be <= 8'd0;
            copy_flush_pending <= 1'b0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
            smoke_ddr_pack_valid <= 1'b0;
            smoke_ddr_pack_addr <= '0;
            smoke_ddr_pack_word <= 64'd0;
            smoke_ddr_pack_be <= 8'd0;
`endif

            rd_state <= RD_IDLE;
            read_owner <= RD_OWNER_FILE;
            read_lane <= 3'd0;
            rd_wait_count <= '0;

            mem_rd_valid <= 1'b0;
            mem_rd_data <= 8'd0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
            smoke_ddr_rd_valid <= 1'b0;
            smoke_ddr_rd_data <= 8'd0;
            smoke_ddr_payload_present <= 1'b0;
            smoke_ddr_payload_length <= 19'd0;
            smoke_ddr_write_req_count_debug <= 16'd0;
            smoke_ddr_write_count_debug <= 16'd0;
            smoke_ddr_write_blocked_count_debug <= 16'd0;
            smoke_ddr_write_status_debug <= 16'd0;
            smoke_ddr_header_skip_count_debug <= 16'd0;
            smoke_ddr_last_write_index_debug <= 16'd0;
            smoke_ddr_last_write_addr_debug <= 16'd0;
            smoke_ddr_last_write_lane_debug <= 16'd0;
            smoke_ddr_last_write_data_debug <= 8'd0;
            smoke_ddr_read_count_debug <= 16'd0;
            smoke_ddr_last_read_index_debug <= 16'd0;
            smoke_ddr_last_read_addr_debug <= 16'd0;
            smoke_ddr_last_read_lane_debug <= 16'd0;
            smoke_ddr_last_read_word0_debug <= 16'd0;
            smoke_ddr_last_read_word1_debug <= 16'd0;
            smoke_ddr_last_read_data_debug <= 8'd0;
`endif
            segapcm_copy_flush_done <= 1'b0;
            segapcm_copy_accept_count_debug <= 16'd0;
            segapcm_copy_write_count_debug <= 16'd0;
            copy_full_detect_count <= 16'd0;
            copy_push_req_count <= 16'd0;
            copy_push_fire_count <= 16'd0;
            copy_fifo_push_count <= 16'd0;
            read_after_copy_count <= 16'd0;

            load_done <= 1'b0;
            load_done_pulse <= 1'b0;
            play_ready_pulse <= 1'b0;
            load_error <= 1'b0;
            overflow_error <= 1'b0;
            file_size <= 32'd0;
            magic_debug <= 32'd0;

            ddram_burstcnt <= 8'd0;
            ddram_addr <= '0;
            ddram_rd <= 1'b0;
            ddram_din <= 64'd0;
            ddram_be <= 8'd0;
            ddram_we <= 1'b0;
            write_pending <= 1'b0;
        end else begin
            ioctl_download_q <= ioctl_download;

            mem_rd_valid <= 1'b0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
            smoke_ddr_rd_valid <= 1'b0;
`endif
            load_done_pulse <= 1'b0;
            play_ready_pulse <= 1'b0;
            segapcm_copy_flush_done <= 1'b0;

            ddram_burstcnt <= 8'd0;
            ddram_rd <= 1'b0;
            ddram_we <= 1'b0;
            ddram_be <= 8'd0;

            if (download_start) begin
                download_active <= file_accept;
                finish_pending <= 1'b0;
                write_pending <= 1'b0;

                fifo_wr_ptr <= '0;
                fifo_rd_ptr <= '0;
                fifo_count <= '0;
                pack_valid <= 1'b0;
                pack_addr <= '0;
                pack_word <= 64'd0;
                pack_be <= 8'd0;
                copy_pack_valid <= 1'b0;
                copy_pack_addr <= '0;
                copy_pack_word <= 64'd0;
                copy_pack_be <= 8'd0;
                copy_flush_pending <= 1'b0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                smoke_ddr_pack_valid <= 1'b0;
                smoke_ddr_pack_addr <= '0;
                smoke_ddr_pack_word <= 64'd0;
                smoke_ddr_pack_be <= 8'd0;
`endif

                rd_state <= RD_IDLE;
                read_owner <= RD_OWNER_FILE;
                read_lane <= 3'd0;
                rd_wait_count <= '0;

                mem_rd_valid <= 1'b0;
                mem_rd_data <= 8'd0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                smoke_ddr_rd_valid <= 1'b0;
                smoke_ddr_rd_data <= 8'd0;
                smoke_ddr_payload_present <= 1'b0;
                smoke_ddr_payload_length <= 19'd0;
                smoke_ddr_write_req_count_debug <= 16'd0;
                smoke_ddr_write_count_debug <= 16'd0;
                smoke_ddr_write_blocked_count_debug <= 16'd0;
                smoke_ddr_write_status_debug <= 16'd0;
                smoke_ddr_header_skip_count_debug <= 16'd0;
                smoke_ddr_last_write_index_debug <= 16'd0;
                smoke_ddr_last_write_addr_debug <= 16'd0;
                smoke_ddr_last_write_lane_debug <= 16'd0;
                smoke_ddr_last_write_data_debug <= 8'd0;
                smoke_ddr_read_count_debug <= 16'd0;
                smoke_ddr_last_read_index_debug <= 16'd0;
                smoke_ddr_last_read_addr_debug <= 16'd0;
                smoke_ddr_last_read_lane_debug <= 16'd0;
                smoke_ddr_last_read_word0_debug <= 16'd0;
                smoke_ddr_last_read_word1_debug <= 16'd0;
                smoke_ddr_last_read_data_debug <= 8'd0;
`endif
                segapcm_copy_accept_count_debug <= 16'd0;
                segapcm_copy_write_count_debug <= 16'd0;
                copy_full_detect_count <= 16'd0;
                copy_push_req_count <= 16'd0;
                copy_push_fire_count <= 16'd0;
                copy_fifo_push_count <= 16'd0;
                read_after_copy_count <= 16'd0;

                load_done <= 1'b0;
                load_done_pulse <= 1'b0;
                play_ready_pulse <= 1'b0;
                load_error <= 1'b0;
                overflow_error <= 1'b0;
                file_size <= 32'd0;
                magic_debug <= 32'd0;
            end else begin
                if (download_end && download_active) begin
                    download_active <= 1'b0;
                    finish_pending <= 1'b1;
                end

                if (write_pop) begin
                    ddram_burstcnt <= 8'd1;
                    ddram_addr <= fifo_addr[fifo_rd_ptr];
                    ddram_din <= fifo_din[fifo_rd_ptr];
                    ddram_be <= fifo_be[fifo_rd_ptr];
                    ddram_we <= 1'b1;
                    write_pending <= 1'b1;
                    fifo_rd_ptr <= fifo_ptr_inc(fifo_rd_ptr);
                    if (fifo_addr[fifo_rd_ptr] >= SEGAPCM_ROM_BASE_ADDR) begin
                        segapcm_copy_write_count_debug <=
                            segapcm_copy_write_count_debug + 16'd1;
                    end
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                    if (smoke_ddr_write_pop_live) begin
                        smoke_ddr_write_req_count_debug <=
                            smoke_ddr_write_commit_next;
                        smoke_ddr_last_write_addr_debug <=
                            fifo_addr[fifo_rd_ptr][15:0];
                        smoke_ddr_last_write_lane_debug <=
                            {13'd0, smoke_ddr_write_pop_last_lane};
                        smoke_ddr_last_write_data_debug <=
                            lane_dout(fifo_din[fifo_rd_ptr],
                                      smoke_ddr_write_pop_last_lane);
                        if ({3'd0, smoke_ddr_write_commit_next} >=
                            smoke_ddr_effective_capture_bytes) begin
                            smoke_ddr_payload_present <= 1'b1;
                            smoke_ddr_payload_length <=
                                smoke_ddr_effective_capture_bytes;
                        end
                    end
`endif
                end else if (write_pending && !ddram_busy) begin
                    write_pending <= 1'b0;
                end

                if (segapcm_copy_flush_req) begin
                    copy_flush_pending <= 1'b1;
                end

                if (pack_flush_blocked) begin
                    overflow_error <= 1'b1;
                end

                if (copy_accept &&
                    copy_same_word_full &&
                    (copy_full_detect_count != 16'hffff)) begin
                    copy_full_detect_count <= copy_full_detect_count + 16'd1;
                end

                if (segapcm_copy_wr_req &&
                    copy_push_requested &&
                    (copy_push_req_count != 16'hffff)) begin
                    copy_push_req_count <= copy_push_req_count + 16'd1;
                end

`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                smoke_ddr_write_status_debug <= {
                    8'd0,
                    smoke_ddr_payload_present,
                    smoke_ddr_capture_open,
                    copy_pack_valid,
                    !fifo_empty,
                    write_pending,
                    smoke_ddr_write_accept_live,
                    smoke_ddr_write_blocked_live,
                    smoke_ddr_write_req_live
                };
                if (smoke_ddr_write_blocked_live &&
                    (smoke_ddr_write_blocked_count_debug != 16'hffff)) begin
                    smoke_ddr_write_blocked_count_debug <=
                        smoke_ddr_write_blocked_count_debug + 16'd1;
                end
`endif

                if (copy_push_fire &&
                    (copy_push_fire_count != 16'hffff)) begin
                    copy_push_fire_count <= copy_push_fire_count + 16'd1;
                end

                if (pack_flush_fire || copy_push_fire
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                    || smoke_ddr_tap_push_fire
`endif
                ) begin
                    if ((copy_push_fire
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                         || smoke_ddr_tap_push_fire
`endif
                        ) &&
                        (copy_fifo_push_count != 16'hffff)) begin
                        copy_fifo_push_count <= copy_fifo_push_count + 16'd1;
                    end
                    fifo_addr[fifo_wr_ptr] <=
                        pack_flush_fire ? pack_addr :
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                        smoke_ddr_tap_push_fire ? smoke_ddr_tap_push_addr :
`endif
                        copy_push_addr;
                    fifo_din[fifo_wr_ptr] <=
                        pack_flush_fire ? pack_word :
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                        smoke_ddr_tap_push_fire ? smoke_ddr_tap_push_word :
`endif
                        copy_push_word;
                    fifo_be[fifo_wr_ptr] <=
                        pack_flush_fire ? pack_be :
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                        smoke_ddr_tap_push_fire ? smoke_ddr_tap_push_be :
`endif
                        copy_push_be;
                    fifo_wr_ptr <= fifo_ptr_inc(fifo_wr_ptr);

                    if (pack_flush_fire && pack_word_changed) begin
                        pack_valid <= 1'b1;
                        pack_addr <= ioctl_word_addr;
                        pack_word <= lane_din(ioctl_dout, ioctl_addr[2:0]);
                        pack_be <= lane_be(ioctl_addr[2:0]);
                    end else if (pack_flush_fire) begin
                        pack_valid <= 1'b0;
                        pack_addr <= '0;
                        pack_word <= 64'd0;
                        pack_be <= 8'd0;
                    end

                    if (copy_storage_enabled &&
                        copy_push_fire &&
                        copy_word_changed) begin
                        copy_pack_valid <= 1'b1;
                        copy_pack_addr <= segapcm_copy_word_addr;
                        copy_pack_word <= copy_lane_word;
                        copy_pack_be <= copy_lane_be;
                    end else if (copy_storage_enabled && copy_push_fire) begin
                        copy_pack_valid <= 1'b0;
                        copy_pack_addr <= '0;
                        copy_pack_word <= 64'd0;
                        copy_pack_be <= 8'd0;
                    end

`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                    if (smoke_ddr_tap_push_fire &&
                        smoke_ddr_tap_word_changed) begin
                        smoke_ddr_pack_valid <= 1'b1;
                        smoke_ddr_pack_addr <= smoke_ddr_tap_word_addr;
                        smoke_ddr_pack_word <= smoke_ddr_tap_lane_word;
                        smoke_ddr_pack_be <= smoke_ddr_tap_lane_be;
                    end else if (smoke_ddr_tap_push_fire) begin
                        smoke_ddr_pack_valid <= 1'b0;
                        smoke_ddr_pack_addr <= '0;
                        smoke_ddr_pack_word <= 64'd0;
                        smoke_ddr_pack_be <= 8'd0;
                    end
`endif
                end

                if (accept_wr) begin
                    if (!ioctl_addr_in_range) begin
                        overflow_error <= 1'b1;
                    end else if (pack_word_changed && !pack_flush_fire) begin
                        overflow_error <= 1'b1;
                    end else if (!pack_word_changed) begin
                        pack_valid <= 1'b1;
                        pack_addr <= ioctl_word_addr;
                        pack_word <= merge_lane(
                            pack_valid ? pack_word : 64'd0,
                            ioctl_dout,
                            ioctl_addr[2:0]
                        );
                        pack_be <= (pack_valid ? pack_be : 8'd0) |
                                   lane_be(ioctl_addr[2:0]);
                    end

                    if (ioctl_addr_in_range) begin

                        if (ioctl_addr_plus_one > file_size) begin
                            file_size <= ioctl_addr_plus_one;
                        end

                        case (ioctl_addr[1:0])
                            2'd0: magic_debug[7:0] <= ioctl_dout;
                            2'd1: magic_debug[15:8] <= ioctl_dout;
                            2'd2: magic_debug[23:16] <= ioctl_dout;
                            2'd3: magic_debug[31:24] <= ioctl_dout;
                            default: begin end
                        endcase
                    end
                end

                if (copy_accept) begin
                    segapcm_copy_accept_count_debug <=
                        segapcm_copy_accept_count_debug + 16'd1;
                end

                if (copy_storage_enabled &&
                    copy_accept &&
                    !copy_word_changed &&
                    !copy_same_word_full) begin
                    copy_pack_valid <= 1'b1;
                    copy_pack_addr <= segapcm_copy_word_addr;
                    copy_pack_word <= copy_merged_word;
                    copy_pack_be <= copy_merged_be;
                end

`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                if (smoke_ddr_write_accept_live) begin
                    if (smoke_ddr_header_skip_count_debug < 16'd8) begin
                        smoke_ddr_header_skip_count_debug <= 16'd8;
                    end
                    smoke_ddr_write_count_debug <=
                        smoke_ddr_write_count_debug + 16'd1;
                    smoke_ddr_last_write_index_debug <=
                        smoke_ddr_write_count_debug;
                end

                if (smoke_ddr_write_accept_live &&
                    !smoke_ddr_tap_word_changed &&
                    !smoke_ddr_tap_word_full) begin
                    smoke_ddr_pack_valid <= 1'b1;
                    smoke_ddr_pack_addr <= smoke_ddr_tap_word_addr;
                    smoke_ddr_pack_word <= smoke_ddr_tap_merged_word;
                    smoke_ddr_pack_be <= smoke_ddr_tap_merged_be;
                end
`endif

                case ({(pack_flush_fire || copy_push_fire
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                         || smoke_ddr_tap_push_fire
`endif
                        ), write_pop})
                    2'b10: fifo_count <= fifo_count + {{FIFO_AW{1'b0}}, 1'b1};
                    2'b01: fifo_count <= fifo_count - {{FIFO_AW{1'b0}}, 1'b1};
                    default: fifo_count <= fifo_count;
                endcase

                if (read_can_accept && mem_rd_req) begin
                    if ((segapcm_copy_write_count_debug != 16'd0) &&
                        (read_after_copy_count != 16'hffff)) begin
                        read_after_copy_count <= read_after_copy_count + 16'd1;
                    end
                    // Safety guard: if the player ever asks past the loaded VGM
                    // image, synthesize VGM end (0x66) instead of reading
                    // undefined DDRAM contents or waiting on an invalid read.
                    if (mem_rd_addr32 >= file_size) begin
                        mem_rd_data <= 8'h66;
                        mem_rd_valid <= 1'b1;
                        rd_state <= RD_IDLE;
                    end else begin
                        ddram_burstcnt <= 8'd1;
                        ddram_addr <= read_word_addr;
                        ddram_rd <= 1'b1;
                        read_lane <= mem_rd_addr[2:0];
                        read_owner <= RD_OWNER_FILE;
                        rd_wait_count <= '0;
                        rd_state <= RD_WAIT;
                    end
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                end else if (smoke_ddr_read_can_accept && smoke_ddr_rd_req) begin
                    ddram_burstcnt <= 8'd1;
                    ddram_addr <= smoke_ddr_read_word_addr;
                    ddram_rd <= 1'b1;
                    read_lane <= smoke_ddr_rd_addr[2:0];
                    read_owner <= RD_OWNER_SMOKE_DDR;
                    smoke_ddr_last_read_index_debug <= smoke_ddr_rd_addr[15:0];
                    smoke_ddr_last_read_addr_debug <=
                        smoke_ddr_read_word_addr[15:0];
                    smoke_ddr_last_read_lane_debug <=
                        {13'd0, smoke_ddr_rd_addr[2:0]};
                    rd_wait_count <= '0;
                    rd_state <= RD_WAIT;
                    if (smoke_ddr_read_count_debug != 16'hffff) begin
                        smoke_ddr_read_count_debug <=
                            smoke_ddr_read_count_debug + 16'd1;
                    end
`endif
                end else if (rd_state == RD_WAIT && ddram_dout_ready) begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                    if (read_owner == RD_OWNER_SMOKE_DDR) begin
                        smoke_ddr_rd_data <= lane_dout(ddram_dout, read_lane);
                        smoke_ddr_last_read_data_debug <=
                            lane_dout(ddram_dout, read_lane);
                        smoke_ddr_last_read_word0_debug <= ddram_dout[15:0];
                        smoke_ddr_last_read_word1_debug <= ddram_dout[63:48];
                        smoke_ddr_rd_valid <= 1'b1;
                    end else begin
                        mem_rd_data <= lane_dout(ddram_dout, read_lane);
                        mem_rd_valid <= 1'b1;
                    end
`else
                    mem_rd_data <= lane_dout(ddram_dout, read_lane);
                    mem_rd_valid <= 1'b1;
`endif
                    rd_wait_count <= '0;
                    rd_state <= RD_IDLE;
                end else if (rd_state == RD_WAIT) begin
                    if (rd_wait_count >= RD_TIMEOUT_LAST) begin
                        // If DDRAM never returns data, fail safe as VGM end.
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
                        if (read_owner == RD_OWNER_SMOKE_DDR) begin
                            smoke_ddr_rd_data <= 8'h80;
                            smoke_ddr_last_read_data_debug <= 8'h80;
                            smoke_ddr_last_read_word0_debug <= 16'd0;
                            smoke_ddr_last_read_word1_debug <= 16'd0;
                            smoke_ddr_rd_valid <= 1'b1;
                        end else begin
                            mem_rd_data <= 8'h66;
                            mem_rd_valid <= 1'b1;
                        end
`else
                        mem_rd_data <= 8'h66;
                        mem_rd_valid <= 1'b1;
`endif
                        rd_wait_count <= '0;
                        rd_state <= RD_IDLE;
                    end else begin
                        rd_wait_count <= rd_wait_count + {{(RD_TIMEOUT_AW-1){1'b0}}, 1'b1};
                    end
                end

                if (load_can_finish) begin
                    finish_pending <= 1'b0;
                    load_done <= !overflow_error && !load_error;
                    load_done_pulse <= !overflow_error && !load_error;
                    play_ready_pulse <= !overflow_error && !load_error;
                end

                if (copy_can_finish) begin
                    copy_flush_pending <= 1'b0;
                    segapcm_copy_flush_done <= 1'b1;
                end
            end
        end
    end

endmodule
