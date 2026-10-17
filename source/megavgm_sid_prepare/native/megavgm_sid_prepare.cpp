// MegaVGMPlayer Engine C C6: raw PSID/RSID -> canonical Packed MVGMSID v2.
// Actual SID bus writes are observed synchronously at sidemu::writeReg entry.
#include "packed_v2.h"
#include "sha256.h"

#include <sidplayfp/sidplayfp.h>
#include <sidplayfp/SidConfig.h>
#include <sidplayfp/SidDatabase.h>
#include <sidplayfp/SidTune.h>
#include <sidplayfp/SidTuneInfo.h>
#include <sidplayfp/builders/sidlite.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <climits>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <limits>
#include <map>
#include <sstream>
#include <string>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <vector>

#ifndef MEGAVGM_SID_PREPARE_COMMIT
#define MEGAVGM_SID_PREPARE_COMMIT "unknown"
#endif
#ifndef MVGMSID_LIBSIDPLAYFP_COMMIT
#define MVGMSID_LIBSIDPLAYFP_COMMIT "unknown"
#endif

namespace {
using namespace megavgm_sid;
constexpr std::uint32_t kPalHz=985248;
constexpr std::uint32_t kNtscHz=1022727;
constexpr const char *kVersion="1.0.0";

struct Options {
	std::string input,output,cache_root,songlength_db,sidecar;
	std::string model="auto",timing="auto";
	std::uint64_t subtune=0,fallback_seconds=300,duration_ms=0;
	bool duration_override=false,inspect_source=false;
};

struct Sidecar {
	bool present=false;
	std::string source_sha,model,timing;
	std::uint64_t subtune=0,duration_ms=0;
};

struct LoopSidecar {
	bool present=false;
	std::string schema,content_sha;
	std::uint64_t subtune=0,start_ms=0,end_ms=0;
};

struct Resolution {
	std::string model,timing,model_source,timing_source,duration_source;
	std::uint32_t clock=0;
	std::uint64_t duration_ms=0,cycles=0;
	bool capture_limit=false,model_override=false,timing_override=false;
	std::string database_sha,tune_md5;
};

struct Capture {
	FILE *file=nullptr;
	std::uint64_t origin=0,end=0,previous=0,bytes=0,writes=0,capacity_cycle=0;
	bool active=false,have_write=false,failed=false,allow_capacity_limit=false,
		capacity_reached=false;
	std::string detail;
};

int fail(const std::string &message) { std::cerr<<"megavgm_sid_prepare: "<<message<<'\n';return 2; }

bool uint_value(const std::string &text,std::uint64_t &value)
{
	if(text.empty()||text[0]=='-')return false;
	char *end=nullptr;errno=0;const auto parsed=std::strtoull(text.c_str(),&end,10);
	if(errno||!end||*end)return false;
	value=parsed;
	return true;
}

std::string json(const char *value)
{
	std::string out="\"";
	if(value) {
		for(const unsigned char *p=(const unsigned char*)value;*p;++p){
			const unsigned char c=*p;
			if(c=='"'||c=='\\'){out.push_back('\\');out.push_back(char(c));}
			else if(c=='\b')out+="\\b";else if(c=='\f')out+="\\f";else if(c=='\n')out+="\\n";
			else if(c=='\r')out+="\\r";else if(c=='\t')out+="\\t";
			else if(c<0x20){char b[7];std::snprintf(b,sizeof(b),"\\u%04x",c);out+=b;}
			else out.push_back(char(c));
		}
	}
	out.push_back('"');return out;
}

std::string json(const std::string &value){return json(value.c_str());}

bool mkdirs(const std::string &path,std::string &detail)
{
	if(path.empty()||path[0]!='/'){detail="cache root must be absolute";return false;}
	std::string current;
	for(std::size_t i=1;i<=path.size();++i){
		if(i!=path.size()&&path[i]!='/')continue;
		current=path.substr(0,i);if(current.empty())continue;
		if(::mkdir(current.c_str(),0755)<0&&errno!=EEXIST){detail=std::strerror(errno);return false;}
		struct stat st={};if(::stat(current.c_str(),&st)<0||!S_ISDIR(st.st_mode)){detail="cache path component is not a directory";return false;}
	}
	return true;
}

bool copy_snapshot(const std::string &source,std::string &snapshot,
		std::array<std::uint8_t,32> &digest,std::string &detail)
{
	int in=open(source.c_str(),O_RDONLY|O_CLOEXEC|O_NOFOLLOW);if(in<0){detail=std::strerror(errno);return false;}
	struct stat st={};if(fstat(in,&st)<0||!S_ISREG(st.st_mode)){detail="source is not a regular non-symlink file";close(in);return false;}
	char name[]="/tmp/megavgm-sid-source-XXXXXX";int out=mkstemp(name);if(out<0){detail=std::strerror(errno);close(in);return false;}
	fchmod(out,0600);snapshot=name;Sha256 hash;std::uint8_t data[65536];bool ok=true;
	for(;;){ssize_t n=read(in,data,sizeof(data));if(n>0){hash.update(data,n);std::size_t off=0;while(off<std::size_t(n)){ssize_t w=write(out,data+off,n-off);if(w>0)off+=w;else if(w<0&&errno==EINTR)continue;else{detail=std::strerror(errno);ok=false;break;}}if(!ok)break;}else if(n==0)break;else if(errno!=EINTR){detail=std::strerror(errno);ok=false;break;}}
	if(ok&&fsync(out)<0){detail=std::strerror(errno);ok=false;}
	if(close(in)<0&&ok){detail=std::strerror(errno);ok=false;}if(close(out)<0&&ok){detail=std::strerror(errno);ok=false;}
	if(!ok){unlink(snapshot.c_str());snapshot.clear();return false;}digest=hash.finish();return true;
}

bool parse_sidecar(const std::string &path,const std::string &source_sha,
		std::uint64_t subtune,Sidecar &sidecar,std::string &detail)
{
	std::ifstream in(path);if(!in){if(errno==ENOENT){detail.clear();return true;}detail=std::strerror(errno);return false;}
	std::string line;if(!std::getline(in,line)||line!="MEGAVGMSID_OVERRIDE_V1"){detail="invalid SID override sidecar header";return false;}
	std::map<std::string,std::string> values;
	while(std::getline(in,line)){if(!line.empty()&&line.back()=='\r')line.pop_back();if(line.empty()){detail="empty SID override line";return false;}auto p=line.find('=');if(p==std::string::npos||p==0||!values.emplace(line.substr(0,p),line.substr(p+1)).second){detail="malformed/duplicate SID override";return false;}}
	for(const auto &item:values)if(item.first!="source_sha256"&&item.first!="subtune"&&item.first!="duration_ms"&&item.first!="model"&&item.first!="timing"){detail="unknown SID override key";return false;}
	if(values.count("source_sha256")!=1||values["source_sha256"]!=source_sha){detail="SID override source SHA mismatch";return false;}
	std::uint64_t selected=0;if(values.count("subtune")!=1||!uint_value(values["subtune"],selected)||selected!=subtune){detail="SID override subtune mismatch";return false;}
	sidecar.present=true;sidecar.source_sha=source_sha;sidecar.subtune=selected;
	if(values.count("duration_ms")){if(!uint_value(values["duration_ms"],sidecar.duration_ms)||!sidecar.duration_ms){detail="invalid SID override duration_ms";return false;}}
	if(values.count("model")){sidecar.model=values["model"];if(sidecar.model!="6581"&&sidecar.model!="8580"){detail="invalid SID override model";return false;}}
	if(values.count("timing")){sidecar.timing=values["timing"];std::transform(sidecar.timing.begin(),sidecar.timing.end(),sidecar.timing.begin(),::tolower);if(sidecar.timing!="pal"&&sidecar.timing!="ntsc"){detail="invalid SID override timing";return false;}}
	return true;
}

class LoopJsonParser {
public:
	explicit LoopJsonParser(const std::string &text):text_(text){}
	bool parse(std::map<std::string,std::string> &strings,
			std::map<std::string,std::uint64_t> &numbers,std::string &detail)
	{
		space();if(!take('{'))return error("manual loop sidecar must be a JSON object",detail);
		space();if(take('}'))return finish(detail);
		for(;;){
			std::string key;if(!string(key,detail))return false;
			space();if(!take(':'))return error("missing ':' in manual loop sidecar",detail);space();
			if(pos_<text_.size()&&text_[pos_]=='\"'){
				std::string value;if(!string(value,detail))return false;
				if(strings.count(key)||numbers.count(key))return error("duplicate manual loop sidecar key",detail);
				strings.emplace(key,value);
			}else{
				std::uint64_t value=0;if(!number(value,detail))return false;
				if(strings.count(key)||numbers.count(key))return error("duplicate manual loop sidecar key",detail);
				numbers.emplace(key,value);
			}
			space();if(take('}'))return finish(detail);
			if(!take(','))return error("missing ',' in manual loop sidecar",detail);
			space();
		}
	}
private:
	const std::string &text_;std::size_t pos_=0;
	void space(){while(pos_<text_.size()&&(text_[pos_]==' '||text_[pos_]=='\t'||text_[pos_]=='\r'||text_[pos_]=='\n'))++pos_;}
	bool take(char c){if(pos_<text_.size()&&text_[pos_]==c){++pos_;return true;}return false;}
	bool error(const char *message,std::string &detail){detail=message;return false;}
	bool finish(std::string &detail){space();if(pos_!=text_.size())return error("trailing manual loop sidecar data",detail);return true;}
	bool string(std::string &out,std::string &detail){
		if(!take('\"'))return error("manual loop sidecar key/value must be a JSON string",detail);
		while(pos_<text_.size()){
			const unsigned char c=text_[pos_++];if(c=='\"')return true;
			if(c<0x20)return error("control character in manual loop sidecar string",detail);
			if(c!='\\'){out.push_back(char(c));continue;}
			if(pos_>=text_.size())return error("truncated JSON escape",detail);
			const char e=text_[pos_++];
			if(e=='\"'||e=='\\'||e=='/')out.push_back(e);
			else if(e=='b')out.push_back('\b');else if(e=='f')out.push_back('\f');
			else if(e=='n')out.push_back('\n');else if(e=='r')out.push_back('\r');else if(e=='t')out.push_back('\t');
			else return error("unsupported JSON escape in manual loop sidecar",detail);
		}
		return error("unterminated manual loop sidecar string",detail);
	}
	bool number(std::uint64_t &out,std::string &detail){
		if(pos_>=text_.size()||text_[pos_]<'0'||text_[pos_]>'9')return error("manual loop sidecar number must be an unsigned integer",detail);
		if(text_[pos_]=='0'&&pos_+1<text_.size()&&text_[pos_+1]>='0'&&text_[pos_+1]<='9')return error("noncanonical manual loop sidecar integer",detail);
		while(pos_<text_.size()&&text_[pos_]>='0'&&text_[pos_]<='9'){
			const unsigned digit=text_[pos_++]-'0';
			if(out>(std::numeric_limits<std::uint64_t>::max()-digit)/10)return error("manual loop sidecar integer overflow",detail);
			out=out*10+digit;
		}
		return true;
	}
};

bool read_loop_sidecar(const std::string &path,const std::string &source_sha,
		std::uint64_t subtune,LoopSidecar &sidecar,std::string &detail)
{
	int fd=open(path.c_str(),O_RDONLY|O_CLOEXEC|O_NOFOLLOW);
	if(fd<0){if(errno==ENOENT){detail.clear();return true;}detail=std::strerror(errno);return false;}
	struct stat st={};if(fstat(fd,&st)<0||!S_ISREG(st.st_mode)||st.st_size<2||st.st_size>16384){
		detail="manual loop sidecar is not a bounded regular file";close(fd);return false;
	}
	std::string content(static_cast<std::size_t>(st.st_size),'\0');std::size_t off=0;
	while(off<content.size()){
		const auto n=read(fd,&content[off],content.size()-off);
		if(n>0)off+=static_cast<std::size_t>(n);else if(n<0&&errno==EINTR)continue;
		else{detail=n==0?"truncated manual loop sidecar":std::strerror(errno);close(fd);return false;}
	}
	if(close(fd)<0){detail=std::strerror(errno);return false;}
	std::map<std::string,std::string> strings;std::map<std::string,std::uint64_t> numbers;
	LoopJsonParser parser(content);if(!parser.parse(strings,numbers,detail))return false;
	for(const auto &item:strings)if(item.first!="schema"&&item.first!="source_sha256"){
		detail="unknown/string-typed manual loop sidecar field";return false;
	}
	for(const auto &item:numbers)if(item.first!="subtune"&&item.first!="loop_start_ms"&&item.first!="loop_end_ms"){
		detail="unknown/numeric manual loop sidecar field";return false;
	}
	if(strings.size()!=2||numbers.size()!=3||strings["schema"]!="MegaVGMPlayer-SID-loop-v1"){
		detail="manual loop sidecar schema/field set mismatch";return false;
	}
	if(strings["source_sha256"]!=source_sha){detail="manual loop sidecar source SHA mismatch";return false;}
	if(numbers["subtune"]!=subtune){detail="manual loop sidecar subtune mismatch";return false;}
	if(numbers["loop_end_ms"]<=numbers["loop_start_ms"]){detail="manual loop sidecar start must precede end";return false;}
	Sha256 hash;hash.update(content.data(),content.size());sidecar.present=true;
	sidecar.schema=strings["schema"];sidecar.content_sha=hex_digest(hash.finish());sidecar.subtune=subtune;
	sidecar.start_ms=numbers["loop_start_ms"];sidecar.end_ms=numbers["loop_end_ms"];
	return true;
}

bool milliseconds_to_cycle(std::uint64_t milliseconds,std::uint32_t clock,
		std::uint64_t &cycle,std::string &detail)
{
	const auto seconds=milliseconds/1000,remainder=milliseconds%1000;
	if(seconds>std::numeric_limits<std::uint64_t>::max()/clock){detail="manual loop cycle overflow";return false;}
	cycle=seconds*clock;
	const auto fraction=remainder*std::uint64_t(clock);
	const auto rounded=(fraction+500)/1000;
	if(cycle>std::numeric_limits<std::uint64_t>::max()-rounded){detail="manual loop cycle overflow";return false;}
	cycle+=rounded;return true;
}

const char *model_name(SidTuneInfo::model_t value){switch(value){case SidTuneInfo::SIDMODEL_6581:return "6581";case SidTuneInfo::SIDMODEL_8580:return "8580";case SidTuneInfo::SIDMODEL_ANY:return "any";default:return "unknown";}}
const char *timing_name(SidTuneInfo::clock_t value){switch(value){case SidTuneInfo::CLOCK_PAL:return "pal";case SidTuneInfo::CLOCK_NTSC:return "ntsc";case SidTuneInfo::CLOCK_ANY:return "any";default:return "unknown";}}

bool resolve(const Options &options,SidTune &tune,const SidTuneInfo &info,
		const std::string &source_sha,const Sidecar &sidecar,Resolution &r,std::string &detail)
{
	const auto declared_model=info.sidModel(0);const auto declared_timing=info.clockSpeed();
	if(options.model!="auto"){r.model=options.model;r.model_source="cli";r.model_override=true;}
	else if(declared_model==SidTuneInfo::SIDMODEL_6581||declared_model==SidTuneInfo::SIDMODEL_8580){r.model=model_name(declared_model);r.model_source="PSID/RSID header";}
	else if(!sidecar.model.empty()){r.model=sidecar.model;r.model_source="exact SHA/subtune sidecar";r.model_override=true;}
	else{detail="SID model metadata is unknown/any and no exact override exists";return false;}
	if(options.timing!="auto"){r.timing=options.timing;r.timing_source="cli";r.timing_override=true;}
	else if(declared_timing==SidTuneInfo::CLOCK_PAL||declared_timing==SidTuneInfo::CLOCK_NTSC){r.timing=timing_name(declared_timing);r.timing_source="PSID/RSID header";}
	else if(!sidecar.timing.empty()){r.timing=sidecar.timing;r.timing_source="exact SHA/subtune sidecar";r.timing_override=true;}
	else{detail="SID timing metadata is unknown/any and no exact override exists";return false;}
	r.clock=r.timing=="pal"?kPalHz:kNtscHz;
	if(!options.songlength_db.empty()){
		struct stat st={};if(stat(options.songlength_db.c_str(),&st)==0){
			SidDatabase db;if(!db.open(options.songlength_db.c_str())){detail=std::string("cannot open songlength DB: ")+db.error();return false;}
			const auto length=db.lengthMs(tune);if(length>0){r.duration_ms=static_cast<std::uint64_t>(length);r.duration_source="HVSC Songlengths.md5 exact content MD5 + subtune";std::array<std::uint8_t,32>d{};if(!sha256_file(options.songlength_db,d,detail))return false;r.database_sha=hex_digest(d);}
		} else if(errno!=ENOENT){detail=std::string("songlength DB stat: ")+std::strerror(errno);return false;}
	}
	if(!r.duration_ms&&options.duration_override){r.duration_ms=options.duration_ms;r.duration_source="CLI explicit duration";}
	if(!r.duration_ms&&sidecar.duration_ms){r.duration_ms=sidecar.duration_ms;r.duration_source="exact SHA/subtune sidecar";}
	if(!r.duration_ms){if(!options.fallback_seconds||options.fallback_seconds>std::numeric_limits<std::uint64_t>::max()/1000){detail="invalid fallback duration";return false;}r.duration_ms=options.fallback_seconds*1000;r.duration_source="fallback capture limit";r.capture_limit=true;}
	if(r.duration_ms>std::numeric_limits<std::uint64_t>::max()/r.clock){detail="duration cycle multiplication overflow";return false;}
	const auto product=r.duration_ms*std::uint64_t(r.clock);r.cycles=product/1000+(product%1000?1:0);if(!r.cycles){detail="zero capture duration";return false;}
	char md5[SidTune::MD5_LENGTH+1]={};tune.createMD5New(md5);r.tune_md5=md5;
	(void)source_sha;return true;
}

void observe(void *opaque,unsigned sid,uint_least64_t cycle,uint_least8_t addr,uint8_t data)
{
	auto &c=*static_cast<Capture*>(opaque);if(!c.active||c.failed)return;
	if(cycle<c.origin){c.failed=true;c.detail="observer cycle before capture origin";return;}
	const std::uint64_t relative=cycle-c.origin;if(relative>=c.end)return;
	if(sid!=0||addr>0x18){c.failed=true;c.detail="unsupported SID index/register observed";return;}
	if(c.have_write&&relative<=c.previous){c.failed=true;c.detail=relative==c.previous?"same-cycle SID WRITE":"unordered SID WRITE";return;}
	// Preserve enough room for the canonical EOF record. A duration-less
	// fallback may end at this real bus-cycle boundary; trusted durations must
	// never be silently shortened.
	const auto decision=capacity_decision(c.bytes,relative-c.previous,c.allow_capacity_limit);
	if(decision!=CapacityDecision::Write){
		if(decision==CapacityDecision::Reject){c.failed=true;c.detail="prepared stream exceeds 8 MiB Engine C capacity";return;}
		c.capacity_reached=true;c.capacity_cycle=relative;c.active=false;return;
	}
	std::string detail;if(!write_uleb(c.file,relative-c.previous,c.bytes,detail)||
		std::fputc(addr,c.file)==EOF||std::fputc(data,c.file)==EOF){c.failed=true;c.detail=detail.empty()?std::strerror(errno):detail;return;}
	c.bytes+=2;
	c.previous=relative;c.have_write=true;++c.writes;
}

bool write_all(int fd,const std::string &data,std::string &detail)
{
	std::size_t off=0;while(off<data.size()){ssize_t n=write(fd,data.data()+off,data.size()-off);if(n>0)off+=n;else if(n<0&&errno==EINTR)continue;else{detail=std::strerror(errno);return false;}}return true;
}

bool atomic_text(const std::string &path,const std::string &data,std::string &detail)
{
	std::string pattern=path+".tmp.XXXXXX";std::vector<char> name(pattern.begin(),pattern.end());name.push_back(0);
	int fd=mkstemp(name.data());if(fd<0){detail=std::strerror(errno);return false;}fchmod(fd,0644);
	bool ok=write_all(fd,data,detail);if(ok&&fsync(fd)<0){detail=std::strerror(errno);ok=false;}if(close(fd)<0&&ok){detail=std::strerror(errno);ok=false;}
	if(ok&&rename(name.data(),path.c_str())<0){detail=std::strerror(errno);ok=false;}if(!ok)unlink(name.data());return ok;
}

bool fsync_parent_directory(const std::string &path,std::string &detail)
{
	const auto slash=path.find_last_of('/');const std::string parent=slash==std::string::npos?".":slash?path.substr(0,slash):"/";
	int flags=O_RDONLY|O_CLOEXEC;
#ifdef O_DIRECTORY
	flags|=O_DIRECTORY;
#endif
	int fd=open(parent.c_str(),flags);if(fd<0){detail=std::strerror(errno);return false;}
	bool ok=true;
#ifdef MEGAVGM_SID_PREPARE_TESTING
	if(std::getenv("MEGAVGM_TEST_DIRECTORY_FSYNC_FAILURE")){errno=EIO;ok=false;}
	else
#endif
	if(fsync(fd)<0)ok=false;
	if(!ok)detail=std::strerror(errno);
	if(close(fd)<0&&ok){detail=std::strerror(errno);ok=false;}
	return ok;
}

std::string build_provenance(const Options &o,const SidTuneInfo &info,const Resolution &r,
		const Sidecar &sidecar,const LoopSidecar &loop,const std::string &source_sha,const std::string &cache_key,
		const std::string &output,const std::string &output_sha,const PackedMetadata &m)
{
	std::ostringstream s;s<<"{\n  \"schema\":\"MegaVGMPlayer-SID-cache-v1\",\n"
	 <<"  \"cache_key\":"<<json(cache_key)<<",\n  \"source\":{\"path\":"<<json(o.input)
	 <<",\"sha256\":"<<json(source_sha)<<",\"title\":"<<json(info.numberOfInfoStrings()>0?info.infoString(0):"")
	 <<",\"author\":"<<json(info.numberOfInfoStrings()>1?info.infoString(1):"")
	 <<",\"released\":"<<json(info.numberOfInfoStrings()>2?info.infoString(2):"")
	 <<",\"format\":"<<json(info.formatString())<<",\"compatibility\":"<<int(info.compatibility())
	 <<",\"songs\":"<<info.songs()<<",\"start_song\":"<<info.startSong()<<"},\n"
	 <<"  \"selection\":{\"subtune\":"<<m.subtune<<",\"model\":"<<json(r.model)
	 <<",\"timing\":"<<json(r.timing)<<",\"clock_num\":"<<m.clock_num<<",\"clock_den\":1"
	 <<",\"model_source\":"<<json(r.model_source)<<",\"timing_source\":"<<json(r.timing_source)<<"},\n"
	 <<"  \"duration\":{\"milliseconds\":"<<r.duration_ms<<",\"source\":"<<json(r.duration_source)
	 <<",\"capture_limit\":"<<(r.capture_limit?"true":"false")<<",\"database_sha256\":"<<json(r.database_sha)
	 <<",\"tune_md5_new\":"<<json(r.tune_md5)<<"},\n"
	 <<"  \"converter\":{\"version\":"<<json(kVersion)<<",\"commit\":"<<json(MEGAVGM_SID_PREPARE_COMMIT)
		 <<",\"libsidplayfp_version\":\"3.1.1\",\"libsidplayfp_commit\":"<<json(MVGMSID_LIBSIDPLAYFP_COMMIT)
		 <<",\"capacity_bytes\":"<<kMaximumFileBytes
	 <<",\"capture_hook\":\"sidemu::writeReg entry / EventScheduler PHI1\",\"external_roms\":false},\n"
	 <<"  \"capture\":{\"write_count\":"<<m.write_count<<",\"final_native_cycle\":"<<m.stream_cycles
	 <<",\"loop_valid\":"<<((m.flags&kLoopValid)?"true":"false")<<"},\n"
	 <<"  \"loop\":{\"loop_source\":"<<json(loop.present?"manual_sidecar":"none")
	 <<",\"sidecar_sha256\":"<<json(loop.content_sha)<<",\"requested_loop_start_ms\":"<<loop.start_ms
	 <<",\"requested_loop_end_ms\":"<<loop.end_ms<<",\"resolved_loop_start_cycle\":"<<m.loop_start_cycle
	 <<",\"resolved_loop_end_cycle\":"<<m.loop_end_cycle<<",\"loop_write_index\":"<<m.loop_write_index
	 <<",\"loop_valid\":"<<((m.flags&kLoopValid)?"true":"false")<<"},\n"
	 <<"  \"artifact\":{\"path\":"<<json(output)<<",\"format\":\"Packed MVGMSID v2.0\",\"sha256\":"<<json(output_sha)<<"},\n"
	 <<"  \"override_sidecar_present\":"<<(sidecar.present?"true":"false")<<"\n}\n";return s.str();
}

std::string cache_key(const std::string &source_sha,const Resolution &r,std::uint64_t subtune,
		const LoopSidecar &loop)
{
	std::ostringstream canonical;canonical<<"MegaVGMPlayer-SID-cache-key-v1\nsource="<<source_sha
	 <<"\nsubtune="<<subtune<<"\nmodel="<<r.model<<"\ntiming="<<r.timing<<"\nclock="<<r.clock<<"/1"
	 <<"\nduration_ms="<<r.duration_ms<<"\nduration_source="<<r.duration_source<<"\ndb_sha="<<r.database_sha
	 <<"\nconverter="<<kVersion<<"@"<<MEGAVGM_SID_PREPARE_COMMIT
		 <<"\nlibsidplayfp=3.1.1@"<<MVGMSID_LIBSIDPLAYFP_COMMIT
		 <<"\npacked=2.0/encoding1\ncapacity_bytes="<<kMaximumFileBytes<<"\n";
	if(loop.present)canonical<<"loop_schema="<<loop.schema<<"\nloop_sidecar_sha256="<<loop.content_sha
		<<"\nloop_source_sha256="<<source_sha<<"\nloop_subtune="<<subtune
		<<"\nloop_start_ms="<<loop.start_ms<<"\nloop_end_ms="<<loop.end_ms
		<<"\nloop_snap=nearest-write-boundary-ties-earlier-v1\n";
	Sha256 h;const auto value=canonical.str();h.update(value.data(),value.size());return hex_digest(h.finish());
}

bool provenance_matches(const std::string &path,const std::string &key,
		const std::string &sha)
{
	std::ifstream in(path,std::ios::binary);if(!in)return false;
	std::string content((std::istreambuf_iterator<char>(in)),{});if(content.size()>65536)return false;
	return content.find("\"cache_key\":\""+key+"\"")!=std::string::npos&&
		content.find("\"sha256\":\""+sha+"\"")!=std::string::npos;
}

bool capture_to(SidTune &tune,
		const Resolution &r,const std::array<std::uint8_t,32> &source_digest,
		const std::string &temporary,PackedMetadata &metadata,std::string &detail)
{
	FILE *file=std::fopen(temporary.c_str(),"w+b");if(!file){detail=std::strerror(errno);return false;}
	std::uint8_t zero[128]={};if(std::fwrite(zero,1,sizeof(zero),file)!=sizeof(zero)){detail=std::strerror(errno);std::fclose(file);return false;}
	sidplayfp player;SIDLiteBuilder sid("megavgm-sid-prepare");Capture capture;capture.file=file;capture.end=r.cycles;
	capture.allow_capacity_limit=r.capture_limit;
	player.setSidWriteObserver(observe,&capture);SidConfig cfg=player.config();cfg.sidEmulation=&sid;cfg.frequency=48000;
	cfg.samplingMethod=SidConfig::INTERPOLATE;cfg.powerOnDelay=0;cfg.defaultSidModel=r.model=="6581"?SidConfig::MOS6581:SidConfig::MOS8580;
	cfg.forceSidModel=r.model_override;cfg.defaultC64Model=r.timing=="pal"?SidConfig::PAL:SidConfig::NTSC;cfg.forceC64Model=r.timing_override;
	if(!player.config(cfg)){detail=std::string("libsidplayfp config failed: ")+player.error();std::fclose(file);return false;}
	if(!player.load(&tune)){detail=std::string("libsidplayfp load failed: ")+player.error();std::fclose(file);return false;}
	if(player.installedSIDs()!=1){detail="runtime SID count is not one";std::fclose(file);return false;}
	capture.origin=player.currentCycle();capture.active=true;
	while(player.currentCycle()-capture.origin<r.cycles&&!capture.failed&&!capture.capacity_reached){const auto before=player.currentCycle();if(player.play(4096)<0){capture.failed=true;capture.detail=std::string("emulation failed: ")+player.error();break;}if(player.currentCycle()<=before){capture.failed=true;capture.detail="emulator made no cycle progress";break;}}
	capture.active=false;if(capture.failed){detail=capture.detail;std::fclose(file);return false;}
	const std::uint64_t final_cycle=capture.capacity_reached?capture.capacity_cycle:r.cycles;
	if(final_cycle<capture.previous||!write_uleb(file,final_cycle-capture.previous,capture.bytes,detail)||std::fputc(0xff,file)==EOF){if(detail.empty())detail=std::strerror(errno);std::fclose(file);return false;}++capture.bytes;
	metadata.flags=r.capture_limit?kEndIsCaptureLimit:kDurationKnown;
	if(r.model_override)metadata.flags|=kModelExplicitOverride;
	if(r.timing_override)metadata.flags|=kClockExplicitOverride;
	metadata.clock_num=r.clock;metadata.sid_model=r.model=="6581"?1:2;metadata.timing_standard=r.timing=="pal"?1:2;
	metadata.subtune=static_cast<std::uint32_t>(tune.getInfo()->currentSong());metadata.write_count=capture.writes;
	metadata.stream_bytes=capture.bytes;metadata.stream_cycles=final_cycle;metadata.duration_cycles=r.capture_limit?0:final_cycle;metadata.source_sha256=source_digest;
	if(!write_header(file,metadata,detail)){std::fclose(file);return false;}
	if(std::fflush(file)!=0||fsync(fileno(file))<0){detail=std::strerror(errno);std::fclose(file);return false;}
	if(std::fclose(file)!=0){detail=std::strerror(errno);return false;}
	PackedMetadata checked;if(!validate_packed_v2(temporary,checked,detail))return false;
	return true;
}

bool parse_options(int argc,char **argv,Options &o,std::string &detail)
{
	for(int i=1;i<argc;++i){std::string arg=argv[i];auto need=[&]()->const char*{return ++i<argc?argv[i]:nullptr;};const char *v=nullptr;
		if(arg=="--input"&&(v=need()))o.input=v;else if(arg=="--output"&&(v=need()))o.output=v;
		else if(arg=="--cache-root"&&(v=need()))o.cache_root=v;else if(arg=="--songlength-db"&&(v=need()))o.songlength_db=v;
		else if(arg=="--sidecar"&&(v=need()))o.sidecar=v;else if(arg=="--model"&&(v=need()))o.model=v;
		else if(arg=="--timing"&&(v=need()))o.timing=v;else if(arg=="--inspect-source")o.inspect_source=true;
		else if(arg=="--subtune"&&(v=need())){if(!uint_value(v,o.subtune))return detail="invalid --subtune",false;}
		else if(arg=="--fallback-seconds"&&(v=need())){if(!uint_value(v,o.fallback_seconds))return detail="invalid --fallback-seconds",false;}
		else if(arg=="--duration-ms"&&(v=need())){if(!uint_value(v,o.duration_ms)||!o.duration_ms)return detail="invalid --duration-ms",false;o.duration_override=true;}
		else return detail="invalid/incomplete argument: "+arg,false;
	}
	if(o.input.empty())return detail="--input is required",false;
	if(!o.inspect_source&&(o.output.empty()==o.cache_root.empty()))return detail="choose exactly one of --output or --cache-root",false;
	if(o.model!="auto"&&o.model!="6581"&&o.model!="8580")return detail="--model must be auto, 6581 or 8580",false;
	std::transform(o.timing.begin(),o.timing.end(),o.timing.begin(),::tolower);
	if(o.timing!="auto"&&o.timing!="pal"&&o.timing!="ntsc")return detail="--timing must be auto, pal or ntsc",false;
	return true;
}

} // namespace

