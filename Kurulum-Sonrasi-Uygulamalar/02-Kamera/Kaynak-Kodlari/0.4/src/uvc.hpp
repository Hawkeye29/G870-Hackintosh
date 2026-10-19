#pragma once
#include <cstdint>
#include <cstddef>
#include <vector>
#include <stdexcept>
inline unsigned le16(const uint8_t*p){return p[0]|unsigned(p[1])<<8;}
inline uint32_t le32(const uint8_t*p){return le16(p)|(uint32_t(le16(p+2))<<16);}
inline void put32(uint8_t*p,uint32_t v){for(int i=0;i<4;i++)p[i]=(v>>(8*i))&255;}
struct Alt{unsigned number,capacity;};
struct Config{unsigned iface=999,format=0,frame=0,interval=0,maxframe=0;std::vector<Alt> alts;};
inline Config parse(const uint8_t*p,size_t n){
 Config c; unsigned iface=999,alt=0,cls=0,sub=0,fmt=0;
 if(n<9||p[1]!=2||le16(p+2)!=n)throw std::runtime_error("Invalid configuration length");
 for(size_t o=0;o<n;){size_t l=p[o];if(l<2||l>n-o)throw std::runtime_error("Truncated descriptor");auto d=p+o;
 if(d[1]==4){if(l<9)throw std::runtime_error("Short interface");iface=d[2];alt=d[3];cls=d[5];sub=d[6];fmt=0;}
 if(cls==14&&sub==2){
  if(d[1]==0x24&&l>=4&&d[2]==6)fmt=d[3];
  if(d[1]==0x24&&l>=26&&d[2]==7&&fmt&&alt==0&&le16(d+5)==640&&le16(d+7)==480){c.iface=iface;c.format=fmt;c.frame=d[3];c.maxframe=le32(d+17);c.interval=le32(d+21);}
  if(d[1]==5&&l>=7&&d[2]==0x81&&(d[3]&3)==1&&d[6]==1&&iface==1){unsigned raw=le16(d+4),m=(raw>>11)&3;if(m==3)throw std::runtime_error("Reserved packet multiplier");c.alts.push_back({alt,(raw&2047)*(m+1)});}
 }
 o+=l;
 }
 if(c.iface!=1||!c.format||!c.frame||!c.interval||!c.maxframe||c.maxframe>8*1024*1024||c.alts.empty())throw std::runtime_error("Expected MJPEG 640x480 interface absent");return c;
}
struct Assembler{
 size_t limit;int fid=-1;bool bad=false;std::vector<uint8_t> current,image;
 explicit Assembler(size_t cap):limit(cap){}
 void packet(const uint8_t*p,size_t n){
  if(!image.empty())return;
  if(n<2||p[0]<2||p[0]>n){bad=true;return;}
  int f=p[1]&1;if(f!=fid){fid=f;current.clear();bad=false;}
  if(p[1]&0x40)bad=true;
  size_t len=n-p[0];if(len>limit||current.size()>limit-len)bad=true;
  if(!bad)current.insert(current.end(),p+p[0],p+n);
  if(p[1]&2){if(!bad&&current.size()>=4&&current[0]==255&&current[1]==216&&current[current.size()-2]==255&&current.back()==217)image=current;current.clear();bad=true;}
 }
};
