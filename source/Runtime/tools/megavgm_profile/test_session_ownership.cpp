#include <algorithm>
#include <iterator>
#define main existing_profile_suite_main
#include "test_phase2a.cpp"
#undef main
#include <cstdio>
#include <csignal>
#include <sys/wait.h>
#include <fcntl.h>
// Phase3.7 actual Main latest-transfer schema and Phase3.6 virtual checkpoints.
// The emitter atomically replaces the latest receipt like Main; no FPGA/audio.
#ifdef __linux__
static std::string ack_path;
static void emit(unsigned seq,unsigned idx,unsigned gen,bool valid,const std::string &path,const char *phase="TRANSFER_SUCCESS",int pid=0) {
 std::ofstream f(ack_path+".tmp");
 f<<"version=2\npid="<<(pid?pid:getpid())<<"\nphase="<<phase<<"\ncommand_seq="<<seq<<"\ngeneration_valid="<<valid<<"\ngeneration="<<gen<<"\nindex="<<idx<<"\npath="<<path<<'\n';f.close();assert(!f.fail());assert(!rename((ack_path+".tmp").c_str(),ack_path.c_str()));
}
struct OwnedSim : Sim {
 FileClient client;std::string root;int fault=0;unsigned fades_requested=0;bool native_finite=false;
 OwnedSim(const std::string &r,int bad=0,Profile initial=Profile::F):Sim(initial),client(r,ack_path),root(r),fault(bad){duration=100000000;}
 std::string main_identity() override{return process_identity(getpid());}
 bool begin(const Request &r,std::string &d) override{client.forget_session();return Sim::begin(r,d);}
 bool poll(Reply &r,std::string &d) override{bool ok=Sim::poll(r,d);assert(write_reply(root,r,d));return ok;}
 bool load_acknowledged(const Reply &r,const std::string &p,std::string &d) override{return client.load_acknowledged(r,p,d);}
 bool owns_session(const Reply &r,const std::string &p,const PlaybackStatus &s,std::string &d) override{return client.owns_session(r,p,s,d);}
 void note_policy_control() override{client.note_policy_control();}
 void forget_session() override{client.forget_session();}
 bool issue_load_generated(const std::string &p,std::uint64_t g,std::string &d) override{
  bool ok=Sim::issue_load_generated(p,g,d);current.loop_valid=loads==1;current.loop_count=0;native_finite=false;
  emit(2,1,g,true,p);return ok;
 }
 bool issue_transition(TransitionReason reason,std::string &d) override{
  bool ok=Sim::issue_transition(reason,d);
  if(loads==1){emit(3+transitions.size(),2,0,false,"/tmp/megavgm_transition.control");native_finite=reason==TransitionReason::LoopLimitTwoLoops && current.loop_count<2;
   if(reason==TransitionReason::LoopLimitTwoLoops && current.loop_count>=5){
    if(fault==1){current.session=99;current.state=PlaybackState::Playing;}
    if(fault==2){current.session=99;current.state=PlaybackState::Ended;}
    if(fault>=3 && fault<=6){auto bad=reply;
  if(fault==3)bad.generation++;
  if(fault==4)bad.domain++;
  if(fault==5)bad.profile=Profile::E;
  if(fault==6)bad.main_identity+="-regenerated";assert(write_reply(root,bad,d));}
    if(fault==7)emit(50,1,1,true,loaded.back());
   }
  }return ok;
 }
 bool issue_stop(std::string &) override{++fades_requested;fade_end=ms+100;emit(100,2,0,false,"/tmp/megavgm_stop.control");return true;}
 void sleep_ms(std::uint32_t n) override{
  int saved=duration;
  if(loads>1)duration=400;
  Sim::sleep_ms(n);duration=saved;
  if(loads==1 && current.state==PlaybackState::Playing){unsigned elapsed=ms-started;current.loop_count=elapsed>=64422?5:elapsed>=51654?4:elapsed>=38897?3:elapsed>=26143?2:elapsed>=13256?1:0;
   if(native_finite && current.loop_count>=2)current.state=PlaybackState::Ended;
  }
 }
 bool publish(const ControllerSnapshot &s,std::string &) override{snapshots.push_back(s);return true;}
};
static void parked_owner_units() {
 std::string channel,d;assert(make_channel(channel,d));FileClient client(channel);
 Request request{1,0,0,Profile::Error,true,"/refused.vgm"};assert(client.begin(request,d));
 Reply lease;lease.generation=1;lease.domain=1;lease.profile=Profile::A;lease.state="STOPPED";lease.main_identity=process_identity(getpid());
 assert(write_reply(channel,lease,d));assert(client.owns_parked(lease,d));
 for(int bad=0;bad<7;++bad){
  auto changed=lease;
  if(bad==0)++changed.generation;
  if(bad==1)++changed.domain;
  if(bad==2)++changed.baseline;
  if(bad==3)changed.profile=Profile::D;
  if(bad==4)changed.main_identity+="-changed";
  if(bad==5)changed.state="READY";
  if(bad==6)changed.state="FAILED";
  assert(write_reply(channel,changed,d));assert(!client.owns_parked(lease,d));
 }
 assert(write_reply(channel,lease,d));assert(client.owns_parked(lease,d));
 const std::string moved=channel+".held";assert(!rename(channel.c_str(),moved.c_str()));assert(!mkdir(channel.c_str(),0700));
 assert(write_reply(channel,lease,d));assert(!client.owns_parked(lease,d));assert(!client.begin(request,d));
 unlink((channel+"/reply").c_str());rmdir(channel.c_str());
 unlink((moved+"/request").c_str());unlink((moved+"/reply").c_str());rmdir(moved.c_str());
 std::cout<<"REJECTED_PARK_REAL_PROC_LEASE_EPOCH_NEGATIVES_PASS\n";
}
static void rejected_controller_process() {
 // Real process lifetime + real Controller/SwitchOwner; Main/FPGA remain mocks.
 int notification[2],command[2];assert(!pipe(notification)&&!pipe(command));
 pid_t child=fork();assert(child>=0);
 if(child==0){
  close(notification[0]);close(command[1]);assert(fcntl(command[0],F_SETFL,O_NONBLOCK)==0);
  std::string root,d;assert(make_channel(root,d));
  const std::string bad=root+"/bad.vgm",good=root+"/good.vgm";
  {std::ofstream f(bad);f<<"not VGM";}
  auto bytes=fixture(Profile::A);{std::ofstream f(good,std::ios::binary);f.write(reinterpret_cast<const char*>(bytes.data()),bytes.size());}
  Sim sim(Profile::A);bool notified=false;
  sim.on_publish=[&](Sim &,const ControllerSnapshot &snapshot){
   if(!notified&&!snapshot.load_error.empty()){notified=true;assert(write(notification[1],"E",1)==1);}
  };
  sim.input=[&](Sim &,ControlCommand &c){char value;auto n=read(command[0],&value,1);if(n==1){c.type=ControlCommandType::Next;return ControlPollResult::Command;}usleep(1000);return ControlPollResult::None;};
  auto result=play(sim,{{"bad",bad},{"good",good}},root);assert(result==PlaylistResult::Complete&&sim.loads==1&&sim.switches==0);
  unlink(bad.c_str());unlink(good.c_str());rmdir(root.c_str());_exit(0);
 }
 close(notification[1]);close(command[0]);char value;assert(read(notification[0],&value,1)==1&&value=='E');
 usleep(30000);int code;assert(waitpid(child,&code,WNOHANG)==0);assert(kill(child,0)==0);
 assert(write(command[1],"N",1)==1);assert(waitpid(child,&code,0)==child&&WIFEXITED(code)&&WEXITSTATUS(code)==0);
 close(notification[0]);close(command[1]);
 std::cout<<"REJECTED_CONTROLLER_PROCESS_ALIVE_NEXT_NORMAL_TRACK_PASS\n";
}
static void units(const std::string &root){
 Reply lease;lease.generation=1;lease.domain=1;lease.profile=Profile::F;lease.main_identity=process_identity(getpid());lease.state="READY";std::string d,path="/music/Boss1.vgm";
 PlaybackStatus playing{2,1,PlaybackState::Playing,0,true,5};FileClient client(root,ack_path);
 auto acquire=[&](){assert(write_reply(root,lease,d));emit(2,1,1,true,path);assert(client.load_acknowledged(lease,path,d));};
 acquire();assert(client.owns_session(lease,path,playing,d));
 client.note_policy_control();
 for(auto phase:{"PARSED","TRANSFER_ENTERED","TRANSFER_SUCCESS"}){emit(3,2,0,false,"/tmp/megavgm_transition.control",phase);assert(!client.load_acknowledged(lease,path,d));assert(client.owns_session(lease,path,playing,d));}
 for(unsigned n=4;n<15;n++){emit(n,2,0,false,"/tmp/megavgm_transition.control");assert(client.owns_session(lease,path,playing,d));}
 std::cout<<"A_G_UPLOAD_PROOF_SURVIVES_NORMAL_INDEX2_MULTIPLE_PHASES_PASS\n";
 for(int i=0;i<16;i++){
  acquire();client.note_policy_control();auto s=playing;auto bad=lease;
  emit(3,2,0,false,"/tmp/megavgm_transition.control");
  if(i==0)s.session=99;
  if(i==1)s.state=PlaybackState::Ended;
  if(i==2)s.error=1;
  if(i==3)s.version=1;
  if(i==4)bad.generation++;
  if(i==5)bad.domain++;
  if(i==6)bad.baseline++;
  if(i==7)bad.profile=Profile::E;
  if(i==8)bad.main_identity+="-new-start";
  if(i==9)bad.state="PARKED";
  assert(write_reply(root,bad,d));
  if(i==10)emit(3,1,1,true,path); // new index1 even same path/gen is foreign
  if(i==11)emit(3,2,0,false,"/unknown/control");
  if(i==12)emit(3,2,0,false,"/tmp/megavgm_transition.control","TRANSFER_FAILURE");
  if(i==13)emit(3,2,0,false,"/tmp/megavgm_transition.control","TRANSFER_SUCCESS",getpid()+99999);
  if(i==14)client.forget_session();
  if(i==15){std::ofstream f(ack_path);f<<"malformed\n";}
  assert(!client.owns_session(lease,path,s,d));
 }
 acquire();emit(3,2,0,false,"/tmp/megavgm_transition.control");assert(!client.owns_session(lease,path,playing,d)); // unnoted control
 acquire();auto req=Request{2,1,1,Profile::F,false,path};assert(client.begin(req,d));assert(!client.owns_session(lease,path,playing,d));
 acquire();auto original=process_identity(getpid());pid_t child=fork();assert(child>=0);
 if(!child){pause();_exit(0);}auto regenerated=lease;regenerated.main_identity=process_identity(child);assert(!regenerated.main_identity.empty() && regenerated.main_identity!=original);assert(write_reply(root,regenerated,d));assert(!client.owns_session(lease,path,playing,d));kill(child,SIGTERM);waitpid(child,nullptr,0);
 acquire();
 std::string saved=root+".saved";
 assert(!rename(root.c_str(),saved.c_str()));assert(!mkdir(root.c_str(),0700));
 assert(write_reply(root,lease,d));emit(2,1,1,true,path);
 assert(!client.owns_session(lease,path,playing,d));
 unlink(ack_path.c_str());unlink((root+"/reply").c_str());assert(!rmdir(root.c_str()));assert(!rename(saved.c_str(),root.c_str()));
 pid_t dying=fork();assert(dying>=0);
 if(!dying){pause();_exit(0);}
 auto child_lease=lease;child_lease.main_identity=process_identity(dying);assert(!child_lease.main_identity.empty());
 assert(write_reply(root,child_lease,d));emit(2,1,1,true,path,"TRANSFER_SUCCESS",dying);
 assert(client.load_acknowledged(child_lease,path,d));kill(dying,SIGTERM);waitpid(dying,nullptr,0);
 assert(!client.owns_session(child_lease,path,playing,d));
 std::cout<<"I_J_RECEIPT_LEASE_SESSION_MAIN_REGENERATION_EPOCH_NEGATIVES21_PASS\n";
 unlink((root+"/request").c_str());
}
static void controllers(const std::string &root,const std::string &pf,const std::string &pn){
 for(int scenario=0;scenario<13;++scenario){
  int bad=scenario>=5 && scenario<=11?scenario-4:0;OwnedSim s(root,bad);int commands=0;bool off_sent=false;
  if(scenario==12)s.preferences.repeat=RepeatMode::All;
  s.input=[&](Sim &x,ControlCommand &cmd){unsigned elapsed=x.ms-x.started;
   if(x.loads==1 && commands==0 && x.current.state==PlaybackState::Playing && elapsed>= (scenario==2?1000:22517)){commands++;cmd.type=ControlCommandType::Repeat;cmd.repeat=RepeatMode::One;return ControlPollResult::Command;}
   if(x.loads==1 && commands==1 && x.current.state==PlaybackState::Playing && elapsed>= (scenario==2?2000:70887)){
    assert(scenario==2 || x.current.loop_count>=5);commands++;cmd.type=scenario==3?ControlCommandType::Stop:ControlCommandType::Repeat;cmd.repeat=scenario==1?RepeatMode::Off:RepeatMode::All;return ControlPollResult::Command;
   }
   if(scenario==3 && x.loads==1 && commands==2 && x.current.state==PlaybackState::Ended){commands++;cmd.type=ControlCommandType::Next;return ControlPollResult::Command;}
   if(x.loads==2 && commands>=2 && !off_sent && x.current.state==PlaybackState::Playing){off_sent=true;commands++;cmd.type=ControlCommandType::Repeat;cmd.repeat=RepeatMode::Off;return ControlPollResult::Command;}
   return ControlPollResult::None;
  };
  if(scenario==4){ // ONE remains ONE past5; later Stop, never automatic fade.
   s.input=[&](Sim &x,ControlCommand &cmd){if(!commands&&x.current.state==PlaybackState::Playing){commands++;cmd.type=ControlCommandType::Repeat;cmd.repeat=RepeatMode::One;return ControlPollResult::Command;}if(commands==1&&x.current.loop_count>=5){commands++;cmd.type=ControlCommandType::Stop;return ControlPollResult::Command;}if(commands==2&&x.current.state==PlaybackState::Ended){commands++;cmd.type=ControlCommandType::Next;return ControlPollResult::Command;}if(x.loads==2&&!off_sent&&x.current.state==PlaybackState::Playing){off_sent=true;cmd.type=ControlCommandType::Repeat;cmd.repeat=RepeatMode::Off;return ControlPollResult::Command;}return ControlPollResult::None;};
  }
  std::string log;auto result=play(s,{{"Boss1",pf},{"next",pn}},root,nullptr,2000,0,&log);
  if(scenario<=2 || scenario==12){assert(result==PlaylistResult::Complete && s.loads==2 && s.fades_requested==(scenario==2?0u:1u));std::cout<<(scenario==0?"B_ONE5_TO_ALL":scenario==1?"C_ONE5_TO_OFF":scenario==12?"F_ALL_ONE_ALL":"D_ONE_TO_ALL_EARLY")<<"_PASS\n";}
  else if(scenario<=4){assert(result==PlaylistResult::Complete && s.loads==2 && s.fades_requested==1 && log.find("REPEAT_RECOVERY_FADE_ONLY")==std::string::npos);std::cout<<(scenario==3?"H_STOP_PRIORITY":"E_ONE5_CONTINUES")<<"_PASS\n";}
  else if(scenario<=6){assert(result==PlaylistResult::Suspended && s.loads==1 && s.fades_requested==0);std::cout<<"STALE_SESSION_"<<(scenario==5?"PLAYING":"ENDED")<<"_REJECT_PASS\n";}
  else{assert(result==PlaylistResult::CommandWriteFailed && s.loads==1 && s.fades_requested==0);std::cout<<"REAL_OWNER_LOSS_"<<bad<<"_REJECT_PASS\n";}
  std::cout<<"SCENARIO "<<scenario<<" fade="<<s.fades_requested<<" loads="<<s.loads<<'\n'<<log;
 }
 }
