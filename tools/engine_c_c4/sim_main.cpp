#include "Vc2_sim_top.h"
#include "verilated.h"
#include <fstream>
#include <vector>
#include <iostream>
#include <stdexcept>
#include <algorithm>
#include <cstdint>

static void require(bool b, const char* msg) { if(!b) throw std::runtime_error(msg); }
static uint64_t le64(const std::vector<uint8_t>& v, size_t i) {
    uint64_t n=0; for(int j=0;j<8;j++) n|=uint64_t(v.at(i+j))<<(j*8); return n;
}
static uint32_t le32(const std::vector<uint8_t>& v,size_t i) {
    uint32_t n=0;for(int j=0;j<4;j++) n|=uint32_t(v.at(i+j))<<(8*j);return n;
}
static void put32(std::vector<uint8_t>& v,size_t i,uint32_t n) {
    for(int j=0;j<4;j++) v.at(i+j)=n>>(8*j);
}
struct Write { uint64_t cycle; uint8_t addr,data; };
static std::vector<uint8_t> readfile(const char* path) {
    std::ifstream f(path,std::ios::binary); require(bool(f),"input open");
    return {std::istreambuf_iterator<char>(f),{}};
}
int main(int argc,char** argv) try {
    Verilated::commandArgs(argc,argv);
    require(argc>=3,"usage sim FILE good|reject [pcm output]");
    auto bytes=readfile(argv[1]); std::string mode=argv[2];
    bool starve=mode=="starve",corrupt=mode=="corrupt";
    bool fault=starve||corrupt,good=mode!="reject";
    bool sequence=mode=="sequence";
    auto original=bytes;
    Vc2_sim_top d;
    auto edge=[&](){ d.clk=0; d.eval(); d.clk=1; d.eval(); };
    d.reference_reset=1; d.rd_ready=1; d.start=0; d.rd_valid=0;
    d.ddr_busy=0; d.ddr_valid=0; d.ddr_dout=0;
    std::vector<uint64_t> memory(524288,0xabcdef0123456789ULL);
    std::vector<Write> expected; uint64_t expected_cycles=0;
    if(good) for(size_t p=128;p<bytes.size();p+=16) {
        if(bytes[p]==0) expected_cycles+=le64(bytes,p+8);
        if(bytes[p]==1) expected.push_back({expected_cycles,bytes[p+1],bytes[p+2]});
    }
    std::vector<int32_t> first_audio;
    std::ofstream pcm; if(argc>3) pcm.open(argv[3],std::ios::binary);
    // First run dirties all active filter/voice pipelines. Second identical run
    // compares every native publication against a reference held in reset before it.
    for(int session=0;session<(sequence?8:good&&!fault?2:1);session++) {
        bytes=original;
        if(sequence) {
            static const unsigned models[]={1,2,2,1,1,2,2,1};
            static const unsigned timings[]={1,2,1,2,1,1,2,2};
            bytes[28]=models[session];bytes[29]=timings[session];
            put32(bytes,20,bytes[29]==1?985248:1022727);put32(bytes,24,1);
        }
        uint32_t num=good?le32(bytes,20):985248,den=good?le32(bytes,24):1;
        unsigned model=good?bytes[28]:1,timing=good?bytes[29]:1;
        d.reset=1; edge(); // exactly one SYS edge; not a sample-count warmup
        d.reset=0; d.reference_reset=session==0; d.file_size=bytes.size();
        d.start=1; edge(); d.start=0;
        uint64_t cycles=0, ce_count=0, launch_at=0, pulses=0, changes=0;
        uint64_t last_ce=0, sample_epoch=0; bool active=false, previous_valid=false;
        size_t wi=0; int32_t previous_audio=0; uint32_t oldosc=0, audio_phase=0;
        uint64_t limit=(good?uint64_t(__uint128_t(expected_cycles)*20000000*den/num):0)+bytes.size()*8+1000000;
        unsigned remaining=0, delay=0, read_address=0;
        for(;cycles<limit;cycles++) {
            d.clk=0; d.eval();
            if(d.ddr_we || d.ddr_rd) {
                require(d.ddr_addr>=0x6100000 && d.ddr_addr<0x6180000,"DDR descriptor address range");
                unsigned a=d.ddr_addr-0x6100000;
                require(!d.ddr_busy,"DDR request while busy");
                if(d.ddr_we) { require(d.ddr_be==255,"descriptor byte enable"); memory.at(a)=d.ddr_din; }
                else {
                    require(!remaining,"overlapping DDR burst");
                    remaining=d.ddr_burst; read_address=a; delay=3;
                }
            }
            bool request=d.rd_req && d.rd_ready;
            uint32_t address=d.rd_addr;
            bool ce=d.ce_sid, wr=d.reg_write, rawv=d.raw_valid;
            uint32_t prev_freq=d.frequency, prev_osc=d.oscillator;
            int32_t a=int32_t(d.raw_audio<<14)>>14;
            if(rawv) {
                require(!previous_valid,"sample publication must be pulse");
                require(last_ce>0 && cycles-last_ce==17,"consumer edge must be CE + 17 SYS clocks (commit +16)");
                require(sample_epoch!=ce_count,"one publication per CE"); sample_epoch=ce_count;
                if(session==0) first_audio.push_back(a);
                else {
                    require(d.reference_valid && d.raw_audio==d.reference_audio,"stale audio vs clean reference");
                    if(!sequence) require(pulses<first_audio.size() && a==first_audio[pulses],"repeat-session deterministic audio");
                }
                if(a!=previous_audio) changes++;
                previous_audio=a; pulses++;
            }
            previous_valid=rawv;
            if(wr) {
                require(wi<expected.size(),"extra WRITE"); auto w=expected[wi++];
                uint64_t tick=d.busy ? d.native_cycle+1 : 0;
                require((ce || !active) && tick==w.cycle,"WRITE cycle/phase mismatch");
                require(d.reg_addr==w.addr && d.reg_data==w.data,"WRITE order/data mismatch");
            }
            if(ce) { ce_count++; last_ce=cycles; }
            d.clk=1; d.eval();
            if(!active && (d.busy || d.done)) { active=true; launch_at=cycles; }
            if(active) {
                require(ce_count==uint64_t(__uint128_t(cycles-launch_at)*num/(__uint128_t(20000000)*den)),"fractional CE cumulative count");
                require(d.observed_num==num && d.observed_den==den &&
                        d.observed_model==(model==2) && d.sid_model==(model==2) && d.observed_timing==timing,"session config/latch mismatch");
                require(!d.rd_req,"file reread during playback");
                if(sequence) {
                    // Mutate the upload source and issue spurious start; accepted
                    // configuration MUST stay immutable until the next reset/load.
                    bytes[28]=0;bytes[29]=0;put32(bytes,20,1);put32(bytes,24,0);
                    d.start=(cycles%127==0);
                }
            }
            if(ce && prev_freq && !d.fatal) {
                require(d.oscillator==((prev_osc+prev_freq)&0xffffff),"SID oscillator/register update phase");
            }
            oldosc=d.oscillator;
            if(pcm && session==0 && active) {
                audio_phase+=44100;
                if(audio_phase>=20000000) {
                    audio_phase-=20000000; int16_t s=(int32_t(d.raw_audio<<14)>>14)>>2;
                    char b[2]={char(s&255),char((s>>8)&255)}; pcm.write(b,2);
                }
            }
            d.ddr_valid=0;
            if(remaining) {
                if(delay) --delay;
                else if(!starve || !active) {
                    d.ddr_valid=1; d.ddr_dout=memory.at(read_address++);
                    if(corrupt && active && (read_address%2==0)) d.ddr_dout|=1ULL<<63;
                    --remaining;
                }
            }
            d.ddr_busy=(cycles%17==0);
            d.rd_valid=request;
            if(request) { require(address<bytes.size(),"out-of-range file request"); d.rd_data=bytes[address]; }
            if(d.fatal) {
                if(fault) {
                    require(active && d.audio==0,"storage fault not silent");
                    require(d.error_code==(starve?0x80:0x81),"wrong storage fault code");
                    std::cout<<"FAULT "<<mode<<" code="<<int(d.error_code)<<" native_cycle="<<d.native_cycle<<" writes="<<wi<<"\n";
                    return 0;
                }
                require(!good,"unexpected fatal"); require(d.writes==0 && !d.ce_sid && d.audio==0,"reject side effect");
                require(!d.loaded && d.observed_num==0 && d.observed_den==0,"rejected configuration was committed");
                std::cout<<"REJECT code="<<int(d.error_code)<<" cycles="<<cycles<<"\n"; return 0;
            }
            if(d.done) {
                require(!fault,"storage fault not detected");
                require(good,"accepted malformed file"); require(wi==expected.size(),"missing WRITE");
                require(d.native_cycle==expected_cycles,"EOF cycle mismatch");
                if(argc>3) require(changes>100 && pulses>100,"no qualified tone audio");
                // Clear only the reference after every completed session, while
                // DUT's old SID pipelines remain dirty until its next load.
                d.reference_reset=1;
                for(int i=0;i<1000;i++) { edge(); require(!d.reg_write,"WRITE after parser EOF"); }
                std::cout<<"SESSION "<<session<<" writes="<<wi<<" final_cycle="<<d.native_cycle
                         <<" model="<<model<<" timing="<<timing<<" clock="<<num<<"/"<<den
                         <<" ce="<<ce_count<<" publications="<<pulses<<" changes="<<changes<<"\n";
                break;
            }
        }
        require(cycles<limit,"simulation timeout");
        d.start=0;
    }
    return 0;
} catch(const std::exception& e) { std::cerr<<"FAIL: "<<e.what()<<"\n"; return 1; }
