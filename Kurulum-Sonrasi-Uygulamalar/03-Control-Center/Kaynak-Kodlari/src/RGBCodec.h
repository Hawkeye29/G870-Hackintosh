#pragma once
#include <stdint.h>
#define G870_RGB_METHOD "GRGB"
static inline int g870_rgb_valid(uint64_t value) {
 unsigned mode=(unsigned)((value>>28)&15),brightness=(unsigned)((value>>24)&15);
 uint64_t zone=value>>32;
 return (zone==0||zone==3||zone==4||zone==5)&&(mode==1||mode==3||mode==6||mode==7)&&brightness<=2;
}
static inline int g870_rgb_parse_hex(const char *text,uint64_t *output) {
 uint64_t value=0;for(unsigned i=0;i<8;i++) {
  unsigned digit;if(text[i]>='0'&&text[i]<='9')digit=(unsigned)(text[i]-'0');else if(text[i]>='a'&&text[i]<='f')digit=(unsigned)(text[i]-'a'+10);else return 0;
  value=(value<<4)|digit;
 }
 if(text[8]||!g870_rgb_valid(value))return 0;*output=value;return 1;
}
static inline int g870_rgb_parse_zone(const char *text,uint64_t *output) {
 if(!text[0]||text[1]!=' '||text[0]<'3'||text[0]>'5')return 0;
 uint64_t value=0;if(!g870_rgb_parse_hex(text+2,&value))return 0;
 *output=((uint64_t)(text[0]-'0')<<32)|value;return 1;
}
