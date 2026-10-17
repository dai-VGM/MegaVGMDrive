#include "profile.h"
#include "../megavgm_playlist/playlist_control.h"
#include <cassert>
#include <fstream>
#include <iostream>
#include <sys/stat.h>
#include <unistd.h>
using namespace megavgm_profile;
static void word(std::vector<unsigned char> &b, unsigned at, unsigned n) {
    for (unsigned i=0;i<4;++i) b[at+i]=n>>(8*i);
}
static std::vector<unsigned char> vgm(std::initializer_list<unsigned char> commands) {
    std::vector<unsigned char> b(128,0);
    word(b,0,0x206d6756); word(b,8,0x150); word(b,0x34,0x4c);
    // Deliberately set unused clocks: they must not appear in display evidence.
    for (unsigned at : {0x0c,0x2c,0x30,0x44,0x38,0x4c}) word(b,at,1);
    // Used YM2151 metadata must describe a supported physical clock.
    word(b,0x30,4000000);
    b.insert(b.end(),commands); b.push_back(0x66); word(b,4,b.size()-4);
    return b;
}
static std::vector<unsigned char> c140_vgm(unsigned type, bool ym2151=true) {
    std::vector<unsigned char> b(0xc0,0);
    word(b,0,0x206d6756); word(b,8,0x161); word(b,0x34,0x8c);
    word(b,0xa8,12288000); b[0x96]=type;
    if (ym2151) word(b,0x30,3579545);
    const unsigned char rom[]={
        0x67,0x66,0x8d,0x08,0,0,0,
        0,0,0,0, 0,0,0,0
    };
    b.insert(b.end(),rom,rom+sizeof(rom));
    if (ym2151) b.insert(b.end(),{0x54,0x28,0x34});
    b.insert(b.end(),{0xd4,0x00,0x05,0x80,0x62,0x66});
    word(b,4,b.size()-4);
    return b;
}
static std::vector<unsigned char> md_missing_sn(
        std::initializer_list<unsigned char> commands = {0x50,0x90,0x52,0x22,0}) {
    std::vector<unsigned char> b(128,0);
    word(b,0,0x206d6756); word(b,8,0x150); word(b,0x34,0x4c);
    word(b,0x2c,7670453); word(b,0x28,9); b[0x2a]=16;
    b.insert(b.end(),commands); b.push_back(0x66); word(b,4,b.size()-4);
    return b;
}
static void write_file(const std::string &path, const std::vector<unsigned char> &bytes) {
    std::ofstream f(path, std::ios::binary);
    f.write(reinterpret_cast<const char *>(bytes.data()), bytes.size());
    assert(f.good());
}
int main() {
    auto normalize=md_missing_sn();
    const auto normalize_before=normalize;
    const auto normalization=normalize_sn76489_clock_bytes(normalize);
    assert(normalization.applied && classify_bytes(normalize).profile==Profile::A);
    assert(classify_bytes(normalize).sound_chips=="PSG,YM2612");
    assert(normalize[0x0c]==0x99 && normalize[0x0d]==0x9e &&
        normalize[0x0e]==0x36 && normalize[0x0f]==0x00);
    for (std::size_t i=0;i<normalize.size();++i)
        assert((i>=0x0c && i<0x10) || normalize[i]==normalize_before[i]);
    assert(!normalize_sn76489_clock_bytes(normalize).applied);

    auto ym_only=md_missing_sn({0x52,0x22,0});
    const auto ym_only_before=ym_only;
    assert(!normalize_sn76489_clock_bytes(ym_only).applied && ym_only==ym_only_before);
    auto missing_ym=md_missing_sn(); word(missing_ym,0x2c,0);
    assert(!normalize_sn76489_clock_bytes(missing_ym).applied);
    auto dual_ym=md_missing_sn(); word(dual_ym,0x2c,0x40000001);
    assert(!normalize_sn76489_clock_bytes(dual_ym).applied);
    auto second_sn=md_missing_sn({0x30,0x90});
    assert(!normalize_sn76489_clock_bytes(second_sn).applied);
    auto second_ym=md_missing_sn({0xa2,0x22,0});
    assert(!normalize_sn76489_clock_bytes(second_ym).applied);
    auto unsupported=md_missing_sn({0xff});
    assert(!normalize_sn76489_clock_bytes(unsupported).applied);
    auto mixed=md_missing_sn({0x50,0x90,0x54,0x22,0}); word(mixed,0x30,3579545);
    assert(!normalize_sn76489_clock_bytes(mixed).applied);
    auto non_md_block=md_missing_sn({0x50,0x90,0x67,0x66,1,0,0,0,0});
    assert(!normalize_sn76489_clock_bytes(non_md_block).applied);
    auto second_block=md_missing_sn({0x50,0x90,0x67,0x66,0,0,0,0x80});
    assert(!normalize_sn76489_clock_bytes(second_block).applied);
    auto ym2612_pcm=md_missing_sn(
        {0x50,0x90,0x67,0x66,0x00,0,0,0,0,0x52,0x22,0});
    assert(normalize_sn76489_clock_bytes(ym2612_pcm).applied);
    auto bad_loop=md_missing_sn(); word(bad_loop,0x1c,0x80-0x1c+1);
    assert(!normalize_sn76489_clock_bytes(bad_loop).applied);
    auto bad_eof=md_missing_sn(); word(bad_eof,4,bad_eof.size());
    assert(!normalize_sn76489_clock_bytes(bad_eof).applied);

    auto md=vgm({0x50,0x90,0x52,0x22,0});
    word(md,0x18,44100);
    assert(classify_bytes(md).profile==Profile::A);
    assert(classify_bytes(md).sound_chips=="PSG,YM2612");
    assert(classify_bytes(md).timing.duration_valid &&
        classify_bytes(md).timing.duration_ms==1000 &&
        !classify_bytes(md).timing.loop_valid &&
        classify_bytes(md).timing.source=="VGM_HEADER");
    auto loop_timing=md;
    word(loop_timing,0x1c,0x80-0x1c);word(loop_timing,0x20,22050);
    const auto classified_loop=classify_bytes(loop_timing);
    assert(classified_loop.profile==Profile::A && classified_loop.timing.loop_valid &&
        classified_loop.timing.loop_duration_ms==500);
    assert(classify_bytes(vgm({0x54,0x22,0,0xc0,0,0,0})).sound_chips=="YM2151,SegaPCM");
    assert(classify_bytes(vgm({0x55,0x22,0})).sound_chips=="YM2203");
    assert(classify_bytes(vgm({0xc0,0,0,0})).sound_chips=="SegaPCM");
    assert(classify_bytes(vgm({0x50,0x90})).sound_chips=="PSG");
    auto b=vgm({0x58,0x22,0});
    assert(classify_bytes(b).profile==Profile::B && classify_bytes(b).sound_chips=="YM2610");
    word(b,0x4c,0x80000001);
    assert(classify_bytes(b).profile==Profile::B && classify_bytes(b).sound_chips=="YM2610");
    auto b_channel = vgm({0x58,0xa0,0x12,0x58,0xa4,0x34,0x58,0x28,0xf0});
    word(b_channel,0x4c,0x80000001);
    assert(classify_bytes(b_channel).profile==Profile::B &&
        classify_bytes(b_channel).sound_chips=="YM2610B");
    word(b_channel,0x4c,1);
    assert(classify_bytes(b_channel).profile==Profile::B &&
        classify_bytes(b_channel).sound_chips=="YM2610");
    auto hidden_init = vgm({0x58,0x30,0x71,0x59,0x40,0x20});
    word(hidden_init,0x4c,0x80000001);
    assert(classify_bytes(hidden_init).profile==Profile::B &&
        classify_bytes(hidden_init).sound_chips=="YM2610");
    word(b,0x4c,0x40000001);
    assert(classify_bytes(b).profile==Profile::Unsupported && classify_bytes(b).sound_chips.empty());
    auto d0=c140_vgm(0);
    assert(classify_bytes(d0).profile==Profile::D);
    assert(classify_bytes(d0).sound_chips=="YM2151,C140");
    assert(classify_bytes(d0).detail.find("System 2")!=std::string::npos);
    auto d1=c140_vgm(1);
    assert(classify_bytes(d1).profile==Profile::D);
    assert(classify_bytes(d1).detail.find("System 21")!=std::string::npos);
    auto legacy=d0; word(legacy,8,0x160); legacy[0x96]=2;
    assert(classify_bytes(legacy).profile==Profile::D);
    auto d2=c140_vgm(2);
    assert(classify_bytes(d2).profile==Profile::Unsupported);
    auto unknown_d=c140_vgm(3);
    assert(classify_bytes(unknown_d).profile==Profile::Unsupported);
    auto missing_d_clock=d0; word(missing_d_clock,0xa8,0);
    assert(classify_bytes(missing_d_clock).profile==Profile::Error);
    auto dual_d=d0; word(dual_d,0xa8,0x40000001);
    assert(classify_bytes(dual_d).profile==Profile::Unsupported);
    auto missing_ym_clock=d0; word(missing_ym_clock,0x30,0);
    assert(classify_bytes(missing_ym_clock).profile==Profile::Error);
    auto c140_only=c140_vgm(0,false);
    assert(classify_bytes(c140_only).profile==Profile::D);
    assert(classify_bytes(c140_only).sound_chips=="C140");
    auto no_c140_command=d0;
    no_c140_command.erase(no_c140_command.end()-6,no_c140_command.end()-2);
    word(no_c140_command,4,no_c140_command.size()-4);
    assert(classify_bytes(no_c140_command).profile==Profile::Unsupported);
    auto no_c140_block=d0;
    no_c140_block.erase(no_c140_block.begin()+0xc0,no_c140_block.begin()+0xcf);
    word(no_c140_block,4,no_c140_block.size()-4);
    assert(classify_bytes(no_c140_block).profile==Profile::Error);
    auto mixed_d=d0;
    mixed_d.insert(mixed_d.end()-1,{0x50,0x90}); word(mixed_d,0x0c,3579545);
    word(mixed_d,4,mixed_d.size()-4);
    assert(classify_bytes(mixed_d).profile==Profile::Ambiguous);
    word(md,0x2c,0);
    assert(classify_bytes(md).profile==Profile::Error && classify_bytes(md).sound_chips.empty());
    assert(classify_bytes(vgm({0x54,0,0,0x58,0,0})).profile==Profile::Ambiguous);
    assert(classify_bytes(vgm({0x54,0,0,0x58,0,0})).sound_chips.empty());
    // Data block evidence still chooses A exactly as before; not a played chip.
    const auto data=classify_bytes(vgm({0x67,0x66,0,0,0,0,0}));
    assert(data.profile==Profile::A && data.sound_chips.empty());
    const auto invalid=classify_bytes(vgm({0xff}));
    assert(invalid.profile==Profile::Unsupported && invalid.sound_chips.empty());
    char dir[]="/tmp/megavgm-chips.XXXXXX"; assert(mkdtemp(dir));
    const std::string path=std::string(dir)+"/status";
    megavgm_playlist::PosixControllerIo io(std::string(dir)+"/cmd",path);
    megavgm_playlist::ControllerSnapshot s;
    s.state="PLAYING"; s.index=4; s.count=10; s.path="/track.vgm"; s.session=1;
    s.sound_chips="PSG,YM2612"; std::string detail;
    assert(io.publish(s,detail));
    auto read=[&]() {std::ifstream f(path); return std::string(std::istreambuf_iterator<char>(f),{});};
    assert(read().find("sound_chips=PSG,YM2612\n")!=std::string::npos);
    assert(read().find("session=1\n")!=std::string::npos);
    s.path="/next.vgm"; s.sound_chips.clear(); assert(io.publish(s,detail));
    assert(read().find("sound_chips=")==std::string::npos);
    unlink(path.c_str());

    const std::string album=std::string(dir)+"/album";
    assert(mkdir(album.c_str(),0700)==0);
    auto declared_track=vgm({0x58,0x22,0});
    const std::string track=album+"/track.vgm";
    const std::string metadata=album+"/.megavgm-sound-chip";
    write_file(track,declared_track);
    const auto intrinsic=classify_bytes(declared_track);
    assert(intrinsic.profile==Profile::B && intrinsic.sound_chips=="YM2610");
    {
        std::ofstream f(metadata); f << "version=1\nsound_chip=YM2610B\n";
    }
    const auto package_b=classify_file(track,dir);
    assert(package_b.profile==intrinsic.profile && package_b.detail==intrinsic.detail &&
        package_b.commands==intrinsic.commands && package_b.sound_chips=="YM2610B");
    {
        std::ofstream f(metadata); f << "version=1\nsound_chip=YM2610\n";
    }
    auto declared_standard=vgm({0x58,0xa0,0x12,0x58,0x28,0xf0});
    word(declared_standard,0x4c,0x80000001);
    write_file(track,declared_standard);
    const auto intrinsic_standard=classify_bytes(declared_standard);
    assert(intrinsic_standard.sound_chips=="YM2610B");
    const auto package_standard=classify_file(track,dir);
    assert(package_standard.profile==intrinsic_standard.profile &&
        package_standard.detail==intrinsic_standard.detail &&
        package_standard.commands==intrinsic_standard.commands &&
        package_standard.sound_chips=="YM2610");
    {
        std::ofstream f(metadata); f << "version=1\nsound_chip=invalid\n";
    }
    assert(classify_file(track,dir).sound_chips==intrinsic_standard.sound_chips);
    unlink(metadata.c_str()); unlink(track.c_str()); rmdir(album.c_str()); rmdir(dir);
    std::cout << "Sound chip stream/package evidence + atomic metadata regression PASS\n";
}
