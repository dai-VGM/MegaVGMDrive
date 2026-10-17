#include "switch.h"
#include "../megavgm_playlist/playback_deadline.h"
#include "../megavgm_playlist/playlist.h"
#include <cassert>
#include <cstdlib>
#include <fstream>
#include <functional>
#include <iostream>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>
using namespace megavgm_profile;
using namespace megavgm_playlist;
using namespace megavgm_autoplay2;

static void put16(std::vector<unsigned char> &b,std::size_t p,std::uint16_t v) {
    b[p]=v&255;b[p+1]=v>>8;
}
static void put32(std::vector<unsigned char> &b,std::size_t p,std::uint32_t v) {
    for(unsigned i=0;i<4;++i)b[p+i]=(v>>(8*i))&255;
}
static void put64(std::vector<unsigned char> &b,std::size_t p,std::uint64_t v) {
    for(unsigned i=0;i<8;++i)b[p+i]=(v>>(8*i))&255;
}
static std::vector<unsigned char> fixture(Profile p) {
    if (p==Profile::F) {
        std::vector<unsigned char> b(0xa8,0);put32(b,0,0x206d6756);put32(b,8,0x161);put32(b,0x34,0x74);put32(b,0xa4,3579545);
        b.insert(b.end(),{0xb9,0,0,0x62,0x66});put32(b,4,b.size()-4);return b;
    }
    if (p==Profile::D) {
        std::vector<unsigned char> b(0xc0,0);
        put32(b,0,0x206d6756); put32(b,8,0x161); put32(b,0x34,0x8c);
        put32(b,0x18,44100);
        put32(b,0x30,3579545); put32(b,0xa8,12288000); b[0x96]=0;
        const unsigned char rom[]={0x67,0x66,0x8d,0x08,0,0,0,0,0,0,0,0,0,0,0};
        b.insert(b.end(),rom,rom+sizeof(rom));
        b.insert(b.end(),{0x54,0x28,0x34,0xd4,0x00,0x05,0x80,0x62,0x66});
        put32(b,4,b.size()-4);
        return b;
    }
    std::vector<unsigned char> b(128,0);
    b[0]='V'; b[1]='g'; b[2]='m'; b[3]=' ';
    b[8]=0x50; b[9]=1; b[0x34]=0x4c;
    put32(b,0x18,44100);
    if(p==Profile::A) put32(b,0x30,4000000); else b[0x4c]=1;
    b.push_back(p==Profile::A ? 0x54 : 0x58); b.push_back(0x22); b.push_back(0);
    b.push_back(0x62); b.push_back(0x66); b[4]=b.size()-4;
    return b;
}
static std::vector<unsigned char> sid_fixture(unsigned version=2,unsigned model=1,unsigned timing=1) {
    std::vector<unsigned char> b(128,0);
    const char magic[]="MVGMSID";std::copy(magic,magic+7,b.begin());
    put16(b,8,version);put16(b,12,128);put16(b,14,version==1?16:1);
    put32(b,0x10,4);put32(b,0x14,timing==1?985248:1022727);put32(b,0x18,1);
    b[0x1c]=model;b[0x1d]=timing;b[0x1e]=1;put32(b,0x20,2);put64(b,0x38,100);
    for(unsigned i=0;i<32;++i)b[0x60+i]=i+1;
    if(version==2) {
        const unsigned char body[]={0,0,0x11,100,0xff};
        put64(b,0x28,1);put64(b,0x30,sizeof(body));b.insert(b.end(),body,body+sizeof(body));
    } else {
        put64(b,0x28,3);put64(b,0x30,48);
        std::vector<unsigned char> body(48,0);body[0]=1;body[1]=0;body[2]=0x11;
        body[16]=0;put64(body,24,100);body[32]=0xff;b.insert(b.end(),body.begin(),body.end());
    }
    return b;
}
static std::vector<unsigned char> sid_sized_fixture(std::size_t total) {
    assert(total>=130 && total<=8*1024*1024);
    auto b=sid_fixture();b.resize(128);
    const std::size_t payload=total-130;
    const std::uint64_t count=payload/3;
    const unsigned extra=payload%3;
    const std::uint64_t first_delta=extra==0?1:extra==1?128:16384;
    if(extra==0)b.push_back(1);
    else if(extra==1){b.push_back(0x80);b.push_back(1);}
    else {b.push_back(0x80);b.push_back(0x80);b.push_back(1);}
    b.push_back(0);b.push_back(0);
    for(std::uint64_t i=1;i<count;++i){b.push_back(1);b.push_back(0);b.push_back(0);}
    b.push_back(0);b.push_back(0xff);
    assert(b.size()==total);
    put64(b,0x28,count);put64(b,0x30,total-128);put64(b,0x38,first_delta+count-1);
    return b;
}
struct Sim : Runtime, SwitchHost, Client, ControllerIo {
    PlaybackStatus current{2,0,PlaybackState::Idle,0,false,0};
    Profile resident;
    SwitchOwner owner;
    Request request;
    Reply reply;
    std::uint64_t ms=0, started=0, generation=0, fade_end=0;
	int switches=0, fades=0, loads=0, stops=0, begins=0, pid=1;
    int duration=400, ack_delay=0;
    bool failed_replace=false, late_status=false, fade_completes=true;
    std::vector<std::string> loaded;
    std::vector<Profile> requested, replaced;
    std::vector<TransitionReason> transitions;
    std::vector<ControllerSnapshot> snapshots;
    PlaybackPreferences preferences;
    std::function<void(Sim&)> during_replace;
    std::function<void(Sim&)> on_discard;
    std::function<void(Sim&,const ControllerSnapshot&)> on_publish;
    std::function<ControlPollResult(Sim&, ControlCommand&)> input;
    explicit Sim(Profile p) : resident(p), owner(*this,p) {}
    bool status(PlaybackStatus &s, std::string &) override { s=current; return true; }
    std::string main_identity() override { return std::to_string(pid)+":verified"; }
    bool fade(std::string &) override { ++fades; fade_end=fade_completes ? ms+100 : 0; return true; }
    bool stop(std::string &) override { ++stops; current.state=PlaybackState::Ended; fade_end=0; return true; }
    bool replace(Profile p, std::string &d) override {
        if (failed_replace) { d="simulated RBF failure"; return false; }
        ++switches; ++pid; resident=p; replaced.push_back(p);
        current={2,0,PlaybackState::Idle,0,false,0};
        if (during_replace) during_replace(*this);
        return true;
    }
    std::uint64_t now() override { return ms; }
    bool begin(const Request &r, std::string &) override {
        ++begins; request=r; requested.push_back(r.profile); return true;
    }
    bool poll(Reply &r, std::string &) override { reply=owner.tick(request); r=reply; return true; }
    bool load_acknowledged(const Reply &r,const std::string &p,std::string &) override {
        return !late_status && ms>=started+ack_delay && generation==r.generation && r.domain==reply.domain &&
            r.main_identity==main_identity() && !loaded.empty() && loaded.back()==p;
    }
    StatusReadResult read_status(PlaybackStatus &s, std::string &) override {
        s=current;
        if (late_status && loads) { s.session=57; s.state=PlaybackState::Playing; }
        return StatusReadResult::Ok;
    }
    bool main_available(std::string &) override { return true; }
    bool owns_parked(const Reply &r,std::string &d) override {return r.main_identity==main_identity() && Client::owns_parked(r,d);}
    bool issue_load(const std::string &, std::string &) override { assert(false); return false; }
    bool issue_load_generated(const std::string &p,std::uint64_t g,std::string &) override {
        assert(reply.state=="READY" && reply.generation==g && reply.profile==resident);
        assert(current.session==reply.baseline && !fade_end);
        ++loads; loaded.push_back(p); generation=g; started=ms;
        current.session=reply.baseline+1; current.state=PlaybackState::Loading; return true;
    }
    bool issue_stop(std::string &d) override { return stop(d); }
    bool issue_transition(TransitionReason reason,std::string &) override {
        transitions.push_back(reason); return true;
    }
    std::uint64_t monotonic_ms() override { return ms; }
    void sleep_ms(std::uint32_t n) override {
        ms+=n;
        if (fade_end && ms>=fade_end) { current.state=PlaybackState::Ended; fade_end=0; }
        else if (loads && current.state==PlaybackState::Loading && ms>=started+10) current.state=PlaybackState::Playing;
        else if (loads && current.state==PlaybackState::Playing && ms>=started+duration) current.state=PlaybackState::Ended;
        if(ms>=200000) {std::cerr << "TIMEOUT loads=" << loads << " last=" << (snapshots.empty()?"NONE":snapshots.back().path) << " error=" << (snapshots.empty()?"NONE":snapshots.back().load_error) << std::endl;}
        assert(ms < 200000);
    }
    ControlPollResult poll_command(ControlCommand &c,std::string &) override { return input ? input(*this,c) : ControlPollResult::None; }
    bool discard_commands(std::string &) override {
        if (on_discard) on_discard(*this);
        return true;
    }
    bool publish(const ControllerSnapshot &s,std::string &) override {
        if (s.state=="PLAYING") {
            const std::string evidence = (is_raw_sid_name(s.path) || is_native_container_name(s.path))
				? loaded.back() : s.path;
            const auto c=classify_file(evidence,evidence.substr(0,evidence.find_last_of('/')));
            assert(s.sound_chips==c.sound_chips && !s.sound_chips.empty());
            assert(s.sid_format_version==c.sid.format_version);
            assert(s.sid_model==c.sid.model && s.sid_timing==c.sid.timing);
            assert(s.sid_subtune==c.sid.subtune && s.sid_capture_limited==c.sid.capture_limited);
            assert(s.sid_source_sha256==c.sid.source_sha256);
        }
        snapshots.push_back(s);
        if (on_publish) on_publish(*this,s);
        return true;
    }
    bool load_preferences(PlaybackPreferences &p,std::string &) override { p=preferences; return true; }
    bool save_preferences(const PlaybackPreferences &,std::string &) override { return true; }
};
struct FakePreparer : SidPreparer {
	std::string artifact;
 PreparedPlaybackTiming timing;
 PreparedPlaybackTiming playback_timing() const override { return timing; }
	int starts=0,polls=0,cancels=0,ready_after=2,active_ready_after=2;
	bool fail=false,active=false,publish_valid_on_cancel=false,cached=false;
	std::string cancel_detail;
	bool start(const std::string &,std::string &) override {
		++starts;polls=0;active=true;active_ready_after=cached?1:ready_after;return true;
	}
	SidPreparePollResult poll(std::string &path,std::string &detail) override {
		++polls;
		if(fail){active=false;detail="UNSUPPORTED_SID: fixture";return SidPreparePollResult::Failed;}
		if(polls<active_ready_after)return SidPreparePollResult::Running;
		active=false;path=artifact;return SidPreparePollResult::Ready;
	}
	std::string cancel() override { if(active){++cancels;if(publish_valid_on_cancel)cached=true;}active=false;return cancel_detail; }
};
static std::string canonical_fixture(const std::string &path) {
    char resolved[4096]; assert(realpath(path.c_str(), resolved)); return resolved;
}
static void resume_rejected(Sim &sim, const std::string &target) {
    auto prior = sim.input;
    sim.input = [prior,target,sent=false](Sim &x, ControlCommand &c) mutable {
        if (!sent && !x.snapshots.empty() && !x.snapshots.back().load_error.empty()) {
            assert(x.snapshots.back().state == "STOPPED");
            assert(x.current.state == PlaybackState::Ended || x.current.state == PlaybackState::Idle);
            sent = true; c.type = ControlCommandType::Playlist; c.path = target+".retry.snapshot";
            {std::ofstream file(c.path);file<<"MEGAVGM_PLAYLIST_V1\nNAME Retry\nSTART 0\nCOUNT 1\nPATH "<<target<<"\n";}
            chmod(c.path.c_str(),0600);
            return ControlPollResult::Command;
        }
        return prior ? prior(x,c) : ControlPollResult::None;
    };
}
static PlaylistResult play(Sim &s,const std::vector<Track> &tracks,const std::string &root,
		SidPreparer *preparer=nullptr,std::uint64_t timeout_ms=2000,
		std::uint64_t sid_prepare_timeout_ms=0,std::string *captured_log=nullptr) {
    PlaylistConfig c; c.profile_client=&s; c.approved_root=root; c.poll_interval_ms=10;
	c.sid_preparer=preparer;c.sid_cache_root=root;c.native_preparer=preparer;c.native_cache_root=root;
	c.session_timeout_ms=timeout_ms;
	c.sid_prepare_timeout_ms=sid_prepare_timeout_ms ? sid_prepare_timeout_ms : timeout_ms;
	c.playing_timeout_ms=2000; c.initial_playlist_name="Mixed test";
    std::ostringstream log;
    auto result=run(s,c,tracks,log,&s);
	if(captured_log)*captured_log=log.str();
    if (result!=PlaylistResult::Complete) std::cerr << log.str();
    return result;
}
static std::vector<unsigned char> resident_fixture(unsigned pages) {
    std::vector<unsigned char> b(192,0);put32(b,0,0x206d6756);put32(b,8,0x161);
    put32(b,0x34,192-0x34);put32(b,0xac,3579545);put32(b,0x18,44100);
    const unsigned char rom[]={0x67,0x66,0x8e,12,0,0,0,0,0,0x20,0,0,0,0,0,1,2,3,4};
    b.insert(b.end(),rom,rom+sizeof(rom));
    auto wr=[&](unsigned a,unsigned v){b.push_back(0xba);b.push_back(a);b.push_back(v);};
    for(unsigned n=0;n<6;++n){wr(40,0);wr(10,255);wr(11,255);wr(12,0);wr(13,0);wr(14,n);wr(40,1);}
    if(pages>192){wr(40,0);wr(10,0);wr(11,0);wr(12,0);wr(13,0);wr(14,6);wr(40,1);}
    b.push_back(0x66);put32(b,4,b.size()-4);return b;
}

