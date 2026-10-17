#include <algorithm>
#define main phase2a_inherited_main
#include "test_phase2a.cpp"
#undef main
#include <iterator>

struct CapacitySim : Sim {
    bool owner_lost=false, stale_park=false, stale_reply=false;
    int fatal_after=-1;
    unsigned reads=0;
    explicit CapacitySim():Sim(Profile::A) {}
    bool owns_parked(const Reply &r,std::string &d) override {
        return !owner_lost && r.generation==request.generation &&
            r.domain==reply.domain && r.baseline==current.session && Sim::owns_parked(r,d);
    }
    bool poll(Reply &r,std::string &d) override {
        bool result=Sim::poll(r,d);
        if(stale_reply && r.state=="STOPPED") ++r.generation;
        return result;
    }
    StatusReadResult read_status(PlaybackStatus &s,std::string &d) override {
        if(ms>10000||++reads>10000){d="fixture progress watchdog";return StatusReadResult::IoError;}
        auto result=Sim::read_status(s,d);
        if(stale_park && request.stop) ++s.session;
        if(fatal_after>=0 && loads && ms-started>=unsigned(fatal_after)) {
            s.state=PlaybackState::Fatal;s.error=0xe1;
        }
        return result;
    }
};
static unsigned cases=0;
static void check(bool value,const char *name){if(!value){std::cerr<<"FAILED "<<name<<'\n';std::abort();}}
static void write_fixture(const std::string &p,const std::vector<unsigned char> &b){std::ofstream f(p,std::ios::binary);f.write(reinterpret_cast<const char*>(b.data()),b.size());assert(f.good());}
static PlaylistResult execute_capacity(CapacitySim &sim,const std::vector<Track>&tracks,
 const std::string &root,bool named,std::string &log,RandomSource *random=nullptr,SidPreparer *provider=nullptr){
 PlaylistConfig cfg;cfg.profile_client=&sim;cfg.approved_root=root;cfg.poll_interval_ms=10;cfg.main_probe_interval_ms=10;
 cfg.session_timeout_ms=1000;cfg.playing_timeout_ms=1000;cfg.stop_timeout_ms=1000;
 cfg.initial_playlist_name=named?"Capacity regression":"";cfg.random_source=random;
 cfg.native_preparer=provider;cfg.native_cache_root=root;cfg.sid_preparer=provider;cfg.sid_cache_root=root;
 std::ostringstream out;auto result=run(sim,cfg,tracks,out,&sim);log=out.str();
 std::cout<<"CASE "<<++cases<<" result="<<playlist_result_name(result)<<" loads="<<sim.loads<<'\n'<<log;
 return result;
}
static unsigned occurrences(const std::string&s,const std::string&needle){unsigned n=0;std::size_t p=0;while((p=s.find(needle,p))!=std::string::npos){++n;p+=needle.size();}return n;}
static void normal_chain(const std::string&root,const std::vector<Track>&tracks,const std::vector<std::string>&expected,bool named,unsigned skips){
 CapacitySim sim;std::string log;check(execute_capacity(sim,tracks,root,named,log)==PlaylistResult::Complete,"automatic chain completes");
 check(sim.loaded==expected,"only accepted source files transferred in queue order");
 check(occurrences(log,"TRACK_LOAD_SKIPPED generation=")==skips,"exactly one skip per rejected candidate");
 for(const auto&t:tracks)if(classify_file(t.path,root).resource_capacity_exceeded){
  check(log.find("LOAD_FILE_REQUEST path="+t.path)==std::string::npos,"refused track has zero index1 transfers");
  for(const auto&s:sim.snapshots)check(s.path!=t.path||s.state!="PLAYING","refused track has zero fake PLAYING");
 }
}
int main(){
 char tmp[]="/tmp/capacity-skip.XXXXXX";check(mkdtemp(tmp)!=nullptr,"scratch");std::string root=canonical_fixture(tmp);
 std::string a=root+"/01.vgm",bad=root+"/02.vgm",bad2=root+"/03.vgm",last=root+"/z99.vgm",d=root+"/D.vgm",f=root+"/F.vgm";
 write_fixture(a,fixture(Profile::A));write_fixture(last,fixture(Profile::A));write_fixture(bad,resident_fixture(193));write_fixture(bad2,resident_fixture(193));write_fixture(d,fixture(Profile::D));write_fixture(f,fixture(Profile::F));
 check(classify_file(bad,root).resource_capacity_exceeded,"capacity fixture is real classifier refusal");
 std::vector<Track> chain={{"01",a},{"02",bad},{"99",last}};
 normal_chain(root,chain,{a,last},false,1); // Directory natural handoff is automatic too.
 normal_chain(root,chain,{a,last},true,1);
 normal_chain(root,{{"99",last}},{last},false,0);
 normal_chain(root,{{"01",a},{"D",d},{"F",f},{"99",last}},{a,d,f,last},true,0);
 normal_chain(root,{{"01",a},{"02",bad},{"03",bad2},{"99",last}},{a,last},true,2);
 // Explicit bad selection waits, stays live, preserves reason; explicit Next recovers.
 for(int kind=0;kind<3;++kind){
  CapacitySim sim;std::string log;unsigned held=0;bool sent=false,advanced=false,next=false;
  sim.input=[&](Sim&x,ControlCommand&c){if(!advanced&&!x.snapshots.empty()&&!x.snapshots.back().load_error.empty()){
   check(x.loads==(kind?1:0),"no implicit advance from manual selection/Stop");
   check(x.snapshots.back().load_error=="resource_capacity_exceeded","PWA receives capacity reason");
   if(kind==1&&!sent){sent=true;c.type=ControlCommandType::Stop;return ControlPollResult::Command;}
   if(++held<10)return ControlPollResult::None;
   advanced=true;c.type=ControlCommandType::Next;return ControlPollResult::Command;
  }return ControlPollResult::None;};
  if(kind==2){auto after=sim.input;sim.input=[&,after](Sim&x,ControlCommand&c){if(!next&&x.loads==1&&!x.snapshots.empty()&&x.snapshots.back().state=="PLAYING"&&x.ms-x.started>=40){next=true;c.type=ControlCommandType::Next;return ControlPollResult::Command;}return after(x,c);};}
  check(execute_capacity(sim,kind?chain:std::vector<Track>{{"02",bad},{"99",last}},root,false,log)==PlaylistResult::Complete,"manual bad/Stop/Next recovery");
  check(sim.loaded==(kind?std::vector<std::string>{a,last}:std::vector<std::string>{last}),"manual recovery exactly once");
  check(log.find("TRACK_LOAD_SKIPPED")==std::string::npos,"manual error never auto skips");
 }
 // Final capacity failure and all-failure queues stop explicitly; no process exit
 // occurs until this test sends a new user command after ten parked polls.
 for(int kind=0;kind<5;++kind){
  CapacitySim sim;std::string log;unsigned held=0;bool resumed=false;
  if(kind==2)sim.preferences.repeat=RepeatMode::All;
  if(kind==3)sim.preferences.repeat=RepeatMode::One;
  if(kind==4){sim.preferences.repeat=RepeatMode::All;sim.preferences.shuffle=true;}
  bool invalidated=false;sim.on_publish=[&](Sim &,const ControllerSnapshot&value){if(!invalidated&&value.path==a&&value.state=="ENDED"){invalidated=true;write_fixture(a,resident_fixture(193));}};
  const std::string recovery=root+"/recovery.snapshot";{std::ofstream out(recovery);out<<"MEGAVGM_PLAYLIST_V1\nNAME Recovery\nSTART 0\nCOUNT 1\nPATH "<<last<<"\n";}
  sim.input=[&](Sim&x,ControlCommand&c){if(!resumed&&!x.snapshots.empty()&&x.snapshots.back().load_error_detail.find("No playable candidate")!=std::string::npos){
   if(++held<10)return ControlPollResult::None;
   resumed=true;c.type=ControlCommandType::Playlist;c.path=recovery;return ControlPollResult::Command;
  }if(resumed&&x.current.state==PlaybackState::Playing&&x.preferences.repeat!=RepeatMode::Off){x.preferences.repeat=RepeatMode::Off;c.type=ControlCommandType::Repeat;c.repeat=RepeatMode::Off;return ControlPollResult::Command;}return ControlPollResult::None;};
  auto tracks=kind==0?std::vector<Track>{{"01",a},{"02",bad}}:std::vector<Track>{{"01",a},{"02",bad},{"03",bad2}};
  check(execute_capacity(sim,tracks,root,true,log)==PlaylistResult::Complete,"exhausted queue remains recoverable");
  check(resumed&&held>=10,"explicit exhausted STOPPED waits for user");
  check(log.find("TRACK_SKIP_EXHAUSTED")!=std::string::npos,"exhaustion recorded once");
  check(occurrences(log,"TRACK_SKIP_EXHAUSTED")==1,"no exhaustion spin");
  check(sim.loaded==std::vector<std::string>({a,last}),"exhausted queue never uploads refused tracks");
  write_fixture(a,fixture(Profile::A));
  unlink(recovery.c_str());
 }
 // Repeat All returns through the same bag/order; One does not turn into Next.
 {
  CapacitySim sim;sim.preferences.repeat=RepeatMode::All;std::string log;bool finite=false;
  sim.input=[&](Sim&x,ControlCommand&c){if(!finite&&x.loads==4&&x.current.state==PlaybackState::Playing){finite=true;c.type=ControlCommandType::Repeat;c.repeat=RepeatMode::Off;return ControlPollResult::Command;}return ControlPollResult::None;};
  check(execute_capacity(sim,chain,root,true,log)==PlaylistResult::Complete,"Repeat All wraps");
  check(sim.loaded==std::vector<std::string>({a,last,a,last}),"Repeat All ordered traversal unchanged");
 }
 for(bool repeat_all:{false,true}){
  CapacitySim sim;sim.preferences.shuffle=true;sim.preferences.repeat=repeat_all?RepeatMode::All:RepeatMode::Off;
  XorShiftRandom random(44),oracle_random(44);PlaybackTraversal oracle(oracle_random);oracle.reset(4,0,sim.preferences);
  std::vector<Track> tracks={{"01",a},{"02",bad},{"03",bad2},{"99",last}};std::vector<std::string> expected={a};std::size_t current=0;
  for(unsigned n=0;n<3;++n){std::size_t next=current;check(oracle.next(current,true,false,next)==TraversalResult::Track,"shuffle oracle");current=next;if(current==0||current==3)expected.push_back(tracks[current].path);}
  std::string log;bool finite=false,finished=false;sim.input=[&](Sim&x,ControlCommand&c){if(!finished&&!x.snapshots.empty()&&x.snapshots.back().load_error_detail.find("No playable candidate")!=std::string::npos){finished=true;c.type=ControlCommandType::Next;return ControlPollResult::Command;}if(repeat_all&&!finite&&x.loads==2&&x.current.state==PlaybackState::Playing){finite=true;c.type=ControlCommandType::Repeat;c.repeat=RepeatMode::Off;return ControlPollResult::Command;}return ControlPollResult::None;};
  check(execute_capacity(sim,tracks,root,true,log,&random)==PlaylistResult::Complete,"Shuffle bounded completion");check(sim.loaded==expected,"Shuffle bag order including rejected entries unchanged");
 }
 // PREV uses actual played history, never an automatically refused item.
 {
  struct ZeroRandom : RandomSource { std::uint32_t uniform(std::uint32_t) override { return 0; } } random;
  CapacitySim sim;sim.preferences.shuffle=true;std::string log;bool previous=false;
  sim.input=[&](Sim&x,ControlCommand&cmd){if(!previous&&x.loads==2&&!x.snapshots.empty()&&x.snapshots.back().state=="PLAYING"&&x.ms-x.started>=40){previous=true;cmd.type=ControlCommandType::Previous;return ControlPollResult::Command;}return ControlPollResult::None;};
  check(execute_capacity(sim,chain,root,false,log,&random)==PlaylistResult::Complete,"Shuffle PREV skips unplayed history");
  check(previous&&sim.loaded==std::vector<std::string>({a,last,a,last}),"PREV returns last actual song");
 }
 for(unsigned seed=1;seed<=16;++seed){
  CapacitySim sim;sim.preferences.shuffle=true;sim.preferences.repeat=RepeatMode::All;XorShiftRandom random(seed);std::string log;bool finite=false,finished=false;
  sim.input=[&](Sim&x,ControlCommand&cmd){if(!finite&&x.loads==8&&x.current.state==PlaybackState::Playing){finite=true;cmd.type=ControlCommandType::Repeat;cmd.repeat=RepeatMode::Off;return ControlPollResult::Command;}if(!finished&&!x.snapshots.empty()&&x.snapshots.back().load_error_detail.find("No playable candidate")!=std::string::npos){finished=true;cmd.type=ControlCommandType::Next;return ControlPollResult::Command;}return ControlPollResult::None;};
  check(execute_capacity(sim,chain,root,true,log,&random)==PlaylistResult::Complete,"Shuffle Repeat All completes bounded test");
  for(std::size_t i=1;i<sim.loaded.size();++i)check(sim.loaded[i]!=sim.loaded[i-1],"no immediate audible repeat across rejected bag entries");
 }
 // Ordinary unsupported/malformed files stay errors, even on automatic handoff.
 {
  std::string invalid=root+"/04.vgm";write_fixture(invalid,{1,2,3});CapacitySim sim;std::string log;bool moved=false;unsigned error_polls=0;
  sim.input=[&](Sim&x,ControlCommand&c){if(!moved&&!x.snapshots.empty()&&!x.snapshots.back().load_error.empty()){if(++error_polls<10)return ControlPollResult::None;moved=true;c.type=ControlCommandType::Next;return ControlPollResult::Command;}return ControlPollResult::None;};
  check(execute_capacity(sim,{{"01",a},{"04",invalid},{"99",last}},root,true,log)==PlaylistResult::Complete,"malformed manual recovery");check(log.find("TRACK_LOAD_SKIPPED")==std::string::npos,"capacity-only scope");unlink(invalid.c_str());
 }
 // New Stop/Next intent on the rejection edge outranks automatic recovery.
 for(bool stop:{false,true}){
  CapacitySim sim;std::string log;bool signalled=false,advanced=false;unsigned held=0;
  sim.input=[&](Sim&x,ControlCommand&c){if(!advanced&&!x.snapshots.empty()&&!x.snapshots.back().load_error.empty()){
   if(!signalled){signalled=true;advanced=!stop;c.type=stop?ControlCommandType::Stop:ControlCommandType::Next;return ControlPollResult::Command;}
   if(stop&&++held>=10){advanced=true;c.type=ControlCommandType::Next;return ControlPollResult::Command;}
  }return ControlPollResult::None;};
  check(execute_capacity(sim,chain,root,false,log)==PlaylistResult::Complete,"rejection-edge user priority");check(sim.loaded==std::vector<std::string>({a,last}),"navigation exactly once");check(log.find("TRACK_LOAD_SKIPPED")==std::string::npos,"user wins automatic skip");
 }
 // Stale completion, false owner and stale STOPPED reply cannot advance.
 for(int fault=0;fault<3;++fault){
  CapacitySim sim;sim.owner_lost=fault==0;sim.stale_park=fault==1;sim.stale_reply=fault==2;std::string log;
  auto result=execute_capacity(sim,chain,root,false,log);
  check(result==(fault==2?PlaylistResult::TrackSessionTimeout:PlaylistResult::ControlIoError),"stale/owner failure is fatal to transaction");check(sim.loads==1,"no next load on stale/owner fault");check(log.find("TRACK_LOAD_SKIPPED")==std::string::npos,"no stale completion advance");
 }
 for(int time:{0,200}){
  CapacitySim sim;sim.fatal_after=time;std::string log;check(execute_capacity(sim,chain,root,true,log)==PlaylistResult::ControlIoError,"FPGA FATAL not recoverable skip");check(sim.loads==1&&log.find("FPGA_FATAL_NO_AUTOMATIC_SKIP")!=std::string::npos,"FATAL never advances");
 }
 // Generic switching A -> (refused A) -> D -> E prepared NSF -> F -> C SID.
 {
  std::string source=root+"/E.nsfe",prepared=root+"/E-prepared.nsf",sid=root+"/C.mvgmsid";write_fixture(source,{'N','S','F','E'});
  std::vector<unsigned char> nsf(160,0);std::copy_n("NESM\x1a",5,nsf.begin());nsf[5]=1;nsf[6]=1;nsf[7]=1;put16(nsf,8,0x8000);put16(nsf,10,0x8000);put16(nsf,12,0x8000);nsf[128]=0x60;write_fixture(prepared,nsf);write_fixture(sid,sid_fixture());
  FakePreparer provider;provider.artifact=prepared;provider.timing.valid=true;provider.timing.target_ms=100;
  CapacitySim sim;std::string log;check(execute_capacity(sim,{{"01",a},{"02",bad},{"D",d},{"E.nsfe",source},{"F",f},{"C.mvgmsid",sid}},root,true,log,nullptr,&provider)==PlaylistResult::Complete,"A-D-E-F-C switching and E timer");
  check(sim.loaded==std::vector<std::string>({a,d,prepared,f,sid}),"generic engine sequence exact");check(log.find("METADATA_FADE_ONLY")!=std::string::npos,"E automatic completion preserved");check(sim.replaced==std::vector<Profile>({Profile::D,Profile::E,Profile::F,Profile::C}),"no engine-specific skip branch");
  unlink(source.c_str());unlink(prepared.c_str());unlink(sid.c_str());
 }
 if(const char *real=std::getenv("MEGAVGM_CAPACITY_SKIP_REAL_DIR")){
  std::vector<Track> tracks;for(auto name:{"04.vgm","05.vgm","06.vgm"})tracks.push_back({name,std::string(real)+"/"+name});
  check(classify_file(tracks[0].path,real).profile==Profile::A,"actual04 accepted");check(classify_file(tracks[1].path,real).resource_capacity_exceeded,"actual05 rejected");check(classify_file(tracks[2].path,real).profile==Profile::A,"actual06 accepted");
  normal_chain(real,tracks,{tracks[0].path,tracks[2].path},false,1);
  normal_chain(real,{{"06",tracks[2].path}},{tracks[2].path},false,0);
  CapacitySim manual;std::string log;unsigned held=0;bool next=false;
  manual.input=[&](Sim&x,ControlCommand&c){if(!next&&!x.snapshots.empty()&&!x.snapshots.back().load_error.empty()){
   check(x.loads==0&&x.snapshots.back().load_error=="resource_capacity_exceeded","actual05 manual rejection before upload");
   if(++held<10)return ControlPollResult::None;
   next=true;c.type=ControlCommandType::Next;return ControlPollResult::Command;
  }return ControlPollResult::None;};
  check(execute_capacity(manual,{{"05",tracks[1].path},{"06",tracks[2].path}},real,false,log)==PlaylistResult::Complete,"actual05 manual error then explicit06");
  check(held>=10&&manual.loaded==std::vector<std::string>{tracks[2].path}&&log.find("TRACK_LOAD_SKIPPED")==std::string::npos,"actual05 never auto-skipped on manual selection");
 }
 for(auto p:{a,bad,bad2,last,d,f}) { unlink(p.c_str()); }
 rmdir(root.c_str());
 std::cout<<"CAPACITY_AUTOMATIC_SKIP_PASS cases="<<cases<<" controlled Host/Controller; no FPGA/audio/hardware claim\n";
}
