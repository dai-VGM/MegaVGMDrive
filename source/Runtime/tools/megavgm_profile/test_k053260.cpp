#include "profile.h"
#include <cassert>
#include <iostream>
#include <vector>
using namespace megavgm_profile;using Bytes=std::vector<unsigned char>;
static unsigned checks=0;
void put(Bytes& b,unsigned p,unsigned v){for(unsigned i=0;i<4;++i)b[p+i]=(v>>(8*i))&255;}
Bytes block(unsigned start=0,unsigned total=4096,unsigned count=64){Bytes b(15+count,0);b[0]=0x67;b[1]=0x66;b[2]=0x8e;put(b,3,count+8);put(b,7,total);put(b,11,start);return b;}
void add(Bytes& a,const Bytes& b){a.insert(a.end(),b.begin(),b.end());}
Bytes image(Bytes s){Bytes b(192,0);b[0]='V';b[1]='g';b[2]='m';b[3]=' ';put(b,8,0x161);put(b,0x34,192-0x34);put(b,0xac,3579545);put(b,0x30,3579545);put(b,0x18,44100);add(b,s);put(b,4,b.size()-4);return b;}
Bytes valid(){auto s=block();add(s,{0x54,0x20,0xc0,0xba,0x2f,2,0xba,0x28,1,0x61,1,0,0x66});return image(s);}
void good(const Bytes& b,const char* chips){auto before=b;auto v=classify_bytes(b);++checks;if(v.profile!=Profile::A||v.sound_chips!=chips){std::cerr<<name(v.profile)<<" "<<v.detail<<" "<<v.sound_chips<<"\n";std::abort();}assert(before==b);}
void bad(const Bytes& b){auto v=classify_bytes(b);++checks;assert(v.profile==Profile::Unsupported||v.profile==Profile::Error||v.profile==Profile::Ambiguous);}
int main(int argc,char**argv){
 if(argc>1){for(int i=1;i<argc;++i){const std::string path=argv[i];auto v=classify_file(path,path.substr(0,path.find_last_of('/')));std::cout<<name(v.profile)<<'\t'<<v.sound_chips<<'\t'<<v.commands<<'\t'<<v.detail<<'\t'<<argv[i]<<'\n';}return 0;}
#if !defined(MEGAVGM_HOST_K053260) || !MEGAVGM_HOST_K053260
 bad(valid());auto s=block();add(s,{0x54,0,0,0x66});bad(image(s));std::cout<<"K053260_DEFAULT_OFF_PASS "<<checks<<'\n';return 0;
#else
 good(valid(),"YM2151,K053260");auto x=valid();put(x,0x30,4000000);good(x,"YM2151,K053260");
 auto s=block();add(s,{0xba,0x2f,2,0xba,0x28,1,0x66});good(image(s),"K053260");
 for(unsigned hz:{0u,3579546u,0x40369e99u,0x80369e99u}){x=valid();put(x,0xac,hz);bad(x);}
 for(unsigned hz:{0u,2304u,0x403d0900u}){x=valid();put(x,0x30,hz);bad(x);}
 x=valid();put(x,8,0x150);bad(x);x=valid();put(x,0xac,1);good(x,"YM2151,K053260");
 for(unsigned addr:{64u,128u,255u}){s=block();add(s,{0xba,static_cast<unsigned char>(addr),0,0x66});bad(image(s));}
 s=block();add(s,{0xba,0,0x66});bad(image(s)); // missing END, not a fabricated terminator
 s=block();add(s,{0xba,0});bad(image(s)); // actually truncated WRITE
 bad(image({0xba,0,0,0x66}));s=block();add(s,{0x54,0,0,0x66});
#if defined(MEGAVGM_HOST_K053260_EMPTY_ROM) && MEGAVGM_HOST_K053260_EMPTY_ROM
 good(image(s),"YM2151");
#else
 bad(image(s));
#endif
 for(auto b:{block(0,0),block(4096,4096),block(0,0x400001),block(0xfffffff0u,4096)}){add(b,{0xba,0,0,0x66});bad(image(b));}
 s={0xba,0x28,1};add(s,block());add(s,{0x66});bad(image(s));
 s=block();add(s,block(128,8192));add(s,{0xba,0,0,0x66});bad(image(s));
 s=block();add(s,block());add(s,{0xba,0x28,1,0x66});good(image(s),"K053260"); // immutable overlay with executable resident plan
 s.clear();for(unsigned i=0;i<33;++i)add(s,block());add(s,{0xba,0,0,0x66});bad(image(s));
 for(auto cmd:{Bytes{0x58,0,0},Bytes{0xb9,0,0},Bytes{0xd4,0,0,0}}){s=block();add(s,{0xba,0,0});add(s,cmd);add(s,{0x66});bad(image(s));}
 x=valid();put(x,0x1c,192-0x1c);good(x,"YM2151,K053260");put(x,0x1c,193-0x1c);bad(x);
 for(unsigned i=0;i<5;++i){good(valid(),"YM2151,K053260");x=valid();put(x,0xac,0);bad(x);}
 s=block();add(s,{0xba,0,0,0x66});
#if defined(MEGAVGM_HOST_K053260_EMPTY_ROM) && MEGAVGM_HOST_K053260_EMPTY_ROM
 good(image(s),"K053260");
 s=block(0,4096,0);add(s,{0xba,0,0,0x66});good(image(s),"K053260");
 s=block(0,4096,0);add(s,{0xba,0x28,1,0x66});bad(image(s)); // declaration is not data
#else
 bad(image(s));
 s=block(0,4096,0);add(s,{0xba,0,0,0x66});bad(image(s));
#endif
 std::cout<<"K053260_ADMISSION_PASS "<<checks<<'\n';
#endif
}
