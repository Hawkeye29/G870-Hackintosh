#include "uvc.hpp"
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <ImageIO/ImageIO.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <atomic>
#include <cstdarg>
#include <cstdlib>
#include <unistd.h>
#include <memory>
#include "StreamTiming.hpp"
using IF=IOUSBInterfaceInterface300;
static std::atomic_bool interrupted{false};
static std::atomic_bool poisoned{false};
static void (*logger)(const char*)=nullptr;
extern "C" void g870_cancel(){interrupted=true;}
static void cameraLog(const char*fmt,...){char buf[2048];va_list a;va_start(a,fmt);vsnprintf(buf,sizeof(buf),fmt,a);va_end(a);if(logger)logger(buf);}
static void cameraPuts(const char*s){cameraLog("%s\n",s);}
static void check(IOReturn k,const char*step){cameraLog("%s: 0x%08x\n",step,k);if(k)throw std::runtime_error(step);}
static int prop(io_service_t s,CFStringRef key){int n=0;auto v=IORegistryEntryCreateCFProperty(s,key,kCFAllocatorDefault,0);if(v){if(CFGetTypeID(v)==CFNumberGetTypeID())CFNumberGetValue((CFNumberRef)v,kCFNumberIntType,&n);CFRelease(v);}return n;}
static IOUSBDeviceInterface** device(){
 io_iterator_t it=0;check(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching(kIOUSBDeviceClassName),&it),"Find USB");IOUSBDeviceInterface**u=nullptr;io_service_t s;
 while((s=IOIteratorNext(it))){if(prop(s,CFSTR("idVendor"))==0x0408&&prop(s,CFSTR("idProduct"))==0x209d){IOCFPlugInInterface**p=nullptr;SInt32 score=0;auto k=IOCreatePlugInInterfaceForService(s,kIOUSBDeviceUserClientTypeID,kIOCFPlugInInterfaceID,&p,&score);cameraLog("Device plugin: 0x%08x\n",k);if(!k&&p){(*p)->QueryInterface(p,CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),(LPVOID*)&u);(*p)->Release(p);}}IOObjectRelease(s);if(u)break;}IOObjectRelease(it);if(!u)throw std::runtime_error("0408:209d USB user client unavailable");return u;
}
static void logProperty(io_service_t service,CFStringRef key,const char*label){
 auto value=IORegistryEntryCreateCFProperty(service,key,kCFAllocatorDefault,0);if(!value){cameraLog("%s: absent\n",label);return;}
 auto description=CFCopyDescription(value);char text[512]={};if(description&&CFStringGetCString(description,text,sizeof(text),kCFStringEncodingUTF8))cameraLog("%s: %s\n",label,text);if(description)CFRelease(description);CFRelease(value);
}
static IF** interface(IOUSBDeviceInterface**d){
 IOUSBFindInterfaceRequest r={14,2,kIOUSBFindInterfaceDontCare,0};io_iterator_t it=0;check((*d)->CreateInterfaceIterator(d,&r,&it),"Find streaming interface");IF**u=nullptr;io_service_t s;
 while((s=IOIteratorNext(it))){logProperty(s,CFSTR("CameraAssistantBundleID"),"Streaming CameraAssistantBundleID");logProperty(s,CFSTR("UsbExclusiveOwner"),"Streaming UsbExclusiveOwner");IOCFPlugInInterface**p=nullptr;SInt32 score=0;auto k=IOCreatePlugInInterfaceForService(s,kIOUSBInterfaceUserClientTypeID,kIOCFPlugInInterfaceID,&p,&score);cameraLog("Interface plugin: 0x%08x\n",k);if(!k&&p){(*p)->QueryInterface(p,CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300),(LPVOID*)&u);(*p)->Release(p);}IOObjectRelease(s);if(u)break;}IOObjectRelease(it);if(!u)throw std::runtime_error("Streaming user client unavailable");return u;
}
static void control(IF**u,bool get,unsigned selector,uint8_t*data){IOUSBDevRequestTO r={};r.bmRequestType=get?0xa1:0x21;r.bRequest=get?0x81:1;r.wValue=selector<<8;r.wIndex=1;r.wLength=48;r.pData=data;r.noDataTimeout=2000;r.completionTimeout=2000;auto k=(*u)->ControlRequestTO(u,0,&r);cameraLog("%s selector=%u length=48 status=0x%08x returned=%u\n",get?"GET_CUR":"SET_CUR",selector,k,(unsigned)r.wLenDone);if(k||r.wLenDone!=48)throw std::runtime_error("48-byte UVC control failed");}
struct Batch{bool done=false,pending=false,gap=false;IOReturn status=0;std::vector<uint8_t>bytes;std::vector<IOUSBIsocFrame>frames;};
static void completed(void*p,IOReturn k,void*){auto*b=(Batch*)p;b->status=k;b->pending=false;b->done=true;}
static bool wait(Batch*b,double seconds){double until=CFAbsoluteTimeGetCurrent()+seconds;while(!b->done&&CFAbsoluteTimeGetCurrent()<until&&!interrupted)CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.01,true);return b->done;}
extern "C" int g870_stream(void (*logfn)(const char*),void (*framefn)(CFDataRef,void*),void*context){
 logger=logfn;
 if(poisoned){cameraPuts("STOP: previous cancellation incomplete; restart extension.");logger=nullptr;return 1;}
 cameraPuts("G870 LIVE 0.4; target 0408:209d only. No still-frame replay.");
 IOUSBDeviceInterface**d=nullptr;IF**u=nullptr;CFRunLoopSourceRef source=nullptr;
 bool opened=false,changed=false,originalValid=false,probeChanged=false;uint8_t original[48]={};UInt8 pipe=0;
 constexpr unsigned ringSize=4,packets=256;
 auto batches=std::make_unique<std::vector<Batch>>(ringSize);int result=1;unsigned long frames=0;
 try{
 d=device();IOUSBConfigurationDescriptorPtr desc=nullptr;check((*d)->GetConfigurationDescriptorPtr(d,0,&desc),"Read descriptors");if(!desc)throw std::runtime_error("No descriptors");auto c=parse((uint8_t*)desc,le16((uint8_t*)desc+2));
 u=interface(d);UInt8 num=0,alt=0;check((*u)->GetInterfaceNumber(u,&num),"Interface number");check((*u)->GetAlternateSetting(u,&alt),"Current alternate");if(num!=1||alt!=0)throw std::runtime_error("Interface not idle");check((*u)->USBInterfaceOpen(u),"Open streaming interface");opened=true;
 UInt32 period=0;check((*u)->GetFrameListTime(u,&period),"Frame period");if(period!=125)throw std::runtime_error("Expected high-speed 125us packets");
 control(u,true,1,original);originalValid=true;uint8_t p[48];memcpy(p,original,48);p[0]=1;p[1]=0;p[2]=c.format;p[3]=c.frame;put32(p+4,c.interval);put32(p+18,c.maxframe);probeChanged=true;control(u,false,1,p);control(u,true,1,p);
 unsigned payload=le32(p+22),maxframe=le32(p+18);cameraLog("Negotiated format=%u frame=%u interval=%u maxframe=%u payload=%u\n",p[2],p[3],le32(p+4),maxframe,payload);
 if(p[2]!=c.format||p[3]!=c.frame||le32(p+4)!=c.interval||!maxframe||maxframe>8*1024*1024||!payload)throw std::runtime_error("Unexpected negotiation");
 Alt selected={0,0};for(auto a:c.alts)if(a.capacity>=payload&&(!selected.capacity||a.capacity<selected.capacity))selected=a;if(!selected.capacity)throw std::runtime_error("Payload exceeds capacity");
 control(u,false,2,p);check((*u)->CreateInterfaceAsyncEventSource(u,&source),"Async source");CFRunLoopAddSource(CFRunLoopGetCurrent(),source,kCFRunLoopDefaultMode);
 changed=true;check((*u)->SetAlternateInterface(u,selected.number),"Start streaming alternate");
 UInt8 count=0;check((*u)->GetNumEndpoints(u,&count),"Endpoints");for(UInt8 i=1;i<=count;i++){UInt8 dir=0,number=0,type=0,interval=0;UInt16 size=0;check((*u)->GetPipeProperties(u,i,&dir,&number,&type,&size,&interval),"Pipe properties");if(dir==kUSBIn&&number==1&&type==kUSBIsoc&&interval==1)pipe=i;}if(!pipe)throw std::runtime_error("Iso IN pipe absent");
 StreamTiming timing;unsigned retries=0,packetErrors=0;unsigned long bytes=0;double lastFrame=CFAbsoluteTimeGetCurrent(),lastLog=lastFrame;
 auto submit=[&](Batch&b){
   for(auto&f:b.frames){f.frStatus=0;f.frReqCount=selected.capacity;f.frActCount=0;}
   bool forcedGap=false;
   for(unsigned attempt=0;attempt<3&&!interrupted;attempt++){
     UInt64 bus=0;AbsoluteTime at={};auto clockStatus=(*u)->GetBusFrameNumber(u,&bus,&at);if(clockStatus)check(clockStatus,"Read USB clock");auto slot=timing.reserve(bus);b.gap=slot.gap||forcedGap;b.done=false;b.status=0;
     auto status=(*u)->ReadIsochPipeAsync(u,pipe,b.bytes.data(),slot.start,packets,b.frames.data(),completed,&b);
     if(status==kIOReturnSuccess){b.pending=true;return;}
     if(status==kIOReturnIsoTooOld){retries++;timing.reset();forcedGap=true;cameraLog("USB timing retry status=0x%08x count=%u\n",status,retries);continue;}
     check(status,"Queue isochronous batch");
   }
   if(!interrupted)throw std::runtime_error("USB schedule recovery exhausted");
 };
 for(auto&b:*batches){b.bytes.resize(size_t(selected.capacity)*packets);b.frames.resize(packets);submit(b);}
 cameraLog("LIVE queued: %u buffers, %u microframes each, alternate=%u. Target 640x480 at 30fps.\n",ringSize,packets,selected.number);
 Assembler assembly(maxframe);unsigned index=0;
 while(!interrupted){
   auto&b=(*batches)[index];if(!wait(&b,3)){if(interrupted)break;throw std::runtime_error("USB completion timeout");}
   if(b.gap)assembly.bad=true;
   if(b.status!=kIOReturnSuccess&&b.status!=kIOReturnUnderrun)assembly.bad=true;
   for(size_t i=0;i<packets&&!interrupted;i++){
     auto&f=b.frames[i];
     if((f.frStatus==0||f.frStatus==kIOReturnUnderrun)&&f.frActCount&&f.frActCount<=f.frReqCount){
       assembly.packet(b.bytes.data()+i*selected.capacity,f.frActCount);bytes+=f.frActCount;
       if(!assembly.image.empty()){
         auto image=std::move(assembly.image);assembly.image.clear();
         auto data=CFDataCreate(kCFAllocatorDefault,image.data(),image.size());
         if(data){framefn(data,context);CFRelease(data);frames++;lastFrame=CFAbsoluteTimeGetCurrent();}
       }
     }else if(f.frStatus!=0&&f.frStatus!=kIOReturnUnderrun){assembly.bad=true;packetErrors++;}
   }
   submit(b);index=(index+1)%ringSize;
   double now=CFAbsoluteTimeGetCurrent();
   if(now-lastLog>=5){cameraLog("LIVE USB frames=%lu bytes=%lu packet-errors=%u timing-retries=%u\n",frames,bytes,packetErrors,retries);lastLog=now;}
   if(now-lastFrame>8)throw std::runtime_error("No complete MJPEG frame for 8 seconds");
 }
 result=0;
 }catch(const std::exception&e){cameraLog("STREAM STOP: %s\n",e.what());}
 // Drain every in-flight callback before freeing any USB buffer.
 bool pending=false;for(auto&b:*batches)pending|=b.pending;
 if(pending&&opened&&pipe){auto status=(*u)->AbortPipe(u,pipe);cameraLog("Abort pending reads: 0x%08x\n",status);}
 double until=CFAbsoluteTimeGetCurrent()+3;
 while(pending&&CFAbsoluteTimeGetCurrent()<until){CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.01,true);pending=false;for(auto&b:*batches)pending|=b.pending;}
 if(pending){poisoned=true;batches.release();cameraPuts("USB cancellation incomplete; buffers retained, future streams disabled in this process.");}
 if(opened){if(changed)cameraLog("Stop stream alt0: 0x%08x\n",(*u)->SetAlternateInterface(u,0));if(originalValid&&probeChanged)try{control(u,false,1,original);}catch(...){cameraPuts("PROBE restore failed");}(*u)->USBInterfaceClose(u);}
 if(source){CFRunLoopRemoveSource(CFRunLoopGetCurrent(),source,kCFRunLoopDefaultMode);CFRelease(source);}if(u)(*u)->Release(u);if(d)(*d)->Release(d);
 cameraLog("LIVE CLOSED: frames=%lu result=%d\n",frames,result);logger=nullptr;return result;
}
// Reset only before scheduling a session; cancellation itself is monotonic for that session.
extern "C" void g870_prepare(){interrupted=false;}
