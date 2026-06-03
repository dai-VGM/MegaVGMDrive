#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

uint8_t read_u8(const std::vector<uint8_t>& data, size_t& pos) {
  if (pos >= data.size()) {
    throw std::runtime_error("unexpected end of file");
  }
  return data[pos++];
}

uint16_t read_le16(const std::vector<uint8_t>& data, size_t& pos) {
  uint16_t value = read_u8(data, pos);
  value |= static_cast<uint16_t>(read_u8(data, pos)) << 8;
  return value;
}

uint32_t read_le32(const std::vector<uint8_t>& data, size_t& pos) {
  uint32_t value = read_u8(data, pos);
  value |= static_cast<uint32_t>(read_u8(data, pos)) << 8;
  value |= static_cast<uint32_t>(read_u8(data, pos)) << 16;
  value |= static_cast<uint32_t>(read_u8(data, pos)) << 24;
  return value;
}

uint32_t read_le32_at(const std::vector<uint8_t>& data, size_t pos) {
  if (pos + 4 > data.size()) {
    throw std::runtime_error("unexpected end of file while reading header");
  }
  return static_cast<uint32_t>(data[pos]) |
         (static_cast<uint32_t>(data[pos + 1]) << 8) |
         (static_cast<uint32_t>(data[pos + 2]) << 16) |
         (static_cast<uint32_t>(data[pos + 3]) << 24);
}

void print_hex_byte(uint8_t value) {
  std::cout << std::uppercase << std::hex << std::setw(2) << std::setfill('0')
            << static_cast<int>(value) << std::dec << std::setfill(' ');
}

void skip_bytes(size_t count, size_t& pos, size_t size) {
  if (pos + count > size) {
    throw std::runtime_error("unexpected end of file while skipping command data");
  }
  pos += count;
}

struct Summary {
  uint64_t ym2612_port0_writes = 0;
  uint64_t ym2612_port1_writes = 0;
  uint64_t sn76489_writes = 0;
  uint64_t wait_commands = 0;
  uint64_t vgm_wait_commands = 0;
  uint64_t wait_samples = 0;
  uint64_t short_wait_commands = 0;
  uint64_t data_blocks = 0;
  uint64_t pcm_seeks = 0;
  uint64_t dac_stream_writes = 0;
  uint64_t game_gear_stereo_commands = 0;
  std::map<uint8_t, uint64_t> unsupported_commands;
  uint64_t end_commands = 0;
  bool end_reached = false;
  size_t total_bytes = 0;
};

struct YmRegisterSummary {
  uint64_t lfo_writes = 0;
  uint64_t dac_data_writes = 0;
  uint64_t dac_enable_writes = 0;
  uint64_t keyon_writes = 0;
  std::map<uint8_t, uint64_t> keyon_data_counts;
  uint64_t operator_parameter_writes = 0;
  uint64_t frequency_low_writes = 0;
  uint64_t frequency_high_block_writes = 0;
  uint64_t algorithm_feedback_writes = 0;
  uint64_t pan_ams_fms_writes = 0;

  uint64_t port1_frequency_low_writes = 0;
  uint64_t port1_frequency_high_block_writes = 0;
  uint64_t port1_algorithm_feedback_writes = 0;
  uint64_t port1_pan_ams_fms_writes = 0;

  bool active_keyon_seen = false;
  size_t first_active_keyon_offset = 0;
  uint64_t operator_parameter_writes_before_first_keyon = 0;
  uint64_t frequency_low_writes_before_first_keyon = 0;
  uint64_t frequency_high_block_writes_before_first_keyon = 0;
  uint64_t algorithm_feedback_writes_before_first_keyon = 0;
  uint64_t pan_ams_fms_writes_before_first_keyon = 0;
};

struct Options {
  bool emit_sv = false;
  uint64_t emit_sv_limit = 0;
  bool dump_header = false;
  bool stats = false;
  bool dump_commands = false;
  uint64_t dump_command_limit = 0;
};

struct VgmHeader {
  uint32_t magic = 0;
  uint32_t eof_offset = 0;
  uint32_t version = 0;
  uint32_t sn76489_clock = 0;
  uint32_t gd3_offset = 0;
  uint32_t total_samples = 0;
  uint32_t loop_offset = 0;
  uint32_t loop_samples = 0;
  uint32_t ym2612_clock = 0;
  uint32_t data_offset = 0;
  size_t command_start = 0;
};

