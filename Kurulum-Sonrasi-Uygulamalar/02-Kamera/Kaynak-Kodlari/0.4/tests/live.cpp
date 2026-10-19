#include "../src/uvc.hpp"
#include "../src/StreamTiming.hpp"
#include <cassert>
#include <iostream>
static void packet(Assembler&a,unsigned flags,std::initializer_list<uint8_t>payload){std::vector<uint8_t>p={2,uint8_t(flags)};p.insert(p.end(),payload);a.packet(p.data(),p.size());}
int main(){
 StreamTiming t;
 // Queue four consecutive 32ms slots ahead of the USB bus.
 for(unsigned i=0;i<4;i++){auto s=t.reserve(1000);assert(s.start==1032+i*32&&!s.gap);}
 // Sustained queue replenishment must preserve contiguous start frames.
 for(unsigned i=0;i<10000;i++){auto s=t.reserve(1032+i*32);assert(s.start==1160+i*32&&!s.gap);}
 auto recovery=t.reserve(1'000'000);assert(recovery.gap&&recovery.start==1'000'032);
 auto next=t.reserve(1'000'000);assert(!next.gap&&next.start==1'000'064);
 t.reset();auto reset=t.reserve(500);assert(reset.start==532);
 // Stream consumes every finished frame, including consecutive frames in one batch.
 Assembler a(100);unsigned frames=0;
 for(unsigned i=0;i<1000;i++){unsigned fid=i&1;packet(a,fid,{255,216,1});assert(a.image.empty());packet(a,fid|2,{2,255,217});assert(a.image.size()==6);auto image=std::move(a.image);a.image.clear();frames++;}
 assert(frames==1000);
 // A USB packet gap must discard the damaged frame, then recover on FID transition.
 Assembler b(100);packet(b,0,{255,216,1});b.bad=true;packet(b,2,{255,217});assert(b.image.empty());packet(b,3,{255,216,255,217});assert(b.image.size()==4);
 std::cout<<"PASS: contiguous scheduling, delayed-submit recovery, 1000 continuous frames, packet-gap recovery\n";
}
