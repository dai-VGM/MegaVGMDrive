#include "profile.h"
#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>
using namespace megavgm_profile;
static void put(std::vector<unsigned char>& b,unsigned p,std::uint32_t v){for(unsigned i=0;i<4;++i)b[p+i]=(v>>(i*8))&255;}
static std::vector<unsigned char> track(std::uint32_t clock,bool konami,bool fm=true){
 std::vector<unsigned char>b(192);b[0]='V';b[1]='g';b[2]='m';b[3]=' ';put(b,8,0x161);put(b,0x34,192-0x34);put(b,0x30,clock);
 if(konami){put(b,0xac,3579545);const unsigned char block[]={0x67,0x66,0x8e,8,0,0,0,0,0x10,0,0,0,0,0,0};b.insert(b.end(),block,block+15);}
 if(fm){const unsigned char write[]={0x54,0x20,0xc0};b.insert(b.end(),write,write+3);}else if(!konami){put(b,0x0c,3579545);b.push_back(0x50);b.push_back(0x9f);}
 b.push_back(0x70);b.push_back(0x66);put(b,4,b.size()-4);return b;
}
int main(){unsigned checks=0;
 for(auto hz:{0u,1u,44100u,3579545u,4000000u,4026987u,8000000u,0x403d0900u,0x803d0900u,0xffffffffu}){
  bool valid=hz==3579545||hz==4000000;
#if defined(MEGAVGM_HOST_A_YM2151_4026987) && MEGAVGM_HOST_A_YM2151_4026987
  valid=valid||hz==4026987;
#endif
  assert((classify_bytes(track(hz,false)).profile==Profile::A)==valid);++checks;
#if defined(MEGAVGM_HOST_K053260_EMPTY_ROM) && MEGAVGM_HOST_K053260_EMPTY_ROM
  assert((classify_bytes(track(hz,true)).profile==Profile::A)==valid);++checks;
#endif
 }
 assert(classify_bytes(track(0,false,false)).profile==Profile::A);++checks;
#if defined(MEGAVGM_HOST_K053260_EMPTY_ROM) && MEGAVGM_HOST_K053260_EMPTY_ROM
 assert(classify_bytes(track(0,true,false)).profile==Profile::A);++checks;
#endif
 std::cout<<"A_YM_CLOCK_CAPABILITY_PASS checks="<<checks<<" no fallback; independent native profiles\n";
}