void add_wait(Summary& summary, uint64_t samples) {
  summary.wait_commands++;
  summary.wait_samples += samples;
}

void add_vgm_wait(Summary& summary, uint64_t samples) {
  add_wait(summary, samples);
  summary.vgm_wait_commands++;
}

void emit_sv_pc(size_t pc) {
  std::cout << "32'h" << std::uppercase << std::hex << std::setw(8)
            << std::setfill('0') << pc << std::dec << std::setfill(' ');
}

void emit_sv_wait(size_t pc, uint64_t samples) {
  std::cout << "tb_vgm_pc = ";
  emit_sv_pc(pc);
  std::cout << ";\n";
  std::cout << "`ifdef VERBOSE_TB_LOG\n";
  std::cout << "$display(\"VGM_WAIT pc=%08h samples=" << samples << "\", ";
  emit_sv_pc(pc);
  std::cout << ");\n";
  std::cout << "`endif\n";
  std::cout << "wait_samples(" << samples << ");\n";
}

void emit_sv_ym(size_t pc, uint8_t command, uint8_t port, uint8_t reg, uint8_t value) {
  std::cout << "tb_vgm_pc = ";
  emit_sv_pc(pc);
  std::cout << ";\n";
  std::cout << "`ifdef VERBOSE_TB_LOG\n";
  std::cout << "$display(\"VGM_YM pc=%08h cmd=%02h port=" << static_cast<int>(port)
            << " reg=%02h data=%02h\", ";
  emit_sv_pc(pc);
  std::cout << ", 8'h";
  print_hex_byte(command);
  std::cout << ", 8'h";
  print_hex_byte(reg);
  std::cout << ", 8'h";
  print_hex_byte(value);
  std::cout << ");\n";
  std::cout << "`endif\n";
  std::cout << "send_ym(1'b" << static_cast<int>(port) << ", 8'h";
  print_hex_byte(reg);
  std::cout << ", 8'h";
  print_hex_byte(value);
  std::cout << ");\n";
}

void emit_sv_psg(size_t pc, uint8_t value) {
  std::cout << "tb_vgm_pc = ";
  emit_sv_pc(pc);
  std::cout << ";\n";
  std::cout << "send_psg(8'h";
  print_hex_byte(value);
  std::cout << ");\n";
}

void emit_sv_pcm_bank(size_t pc,
                      uint8_t type,
                      uint32_t size,
                      const std::vector<uint8_t>& data,
                      size_t data_start) {
  std::cout << "tb_vgm_pc = ";
  emit_sv_pc(pc);
  std::cout << ";\n";
  if (type != 0x00) {
    std::cout << "// DATA_BLOCK type=0x";
    print_hex_byte(type);
    std::cout << " size=" << size << " unsupported for PCM bank emit\n";
    return;
  }

  std::cout << "pcm_bank_size = " << size << ";\n";
  std::cout << "pcm_pos = 0;\n";
  std::cout << "`ifdef VERBOSE_TB_LOG\n";
  std::cout << "$display(\"PCM_BANK_LOAD pc=%08h type=00 size=" << size << "\", ";
  emit_sv_pc(pc);
  std::cout << ");\n";
  std::cout << "`endif\n";

  for (uint32_t i = 0; i < size; ++i) {
    std::cout << "pcm_bank[" << i << "] = 8'h";
    print_hex_byte(data[data_start + i]);
    std::cout << ";\n";
  }
}

void emit_sv_pcm_seek(size_t pc, uint32_t offset) {
  std::cout << "tb_vgm_pc = ";
  emit_sv_pc(pc);
  std::cout << ";\n";
  std::cout << "pcm_pos = " << offset << ";\n";
  std::cout << "pcm_seek_count++;\n";
  std::cout << "`ifdef VERBOSE_TB_LOG\n";
  std::cout << "$display(\"PCM_SEEK pc=%08h offset=" << offset << "\", ";
  emit_sv_pc(pc);
  std::cout << ");\n";
  std::cout << "`endif\n";
}

