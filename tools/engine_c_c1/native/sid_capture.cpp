// Engine C C1: execute a SID program and observe actual C64-to-SID writes.
// The patched hook is before the selected SID emulation engine's write method;
// this program never polls or reconstructs register state.
#include <sidplayfp/sidplayfp.h>
#include <sidplayfp/SidConfig.h>
#include <sidplayfp/SidTune.h>
#include <sidplayfp/SidTuneInfo.h>
#include <sidplayfp/builders/sidlite.h>

#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

#ifndef MVGMSID_LIBSIDPLAYFP_COMMIT
#define MVGMSID_LIBSIDPLAYFP_COMMIT "unknown"
#endif

namespace {
constexpr std::uint32_t PAL_HZ = 985248;
constexpr std::uint32_t NTSC_HZ = 1022727;

struct Write { std::uint64_t cycle; unsigned sid; unsigned addr; unsigned data; };
struct Capture {
    bool active = false;
    bool invalid_time = false;
    std::uint64_t origin = 0;
    std::uint64_t end = 0;
    std::vector<Write> writes;
};

void observe(void *opaque, unsigned sid, uint_least64_t cycle,
             uint_least8_t addr, uint8_t data) {
    auto &capture = *static_cast<Capture *>(opaque);
    if (!capture.active) return;
    if (cycle < capture.origin) { capture.invalid_time = true; return; }
    if (cycle < capture.end)
        capture.writes.push_back({cycle - capture.origin, sid,
                                  static_cast<unsigned>(addr), data});
}

std::string hex(const char *value) {
    std::ostringstream out;
    if (value != nullptr) {
        const auto *p = reinterpret_cast<const unsigned char *>(value);
        while (*p) out << std::hex << std::setw(2) << std::setfill('0')
                       << static_cast<unsigned>(*p++);
    }
    return out.str();
}

void meta(std::ofstream &out, const char *key, const std::string &value) {
    out << "META\t" << key << "\t" << value << '\n';
}

bool parse_uint(const char *text, std::uint64_t &value) {
    try {
        std::size_t used = 0;
        std::string input(text);
        if (input.empty() || input[0] == '-') return false;
        value = std::stoull(input, &used, 10);
        return used == input.size();
    } catch (...) { return false; }
}

const char *clock_name(SidTuneInfo::clock_t value) {
    switch (value) {
    case SidTuneInfo::CLOCK_PAL: return "pal";
    case SidTuneInfo::CLOCK_NTSC: return "ntsc";
    case SidTuneInfo::CLOCK_ANY: return "any";
    default: return "unknown";
    }
}

const char *model_name(SidTuneInfo::model_t value) {
    switch (value) {
    case SidTuneInfo::SIDMODEL_6581: return "6581";
    case SidTuneInfo::SIDMODEL_8580: return "8580";
    case SidTuneInfo::SIDMODEL_ANY: return "any";
    default: return "unknown";
    }
}

int fail(const std::string &message) {
    std::cerr << "sid_capture: " << message << '\n';
    return 2;
}
} // namespace

