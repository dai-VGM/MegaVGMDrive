#include "packed_v2.h"

#include <cerrno>
#include <cstring>
#include <fstream>
#include <limits>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace megavgm_sid {
namespace {

void put16(std::uint8_t *p, std::uint16_t v) { p[0]=v; p[1]=v>>8; }
void put32(std::uint8_t *p, std::uint32_t v) { for(unsigned i=0;i<4;++i)p[i]=v>>(i*8); }
void put64(std::uint8_t *p, std::uint64_t v) { for(unsigned i=0;i<8;++i)p[i]=v>>(i*8); }
std::uint16_t get16(const std::uint8_t *p) { return p[0]|(std::uint16_t(p[1])<<8); }
std::uint32_t get32(const std::uint8_t *p) { std::uint32_t v=0;for(int i=3;i>=0;--i)v=(v<<8)|p[i];return v; }
std::uint64_t get64(const std::uint8_t *p) { std::uint64_t v=0;for(int i=7;i>=0;--i)v=(v<<8)|p[i];return v; }

bool read_exact(FILE *file, void *target, std::size_t size, std::string &detail)
{
	if (std::fread(target,1,size,file)==size) return true;
	detail=std::ferror(file)?std::strerror(errno):"truncated file";return false;
}

bool read_uleb(FILE *file, std::uint64_t &value, std::uint64_t &bytes,
		std::string &detail)
{
	value=0;unsigned count=0;
	for(unsigned group=0;group<10;++group) {
		int ch=std::fgetc(file);if(ch==EOF){detail="truncated ULEB128";return false;}
		const auto byte=static_cast<std::uint8_t>(ch);++count;++bytes;
		if(group==9 && byte>1){detail="ULEB128 u64 overflow";return false;}
		value|=std::uint64_t(byte&0x7f)<<(group*7);
		if(!(byte&0x80)) {
			std::uint64_t copy=value;unsigned canonical=1;while(copy>=128){copy>>=7;++canonical;}
			if(canonical!=count){detail="noncanonical ULEB128";return false;}
			return true;
		}
	}
	detail="overlong ULEB128";return false;
}

bool valid_metadata(const PackedMetadata &m, std::string &detail)
{
	if(m.flags&~kKnownFlags){detail="unknown flags";return false;}
	if(!m.clock_num||!m.clock_den){detail="zero clock numerator/denominator";return false;}
	if(m.sid_model<1||m.sid_model>2||m.timing_standard<1||m.timing_standard>2){detail="unknown model/timing";return false;}
	if(!m.subtune){detail="subtune is not 1-based";return false;}
	if(bool(m.flags&kDurationKnown)!=bool(m.duration_cycles)){detail="duration flag/cycles mismatch";return false;}
	if(m.stream_bytes<2||m.stream_bytes>kMaximumStreamBytes){detail="packed stream exceeds Engine C capacity";return false;}
	if(m.write_count>(std::numeric_limits<std::uint64_t>::max()-2)/3 ||
		3*m.write_count+2>m.stream_bytes){detail="impossible WRITE count/stream size";return false;}
	if(m.write_count>(std::numeric_limits<std::uint64_t>::max()-11)/12 ||
		m.stream_bytes>12*m.write_count+11){detail="impossible packed stream size";return false;}
	if(m.flags&kLoopValid) {
		if(!(m.loop_start_cycle<m.loop_end_cycle &&
			m.loop_end_cycle==m.stream_cycles)){
			detail="invalid loop cycle range";return false;
		}
		if(m.loop_write_index>m.write_count){detail="loop WRITE ordinal out of range";return false;}
	} else if(m.loop_write_index||m.loop_start_cycle||m.loop_end_cycle) {
		detail="loop metadata without LOOP_VALID";return false;
	}
	return true;
}

struct WireWrite {
	std::uint64_t cycle;
	std::uint8_t address;
	std::uint8_t data;
};

bool read_file(const std::string &path,std::vector<std::uint8_t> &raw,std::string &detail)
{
	std::ifstream in(path,std::ios::binary);if(!in){detail=std::strerror(errno);return false;}
	in.seekg(0,std::ios::end);const auto end=in.tellg();
	if(end<0||std::uint64_t(end)>kMaximumFileBytes){detail="invalid file size";return false;}
	raw.resize(static_cast<std::size_t>(end));in.seekg(0);
	if(!raw.empty()&&!in.read(reinterpret_cast<char*>(raw.data()),raw.size())){detail="cannot read packed stream";return false;}
	return true;
}

bool read_uleb_bytes(const std::vector<std::uint8_t> &raw,std::size_t &pos,
		std::uint64_t &value,std::string &detail)
{
	value=0;const auto start=pos;
	for(unsigned group=0;group<10;++group){
		if(pos>=raw.size()){detail="truncated ULEB128";return false;}
		const auto byte=raw[pos++];
		if(group==9&&byte>1){detail="ULEB128 u64 overflow";return false;}
		value|=std::uint64_t(byte&0x7f)<<(group*7);
		if(!(byte&0x80)){
			if(pos-start!=uleb_size(value)){detail="noncanonical ULEB128";return false;}
			return true;
		}
	}
	detail="overlong ULEB128";return false;
}

std::uint64_t distance(std::uint64_t a,std::uint64_t b){return a>b?a-b:b-a;}

std::uint64_t nearest_boundary(const std::vector<std::uint64_t> &boundaries,
		std::uint64_t requested)
{
	std::uint64_t best=boundaries.front(),best_distance=distance(best,requested);
	for(const auto value:boundaries){
		const auto d=distance(value,requested);
		if(d<best_distance||(d==best_distance&&value<best)){best=value;best_distance=d;}
	}
	return best;
}

} // namespace

