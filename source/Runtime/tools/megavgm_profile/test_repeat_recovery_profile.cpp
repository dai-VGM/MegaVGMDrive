#include <algorithm>
#include <iterator>
// Exercise the production Client/Controller/SwitchOwner path. This Runtime
// supplies a looping resident which needs FADE_ONLY after late finite policy.
#define main existing_profile_suite_main
#include "test_phase2a.cpp"
#undef main
struct RecoverySim : Sim {
 bool lose_recovery_owner=false;
 std::vector<std::uint32_t> automatic_sessions;
 explicit RecoverySim():Sim(Profile::F) {preferences.repeat=RepeatMode::One;}
 bool issue_stop(std::string &) override {
  automatic_sessions.push_back(current.session);
  assert(current.state==PlaybackState::Playing);
  fade_end=ms+100;return true;
 }
 bool load_acknowledged(const Reply &r,const std::string &p,std::string &d) override {
  return !lose_recovery_owner && Sim::load_acknowledged(r,p,d);
 }
 bool issue_load_generated(const std::string &p,std::uint64_t g,std::string &d) override {
  bool ok=Sim::issue_load_generated(p,g,d);current.loop_valid=false;current.loop_count=0;return ok;
 }
 void sleep_ms(std::uint32_t n) override {
  int saved=duration;if(resident==Profile::F)duration=100000000;
  Sim::sleep_ms(n);duration=saved;
  if(resident==Profile::F && current.state==PlaybackState::Playing) {
   current.loop_valid=true;current.loop_count=static_cast<std::uint16_t>((ms-started)/20);
  }
 }
 bool replace(Profile p,std::string &d) override {
  assert(current.state==PlaybackState::Ended || current.state==PlaybackState::Idle);
  return Sim::replace(p,d);
 }
};
int main() {
 char tmp[]="/tmp/megavgm-repeat-profile.XXXXXX";char *dir=mkdtemp(tmp);assert(dir);
 std::string root(dir),pf=root+"/F.vgm",pe=root+"/prepared.nsf",pne=root+"/original.nsfe";
 auto f=fixture(Profile::F);put32(f,0x18,735);put32(f,0x1c,0xa8-0x1c);put32(f,0x20,735);
 if(const char *actual=std::getenv("MEGAVGM_F_REPEAT_FIXTURE")) {
  std::ifstream input(actual,std::ios::binary);
  f.assign(std::istreambuf_iterator<char>(input),std::istreambuf_iterator<char>());
  assert(!f.empty());
 }
 {std::ofstream o(pf,std::ios::binary);o.write(reinterpret_cast<const char*>(f.data()),f.size());}
 std::vector<unsigned char> nsf(128+32,0);std::copy_n("NESM\x1a",5,nsf.begin());nsf[5]=1;nsf[6]=1;nsf[7]=1;put16(nsf,8,0x8000);put16(nsf,10,0x8000);put16(nsf,12,0x8000);nsf[128]=0x60;
 {std::ofstream o(pe,std::ios::binary);o.write(reinterpret_cast<const char*>(nsf.data()),nsf.size());}
 {std::ofstream o(pne);o<<"NSFE";}
 assert(classify_file(pf,root).profile==Profile::F);
 assert(classify_file(pe,root).profile==Profile::E);
 for(bool lose_owner:{false,true}) {
  RecoverySim sim;bool changed=false;
  sim.input=[&](Sim &x,ControlCommand &c){
   if(!changed && x.loads==1 && x.current.state==PlaybackState::Playing && x.current.loop_count>=3) {
    changed=true;c.type=ControlCommandType::Repeat;c.repeat=RepeatMode::Off;
    sim.lose_recovery_owner=lose_owner;return ControlPollResult::Command;
   }return ControlPollResult::None;
  };
  FakePreparer provider;provider.artifact=pe;provider.timing.valid=true;provider.timing.target_ms=300;
  std::string log;
  auto result=play(sim,{{"F.vgm",pf},{"original.nsfe",pne}},root,&provider,2000,0,&log);
  if(lose_owner) {
   assert(result==PlaylistResult::CommandWriteFailed && sim.loads==1 && sim.automatic_sessions.empty() && sim.switches==0);
   assert(log.find("REPEAT_RECOVERY_OWNER_LOST")!=std::string::npos);
   std::cout<<"REPEAT_RECOVERY_LEASE_LOSS_REJECT_PASS\n";
  } else {
   assert(result==PlaylistResult::Complete && sim.loads==2 && sim.switches==1 && sim.resident==Profile::E);
   assert(sim.automatic_sessions.size()==2); // F recovery, then fresh E metadata timer.
   assert(log.find("REPEAT_RECOVERY_FADE_ONLY")!=std::string::npos && log.find("METADATA_FADE_ONLY")!=std::string::npos);
   std::cout<<log<<"REPEAT_F_RECOVERY_TO_E_METADATA_PASS\n";
  }
 }
 unlink(pf.c_str());unlink(pe.c_str());unlink(pne.c_str());rmdir(root.c_str());
}