static void lifecycle_queue_metadata(const std::string &root,const std::string &pf,const std::string &pn){
 std::string snap=root+"/reload.snapshot",detail;
 for(int mode=0;mode<6;++mode){
  {std::ofstream f(snap);f<<"MEGAVGM_PLAYLIST_V1\nNAME Reload\nSTART 0\nCOUNT 2\nPATH "<<pf<<"\nPATH "<<pn<<"\n";}
  OwnedSim s(root);int command=0;bool off_sent=false;
  if(mode>=4){s.preferences.repeat=RepeatMode::All;s.preferences.shuffle=mode==5;}
  s.input=[&](Sim &x,ControlCommand &c){
   if(!command && x.current.state==PlaybackState::Playing){++command;c.type=ControlCommandType::Repeat;c.repeat=RepeatMode::One;return ControlPollResult::Command;}
   if(command==1 && x.current.loop_count>=5){++command;
    c.type=mode==0?ControlCommandType::Next:mode==1?ControlCommandType::Playlist:mode==2?ControlCommandType::Stop:ControlCommandType::Repeat;
    c.path=snap;c.repeat=RepeatMode::All;return ControlPollResult::Command;
   }
   if(mode==2 && command==2 && x.current.state==PlaybackState::Ended){++command;c.type=ControlCommandType::Playlist;c.path=snap;return ControlPollResult::Command;}
   if(mode==3 && command==2 && s.fade_end){++command;c.type=ControlCommandType::Stop;return ControlPollResult::Command;}
   if(mode==3 && command==3 && x.current.state==PlaybackState::Ended){++command;c.type=ControlCommandType::Next;return ControlPollResult::Command;}
   if(command>=2 && x.loads>=(mode>=4?4:2) && x.current.state==PlaybackState::Playing && !off_sent){off_sent=true;++command;c.type=ControlCommandType::Repeat;c.repeat=RepeatMode::Off;return ControlPollResult::Command;}
   return ControlPollResult::None;
  };
  std::string log;assert(play(s,{{"F",pf},{"next",pn}},root,nullptr,2000,0,&log)==PlaylistResult::Complete);
  if(mode==0)assert(s.loads==2 && s.fades_requested==0);
  if(mode==1)assert(s.loads==3 && s.fades_requested==0);
  if(mode==2)assert(s.loads==3 && s.fades_requested==1);
  if(mode==3)assert(s.loads==2 && s.fades_requested==1 && log.find("STOP_JOINS_AUTOMATIC_FADE")!=std::string::npos);
  if(mode>=4){assert(s.loads==4 && s.fades_requested==1);for(std::size_t i=1;i<s.loaded.size();++i)assert(s.loaded[i]!=s.loaded[i-1]);}
  std::cout<<"REAL_CLIENT_LIFECYCLE_QUEUE_"<<mode<<"_PASS\n"<<log;
 }
 unlink(snap.c_str());
 // Metadata fade after a normal policy transfer, then E -> F through the same
 // Controller/FileClient/SwitchOwner. Native CPU/APU and RBF loading are mocked.
 OwnedSim timed(root,0,Profile::E);
 std::string prepared=root+"/prepared.nsf",source=root+"/source.nsfe";
 std::vector<unsigned char> nsf(160,0);std::copy_n("NESM\x1a",5,nsf.begin());nsf[5]=1;nsf[6]=1;nsf[7]=1;put16(nsf,8,0x8000);put16(nsf,10,0x8000);put16(nsf,12,0x8000);nsf[128]=0x60;
 {std::ofstream f(prepared,std::ios::binary);f.write(reinterpret_cast<const char*>(nsf.data()),nsf.size());}
 std::vector<unsigned char> nsfe={'N','S','F','E'};
 auto chunk=[&](const char *tag,const std::vector<unsigned char> &data){unsigned len=data.size();for(unsigned i=0;i<4;i++)nsfe.push_back((len>>(8*i))&255);nsfe.insert(nsfe.end(),tag,tag+4);nsfe.insert(nsfe.end(),data.begin(),data.end());};
 chunk("INFO",{0,0x80,0,0x80,0,0x80,0,0,1,0});chunk("DATA",{0x60});chunk("time",{200,0,0,0});chunk("fade",{100,0,0,0});chunk("NEND",{});
 {std::ofstream f(source,std::ios::binary);f.write(reinterpret_cast<const char*>(nsfe.data()),nsfe.size());}
 FakePreparer provider;provider.artifact=prepared;provider.timing.valid=true;provider.timing.target_ms=300;
 bool changed=false,off_sent=false;timed.input=[&](Sim &x,ControlCommand &cmd){if(!changed&&x.loads==1&&x.current.state==PlaybackState::Playing){changed=true;cmd.type=ControlCommandType::Repeat;cmd.repeat=RepeatMode::All;return ControlPollResult::Command;}if(x.loads==2&&x.current.state==PlaybackState::Playing&&!off_sent){off_sent=true;cmd.type=ControlCommandType::Repeat;cmd.repeat=RepeatMode::Off;return ControlPollResult::Command;}return ControlPollResult::None;};
 std::string log;auto result=play(timed,{{"source.nsfe",source},{"F.vgm",pf}},root,&provider,2000,0,&log);std::cout<<log<<std::endl;assert(result==PlaylistResult::Complete);assert(timed.fades_requested==1 && timed.loads==2 && timed.switches==1 && log.find("METADATA_FADE_ONLY")!=std::string::npos);std::cout<<"N_REAL_CLIENT_NSFE_POLICY_CHANGE_METADATA_E_F_PASS\n"<<log;
 unlink(prepared.c_str());unlink(source.c_str());
}
#endif
int main(){
#ifdef __linux__
 parked_owner_units();rejected_controller_process();
#endif
#ifdef __linux__
 char tmp[]="/tmp/owned-session.XXXXXX";assert(mkdtemp(tmp));std::string root(tmp);ack_path=root+"/main.status";
 units(root);
 auto f=fixture(Profile::F);put32(f,0x18,575024);put32(f,0x1c,0xa8-0x1c);put32(f,0x20,565204);std::string pf=root+"/F.vgm",pn=root+"/next.vgm";
 for(auto p:{pf,pn}){std::ofstream o(p,std::ios::binary);o.write(reinterpret_cast<const char*>(f.data()),f.size());}
 controllers(root,pf,pn);lifecycle_queue_metadata(root,pf,pn);unlink(pf.c_str());unlink(pn.c_str());unlink(ack_path.c_str());unlink((root+"/reply").c_str());rmdir(root.c_str());
#else
 std::cout<<"FileClient proc identity regression requires Linux ARM/QEMU; NOT_RUN on non-Linux\n";
#endif
}