int main(int argc,char **argv)
{
	Options o;std::string detail;if(!parse_options(argc,argv,o,detail))return fail(detail);
	std::string snapshot;std::array<std::uint8_t,32> source_digest{};if(!copy_snapshot(o.input,snapshot,source_digest,detail))return fail("source snapshot: "+detail);
	struct Cleanup{std::string path;~Cleanup(){if(!path.empty())unlink(path.c_str());}} cleanup{snapshot};
	SidTune tune(snapshot.c_str());if(!tune.getStatus())return fail(std::string("malformed/unsupported SID: ")+tune.statusString());
	const SidTuneInfo *initial=tune.getInfo();if(!initial)return fail("missing SID metadata");
	if(initial->sidChips()!=1)return fail("only single-SID files are supported");
	if(initial->compatibility()==SidTuneInfo::COMPATIBILITY_BASIC)return fail("SID requires a C64 BASIC ROM; external ROM support is not enabled");
	const std::uint64_t subtune=o.subtune?o.subtune:initial->startSong();if(!subtune||subtune>initial->songs()||tune.selectSong(static_cast<unsigned>(subtune))!=subtune)return fail("subtune outside 1..songs");
	const SidTuneInfo *info=tune.getInfo();if(!info)return fail("missing selected-subtune metadata");
	const std::string source_sha=hex_digest(source_digest);Sidecar sidecar;LoopSidecar loop;
	const std::string sidecar_path=o.sidecar.empty()?o.input+".megavgm":o.sidecar;
	if(!parse_sidecar(sidecar_path,source_sha,subtune,sidecar,detail))return fail(detail);
	Resolution r;if(!resolve(o,tune,*info,source_sha,sidecar,r,detail))return fail(detail);
	if(!read_loop_sidecar(o.input+".loop.json",source_sha,subtune,loop,detail))return fail(detail);
	if(loop.present&&loop.end_ms>r.duration_ms)return fail("manual loop end exceeds capture horizon");
	if(o.inspect_source){std::cout<<"{\"title\":"<<json(info->numberOfInfoStrings()?info->infoString(0):"")<<",\"songs\":"<<info->songs()<<",\"startSong\":"<<info->startSong()<<",\"subtune\":"<<subtune<<",\"model\":"<<json(r.model)<<",\"timing\":"<<json(r.timing)<<",\"durationMs\":"<<r.duration_ms<<"}\n";return 0;}
	const std::string key=cache_key(source_sha,r,subtune,loop);std::string output=o.output,provenance=o.output+".json",lock_path;int lock_fd=-1;
	if(!o.cache_root.empty()){
		if(!mkdirs(o.cache_root,detail))return fail("cache root: "+detail);
		output=o.cache_root+"/"+key+".mvgmsid";provenance=o.cache_root+"/"+key+".json";lock_path=o.cache_root+"/"+key+".lock";
		lock_fd=open(lock_path.c_str(),O_RDWR|O_CREAT|O_CLOEXEC,0600);if(lock_fd<0||flock(lock_fd,LOCK_EX)<0)return fail("cache lock failed: "+std::string(std::strerror(errno)));
		PackedMetadata existing;std::array<std::uint8_t,32> digest{};
		if(validate_packed_v2(output,existing,detail)&&existing.source_sha256==source_digest&&existing.subtune==subtune&&
			existing.sid_model==(r.model=="6581"?1:2)&&existing.timing_standard==(r.timing=="pal"?1:2)&&
			sha256_file(output,digest,detail)&&provenance_matches(provenance,key,hex_digest(digest))){
			std::cout<<output<<'\n';close(lock_fd);return 0;
		}
	}
	const std::string temporary=output+".tmp."+std::to_string(static_cast<unsigned long>(getpid()));unlink(temporary.c_str());
	PackedMetadata metadata;if(!capture_to(tune,r,source_digest,temporary,metadata,detail)){unlink(temporary.c_str());if(lock_fd>=0)close(lock_fd);return fail(detail);}
	if(loop.present){
		std::uint64_t requested_start_cycle=0,requested_end_cycle=0;
		if(!milliseconds_to_cycle(loop.start_ms,r.clock,requested_start_cycle,detail)||
		   !milliseconds_to_cycle(loop.end_ms,r.clock,requested_end_cycle,detail)){
			unlink(temporary.c_str());if(lock_fd>=0)close(lock_fd);return fail(detail);
		}
		if(!canonicalize_manual_loop(temporary,temporary,requested_start_cycle,
			requested_end_cycle,metadata,detail)){
			unlink(temporary.c_str());if(lock_fd>=0)close(lock_fd);return fail(detail);
		}
	}
	std::array<std::uint8_t,32> out_digest{};if(!sha256_file(temporary,out_digest,detail)){unlink(temporary.c_str());if(lock_fd>=0)close(lock_fd);return fail(detail);}
	const std::string out_sha=hex_digest(out_digest);
	const std::string content=build_provenance(o,*info,r,sidecar,loop,source_sha,key,output,out_sha,metadata);
	if(!atomic_text(provenance,content,detail)){unlink(temporary.c_str());if(lock_fd>=0)close(lock_fd);return fail("provenance: "+detail);}
	if(rename(temporary.c_str(),output.c_str())<0){unlink(temporary.c_str());if(lock_fd>=0)close(lock_fd);return fail("atomic publish: "+std::string(std::strerror(errno)));}
	if(!fsync_parent_directory(output,detail)){if(lock_fd>=0)close(lock_fd);return fail("cache directory fsync: "+detail);}
	if(lock_fd>=0)close(lock_fd);
	std::cout<<output<<'\n';
	return 0;
}