int main(int argc, char **argv) {
    std::string input, trace, model = "auto", timing = "auto";
    std::uint64_t subtune = 0, capture_seconds = 0;
    for (int i = 1; i < argc; ++i) {
        std::string arg(argv[i]);
        auto need = [&]() -> const char * {
            if (++i >= argc) return nullptr;
            return argv[i];
        };
        const char *value = nullptr;
        if (arg == "--input" && (value = need())) input = value;
        else if (arg == "--trace" && (value = need())) trace = value;
        else if (arg == "--model" && (value = need())) model = value;
        else if (arg == "--timing" && (value = need())) timing = value;
        else if (arg == "--subtune" && (value = need())) {
            if (!parse_uint(value, subtune)) return fail("invalid --subtune");
        } else if (arg == "--capture-seconds" && (value = need())) {
            if (!parse_uint(value, capture_seconds)) return fail("invalid --capture-seconds");
        } else return fail("invalid or incomplete argument: " + arg);
    }
    if (input.empty() || trace.empty() || subtune == 0 || capture_seconds == 0)
        return fail("--input, --trace, positive --subtune and --capture-seconds are required");
    if (model != "auto" && model != "6581" && model != "8580")
        return fail("--model must be auto, 6581 or 8580");
    if (timing != "auto" && timing != "pal" && timing != "ntsc")
        return fail("--timing must be auto, pal or ntsc");

    SidTune tune(input.c_str());
    if (!tune.getStatus()) return fail(std::string("malformed/unsupported SID: ") + tune.statusString());
    const SidTuneInfo *initial = tune.getInfo();
    if (!initial) return fail("missing SID metadata");
    if (initial->sidChips() != 1) return fail("MVGMSID v1 requires exactly one SID");
    if (subtune > initial->songs()) return fail("subtune outside 1..songs");
    if (tune.selectSong(static_cast<unsigned>(subtune)) != subtune)
        return fail("libsidplayfp did not select requested subtune");
    const SidTuneInfo *info = tune.getInfo();
    if (!info) return fail("missing selected-subtune metadata");

    const bool model_override = model != "auto";
    const bool timing_override = timing != "auto";
    const SidTuneInfo::model_t source_model = info->sidModel(0);
    const SidTuneInfo::clock_t source_clock = info->clockSpeed();
    if (!model_override) {
        if (source_model == SidTuneInfo::SIDMODEL_6581) model = "6581";
        else if (source_model == SidTuneInfo::SIDMODEL_8580) model = "8580";
        else return fail("SID model metadata is unknown/any; pass --model");
    }
    if (!timing_override) {
        if (source_clock == SidTuneInfo::CLOCK_PAL) timing = "pal";
        else if (source_clock == SidTuneInfo::CLOCK_NTSC) timing = "ntsc";
        else return fail("clock metadata is unknown/any; pass --timing");
    }
    const std::uint32_t clock_hz = timing == "pal" ? PAL_HZ : NTSC_HZ;
    if (capture_seconds > std::numeric_limits<std::uint64_t>::max() / clock_hz)
        return fail("capture cycle multiplication overflow");
    const std::uint64_t capture_cycles = capture_seconds * clock_hz;

    sidplayfp player;
    SIDLiteBuilder sid("mvgmsid-capture");
    Capture capture;
    player.setSidWriteObserver(observe, &capture);
    SidConfig cfg = player.config();
    cfg.sidEmulation = &sid;
    cfg.frequency = 48000;
    cfg.samplingMethod = SidConfig::INTERPOLATE;
    cfg.powerOnDelay = 0; // deterministic C64 startup; lib adds its documented base delay
    cfg.defaultSidModel = model == "6581" ? SidConfig::MOS6581 : SidConfig::MOS8580;
    cfg.forceSidModel = model_override;
    cfg.defaultC64Model = timing == "pal" ? SidConfig::PAL : SidConfig::NTSC;
    cfg.forceC64Model = timing_override;
    if (!player.config(cfg)) return fail(std::string("config failed: ") + player.error());
    if (!player.load(&tune)) return fail(std::string("load failed: ") + player.error());
    if (player.installedSIDs() != 1) return fail("runtime installed SID count is not one");

    capture.origin = player.currentCycle();
    if (capture_cycles > std::numeric_limits<std::uint64_t>::max() - capture.origin)
        return fail("capture end cycle overflow");
    capture.end = capture.origin + capture_cycles;
    capture.active = true;
    while (player.currentCycle() < capture.end) {
        const auto before = player.currentCycle();
        if (player.play(1000) < 0) return fail(std::string("emulation failed: ") + player.error());
        if (player.currentCycle() <= before) return fail("emulator made no cycle progress");
    }
    capture.active = false;
    if (capture.invalid_time) return fail("observer reported a cycle before capture origin");

    std::ofstream out(trace, std::ios::binary | std::ios::trunc);
    if (!out) return fail("cannot create trace output");
    out << "MVGMCAP1\n";
    meta(out, "libsidplayfp_version", "3.1.1");
    meta(out, "libsidplayfp_commit", MVGMSID_LIBSIDPLAYFP_COMMIT);
    meta(out, "title_hex", info->numberOfInfoStrings() > 0 ? hex(info->infoString(0)) : "");
    meta(out, "author_hex", info->numberOfInfoStrings() > 1 ? hex(info->infoString(1)) : "");
    meta(out, "released_hex", info->numberOfInfoStrings() > 2 ? hex(info->infoString(2)) : "");
    meta(out, "format_hex", hex(info->formatString()));
    meta(out, "songs", std::to_string(info->songs()));
    meta(out, "start_song", std::to_string(info->startSong()));
    meta(out, "subtune", std::to_string(subtune));
    meta(out, "song_speed", std::to_string(info->songSpeed()));
    meta(out, "source_model", model_name(source_model));
    meta(out, "source_timing", clock_name(source_clock));
    meta(out, "model", model);
    meta(out, "timing", timing);
    meta(out, "model_override", model_override ? "true" : "false");
    meta(out, "timing_override", timing_override ? "true" : "false");
    meta(out, "clock_hz", std::to_string(clock_hz));
    meta(out, "capture_seconds", std::to_string(capture_seconds));
    meta(out, "capture_cycles", std::to_string(capture_cycles));
    meta(out, "write_count", std::to_string(capture.writes.size()));
    for (const auto &write : capture.writes)
        out << "WRITE\t" << write.cycle << '\t' << write.sid << '\t'
            << write.addr << '\t' << write.data << '\n';
    out << "END\t" << capture_cycles << '\n';
    if (!out) return fail("trace write failed");
    return 0;
}
