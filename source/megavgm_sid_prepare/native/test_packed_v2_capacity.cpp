#include "packed_v2.h"

#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <unistd.h>

using namespace megavgm_sid;

namespace {

std::string temporary_path()
{
	char name[]="/tmp/megavgm-packed-capacity-XXXXXX";
	const int fd=mkstemp(name);assert(fd>=0);assert(close(fd)==0);return name;
}

void put_dense(FILE *file,std::uint64_t count)
{
	std::uint8_t block[3*4096];
	for(unsigned i=0;i<4096;++i){block[3*i]=1;block[3*i+1]=0;block[3*i+2]=0;}
	while(count){const auto n=count>4096?4096:static_cast<unsigned>(count);
		assert(std::fwrite(block,3,n,file)==n);count-=n;}
}

void make_valid(const std::string &path,std::uint64_t total)
{
	assert(total>=130&&total<=kMaximumFileBytes);
	const auto payload=total-130;
	const std::uint64_t count=payload/3;
	const unsigned extra=payload%3;
	const std::uint64_t first_delta=extra==0?1:extra==1?128:16384;
	FILE *file=std::fopen(path.c_str(),"w+b");assert(file);
	std::uint8_t zero[128]={};assert(std::fwrite(zero,1,sizeof(zero),file)==sizeof(zero));
	std::uint64_t bytes=0;std::string detail;
	assert(write_uleb(file,first_delta,bytes,detail));
	assert(std::fputc(0,file)!=EOF&&std::fputc(0,file)!=EOF);bytes+=2;
	put_dense(file,count-1);bytes+=(count-1)*3;
	assert(write_uleb(file,0,bytes,detail));assert(std::fputc(0xff,file)!=EOF);++bytes;
	assert(bytes==total-kHeaderBytes);
	PackedMetadata m;m.flags=kEndIsCaptureLimit;m.clock_num=985248;m.sid_model=1;
	m.timing_standard=1;m.subtune=1;m.write_count=count;m.stream_bytes=bytes;
	m.stream_cycles=first_delta+count-1;
	assert(write_header(file,m,detail));assert(std::fclose(file)==0);
}

bool validates(const std::string &path)
{
	PackedMetadata m;std::string detail;return validate_packed_v2(path,m,detail);
}

std::string make_loop(std::uint64_t loop_index,std::uint64_t loop_start,
		bool include_second_write=true,bool collision=false)
{
	const auto path=temporary_path();FILE *file=std::fopen(path.c_str(),"w+b");assert(file);
	std::uint8_t zero[128]={};assert(std::fwrite(zero,1,sizeof(zero),file)==sizeof(zero));
	std::uint64_t bytes=0;std::string detail;
	assert(write_uleb(file,0,bytes,detail));assert(std::fputc(0,file)!=EOF&&std::fputc(1,file)!=EOF);bytes+=2;
	std::uint64_t count=1,previous=0;
	if(include_second_write){assert(write_uleb(file,collision?10:5,bytes,detail));assert(std::fputc(1,file)!=EOF&&std::fputc(2,file)!=EOF);bytes+=2;++count;previous=collision?10:5;}
	const std::uint64_t end=10;assert(write_uleb(file,end-previous,bytes,detail));assert(std::fputc(0xff,file)!=EOF);++bytes;
	PackedMetadata m;m.flags=kLoopValid;m.clock_num=985248;m.sid_model=1;m.timing_standard=1;m.subtune=1;
	m.write_count=count;m.stream_bytes=bytes;m.stream_cycles=end;m.loop_write_index=loop_index;
	m.loop_start_cycle=loop_start;m.loop_end_cycle=end;
	assert(write_header(file,m,detail));assert(std::fclose(file)==0);return path;
}

void patch64(const std::string &path,long offset,std::uint64_t value)
{
	FILE *file=std::fopen(path.c_str(),"r+b");assert(file);assert(std::fseek(file,offset,SEEK_SET)==0);
	for(unsigned i=0;i<8;++i)assert(std::fputc((value>>(8*i))&255,file)!=EOF);
	assert(std::fclose(file)==0);
}

} // namespace

int main()
{
	assert(kMaximumFileBytes==8388608);
	assert(capacity_decision(kMaximumStreamBytes-14,1,false)==CapacityDecision::Write);
	assert(capacity_decision(kMaximumStreamBytes-13,1,false)==CapacityDecision::Reject);
	assert(capacity_decision(kMaximumStreamBytes-13,1,true)==CapacityDecision::CaptureLimit);
	assert(capacity_decision(kMaximumStreamBytes-15,128,false)==CapacityDecision::Write);
	assert(capacity_decision(kMaximumStreamBytes-14,128,false)==CapacityDecision::Reject);
	assert(capacity_decision(UINT64_MAX,UINT64_MAX,false)==CapacityDecision::Reject);

	for(const auto size:{4194304ull,kMaximumFileBytes-1,kMaximumFileBytes}){
		const auto path=temporary_path();make_valid(path,size);assert(validates(path));unlink(path.c_str());
	}
	const auto oversized=temporary_path();make_valid(oversized,kMaximumFileBytes);
	FILE *append=std::fopen(oversized.c_str(),"ab");assert(append);assert(std::fputc(0,append)!=EOF);assert(std::fclose(append)==0);
	assert(!validates(oversized));unlink(oversized.c_str());
	for(const auto &path:{make_loop(1,5),make_loop(0,0),make_loop(1,0,false)}){
		assert(validates(path));unlink(path.c_str());
	}
	auto bad_index=make_loop(1,5);patch64(bad_index,0x48,3);
	auto bad_start=make_loop(1,5);patch64(bad_start,0x50,6);
	for(const auto &path:{bad_index,bad_start,make_loop(0,0,true,true)}){
		assert(!validates(path));unlink(path.c_str());
	}
	std::puts("Packed v2 native 8 MiB capacity tests PASS");
}
