#include "CurveCodec.h"
#include "RGBCodec.h"
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
static volatile sig_atomic_t interrupted = 0;
static uint64_t sessionIdentifier = 0;
static void on_signal(int signal_number) { (void)signal_number; interrupted=1; }
static uint32_t word32(const uint8_t *p) { return p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24; }
static kern_return_t query(io_connect_t c, uint64_t command, uint8_t *reply) {
 size_t size=32; kern_return_t result=IOConnectCallMethod(c,0,&command,1,NULL,0,NULL,NULL,reply,&size);
 return result ? result : size==32 ? KERN_SUCCESS : kIOReturnBadMessageID;
}
static kern_return_t control(io_connect_t c, uint32_t selector, uint64_t value) {
 return IOConnectCallMethod(c,selector,selector==3 ? NULL : &value,selector==3 ? 0 : 1,NULL,0,NULL,NULL,NULL,NULL);
}
static int boolean_property(io_service_t service, const char *name) {
 CFStringRef key=CFStringCreateWithCString(NULL,name,kCFStringEncodingUTF8);
 CFTypeRef object=IORegistryEntryCreateCFProperty(service,key,kCFAllocatorDefault,0); CFRelease(key);
 int result=object && CFGetTypeID(object)==CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)object);
 if(object)CFRelease(object);return result;
}
// Compatibility with the already-running 0.5.2 driver: LastRGBValue exists
// only after firmware acknowledgement, and is cleared by a system restart.
static int rgb_available(io_service_t service) {
 if(boolean_property(service,"RGBSupported"))return 1;
 CFTypeRef proof=IORegistryEntryCreateCFProperty(service,CFSTR("LastRGBValue"),kCFAllocatorDefault,0);
 int available=proof&&CFGetTypeID(proof)==CFNumberGetTypeID();
 if(proof)CFRelease(proof);return available;
}
static int number_property(io_service_t service,const char *name) {
 CFStringRef key=CFStringCreateWithCString(NULL,name,kCFStringEncodingUTF8);
 CFTypeRef object=IORegistryEntryCreateCFProperty(service,key,kCFAllocatorDefault,0);CFRelease(key);
 int result=0;if(object && CFGetTypeID(object)==CFNumberGetTypeID())CFNumberGetValue((CFNumberRef)object,kCFNumberIntType,&result);
 if(object)CFRelease(object);return result;
}
static uint64_t curve_property(io_service_t service,const char *name) {
 CFStringRef key=CFStringCreateWithCString(NULL,name,kCFStringEncodingUTF8);
 CFTypeRef object=IORegistryEntryCreateCFProperty(service,key,kCFAllocatorDefault,0);CFRelease(key);
 int64_t value=0;if(object&&CFGetTypeID(object)==CFNumberGetTypeID())CFNumberGetValue((CFNumberRef)object,kCFNumberSInt64Type,&value);
 if(object)CFRelease(object);return (uint64_t)value;
}
static void snapshot(io_connect_t c, io_service_t service, int controls, unsigned actionResult, const char *action, unsigned sequence) {
 uint8_t status[32],mode[32];
 kern_return_t result=query(c,0x200,status); if(!result)result=query(c,0x300,mode);
 if(result) { printf("{\"error\":%u,\"controls\":%s}\n",result,controls?"true":"false");return; }
 if(controls)control(c,3,0);
 printf("{\"session_id\":\"%016llx\",",(unsigned long long)sessionIdentifier);
 printf("\"rgb_stage\":%u,\"rgb_acpi_result\":%u,\"rgb_firmware_result\":%u,\"rgb_request\":%u,",(unsigned)number_property(service,"LastRGBStage"),(unsigned)number_property(service,"LastRGBACPIResult"),(unsigned)number_property(service,"LastRGBFirmwareResult"),(unsigned)number_property(service,"LastRGBRequest"));
 printf("\"rgb_supported\":%s,",rgb_available(service)?"true":"false");
 printf("\"rgb_zones_supported\":%s,",boolean_property(service,"RGBZonesSupported")?"true":"false");
 printf("\"curve_all_modes\":%s,",boolean_property(service,"CurveAllModes")?"true":"false");
 printf("\"curve_supported\":%s,\"curve_point_count\":%d,\"curve_hex\":\"%016llx%016llx\",",boolean_property(service,"CurveSupported")?"true":"false",number_property(service,"CurvePointCount"),(unsigned long long)curve_property(service,"CurvePackedLow"),(unsigned long long)curve_property(service,"CurvePackedHigh"));
 printf("\"quiet_supported\":%s,\"quiet_active\":%s,\"quiet_duty\":%d,\"quiet_reason\":%d,",boolean_property(service,"QuietSupported")?"true":"false",boolean_property(service,"QuietActive")?"true":"false",number_property(service,"QuietDuty"),number_property(service,"QuietReason"));
 printf("\"action_sequence\":%u,\"timestamp\":%lld,\"controls\":%s,\"override\":%s,\"restoration_pending\":%s,\"action_result\":%u,\"action\":\"%s\",\"status\":{\"cpu_temperature_raw\":%u,\"gpu_temperature_raw\":%u,\"cpu_fan_raw\":%u,\"gpu_fan_raw\":%u},\"mode\":{\"firmware_mode_raw\":%u}}\n",
  sequence,(long long)time(NULL),controls?"true":"false",boolean_property(service,"FanOverrideActive")?"true":"false",boolean_property(service,"RestorationPending")?"true":"false",actionResult,action,word32(status+4),word32(status+8),word32(status+12),word32(status+16),word32(mode+4));
}
static int session(io_connect_t c,io_service_t service,int controls) {
 sessionIdentifier=((uint64_t)arc4random()<<32)|arc4random();
 setvbuf(stdout,NULL,_IOLBF,0);
 struct sigaction handler={0}; handler.sa_handler=on_signal;sigemptyset(&handler.sa_mask);
 sigaction(SIGINT,&handler,NULL);sigaction(SIGTERM,&handler,NULL);sigaction(SIGHUP,&handler,NULL);
 char line[128]; unsigned lastResult=0,sequence=0;const char *lastAction="none";
 while(!interrupted && fgets(line,sizeof(line),stdin)) {
  if(!strchr(line,'\n') && !feof(stdin)) { int ch;while((ch=getchar())!='\n'&&ch!=EOF){};puts("{\"ok\":false,\"error\":\"line_too_long\"}");continue; }
  line[strcspn(line,"\r\n")]=0;
  if(!strcmp(line,"quit"))break;
  if(!strcmp(line,"sample")) {
   snapshot(c,service,controls,lastResult,lastAction,sequence);continue;
  }
  uint32_t selector=0;uint64_t value=0,high=0;const char *action="invalid";
  if(!strcmp(line,"mode 0")){selector=1;value=0;action="mode";}
  else if(!strcmp(line,"mode 1")){selector=1;value=1;action="mode";}
  else if(!strcmp(line,"mode 2")){selector=1;value=2;action="mode";}
  else if(!strcmp(line,"fan max")){selector=2;value=100;action="fan_max";}
  else if(!strcmp(line,"fan auto")){selector=2;value=255;action="fan_auto";}
  else if(!strcmp(line,"quiet on") && boolean_property(service,"QuietSupported")){selector=4;value=1;action="quiet_on";}
  else if(!strcmp(line,"quiet off") && boolean_property(service,"QuietSupported")){selector=4;value=0;action="quiet_off";}
  else if(!strncmp(line,"curve ",6) && g870_curve_parse_hex(line+6,&value,&high) && boolean_property(service,"CurveSupported") && number_property(service,"CurvePointCount")==8){selector=5;action="curve";}
  else if(!strncmp(line,"rgbzone ",8) && g870_rgb_parse_zone(line+8,&value) && boolean_property(service,"RGBZonesSupported")){selector=6;action="rgb_zone";}
  else if(!strncmp(line,"rgb ",4) && g870_rgb_parse_hex(line+4,&value) && rgb_available(service)){selector=6;action="rgb";}
  uint64_t curveInput[2]={value,high};
  lastResult=selector && controls ? (selector==5 ? IOConnectCallMethod(c,5,curveInput,2,NULL,0,NULL,NULL,NULL,NULL) : control(c,selector,value)) : kIOReturnUnsupported;
  lastAction=action;sequence++;
  printf("{\"ok\":%s,\"action\":\"%s\",\"result\":%u}\n",lastResult==0?"true":"false",action,lastResult);
 }
 // Closing this connection restores its overrides, including on EOF/signal.
 return 0;
}
#include "ServiceTransport.h"
int main(int argc,char **argv) {
 if(argc==2&&!strcmp(argv[1],"connect"))return service_connect();
 if(argc==3&&!strcmp(argv[1],"serve"))return service_serve(argv[2]);
 if(argc!=2){fprintf(stderr,"Usage: g870ctl probe|status|mode|capabilities|session\n");return 2;}
 uint64_t command=0;int isSession=!strcmp(argv[1],"session");int diagnose=!strcmp(argv[1],"rgbdiagnose");
 if(!strcmp(argv[1],"status"))command=0x200;
 else if(!strcmp(argv[1],"mode"))command=0x300;
 else if(!strcmp(argv[1],"capabilities"))command=0x202;
 else if(strcmp(argv[1],"probe") && !isSession && !diagnose){fprintf(stderr,"Unknown command\n");return 2;}
 io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("G870Bridge"));
 if(!service){fprintf(stderr,"G870Bridge is not loaded or matched. No command sent.\n");return 3;}
 int controls=boolean_property(service,"HardwareControlEnabled");
 if(!command&&!isSession&&!diagnose){printf("G870Bridge matched; controls: %s; RGB verified: %s. No hardware command sent.\n",controls?"yes":"no",rgb_available(service)?"yes":"no");IOObjectRelease(service);return 0;}
 if(geteuid()!=0){fprintf(stderr,"Run with sudo.\n");IOObjectRelease(service);return 4;}
 io_connect_t connection=IO_OBJECT_NULL;
 kern_return_t result=IOServiceOpen(service,mach_task_self(),0,&connection);
 if(result){fprintf(stderr,"IOServiceOpen: 0x%x\n",result);IOObjectRelease(service);return 5;}
 if(diagnose) {
  result=control(connection,6,0x12ff0000);
  printf("{\"request\":\"static_red_high\",\"result\":%u,\"rgb_supported\":%s,\"stage\":%u,\"acpi_result\":%u,\"firmware_result\":%u}\n",result,rgb_available(service)?"true":"false",(unsigned)number_property(service,"LastRGBStage"),(unsigned)number_property(service,"LastRGBACPIResult"),(unsigned)number_property(service,"LastRGBFirmwareResult"));
  IOServiceClose(connection);IOObjectRelease(service);return 0;
 }
 if(isSession){int exitCode=session(connection,service,controls);IOServiceClose(connection);IOObjectRelease(service);return exitCode;}
 uint8_t reply[32];result=query(connection,command,reply);IOServiceClose(connection);IOObjectRelease(service);
 if(result){fprintf(stderr,"Query failed: 0x%x\n",result);return 6;}
 printf("{\"command\":%llu,\"raw\":\"",command);for(int i=0;i<32;i++)printf("%02x",reply[i]);printf("\"");
 if(command==0x200)printf(",\"cpu_temperature_raw\":%u,\"gpu_temperature_raw\":%u,\"cpu_fan_raw\":%u,\"gpu_fan_raw\":%u",word32(reply+4),word32(reply+8),word32(reply+12),word32(reply+16));
 if(command==0x300)printf(",\"firmware_mode_raw\":%u",word32(reply+4));puts("}");return 0;
}
