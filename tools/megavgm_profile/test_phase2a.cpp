#include "switch.h"
#include "../megavgm_playlist/playlist.h"
#include <cassert>
#include <fstream>
#include <functional>
#include <iostream>
#include <sstream>
#include <unistd.h>
using namespace megavgm_profile;
using namespace megavgm_playlist;
using namespace megavgm_autoplay2;

static std::vector<unsigned char> fixture(Profile p) {
    std::vector<unsigned char> b(128,0);
    b[0]='V'; b[1]='g'; b[2]='m'; b[3]=' ';
    b[8]=0x50; b[9]=1; b[0x34]=0x4c;
    b[p==Profile::A ? 0x30 : 0x4c]=1;
    b.push_back(p==Profile::A ? 0x54 : 0x58); b.push_back(0x22); b.push_back(0);
    b.push_back(0x62); b.push_back(0x66); b[4]=b.size()-4;
    return b;
}
struct Sim : Runtime, SwitchHost, Client, ControllerIo {
    PlaybackStatus current{2,0,PlaybackState::Idle,0,false,0};
    Profile resident;
    SwitchOwner owner;
    Request request;
    Reply reply;
    std::uint64_t ms=0, started=0, generation=0, fade_end=0;
    int switches=0, fades=0, loads=0, stops=0, pid=1;
    int duration=400, ack_delay=0;
    bool failed_replace=false, late_status=false;
    std::vector<std::string> loaded;
    std::vector<ControllerSnapshot> snapshots;
    PlaybackPreferences preferences;
    std::function<void(Sim&)> during_replace;
    std::function<ControlPollResult(Sim&, ControlCommand&)> input;
    explicit Sim(Profile p) : resident(p), owner(*this,p) {}
    bool status(PlaybackStatus &s, std::string &) override { s=current; return true; }
    std::string main_identity() override { return std::to_string(pid)+":verified"; }
    bool fade(std::string &) override { ++fades; fade_end=ms+100; return true; }
    bool stop(std::string &) override { ++stops; current={2,0,PlaybackState::Idle,0,false,0}; fade_end=0; return true; }
    bool replace(Profile p, std::string &d) override {
        if (failed_replace) { d="simulated RBF failure"; return false; }
        ++switches; ++pid; resident=p;
        current={2,0,PlaybackState::Idle,0,false,0};
        if (during_replace) during_replace(*this);
        return true;
    }
    std::uint64_t now() override { return ms; }
    bool begin(const Request &r, std::string &) override { request=r; return true; }
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
    bool issue_load(const std::string &, std::string &) override { assert(false); return false; }
    bool issue_load_generated(const std::string &p,std::uint64_t g,std::string &) override {
        assert(reply.state=="READY" && reply.generation==g && reply.profile==resident);
        assert(current.session==reply.baseline && !fade_end);
        ++loads; loaded.push_back(p); generation=g; started=ms;
        current.session=reply.baseline+1; current.state=PlaybackState::Loading; return true;
    }
    bool issue_stop(std::string &d) override { return stop(d); }
    bool issue_transition(TransitionReason,std::string &) override { return true; }
    std::uint64_t monotonic_ms() override { return ms; }
    void sleep_ms(std::uint32_t n) override {
        ms+=n;
        if (fade_end && ms>=fade_end) { current.state=PlaybackState::Ended; fade_end=0; }
        else if (loads && current.state==PlaybackState::Loading && ms>=started+10) current.state=PlaybackState::Playing;
        else if (loads && current.state==PlaybackState::Playing && ms>=started+duration) current.state=PlaybackState::Ended;
        assert(ms < 200000);
    }
    ControlPollResult poll_command(ControlCommand &c,std::string &) override { return input ? input(*this,c) : ControlPollResult::None; }
    bool discard_commands(std::string &) override { return true; }
    bool publish(const ControllerSnapshot &s,std::string &) override { snapshots.push_back(s); return true; }
    bool load_preferences(PlaybackPreferences &p,std::string &) override { p=preferences; return true; }
    bool save_preferences(const PlaybackPreferences &,std::string &) override { return true; }
};
static PlaylistResult play(Sim &s,const std::vector<Track> &tracks,const std::string &root) {
    PlaylistConfig c; c.profile_client=&s; c.approved_root=root; c.poll_interval_ms=10;
    c.session_timeout_ms=2000; c.playing_timeout_ms=2000; c.initial_playlist_name="Mixed test";
    std::ostringstream log;
    auto result=run(s,c,tracks,log,&s);
    if (result!=PlaylistResult::Complete) std::cout << log.str();
    return result;
}
int main() {
    auto a=fixture(Profile::A), b=fixture(Profile::B);
    assert(classify_bytes(a).profile==Profile::A); assert(classify_bytes(b).profile==Profile::B);
    auto bad=a; bad[128]=0x5a; assert(classify_bytes(bad).profile==Profile::Unsupported);
    bad=a; bad.pop_back(); assert(classify_bytes(bad).profile==Profile::Error);
    bad=a; bad[0x30]=0; assert(classify_bytes(bad).profile==Profile::Error);
    bad=a; bad[0x33]=0x40; assert(classify_bytes(bad).profile==Profile::Unsupported);
    bad=a; bad[131]=0x58; bad.insert(bad.end()-1,{0x22,0}); bad[4]=bad.size()-4;
    assert(classify_bytes(bad).profile==Profile::Ambiguous);
    bad=a; bad[128]=0x62; bad[129]=0x62; bad[130]=0x62;
    assert(classify_bytes(bad).profile==Profile::Ambiguous);
    std::string root, detail; assert(make_channel(root,detail));
    const std::string pa=root+"/a.vgm", pb=root+"/b.vgm";
    for (const auto &p : {pa,pb}) {
        auto bytes=p==pa?a:b; std::ofstream f(p,std::ios::binary); f.write(reinterpret_cast<const char*>(bytes.data()),bytes.size());
    }
    assert(classify_file(pa,root).profile==Profile::A);
    assert(classify_file(pa,"/nonexistent").profile==Profile::Error);
    Request q{5,1,57,Profile::B,false,pb}; assert(write_request(root,q,detail)); Request qr;
    assert(read_request(root,qr,detail) && qr.generation==5 && qr.path==pb);
    Reply rr{5,2,0,Profile::B,"3:123","READY",""}; assert(write_reply(root,rr,detail)); Reply read;
    assert(read_reply(root,read,detail) && read.domain==2);
#ifdef __linux__
    {
        const std::string ack=root+"/main.status";
        FileClient client(root,ack);
        rr.main_identity=process_identity(getpid()); assert(!rr.main_identity.empty());
        assert(write_reply(root,rr,detail));
        auto witness=[&](int pid,int gen,int valid,int idx) {
            std::ofstream f(ack);
            f << "version=2\npid=" << pid << "\nphase=TRANSFER_SUCCESS\ngeneration_valid=" << valid
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
        std::vector<Track> t; for (char p:sequence) t.push_back({std::string(1,p),p=='A'?pa:pb}); return t;
    };
    for (const auto &sequence : {"AAA","BBB","AABBA","ABABA"}) {
        Sim s(sequence[0]=='A'?Profile::A:Profile::B);
        assert(play(s,tracks(sequence),root)==PlaylistResult::Complete);
        int expected=0; for (std::size_t i=1;i<std::string(sequence).size();++i) expected+=sequence[i]!=sequence[i-1];
        assert(s.switches==expected && s.loads==int(std::string(sequence).size()));
        for (const auto &v:s.snapshots) assert(v.count==std::string(sequence).size() && v.playlist=="Mixed test");
        std::cout << sequence << " switch=" << s.switches << " loads=" << s.loads << " PASS\n";
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
            if (!disabled && x.loads>=4 && x.current.state==PlaybackState::Playing && x.ms>=x.started+30) {
                disabled=true; c.type=ControlCommandType::Repeat; c.repeat=RepeatMode::Off;
                return ControlPollResult::Command;
            } return ControlPollResult::None;
        };
        assert(play(s,tracks(mode==RepeatMode::One?"A":"ABA"),root)==PlaylistResult::Complete);
        if (mode==RepeatMode::One) assert(s.switches==0 && s.loads==4);
        else assert(s.loads==6 && s.switches==4);
    }
    {
        Sim s(Profile::A); s.preferences.shuffle=true;
        assert(play(s,tracks("AABBA"),root)==PlaylistResult::Complete);
        assert(s.loads==5);
        int expected=0; for (std::size_t i=1;i<s.loaded.size();++i) expected+=s.loaded[i]!=s.loaded[i-1];
        assert(s.switches==expected);
    }
    {
        Sim s(Profile::A); std::ofstream f(root+"/bad.vgm"); f << "not VGM"; f.close();
        assert(play(s,{{"bad",root+"/bad.vgm"}},root)==PlaylistResult::InvalidTrackPath);
        assert(s.loads==0 && s.switches==0 && s.fades==0); unlink((root+"/bad.vgm").c_str());
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
    for (const auto &p : {pa,pb,root+"/request",root+"/reply"}) unlink(p.c_str());
    rmdir(root.c_str());
    std::cout << "Phase2A classifier/channel/real-controller + switch-owner integration PASS\n";
}
