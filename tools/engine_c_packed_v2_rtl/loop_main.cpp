#include "Vc2_sim_top.h"
#include "verilated.h"

#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static void require(bool value,const std::string &message) {
    if(!value) throw std::runtime_error(message);
}
static std::vector<std::uint8_t> read_file(const char *path) {
    std::ifstream file(path,std::ios::binary);require(bool(file),"cannot open input");
    return {std::istreambuf_iterator<char>(file),{}};
}
static std::uint64_t le64(const std::vector<std::uint8_t> &raw,std::size_t pos) {
    std::uint64_t value=0;for(unsigned i=0;i<8;++i)value|=std::uint64_t(raw.at(pos+i))<<(8*i);return value;
}
static std::uint32_t le32(const std::vector<std::uint8_t> &raw,std::size_t pos) {
    std::uint32_t value=0;for(unsigned i=0;i<4;++i)value|=std::uint32_t(raw.at(pos+i))<<(8*i);return value;
}
static std::uint64_t uleb(const std::vector<std::uint8_t> &raw,std::size_t &pos) {
    std::uint64_t value=0;for(unsigned group=0;group<10;++group) {
        require(pos<raw.size(),"truncated ULEB");const auto byte=raw[pos++];
        value|=std::uint64_t(byte&127)<<(group*7);if(!(byte&128))return value;
    }
    throw std::runtime_error("overlong ULEB");
}
struct Write { std::uint64_t cycle;std::uint8_t address,data; };
static std::vector<Write> source_writes(const std::vector<std::uint8_t> &raw) {
    std::vector<Write> writes;std::size_t pos=128;std::uint64_t cycle=0;
    while(pos<raw.size()) {
        cycle+=uleb(raw,pos);require(pos<raw.size(),"missing tag");const auto tag=raw[pos++];
        if(tag==255)break;require(pos<raw.size(),"missing data");writes.push_back({cycle,tag,raw[pos++]});
    }
    return writes;
}
int main(int argc,char **argv) try {
    Verilated::commandArgs(argc,argv);
    require(argc>=4,"usage: FILE loop|repeat|finite PCM");
    const auto raw=read_file(argv[1]);const std::string mode=argv[2];
    const bool repeating=mode=="repeat",looping=mode=="loop"||repeating;
	require(looping||mode=="finite","bad mode");
    const auto flags=le32(raw,0x10),clock_num=le32(raw,0x14),clock_den=le32(raw,0x18);
    const auto stream_end=le64(raw,0x38),loop_index=le64(raw,0x48);
    const auto loop_start=le64(raw,0x50),loop_end=le64(raw,0x58);
    require(bool(flags&2)==looping,"mode/LOOP_VALID mismatch");
    const auto source=source_writes(raw);std::vector<Write> expected=source;
    std::uint64_t final_cycle=stream_end;
    if(looping) {
        const auto period=loop_end-loop_start;
		const unsigned complete_traversals=repeating?5:3;
        for(unsigned traversal=1;traversal<complete_traversals;++traversal)
            for(std::size_t i=loop_index;i<source.size();++i)
                expected.push_back({source[i].cycle+traversal*period,source[i].address,source[i].data});
		final_cycle=loop_end+(complete_traversals-1)*period;
		if(repeating && loop_index<source.size())
			expected.push_back({source[loop_index].cycle+complete_traversals*period,
				source[loop_index].address,source[loop_index].data});
    }
    std::ofstream pcm(argv[3],std::ios::binary);require(bool(pcm),"cannot open PCM");
    Vc2_sim_top dut;auto edge=[&](){dut.clk=0;dut.eval();dut.clk=1;dut.eval();};
    dut.reference_reset=1;dut.loop_halt=0;dut.rd_ready=1;dut.start=0;dut.rd_valid=0;
    dut.ddr_busy=0;dut.ddr_valid=0;dut.ddr_dout=0;dut.reset=1;edge();dut.reset=0;
    std::vector<std::uint64_t> memory(1572864);
    for(std::size_t word=0;word<(raw.size()+7)/8;++word)
        for(unsigned byte=0;byte<8 && word*8+byte<raw.size();++byte)
            memory[word]|=std::uint64_t(raw[word*8+byte])<<(8*byte);
    dut.file_size=raw.size();dut.start=1;edge();dut.start=0;
    std::size_t write_index=0;std::uint64_t sys=0,ce_count=0,publications=0;
    unsigned remaining=0,delay=0,read_address=0,boundaries=0,entries=0;
    bool active=false,previous_reset=true;
    const auto sys_limit=std::uint64_t((__uint128_t(final_cycle+100)*20000000*clock_den)/clock_num)+200000;
    for(;sys<sys_limit;++sys) {
        dut.clk=0;dut.eval();
        if(dut.ddr_rd) {
            require(!remaining && dut.ddr_addr>=0x6000000 && dut.ddr_addr<0x6180000,"DDR request");
            remaining=dut.ddr_burst;read_address=dut.ddr_addr-0x6000000;delay=3;
        }
        const bool host_request=dut.rd_req&&dut.rd_ready;const auto host_address=dut.rd_addr;
        if(dut.reg_write) {
            require(write_index<expected.size(),"extra WRITE");const auto &want=expected[write_index++];
            const auto cycle=dut.busy?dut.native_cycle+1:0;
            require(cycle==want.cycle && dut.reg_addr==want.address && dut.reg_data==want.data,
                    "WRITE sequence/timing mismatch at "+std::to_string(write_index-1));
        }
        if(dut.ce_sid)++ce_count;
        if(dut.raw_valid) {
            const std::uint32_t bits=std::uint32_t(std::int32_t(dut.raw_audio<<14)>>14);
            const char encoded[4]={char(bits),char(bits>>8),char(bits>>16),char(bits>>24)};
            pcm.write(encoded,4);++publications;
        }
        if(dut.loop_entry_pulse)++entries;
        if(dut.loop_boundary_pulse) {
            ++boundaries;require(!dut.sid_reset,"SID reset at loop boundary");
            require(dut.loop_count==boundaries,"loop count mismatch");
			if(looping && !repeating && boundaries==2)dut.loop_halt=1;
        }
        require(!(active && dut.sid_reset),"SID reset after accepted session");
        previous_reset=dut.sid_reset;
        dut.clk=1;dut.eval();dut.ddr_valid=0;dut.rd_valid=0;
        if(!active && (dut.busy||dut.done)){active=true;dut.reference_reset=0;}
        if(remaining) {
            if(delay)--delay;else {dut.ddr_dout=memory.at(read_address++);dut.ddr_valid=1;--remaining;}
        }
        dut.ddr_busy=sys%17==0;
        if(host_request) {require(host_address<raw.size(),"host read range");dut.rd_data=raw[host_address];dut.rd_valid=1;}
        require(!dut.fatal,"unexpected fatal "+std::to_string(dut.error_code)+
			" sys="+std::to_string(sys)+" native="+std::to_string(dut.native_cycle)+
			" writes="+std::to_string(write_index)+" boundaries="+std::to_string(boundaries));
		if(looping && boundaries==(repeating?5u:3u))break;
        if(!looping && dut.done)break;
    }
    require(sys<sys_limit,"simulation timeout");require(write_index==expected.size(),"missing WRITE");
    require(dut.native_cycle==final_cycle,"final native cycle mismatch");
	if(looping)require(boundaries==(repeating?5u:3u) && dut.loop_count==boundaries && entries==1 && !dut.done,
		"loop publication contract");
    else require(!boundaries && !dut.loop_valid && dut.done,"finite publication contract");
    const auto expected_ticks=std::uint64_t((__uint128_t(dut.native_cycle)*44100*clock_den)/clock_num);
    require(dut.transport_ticks==expected_ticks,"transport tick rational drift");
    std::cout<<(looping?"LOOP":"FINITE")<<" writes="<<write_index<<" cycles="<<dut.native_cycle
             <<" boundaries="<<boundaries<<" ticks="<<dut.transport_ticks
             <<" publications="<<publications<<"\n";
    return 0;
} catch(const std::exception &error) {
    std::cerr<<"FAIL "<<error.what()<<"\n";return 1;
}
