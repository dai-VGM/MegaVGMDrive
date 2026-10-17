#include <algorithm>
#include <iterator>
// Session-owned late Repeat recovery; production Controller, scripted Main
// status and user input. No FPGA/PWA implementation is replaced here.
#define main existing_playlist_suite_main
#include "test_playlist.cpp"
#undef main
#include <memory>

struct RecoveryResult {
 std::unique_ptr<ScriptRuntime> runtime;
 std::unique_ptr<ScriptController> controller;
 PlaylistResult result;
 std::string log;
};
static std::vector<Frame> late_frames() {
 return {loop_status(9,PlaybackState::Ended,false,0),
 loop_status(10,PlaybackState::Playing,true,0),
 loop_status(10,PlaybackState::Playing,true,1),
 loop_status(10,PlaybackState::Playing,true,2),
 loop_status(10,PlaybackState::Playing,true,152),
 loop_status(10,PlaybackState::Playing,true,153),
 loop_status(10,PlaybackState::Playing,true,154),
 loop_status(10,PlaybackState::Ended,true,155),
 loop_status(11,PlaybackState::Playing,false,0),
 loop_status(99,PlaybackState::Idle,false,0)};
}
static RecoveryResult recovery(std::vector<Frame> frames,std::vector<ControlEvent> events,
 RepeatMode mode=RepeatMode::One,std::size_t start=0,std::uint16_t limit=2,bool fade_ok=true,
 const std::vector<Track> &tracks=three_tracks()) {
 RecoveryResult out;
 out.runtime.reset(new ScriptRuntime(std::move(frames)));out.runtime->stop_ok=fade_ok;
 PlaybackPreferences pref;pref.repeat=mode;
 out.controller.reset(new ScriptController(*out.runtime,std::move(events),pref));
 auto cfg=fast_config();cfg.end_timeout_ms=30;cfg.stop_timeout_ms=20;
 cfg.start_index=start;cfg.loop_limit=limit;
 std::ostringstream log;
 out.result=run(*out.runtime,cfg,tracks,log,out.controller.get());out.log=log.str();
 return out;
}
static std::size_t fades(const RecoveryResult &r) {
 return std::count(r.runtime->commands.begin(),r.runtime->commands.end(),
 "load_file 2 /tmp/megavgm_stop.control\n");
}
static void check(bool ok,const char *name,const RecoveryResult &r) {
 if(!ok)std::cerr<<name<<"\n"<<r.log;assert(ok);
 std::cout<<name<<": PASS fades="<<fades(r)<<" loads="<<r.runtime->generations.size()<<"\n";
}
int main() {
 {auto r=recovery({loop_status(9,PlaybackState::Ended,false,0),loop_status(10,PlaybackState::Playing,true,0),loop_status(10,PlaybackState::Playing,true,152)},{});
  check(r.result==PlaylistResult::TrackEndTimeout && fades(r)==0 && r.runtime->generations.size()==1,"ONE_STAYS_PLAYING",r);}
 for(auto mode:{RepeatMode::All,RepeatMode::Off}) {
  auto r=recovery(late_frames(),{{5,ControlCommandType::Repeat,{},mode}});
  check(r.result==PlaylistResult::Suspended && fades(r)==1 && r.runtime->generations.size()==2 && r.controller->saved_preferences.back().repeat==mode && r.log.find("source=LOOP_LIMIT from=1 action=LOAD to=2")!=std::string::npos,mode==RepeatMode::All?"LATE_ONE_ALL":"LATE_ONE_OFF",r);
 }
 {auto r=recovery(late_frames(),{{5,ControlCommandType::Repeat,{},RepeatMode::All}},RepeatMode::One,2);
  check(fades(r)==1 && r.runtime->generations.size()==2 && r.log.find("source=LOOP_LIMIT from=3 action=LOAD to=1")!=std::string::npos,"ALL_WRAPS_AFTER_ENDED",r);}
 {auto r=recovery(late_frames(),{{5,ControlCommandType::Repeat,{},RepeatMode::Off}},RepeatMode::One,2);
  check(fades(r)==1 && r.result==PlaylistResult::Complete && r.runtime->generations.size()==1,"OFF_COMPLETES_QUEUE_END",r);}
 {auto r=recovery({loop_status(9,PlaybackState::Ended,false,0),loop_status(10,PlaybackState::Playing,true,0),loop_status(10,PlaybackState::Playing,true,1),loop_status(10,PlaybackState::Playing,true,1),loop_status(10,PlaybackState::Ended,true,2),loop_status(11,PlaybackState::Playing,false,0),loop_status(99,PlaybackState::Idle,false,0)},{{3,ControlCommandType::Repeat,{},RepeatMode::All}});
  check(fades(r)==0 && r.runtime->generations.size()==2,"EARLY_ONE_ALL_NATIVE_END",r);}
 {auto f=late_frames();f[4].status.loop_count=1;f[5].status.loop_count=2;
  auto r=recovery(f,{{5,ControlCommandType::Repeat,{},RepeatMode::All}});
  check(fades(r)==1 && r.runtime->generations.size()==2,"BOUNDARY_DURING_POLICY_TRANSFER",r);}
 {auto r=recovery(late_frames(),{{3,ControlCommandType::Repeat,{},RepeatMode::One},{5,ControlCommandType::Repeat,{},RepeatMode::All}},RepeatMode::All);
  check(fades(r)==1 && r.runtime->transitions.size()>=3 && r.runtime->transitions[0]==megavgm_autoplay2::TransitionReason::LoopLimitTwoLoops && r.runtime->transitions[1]==megavgm_autoplay2::TransitionReason::LoopLimitDisabled && r.runtime->transitions[2]==megavgm_autoplay2::TransitionReason::LoopLimitTwoLoops,"ALL_ONE_ALL",r);}
 {auto r=recovery(late_frames(),{{5,ControlCommandType::Repeat,{},RepeatMode::All},{5,ControlCommandType::Repeat,{},RepeatMode::One}});
  check(fades(r)==0 && r.log.find("REPEAT_RECOVERY_FADE_ONLY")==std::string::npos,"ONE_CANCELS_UNISSUED_RECOVERY",r);}
 {auto r=recovery(late_frames(),{{5,ControlCommandType::Repeat,{},RepeatMode::All},{6,ControlCommandType::Repeat,{},RepeatMode::Off},{6,ControlCommandType::Repeat,{},RepeatMode::All},{6,ControlCommandType::Shuffle,{},RepeatMode::Off,true}});
  check(fades(r)==1 && r.controller->saved_preferences.back().repeat==RepeatMode::All && r.controller->saved_preferences.back().shuffle,"REPEAT_SHUFFLE_NO_DUPLICATE",r);}
 {auto r=recovery(late_frames(),{{5,ControlCommandType::Repeat,{},RepeatMode::Off},{6,ControlCommandType::Stop,{}}});
  bool stopped=false;for(const auto &v:r.controller->snapshots)if(v.state=="STOPPED" && v.session==10)stopped=true;
  check(fades(r)==1 && r.runtime->generations.size()==1 && stopped && r.log.find("STOP_JOINS_AUTOMATIC_FADE")!=std::string::npos,"STOP_JOINS_SAME_FADE",r);}
 {auto r=recovery(late_frames(),{{5,ControlCommandType::Repeat,{},RepeatMode::Off},{5,ControlCommandType::Stop,{}}});
  check(fades(r)==1 && r.log.find("REPEAT_RECOVERY_FADE_ONLY")==std::string::npos && r.runtime->generations.size()==1,"STOP_BEFORE_RECOVERY_PRIORITY",r);}
 {auto r=recovery(late_frames(),{{5,ControlCommandType::Repeat,{},RepeatMode::Off},{5,ControlCommandType::Next,{}}});
  check(fades(r)==0 && r.runtime->generations.size()==2 && r.log.find("source=MANUAL_NEXT")!=std::string::npos,"NEXT_BEFORE_RECOVERY_PRIORITY",r);}
 {auto r=recovery(late_frames(),{{5,ControlCommandType::Repeat,{},RepeatMode::Off},{6,ControlCommandType::Next,{}}});
  check(fades(r)==1 && r.runtime->generations.size()==2 && r.log.find("source=MANUAL_NEXT")!=std::string::npos,"NEXT_DURING_RECOVERY",r);}
 for(bool after_request:{false,true})for(unsigned stale:{9u,11u}) {
  auto f=late_frames();f[after_request?6:5]=loop_status(stale,PlaybackState::Ended,true,152);
  auto r=recovery(f,{{5,ControlCommandType::Repeat,{},RepeatMode::Off}});
  check(r.result==PlaylistResult::Suspended && fades(r)==std::size_t(after_request) && r.runtime->generations.size()==1,"STALE_ENDED_REJECTED",r);
 }
 {auto f=late_frames();f[5]=loop_status(11,PlaybackState::Playing,true,152);
  auto r=recovery(f,{{5,ControlCommandType::Repeat,{},RepeatMode::All}});
  check(r.result==PlaylistResult::Suspended && fades(r)==0 && r.runtime->generations.size()==1,"NEW_SESSION_NO_FADE",r);}
 {auto f=late_frames();for(auto &v:f)v.status.loop_valid=false;
  auto r=recovery(f,{{5,ControlCommandType::Repeat,{},RepeatMode::Off}});
  check(fades(r)==0,"NONLOOP_NO_RECOVERY",r);}
 {auto r=recovery(late_frames(),{{5,ControlCommandType::Repeat,{},RepeatMode::Off}},RepeatMode::One,0,0);
  check(fades(r)==0,"UNLIMITED_POLICY_NO_RECOVERY",r);}
 {auto r=recovery(late_frames(),{{5,ControlCommandType::Repeat,{},RepeatMode::Off}},RepeatMode::One,0,2,false);
  check(r.result==PlaylistResult::CommandWriteFailed && r.runtime->generations.size()==1,"FADE_WRITE_FAILURE_NO_ADVANCE",r);}
 {auto r=recovery({loop_status(9,PlaybackState::Ended,false,0),loop_status(10,PlaybackState::Playing,true,0),loop_status(10,PlaybackState::Playing,true,152)},{{3,ControlCommandType::Repeat,{},RepeatMode::Off}});
  check(r.result==PlaylistResult::StopTimeout && fades(r)==1 && r.runtime->generations.size()==1,"NO_ENDED_TIMEOUT_NO_ADVANCE",r);}
 {
  char dir[]="/tmp/megavgm-repeat-reload.XXXXXX";char *made=mkdtemp(dir);assert(made);
  std::string path=std::string(made)+"/Current.vgm";create_file(path);
  auto r=recovery({loop_status(9,PlaybackState::Ended,false,0),
   loop_status(10,PlaybackState::Playing,true,0),loop_status(10,PlaybackState::Playing,true,152),
   loop_status(10,PlaybackState::Playing,true,153),loop_status(10,PlaybackState::Ended,true,154),
   loop_status(11,PlaybackState::Playing,true,0),loop_status(11,PlaybackState::Playing,true,1),
   loop_status(11,PlaybackState::Ended,true,2)},
   {{3,ControlCommandType::Repeat,{},RepeatMode::Off},{4,ControlCommandType::Play,path}},
   RepeatMode::One,0,2,true,{{"Current.vgm",path}});
  check(r.result==PlaylistResult::Complete && fades(r)==1 && r.runtime->generations.size()==2 &&
   r.runtime->commands.front()==r.runtime->commands.back(),"RELOAD_DISCARDS_OLD_RECOVERY",r);
  unlink(path.c_str());rmdir(made);
 }
 // Existing actual discovery/queue Reload tests additionally exercise disposal
 // of track-local recovery state, public readiness, and stale completion.
 test_play_current_from_stopped_restarts_from_beginning();
 test_playlist_selection_from_stopped_replaces_context();
 test_stop_requires_owned_ended_and_rejects_reset_or_old_done();
 test_repeat_all_wrap_and_shuffle_bag();
 std::cout<<"REPEAT_RECOVERY_REGRESSION_PASS\n";
}
