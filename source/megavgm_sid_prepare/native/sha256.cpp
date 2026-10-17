#include "sha256.h"

#include <cerrno>
#include <cstdio>
#include <cstring>

namespace megavgm_sid {
namespace {

constexpr std::uint32_t k[64] = {
	0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
	0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
	0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
	0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
	0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
	0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
	0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
	0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

std::uint32_t rotr(std::uint32_t value, unsigned shift)
{
	return (value >> shift) | (value << (32 - shift));
}

} // namespace

Sha256::Sha256()
{
	state_[0]=0x6a09e667; state_[1]=0xbb67ae85; state_[2]=0x3c6ef372; state_[3]=0xa54ff53a;
	state_[4]=0x510e527f; state_[5]=0x9b05688c; state_[6]=0x1f83d9ab; state_[7]=0x5be0cd19;
}

void Sha256::transform(const std::uint8_t block[64])
{
	std::uint32_t w[64];
	for (unsigned i=0;i<16;++i)
		w[i]=(std::uint32_t(block[i*4])<<24)|(std::uint32_t(block[i*4+1])<<16)|
			(std::uint32_t(block[i*4+2])<<8)|block[i*4+3];
	for (unsigned i=16;i<64;++i) {
		const auto s0=rotr(w[i-15],7)^rotr(w[i-15],18)^(w[i-15]>>3);
		const auto s1=rotr(w[i-2],17)^rotr(w[i-2],19)^(w[i-2]>>10);
		w[i]=w[i-16]+s0+w[i-7]+s1;
	}
	std::uint32_t a=state_[0],b=state_[1],c=state_[2],d=state_[3];
	std::uint32_t e=state_[4],f=state_[5],g=state_[6],h=state_[7];
	for (unsigned i=0;i<64;++i) {
		const auto s1=rotr(e,6)^rotr(e,11)^rotr(e,25);
		const auto ch=(e&f)^((~e)&g);
		const auto t1=h+s1+ch+k[i]+w[i];
		const auto s0=rotr(a,2)^rotr(a,13)^rotr(a,22);
		const auto maj=(a&b)^(a&c)^(b&c);
		const auto t2=s0+maj;
		h=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;
	}
	state_[0]+=a;state_[1]+=b;state_[2]+=c;state_[3]+=d;
	state_[4]+=e;state_[5]+=f;state_[6]+=g;state_[7]+=h;
}

void Sha256::update(const void *data, std::size_t size)
{
	if (finished_) return;
	const auto *p=static_cast<const std::uint8_t *>(data);
	bytes_ += size;
	while (size) {
		const std::size_t take=(size < 64-buffered_) ? size : 64-buffered_;
		std::memcpy(buffer_+buffered_,p,take);
		buffered_+=take;p+=take;size-=take;
		if (buffered_==64) { transform(buffer_); buffered_=0; }
	}
}

std::array<std::uint8_t,32> Sha256::finish()
{
	if (!finished_) {
		const std::uint64_t bits=bytes_*8;
		buffer_[buffered_++]=0x80;
		if (buffered_>56) { while(buffered_<64) buffer_[buffered_++]=0; transform(buffer_); buffered_=0; }
		while(buffered_<56) buffer_[buffered_++]=0;
		for(int i=7;i>=0;--i) buffer_[buffered_++]=static_cast<std::uint8_t>(bits>>(i*8));
		transform(buffer_);buffered_=0;finished_=true;
	}
	std::array<std::uint8_t,32> out{};
	for(unsigned i=0;i<8;++i) for(unsigned j=0;j<4;++j)
		out[i*4+j]=static_cast<std::uint8_t>(state_[i]>>(24-j*8));
	return out;
}

bool sha256_file(const std::string &path, std::array<std::uint8_t,32> &digest,
		std::string &detail)
{
	FILE *file=std::fopen(path.c_str(),"rb");
	if (!file) { detail=std::strerror(errno); return false; }
	Sha256 hash; std::uint8_t data[65536]; bool ok=true;
	for (;;) {
		const auto count=std::fread(data,1,sizeof(data),file);
		if (count) hash.update(data,count);
		if (count<sizeof(data)) { if (std::ferror(file)) { detail=std::strerror(errno);ok=false; } break; }
	}
	if (std::fclose(file)!=0 && ok) { detail=std::strerror(errno);ok=false; }
	if (ok) { digest=hash.finish();detail.clear(); }
	return ok;
}

std::string hex_digest(const std::array<std::uint8_t,32> &digest)
{
	static const char digits[]="0123456789abcdef";
	std::string out;out.reserve(64);
	for(auto byte:digest) { out.push_back(digits[byte>>4]);out.push_back(digits[byte&15]); }
	return out;
}

} // namespace megavgm_sid
