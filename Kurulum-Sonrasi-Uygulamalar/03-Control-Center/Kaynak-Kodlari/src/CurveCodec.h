#pragma once
#include <stdint.h>
#define G870_CURVE_POINTS 8
typedef struct { uint8_t temperature, duty; } G870CurvePoint;
typedef struct { G870CurvePoint points[G870_CURVE_POINTS]; } G870Curve;
static inline G870Curve g870_default_curve(void) {
 G870Curve c={{{45,35},{50,35},{55,38},{60,42},{65,47},{70,53},{75,60},{79,70}}};return c;
}
static inline int g870_curve_valid(G870Curve c) {
 for(unsigned i=0;i<G870_CURVE_POINTS;i++) {
  if(c.points[i].temperature<20||c.points[i].temperature>79||c.points[i].duty<35||c.points[i].duty>100)return 0;
  if(i&&(c.points[i].temperature<c.points[i-1].temperature+3||c.points[i].duty<c.points[i-1].duty))return 0;
 }return 1;
}
static inline uint64_t g870_curve_pack_half(G870Curve c,unsigned half) {
 uint64_t value=0;for(unsigned i=0;i<4;i++)value|=(uint64_t)c.points[i+half*4].temperature<<(i*16)|(uint64_t)c.points[i+half*4].duty<<(i*16+8);return value;
}
static inline G870Curve g870_curve_unpack(uint64_t low,uint64_t high) {
 G870Curve c;for(unsigned i=0;i<G870_CURVE_POINTS;i++){uint64_t value=i<4?low:high;unsigned shift=(i%4)*16;c.points[i].temperature=(uint8_t)(value>>shift);c.points[i].duty=(uint8_t)(value>>(shift+8));}return c;
}
static inline int g870_curve_parse_hex(const char *text,uint64_t *low,uint64_t *high) {
 uint64_t parts[2]={0,0};for(unsigned i=0;i<32;i++) {
  unsigned digit;if(text[i]>='0'&&text[i]<='9')digit=(unsigned)(text[i]-'0');else if(text[i]>='a'&&text[i]<='f')digit=(unsigned)(text[i]-'a'+10);else return 0;
  parts[i/16]=(parts[i/16]<<4)|digit;
 }
 if(text[32]||!g870_curve_valid(g870_curve_unpack(parts[0],parts[1])))return 0;
 *low=parts[0];*high=parts[1];return 1;
}
