#include "../src/uvc.hpp"
#include <cassert>
#include <fstream>
#include <iterator>
#include <iostream>
static void packet(Assembler&a,unsigned flags,std::initializer_list<uint8_t>payload){std::vector<uint8_t>p={2,uint8_t(flags)};p.insert(p.end(),payload);a.packet(p.data(),p.size());}
int main(int argc,char**argv){
 assert(argc==2);std::ifstream f(argv[1],std::ios::binary);std::vector<uint8_t>d((std::istreambuf_iterator<char>(f)),{});auto c=parse(d.data(),d.size());assert(c.format==1&&c.frame==5&&c.maxframe==614400&&c.interval==333333&&c.alts.size()==7);assert(c.alts.back().capacity==3060);
 auto truncated=d;truncated.pop_back();bool rejected=false;try{parse(truncated.data(),truncated.size());}catch(...){rejected=true;}assert(rejected);
 auto malformed=d;malformed[9]=0;rejected=false;try{parse(malformed.data(),malformed.size());}catch(...){rejected=true;}assert(rejected);
 Assembler a(100);packet(a,0,{255,216,1});packet(a,2,{2,255,217});assert(a.image.size()==6);
 Assembler b(100);packet(b,0,{1,2});packet(b,2,{255,217});assert(b.image.empty());packet(b,1,{255,216});packet(b,3,{255,217});assert(b.image.size()==4);
 Assembler e(100);packet(e,0,{255,216});packet(e,0x42,{255,217});assert(e.image.empty());packet(e,3,{255,216,255,217});assert(e.image.size()==4);
 Assembler small(4);packet(small,0,{255,216,1,2,3});packet(small,2,{255,217});assert(small.image.empty());packet(small,3,{255,216,255,217});assert(small.image.size()==4);
 Assembler h(100);uint8_t invalid[]={8,0,255,216};h.packet(invalid,sizeof invalid);packet(h,3,{255,216,255,217});assert(h.image.size()==4);
 // Frame transition discards an incomplete previous frame.
 Assembler transition(100);packet(transition,0,{255,216,1});packet(transition,3,{255,216,255,217});assert(transition.image.size()==4);
 std::cout<<"PASS: actual camera descriptors, malformed descriptors, fragmented MJPEG, partial frames, ERR, overflow, bad headers, FID transition\n";
}