void emit_sv_dac_stream(size_t pc, uint8_t command, uint8_t samples) {
  std::cout << "tb_vgm_pc = ";
  emit_sv_pc(pc);
  std::cout << ";\n";
  std::cout << "dac_stream_command_count++;\n";
  std::cout << "if (pcm_pos < pcm_bank_size) begin\n";
  std::cout << "  send_ym(1'b0, 8'h2A, pcm_bank[pcm_pos]);\n";
  std::cout << "  pcm_pos++;\n";
  std::cout << "  dac_generated_write_count++;\n";
  std::cout << "end else begin\n";
  std::cout << "`ifdef VERBOSE_TB_LOG\n";
  std::cout << "  $display(\"PCM_STREAM_UNDERRUN pc=%08h cmd=%02h pcm_pos=%0d pcm_bank_size=%0d\", ";
  emit_sv_pc(pc);
  std::cout << ", 8'h";
  print_hex_byte(command);
  std::cout << ", pcm_pos, pcm_bank_size);\n";
  std::cout << "`endif\n";
  std::cout << "end\n";
  if (samples > 0) {
    emit_sv_wait(pc, samples);
  }
}

std::string hex32(uint32_t value) {
  std::ostringstream out;
  out << "0x" << std::uppercase << std::hex << std::setw(8)
      << std::setfill('0') << value;
  return out.str();
}

std::string hex_offset(size_t value) {
  std::ostringstream out;
  out << "0x" << std::uppercase << std::hex << std::setw(8)
      << std::setfill('0') << value;
  return out.str();
}

std::string magic_string(uint32_t magic) {
  std::string text;
  text.push_back(static_cast<char>(magic & 0xFF));
  text.push_back(static_cast<char>((magic >> 8) & 0xFF));
  text.push_back(static_cast<char>((magic >> 16) & 0xFF));
  text.push_back(static_cast<char>((magic >> 24) & 0xFF));
  return text;
}

VgmHeader read_header(const std::vector<uint8_t>& data) {
  VgmHeader header;
  header.magic = read_le32_at(data, 0x00);
  header.eof_offset = read_le32_at(data, 0x04);
  header.version = read_le32_at(data, 0x08);
  header.sn76489_clock = read_le32_at(data, 0x0C);
  header.gd3_offset = read_le32_at(data, 0x14);
  header.total_samples = read_le32_at(data, 0x18);
  header.loop_offset = read_le32_at(data, 0x1C);
  header.loop_samples = read_le32_at(data, 0x20);
  header.ym2612_clock = read_le32_at(data, 0x2C);
  header.data_offset = header.version >= 0x00000150 ? read_le32_at(data, 0x34) : 0;

  if (header.version >= 0x00000150 && header.data_offset != 0) {
    header.command_start = 0x34 + header.data_offset;
  } else {
    header.command_start = 0x40;
  }

  return header;
}

void print_header(const VgmHeader& header, const std::vector<uint8_t>& data) {
  std::cout << "VGM HEADER\n";
  std::cout << "magic: " << magic_string(header.magic) << " (" << hex32(header.magic) << ")\n";
  std::cout << "EOF offset: " << hex32(header.eof_offset)
            << " absolute=" << hex_offset(static_cast<size_t>(0x04) + header.eof_offset) << "\n";
  std::cout << "version: " << hex32(header.version) << "\n";
  std::cout << "SN76489 clock: " << header.sn76489_clock << "\n";
  std::cout << "YM2612 clock: " << header.ym2612_clock << "\n";
  std::cout << "GD3 offset: " << hex32(header.gd3_offset);
  if (header.gd3_offset != 0) {
    std::cout << " absolute=" << hex_offset(static_cast<size_t>(0x14) + header.gd3_offset);
  }
  std::cout << "\n";
  std::cout << "total samples: " << header.total_samples << "\n";
  std::cout << "loop offset: " << hex32(header.loop_offset);
  if (header.loop_offset != 0) {
    std::cout << " absolute=" << hex_offset(static_cast<size_t>(0x1C) + header.loop_offset);
  }
  std::cout << "\n";
  std::cout << "loop samples: " << header.loop_samples << "\n";
  std::cout << "data offset: " << hex32(header.data_offset) << "\n";
  std::cout << "command_start offset: " << hex_offset(header.command_start) << "\n";

  const size_t dump_size = 64;
  const size_t end = std::min(data.size(), header.command_start + dump_size);
  std::cout << "\nCOMMAND_START HEXDUMP\n";
  for (size_t pos = header.command_start; pos < end; pos += 16) {
    std::cout << hex_offset(pos) << ": ";
    for (size_t i = 0; i < 16 && pos + i < end; ++i) {
      print_hex_byte(data[pos + i]);
      std::cout << " ";
    }
    std::cout << "\n";
  }
}

