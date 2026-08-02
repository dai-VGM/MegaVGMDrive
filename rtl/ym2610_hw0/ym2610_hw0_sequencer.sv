`timescale 1ns/1ps

module ym2610_hw0_sequencer #(
    parameter bit FAST_SIM = 1'b0,
    parameter integer BOOT_SAMPLES = 32768
) (
    input  logic               clk,
    input  logic               reset,
    input  logic               core_ready,
    input  logic               audio_zero,
    input  logic               sample_strobe,
    input  logic        [8:0]  chip_cycle_mod432,
    input  logic        [7:0]  bus_dout,
    input  logic               adpcmb_eos,
    input  logic               adpcmb_active,
    output logic        [1:0]  bus_addr,
    output logic        [7:0]  bus_din,
    output logic               bus_cs_n,
    output logic               bus_wr_n,
    output logic        [3:0]  test_phase,
    output logic        [7:0]  microcode_index,
    output logic       [31:0]  accepted_write_count,
    output logic               busy_timeout,
    output logic               write_while_busy,
    output logic       [15:0]  sequence_restart_count,
    output logic               measurement_active,
    output logic        [3:0]  measurement_phase,
    output logic               halted
);
    localparam logic [4:0] P_SILENCE   = 5'd0;
    localparam logic [4:0] P_FM        = 5'd1;
    localparam logic [4:0] P_FM_OFF    = 5'd2;
    localparam logic [4:0] P_SSG       = 5'd3;
    localparam logic [4:0] P_SSG_OFF   = 5'd4;
    localparam logic [4:0] P_A0_CFG    = 5'd5;
    localparam logic [4:0] P_A0_ON     = 5'd6;
    localparam logic [4:0] P_A0_OFF    = 5'd7;
    localparam logic [4:0] P_A6_CFG    = 5'd8;
    localparam logic [4:0] P_A6_ON     = 5'd9;
    localparam logic [4:0] P_A6_OFF    = 5'd10;
    localparam logic [4:0] P_B_STEREO  = 5'd11;
    localparam logic [4:0] P_B_LEFT    = 5'd12;
    localparam logic [4:0] P_B_RIGHT   = 5'd13;
    localparam logic [4:0] P_B_SHORT   = 5'd14;
    localparam logic [4:0] P_B_START   = 5'd15;
    localparam logic [4:0] P_B_RESET   = 5'd16;

    localparam logic [5:0] H_BOOT          = 6'd0;
    localparam logic [5:0] H_COLD          = 6'd1;
    localparam logic [5:0] H_FM_CFG        = 6'd2;
    localparam logic [5:0] H_FM_ATTACK     = 6'd3;
    localparam logic [5:0] H_FM_MEASURE    = 6'd4;
    localparam logic [5:0] H_FM_HOLD       = 6'd5;
    localparam logic [5:0] H_FM_OFF        = 6'd6;
    localparam logic [5:0] H_SILENCE_1     = 6'd7;
    localparam logic [5:0] H_SSG_CFG       = 6'd8;
    localparam logic [5:0] H_SSG_ATTACK    = 6'd9;
    localparam logic [5:0] H_SSG_MEASURE   = 6'd10;
    localparam logic [5:0] H_SSG_HOLD      = 6'd11;
    localparam logic [5:0] H_SSG_OFF       = 6'd12;
    localparam logic [5:0] H_SILENCE_2     = 6'd13;
    localparam logic [5:0] H_A0_CFG        = 6'd14;
    localparam logic [5:0] H_A0_ALIGN      = 6'd15;
    localparam logic [5:0] H_A0_WAIT       = 6'd16;
    localparam logic [5:0] H_A0_OFF        = 6'd17;
    localparam logic [5:0] H_SILENCE_3     = 6'd18;
    localparam logic [5:0] H_A6_CFG        = 6'd19;
    localparam logic [5:0] H_A6_ALIGN      = 6'd20;
    localparam logic [5:0] H_A6_WAIT       = 6'd21;
    localparam logic [5:0] H_A6_OFF        = 6'd22;
    localparam logic [5:0] H_SILENCE_4     = 6'd23;
    localparam logic [5:0] H_B_CFG         = 6'd24;
    localparam logic [5:0] H_B_ALIGN       = 6'd25;
    localparam logic [5:0] H_B_WAIT        = 6'd26;
    localparam logic [5:0] H_B_RESET       = 6'd27;
    localparam logic [5:0] H_SILENCE_5     = 6'd28;
    localparam logic [5:0] H_L_CFG         = 6'd29;
    localparam logic [5:0] H_L_ALIGN       = 6'd30;
    localparam logic [5:0] H_L_WAIT        = 6'd31;
    localparam logic [5:0] H_L_RESET       = 6'd32;
    localparam logic [5:0] H_PAN_SILENCE   = 6'd33;
    localparam logic [5:0] H_R_CFG         = 6'd34;
    localparam logic [5:0] H_R_ALIGN       = 6'd35;
    localparam logic [5:0] H_R_WAIT        = 6'd36;
    localparam logic [5:0] H_R_RESET       = 6'd37;
    localparam logic [5:0] H_SILENCE_6     = 6'd38;
    localparam logic [5:0] H_SHORT_CFG     = 6'd39;
    localparam logic [5:0] H_SHORT_ALIGN1  = 6'd40;
    localparam logic [5:0] H_SHORT_WAIT1   = 6'd41;
    localparam logic [5:0] H_SHORT_SILENCE = 6'd42;
    localparam logic [5:0] H_SHORT_ALIGN2  = 6'd43;
    localparam logic [5:0] H_SHORT_WAIT2   = 6'd44;
    localparam logic [5:0] H_FINAL_STOP    = 6'd45;
    localparam logic [5:0] H_FINAL_SILENCE = 6'd46;

    localparam logic [3:0] B_IDLE          = 4'd0;
    localparam logic [3:0] B_CLEAR_SETUP   = 4'd1;
    localparam logic [3:0] B_CLEAR_SAMPLE  = 4'd2;
    localparam logic [3:0] B_ADDR_SETUP    = 4'd3;
    localparam logic [3:0] B_ADDR_CAPTURE  = 4'd4;
    localparam logic [3:0] B_DATA_CHECK    = 4'd5;
    localparam logic [3:0] B_DATA_SAMPLE   = 4'd6;
    localparam logic [3:0] B_DATA_CAPTURE  = 4'd7;
    localparam logic [3:0] B_ASSERT_SETUP  = 4'd8;
    localparam logic [3:0] B_ASSERT_SAMPLE = 4'd9;
    localparam logic [3:0] B_DONE_SETUP    = 4'd10;
    localparam logic [3:0] B_DONE_SAMPLE   = 4'd11;

    localparam integer COLD_SAMPLES = BOOT_SAMPLES;
    localparam integer SILENCE_SAMPLES = FAST_SIM ? 512 : 24576;
    localparam integer LONG_SAMPLES = FAST_SIM ? 4096 : 81920;
    localparam integer PAN_SAMPLES = FAST_SIM ? 4096 : 53248;
    localparam integer A6_SAMPLES = FAST_SIM ? 8192 : 81920;
    // Phase 4A starts its 4096-public-sample goal after START has returned,
    // while its active-lane hash already contains the boundary sample.  The
    // published anchor therefore contains 4097 active samples.  Preserve that
    // exact event contract in simulation; the hardware hold remains audible.
    localparam integer B_SAMPLES = FAST_SIM ? 4097 : 81920;

    logic [5:0] high_state;
    logic [4:0] program_id;
    logic       program_active;
    logic       program_done;
    logic [3:0] bus_state;
    logic       txn_active;
    logic [16:0] current_word;
    logic [15:0] busy_watchdog;
    logic        sample_d;
    logic [31:0] sample_count;
    logic [31:0] natural_watchdog;
    logic        natural_armed;

    wire sample_rise = sample_strobe && !sample_d;

    function automatic integer program_length(input logic [4:0] id);
        begin
            case (id)
                P_SILENCE:  program_length = 18;
                P_FM:       program_length = 33;
                P_FM_OFF:   program_length = 1;
                P_SSG:      program_length = 4;
                P_SSG_OFF:  program_length = 2;
                P_A0_CFG:   program_length = 11;
                P_A0_ON:    program_length = 1;
                P_A0_OFF:   program_length = 1;
                P_A6_CFG:   program_length = 31;
                P_A6_ON:    program_length = 1;
                P_A6_OFF:   program_length = 1;
                P_B_STEREO,
                P_B_LEFT,
                P_B_RIGHT,
                P_B_SHORT:  program_length = 10;
                P_B_START:  program_length = 1;
                P_B_RESET:  program_length = 2;
                default:    program_length = 0;
            endcase
        end
    endfunction

    function automatic [16:0] program_word(
        input logic [4:0] id,
        input logic [7:0] index
    );
        integer op_group;
        integer op_step;
        integer voice;
        integer voice_step;
        logic [7:0] op_offset;
        logic [7:0] op_data;
        logic [7:0] pan;
        logic [7:0] end_page;
        begin
            program_word = {1'b0, 8'h00, 8'h00};
            case (id)
                P_SILENCE: begin
                    case (index)
                        0: program_word={1'b0,8'h28,8'h00};
                        1: program_word={1'b0,8'h28,8'h01};
                        2: program_word={1'b0,8'h28,8'h02};
                        3: program_word={1'b0,8'h28,8'h04};
                        4: program_word={1'b0,8'h28,8'h05};
                        5: program_word={1'b0,8'h28,8'h06};
                        6: program_word={1'b0,8'h22,8'h00};
                        7: program_word={1'b0,8'h27,8'h00};
                        8: program_word={1'b0,8'h2b,8'h00};
                        9: program_word={1'b0,8'h08,8'h00};
                       10: program_word={1'b0,8'h09,8'h00};
                       11: program_word={1'b0,8'h0a,8'h00};
                       12: program_word={1'b0,8'h06,8'h00};
                       13: program_word={1'b0,8'h07,8'h3f};
                       14: program_word={1'b1,8'h00,8'hbf};
                       15: program_word={1'b0,8'h10,8'h01};
                       16: program_word={1'b0,8'h1c,8'h80};
                       17: program_word={1'b0,8'h10,8'h00};
                       default: ;
                    endcase
                end
                P_FM: begin
                    case (index)
                        0: program_word={1'b0,8'ha5,8'h22};
                        1: program_word={1'b0,8'ha1,8'h00};
                        2: program_word={1'b0,8'hb1,8'h07};
                        3: program_word={1'b0,8'hb5,8'hc0};
                        32: program_word={1'b0,8'h28,8'h11};
                        default: begin
                            op_group = (index - 4) / 7;
                            op_step = (index - 4) % 7;
                            case (op_group)
                                0: op_offset = 8'h00;
                                1: op_offset = 8'h08;
                                2: op_offset = 8'h04;
                                default: op_offset = 8'h0c;
                            endcase
                            case (op_step)
                                0: op_data = 8'h01;
                                1: op_data = op_group == 0 ? 8'h00 : 8'h7f;
                                2: op_data = 8'h1f;
                                3: op_data = 8'h00;
                                4: op_data = 8'h00;
                                5: op_data = 8'haf;
                                default: op_data = 8'h00;
                            endcase
                            case (op_step)
                                0: program_word={1'b0,8'h31+op_offset,op_data};
                                1: program_word={1'b0,8'h41+op_offset,op_data};
                                2: program_word={1'b0,8'h51+op_offset,op_data};
                                3: program_word={1'b0,8'h61+op_offset,op_data};
                                4: program_word={1'b0,8'h71+op_offset,op_data};
                                5: program_word={1'b0,8'h81+op_offset,op_data};
                                default: program_word={1'b0,8'h91+op_offset,op_data};
                            endcase
                        end
                    endcase
                end
                P_FM_OFF: program_word={1'b0,8'h28,8'h01};
                P_SSG: begin
                    case(index)
                        0: program_word={1'b0,8'h00,8'h20};
                        1: program_word={1'b0,8'h01,8'h00};
                        2: program_word={1'b0,8'h07,8'h3e};
                        default: program_word={1'b0,8'h08,8'h0f};
                    endcase
                end
                P_SSG_OFF: program_word = index == 0 ?
                    {1'b0,8'h08,8'h00} : {1'b0,8'h07,8'h3f};
                P_A0_CFG: begin
                    case(index)
                        0: program_word={1'b1,8'h10,8'h00};
                        1: program_word={1'b1,8'h18,8'h00};
                        2: program_word={1'b1,8'h20,8'h0f};
                        3: program_word={1'b1,8'h28,8'h00};
                        4: program_word={1'b1,8'h01,8'h3f};
                        5: program_word={1'b1,8'h08,8'hf5};
                        6: program_word={1'b1,8'h09,8'h00};
                        7: program_word={1'b1,8'h0a,8'h00};
                        8: program_word={1'b1,8'h0b,8'h00};
                        9: program_word={1'b1,8'h0c,8'h00};
                        default: program_word={1'b1,8'h0d,8'h00};
                    endcase
                end
                P_A0_ON:  program_word={1'b1,8'h00,8'h01};
                P_A0_OFF: program_word={1'b1,8'h00,8'h81};
                P_A6_CFG: begin
                    if (index == 0) program_word={1'b1,8'h01,8'h3f};
                    else begin
                        voice = (index - 1) / 5;
                        voice_step = (index - 1) % 5;
                        case (voice_step)
                            0: program_word={1'b1,8'h10+voice[7:0],voice[7:0]};
                            1: program_word={1'b1,8'h18+voice[7:0],8'h00};
                            2: program_word={1'b1,8'h20+voice[7:0],voice[7:0]+8'h0f};
                            3: program_word={1'b1,8'h28+voice[7:0],8'h00};
                            default: program_word={1'b1,8'h08+voice[7:0],8'hc0};
                        endcase
                    end
                end
                P_A6_ON:  program_word={1'b1,8'h00,8'h3f};
                P_A6_OFF: program_word={1'b1,8'h00,8'hbf};
                P_B_STEREO,
                P_B_LEFT,
                P_B_RIGHT,
                P_B_SHORT: begin
                    pan = id == P_B_LEFT ? 8'h80 :
                          id == P_B_RIGHT ? 8'h40 : 8'hc0;
                    end_page = id == P_B_SHORT ? 8'h20 : 8'h4f;
                    case(index)
                        0: program_word={1'b0,8'h10,8'h01};
                        1: program_word={1'b0,8'h10,8'h00};
                        2: program_word={1'b0,8'h11,pan};
                        3: program_word={1'b0,8'h12,8'h20};
                        4: program_word={1'b0,8'h13,8'h00};
                        5: program_word={1'b0,8'h14,end_page};
                        6: program_word={1'b0,8'h15,8'h00};
                        7: program_word={1'b0,8'h19,8'h00};
                        8: program_word={1'b0,8'h1a,8'h80};
                        default: program_word={1'b0,8'h1b,8'hff};
                    endcase
                end
                P_B_START: program_word={1'b0,8'h10,8'h80};
                P_B_RESET: program_word = index == 0 ?
                    {1'b0,8'h10,8'h01} : {1'b0,8'h10,8'h00};
                default: ;
            endcase
        end
    endfunction

    task automatic drive_idle;
        begin
            bus_addr <= 2'b00;
            bus_din <= 8'h00;
            bus_cs_n <= 1'b1;
            bus_wr_n <= 1'b1;
        end
    endtask

    task automatic drive_status;
        begin
            bus_addr <= 2'b00;
            bus_din <= 8'h00;
            bus_cs_n <= 1'b0;
            bus_wr_n <= 1'b1;
        end
    endtask

    task automatic start_program(input logic [4:0] id);
        begin
            program_id <= id;
            microcode_index <= 8'd0;
            program_active <= 1'b1;
        end
    endtask

    // The synthesizable bus-drive tasks below assign this process's outputs.
    // Use a plain clocked process so lint tools do not misclassify task-body
    // assignments as separate always_ff drivers.
    always @(posedge clk) begin
        sample_d <= sample_strobe;
        program_done <= 1'b0;

        if (reset) begin
            bus_addr <= 2'b00;
            bus_din <= 8'h00;
            bus_cs_n <= 1'b1;
            bus_wr_n <= 1'b1;
            test_phase <= 4'd0;
            high_state <= H_BOOT;
            program_id <= P_SILENCE;
            program_active <= 1'b0;
            txn_active <= 1'b0;
            bus_state <= B_IDLE;
            microcode_index <= 8'd0;
            current_word <= 17'd0;
            busy_watchdog <= 16'd0;
            sample_count <= 32'd0;
            natural_watchdog <= 32'd0;
            natural_armed <= 1'b0;
            accepted_write_count <= 32'd0;
            busy_timeout <= 1'b0;
            write_while_busy <= 1'b0;
            sequence_restart_count <= 16'd0;
            measurement_active <= 1'b0;
            measurement_phase <= 4'd0;
            halted <= 1'b0;
            sample_d <= 1'b0;
        end else if (!halted) begin
            // Transaction engine.  Status is read through the public bus;
            // no internal busy net or fixed inter-write delay is used.
            case (bus_state)
                B_IDLE: begin
                    drive_idle();
                    if (program_active && !txn_active) begin
                        current_word <= program_word(program_id,
                                                     microcode_index);
                        txn_active <= 1'b1;
                        busy_watchdog <= 16'd0;
                        bus_state <= B_CLEAR_SETUP;
                    end
                end
                B_CLEAR_SETUP: begin
                    drive_status();
                    bus_state <= B_CLEAR_SAMPLE;
                end
                B_CLEAR_SAMPLE: begin
                    if (bus_dout[7] == 1'b0) begin
                        drive_idle();
                        busy_watchdog <= 16'd0;
                        bus_state <= B_ADDR_SETUP;
                    end else if (busy_watchdog == 16'hffff) begin
                        busy_timeout <= 1'b1;
                        halted <= 1'b1;
                    end else begin
                        busy_watchdog <= busy_watchdog + 16'd1;
                        drive_status();
                    end
                end
                B_ADDR_SETUP: begin
                    bus_addr <= {current_word[16],1'b0};
                    bus_din <= current_word[15:8];
                    bus_cs_n <= 1'b0;
                    bus_wr_n <= 1'b0;
                    bus_state <= B_ADDR_CAPTURE;
                end
                B_ADDR_CAPTURE: begin
                    drive_idle();
                    bus_state <= B_DATA_CHECK;
                end
                B_DATA_CHECK: begin
                    drive_status();
                    bus_state <= B_DATA_SAMPLE;
                end
                B_DATA_SAMPLE: begin
                    if (bus_dout[7] != 1'b0) begin
                        write_while_busy <= 1'b1;
                        halted <= 1'b1;
                        drive_idle();
                    end else begin
                        bus_addr <= {current_word[16],1'b1};
                        bus_din <= current_word[7:0];
                        bus_cs_n <= 1'b0;
                        bus_wr_n <= 1'b0;
                        bus_state <= B_DATA_CAPTURE;
                    end
                end
                B_DATA_CAPTURE: begin
                    drive_idle();
                    accepted_write_count <= accepted_write_count + 32'd1;
                    if (program_id == P_A0_ON) begin
                        measurement_active <= 1'b1;
                        measurement_phase <= 4'd3;
                    end else if (program_id == P_A6_ON) begin
                        measurement_active <= 1'b1;
                        measurement_phase <= 4'd4;
                    end else if (program_id == P_B_START &&
                                 test_phase == 4'd5) begin
                        measurement_active <= 1'b1;
                        measurement_phase <= 4'd5;
                    end
                    busy_watchdog <= 16'd0;
                    bus_state <= B_ASSERT_SETUP;
                end
                B_ASSERT_SETUP: begin
                    drive_status();
                    bus_state <= B_ASSERT_SAMPLE;
                end
                B_ASSERT_SAMPLE: begin
                    if (bus_dout[7] == 1'b1) begin
                        busy_watchdog <= 16'd0;
                        drive_status();
                        bus_state <= B_DONE_SAMPLE;
                    end else if (busy_watchdog == 16'hffff) begin
                        busy_timeout <= 1'b1;
                        halted <= 1'b1;
                    end else begin
                        busy_watchdog <= busy_watchdog + 16'd1;
                        drive_status();
                    end
                end
                B_DONE_SETUP: begin
                    drive_status();
                    bus_state <= B_DONE_SAMPLE;
                end
                B_DONE_SAMPLE: begin
                    if (bus_dout[7] == 1'b0) begin
                        drive_idle();
                        txn_active <= 1'b0;
                        bus_state <= B_IDLE;
                        if (microcode_index + 1 >=
                            program_length(program_id)) begin
                            program_active <= 1'b0;
                            program_done <= 1'b1;
                        end else begin
                            microcode_index <= microcode_index + 8'd1;
                        end
                    end else if (busy_watchdog == 16'hffff) begin
                        busy_timeout <= 1'b1;
                        halted <= 1'b1;
                    end else begin
                        busy_watchdog <= busy_watchdog + 16'd1;
                        drive_status();
                    end
                end
                default: bus_state <= B_IDLE;
            endcase

            if (halted || busy_timeout || write_while_busy) begin
                halted <= 1'b1;
                measurement_active <= 1'b0;
                drive_idle();
            end else begin
                case (high_state)
                    H_BOOT: if (core_ready && audio_zero &&
                                bus_dout[7] == 1'b0 && !program_active) begin
                        test_phase <= 4'd0;
                        start_program(P_SILENCE);
                        high_state <= H_COLD;
                        sample_count <= 32'd0;
                    end
                    H_COLD: begin
                        if (program_done) sample_count <= 32'd0;
                        else if (!program_active && sample_rise) begin
                            if (sample_count + 1 >= COLD_SAMPLES) begin
                                high_state <= H_FM_CFG;
                                start_program(P_FM);
                                test_phase <= 4'd1;
                                sample_count <= 32'd0;
                            end else sample_count <= sample_count + 32'd1;
                        end
                    end
                    H_FM_CFG: if (program_done) begin
                        high_state <= H_FM_ATTACK; sample_count <= 32'd0;
                    end
                    H_FM_ATTACK: if (sample_rise) begin
                        if (sample_count + 1 >= 4096) begin
                            high_state <= H_FM_MEASURE; sample_count <= 0;
                            measurement_active <= 1'b1;
                            measurement_phase <= 4'd1;
                        end else sample_count <= sample_count + 1;
                    end
                    H_FM_MEASURE: if (sample_rise) begin
                        if (sample_count + 1 >= 4096) begin
                            measurement_active <= 1'b0; sample_count <= 0;
                            if (FAST_SIM) begin start_program(P_FM_OFF); high_state <= H_FM_OFF; end
                            else high_state <= H_FM_HOLD;
                        end else sample_count <= sample_count + 1;
                    end
                    H_FM_HOLD: if (sample_rise) begin
                        if (sample_count + 1 >= LONG_SAMPLES-8192) begin
                            start_program(P_FM_OFF); high_state <= H_FM_OFF;
                        end else sample_count <= sample_count + 1;
                    end
                    H_FM_OFF: if (program_done) begin
                        high_state <= H_SILENCE_1; test_phase <= 0; sample_count <= 0;
                    end
                    H_SILENCE_1: if (sample_rise) begin
                        if (sample_count + 1 >= SILENCE_SAMPLES) begin
                            start_program(P_SSG); high_state <= H_SSG_CFG;
                            test_phase <= 2; sample_count <= 0;
                        end else sample_count <= sample_count + 1;
                    end
                    H_SSG_CFG: if (program_done) begin high_state<=H_SSG_ATTACK; sample_count<=0; end
                    H_SSG_ATTACK: if (sample_rise) begin
                        if (sample_count + 1 >= 263) begin
                            high_state<=H_SSG_MEASURE; sample_count<=0;
                            measurement_active<=1; measurement_phase<=2;
                        end else sample_count<=sample_count+1;
                    end
                    H_SSG_MEASURE: if (sample_rise) begin
                        if (sample_count + 1 >= 4096) begin
                            measurement_active<=0; sample_count<=0;
                            if (FAST_SIM) begin start_program(P_SSG_OFF); high_state<=H_SSG_OFF; end
                            else high_state<=H_SSG_HOLD;
                        end else sample_count<=sample_count+1;
                    end
                    H_SSG_HOLD: if (sample_rise) begin
                        if (sample_count + 1 >= LONG_SAMPLES-4352) begin
                            start_program(P_SSG_OFF); high_state<=H_SSG_OFF;
                        end else sample_count<=sample_count+1;
                    end
                    H_SSG_OFF: if(program_done) begin high_state<=H_SILENCE_2;test_phase<=0;sample_count<=0;end
                    H_SILENCE_2: if(sample_rise) begin
                        if(sample_count+1>=SILENCE_SAMPLES) begin start_program(P_A0_CFG);high_state<=H_A0_CFG;test_phase<=3;sample_count<=0;end
                        else sample_count<=sample_count+1;
                    end
                    H_A0_CFG: if(program_done) high_state<=H_A0_ALIGN;
                    H_A0_ALIGN: if(!program_active && chip_cycle_mod432==9'd230) begin start_program(P_A0_ON);high_state<=H_A0_WAIT;sample_count<=0;end
                    H_A0_WAIT: if(measurement_active && sample_rise) begin
                        if(sample_count+1>=LONG_SAMPLES) begin measurement_active<=0;start_program(P_A0_OFF);high_state<=H_A0_OFF;end
                        else sample_count<=sample_count+1;
                    end
                    H_A0_OFF: if(program_done) begin high_state<=H_SILENCE_3;test_phase<=0;sample_count<=0;end
                    H_SILENCE_3: if(sample_rise) begin
                        if(sample_count+1>=SILENCE_SAMPLES) begin start_program(P_A6_CFG);high_state<=H_A6_CFG;test_phase<=4;sample_count<=0;end
                        else sample_count<=sample_count+1;
                    end
                    H_A6_CFG: if(program_done) high_state<=H_A6_ALIGN;
                    H_A6_ALIGN: if(!program_active && chip_cycle_mod432==9'd402) begin start_program(P_A6_ON);high_state<=H_A6_WAIT;sample_count<=0;end
                    H_A6_WAIT: if(measurement_active && sample_rise) begin
                        if(sample_count+1>=A6_SAMPLES) begin measurement_active<=0;start_program(P_A6_OFF);high_state<=H_A6_OFF;end
                        else sample_count<=sample_count+1;
                    end
                    H_A6_OFF: if(program_done) begin high_state<=H_SILENCE_4;test_phase<=0;sample_count<=0;end
                    H_SILENCE_4: if(sample_rise) begin
                        if(sample_count+1>=SILENCE_SAMPLES) begin start_program(P_B_STEREO);high_state<=H_B_CFG;test_phase<=5;sample_count<=0;end
                        else sample_count<=sample_count+1;
                    end
                    H_B_CFG: if(program_done) high_state<=H_B_ALIGN;
                    H_B_ALIGN: if(!program_active && chip_cycle_mod432==9'd416) begin start_program(P_B_START);high_state<=H_B_WAIT;sample_count<=0;end
                    H_B_WAIT: if(measurement_active && adpcmb_active && sample_rise) begin
                        if(sample_count+1>=B_SAMPLES) begin measurement_active<=0;start_program(P_B_RESET);high_state<=H_B_RESET;end
                        else sample_count<=sample_count+1;
                    end
                    H_B_RESET: if(program_done) begin high_state<=H_SILENCE_5;test_phase<=0;sample_count<=0;end
                    H_SILENCE_5: if(sample_rise) begin
                        if(sample_count+1>=SILENCE_SAMPLES) begin start_program(P_B_LEFT);high_state<=H_L_CFG;test_phase<=6;sample_count<=0;end
                        else sample_count<=sample_count+1;
                    end
                    H_L_CFG: if(program_done) high_state<=H_L_ALIGN;
                    H_L_ALIGN: if(!program_active && chip_cycle_mod432==9'd416) begin start_program(P_B_START);high_state<=H_L_WAIT;sample_count<=0;end
                    H_L_WAIT: if(sample_rise) begin
                        if(sample_count+1>=PAN_SAMPLES) begin start_program(P_B_RESET);high_state<=H_L_RESET;end
                        else sample_count<=sample_count+1;
                    end
                    H_L_RESET: if(program_done) begin high_state<=H_PAN_SILENCE;sample_count<=0;end
                    H_PAN_SILENCE: if(sample_rise) begin
                        if(sample_count+1>=SILENCE_SAMPLES) begin start_program(P_B_RIGHT);high_state<=H_R_CFG;sample_count<=0;end
                        else sample_count<=sample_count+1;
                    end
                    H_R_CFG: if(program_done) high_state<=H_R_ALIGN;
                    H_R_ALIGN: if(!program_active && chip_cycle_mod432==9'd416) begin start_program(P_B_START);high_state<=H_R_WAIT;sample_count<=0;end
                    H_R_WAIT: if(sample_rise) begin
                        if(sample_count+1>=PAN_SAMPLES) begin start_program(P_B_RESET);high_state<=H_R_RESET;end
                        else sample_count<=sample_count+1;
                    end
                    H_R_RESET: if(program_done) begin high_state<=H_SILENCE_6;test_phase<=0;sample_count<=0;end
                    H_SILENCE_6: if(sample_rise) begin
                        if(sample_count+1>=SILENCE_SAMPLES) begin start_program(P_B_SHORT);high_state<=H_SHORT_CFG;test_phase<=7;sample_count<=0;end
                        else sample_count<=sample_count+1;
                    end
                    H_SHORT_CFG: if(program_done) high_state<=H_SHORT_ALIGN1;
                    H_SHORT_ALIGN1: if(!program_active && chip_cycle_mod432==9'd416) begin start_program(P_B_START);high_state<=H_SHORT_WAIT1;natural_watchdog<=0;natural_armed<=0;end
                    H_SHORT_WAIT1: if(program_done) natural_armed<=1;
                        else if(natural_armed && adpcmb_eos) begin high_state<=H_SHORT_SILENCE;sample_count<=0;natural_armed<=0;end
                        else if(sample_rise) begin natural_watchdog<=natural_watchdog+1; if(natural_watchdog>4096) begin busy_timeout<=1;halted<=1;end end
                    H_SHORT_SILENCE: if(sample_rise) begin
                        if(sample_count+1>=SILENCE_SAMPLES) begin high_state<=H_SHORT_ALIGN2;sample_count<=0;end
                        else sample_count<=sample_count+1;
                    end
                    H_SHORT_ALIGN2: if(!program_active && chip_cycle_mod432==9'd416) begin start_program(P_B_START);high_state<=H_SHORT_WAIT2;natural_watchdog<=0;natural_armed<=0;end
                    H_SHORT_WAIT2: if(program_done) natural_armed<=1;
                        else if(natural_armed && adpcmb_eos) begin start_program(P_SILENCE);high_state<=H_FINAL_STOP;test_phase<=0;natural_armed<=0;end
                        else if(sample_rise) begin natural_watchdog<=natural_watchdog+1; if(natural_watchdog>4096) begin busy_timeout<=1;halted<=1;end end
                    H_FINAL_STOP: if(program_done) begin high_state<=H_FINAL_SILENCE;sample_count<=0;end
                    H_FINAL_SILENCE: if(sample_rise) begin
                        if(sample_count+1>=COLD_SAMPLES) begin high_state<=H_BOOT;sequence_restart_count<=sequence_restart_count+1;sample_count<=0;end
                        else sample_count<=sample_count+1;
                    end
                    default: begin halted<=1;busy_timeout<=1;end
                endcase
            end
        end else begin
            drive_idle();
            measurement_active <= 1'b0;
        end
    end
endmodule
