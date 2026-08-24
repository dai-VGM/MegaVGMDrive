`timescale 1ns/1ps

// Full-file header/compatibility/data-block pre-scan.  No playback-visible
// output is committed until ST_FINISH, so a rejected B/dual file can never
// leak a register write into JT10.
module ym2610_player_scanner #(
    parameter int ADDR_WIDTH = 23,
    parameter int MAX_A_DESCRIPTORS = 64,
    parameter int MAX_B_DESCRIPTORS = 16,
    parameter ENABLE_YM2610B = 0
) (
    input  logic                  clk,
    input  logic                  reset,
    input  logic                  start,
    input  logic [31:0]           physical_size,

    output logic                  mem_req,
    output logic [ADDR_WIDTH-1:0] mem_addr,
    input  logic                  mem_ready,
    input  logic                  mem_valid,
    input  logic [7:0]            mem_data,

    output logic                  busy,
    output logic                  done,
    output logic                  accepted,
    output logic [3:0]            classification,
    output logic [7:0]            reject_code,
    output logic [31:0]           original_size,
    output logic [31:0]           data_offset,
    output logic [31:0]           chip_clock,
    output logic [31:0]           loop_target,
    output logic [31:0]           loop_samples,
    output logic [31:0]           end_pc,
    output logic [31:0]           total_samples,
    output logic [31:0]           total_writes,
    output logic [31:0]           port0_writes,
    output logic [31:0]           port1_writes,
    output logic [31:0]           b_only_writes,
    output logic [31:0]           unknown_writes,
    output logic [31:0]           command_count,
    output logic [4:0]            debug_state,
    output logic                  variant_b,
    output logic                  dual_chip,
    output logic [31:0]           first_bad_pc,
    output logic                  first_bad_port,
    output logic [7:0]            first_bad_address,
    output logic [7:0]            first_bad_data,
    output logic [31:0]           first_bad_sample,
    output logic [3:0]            first_bad_semantic,
    output logic [2:0]            first_bad_target,
    output logic [3:0]            descriptor_a_count,
    output logic [3:0]            descriptor_b_count,
    output logic [6:0]            descriptor_a_count_full,
    output logic [4:0]            descriptor_b_count_full,

    input  logic                  map_req_valid,
    output logic                  map_req_ready,
    input  logic                  map_space_b,
    input  logic [23:0]           map_logical_addr,
    output logic                  map_rsp_valid,
    output logic                  map_rsp_hit,
    output logic [ADDR_WIDTH-1:0] map_rsp_file_addr
);
    localparam logic [3:0] VARIANT_NONE        = 4'd0;
    localparam logic [3:0] VARIANT_STANDARD    = 4'd1;
    localparam logic [3:0] VARIANT_B_COMPAT    = 4'd2;
    localparam logic [3:0] VARIANT_B_REQUIRED  = 4'd3;
    localparam logic [3:0] VARIANT_DUAL        = 4'd4;

    localparam logic [7:0] REJECT_NONE         = 8'h00;
    localparam logic [7:0] REJECT_HEADER       = 8'h01;
    localparam logic [7:0] REJECT_DUAL         = 8'h02;
    localparam logic [7:0] REJECT_B_REQUIRED   = 8'h03;
    localparam logic [7:0] REJECT_REGISTER     = 8'h04;
    localparam logic [7:0] REJECT_OPCODE       = 8'h05;
    localparam logic [7:0] REJECT_BLOCK        = 8'h06;
    localparam logic [7:0] REJECT_RANGE        = 8'h07;
    localparam logic [7:0] REJECT_DESCRIPTOR   = 8'h08;
    localparam logic [6:0] MAX_A_DESCRIPTOR_COUNT =
        MAX_A_DESCRIPTORS[6:0];
    localparam logic [4:0] MAX_B_DESCRIPTOR_COUNT =
        MAX_B_DESCRIPTORS[4:0];

    typedef enum logic [4:0] {
        ST_IDLE, ST_HEADER, ST_VALIDATE, ST_COMMAND, ST_WRITE_ADDR,
        ST_WRITE_DATA, ST_WAIT_LO, ST_WAIT_HI, ST_BLOCK_MARK,
        ST_BLOCK_TYPE, ST_BLOCK_SIZE, ST_BLOCK_META, ST_DESC_READ,
        ST_DESC_COMPARE, ST_DESC_STORE, ST_FINISH, ST_FATAL, ST_DONE
    } state_t;

    state_t state;
    assign debug_state = state;
    logic [7:0] header [0:127];
    logic [7:0] header_index;
    logic read_pending;
    logic [31:0] scan_pc;
    logic [31:0] command_pc;
    logic [7:0] opcode;
    logic pending_port;
    logic [7:0] pending_address;
    logic [7:0] wait_low;
    logic [1:0] block_size_index;
    logic [2:0] block_meta_index;
    logic [7:0] block_type;
    logic [31:0] block_size;
    logic [31:0] block_size_build;
    logic [31:0] block_rom_size;
    logic [31:0] block_logical_start;
    logic first_bad_valid;
    logic first_bad_b_only;
    logic loop_boundary_seen;

    logic compat_accepted;
    logic compat_b_only;
    logic compat_unknown;
    logic [3:0] compat_semantic;
    logic [2:0] compat_target;
    wire compat_effective_accepted = compat_accepted ||
        (ENABLE_YM2610B && variant_b && compat_b_only);

    // Descriptor payloads are packed into synchronous memories.  No memory
    // clear is performed: the committed count is the validity boundary, which
    // keeps the arrays eligible for Cyclone V block-RAM inference.
    localparam int A_DESC_WIDTH = 24 + 25 + ADDR_WIDTH;
    localparam int B_DESC_WIDTH = 20 + 21 + ADDR_WIDTH;
    (* ramstyle = "M10K, no_rw_check" *)
    logic [A_DESC_WIDTH-1:0] desc_a_mem [0:MAX_A_DESCRIPTORS-1];
    (* ramstyle = "M10K, no_rw_check" *)
    logic [B_DESC_WIDTH-1:0] desc_b_mem [0:MAX_B_DESCRIPTORS-1];
    logic [A_DESC_WIDTH-1:0] desc_a_q;
    logic [B_DESC_WIDTH-1:0] desc_b_q;
    logic [5:0] descriptor_read_index;
    logic descriptor_a_we, descriptor_b_we;
    logic [5:0] descriptor_a_waddr;
    logic [3:0] descriptor_b_waddr;
    logic [A_DESC_WIDTH-1:0] descriptor_a_wdata;
    logic [B_DESC_WIDTH-1:0] descriptor_b_wdata;

    logic pending_desc_space_b;
    logic [23:0] pending_desc_logical;
    logic [24:0] pending_desc_length;
    logic [ADDR_WIDTH-1:0] pending_desc_file;
    logic [6:0] overlap_index;
    logic descriptors_committed;

    typedef enum logic [1:0] {MAP_IDLE, MAP_READ, MAP_COMPARE} map_state_t;
    map_state_t map_state;
    logic map_request_space_b;
    logic [23:0] map_request_logical;
    logic [6:0] map_index;

    wire [23:0] desc_a_start = desc_a_q[A_DESC_WIDTH-1 -: 24];
    wire [24:0] desc_a_length =
        desc_a_q[A_DESC_WIDTH-24-1 -: 25];
    wire [ADDR_WIDTH-1:0] desc_a_file = desc_a_q[ADDR_WIDTH-1:0];
    wire [19:0] desc_b_start = desc_b_q[B_DESC_WIDTH-1 -: 20];
    wire [20:0] desc_b_length =
        desc_b_q[B_DESC_WIDTH-20-1 -: 21];
    wire [ADDR_WIDTH-1:0] desc_b_file = desc_b_q[ADDR_WIDTH-1:0];

    ym2610_player_compat u_compat (
        .port(pending_port), .address(pending_address), .data(mem_data),
        .accepted(compat_accepted), .b_only(compat_b_only),
        .unknown(compat_unknown), .semantic(compat_semantic),
        .target(compat_target)
    );

    function automatic [31:0] header32(input integer offset);
        header32 = {header[offset+3], header[offset+2],
                    header[offset+1], header[offset]};
    endfunction

    function automatic logic fetch_state(input state_t value);
        case (value)
            ST_HEADER, ST_COMMAND, ST_WRITE_ADDR, ST_WRITE_DATA,
            ST_WAIT_LO, ST_WAIT_HI, ST_BLOCK_MARK, ST_BLOCK_TYPE,
            ST_BLOCK_SIZE, ST_BLOCK_META: fetch_state = 1'b1;
            default: fetch_state = 1'b0;
        endcase
    endfunction

    always_comb begin
        mem_req = busy && fetch_state(state) && !read_pending;
        case (state)
            ST_HEADER:     mem_addr = {{(ADDR_WIDTH-8){1'b0}}, header_index};
            ST_COMMAND:    mem_addr = scan_pc[ADDR_WIDTH-1:0];
            ST_WRITE_ADDR,
            ST_WRITE_DATA,
            ST_WAIT_LO,
            ST_WAIT_HI,
            ST_BLOCK_MARK,
            ST_BLOCK_TYPE,
            ST_BLOCK_SIZE,
            ST_BLOCK_META: mem_addr = scan_pc[ADDR_WIDTH-1:0];
            default:       mem_addr = '0;
        endcase
    end

    assign descriptor_a_count = descriptor_a_count_full > 7'd15 ?
                                4'hf : descriptor_a_count_full[3:0];
    assign descriptor_b_count = descriptor_b_count_full > 5'd15 ?
                                4'hf : descriptor_b_count_full[3:0];
    assign map_req_ready = descriptors_committed && map_state == MAP_IDLE;

    always_comb begin
        descriptor_read_index = 6'd0;
        if (state == ST_DESC_READ)
            descriptor_read_index = overlap_index[5:0];
        else if (state == ST_DESC_COMPARE) begin
            if ((!pending_desc_space_b && overlap_index + 7'd1 <
                 descriptor_a_count_full) ||
                (pending_desc_space_b && overlap_index + 7'd1 <
                 {2'd0, descriptor_b_count_full}))
                descriptor_read_index = overlap_index[5:0] + 6'd1;
            else
                descriptor_read_index = overlap_index[5:0];
        end else if (map_state == MAP_READ)
            descriptor_read_index = map_index[5:0];
        else if (map_state == MAP_COMPARE) begin
            if ((!map_request_space_b && map_index + 7'd1 <
                 descriptor_a_count_full) ||
                (map_request_space_b && map_index + 7'd1 <
                 {2'd0, descriptor_b_count_full}))
                descriptor_read_index = map_index[5:0] + 6'd1;
            else
                descriptor_read_index = map_index[5:0];
        end

        descriptor_a_we = state == ST_DESC_STORE && !pending_desc_space_b;
        descriptor_b_we = state == ST_DESC_STORE && pending_desc_space_b;
        descriptor_a_waddr = descriptor_a_count_full[5:0];
        descriptor_b_waddr = descriptor_b_count_full[3:0];
        descriptor_a_wdata = {pending_desc_logical,
                              pending_desc_length,
                              pending_desc_file};
        descriptor_b_wdata = {pending_desc_logical[19:0],
                              pending_desc_length[20:0],
                              pending_desc_file};
    end

    always_ff @(posedge clk) begin
        if (descriptor_a_we)
            desc_a_mem[descriptor_a_waddr] <= descriptor_a_wdata;
        if (descriptor_b_we)
            desc_b_mem[descriptor_b_waddr] <= descriptor_b_wdata;
        desc_a_q <= desc_a_mem[descriptor_read_index];
        desc_b_q <= desc_b_mem[descriptor_read_index[3:0]];
    end

    // A single sequential engine serves runtime mapping after scan completion.
    // Scanner overlap checks use the same RAM read data while mapping is idle.
    always_ff @(posedge clk) begin
        map_rsp_valid <= 1'b0;
        if (reset || start) begin
            map_state <= MAP_IDLE;
            map_request_space_b <= 1'b0;
            map_request_logical <= 24'd0;
            map_index <= 7'd0;
            map_rsp_hit <= 1'b0;
            map_rsp_file_addr <= '0;
        end else begin
            case (map_state)
                MAP_IDLE: if (map_req_valid && map_req_ready) begin
                    map_request_space_b <= map_space_b;
                    map_request_logical <= map_logical_addr;
                    map_index <= 7'd0;
                    map_state <= MAP_READ;
                end
                MAP_READ: begin
                    if ((map_request_space_b && descriptor_b_count_full == 0) ||
                        (!map_request_space_b && descriptor_a_count_full == 0)) begin
                        map_rsp_valid <= 1'b1;
                        map_rsp_hit <= 1'b0;
                        map_rsp_file_addr <= '0;
                        map_state <= MAP_IDLE;
                    end else begin
                        map_state <= MAP_COMPARE;
                    end
                end
                MAP_COMPARE: begin
                    if (map_request_space_b) begin
                        if (map_request_logical[23:20] == 0 &&
                            map_request_logical[19:0] >= desc_b_start &&
                            {1'b0, map_request_logical[19:0]} <
                              ({1'b0, desc_b_start} + desc_b_length)) begin
                            map_rsp_valid <= 1'b1;
                            map_rsp_hit <= 1'b1;
                            map_rsp_file_addr <= desc_b_file +
                                (map_request_logical[19:0] - desc_b_start);
                            map_state <= MAP_IDLE;
                        end else if (map_index + 7'd1 >=
                                     {2'd0, descriptor_b_count_full}) begin
                            map_rsp_valid <= 1'b1;
                            map_rsp_hit <= 1'b0;
                            map_rsp_file_addr <= '0;
                            map_state <= MAP_IDLE;
                        end else begin
                            map_index <= map_index + 7'd1;
                            map_state <= MAP_COMPARE;
                        end
                    end else begin
                        if ({1'b0, map_request_logical} >=
                              {1'b0, desc_a_start} &&
                            {1'b0, map_request_logical} <
                              ({1'b0, desc_a_start} + desc_a_length)) begin
                            map_rsp_valid <= 1'b1;
                            map_rsp_hit <= 1'b1;
                            map_rsp_file_addr <= desc_a_file +
                                (map_request_logical - desc_a_start);
                            map_state <= MAP_IDLE;
                        end else if (map_index + 7'd1 >=
                                     descriptor_a_count_full) begin
                            map_rsp_valid <= 1'b1;
                            map_rsp_hit <= 1'b0;
                            map_rsp_file_addr <= '0;
                            map_state <= MAP_IDLE;
                        end else begin
                            map_index <= map_index + 7'd1;
                            map_state <= MAP_COMPARE;
                        end
                    end
                end
                default: map_state <= MAP_IDLE;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        done <= 1'b0;
        if (reset) begin
            state <= ST_IDLE;
            read_pending <= 1'b0;
            busy <= 1'b0;
            accepted <= 1'b0;
            classification <= VARIANT_NONE;
            reject_code <= REJECT_NONE;
            descriptors_committed <= 1'b0;
            descriptor_a_count_full <= 7'd0;
            descriptor_b_count_full <= 5'd0;
            original_size <= 32'd0;
            data_offset <= 32'd0;
            chip_clock <= 32'd0;
            loop_target <= 32'd0;
            loop_samples <= 32'd0;
            end_pc <= 32'd0;
            total_samples <= 32'd0;
            total_writes <= 32'd0;
            port0_writes <= 32'd0;
            port1_writes <= 32'd0;
            b_only_writes <= 32'd0;
            unknown_writes <= 32'd0;
            command_count <= 32'd0;
            variant_b <= 1'b0;
            dual_chip <= 1'b0;
            first_bad_valid <= 1'b0;
            first_bad_b_only <= 1'b0;
            first_bad_pc <= 32'd0;
            first_bad_port <= 1'b0;
            first_bad_address <= 8'd0;
            first_bad_data <= 8'd0;
            first_bad_sample <= 32'd0;
            first_bad_semantic <= 4'd0;
            first_bad_target <= 3'd0;
            loop_boundary_seen <= 1'b0;
            pending_desc_space_b <= 1'b0;
            pending_desc_logical <= 24'd0;
            pending_desc_length <= 25'd0;
            pending_desc_file <= '0;
            overlap_index <= 7'd0;
        end else begin
            if (mem_req && mem_ready)
                read_pending <= 1'b1;
            if (mem_valid && read_pending)
                read_pending <= 1'b0;

            if (start) begin
                state <= ST_HEADER;
                header_index <= 8'd0;
                read_pending <= 1'b0;
                busy <= 1'b1;
                accepted <= 1'b0;
                classification <= VARIANT_NONE;
                reject_code <= REJECT_NONE;
                descriptors_committed <= 1'b0;
                descriptor_a_count_full <= 7'd0;
                descriptor_b_count_full <= 5'd0;
                total_samples <= 32'd0;
                total_writes <= 32'd0;
                port0_writes <= 32'd0;
                port1_writes <= 32'd0;
                b_only_writes <= 32'd0;
                unknown_writes <= 32'd0;
                command_count <= 32'd0;
                first_bad_valid <= 1'b0;
                first_bad_b_only <= 1'b0;
                loop_boundary_seen <= 1'b0;
                end_pc <= 32'd0;
            end else begin
                case (state)
                    ST_IDLE: begin end
                    ST_HEADER: if (mem_valid && read_pending) begin
                        header[header_index[6:0]] <= mem_data;
                        if (header_index == 8'd127)
                            state <= ST_VALIDATE;
                        else
                            header_index <= header_index + 8'd1;
                    end
                    ST_VALIDATE: begin
                        original_size <= header32(4) + 32'd4;
                        data_offset <= (header32(8) < 32'h150) ?
                            32'h40 : 32'h34 + header32(52);
                        chip_clock <= header32(76) & 32'h3fff_ffff;
                        variant_b <= header[7'h4f][7];
                        dual_chip <= header[7'h4f][6];
                        loop_target <= (header32(28) == 0) ?
                            32'd0 : 32'h1c + header32(28);
                        scan_pc <= (header32(8) < 32'h150) ?
                            32'h40 : 32'h34 + header32(52);
                        if ({header[3], header[2], header[1], header[0]} != 32'h206d6756 ||
                            header32(4) + 32'd4 > physical_size ||
                            header32(4) + 32'd4 < 32'h40 ||
                            ((header32(8) < 32'h150 ? 32'h40 :
                              32'h34 + header32(52)) >= header32(4) + 32'd4) ||
                            ((header32(8) < 32'h150 ? 32'h40 :
                              32'h34 + header32(52)) < 32'h40) ||
                            ((header32(76) & 32'h3fff_ffff) == 0)) begin
                            reject_code <= REJECT_HEADER;
                            state <= ST_FATAL;
                        end else if (header[7'h4f][6]) begin
                            classification <= VARIANT_DUAL;
                            reject_code <= REJECT_DUAL;
                            state <= ST_FATAL;
                        end else begin
                            state <= ST_COMMAND;
                        end
                    end
                    ST_COMMAND: if (mem_valid && read_pending) begin
                        opcode <= mem_data;
                        command_pc <= scan_pc;
                        command_count <= command_count + 32'd1;
                        if (scan_pc == loop_target && loop_target != 0) begin
                            loop_samples <= total_samples;
                            loop_boundary_seen <= 1'b1;
                        end
                        scan_pc <= scan_pc + 32'd1;
                        case (mem_data)
                            8'h58, 8'h59: begin
                                pending_port <= mem_data[0];
                                state <= ST_WRITE_ADDR;
                            end
                            8'h61: state <= ST_WAIT_LO;
                            8'h62: begin
                                total_samples <= total_samples + 32'd735;
                                state <= ST_COMMAND;
                            end
                            8'h63: begin
                                total_samples <= total_samples + 32'd882;
                                state <= ST_COMMAND;
                            end
                            8'h66: begin
                                end_pc <= scan_pc;
                                state <= ST_FINISH;
                            end
                            8'h67: state <= ST_BLOCK_MARK;
                            8'h70, 8'h71, 8'h72, 8'h73,
                            8'h74, 8'h75, 8'h76, 8'h77,
                            8'h78, 8'h79, 8'h7a, 8'h7b,
                            8'h7c, 8'h7d, 8'h7e, 8'h7f: begin
                                total_samples <= total_samples +
                                    {28'd0, mem_data[3:0]} + 32'd1;
                                state <= ST_COMMAND;
                            end
                            default: begin
                                if (!first_bad_valid) begin
                                    first_bad_valid <= 1'b1;
                                    first_bad_pc <= scan_pc;
                                    first_bad_data <= mem_data;
                                    first_bad_sample <= total_samples;
                                end
                                reject_code <= REJECT_OPCODE;
                                state <= ST_FATAL;
                            end
                        endcase
                    end
                    ST_WRITE_ADDR: if (mem_valid && read_pending) begin
                        pending_address <= mem_data;
                        scan_pc <= scan_pc + 32'd1;
                        state <= ST_WRITE_DATA;
                    end
                    ST_WRITE_DATA: if (mem_valid && read_pending) begin
                        scan_pc <= scan_pc + 32'd1;
                        total_writes <= total_writes + 32'd1;
                        if (pending_port)
                            port1_writes <= port1_writes + 32'd1;
                        else
                            port0_writes <= port0_writes + 32'd1;
                        if (compat_b_only)
                            b_only_writes <= b_only_writes + 32'd1;
                        if (compat_unknown)
                            unknown_writes <= unknown_writes + 32'd1;
                        if (!compat_effective_accepted && !first_bad_valid) begin
                            first_bad_valid <= 1'b1;
                            first_bad_b_only <= compat_b_only;
                            first_bad_pc <= command_pc;
                            first_bad_port <= pending_port;
                            first_bad_address <= pending_address;
                            first_bad_data <= mem_data;
                            first_bad_sample <= total_samples;
                            first_bad_semantic <= compat_semantic;
                            first_bad_target <= compat_target;
                        end
                        state <= ST_COMMAND;
                    end
                    ST_WAIT_LO: if (mem_valid && read_pending) begin
                        wait_low <= mem_data;
                        scan_pc <= scan_pc + 32'd1;
                        state <= ST_WAIT_HI;
                    end
                    ST_WAIT_HI: if (mem_valid && read_pending) begin
                        total_samples <= total_samples +
                                         {16'd0, mem_data, wait_low};
                        scan_pc <= scan_pc + 32'd1;
                        state <= ST_COMMAND;
                    end
                    ST_BLOCK_MARK: if (mem_valid && read_pending) begin
                        scan_pc <= scan_pc + 32'd1;
                        if (mem_data != 8'h66) begin
                            reject_code <= REJECT_BLOCK;
                            state <= ST_FATAL;
                        end else state <= ST_BLOCK_TYPE;
                    end
                    ST_BLOCK_TYPE: if (mem_valid && read_pending) begin
                        block_type <= mem_data;
                        scan_pc <= scan_pc + 32'd1;
                        block_size_index <= 2'd0;
                        block_size_build <= 32'd0;
                        state <= ST_BLOCK_SIZE;
                    end
                    ST_BLOCK_SIZE: if (mem_valid && read_pending) begin
                        scan_pc <= scan_pc + 32'd1;
                        case (block_size_index)
                            2'd0: block_size_build[7:0] <= mem_data;
                            2'd1: block_size_build[15:8] <= mem_data;
                            2'd2: block_size_build[23:16] <= mem_data;
                            2'd3: begin
                                block_size <= {1'b0, mem_data[6:0], block_size_build[23:0]};
                                block_meta_index <= 3'd0;
                                block_rom_size <= 32'd0;
                                block_logical_start <= 32'd0;
                                if (mem_data[7] ||
                                    (block_type != 8'h82 && block_type != 8'h83)) begin
                                    reject_code <= REJECT_BLOCK;
                                    state <= ST_FATAL;
                                end else if ({1'b0, mem_data[6:0], block_size_build[23:0]} < 8) begin
                                    reject_code <= REJECT_BLOCK;
                                    state <= ST_FATAL;
                                end else state <= ST_BLOCK_META;
                            end
                        endcase
                        if (block_size_index != 2'd3)
                            block_size_index <= block_size_index + 2'd1;
                    end
                    ST_BLOCK_META: if (mem_valid && read_pending) begin
                        scan_pc <= scan_pc + 32'd1;
                        case (block_meta_index)
                            3'd0: block_rom_size[7:0] <= mem_data;
                            3'd1: block_rom_size[15:8] <= mem_data;
                            3'd2: block_rom_size[23:16] <= mem_data;
                            3'd3: block_rom_size[31:24] <= mem_data;
                            3'd4: block_logical_start[7:0] <= mem_data;
                            3'd5: block_logical_start[15:8] <= mem_data;
                            3'd6: block_logical_start[23:16] <= mem_data;
                            3'd7: begin
                                // Empty ROM blocks carry declarations only and
                                // do not create zero-length descriptors.
                                if ({1'b0, command_pc} + 33'd7 +
                                    {1'b0, block_size} >
                                    {1'b0, original_size}) begin
                                    reject_code <= REJECT_RANGE;
                                    state <= ST_FATAL;
                                end else if (block_size == 32'd8) begin
                                    if (block_type == 8'h82 &&
                                        (block_rom_size == 0 ||
                                         block_rom_size > 32'h0100_0000 ||
                                         mem_data != 0 ||
                                         {8'd0, block_logical_start[23:0]} >
                                           block_rom_size)) begin
                                        reject_code <= REJECT_RANGE;
                                        state <= ST_FATAL;
                                    end else begin
                                        scan_pc <= command_pc + 32'd7 + block_size;
                                        state <= ST_COMMAND;
                                    end
                                end else if ((block_type == 8'h82 &&
                                     (block_rom_size == 0 ||
                                      block_rom_size > 32'h0100_0000 ||
                                      mem_data != 0 ||
                                      ({1'b0, mem_data,
                                        block_logical_start[23:0]} +
                                       {1'b0, block_size - 32'd8}) >
                                      {1'b0, block_rom_size})) ||
                                    (block_type == 8'h83 &&
                                     (block_rom_size == 0 ||
                                      ({1'b0, mem_data,
                                        block_logical_start[23:0]} +
                                       {1'b0, block_size - 32'd8}) >
                                      {1'b0, block_rom_size} ||
                                      ({1'b0, mem_data,
                                        block_logical_start[23:0]} +
                                       {1'b0, block_size - 32'd8}) >
                                      33'd524288))) begin
                                    reject_code <= REJECT_RANGE;
                                    state <= ST_FATAL;
                                end else if ((block_type == 8'h82 &&
                                             descriptor_a_count_full >=
                                               MAX_A_DESCRIPTOR_COUNT) ||
                                            (block_type == 8'h83 &&
                                             descriptor_b_count_full >=
                                               MAX_B_DESCRIPTOR_COUNT)) begin
                                    reject_code <= REJECT_DESCRIPTOR;
                                    state <= ST_FATAL;
                                end else begin
                                    pending_desc_space_b <= block_type == 8'h83;
                                    pending_desc_logical <=
                                        block_logical_start[23:0];
                                    pending_desc_length <=
                                        block_size[24:0] - 25'd8;
                                    pending_desc_file <=
                                        command_pc[ADDR_WIDTH-1:0] +
                                        ADDR_WIDTH'(15);
                                    overlap_index <= 7'd0;
                                    if ((block_type == 8'h82 &&
                                         descriptor_a_count_full == 0) ||
                                        (block_type == 8'h83 &&
                                         descriptor_b_count_full == 0))
                                        state <= ST_DESC_STORE;
                                    else
                                        state <= ST_DESC_READ;
                                end
                            end
                        endcase
                        if (block_meta_index != 3'd7)
                            block_meta_index <= block_meta_index + 3'd1;
                    end
                    ST_DESC_READ: state <= ST_DESC_COMPARE;
                    ST_DESC_COMPARE: begin
                        if (pending_desc_space_b) begin
                            if (({1'b0, pending_desc_logical[19:0]} +
                                 pending_desc_length[20:0] >
                                 {1'b0, desc_b_start}) &&
                                ({1'b0, pending_desc_logical[19:0]} <
                                 ({1'b0, desc_b_start} + desc_b_length))) begin
                                reject_code <= REJECT_DESCRIPTOR;
                                state <= ST_FATAL;
                            end else if (overlap_index + 7'd1 >=
                                         {2'd0, descriptor_b_count_full}) begin
                                state <= ST_DESC_STORE;
                            end else begin
                                overlap_index <= overlap_index + 7'd1;
                                state <= ST_DESC_COMPARE;
                            end
                        end else begin
                            if (({1'b0, pending_desc_logical} +
                                 pending_desc_length >
                                 {1'b0, desc_a_start}) &&
                                ({1'b0, pending_desc_logical} <
                                 ({1'b0, desc_a_start} + desc_a_length))) begin
                                reject_code <= REJECT_DESCRIPTOR;
                                state <= ST_FATAL;
                            end else if (overlap_index + 7'd1 >=
                                         descriptor_a_count_full) begin
                                state <= ST_DESC_STORE;
                            end else begin
                                overlap_index <= overlap_index + 7'd1;
                                state <= ST_DESC_COMPARE;
                            end
                        end
                    end
                    ST_DESC_STORE: begin
                        if (pending_desc_space_b)
                            descriptor_b_count_full <=
                                descriptor_b_count_full + 5'd1;
                        else
                            descriptor_a_count_full <=
                                descriptor_a_count_full + 7'd1;
                        scan_pc <= command_pc + 32'd7 + block_size;
                        state <= ST_COMMAND;
                    end
                    ST_FINISH: begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        if (loop_target != 0 && !loop_boundary_seen) begin
                            accepted <= 1'b0;
                            reject_code <= REJECT_HEADER;
                        end else if (first_bad_valid) begin
                            accepted <= 1'b0;
                            classification <= variant_b ? VARIANT_B_REQUIRED : VARIANT_STANDARD;
                            reject_code <= first_bad_b_only ? REJECT_B_REQUIRED : REJECT_REGISTER;
                        end else begin
                            accepted <= 1'b1;
                            classification <= variant_b ? VARIANT_B_COMPAT : VARIANT_STANDARD;
                            reject_code <= REJECT_NONE;
                            descriptors_committed <= 1'b1;
                            if (loop_boundary_seen)
                                loop_samples <= total_samples - loop_samples;
                        end
                        state <= ST_DONE;
                    end
                    ST_FATAL: begin
                        busy <= 1'b0;
                        accepted <= 1'b0;
                        done <= 1'b1;
                        state <= ST_DONE;
                    end
                    ST_DONE: begin end
                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule
