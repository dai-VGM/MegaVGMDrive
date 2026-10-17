#include "profile.h"
#include <fstream>
#include <vector>
#include <iostream>
#include <iomanip>
#include <chrono>
#include <algorithm>
using Clock=std::chrono::steady_clock;
int main(int n,char**v){if(n<2)return 2;int repeat=n>2?std::stoi(v[2]):1;for(int run=0;run<repeat;++run){auto a=Clock::now();std::ifstream f(v[1],std::ios::binary);if(!f)return 3;std::vector<unsigned char>b{std::istreambuf_iterator<char>(f),{}};auto start=Clock::now();auto c=megavgm_profile::classify_bytes(b);auto end=Clock::now();std::cout<<"{\"profile\":"<<std::quoted(megavgm_profile::name(c.profile))<<",\"detail\":"<<std::quoted(c.detail)<<",\"commands\":"<<c.commands<<",\"prepare_ms\":"<<std::chrono::duration<double,std::milli>(end-a).count()<<",\"read_ms\":"<<std::chrono::duration<double,std::milli>(start-a).count()<<",\"classify_ms\":"<<std::chrono::duration<double,std::milli>(end-start).count();
#ifdef CAPACITY_CANDIDATE
std::cout<<",\"capacity_error\":"<<c.resource_capacity_exceeded<<",\"pages\":"<<c.required_pages<<",\"fault_pc\":"<<c.resource_fault_pc<<",\"fault_traversal\":"<<c.resource_fault_traversal<<",\"page_set\":[";bool first=true;for(unsigned p=0;p<1024;++p)if(c.resource_page_mask[p>>6]&(uint64_t(1)<<(p&63))){if(!first)std::cout<<',';first=false;std::cout<<p;}std::cout<<']';
#endif
std::cout<<"}\n";} }