unsigned uleb_size(std::uint64_t value)
{
	unsigned bytes=1;while(value>=128){value>>=7;++bytes;}return bytes;
}

CapacityDecision capacity_decision(std::uint64_t current_stream_bytes,
		std::uint64_t delta, bool allow_capacity_limit)
{
	const auto write_bytes=std::uint64_t(uleb_size(delta))+2;
	const bool fits=current_stream_bytes<=kMaximumStreamBytes &&
		write_bytes<=kMaximumStreamBytes-current_stream_bytes &&
		kMaximumEofBytes<=kMaximumStreamBytes-current_stream_bytes-write_bytes;
	if(fits)return CapacityDecision::Write;
	return allow_capacity_limit?CapacityDecision::CaptureLimit:CapacityDecision::Reject;
}

bool write_uleb(FILE *file, std::uint64_t value, std::uint64_t &bytes,
		std::string &detail)
{
	do {
		std::uint8_t byte=static_cast<std::uint8_t>(value&0x7f);value>>=7;
		if(value)byte|=0x80;
		if(std::fputc(byte,file)==EOF){detail=std::strerror(errno);return false;}
		++bytes;
	} while(value);
	return true;
}

bool write_header(FILE *file, const PackedMetadata &m, std::string &detail)
{
	if(!valid_metadata(m,detail))return false;
	std::uint8_t raw[128]={};std::memcpy(raw,"MVGMSID\0",8);
	put16(raw+8,2);put16(raw+10,0);put16(raw+12,128);put16(raw+14,1);
	put32(raw+0x10,m.flags);put32(raw+0x14,m.clock_num);put32(raw+0x18,m.clock_den);
	raw[0x1c]=m.sid_model;raw[0x1d]=m.timing_standard;raw[0x1e]=1;
	put32(raw+0x20,m.subtune);put64(raw+0x28,m.write_count);put64(raw+0x30,m.stream_bytes);
	put64(raw+0x38,m.stream_cycles);put64(raw+0x40,m.duration_cycles);
	put64(raw+0x48,m.loop_write_index);put64(raw+0x50,m.loop_start_cycle);
	put64(raw+0x58,m.loop_end_cycle);
	std::memcpy(raw+0x60,m.source_sha256.data(),32);
	if(std::fseek(file,0,SEEK_SET)!=0||std::fwrite(raw,1,sizeof(raw),file)!=sizeof(raw)){
		detail=std::strerror(errno);return false;
	}
	return true;
}

