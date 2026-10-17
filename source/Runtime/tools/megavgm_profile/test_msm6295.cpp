#include "profile.h"
#include <cassert>
#include <iostream>
#include <vector>
using namespace megavgm_profile;
using Bytes=std::vector<unsigned char>;
static unsigned cases=0;
void put(Bytes &b,unsigned p,unsigned v){for(unsigned i=0;i<4;++i)b[p+i]=(v>>(8*i))&255;}
Bytes block(unsigned start=0,unsigned total=4096,unsigned count=2048,unsigned type=0x8b){
 Bytes b(15+count,0);b[0]=0x67;b[1]=0x66;b[2]=type;put(b,3,8+count);put(b,7,total);put(b,11,start);return b;
}
void add(Bytes &a,const Bytes &b){a.insert(a.end(),b.begin(),b.end());}
Bytes image(Bytes stream,unsigned msm_clock=1000000){Bytes b(192,0);b[0]='V';b[1]='g';b[2]='m';b[3]=' ';put(b,8,0x161);put(b,0x34,192-0x34);put(b,0x30,4000000);put(b,0x98,msm_clock);put(b,0xa8,21390);put(b,0x18,44100);add(b,stream);put(b,4,b.size()-4);return b;}
Bytes valid(){Bytes s=block();add(s,{0x54,0x20,0xc0,0xb8,0,0x80,0xb8,0,0x10,0x61,0xdf,2,0x66});return image(s);}
void check(const Bytes &b,Profile expected,const char *name,const char *chips=nullptr){
 auto v=classify_bytes(b);++cases;if(v.profile!=expected || (chips&&v.sound_chips!=chips)){std::cerr<<"MSM_TEST_FAIL "<<name<<" "<<megavgm_profile::name(v.profile)<<" "<<v.detail<<" "<<v.sound_chips<<"\n";std::abort();}
}
void reject(const Bytes &b,const char *n){auto v=classify_bytes(b);++cases;if(v.profile!=Profile::Error&&v.profile!=Profile::Unsupported&&v.profile!=Profile::Ambiguous){std::cerr<<"MSM_TEST_FAIL accepted invalid "<<n<<"\n";std::abort();}}
int main(int argc,char **argv){
 if(argc>1){for(int i=1;i<argc;++i){const std::string path=argv[i];auto v=classify_file(path,path.substr(0,path.find_last_of('/')));std::cout<<name(v.profile)<<"\t"<<v.sound_chips<<"\t"<<v.commands<<"\t"<<v.timing.duration_ms<<"\t"<<argv[i]<<"\n";}return 0;}
#if !defined(MEGAVGM_HOST_MSM6295) || !MEGAVGM_HOST_MSM6295
 reject(valid(),"default off");check(image({0xb8,0,0,0x66}),Profile::Unsupported,"B8 default off");
 auto s=block();add(s,{0x54,0x20,0xc0,0x66});check(image(s),Profile::Unsupported,"8B default off");
 std::cout<<"PASS_MSM_DEFAULT_OFF cases="<<cases<<"\n";return 0;
#else
 auto b=valid();check(b,Profile::D,"valid", "YM2151,MSM6295");auto before=b;auto v=classify_bytes(b);assert(b==before&&v.timing.duration_ms==1000&&v.commands==6);
 auto x=b;put(x,0x98,0x800f4240);check(x,Profile::D,"header pin7", "YM2151,MSM6295");
 Bytes s=block();add(s,{0xb8,0,0x80,0xb8,0,0x10,0x66});check(image(s),Profile::D,"MSM only", "MSM6295");
 s=block();add(s,block(0,4096,2048,0x8d));add(s,{0x54,0x20,0xc0,0xd4,0,0,0,0xb8,0,0x80,0xb8,0,0x10,0x66});check(image(s),Profile::D,"all3", "YM2151,C140,MSM6295");
 s=block(4096,4096,0);add(s,{0x54,0x20,0xc0,0x66});check(image(s),Profile::D,"empty declaration isn't chip usage", "YM2151");
 s={0x61,0,0};add(s,block());add(s,{0xb8,0,0,0x66});check(image(s),Profile::D,"zero wait before ROM", "MSM6295");
 s=block();add(s,{0xb8,8,0x40,0xb8,9,0x42,0xb8,10,0x0f,0xb8,11,0,0xb8,12,1,0xb8,15,1,0xb8,0,0,0x66});check(image(s),Profile::D,"supported registers", "MSM6295");
 s.clear();for(unsigned i=0;i<16;++i)add(s,block(i,4096,1));add(s,{0xb8,0,0,0x66});check(image(s),Profile::D,"16 descriptors");
 for(unsigned address:{1u,7u,13u,14u,16u,127u,128u,255u}){s=block();add(s,{0xb8,static_cast<unsigned char>(address),0,0x66});reject(image(s),"register or instance");}
 for(unsigned address:{12u,15u}){s=block();add(s,{0xb8,static_cast<unsigned char>(address),2,0x66});reject(image(s),"pin/bank invalid");}
 s=block();add(s,{0xb8,11,0,0x66});x=image(s);put(x,0x98,0x80000000);reject(x,"zero clock update");
 s=block();add(s,{0xb8,11,1,0x66});reject(image(s),"large clock update");
 for(unsigned c:{0u,4000001u,0x400f4240u}){x=b;put(x,0x98,c);reject(x,"header clock");}
 for(unsigned c:{0u,0x40000001u,0x80000001u}){x=b;put(x,0x30,c);reject(x,"YM clock");}
 x=b;put(x,8,0x150);reject(x,"old version");x=b;x[0x96]=2;reject(x,"C140 type blocks current D");
 reject(image({0xb8}),"short0");reject(image({0xb8,0}),"short1");
 for(unsigned n=0;n<8;++n){s={0x67,0x66,0x8b,static_cast<unsigned char>(n),0,0,0};s.resize(7+n);add(s,{0x66});reject(image(s),"short metadata");}
 for(auto q:std::vector<Bytes>{block(0,0),block(0,0x100001),block(4097,4096,0),block(4095,4096,2),block(0xfffffff0u,4096,32)}){add(q,{0x66});reject(image(q),"ROM range widened");}
 s=block();add(s,block(1,4096,1));add(s,{0x66});reject(image(s),"overlap");
 s=block();add(s,block(3000,8192,1));add(s,{0x66});reject(image(s),"inconsistent declaration");
 s.clear();for(unsigned i=0;i<17;++i)add(s,block(i,4096,1));add(s,{0x66});reject(image(s),"17 descriptors");
 s={0x54,0x20,0xc0};add(s,block());add(s,{0x66});reject(image(s),"late ROM after write");
 s={0x61,1,0};add(s,block());add(s,{0x66});reject(image(s),"late ROM after wait");
 s=block();s[6]=0x80;add(s,{0x66});reject(image(s),"second ROM instance");
 reject(image({0xb8,0,0x80,0xb8,0,0x10,0x66}),"keyon absent ROM");
 s=block();add(s,{0xb8,0,0x80,0x66});reject(image(s),"dangling prefix");
 s=block();add(s,{0xb8,0,0,0xb8,15,1,0x66});x=image(s);put(x,0x1c,192+2063-0x1c);reject(x,"loop bank mismatch");
 s=block();add(s,{0xb8,0,0,0x66});x=image(s);put(x,0x1c,192+2063-0x1c);check(x,Profile::D,"loop bank preserved");
 put(x,0x1c,192+2064-0x1c);reject(x,"loop operand");
 s=block();add(s,{0x50,0,0xb8,0,0,0x66});check(image(s),Profile::Ambiguous,"A mixture");
 s=block();add(s,{0x58,0,0,0xb8,0,0,0x66});check(image(s),Profile::Ambiguous,"B mixture");
 s=block();add(s,{0xb9,0,0,0xb8,0,0,0x66});check(image(s),Profile::Ambiguous,"F mixture");
 s=block();add(s,{0x66});reject(image(s),"orphan ROM");
 s=block();for(unsigned i=0;i<257;++i)add(s,{0x54,0x20,0xc0});add(s,{0x66});reject(image(s),"initial queue capacity");
 x=b;put(x,4,193);reject(x,"declared EOF before ROM");
 std::cout<<"PASS_MSM_ENABLED cases="<<cases<<"\n";
#endif
}