void print_summary(const Summary& summary) {
  std::cout << "\n";
  std::cout << "SUMMARY\n";
  std::cout << "YM2612 port0 writes: " << summary.ym2612_port0_writes << "\n";
  std::cout << "YM2612 port1 writes: " << summary.ym2612_port1_writes << "\n";
  std::cout << "SN76489 writes: " << summary.sn76489_writes << "\n";
  std::cout << "WAIT commands: " << summary.wait_commands << "\n";
  std::cout << "VGM wait commands (0x61/0x62/0x63/0x70-0x7F): "
            << summary.vgm_wait_commands << "\n";
  std::cout << "WAIT total samples: " << summary.wait_samples << "\n";
  std::cout << "Short wait commands: " << summary.short_wait_commands << "\n";
  std::cout << "Data blocks: " << summary.data_blocks << "\n";
  std::cout << "PCM seeks: " << summary.pcm_seeks << "\n";
  std::cout << "YM2612 DAC stream commands: " << summary.dac_stream_writes << "\n";
  std::cout << "Game Gear stereo commands: " << summary.game_gear_stereo_commands << "\n";
  std::cout << "Unsupported commands:\n";
  if (summary.unsupported_commands.empty()) {
    std::cout << "  none\n";
  } else {
    for (const auto& entry : summary.unsupported_commands) {
      std::cout << "  0x";
      print_hex_byte(entry.first);
      std::cout << ": " << entry.second << "\n";
    }
  }
  std::cout << "END commands: " << summary.end_commands << "\n";
  std::cout << "END reached: " << (summary.end_reached ? "yes" : "no") << "\n";
  std::cout << "Total bytes: " << summary.total_bytes << "\n";
}

void print_ym_register_summary(const YmRegisterSummary& summary) {
  std::cout << "\n";
  std::cout << "YM2612 REGISTER SUMMARY\n";
  std::cout << "reg 0x22 LFO writes: " << summary.lfo_writes << "\n";
  std::cout << "reg 0x2A DAC data writes: " << summary.dac_data_writes << "\n";
  std::cout << "reg 0x2B DAC enable writes: " << summary.dac_enable_writes << "\n";
  std::cout << "reg 0x28 KeyOn writes: " << summary.keyon_writes << "\n";
  std::cout << "reg 0x28 KeyOn data distribution:\n";
  if (summary.keyon_data_counts.empty()) {
    std::cout << "  none\n";
  } else {
    for (const auto& entry : summary.keyon_data_counts) {
      std::cout << "  0x";
      print_hex_byte(entry.first);
      std::cout << ": " << entry.second << "\n";
    }
  }
  std::cout << "reg 0x30-0x9E operator parameter writes: "
            << summary.operator_parameter_writes << "\n";
  std::cout << "reg 0xA0-0xA6 frequency low writes: "
            << summary.frequency_low_writes << "\n";
  std::cout << "reg 0xA4-0xAA frequency high/block writes: "
            << summary.frequency_high_block_writes << "\n";
  std::cout << "reg 0xB0-0xB2 algorithm/feedback writes: "
            << summary.algorithm_feedback_writes << "\n";
  std::cout << "reg 0xB4-0xB6 pan/AMS/FMS writes: "
            << summary.pan_ams_fms_writes << "\n";
  std::cout << "port1 ch4-6 frequency low writes: "
            << summary.port1_frequency_low_writes << "\n";
  std::cout << "port1 ch4-6 frequency high/block writes: "
            << summary.port1_frequency_high_block_writes << "\n";
  std::cout << "port1 ch4-6 algorithm/feedback writes: "
            << summary.port1_algorithm_feedback_writes << "\n";
  std::cout << "port1 ch4-6 pan/AMS/FMS writes: "
            << summary.port1_pan_ams_fms_writes << "\n";
  if (summary.active_keyon_seen) {
    std::cout << "first active KeyOn offset: "
              << hex_offset(summary.first_active_keyon_offset) << "\n";
  } else {
    std::cout << "first active KeyOn offset: none\n";
  }
  std::cout << "operator parameter writes before first active KeyOn: "
            << summary.operator_parameter_writes_before_first_keyon << "\n";
  std::cout << "frequency low writes before first active KeyOn: "
            << summary.frequency_low_writes_before_first_keyon << "\n";
  std::cout << "frequency high/block writes before first active KeyOn: "
            << summary.frequency_high_block_writes_before_first_keyon << "\n";
  std::cout << "algorithm/feedback writes before first active KeyOn: "
            << summary.algorithm_feedback_writes_before_first_keyon << "\n";
  std::cout << "pan/AMS/FMS writes before first active KeyOn: "
            << summary.pan_ams_fms_writes_before_first_keyon << "\n";
}