bool validate_packed_v2(const std::string &path, PackedMetadata &m,
		std::string &detail)
{
	struct stat st={};if(stat(path.c_str(),&st)<0){detail=std::strerror(errno);return false;}
	if(!S_ISREG(st.st_mode)||st.st_size<130||std::uint64_t(st.st_size)>kMaximumFileBytes){detail="invalid file size";return false;}
	FILE *file=std::fopen(path.c_str(),"rb");if(!file){detail=std::strerror(errno);return false;}
	std::uint8_t raw[128];bool ok=read_exact(file,raw,sizeof(raw),detail);
	if(ok&&std::memcmp(raw,"MVGMSID\0",8)!=0){detail="bad magic";ok=false;}
	if(ok&&(get16(raw+8)!=2||get16(raw+10)!=0||get16(raw+12)!=128||get16(raw+14)!=1)){
		detail="unsupported version/header/encoding";ok=false;
	}
	if(ok&&(raw[0x1e]!=1||raw[0x1f]||raw[0x24]||raw[0x25]||raw[0x26]||raw[0x27])){
		detail="unsupported SID count/reserved bytes";ok=false;
	}
	if(ok){
		m.flags=get32(raw+0x10);m.clock_num=get32(raw+0x14);m.clock_den=get32(raw+0x18);
		m.sid_model=raw[0x1c];m.timing_standard=raw[0x1d];m.subtune=get32(raw+0x20);
		m.write_count=get64(raw+0x28);m.stream_bytes=get64(raw+0x30);
		m.stream_cycles=get64(raw+0x38);m.duration_cycles=get64(raw+0x40);
		m.loop_write_index=get64(raw+0x48);m.loop_start_cycle=get64(raw+0x50);
		m.loop_end_cycle=get64(raw+0x58);
		std::memcpy(m.source_sha256.data(),raw+0x60,32);
	}
	if(ok&&!valid_metadata(m,detail))ok=false;
	if(ok&&std::uint64_t(st.st_size)!=128+m.stream_bytes){detail="file length mismatch";ok=false;}
	std::uint64_t consumed=0,cycle=0,writes=0,last_write_cycle=0,loop_first_write_cycle=0;
	bool have_write=false,saw_eof=false,loop_boundary_seen=false,loop_first_write_seen=false;
	while(ok&&consumed<m.stream_bytes){
		std::uint64_t delta=0;if(!read_uleb(file,delta,consumed,detail)){ok=false;break;}
		if(delta>std::numeric_limits<std::uint64_t>::max()-cycle){detail="absolute cycle overflow";ok=false;break;}
		cycle+=delta;int tag=std::fgetc(file);if(tag==EOF){detail="missing tag";ok=false;break;}++consumed;
		if(tag==0xff){
			saw_eof=true;
			if(consumed!=m.stream_bytes||writes!=m.write_count||cycle!=m.stream_cycles){detail="EOF/count/cycle mismatch";ok=false;}
			if(ok&&(m.flags&kLoopValid)){
				if(m.loop_write_index==m.write_count){
					const bool wait_only_boundary=!have_write ? m.loop_start_cycle==0 :
						last_write_cycle<=m.loop_start_cycle;
					if(!wait_only_boundary){detail="loop WRITE ordinal is not an event boundary";ok=false;}
					else loop_boundary_seen=true;
				}
				if(ok&&!loop_boundary_seen){detail="loop WRITE ordinal is not an event boundary";ok=false;}
				if(ok&&loop_first_write_seen&&loop_first_write_cycle==m.loop_start_cycle&&
					last_write_cycle==m.loop_end_cycle){
					detail="same-cycle WRITE across loop boundary";ok=false;
				}
			}
			break;
		}
		if(tag>0x18){detail="invalid SID register";ok=false;break;}
		if(have_write&&delta==0){detail="same-cycle WRITE";ok=false;break;}
		if(writes>=m.write_count){detail="excess WRITE count";ok=false;break;}
		if(std::fgetc(file)==EOF){detail="truncated WRITE data";ok=false;break;}++consumed;
		if((m.flags&kLoopValid)&&writes==m.loop_write_index){
			if((have_write&&last_write_cycle>m.loop_start_cycle)||cycle<m.loop_start_cycle){
				detail="loop WRITE ordinal/cycle mismatch";ok=false;break;
			}
			loop_boundary_seen=true;loop_first_write_seen=true;loop_first_write_cycle=cycle;
		}
		++writes;have_write=true;last_write_cycle=cycle;
	}
	if(ok&&(!saw_eof||consumed!=m.stream_bytes)){detail="missing EOF";ok=false;}
	if(std::fclose(file)!=0&&ok){detail=std::strerror(errno);ok=false;}
	if(ok)detail.clear();
	return ok;
}