int main() {
	assert(PlaylistConfig{}.sid_prepare_timeout_ms==120000);
    assert(std::string(rbf(Profile::A)) == "/media/fat/_Custom Cores/Cores/MegaVGMDrive_A.rbf");
    assert(std::string(rbf(Profile::B)) == "/media/fat/_Custom Cores/Cores/MegaVGMDrive_B.rbf");
    assert(std::string(rbf(Profile::C)) == "/media/fat/_Custom Cores/Cores/MegaVGMDrive_C.rbf");
    assert(std::string(rbf(Profile::D)) == "/media/fat/_Custom Cores/Cores/MegaVGMDrive_D.rbf");
    assert(std::string(rbf(Profile::Unsupported)).empty());
    auto a=fixture(Profile::A), b=fixture(Profile::B), c=sid_fixture(), d=fixture(Profile::D);
    assert(classify_bytes(a).profile==Profile::A); assert(classify_bytes(b).profile==Profile::B);
    assert(classify_bytes(d).profile==Profile::D && classify_bytes(d).sound_chips=="YM2151,C140");
    auto f=fixture(Profile::F);
    assert(classify_bytes(f).profile==Profile::F && classify_bytes(f).sound_chips=="HuC6280");
    for(unsigned bad_clock:{0u,3579544u,0x40369e99u,0x80369e99u}) {
        auto bad=f;put32(bad,0xa4,bad_clock);assert(classify_bytes(bad).profile==Profile::Unsupported);
    }
    auto mixed=f;mixed.insert(mixed.end()-1,{0x54,0,0});put32(mixed,4,mixed.size()-4);
    assert(classify_bytes(mixed).profile==Profile::Ambiguous);
    auto dual=f;dual[0xa9]=0x80;assert(classify_bytes(dual).profile==Profile::Unsupported);
    const auto classified_c=classify_bytes(c);
    assert(classified_c.profile==Profile::C && classified_c.sound_chips=="SID 6581");
    assert(classified_c.sid.format_version==2 && classified_c.sid.model=="6581" &&
        classified_c.sid.timing=="PAL" && classified_c.sid.subtune==2 &&
        classified_c.sid.capture_limited && classified_c.sid.source_sha256.size()==64);
    assert(!classified_c.timing.duration_valid && !classified_c.timing.loop_valid);
    auto timed_c=c;put32(timed_c,0x10,1);put64(timed_c,0x40,100);
    const auto classified_timed_c=classify_bytes(timed_c);
    assert(classified_timed_c.profile==Profile::C &&
        classified_timed_c.timing.duration_valid &&
        classified_timed_c.timing.duration_ms==1 &&
        classified_timed_c.timing.source=="MVGMSID_HEADER");
    auto loop_c=c;put32(loop_c,0x10,2);put64(loop_c,0x48,0);
    put64(loop_c,0x50,0);put64(loop_c,0x58,100);
    assert(classify_bytes(loop_c).profile==Profile::C);
    assert(classify_bytes(loop_c).timing.duration_valid &&
        classify_bytes(loop_c).timing.loop_valid &&
        classify_bytes(loop_c).timing.loop_duration_ms==1);
	auto wait_loop=loop_c;put64(wait_loop,0x48,1);put64(wait_loop,0x50,50);
	assert(classify_bytes(wait_loop).profile==Profile::C);
    auto bad_loop=loop_c;put64(bad_loop,0x48,2);
    assert(classify_bytes(bad_loop).profile==Profile::Error);
	bad_loop=loop_c;put64(bad_loop,0x50,11);
    assert(classify_bytes(bad_loop).profile==Profile::Error);
    bad_loop=loop_c;put64(bad_loop,0x58,99);
    assert(classify_bytes(bad_loop).profile==Profile::Error);
	auto collision=loop_c;collision.resize(128);
	const unsigned char collision_body[]={0,0,0x11,100,1,0x22,0,0xff};
	put64(collision,0x28,2);put64(collision,0x30,sizeof(collision_body));
	collision.insert(collision.end(),collision_body,collision_body+sizeof(collision_body));
	assert(classify_bytes(collision).profile==Profile::Error);
    const auto v1=sid_fixture(1,2,2); const auto classified_v1=classify_bytes(v1);
    assert(classified_v1.profile==Profile::C && classified_v1.sound_chips=="SID 8580" &&
        classified_v1.sid.format_version==1 && classified_v1.sid.timing=="NTSC");
    auto v1_loop=v1;put32(v1_loop,0x10,2);put64(v1_loop,0x58,100);
    assert(classify_bytes(v1_loop).profile==Profile::Error);
    auto bad_sid=c;bad_sid[8]=3;assert(classify_bytes(bad_sid).profile==Profile::Error);
    bad_sid=c;bad_sid.back()=0x19;assert(classify_bytes(bad_sid).profile==Profile::Error);
    bad_sid=c;bad_sid[0x10]=2;assert(classify_bytes(bad_sid).profile==Profile::Error);
    bad_sid=c;bad_sid.push_back(0);assert(classify_bytes(bad_sid).profile==Profile::Error);
    for(const auto bytes:{4*1024*1024+1,8*1024*1024-1,8*1024*1024})
        assert(classify_bytes(sid_sized_fixture(bytes)).profile==Profile::C);
    auto oversize=sid_sized_fixture(8*1024*1024);oversize.push_back(0);
    assert(classify_bytes(oversize).profile==Profile::Error);
    auto bad=a; bad[128]=0x5a; assert(classify_bytes(bad).profile==Profile::Unsupported);
    bad=a; bad.pop_back(); assert(classify_bytes(bad).profile==Profile::Error);
    bad=a; put32(bad,0x30,0); assert(classify_bytes(bad).profile==Profile::Error);
    bad=a; bad[0x33]=0x40; assert(classify_bytes(bad).profile==Profile::Unsupported);
    bad=a; bad[131]=0x58; bad.insert(bad.end()-1,{0x22,0}); bad[4]=bad.size()-4;
    assert(classify_bytes(bad).profile==Profile::Ambiguous);
    bad=a; bad[128]=0x62; bad[129]=0x62; bad[130]=0x62;
    assert(classify_bytes(bad).profile==Profile::Ambiguous);
    std::string root, detail; assert(make_channel(root,detail));
    const std::string pa=root+"/a.vgm", pb=root+"/b.vgm", pc=root+"/c.mvgmsid", pd=root+"/d.vgm";
    for (const auto &p : {pa,pb,pd}) {
        auto bytes=p==pa?a:p==pb?b:d; std::ofstream f(p,std::ios::binary); f.write(reinterpret_cast<const char*>(bytes.data()),bytes.size());
    }
    { std::ofstream f(pc,std::ios::binary);f.write(reinterpret_cast<const char*>(c.data()),c.size()); }
	const std::string pl=root+"/loop.vgm";
	auto loop_a=a;put32(loop_a,0x1c,0x80-0x1c);put32(loop_a,0x20,22050);
	{ std::ofstream f(pl,std::ios::binary);f.write(reinterpret_cast<const char*>(loop_a.data()),loop_a.size()); }
	std::vector<unsigned char> raw(124,0);const unsigned char psid_magic[]={'P','S','I','D'};
	std::copy(psid_magic,psid_magic+4,raw.begin());
	raw[5]=2;raw[7]=0x7c;raw[0x0f]=1;raw[0x11]=1;raw[0x76]=0;raw[0x77]=0x14;
	const std::string ps=root+"/source.sid";{std::ofstream f(ps,std::ios::binary);f.write(reinterpret_cast<const char*>(raw.data()),raw.size());}
	const auto raw_admission=inspect_raw_sid_for_prepare(ps,root);
	assert(raw_admission.profile==Profile::C && raw_admission.sid.model=="6581" && raw_admission.sid.timing=="PAL");
	assert(classify_file(ps,root).profile==Profile::Error);
	auto unknown_raw=raw;unknown_raw[0x77]=0;const std::string pu=root+"/unknown.sid";
	{std::ofstream f(pu,std::ios::binary);f.write(reinterpret_cast<const char*>(unknown_raw.data()),unknown_raw.size());}
	assert(inspect_raw_sid_for_prepare(pu,root).profile==Profile::C);
    std::vector<unsigned char> native(129,0);const unsigned char nm[5]={'N','E','S','M',26};
    std::copy(nm,nm+5,native.begin());native[5]=1;native[6]=28;native[7]=1;
    native[9]=native[11]=native[13]=0x80;native[123]=1;native[128]=0x60;
    assert(classify_bytes(native).profile==Profile::E);
    const std::string pe=root+"/prepared.nsf", pne=root+"/original.nsfe";
    {std::ofstream f(pe,std::ios::binary);f.write(reinterpret_cast<const char*>(native.data()),native.size());}
    std::vector<unsigned char> nsfe={'N','S','F','E'};
    const auto chunk=[&](const char *tag,const std::vector<unsigned char> &part){
        const auto n=nsfe.size();nsfe.resize(n+8);put32(nsfe,n,part.size());
        std::copy(tag,tag+4,nsfe.begin()+n+4);nsfe.insert(nsfe.end(),part.begin(),part.end());};
    chunk("INFO",{0,0x80,0,0x80,0,0x80,0,1,28,0});chunk("DATA",{0x60});chunk("NEND",{});
    assert(classify_bytes(nsfe).profile==Profile::E);
    {std::ofstream f(pne,std::ios::binary);f.write(reinterpret_cast<const char*>(nsfe.data()),nsfe.size());}
    auto invalid=native;invalid[5]=2;assert(classify_bytes(invalid).profile==Profile::Unsupported);
    invalid=native;invalid[123]=2;assert(classify_bytes(invalid).profile==Profile::Unsupported);
    invalid=native;invalid[112]=9;assert(classify_bytes(invalid).profile==Profile::Unsupported);
    invalid=nsfe;invalid.insert(invalid.begin()+4,{0,0,0,0,'N','S','F','2'});assert(classify_bytes(invalid).profile==Profile::Unsupported);
    invalid=nsfe;invalid.insert(invalid.begin()+4,{0,0,0,0,'X','X','X','X'});assert(classify_bytes(invalid).profile==Profile::Unsupported);
    {std::string channel,detail;assert(make_channel(channel,detail));
        Request request{99,1,7,Profile::F,false,"F.vgm"},decoded;
        assert(write_request(channel,request,detail) && read_request(channel,decoded,detail));
        assert(decoded.profile==Profile::F && decoded.generation==99);
        Reply reply{ };reply.profile=Profile::F;reply.generation=99;reply.state="READY";
        assert(write_reply(channel,reply,detail));Reply decoded_reply;
        assert(read_reply(channel,decoded_reply,detail) && decoded_reply.profile==Profile::F);
    }
#if defined(MEGAVGM_HOST_MSM6295) && MEGAVGM_HOST_MSM6295
    auto msm=d;msm.resize(192);put32(msm,0x98,1000000);
    std::vector<unsigned char> msm_rom(15+2048,0);
    msm_rom[0]=0x67;msm_rom[1]=0x66;msm_rom[2]=0x8b;
    put32(msm_rom,3,8+2048);put32(msm_rom,7,4096);
    msm.insert(msm.end(),msm_rom.begin(),msm_rom.end());
    msm.insert(msm.end(),{0x54,0x20,0xc0,0xb8,0,0x80,0xb8,0,0x10,0x62,0x66});
    put32(msm,4,msm.size()-4);
    const std::string pm=root+"/MSM.vgm";
    {std::ofstream file(pm,std::ios::binary);file.write(reinterpret_cast<const char*>(msm.data()),msm.size());}
    assert(classify_file(pm,root).profile==Profile::D && classify_file(pm,root).sound_chips=="YM2151,MSM6295");
    for(const auto from:{Profile::A,Profile::B,Profile::C,Profile::D,Profile::E,Profile::F}) {
        Sim sim(from);assert(play(sim,{{"MSM",pm}},root)==PlaylistResult::Complete);
        assert(sim.loads==1 && sim.resident==Profile::D && sim.loaded[0]==pm);
    }
    {Sim sim(Profile::D);assert(play(sim,{{"MSM",pm},{"C140",pd},{"MSM",pm}},root)==PlaylistResult::Complete);
        assert(sim.loads==3 && sim.switches==0 && sim.current.session==3);}
    {std::string channel,detail;assert(make_channel(channel,detail));
        Request a{19,1,7,Profile::D,false,pm},decoded;assert(write_request(channel,a,detail)&&read_request(channel,decoded,detail));
        assert(decoded.profile==Profile::D&&decoded.path==pm&&decoded.generation==19);
        Reply reply;reply.profile=Profile::D;reply.generation=19;reply.state="READY";
        assert(write_reply(channel,reply,detail));Reply received;assert(read_reply(channel,received,detail)&&received.profile==Profile::D);}
    if(const char *list=std::getenv("MEGAVGM_MSM_CORPUS_LIST")) {
        const char *corpus_root=std::getenv("MEGAVGM_MSM_CORPUS_ROOT");assert(corpus_root);
        std::ifstream input(list);std::string path;std::vector<Track> tracks;
        while(std::getline(input,path))if(!path.empty())tracks.push_back({"MSM real",path});
        assert(tracks.size()==64);Sim sim(Profile::A);assert(play(sim,tracks,corpus_root)==PlaylistResult::Complete);
        assert(sim.loads==64&&sim.switches==1&&sim.resident==Profile::D&&sim.current.session==64);
        for(unsigned i=0;i<64;++i)assert(sim.loaded[i]==tracks[i].path);
        std::cout<<"MSM_REAL64_GENERIC_CONTROLLER_ROUTE_PASS; mock Main, no audio/hardware\n";
    }
#endif
    const std::string pf=root+"/F.vgm";{std::ofstream stream(pf,std::ios::binary);stream.write(reinterpret_cast<const char*>(f.data()),f.size());}
    for(const auto from:{Profile::A,Profile::B,Profile::C,Profile::D,Profile::E,Profile::F}) {
        Sim sim(from);assert(play(sim,{{"F",pf}},root)==PlaylistResult::Complete);
        assert(sim.loads==1 && sim.resident==Profile::F && sim.loaded[0]==pf);
    }
    {Sim sim(Profile::F);assert(play(sim,{{"F",pf},{"A",pa}},root)==PlaylistResult::Complete);
        assert(sim.loads==2 && sim.resident==Profile::A && sim.switches==1 && sim.fades==0);}
    {Sim sim(Profile::F);sim.duration=1000;bool selected=false;
        sim.input=[&](Sim &x,ControlCommand &command){
            if(!selected && x.loads==1 && x.current.state==PlaybackState::Playing && x.ms>=x.started+30) {
                selected=true;command.type=ControlCommandType::Next;return ControlPollResult::Command;
            }return ControlPollResult::None;
        };
        assert(play(sim,{{"F",pf},{"A",pa}},root)==PlaylistResult::Complete);
        assert(selected && sim.fades==1 && sim.switches==1 && sim.loads==2);
    }
    for(const auto from:{Profile::A,Profile::B,Profile::C,Profile::D,Profile::E,Profile::F}) {
        Sim sim(from);FakePreparer provider;provider.artifact=pe;
        assert(play(sim,{{"original.nsfe",pne}},root,&provider)==PlaylistResult::Complete);
        assert(provider.starts==1 && sim.loads==1 && sim.loaded[0]==pe && sim.resident==Profile::E);
        for(const auto &snapshot:sim.snapshots)if(snapshot.state=="PLAYING")assert(snapshot.path==pne);
    }
    for(const auto to:{Profile::A,Profile::B,Profile::C,Profile::D}) {
        Sim sim(Profile::E);const auto path=to==Profile::A?pa:to==Profile::B?pb:to==Profile::C?pc:pd;
        assert(play(sim,{{"old",path}},root)==PlaylistResult::Complete && sim.resident==to);
    }
    {Sim sim(Profile::A);FakePreparer provider;provider.artifact=pe;provider.fail=true;
        resume_rejected(sim,pa);
        assert(play(sim,{{"original.nsfe",pne}},root,&provider)==PlaylistResult::Complete && sim.loads>=1 && sim.loaded.front()==canonical_fixture(pa));}
    {Sim sim(Profile::A);FakePreparer provider;provider.artifact=pe;bool sent=false;provider.ready_after=20;
        bool resumed=false;
        sim.input=[&](Sim &x,ControlCommand &command){if(!sent && provider.starts){sent=true;command.type=ControlCommandType::Stop;return ControlPollResult::Command;}if(sent && !resumed && x.reply.state=="STOPPED"){resumed=true;command.type=ControlCommandType::Next;return ControlPollResult::Command;}return ControlPollResult::None;};
        assert(play(sim,{{"original.nsfe",pne},{"a",pa}},root,&provider)==PlaylistResult::Complete && sim.loads==1 && sim.loaded[0]==pa && provider.cancels==1);}
    if(const char *preparer_path=std::getenv("MEGAVGM_NATIVE_PREPARER_TEST")) {
        const char *source_path=std::getenv("MEGAVGM_NATIVE_SOURCE_TEST");
        const char *cache_path=std::getenv("MEGAVGM_NATIVE_CACHE_TEST");assert(source_path&&cache_path);
        struct RealSim : Sim {RealSim():Sim(Profile::A){duration=100000000;} bool issue_stop(std::string &) override {fade_end=ms+100;return true;} void sleep_ms(std::uint32_t n) override {usleep(1000);Sim::sleep_ms(n);}} sim;
        PosixSidPreparer provider(preparer_path,cache_path,"",".nsf",true);
        PlaylistConfig config;config.profile_client=&sim;config.native_preparer=&provider;
        config.native_cache_root=cache_path;config.approved_root="/Users/daizo/Projects/VGM";
        config.poll_interval_ms=10;config.session_timeout_ms=60000;config.playing_timeout_ms=2000;
        std::ostringstream log;
        assert(run(sim,config,{{"AkumajouDensetsu.nsfe",source_path}},log,&sim)==PlaylistResult::Complete);
        assert(sim.loads==1 && sim.resident==Profile::E && sim.loaded[0]!=source_path);
        assert(log.str().find("source=METADATA_END")!=std::string::npos);
        std::cout<<log.str()<<"ACTUAL_GO_PREPARER_ORIGINAL_NSFE_TO_MAIN_INDEX1: PASS\n";
    }

    // Real Controller + SwitchOwner; E has no natural EOF in this model.
    struct TimedSim : Sim {
        std::vector<std::uint64_t> requests_at;
        bool fail_fade=false, lose_owner=false, missing_end=false;
        TimedSim():Sim(Profile::E){}
        bool issue_stop(std::string &detail) override {
            if(fail_fade){detail="injected fade write failure";return false;}
            requests_at.push_back(ms);
            if(!fade_end&&!missing_end)fade_end=ms+100;
            return true;
        }
        bool load_acknowledged(const Reply &r,const std::string &p,std::string &d) override {
            return !(lose_owner && ms>=started+50) && Sim::load_acknowledged(r,p,d);
        }
        void sleep_ms(std::uint32_t n) override {
            const int old=duration;
            if(resident==Profile::E)duration=100000000;
            Sim::sleep_ms(n);duration=old;
        }
        bool replace(Profile p,std::string &d) override {
            // No successor RBF before the actual resident ENDED.
            assert(current.state==PlaybackState::Ended || current.state==PlaybackState::Idle);
            return Sim::replace(p,d);
        }
    };
    auto provider_for=[&](std::uint64_t target){FakePreparer p;p.artifact=pe;p.timing.valid=true;
        p.timing.target_ms=target;p.timing.physical=1;return p;};
    {
        PlaybackDeadline timer;
        assert(!timer.due(1,1,0));timer.arm(9,1,1000,90850);
        assert(!timer.due(9,1,91749));assert(timer.due(9,1,91750));
        assert(!timer.due(10,1,91750));assert(!timer.due(9,2,91750));
        timer.requested();assert(!timer.due(9,1,999999));timer.cancel();
        timer.arm(10,2,5000,0);assert(!timer.due(10,2,4999));assert(timer.due(10,2,5000));
        timer.cancel();assert(!timer.due(10,2,9000));
        timer.arm(11,1,0,4294967294ULL);assert(!timer.due(11,1,4294967193ULL));
        assert(timer.due(11,1,4294967194ULL));
    }
    for(const auto target:{0u,1u,99u,100u,101u,150u,300u,1850u,90850u}) {
        TimedSim sim;auto provider=provider_for(target);std::string log;
        std::uint64_t t0=0;sim.on_publish=[&](Sim &x,const ControllerSnapshot &v){if(!t0&&x.loads==1&&v.state=="PLAYING")t0=x.ms;};
        assert(play(sim,{{"original.nsfe",pne},{"F",pf}},root,&provider,2000,0,&log)==PlaylistResult::Complete);
        assert(sim.loads==2 && sim.switches==1 && sim.resident==Profile::F);
        assert(sim.requests_at.size()==1 && sim.fades==0);
        const auto arm=sim.requests_at.front();
        // Measure observed owned PLAYING, excluding preparation; poll granularity <=10ms.
        const auto elapsed=arm-t0;
        const auto expected=target>100?target-100:0;
        assert(elapsed>=expected && elapsed<expected+10);
        assert(log.find("source=METADATA_END")!=std::string::npos);
        bool telemetry=false;for(const auto &v:sim.snapshots)if(v.path==pne&&v.state=="PLAYING"){
            telemetry=true;assert(v.planned_duration=="FINITE" && v.planned_duration_ms==std::max<std::uint64_t>(target,100));}
        assert(telemetry);
        assert(log.find("STOPPED")==std::string::npos);
    }
    // Unspecified time and legacy NSF never issue timer control.
    for(const auto &path:{pne,pe}) {
        TimedSim sim;FakePreparer provider;provider.artifact=pe;
        PlaylistConfig c;c.profile_client=&sim;c.native_preparer=&provider;c.native_cache_root=root;
        c.approved_root=root;c.poll_interval_ms=10;c.end_timeout_ms=250;
        std::ostringstream log;
        assert(run(sim,c,{{"old.nsf",path}},log,&sim)==PlaylistResult::TrackEndTimeout);
        assert(sim.requests_at.empty() && sim.loads==1);
    }
    // Stale status or Main/lease ownership loss must never fire a timer.
    {
        TimedSim sim;auto provider=provider_for(300);bool changed=false;
        sim.input=[&](Sim &x,ControlCommand &){if(!changed && x.ms>=100){changed=true;x.current.session++;}
            return ControlPollResult::None;};
        assert(play(sim,{{"original.nsfe",pne}},root,&provider)==PlaylistResult::Suspended);
        assert(sim.requests_at.empty());
    }
    {
        TimedSim sim;sim.lose_owner=true;auto provider=provider_for(300);
        assert(play(sim,{{"original.nsfe",pne}},root,&provider)==PlaylistResult::CommandWriteFailed);
        assert(sim.requests_at.empty());
    }
    {
        TimedSim sim;sim.fail_fade=true;auto provider=provider_for(300);
        assert(play(sim,{{"original.nsfe",pne},{"F",pf}},root,&provider)==PlaylistResult::CommandWriteFailed);
        assert(sim.loads==1 && sim.switches==0);
    }
    {
        TimedSim sim;sim.missing_end=true;auto provider=provider_for(300);
        PlaylistConfig c;c.profile_client=&sim;c.native_preparer=&provider;c.native_cache_root=root;
        c.approved_root=root;c.poll_interval_ms=10;c.stop_timeout_ms=250;
        std::ostringstream log;
        assert(run(sim,c,{{"original.nsfe",pne},{"F",pf}},log,&sim)==PlaylistResult::StopTimeout);
        assert(sim.loads==1 && sim.switches==0 && sim.requests_at.size()==1);
    }
    // Next before deadline, exactly at deadline, and during the 100ms fade.
    for(const auto at:{100u,230u,260u}) {
        TimedSim sim;auto provider=provider_for(300);bool next=false;
        sim.input=[&](Sim &x,ControlCommand &c){if(!next&&x.ms>=at){next=true;c.type=ControlCommandType::Next;return ControlPollResult::Command;}
            return ControlPollResult::None;};
        assert(play(sim,{{"original.nsfe",pne},{"F",pf}},root,&provider)==PlaylistResult::Complete);
        assert(sim.loads==2 && sim.switches==1 && sim.requests_at.size()==(at>230?1u:0u));
    }
    // Stop cancels automatic advance. A later Reload starts a fresh timer.
    const std::string reload_snapshot=root+"/timed-reload.snapshot";

    for(const auto at:{100u,230u,260u}) {
    {std::ofstream o(reload_snapshot);o<<"MEGAVGM_PLAYLIST_V1\nNAME Reload\nSTART 0\nCOUNT 1\nPATH "<<pne<<"\n";}
        TimedSim sim;auto provider=provider_for(300);bool stopped=false,resumed=false;
        sim.input=[&](Sim &x,ControlCommand &c){
            if(!stopped&&x.ms>=at){stopped=true;c.type=ControlCommandType::Stop;return ControlPollResult::Command;}
            if(stopped&&!resumed&&!x.snapshots.empty()&&x.snapshots.back().state=="STOPPED"){
                resumed=true;c.type=ControlCommandType::Playlist;c.path=reload_snapshot;return ControlPollResult::Command;}
            return ControlPollResult::None;};
        assert(play(sim,{{"original.nsfe",pne}},root,&provider)==PlaylistResult::Complete);
        assert(sim.loads==2 && sim.switches==0 && provider.starts==2);
        // Stop during the automatic tail joins the existing request; Reload
        // alone rearms the next session. One request per session in all cases.
        assert(sim.requests_at.size()==2);
        assert(sim.requests_at.back()>=sim.started+200);
    }
    unlink(reload_snapshot.c_str());
    // ONE reloads this finite timed track; ALL/Shuffle reuse the queue bag.
    for(const auto mode:{RepeatMode::One,RepeatMode::All}) {
        TimedSim sim;auto provider=provider_for(300);sim.preferences.repeat=mode;
        sim.preferences.shuffle=mode==RepeatMode::All;bool changed=false;
        sim.input=[&](Sim &x,ControlCommand &c){if(!changed&&x.loads>=3&&x.current.state==PlaybackState::Playing){
            changed=true;c.type=ControlCommandType::Repeat;c.repeat=RepeatMode::Off;return ControlPollResult::Command;}
            return ControlPollResult::None;};
        const auto queue=mode==RepeatMode::One?std::vector<Track>{{"original.nsfe",pne}}:
            std::vector<Track>{{"original.nsfe",pne},{"F",pf}};
        assert(play(sim,queue,root,&provider)==PlaylistResult::Complete);
        assert(sim.loads>=3 && provider.starts>=2);
        if(mode==RepeatMode::One)assert(sim.switches==0 && sim.requests_at.size()==3);
        else for(std::size_t i=1;i<sim.loaded.size();++i)assert(sim.loaded[i]!=sim.loaded[i-1]);
    }
    std::cout<<"NSFe timed Controller: boundaries/unknown/NSF/stale/owner/failure/Next/Stop/Reload/ONE/ALL/Shuffle/E-F PASS\n";
    std::cout<<"Engine E native registration, rejection, A-D switches, preparation failure/Stop: PASS\n";
    assert(classify_file(pa,root).profile==Profile::A);
    assert(classify_file(pd,root).profile==Profile::D);
    assert(classify_file(pl,root).timing.loop_valid &&
        classify_file(pl,root).timing.loop_duration_ms==500);
    assert(classify_file(pa,"/nonexistent").profile==Profile::Error);
    Request q{5,1,57,Profile::B,false,pb}; assert(write_request(root,q,detail)); Request qr;
    assert(read_request(root,qr,detail) && qr.generation==5 && qr.path==pb);
    Reply rr{5,2,0,Profile::B,"3:123","READY",""}; assert(write_reply(root,rr,detail)); Reply read;
    assert(read_reply(root,read,detail) && read.domain==2);
    Request qd{6,2,0,Profile::D,false,pd}; assert(write_request(root,qd,detail));
    assert(read_request(root,qr,detail) && qr.profile==Profile::D && qr.path==pd);
    {
        std::ifstream wire(root+"/request"); std::string record;
        std::getline(wire,record);
        assert(record.rfind("MGS1 6 2 0 6 0 ",0)==0);
    }
#ifdef __linux__
    {
        const std::string ack=root+"/main.status";
        FileClient client(root,ack);
        rr.main_identity=process_identity(getpid()); assert(!rr.main_identity.empty());
        assert(write_reply(root,rr,detail));
        auto witness=[&](int pid,int gen,int valid,int idx) {
            std::ofstream f(ack);
            f << "version=2\npid=" << pid << "\nphase=TRANSFER_SUCCESS\ncommand_seq=1\ngeneration_valid=" << valid
              << "\ngeneration=" << gen << "\nindex=" << idx << "\npath=" << pb << '\n';
        };
        witness(getpid(),5,1,1); assert(client.load_acknowledged(rr,pb,detail));
        witness(getpid(),4,1,1); assert(!client.load_acknowledged(rr,pb,detail));
        witness(getpid()+1,5,1,1); assert(!client.load_acknowledged(rr,pb,detail));
        witness(getpid(),5,0,1); assert(!client.load_acknowledged(rr,pb,detail));
        witness(getpid(),5,1,2); assert(!client.load_acknowledged(rr,pb,detail));
        witness(getpid(),5,1,1); assert(!client.load_acknowledged(rr,pa,detail));
        auto newer=rr; newer.generation=6; assert(write_reply(root,newer,detail));
        assert(!client.load_acknowledged(rr,pb,detail));
        unlink(ack.c_str());
    }
#endif
    auto tracks = [&](const std::string &sequence) {
		std::vector<Track> t; for (char p:sequence) t.push_back({std::string(1,p),p=='A'?pa:p=='B'?pb:p=='C'?pc:pd}); return t;
    };
	// Controller time begins only at its first owned PLAYING observation. The
	// validated one-second VGM plus the production 100 ms natural fade is the
	// finite planned end; polling updates elapsed while PLAYING and freezes it
	// at ENDED.
	{
		Sim s(Profile::A);s.duration=80;
		assert(play(s,{{"timed",pa}},root)==PlaylistResult::Complete);
		std::uint64_t last=0;bool advanced=false,ended=false;
		for(const auto &snapshot:s.snapshots){
			if(snapshot.state=="PLAYING"){
				assert(snapshot.planned_duration=="FINITE");
				assert(snapshot.planned_duration_ms==1100);
				assert(snapshot.duration_source=="VGM_HEADER+NATURAL_FADE_100MS");
				advanced|=snapshot.elapsed_ms>last;last=snapshot.elapsed_ms;
			}
			if(snapshot.state=="ENDED"){
				ended=true;assert(snapshot.elapsed_ms>=last);
			}
		}
		assert(advanced&&ended);
	}
	{
		Sim s(Profile::C);s.duration=40;
		assert(play(s,{{"capture-limited",pc}},root)==PlaylistResult::Complete);
		bool checked=false;for(const auto &snapshot:s.snapshots)
			if(snapshot.state=="PLAYING"){
				checked=true;assert(snapshot.planned_duration=="UNKNOWN");
				assert(snapshot.planned_duration_ms==0);
			}
		assert(checked);
	}
	// TWO_LOOPS plays the first stream traversal plus one additional loop
	// traversal. Its fade is inside loop 2, so no natural-EOF tail is added.
	{
		Sim s(Profile::A);s.duration=40;
		assert(play(s,{{"loop",pl}},root)==PlaylistResult::Complete);
		bool checked=false;for(const auto &snapshot:s.snapshots)
			if(snapshot.state=="PLAYING"){
				checked=true;assert(snapshot.planned_duration=="FINITE");
				assert(snapshot.planned_duration_ms==1500);
				assert(snapshot.duration_source=="VGM_HEADER+TWO_LOOPS");
			}
		assert(checked);
	}
	// Repeat One is explicitly unbounded. Once its first public PLAYING record
	// proves infinity, switch back to Repeat Off so this finite fixture exits.
	{
		Sim s(Profile::A);s.duration=50;s.preferences.repeat=RepeatMode::One;
		bool published=false,disabled=false;
		s.on_publish=[&](Sim &,const ControllerSnapshot &snapshot){
			if(snapshot.state=="PLAYING"&&!published)published=true;
		};
		s.input=[&](Sim &,ControlCommand &command){
			if(published&&!disabled){disabled=true;command.type=ControlCommandType::Repeat;
				command.repeat=RepeatMode::Off;return ControlPollResult::Command;}
			return ControlPollResult::None;
		};
		assert(play(s,{{"loop",pl}},root)==PlaylistResult::Complete);
		bool infinite=false,finite=false;for(const auto &snapshot:s.snapshots)
			if(snapshot.state=="PLAYING"){
				infinite|=snapshot.planned_duration=="INFINITE";
				finite|=snapshot.planned_duration=="FINITE";
			}
		assert(infinite&&finite);
	}
	{
		Sim s(Profile::A);s.duration=100;int commands=0;
		s.input=[&](Sim &x,ControlCommand &command){
			if(commands==0&&x.loads==1&&x.current.state==PlaybackState::Playing&&
			   x.ms>=x.started+30){++commands;command.type=ControlCommandType::Stop;
				return ControlPollResult::Command;}
			if(commands==1&&x.current.state==PlaybackState::Ended){++commands;
				command.type=ControlCommandType::Next;return ControlPollResult::Command;}
			return ControlPollResult::None;
		};
		assert(play(s,{{"timed",pa}},root)==PlaylistResult::Complete);
		bool stopped=false;for(const auto &snapshot:s.snapshots)
			if(snapshot.state=="STOPPED"){
				stopped=true;assert(snapshot.elapsed_ms==0);
			}
		assert(stopped&&commands==2);
	}
    const auto profile_for=[](char p){return p=='A'?Profile::A:p=='B'?Profile::B:p=='C'?Profile::C:Profile::D;};
    for (const auto &sequence : {"AAA","BBB","CCC","DDD","AABBA","CCCCC","DDDD","ACCA","BCB","ABCBA","ACBCA","ABCDA"}) {
		Sim s(profile_for(sequence[0]));
        assert(play(s,tracks(sequence),root)==PlaylistResult::Complete);
        int expected=0; for (std::size_t i=1;i<std::string(sequence).size();++i) expected+=sequence[i]!=sequence[i-1];
        assert(s.switches==expected && s.loads==int(std::string(sequence).size()));
        for (const auto &v:s.snapshots) assert(v.count==std::string(sequence).size() && v.playlist=="Mixed test");
        std::cout << sequence << " switch=" << s.switches << " loads=" << s.loads << " PASS\n";
    }
    // Remote HandlePlay reaches this exact Controller PLAY command path. Keep
    // it distinct from Next and PLAYLIST snapshot coverage: the selected file
    // is rediscovered in its parent directory, classified, encoded on MGS1,
    // decoded by SwitchOwner, and used as the replacement target.
    std::vector<std::string> direct_paths;
    auto direct_fixture = [&](char label) {
        const Profile profile=profile_for(label);
        const std::string directory=root+"/direct-"+label;
        assert(mkdir(directory.c_str(),0700)==0);
        const std::string path=directory+"/target"+
            (profile==Profile::C ? ".mvgmsid" : ".vgm");
        const auto bytes=profile==Profile::A?a:profile==Profile::B?b:
            profile==Profile::C?c:d;
        {std::ofstream f(path,std::ios::binary);f.write(
            reinterpret_cast<const char*>(bytes.data()),bytes.size());}
        direct_paths.push_back(path);
        return path;
    };
    const std::string direct_a=direct_fixture('A');
    const std::string direct_b=direct_fixture('B');
    const std::string direct_c=direct_fixture('C');
    const std::string direct_d=direct_fixture('D');
    auto direct_play = [&](Profile resident,const Track &current,
            const std::string &target,Profile expected) {
        Sim s(resident);s.duration=1000;bool sent=false;
        s.input=[&](Sim &x,ControlCommand &command) {
            if(!sent&&x.loads==1&&x.current.state==PlaybackState::Playing&&
                    x.ms>=x.started+30){
                sent=true;command.type=ControlCommandType::Play;
                command.path=target;return ControlPollResult::Command;
            }
            return ControlPollResult::None;
        };
        assert(play(s,{current},root)==PlaylistResult::Complete);
        assert(sent&&s.loads==2&&s.switches==1&&s.resident==expected);
        assert(s.requested==std::vector<Profile>({resident,expected}));
        assert(s.replaced==std::vector<Profile>({expected}));
        assert(s.loaded.back()==target);
    };
    direct_play(Profile::A,{"A",pa},direct_b,Profile::B);
    direct_play(Profile::A,{"A",pa},direct_c,Profile::C);
    direct_play(Profile::A,{"A",pa},direct_d,Profile::D);
    direct_play(Profile::D,{"D",pd},direct_a,Profile::A);
    // After any controller start/restart, PLAYING is the public
    // navigation-ready boundary. A direct PLAY written as soon as that first
    // snapshot is published must survive for both a resident profile reuse and
    // a cross-profile switch, then own generation 2.
    auto immediate_direct_play = [&](Profile resident,const Track &current,
            const std::string &target,Profile expected,int expected_switches) {
        Sim s(resident);s.duration=1000;
        bool published=false,pending=false,claimed=false,discarded=false;
        s.on_publish=[&](Sim &x,const ControllerSnapshot &snapshot) {
            if(!published&&x.loads==1&&snapshot.state=="PLAYING") {
                published=true;pending=true;
            }
        };
        s.on_discard=[&](Sim &) {
            if(pending){pending=false;discarded=true;}
        };
        s.input=[&](Sim &,ControlCommand &command) {
            if(!pending)return ControlPollResult::None;
            pending=false;claimed=true;command.type=ControlCommandType::Play;
            command.path=target;return ControlPollResult::Command;
        };
        assert(play(s,{current},root)==PlaylistResult::Complete);
        assert(published&&claimed&&!discarded);
        assert(s.loads==2&&s.begins==2&&s.request.generation==2);
        assert(s.transitions.size()==2&&s.switches==expected_switches);
        assert(s.requested==std::vector<Profile>({resident,expected}));
        assert(s.resident==expected&&s.loaded.back()==target);
    };
    immediate_direct_play(Profile::A,{"A",pa},direct_a,Profile::A,0);
    immediate_direct_play(Profile::A,{"A",pa},direct_d,Profile::D,1);
	// The owned-load boundary is earlier than public PLAYING. Direct intent
	// received while the first FPGA session is still LOADING is deferred, then
	// claimed only after that session reaches PLAYING. Generation 2 is therefore
	// allocated by the real replacement request, not by the defer operation.
	auto loading_direct_play = [&](Profile resident,const Track &current,
			const std::string &target,Profile expected,int expected_switches) {
		Sim s(resident);s.duration=1000;
		bool offered=false,claimed=false;
		s.input=[&](Sim &x,ControlCommand &command) {
			if(offered||x.loads!=1||x.current.state!=PlaybackState::Loading)
				return ControlPollResult::None;
			offered=true;claimed=true;command.type=ControlCommandType::Play;
			command.path=target;return ControlPollResult::Command;
		};
		assert(play(s,{current},root)==PlaylistResult::Complete);
		assert(offered&&claimed);
		assert(s.loads==2&&s.begins==2&&s.request.generation==2);
		assert(s.transitions.size()==2&&s.switches==expected_switches);
		assert(s.requested==std::vector<Profile>({resident,expected}));
		assert(s.resident==expected&&s.loaded.back()==target);
	};
	loading_direct_play(Profile::A,{"A",pa},direct_a,Profile::A,0);
	loading_direct_play(Profile::A,{"A",pa},direct_d,Profile::D,1);
	// Raw SID identity remains the queue/status path while only the validated
	// prepared cache artifact reaches PROFILE_C and Main index-1.
	{
		Sim s(Profile::A);FakePreparer prep;prep.artifact=pc;
		assert(play(s,{{"source.sid",ps}},root,&prep)==PlaylistResult::Complete);
		assert(prep.starts==1 && prep.polls==2 && s.switches==1 && s.loads==1);
		assert(s.loaded[0]==pc);
		bool preparing=false;for(const auto &snapshot:s.snapshots){
			if(snapshot.state=="PREPARING"){preparing=true;assert(snapshot.path==ps);}
			if(snapshot.state=="PLAYING")assert(snapshot.path==ps && snapshot.sid_format_version==2);
		}
		assert(preparing);
	}
	// A newer navigation intent cancels conversion; the stale artifact cannot
	// become a request or index-1 load.
	{
		Sim s(Profile::C);FakePreparer prep;prep.artifact=pc;prep.ready_after=20;bool sent=false;
		s.input=[&](Sim &,ControlCommand &command){if(!sent&&prep.polls>=1){sent=true;command.type=ControlCommandType::Next;return ControlPollResult::Command;}return ControlPollResult::None;};
		assert(play(s,{{"source.sid",ps},{"a",pa}},root,&prep)==PlaylistResult::Complete);
		assert(prep.cancels==1 && s.loads==1 && s.loaded[0]==pa);
	}
	{
		Sim s(Profile::C);FakePreparer prep;prep.artifact=pc;prep.ready_after=20;bool sent=false;
		s.input=[&](Sim &,ControlCommand &command){if(!sent&&prep.polls>=1){sent=true;command.type=ControlCommandType::Previous;return ControlPollResult::Command;}return ControlPollResult::None;};
		assert(play(s,{{"source.sid",ps}},root,&prep)==PlaylistResult::Complete);
		assert(prep.cancels==1 && prep.starts==2 && s.loads==1 && s.loaded[0]==pc);
	}
	{
		Sim s(Profile::C);FakePreparer prep;prep.artifact=pc;prep.ready_after=20;bool sent=false;
		s.input=[&](Sim &,ControlCommand &command){if(!sent&&prep.polls>=1){sent=true;command.type=ControlCommandType::Play;command.path=pa;return ControlPollResult::Command;}return ControlPollResult::None;};
		assert(play(s,{{"source.sid",ps}},root,&prep)==PlaylistResult::Complete);
		assert(prep.cancels==1 && s.loads>=1 && s.loaded[0]==pa);
	}
	{
		Sim s(Profile::C);FakePreparer prep;prep.artifact=pc;prep.ready_after=20;int commands=0;
		s.input=[&](Sim &x,ControlCommand &command){
			if(commands==0&&prep.polls>=1){++commands;command.type=ControlCommandType::Stop;return ControlPollResult::Command;}
			if(commands==1&&x.reply.state=="STOPPED"){++commands;command.type=ControlCommandType::Next;return ControlPollResult::Command;}
			return ControlPollResult::None;
		};
		assert(play(s,{{"source.sid",ps},{"a",pa}},root,&prep)==PlaylistResult::Complete);
		assert(prep.cancels==1 && s.loads==1 && s.loaded[0]==pa);
	}
	{
		Sim s(Profile::C);FakePreparer prep;prep.artifact=pc;prep.fail=true;
		resume_rejected(s,pa);
        assert(play(s,{{"source.sid",ps}},root,&prep)==PlaylistResult::Complete);
        assert(s.loads>=1 && s.loaded.front()==canonical_fixture(pa));
	}
	// Completion immediately before the watchdog and exactly on its boundary
	// wins because poll observes the child result before testing the deadline.
	for (const int ready_poll : {199, 200}) {
		Sim s(Profile::C);FakePreparer prep;prep.artifact=pc;prep.ready_after=ready_poll;
		assert(play(s,{{"source.sid",ps}},root,&prep)==PlaylistResult::Complete);
		assert(prep.cancels==0 && s.begins==1 && s.loads==1);
	}
	// A converter taking 75 seconds completes under the production 120-second
	// prepare budget without widening the ordinary 60-second session budget.
	{
		Sim s(Profile::C);FakePreparer prep;prep.artifact=pc;prep.ready_after=7500;
		assert(play(s,{{"source.sid",ps}},root,&prep,60000,120000)==PlaylistResult::Complete);
		assert(prep.cancels==0 && s.begins==1 && s.loads==1);
	}
	// The same poll-first boundary contract applies at the production deadline:
	// completion exactly at 120 seconds wins; a Running result there times out.
	{
		Sim s(Profile::C);FakePreparer prep;prep.artifact=pc;prep.ready_after=12000;
		assert(play(s,{{"source.sid",ps}},root,&prep,60000,120000)==PlaylistResult::Complete);
	}
	{
		Sim s(Profile::C);FakePreparer prep;prep.artifact=pc;prep.ready_after=12001;
		assert(play(s,{{"source.sid",ps}},root,&prep,60000,120000)==PlaylistResult::TrackSessionTimeout);
		assert(prep.cancels==1 && s.begins==0 && s.loads==0);
		for(const auto &snapshot:s.snapshots)assert(snapshot.state!="PLAYING");
	}
	// Cleanup failures returned by the preparer remain visible in the
	// controller log without changing cancellation or timeout results.
	{
		Sim s(Profile::C);FakePreparer prep;prep.artifact=pc;prep.ready_after=201;
		prep.cancel_detail="fixture cleanup denied";std::string log;
		assert(play(s,{{"source.sid",ps}},root,&prep,2000,2000,&log)==PlaylistResult::TrackSessionTimeout);
		assert(log.find("SID_TEMP_CLEANUP_FAILED")!=std::string::npos);
		assert(log.find("fixture cleanup denied")!=std::string::npos);
	}
	// The first Running observation at/after the deadline invalidates the
	// prepare generation, cancels/reaps it, and cannot issue a profile request,
	// index-1 load, or PLAYING publication.
	{
		Sim s(Profile::C);FakePreparer prep;prep.artifact=pc;prep.ready_after=201;
		assert(play(s,{{"source.sid",ps}},root,&prep)==PlaylistResult::TrackSessionTimeout);
		assert(prep.cancels==1 && !prep.active && s.begins==0 && s.loads==0);
		for(const auto &snapshot:s.snapshots)assert(snapshot.state!="PLAYING");
	}
	// A fully valid pair that completed while timeout cancellation raced may be
	// reused by the next Play. The real preparer still applies strict cache
	// validation before reporting this one-poll hit.
	{
		FakePreparer prep;prep.artifact=pc;prep.ready_after=201;prep.publish_valid_on_cancel=true;
		Sim timed_out(Profile::C);
		assert(play(timed_out,{{"source.sid",ps}},root,&prep)==PlaylistResult::TrackSessionTimeout);
		assert(prep.cached && prep.cancels==1 && timed_out.begins==0 && timed_out.loads==0);
		Sim retry(Profile::C);
		assert(play(retry,{{"source.sid",ps}},root,&prep)==PlaylistResult::Complete);
		assert(prep.starts==2 && prep.polls==1 && retry.begins==1 && retry.loads==1);
	}
    // Manual next while current is still PLAYING forces FADE_ONLY; controller
    // cannot react to that ENDED with an extra old-RBF load while parked.
    {
        Sim s(Profile::A); s.duration=1000; bool sent=false;
        s.input=[&](Sim &x,ControlCommand &c) { if (!sent && x.loads==1 && x.current.state==PlaybackState::Playing && x.ms>=x.started+30) {
            sent=true; c.type=ControlCommandType::Next; return ControlPollResult::Command; } return ControlPollResult::None; };
        assert(play(s,tracks("AB"),root)==PlaylistResult::Complete);
        assert(s.fades==1 && s.switches==1 && s.loads==2);
    }
    // The critical four-engine playlist is manually advanced without losing
    // position or granting a duplicate load across any session-reset domain.
    {
        Sim s(Profile::A); s.duration=1000; int nexts=0;
        s.input=[&](Sim &x,ControlCommand &c) {
            if (nexts<4 && x.loads==nexts+1 && x.current.state==PlaybackState::Playing && x.ms>=x.started+30) {
                ++nexts; c.type=ControlCommandType::Next; return ControlPollResult::Command;
            }
            return ControlPollResult::None;
        };
        assert(play(s,tracks("ABCDA"),root)==PlaylistResult::Complete);
        assert(nexts==4 && s.fades==4 && s.switches==4 && s.loads==5);
        assert(s.loaded==std::vector<std::string>({pa,pb,pc,pd,pa}));
    }
    // Newer selection while the old session is fading cancels B, stays on A.
    {
        Sim s(Profile::A); s.duration=1000; int commands=0;
        s.input=[&](Sim &x,ControlCommand &c) {
            if ((commands==0 && x.loads==1 && x.current.state==PlaybackState::Playing && x.ms>=x.started+30) || (commands==1 && x.fades==1)) {
                ++commands; c.type=ControlCommandType::Next; return ControlPollResult::Command;
            } return ControlPollResult::None;
        };
        assert(play(s,tracks("ABA"),root)==PlaylistResult::Complete);
        assert(s.switches==0 && s.fades==1 && s.loads==2 && s.loaded.back()==pa);
    }
    // Stop in fade, then Next resumes reserved queue without a stale B load.
    {
        Sim s(Profile::A); s.duration=1000; int commands=0;
        s.input=[&](Sim &x,ControlCommand &c) {
            if (commands==0 && x.loads==1 && x.current.state==PlaybackState::Playing && x.ms>=x.started+30) { ++commands; c.type=ControlCommandType::Next; return ControlPollResult::Command; }
            if (commands==1 && x.fades==1) { ++commands; c.type=ControlCommandType::Stop; return ControlPollResult::Command; }
            if (commands==2 && x.reply.state=="STOPPED") { ++commands; c.type=ControlCommandType::Next; return ControlPollResult::Command; }
            return ControlPollResult::None;
        };
        assert(play(s,tracks("ABA"),root)==PlaylistResult::Complete);
        assert(s.stops==1 && s.switches==0 && s.loads==2);
    }
    {
        Sim s(Profile::A); s.failed_replace=true;
        assert(play(s,tracks("AB"),root)==PlaylistResult::ControlIoError);
        assert(s.loads==1 && s.snapshots.back().index==2);
    }
    {
        Sim s(Profile::A); s.late_status=true;
        assert(play(s,tracks("A"),root)==PlaylistResult::TrackSessionTimeout); assert(s.loads==1);
    }
    // A resident that accepts the host request but never publishes ENDED keeps
    // the controller parked until its owned transaction deadline. The trace
    // must retain the last PARKED reply so hardware can distinguish this from
    // controller I/O failure.
    {
        Sim s(Profile::D); s.duration=1000; s.fade_completes=false; bool sent=false;
        s.input=[&](Sim &x,ControlCommand &c) {
            if (!sent && x.loads==1 && x.current.state==PlaybackState::Playing &&
                x.ms>=x.started+30) {
                sent=true; c.type=ControlCommandType::Next;
                return ControlPollResult::Command;
            }
            return ControlPollResult::None;
        };
        std::string log;
        assert(play(s,tracks("DA"),root,nullptr,250,0,&log)==
            PlaylistResult::TrackSessionTimeout);
        assert(log.find("PROFILE_REPLY generation=2 domain=1 state=PARKED") !=
            std::string::npos);
        assert(log.find("PROFILE_PARK_TIMEOUT generation=2 domain=1 ") !=
            std::string::npos);
    }
    // Old 57 -> fresh 0 -> new 1 is valid. Old generation never wins back lease.
    {
        Sim s(Profile::A); s.current.session=57; s.current.state=PlaybackState::Playing;
        Request r{1,1,57,Profile::B,false,pb}; auto v=s.owner.tick(r); assert(v.state=="PARKED");
        s.sleep_ms(100); v=s.owner.tick(r); assert(s.switches==1 && v.state=="PARKED");
        v=s.owner.tick(r); assert(v.state=="READY" && v.baseline==0 && v.domain==2);
        r={2,2,0,Profile::B,false,pb}; v=s.owner.tick(r); assert(v.generation==2);
        r.generation=1; assert(s.owner.tick(r).generation==2);
    }
    // A newer request arriving DURING blocking Main/RBF configuration is read
    // before READY; the obsolete target receives no index-1 grant.
    {
        Sim s(Profile::A); s.current.state=PlaybackState::Ended;
        Request r{1,1,0,Profile::B,false,pb}; auto v=s.owner.tick(r); assert(v.state=="PARKED" && s.switches==1);
        r={2,1,0,Profile::A,false,pa}; v=s.owner.tick(r); assert(v.state=="PARKED" && s.switches==2);
        v=s.owner.tick(r); assert(v.state=="READY" && v.profile==Profile::A && v.generation==2);
    }
    // 100 consecutive switches exercise session reset domains, not global ordering.
    {
        Sim s(Profile::A); s.current.session=57; s.current.state=PlaybackState::Ended;
        Request r{1,1,57,Profile::B,false,pb}; auto v=s.owner.tick(r);
        v=s.owner.tick(r); assert(v.state=="READY" && v.domain==2);
        // Controller has NOT consumed that READY and still has domain 1.
        r={2,1,57,Profile::A,false,pa}; v=s.owner.tick(r);
        assert(v.state=="PARKED"); v=s.owner.tick(r);
        assert(v.state=="READY" && v.profile==Profile::A && v.domain==3);
    }
    {
        Sim s(Profile::A); s.current.session=57; s.current.state=PlaybackState::Ended;
        Request r{1,1,57,Profile::B,false,pb}; s.owner.tick(r); s.owner.tick(r);
        // Once an index-1 changed baseline, an old-domain request is NOT valid.
        s.current.session=1; s.current.state=PlaybackState::Playing;
        r={2,1,57,Profile::A,false,pa}; assert(s.owner.tick(r).state=="FAILED");
    }
    {
        Sim s(Profile::A); std::string sequence; for (int i=0;i<100;++i) sequence += i%2?'B':'A';
        assert(play(s,tracks(sequence),root)==PlaylistResult::Complete); assert(s.loads==100 && s.switches==99);
    }
    for (const auto mode : {RepeatMode::One, RepeatMode::All}) {
        Sim s(Profile::A); s.preferences.repeat=mode; bool disabled=false;
        s.input=[&](Sim &x,ControlCommand &c) {
            const int disable_after=mode==RepeatMode::One?4:6;
            if (!disabled && x.loads>=disable_after && x.current.state==PlaybackState::Playing && x.ms>=x.started+30) {
                disabled=true; c.type=ControlCommandType::Repeat; c.repeat=RepeatMode::Off;
                return ControlPollResult::Command;
            } return ControlPollResult::None;
        };
        assert(play(s,tracks(mode==RepeatMode::One?"A":"ABCDA"),root)==PlaylistResult::Complete);
        if (mode==RepeatMode::One) assert(s.switches==0 && s.loads==4);
        else assert(s.loads==10 && s.switches==8 && s.loaded[3]==pd &&
            s.loaded[5]==pa && s.loaded[8]==pd);
    }
    {
        Sim s(Profile::A); s.preferences.shuffle=true;
        assert(play(s,tracks("ADBCA"),root)==PlaylistResult::Complete);
        assert(s.loads==5);
        int expected=0; for (std::size_t i=1;i<s.loaded.size();++i) expected+=s.loaded[i]!=s.loaded[i-1];
        assert(s.switches==expected);
    }
    {
        Sim s(Profile::A); std::ofstream f(root+"/bad.vgm"); f << "not VGM"; f.close();
        resume_rejected(s,pa);
        assert(play(s,{{"bad",root+"/bad.vgm"}},root)==PlaylistResult::Complete);
        assert(s.loads>=1 && s.loaded.front()==canonical_fixture(pa) && s.switches==0); unlink((root+"/bad.vgm").c_str());
    }
    {
        Sim s(Profile::A); s.duration=30;
        assert(play(s,tracks("ABBBA"),root)==PlaylistResult::Complete);
        assert(s.loads==5 && s.switches==2);
    }
    {
        Sim s(Profile::A); s.duration=30; s.ack_delay=100;
        assert(play(s,tracks("ABA"),root)==PlaylistResult::Complete);
        assert(s.loads==3 && s.switches==2);
    }
	for (const auto &p : direct_paths) {
		unlink(p.c_str());
		const auto separator=p.find_last_of('/');
		rmdir(p.substr(0,separator).c_str());
	}
    // Rejected data cannot auto-advance, even with Repeat/Shuffle enabled.
    // A bounded observation is followed only by explicit user intent.
    for (int kind=0;kind<9;++kind) {
#if defined(MEGAVGM_HOST_K053260_EMPTY_ROM) && MEGAVGM_HOST_K053260_EMPTY_ROM
        // Legal declaration-only fixtures now have explicit positive tests;
        // retain all malformed/capacity/error lifecycle assertions below.
        if(kind==0 || kind==7 || kind==8)continue;
#endif
        auto bytes=resident_fixture(192);
        if(kind<4) {
            bytes.resize(207); put32(bytes,195,kind==1?0:kind==2?7:8);
            if(kind==3)put32(bytes,199,0);
            bytes.insert(bytes.end(),{0xba,0x28,0,0x66});put32(bytes,4,bytes.size()-4);
        } else if(kind==4) bytes=resident_fixture(193);
        else if(kind==5) {bytes=a;bytes[128]=0xff;}
        else if(kind==6) {bytes=a;bytes.resize(129);put32(bytes,4,bytes.size()-4);}
        else {
            const char *asset=std::getenv(kind==7?"MEGAVGM_CREDIT_ASSET":"MEGAVGM_GAMEOVER_ASSET");
            if(!asset)continue;
            std::ifstream file(asset,std::ios::binary);assert(file);
            bytes.assign(std::istreambuf_iterator<char>(file),{});
        }
        const std::string path=root+"/rejected.vgm";
        {std::ofstream file(path,std::ios::binary);file.write(reinterpret_cast<const char*>(bytes.data()),bytes.size());}
        Sim sim(Profile::A);unsigned polls=0;bool resume=false;int rejected_loads=0;
        sim.preferences.repeat=RepeatMode::One;sim.preferences.shuffle=true;
        sim.input=[&](Sim &x,ControlCommand &command){
            if(!resume&&!x.snapshots.empty()&&!x.snapshots.back().load_error.empty()) {
                assert(x.current.session==0&&x.loads==0&&x.switches==0);
                if(++polls<20)return ControlPollResult::None;
                resume=true;command.type=ControlCommandType::Playlist;command.path=pa+".retry.snapshot";
                {std::ofstream file(command.path);file<<"MEGAVGM_PLAYLIST_V1\nNAME Retry\nSTART 0\nCOUNT 1\nPATH "<<pa<<"\n";}
                chmod(command.path.c_str(),0600);
                return ControlPollResult::Command;
            }
            if(resume&&x.loads>rejected_loads){
                rejected_loads=x.loads; command.type=ControlCommandType::Repeat;command.repeat=RepeatMode::Off;
                return ControlPollResult::Command;
            }
            return ControlPollResult::None;
        };
        assert(play(sim,{{"rejected",path}},root)==PlaylistResult::Complete);
        assert(resume&&polls==20&&sim.loads>=1&&sim.loaded.front()==canonical_fixture(pa));
        unlink(path.c_str());
    }
    // Broken ownership during rejected-track parking is still fatal.
    for(int fault=0;fault<3;++fault){
        Sim sim(Profile::A);bool injected=false;
        sim.input=[&](Sim &x,ControlCommand &){
            if(!injected&&!x.snapshots.empty()&&!x.snapshots.back().load_error.empty()) {
                injected=true;
                if(fault==0)++x.current.session;
                if(fault==1){x.current.state=PlaybackState::Fatal;x.current.error=1;}
                if(fault==2)++x.pid;
            }
            return ControlPollResult::None;
        };
        // Test client's extra live-Main check models FileClient /proc proof.
        assert(play(sim,{{"bad",pu}},root)==PlaylistResult::ControlIoError);
        assert(injected&&sim.loads==0);
    }
    // Capacity refusal is a pre-upload classification error, not a fake FPGA
    // session/FATAL. Manual refusal waits; automatic capacity handoff is tested separately.
#if defined(MEGAVGM_HOST_K053260) && MEGAVGM_HOST_K053260
    const auto within=resident_fixture(192), over=resident_fixture(193);
    assert(classify_bytes(within).profile==Profile::A);
    assert(classify_bytes(over).resource_capacity_exceeded);
    const std::string capacity_path=root+"/over-capacity.vgm";
    {std::ofstream file(capacity_path,std::ios::binary);file.write(reinterpret_cast<const char*>(over.data()),over.size());}
    const Track refused={"Over capacity",capacity_path};
    // Cold, natural progression, and manual Next all retain the Controller.
    for (int entry=0;entry<3;++entry) {
        Sim sim(Profile::A); sim.duration=80; bool next=false;
        if(entry==1){
            std::string trace;
            assert(play(sim,{{"good",pa},refused,{"last",pa}},root,nullptr,2000,0,&trace)==PlaylistResult::Complete);
            assert(sim.loads==2 && sim.loaded==std::vector<std::string>({pa,pa}));
            assert(trace.find("TRACK_LOAD_SKIPPED generation=")!=std::string::npos);
            assert(trace.find("LOAD_FILE_REQUEST path="+capacity_path)==std::string::npos);
            continue;
        }
        if(entry==2) sim.input=[&](Sim &x,ControlCommand &command){
            if(!next&&x.loads==1&&x.current.state==PlaybackState::Playing&&x.ms-x.started>=40){next=true;command.type=ControlCommandType::Next;return ControlPollResult::Command;}
            return ControlPollResult::None;
        };
        unsigned parked=0; bool stopped=false, resumed=false;
        auto before=sim.input;
        sim.input=[&,before](Sim &x,ControlCommand &command){
            if(!resumed&&!x.snapshots.empty()&&!x.snapshots.back().load_error.empty()) {
                assert(x.snapshots.back().state=="STOPPED");
                assert(x.snapshots.back().load_error=="resource_capacity_exceeded");
                assert(x.loads==(entry==0?0:1)); // No automatic skip/retry.
                if(++parked<10) return ControlPollResult::None;
                if(!stopped){stopped=true;command.type=ControlCommandType::Stop;return ControlPollResult::Command;}
                resumed=true;command.type=ControlCommandType::Next;return ControlPollResult::Command;
            }
            return before?before(x,command):ControlPollResult::None;
        };
        std::vector<Track> queue=entry==0?std::vector<Track>{refused,{"good",pa}}:
            std::vector<Track>{{"good",pa},refused,{"last",pa}};
        assert(play(sim,queue,root)==PlaylistResult::Complete);
        assert(parked>=10&&stopped&&sim.loads==(entry==0?1:2));
        assert(sim.snapshots.back().load_error.empty());
    }
    auto empty=within;empty.resize(211);empty.insert(empty.end(),{0xba,0,0,0x66});put32(empty,4,empty.size()-4);
    assert(classify_bytes(within).required_pages==192);
    #if defined(MEGAVGM_HOST_K053260_EMPTY_ROM) && MEGAVGM_HOST_K053260_EMPTY_ROM
    assert(classify_bytes(empty).profile==Profile::A && classify_bytes(empty).required_pages==0);
#else
    assert(classify_bytes(empty).profile==Profile::Unsupported);
#endif // no old page mask across classify/reload
    assert(classify_bytes(within).required_pages==192);
    unlink(capacity_path.c_str());
    std::cout<<"Resource capacity Controller: manual no-skip, automatic capacity skip, no refused upload/session, Next/Reload PASS\n";
#endif
	for (const auto &p : {pa,pb,pc,pd,pl,ps,pu,root+"/request",root+"/reply"}) unlink(p.c_str());
    rmdir(root.c_str());
    std::cout << "Phase2A classifier/channel/real-controller + switch-owner integration PASS\n";
    return 0;
}
