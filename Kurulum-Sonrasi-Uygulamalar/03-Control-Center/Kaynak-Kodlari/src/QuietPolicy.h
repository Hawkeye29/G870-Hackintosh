#pragma once
#include "CurveCodec.h"
namespace QuietPolicy {
enum Reason { Off=0, Active=1, Thermal=2, Sensor=3, FanStall=4, Mode=5, Communication=6 };
struct Decision { unsigned duty; Reason reason; };
inline unsigned interpolate(G870Curve curve,unsigned temperature) {
 if(temperature<=curve.points[0].temperature)return curve.points[0].duty;
 for(unsigned i=1;i<G870_CURVE_POINTS;i++)if(temperature<=curve.points[i].temperature) {
  unsigned span=curve.points[i].temperature-curve.points[i-1].temperature;
  unsigned delta=curve.points[i].duty-curve.points[i-1].duty;
  return curve.points[i-1].duty+(delta*(temperature-curve.points[i-1].temperature)+span-1)/span;
 }
 return curve.points[G870_CURVE_POINTS-1].duty;
}
inline Decision decide(unsigned cpu,unsigned gpu,unsigned cpuRPM,unsigned gpuRPM,unsigned previous,unsigned grace,G870Curve curve=g870_default_curve()) {
 if(!g870_curve_valid(curve)||cpu<5||gpu<5||cpu>110||gpu>110)return {255,Sensor};
 if(cpu>=80||gpu>=80)return {255,Thermal};
 if(grace>=4&&(cpuRPM<300||gpuRPM<300))return {255,FanStall};
 unsigned temperature=cpu>gpu?cpu:gpu;
 unsigned duty=interpolate(curve,temperature);
 if(previous>=35&&previous<=100&&duty<previous&&interpolate(curve,temperature+3)>=previous)duty=previous;
 return {duty,Active};
}
}
