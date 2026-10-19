#pragma once
#include <cstdint>
struct StreamTiming {
 struct Slot { uint64_t start; bool gap; };
 uint64_t next=0;
 Slot reserve(uint64_t bus){bool gap=next!=0&&next<bus+8;if(next==0||gap)next=bus+32;Slot s{next,gap};next+=32;return s;}
 void reset(){next=0;}
};