void add_ym_register_write(YmRegisterSummary& summary,
                           size_t command_pos,
                           uint8_t port,
                           uint8_t reg,
                           uint8_t value) {
  const bool before_first_active_keyon = !summary.active_keyon_seen;
  if (reg == 0x22) {
    summary.lfo_writes++;
  }
  if (reg == 0x2A) {
    summary.dac_data_writes++;
  }
  if (reg == 0x2B) {
    summary.dac_enable_writes++;
  }
  if (reg == 0x28) {
    summary.keyon_writes++;
    summary.keyon_data_counts[value]++;
    if ((value & 0xF0) != 0 && !summary.active_keyon_seen) {
      summary.active_keyon_seen = true;
      summary.first_active_keyon_offset = command_pos;
    }
  }

  if (reg >= 0x30 && reg <= 0x9E) {
    summary.operator_parameter_writes++;
    if (before_first_active_keyon) {
      summary.operator_parameter_writes_before_first_keyon++;
    }
  }
  if (reg >= 0xA0 && reg <= 0xA6) {
    summary.frequency_low_writes++;
    if (before_first_active_keyon) {
      summary.frequency_low_writes_before_first_keyon++;
    }
    if (port == 1) {
      summary.port1_frequency_low_writes++;
    }
  }
  if (reg >= 0xA4 && reg <= 0xAA) {
    summary.frequency_high_block_writes++;
    if (before_first_active_keyon) {
      summary.frequency_high_block_writes_before_first_keyon++;
    }
    if (port == 1) {
      summary.port1_frequency_high_block_writes++;
    }
  }
  if (reg >= 0xB0 && reg <= 0xB2) {
    summary.algorithm_feedback_writes++;
    if (before_first_active_keyon) {
      summary.algorithm_feedback_writes_before_first_keyon++;
    }
    if (port == 1) {
      summary.port1_algorithm_feedback_writes++;
    }
  }
  if (reg >= 0xB4 && reg <= 0xB6) {
    summary.pan_ams_fms_writes++;
    if (before_first_active_keyon) {
      summary.pan_ams_fms_writes_before_first_keyon++;
    }
    if (port == 1) {
      summary.port1_pan_ams_fms_writes++;
    }
  }
}

bool skip_known_unsupported(uint8_t command, const std::vector<uint8_t>& data, size_t& pos, Summary& summary) {
  summary.unsupported_commands[command]++;

  switch (command) {
    case 0x30:  // SN76489 second chip
      skip_bytes(1, pos, data.size());
      return true;

    case 0x51:  // YM2413
    case 0x54:  // YM2151
    case 0x55:  // YM2203
    case 0x56:  // YM2608 port 0
    case 0x57:  // YM2608 port 1
    case 0x58:  // YM2610 port 0
    case 0x59:  // YM2610 port 1
    case 0x5A:  // YM3812
    case 0x5B:  // YM3526
    case 0x5C:  // Y8950
    case 0x5E:  // YMF262 port 0
    case 0x5F:  // YMF262 port 1
    case 0xA0:  // AY8910
      skip_bytes(2, pos, data.size());
      return true;

    case 0x68:  // PCM RAM write
      skip_bytes(11, pos, data.size());
      return true;

    case 0x90:  // setup stream control
      skip_bytes(4, pos, data.size());
      return true;

    case 0x91:  // set stream data
      skip_bytes(4, pos, data.size());
      return true;

    case 0x92:  // set stream frequency
      skip_bytes(5, pos, data.size());
      return true;

    case 0x93:  // start stream
      skip_bytes(10, pos, data.size());
      return true;

    case 0x94:  // stop stream
      skip_bytes(1, pos, data.size());
      return true;

    case 0x95:  // start stream fast
      skip_bytes(4, pos, data.size());
      return true;

    default:
      break;
  }

  summary.unsupported_commands[command]--;
  if (summary.unsupported_commands[command] == 0) {
    summary.unsupported_commands.erase(command);
  }
  return false;
}

