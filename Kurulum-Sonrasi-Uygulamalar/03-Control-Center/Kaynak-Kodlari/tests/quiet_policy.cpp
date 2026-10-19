#include "../src/QuietPolicy.h"
#include "../src/RGBCodec.h"
#include <cassert>
#include <initializer_list>
#include <cstdio>
#include <cstring>
using namespace QuietPolicy;
int main() {
 static_assert(sizeof(G870_RGB_METHOD)-1 == 4,"macOS evaluateObject only accepts a local NameSeg");
 auto c=g870_default_curve();assert(g870_curve_valid(c));
 uint64_t low=g870_curve_pack_half(c,0),high=g870_curve_pack_half(c,1),a=0,b=0;char hex[33];
 snprintf(hex,sizeof(hex),"%016llx%016llx",(unsigned long long)low,(unsigned long long)high);
 assert(g870_curve_parse_hex(hex,&a,&b)&&a==low&&b==high);
 assert(!g870_curve_parse_hex("123",&a,&b));assert(!g870_curve_parse_hex("00000000000000000000000000000000",&a,&b));
 auto bad=c;bad.points[7].temperature=80;assert(!g870_curve_valid(bad));
 bad=c;bad.points[4].duty=35;assert(!g870_curve_valid(bad));bad=c;bad.points[1].temperature=46;assert(!g870_curve_valid(bad));
 assert(decide(40,35,1200,1200,255,0).duty==35);
 assert(decide(55,40,1200,1200,255,0).duty==38);
 assert(decide(57,40,1200,1200,255,0).duty==40);
 assert(decide(54,40,1200,1200,38,0).duty==38);
 assert(decide(50,40,1200,1200,38,0).duty==35);
 assert(decide(75,40,1200,1200,255,0).duty==60);
 assert(decide(79,79,1200,1200,255,0).duty==70);
 assert(decide(80,40,1000,1000,35,0).reason==Thermal);
 assert(decide(40,80,1000,1000,35,0).reason==Thermal);
 assert(decide(0,40,1000,1000,35,0).reason==Sensor);
 assert(decide(40,111,1000,1000,35,0).reason==Sensor);
 assert(decide(40,40,0,1000,35,3).reason==Active);
 assert(decide(40,40,0,1000,35,4).reason==FanStall);
 auto aggressive=c,flat=c;for(unsigned i=0;i<8;i++){aggressive.points[i].duty=(uint8_t)(35+i*9);flat.points[i].duty=35;}
 for(auto curve:{c,aggressive,flat}) {
  assert(g870_curve_valid(curve));unsigned previous=0;
  for(unsigned t=5;t<80;t++){auto d=decide(t,t,1000,1000,255,4,curve);assert(d.reason==Active&&d.duty>=previous);previous=d.duty;}
  for(unsigned cpu=0;cpu<120;cpu++)for(unsigned gpu=0;gpu<120;gpu++) {
   auto d=decide(cpu,gpu,1000,1000,35,4,curve);assert(d.duty==255||(d.duty>=35&&d.duty<=100));
   if(cpu>=80||gpu>=80||cpu<5||gpu<5)assert(d.duty==255);
   if(d.reason!=Active)assert(d.duty==255);
  }
 }
 uint64_t rgb=0;assert(g870_rgb_parse_hex("12ff0000",&rgb)&&rgb==0x12ff0000);
 assert(g870_rgb_valid(0x3200ff00));assert(g870_rgb_valid(0x620000ff));assert(g870_rgb_valid(0x720000ff));
 assert(!g870_rgb_valid(0x420000ff));assert(!g870_rgb_valid(0x130000ff));assert(!g870_rgb_valid(0x112ff0000));
 assert(!g870_rgb_parse_hex("12ff0000;id",&rgb));assert(!g870_rgb_parse_hex("12ff",&rgb));
 for(unsigned zone=3;zone<=5;zone++) {
  assert(g870_rgb_valid(((uint64_t)zone<<32)|0x12ff0000));
  char request[16];snprintf(request,sizeof(request),"%u 12ff0000",zone);
  assert(g870_rgb_parse_zone(request,&rgb)&&rgb==(((uint64_t)zone<<32)|0x12ff0000));
 }
 assert(!g870_rgb_valid(0x612ff0000ULL));assert(!g870_rgb_valid(0x1000000512ff0000ULL));
 assert(!g870_rgb_parse_zone("6 12ff0000",&rgb));assert(!g870_rgb_parse_zone("5 12ff0000;id",&rgb));
 assert(!g870_rgb_parse_zone("5",&rgb));assert(!g870_rgb_parse_zone("",&rgb));
 puts("PASS: 8-point codec, interpolation, hysteresis, exact 80C CPU/GPU fallback, sensor/stall guards, 43200 temperature combinations, RGB payload validation.");
}
