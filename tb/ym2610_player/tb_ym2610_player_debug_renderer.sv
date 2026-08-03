`timescale 1ns/1ps

module tb_ym2610_player_debug_renderer;
    logic enable = 1'b1;
    logic pcm_page = 1'b0;
    logic [9:0] h_count = 10'd0;
    logic [8:0] v_count = 9'd4;
    logic drawing_active = 1'b1;
    logic [3:0] load_state = 4'ha;
    logic [31:0] original_size = 32'h1234_5678;
    logic raw_variant_b = 1'b1;
    logic [3:0] classification = 4'hc;
    logic [7:0] reject_code = 8'hde;
    logic [31:0] first_bad_pc = 32'h89ab_cdef;
    logic first_bad_port = 1'b1;
    logic [7:0] first_bad_address = 8'h67;
    logic [7:0] first_bad_data = 8'h45;
    logic [31:0] parser_pc = 32'h1020_3040;
    logic [7:0] parser_opcode = 8'h59;
    logic [31:0] wait_remaining = 32'h5060_7080;
    logic [31:0] port0_writes = 32'h1122_3344;
    logic [31:0] port1_writes = 32'h5566_7788;
    logic [31:0] start_count = 32'h99aa_bbcc;
    logic [31:0] loop_count = 32'hddee_ff00;
    logic [31:0] unsupported_pc = 32'h1357_9bdf;
    logic [7:0] unsupported_opcode = 8'h50;
    logic [3:0] descriptor_a_count = 4'h5;
    logic [3:0] descriptor_b_count = 4'h6;
    logic [31:0] pcm_requests = 32'h0102_0304;
    logic [31:0] pcm_responses = 32'h0506_0708;
    logic [31:0] adpcma_requests = 32'h9999_aaaa;
    logic [31:0] adpcmb_requests = 32'hbbbb_cccc;
    logic [31:0] adpcma_fetch_requests = 32'h1111_2222;
    logic [31:0] adpcma_fetch_responses = 32'h3333_4444;
    logic [31:0] adpcmb_fetch_requests = 32'h5555_6666;
    logic [31:0] adpcmb_fetch_responses = 32'h7777_8888;
    logic [19:0] pcm_last_address = 20'h01234;
    logic [19:0] adpcma_last_address = 20'habcde;
    logic [19:0] adpcmb_last_address = 20'h54321;
    logic [6:0] pcm_occupancy = 7'h5a;
    logic adpcma_underflow = 1'b1;
    logic adpcmb_underflow = 1'b0;
    logic stale_response = 1'b1;
    logic owner_mismatch = 1'b0;
    logic fatal_active = 1'b0;
    logic [7:0] fatal_code = 8'he1;
    logic [5:0] fatal_error_flags = 6'h2d;
    logic [4:0] scanner_state = 5'h12;
    logic [3:0] parser_state = 4'h9;
    logic [1:0] memory_held_owner = 2'd2;
    logic [1:0] memory_outstanding_owner = 2'd1;
    logic memory_request = 1'b1;
    logic memory_request_held = 1'b1;
    logic memory_outstanding = 1'b1;
    logic ddram_busy = 1'b1;
    logic [22:0] last_memory_accept_addr = 23'h123456;
    logic [22:0] last_memory_response_addr = 23'h654321;
    logic [7:0] load_generation = 8'h5a;
    logic [7:0] last_accept_generation = 8'h6b;
    logic [7:0] last_response_generation = 8'h7c;
    logic [2:0] last_reset_source = 3'd3;
    logic [15:0] video_reset_edge_count = 16'h1234;
    logic pll_unlock_observed = 1'b0;
    logic [15:0] video_frame_heartbeat = 16'h2345;
    logic [15:0] video_line_heartbeat = 16'h3456;
    logic [31:0] player_heartbeat = 32'h4567_89ab;
    logic [31:0] ddr_heartbeat = 32'h5678_9abc;
    logic [31:0] scanner_start_count = 32'd1;
    logic [31:0] parser_command_count = 32'h6789_abcd;
    logic [15:0] upload_fifo_debug = 16'h0080;
    logic upload_partial_valid = 1'b0;
    logic pcm_request_held = 1'b1;
    logic pcm_response_pending = 1'b0;
    logic pcm_held_space_b = 1'b0;
    logic [15:0] peak_l = 16'ha55a;
    logic [15:0] peak_r = 16'h5aa5;
    logic background;
    logic text_pixel;
    integer checks = 0;
    integer failures = 0;
    integer code;
    integer line;
    integer column_index;
    integer pixel_x;
    integer pixel_y;

    ym2610_player_debug_renderer dut (
        .enable(enable), .pcm_page(pcm_page), .h_count(h_count),
        .v_count(v_count), .drawing_active(drawing_active),
        .load_state(load_state), .original_size(original_size),
        .raw_variant_b(raw_variant_b), .classification(classification),
        .reject_code(reject_code), .first_bad_pc(first_bad_pc),
        .first_bad_port(first_bad_port),
        .first_bad_address(first_bad_address), .first_bad_data(first_bad_data),
        .parser_pc(parser_pc), .parser_opcode(parser_opcode),
        .wait_remaining(wait_remaining), .port0_writes(port0_writes),
        .port1_writes(port1_writes), .start_count(start_count),
        .loop_count(loop_count), .unsupported_pc(unsupported_pc),
        .unsupported_opcode(unsupported_opcode),
        .descriptor_a_count(descriptor_a_count),
        .descriptor_b_count(descriptor_b_count), .pcm_requests(pcm_requests),
        .pcm_responses(pcm_responses), .adpcma_requests(adpcma_requests),
        .adpcmb_requests(adpcmb_requests),
        .adpcma_fetch_requests(adpcma_fetch_requests),
        .adpcma_fetch_responses(adpcma_fetch_responses),
        .adpcmb_fetch_requests(adpcmb_fetch_requests),
        .adpcmb_fetch_responses(adpcmb_fetch_responses),
        .pcm_last_address(pcm_last_address),
        .adpcma_last_address(adpcma_last_address),
        .adpcmb_last_address(adpcmb_last_address),
        .pcm_occupancy(pcm_occupancy),
        .adpcma_underflow(adpcma_underflow),
        .adpcmb_underflow(adpcmb_underflow),
        .stale_response(stale_response), .owner_mismatch(owner_mismatch),
        .fatal_active(fatal_active), .fatal_code(fatal_code),
        .fatal_error_flags(fatal_error_flags),
        .scanner_state(scanner_state), .parser_state(parser_state),
        .memory_held_owner(memory_held_owner),
        .memory_outstanding_owner(memory_outstanding_owner),
        .memory_request(memory_request),
        .memory_request_held(memory_request_held),
        .memory_outstanding(memory_outstanding),
        .ddram_busy(ddram_busy),
        .last_memory_accept_addr(last_memory_accept_addr),
        .last_memory_response_addr(last_memory_response_addr),
        .load_generation(load_generation),
        .last_accept_generation(last_accept_generation),
        .last_response_generation(last_response_generation),
        .last_reset_source(last_reset_source),
        .video_reset_edge_count(video_reset_edge_count),
        .pll_unlock_observed(pll_unlock_observed),
        .video_frame_heartbeat(video_frame_heartbeat),
        .video_line_heartbeat(video_line_heartbeat),
        .player_heartbeat(player_heartbeat), .ddr_heartbeat(ddr_heartbeat),
        .scanner_start_count(scanner_start_count),
        .parser_command_count(parser_command_count),
        .upload_fifo_debug(upload_fifo_debug),
        .upload_partial_valid(upload_partial_valid),
        .pcm_request_held(pcm_request_held),
        .pcm_response_pending(pcm_response_pending),
        .pcm_held_space_b(pcm_held_space_b),
        .peak_l(peak_l), .peak_r(peak_r), .background(background),
        .text_pixel(text_pixel)
    );

    function automatic [7:0] expected_hex(input logic [3:0] value);
        expected_hex = value < 10 ? ("0" + value) : ("A" + value - 10);
    endfunction

    task automatic check(input logic condition, input string message);
        begin
            checks = checks + 1;
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %s page=%0d x=%0d y=%0d row=%0d col=%0d char=%02x",
                         message, pcm_page, h_count, v_count, dut.row,
                         dut.column, dut.character);
            end
        end
    endtask

    task automatic set_cell(input integer row_number, input integer col_number);
        begin
            h_count = col_number * 6;
            v_count = 4 + row_number * 8;
            #1;
        end
    endtask

    task automatic check_known(input string message);
        begin
            check(!$isunknown({background, text_pixel, dut.character,
                               dut.glyph_x, dut.glyph_y, dut.column, dut.row,
                               dut.glyph_x_full, dut.glyph_y_full,
                               dut.row_value, dut.label0, dut.label1,
                               dut.row_valid, dut.nibble, dut.shifted_value}),
                  message);
        end
    endtask

    task automatic check_heading(input logic page,
                                 input [7:0] page1,
                                 input [7:0] page2,
                                 input [7:0] page3);
        begin
            pcm_page = page;
            set_cell(0, 0); check(dut.character == "Y", "heading Y");
            set_cell(0, 1); check(dut.character == "M", "heading M");
            set_cell(0, 2); check(dut.character == "2", "heading 2");
            set_cell(0, 3); check(dut.character == "6", "heading 6");
            set_cell(0, 4); check(dut.character == "1", "heading 1");
            set_cell(0, 5); check(dut.character == "0", "heading 0");
            set_cell(0, 6); check(dut.character == " ", "heading spacer");
            set_cell(0, 7); check(dut.character == page1, "heading page char 1");
            set_cell(0, 8); check(dut.character == page2, "heading page char 2");
            set_cell(0, 9); check(dut.character == page3, "heading page char 3");
        end
    endtask

    task automatic check_row(input logic page,
                             input integer row_number,
                             input [7:0] expected_label0,
                             input [7:0] expected_label1,
                             input [31:0] expected_value,
                             input logic expected_valid);
        begin
            pcm_page = page;
            set_cell(row_number, 0);
            check(dut.row_valid == expected_valid, "row valid");
            check(dut.row_value == expected_value, "row value");
            check(dut.character == (expected_valid ? expected_label0 : " "),
                  "label column 0");
            set_cell(row_number, 1);
            check(dut.character == (expected_valid ? expected_label1 : " "),
                  "label column 1");
            set_cell(row_number, 2);
            check(dut.character == " ", "label/value spacer");
            set_cell(row_number, 3);
            check(dut.character == (expected_valid ?
                                     expected_hex(expected_value[31:28]) : " "),
                  "value high nibble");
            set_cell(row_number, 10);
            check(dut.character == (expected_valid ?
                                     expected_hex(expected_value[3:0]) : " "),
                  "value low nibble");
        end
    endtask

    task automatic scan_page(input logic page);
        begin
            pcm_page = page;
            for (line = 0; line <= 17; line = line + 1) begin
                for (column_index = 0; column_index <= 10;
                     column_index = column_index + 1) begin
                    for (pixel_y = 0; pixel_y < 8; pixel_y = pixel_y + 1) begin
                        for (pixel_x = 0; pixel_x < 6; pixel_x = pixel_x + 1) begin
                            h_count = column_index * 6 + pixel_x;
                            v_count = 4 + line * 8 + pixel_y;
                            #1;
                            check_known("line 0-17 pixel X/Z-free");
                            check(background === 1'b1,
                                  "enabled active background");
                        end
                    end
                end
            end
        end
    endtask

    initial begin
        #1;
        check_heading(1'b0, "P", "A", "R");
        check_row(0, 1,  "L", "S", 32'h0000_000a, 1);
        check_row(0, 2,  "S", "Z", 32'h1234_5678, 1);
        check_row(0, 3,  "R", "V", 32'h0000_0001, 1);
        check_row(0, 4,  "C", "L", 32'h0000_000c, 1);
        check_row(0, 5,  "R", "J", 32'h0000_00de, 1);
        check_row(0, 6,  "B", "P", 32'h89ab_cdef, 1);
        check_row(0, 7,  "B", "D", 32'h0001_6745, 1);
        check_row(0, 8,  "P", "C", 32'h1020_3040, 1);
        check_row(0, 9,  "O", "P", 32'h0000_0059, 1);
        check_row(0, 10, "W", "T", 32'h5060_7080, 1);
        check_row(0, 11, "P", "0", 32'h1122_3344, 1);
        check_row(0, 12, "P", "1", 32'h5566_7788, 1);
        check_row(0, 13, "S", "T", 32'h99aa_bbcc, 1);
        check_row(0, 14, "L", "P", 32'hddee_ff00, 1);
        check_row(0, 15, "U", "P", 32'h1357_9bdf, 1);
        check_row(0, 16, "U", "O", 32'h0000_0050, 1);
        check_row(0, 17, "S", "S", 32'h0000_0012, 1);

        check_heading(1'b1, "P", "C", "M");
        check_row(1, 1,  "D", "A", 32'h0000_0005, 1);
        check_row(1, 2,  "D", "B", 32'h0000_0006, 1);
        check_row(1, 3,  "A", "Q", 32'h1111_2222, 1);
        check_row(1, 4,  "A", "S", 32'h3333_4444, 1);
        check_row(1, 5,  "B", "Q", 32'h5555_6666, 1);
        check_row(1, 6,  "B", "S", 32'h7777_8888, 1);
        check_row(1, 7,  "A", "R", 32'h9999_aaaa, 1);
        check_row(1, 8,  "B", "R", 32'hbbbb_cccc, 1);
        check_row(1, 9,  "L", "A", 32'h000a_bcde, 1);
        check_row(1, 10, "L", "B", 32'h0005_4321, 1);
        check_row(1, 11, "O", "C", 32'h0000_005a, 1);
        check_row(1, 12, "U", "A", 32'h0000_0001, 1);
        check_row(1, 13, "U", "B", 32'h0000_0000, 1);
        check_row(1, 14, "S", "T", 32'h0000_0001, 1);
        check_row(1, 15, "O", "M", 32'h0000_0000, 1);
        check_row(1, 16, "P", "L", 32'h0000_a55a, 1);
        check_row(1, 17, "P", "R", 32'h0000_5aa5, 1);

        // Exercise every reject/error code and every hexadecimal glyph.
        pcm_page = 1'b0;
        for (code = 0; code < 256; code = code + 1) begin
            reject_code = code[7:0];
            set_cell(5, 9);
            check(dut.character == expected_hex(code[7:4]),
                  "reject code high digit");
            set_cell(5, 10);
            check(dut.character == expected_hex(code[3:0]),
                  "reject code low digit");
        end

        // Debug View=Off must produce no overlay, including a path where nibble
        // is not otherwise assigned by the rendering overrides.
        enable = 1'b0;
        set_cell(0, 0);
        check(background === 1'b0, "Debug View Off background");
        check(text_pixel === 1'b0, "Debug View Off text");
        check(dut.nibble === 4'd0, "Debug View Off temporary default");
        check_known("Debug View Off X/Z-free");

        // A fatal page overrides Debug View=Off and retains the minimum
        // hardware recorder fields needed for recovery without power cycling.
        fatal_active = 1'b1;
        check_heading(1'b0, "F", "A", "T");
        check_row(0, 1, "F", "T", 32'h0000_00e1, 1);
        check_row(0, 5, "O", "W", 32'h0000_00f9, 1);
        check_row(0, 10, "G", "N", 32'h005a_6b7c, 1);
        check(background === 1'b1, "fatal overrides Debug View Off");
        fatal_active = 1'b0;

        // drawing_active is the active-raster clip. Coordinates outside the
        // native raster remain fully defined and emit neither background nor text.
        enable = 1'b1;
        drawing_active = 1'b0;
        h_count = 10'd1023;
        v_count = 9'd511;
        #1;
        check(background === 1'b0, "active raster outside background");
        check(text_pixel === 1'b0, "active raster outside text");
        check(dut.nibble === 4'd0, "active raster outside temporary default");
        check_known("active raster outside X/Z-free");

        // Reset-state values are all zero at the renderer boundary. The module
        // has no state or reset input and must still be purely combinational.
        drawing_active = 1'b1;
        load_state = 0;
        original_size = 0;
        raw_variant_b = 0;
        classification = 0;
        reject_code = 0;
        first_bad_pc = 0;
        first_bad_port = 0;
        first_bad_address = 0;
        first_bad_data = 0;
        parser_pc = 0;
        parser_opcode = 0;
        wait_remaining = 0;
        port0_writes = 0;
        port1_writes = 0;
        start_count = 0;
        loop_count = 0;
        unsupported_pc = 0;
        unsupported_opcode = 0;
        set_cell(5, 10);
        check(dut.character == "0", "reset-state reject digit");
        check_known("reset-state X/Z-free");

        // Restore nonzero fields before the exhaustive two-page raster scan.
        load_state = 4'ha;
        original_size = 32'h1234_5678;
        raw_variant_b = 1;
        classification = 4'hc;
        reject_code = 8'hde;
        first_bad_pc = 32'h89ab_cdef;
        first_bad_port = 1;
        first_bad_address = 8'h67;
        first_bad_data = 8'h45;
        parser_pc = 32'h1020_3040;
        parser_opcode = 8'h59;
        wait_remaining = 32'h5060_7080;
        port0_writes = 32'h1122_3344;
        port1_writes = 32'h5566_7788;
        start_count = 32'h99aa_bbcc;
        loop_count = 32'hddee_ff00;
        unsupported_pc = 32'h1357_9bdf;
        unsupported_opcode = 8'h50;
        scan_page(1'b0);
        scan_page(1'b1);

        if (failures == 0) begin
            $display("YM2610_DEBUG_RENDERER parser_rows=17 pcm_rows=18 hex=16 reject_codes=256 off=PASS outside=PASS reset=PASS checks=%0d result=PASS",
                     checks);
            $finish;
        end
        $fatal(1, "YM2610 debug renderer: %0d of %0d checks failed",
               failures, checks);
    end
endmodule
