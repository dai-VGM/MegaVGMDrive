#include "Vdecoder_top.h"
#include "verilated.h"
#include <fstream>
#include <iostream>
#include <vector>
#include <stdexcept>
#include <string>
#include <cstdint>
static void check(bool b,const std::string& s){if(!b)throw std::runtime_error(s);}
static std::vector<uint8_t> read(const char* p){std::ifstream f(p,std::ios::binary);check(bool(f),p);return {std::istreambuf_iterator<char>(f),{}};}
static uint64_t le(const std::vector<uint8_t>& b,size_t p,int n){uint64_t v=0;for(int i=0;i<n;i++)v|=uint64_t(b.at(p+i))<<(8*i);return v;}
int main(int argc,char**argv)try{
    Verilated::commandArgs(argc,argv);check(argc>=4,"FILE EXPECTED_TRACE good|reject|short [latency]");
    auto bytes=read(argv[1]);auto expected=read(argv[2]);std::string mode=argv[3];
    bool good=mode=="good"||mode=="loop";unsigned latency=argc>4?std::stoul(argv[4]):64;
    Vdecoder_top d;d.reset=1;d.clk=0;d.eval();d.clk=1;d.eval();d.reset=0;
    d.file_size=bytes.size();d.start=1;d.halt=0;d.d_busy=0;d.d_valid=0;d.mem_req=0;d.mem_addr=0;
    size_t record=0;unsigned remaining=0,address=0,delay=0,max_word=0;bool waiting=false;
    uint64_t limit=bytes.size()*80ULL+10000;
    for(uint64_t sys=0;sys<limit;sys++){
        d.clk=0;d.eval();
        if(d.d_rd){check(!d.d_busy && remaining==0,"DDR overlapping / busy request");
            check(d.d_addr>=0x6000000 && d.d_addr<0x6100000,"raw DDR address");
            remaining=d.d_burst;address=(d.d_addr-0x6000000)*8;delay=latency;
        }
        if(d.mem_valid){
            check(good,"record published before rejected preflight");check((record+1)*10<=expected.size(),"extra record");
            uint64_t cycle=(uint64_t(d.mem_data[0])>>13)|(uint64_t(d.mem_data[1])<<19)|(uint64_t(d.mem_data[2]&0x1fff)<<51);
            unsigned addr=(d.mem_data[0]>>8)&31,data=d.mem_data[0]&255,eof=(d.mem_data[2]>>13)&1;
            unsigned boundary=(d.mem_data[2]>>14)&1;
            uint64_t want=le(expected,record*10,8);unsigned wa=expected[record*10+8],wd=expected[record*10+9];
            unsigned actual_tag=boundary?254:(eof?255:addr);
            check(cycle==want && actual_tag==wa && data==wd,
                "first difference record="+std::to_string(record)+" cycle="+std::to_string(cycle)+" expected="+std::to_string(want)+
                " addr="+std::to_string(addr)+" data="+std::to_string(data));
            record++;waiting=false;
			if(mode=="loop" && record*10==expected.size()) {
				std::cout<<"LOOP TRACE EXACT records="<<record<<" SYS="<<sys<<" delay="<<latency<<"\n";return 0;
			}
            if(eof && !boundary){
                check(record*10==expected.size(),"early EOF");
                check(d.session_model==(bytes[28]==2)&&d.session_timing==bytes[29]&&
                      d.session_clock_num==le(bytes,20,4)&&d.session_clock_den==le(bytes,24,4),"metadata mismatch");
                if(bytes.size()==8388608)check(max_word==0x60fffff,"final 8 MiB DDR word was not read");
                std::cout<<"TRACE EXACT records="<<record<<" EOF="<<cycle<<" SYS="<<sys<<" delay="<<latency
                         <<" MAX_DDR_WORD=0x"<<std::hex<<max_word<<std::dec<<"\n";return 0;
            }
        }
        // Scheduler-style single outstanding request, no faster than one SID
        // cycle. Deliberate starvation is tested with the real scheduler.
        d.mem_req=d.loaded && !waiting && (sys%20==0);d.mem_addr=record&0x3ffff;
        if(d.mem_req)waiting=true;
        d.clk=1;d.eval();d.start=0;d.d_valid=0;
        if(remaining){
            if(delay)--delay;
            else if(mode!="short" || remaining!=1){
                const unsigned word_address=0x6000000+address/8;check(word_address<0x6100000,"adjacent DDR region read");
                if(word_address>max_word)max_word=word_address;
                uint64_t word=0;for(unsigned k=0;k<8;k++)if(address+k<bytes.size())word|=uint64_t(bytes[address+k])<<(8*k);
                d.d_dout=word;d.d_valid=1;address+=8;remaining--;
                // Alternating beat stalls exercise FIFO push/pop coincidences.
                if(sys%7==0)delay=2;
            }
        }
        d.d_busy=sys%17==0;
        if(d.fatal){check(!good && record==0 && !d.loaded,"unexpected fatal/side effects code="+std::to_string(d.error_code));
            std::cout<<"REJECT code="<<unsigned(d.error_code)<<" SYS="<<sys<<"\n";return 0;}
    }
    throw std::runtime_error("timeout records="+std::to_string(record)+" loaded="+std::to_string(d.loaded));
}catch(const std::exception&e){std::cerr<<"FAIL "<<e.what()<<"\n";return 1;}