bool canonicalize_manual_loop(const std::string &input_path,
		const std::string &output_path,std::uint64_t requested_start_cycle,
		std::uint64_t requested_end_cycle,PackedMetadata &metadata,
		std::string &detail)
{
	PackedMetadata original;if(!validate_packed_v2(input_path,original,detail))return false;
	if(original.flags&kLoopValid){detail="input already contains a loop";return false;}
	if(requested_start_cycle>=requested_end_cycle||requested_end_cycle>original.stream_cycles){
		detail="manual loop outside captured horizon";return false;
	}
	std::vector<std::uint8_t> raw;if(!read_file(input_path,raw,detail))return false;
	std::size_t pos=kHeaderBytes;std::uint64_t cycle=0;std::vector<WireWrite>writes;
	while(pos<raw.size()){
		std::uint64_t delta=0;if(!read_uleb_bytes(raw,pos,delta,detail))return false;
		if(delta>std::numeric_limits<std::uint64_t>::max()-cycle){detail="absolute cycle overflow";return false;}
		cycle+=delta;if(pos>=raw.size()){detail="missing tag";return false;}const auto tag=raw[pos++];
		if(tag==0xff)break;
		if(tag>0x18||pos>=raw.size()){detail="malformed WRITE";return false;}
		writes.push_back({cycle,tag,raw[pos++]});
	}
	std::vector<std::uint64_t>end_boundaries{original.stream_cycles};
	for(const auto &write:writes)if(write.cycle>0)end_boundaries.push_back(write.cycle);
	const auto loop_end=nearest_boundary(end_boundaries,requested_end_cycle);
	std::vector<std::uint64_t>start_boundaries{0};
	for(const auto &write:writes)if(write.cycle<loop_end)start_boundaries.push_back(write.cycle);
	const auto loop_start=nearest_boundary(start_boundaries,requested_start_cycle);
	if(loop_start>=loop_end){detail="manual loop collapses after boundary snapping";return false;}
	std::vector<WireWrite>kept;
	for(const auto &write:writes)if(write.cycle<loop_end)kept.push_back(write);
	std::uint64_t loop_index=0;while(loop_index<kept.size()&&kept[loop_index].cycle<loop_start)++loop_index;
	if(loop_index<kept.size()&&kept[loop_index].cycle!=loop_start){detail="loop start is not a WRITE boundary";return false;}
	if(loop_index==kept.size()&&!(kept.empty()?loop_start==0:kept.back().cycle==loop_start)){
		detail="wait-only loop start is not an event boundary";return false;
	}
	FILE *file=std::fopen(output_path.c_str(),"w+b");if(!file){detail=std::strerror(errno);return false;}
	std::uint8_t zero[128]={};bool ok=std::fwrite(zero,1,sizeof(zero),file)==sizeof(zero);
	std::uint64_t bytes=0,previous=0;
	for(const auto &write:kept)if(ok){
		ok=write_uleb(file,write.cycle-previous,bytes,detail)&&
			std::fputc(write.address,file)!=EOF&&std::fputc(write.data,file)!=EOF;
		if(ok){bytes+=2;previous=write.cycle;}else if(detail.empty())detail=std::strerror(errno);
	}
	if(ok)ok=write_uleb(file,loop_end-previous,bytes,detail)&&std::fputc(0xff,file)!=EOF;
	if(ok)++bytes;else if(detail.empty())detail=std::strerror(errno);
	metadata=original;metadata.flags&=~(kDurationKnown|kEndIsCaptureLimit);
	metadata.flags|=kLoopValid;metadata.duration_cycles=0;metadata.write_count=kept.size();
	metadata.stream_bytes=bytes;metadata.stream_cycles=loop_end;metadata.loop_write_index=loop_index;
	metadata.loop_start_cycle=loop_start;metadata.loop_end_cycle=loop_end;
	if(ok)ok=write_header(file,metadata,detail);
	if(ok&&(std::fflush(file)!=0||fsync(fileno(file))<0)){detail=std::strerror(errno);ok=false;}
	if(std::fclose(file)!=0&&ok){detail=std::strerror(errno);ok=false;}
	if(ok)ok=validate_packed_v2(output_path,metadata,detail);
	if(!ok)unlink(output_path.c_str());
	return ok;
}

} // namespace megavgm_sid