int inspect_vgm(const std::string& path, const Options& options) {
  std::ifstream file(path, std::ios::binary);
  if (!file) {
    std::cerr << "ERROR: failed to open file: " << path << "\n";
    return 1;
  }

  std::vector<uint8_t> data((std::istreambuf_iterator<char>(file)),
                            std::istreambuf_iterator<char>());
  Summary summary;
  summary.total_bytes = data.size();

  if (data.size() < 0x40) {
    std::cerr << "ERROR: file is too small for VGM\n";
    return 1;
  }

  if (read_le32_at(data, 0) != 0x206D6756) {
    std::cerr << "ERROR: not an uncompressed VGM file\n";
    return 1;
  }

  const VgmHeader header = read_header(data);
  if (header.command_start >= data.size()) {
    std::cerr << "ERROR: VGM data offset is outside the file\n";
    return 1;
  }

  if (options.dump_header) {
    print_header(header, data);
  }

  const bool quiet_parse = options.dump_header || options.stats || options.dump_commands;
  size_t pos = header.command_start;
  uint64_t emitted_sound_commands = 0;
  uint64_t dumped_commands = 0;
  YmRegisterSummary ym_register_summary;
  while (pos < data.size()) {
    if (options.emit_sv && emitted_sound_commands >= options.emit_sv_limit) {
      return 0;
    }

    const size_t command_pos = pos;
    uint8_t command = read_u8(data, pos);

    switch (command) {
      case 0x50: {
        uint8_t value = read_u8(data, pos);
        summary.sn76489_writes++;
        if (options.dump_commands && dumped_commands < options.dump_command_limit) {
          std::cout << "pc=" << hex_offset(command_pos) << " cmd=50 psg_data=";
          print_hex_byte(value);
          std::cout << "\n";
          dumped_commands++;
        }
        if (options.emit_sv) {
          emit_sv_psg(command_pos, value);
          emitted_sound_commands++;
        } else if (!quiet_parse) {
          std::cout << "SN76489 data=";
          print_hex_byte(value);
          std::cout << "\n";
        }
        break;
      }

      case 0x52: {
        uint8_t reg = read_u8(data, pos);
        uint8_t value = read_u8(data, pos);
        summary.ym2612_port0_writes++;
        add_ym_register_write(ym_register_summary, command_pos, 0, reg, value);
        if (options.dump_commands && dumped_commands < options.dump_command_limit) {
          std::cout << "pc=" << hex_offset(command_pos) << " cmd=52 port=0 reg=";
          print_hex_byte(reg);
          std::cout << " data=";
          print_hex_byte(value);
          std::cout << "\n";
          dumped_commands++;
        }
        if (options.emit_sv) {
          emit_sv_ym(command_pos, command, 0, reg, value);
          emitted_sound_commands++;
        } else if (!quiet_parse) {
          std::cout << "YM2612 P0 reg=";
          print_hex_byte(reg);
          std::cout << " data=";
          print_hex_byte(value);
          std::cout << "\n";
        }
        break;
      }

      case 0x53: {
        uint8_t reg = read_u8(data, pos);
        uint8_t value = read_u8(data, pos);
        summary.ym2612_port1_writes++;
        add_ym_register_write(ym_register_summary, command_pos, 1, reg, value);
        if (options.dump_commands && dumped_commands < options.dump_command_limit) {
          std::cout << "pc=" << hex_offset(command_pos) << " cmd=53 port=1 reg=";
          print_hex_byte(reg);
          std::cout << " data=";
          print_hex_byte(value);
          std::cout << "\n";
          dumped_commands++;
        }
        if (options.emit_sv) {
          emit_sv_ym(command_pos, command, 1, reg, value);
          emitted_sound_commands++;
        } else if (!quiet_parse) {
          std::cout << "YM2612 P1 reg=";
          print_hex_byte(reg);
          std::cout << " data=";
          print_hex_byte(value);
          std::cout << "\n";
        }
        break;
      }

      case 0x61: {
        uint16_t samples = read_le16(data, pos);
        add_vgm_wait(summary, samples);
        if (options.dump_commands && dumped_commands < options.dump_command_limit) {
          std::cout << "pc=" << hex_offset(command_pos) << " cmd=61 wait=" << samples << "\n";
          dumped_commands++;
        }
        if (options.emit_sv) {
          emit_sv_wait(command_pos, samples);
        } else if (!quiet_parse) {
          std::cout << "WAIT " << samples << "\n";
        }
        break;
      }

      case 0x62:
        add_vgm_wait(summary, 735);
        if (options.dump_commands && dumped_commands < options.dump_command_limit) {
          std::cout << "pc=" << hex_offset(command_pos) << " cmd=62 wait=735\n";
          dumped_commands++;
        }
        if (options.emit_sv) {
          emit_sv_wait(command_pos, 735);
        } else if (!quiet_parse) {
          std::cout << "WAIT 735\n";
        }
        break;

      case 0x63:
        add_vgm_wait(summary, 882);
        if (options.dump_commands && dumped_commands < options.dump_command_limit) {
          std::cout << "pc=" << hex_offset(command_pos) << " cmd=63 wait=882\n";
          dumped_commands++;
        }
        if (options.emit_sv) {
          emit_sv_wait(command_pos, 882);
        } else if (!quiet_parse) {
          std::cout << "WAIT 882\n";
        }
        break;

      case 0x67: {
        uint8_t marker = read_u8(data, pos);
        if (marker != 0x66) {
          throw std::runtime_error("invalid VGM data block marker");
        }
        uint8_t type = read_u8(data, pos);
        uint32_t size = read_le32(data, pos);
        const size_t data_start = pos;
        skip_bytes(size, pos, data.size());
        summary.data_blocks++;
        if (options.dump_commands && dumped_commands < options.dump_command_limit) {
          std::cout << "pc=" << hex_offset(command_pos) << " cmd=67 data_block type=0x";
          print_hex_byte(type);
          std::cout << " size=" << size << "\n";
          dumped_commands++;
        }

        if (options.emit_sv) {
          emit_sv_pcm_bank(command_pos, type, size, data, data_start);
        } else if (!quiet_parse) {
          std::cout << "DATA_BLOCK type=0x";
          print_hex_byte(type);
          std::cout << " size=" << size << "\n";
        }
        break;
      }

      case 0x4F: {
        uint8_t value = read_u8(data, pos);
        summary.game_gear_stereo_commands++;
        if (options.dump_commands && dumped_commands < options.dump_command_limit) {
          std::cout << "pc=" << hex_offset(command_pos) << " cmd=4F gg_stereo=";
          print_hex_byte(value);
          std::cout << "\n";
          dumped_commands++;
        }
        if (options.emit_sv) {
          std::cout << "// GAME_GEAR_STEREO data=0x";
          print_hex_byte(value);
          std::cout << " skipped\n";
        } else if (!quiet_parse) {
          std::cout << "GAME_GEAR_STEREO data=";
          print_hex_byte(value);
          std::cout << "\n";
        }
        break;
      }

      case 0x66:
        summary.end_reached = true;
        summary.end_commands++;
        summary.unsupported_commands.erase(0x66);
        if (options.dump_commands && dumped_commands < options.dump_command_limit) {
          std::cout << "pc=" << hex_offset(command_pos) << " cmd=66 end\n";
          dumped_commands++;
        }
        if (options.emit_sv) {
          std::cout << "// END\n";
        } else if (!quiet_parse) {
          std::cout << "END\n";
          print_summary(summary);
        }
        if (quiet_parse) {
          print_summary(summary);
          print_ym_register_summary(ym_register_summary);
        }
        return 0;

      case 0xE0: {
        uint32_t offset = read_le32(data, pos);
        summary.pcm_seeks++;
        if (options.dump_commands && dumped_commands < options.dump_command_limit) {
          std::cout << "pc=" << hex_offset(command_pos) << " cmd=E0 pcm_seek=" << offset << "\n";
          dumped_commands++;
        }
        if (options.emit_sv) {
          emit_sv_pcm_seek(command_pos, offset);
        } else if (!quiet_parse) {
          std::cout << "PCM_SEEK offset=" << offset << "\n";
        }
        break;
      }

      default:
        if (command >= 0x70 && command <= 0x7F) {
          uint8_t samples = (command & 0x0F) + 1;
          add_vgm_wait(summary, samples);
          summary.short_wait_commands++;
          if (options.dump_commands && dumped_commands < options.dump_command_limit) {
            std::cout << "pc=" << hex_offset(command_pos) << " cmd=";
            print_hex_byte(command);
            std::cout << " short_wait=" << static_cast<int>(samples) << "\n";
            dumped_commands++;
          }
          if (options.emit_sv) {
            emit_sv_wait(command_pos, samples);
          } else if (!quiet_parse) {
            std::cout << "WAIT_SHORT " << static_cast<int>(samples) << "\n";
          }
          break;
        }

        if (command >= 0x80 && command <= 0x8F) {
          uint8_t samples = command & 0x0F;
          summary.dac_stream_writes++;
          if (samples > 0) {
            add_wait(summary, samples);
          }
          if (options.dump_commands && dumped_commands < options.dump_command_limit) {
            std::cout << "pc=" << hex_offset(command_pos) << " cmd=";
            print_hex_byte(command);
            std::cout << " dac_stream_wait=" << static_cast<int>(samples) << "\n";
            dumped_commands++;
          }
          if (options.emit_sv) {
            emit_sv_dac_stream(command_pos, command, samples);
            emitted_sound_commands++;
          } else if (!quiet_parse) {
            std::cout << "YM2612_DAC_STREAM_WAIT " << static_cast<int>(samples) << "\n";
          }
          break;
        }

        if (!skip_known_unsupported(command, data, pos, summary)) {
          summary.unsupported_commands[command]++;
          if (options.dump_commands && dumped_commands < options.dump_command_limit) {
            std::cout << "pc=" << hex_offset(command_pos) << " cmd=";
            print_hex_byte(command);
            std::cout << " unsupported\n";
            dumped_commands++;
          }
          std::cerr << "ERROR: unsupported command 0x" << std::uppercase << std::hex
                    << std::setw(2) << std::setfill('0') << static_cast<int>(command)
                    << " at offset 0x" << command_pos << std::dec << "\n";
          print_summary(summary);
          print_ym_register_summary(ym_register_summary);
          return 1;
        }
        if (options.dump_commands && dumped_commands < options.dump_command_limit) {
          std::cout << "pc=" << hex_offset(command_pos) << " cmd=";
          print_hex_byte(command);
          std::cout << " skipped_unsupported_family\n";
          dumped_commands++;
        }
        break;
    }
  }

  std::cerr << "ERROR: reached end of file before 0x66 END\n";
  if (!options.emit_sv) {
    print_summary(summary);
    print_ym_register_summary(ym_register_summary);
  }
  return 1;
}

}  // namespace

int main(int argc, char** argv) {
  Options options;
  std::string path;

  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "--emit-sv") {
      if (i + 1 >= argc) {
        std::cerr << "ERROR: --emit-sv requires a numeric command limit\n";
        return 1;
      }
      char* end = nullptr;
      const unsigned long long limit = std::strtoull(argv[++i], &end, 10);
      if (end == argv[i] || *end != '\0') {
        std::cerr << "ERROR: --emit-sv requires a numeric command limit\n";
        return 1;
      }
      options.emit_sv = true;
      options.emit_sv_limit = limit;
    } else if (arg == "--dump-header") {
      options.dump_header = true;
    } else if (arg == "--stats") {
      options.stats = true;
    } else if (arg == "--dump-commands") {
      if (i + 1 >= argc) {
        std::cerr << "ERROR: --dump-commands requires a numeric command limit\n";
        return 1;
      }
      char* end = nullptr;
      const unsigned long long limit = std::strtoull(argv[++i], &end, 10);
      if (end == argv[i] || *end != '\0') {
        std::cerr << "ERROR: --dump-commands requires a numeric command limit\n";
        return 1;
      }
      options.dump_commands = true;
      options.dump_command_limit = limit;
    } else if (!arg.empty() && arg[0] == '-') {
      std::cerr << "ERROR: unknown option: " << arg << "\n";
      return 1;
    } else if (path.empty()) {
      path = arg;
    } else {
      std::cerr << "ERROR: multiple input files were provided\n";
      return 1;
    }
  }

  if (path.empty()) {
    std::cerr << "Usage: " << argv[0]
              << " [--emit-sv N] [--dump-header] [--stats] [--dump-commands N] path/to/file.vgm\n";
    return 1;
  }

  try {
    return inspect_vgm(path, options);
  } catch (const std::exception& e) {
    std::cerr << "ERROR: " << e.what() << "\n";
    return 1;
  }
}
