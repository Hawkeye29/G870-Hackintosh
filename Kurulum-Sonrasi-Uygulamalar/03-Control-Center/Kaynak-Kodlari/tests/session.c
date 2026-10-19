#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
static int fakeCapabilities=0,fakeRGBProof=0;
static CFTypeRef fakeProperty(io_registry_entry_t entry,CFStringRef key,CFAllocatorRef allocator,IOOptionBits options);
#define IORegistryEntryCreateCFProperty fakeProperty
#include <assert.h>
#include <stdlib.h>
static kern_return_t fakeCall(mach_port_t,uint32_t,const uint64_t*,uint32_t,const void*,size_t,uint64_t*,uint32_t*,void*,size_t*);
#define IOConnectCallMethod fakeCall
#define main cli_main
#include "../src/g870ctl.c"
#undef IORegistryEntryCreateCFProperty
#undef main
#undef IOConnectCallMethod
static CFTypeRef fakeProperty(io_registry_entry_t entry,CFStringRef key,CFAllocatorRef allocator,IOOptionBits options) {
 if(fakeCapabilities&&(CFEqual(key,CFSTR("CurveSupported"))||CFEqual(key,CFSTR("QuietSupported"))||CFEqual(key,CFSTR("RGBSupported"))||CFEqual(key,CFSTR("RGBZonesSupported"))))return CFRetain(kCFBooleanTrue);
 if(fakeCapabilities&&CFEqual(key,CFSTR("CurvePointCount"))){int count=8;return CFNumberCreate(NULL,kCFNumberIntType,&count);}
 if(fakeRGBProof&&CFEqual(key,CFSTR("LastRGBValue"))){int value=0x12ff0000;return CFNumberCreate(NULL,kCFNumberIntType,&value);}
 return NULL;
}
static unsigned setters, renewals, queries;
static int failQuery;
static kern_return_t fakeCall(mach_port_t c,uint32_t selector,const uint64_t *input,uint32_t inputCount,const void *si,size_t sis,uint64_t *so,uint32_t *soc,void *output,size_t *size) {
 (void)c;(void)si;(void)sis;(void)so;(void)soc;
 if(selector==0){queries++;if(failQuery)return kIOReturnIOError;assert(inputCount==1&&size&&*size==32);memset(output,0,32);((uint8_t*)output)[4]=(*input==0x300?2:51);return 0;}
 if(selector==3){renewals++;assert(inputCount==0);return 0;}
 if(selector==5){assert(inputCount==2&&g870_curve_valid(g870_curve_unpack(input[0],input[1])));setters++;return 0;}
 assert(inputCount==1);assert((selector==1&&*input<=2)||(selector==2&&(*input==100||*input==255))||(selector==4&&*input<=1)||(selector==6&&g870_rgb_valid(*input)));setters++;return 0;
}
static char *run(const char *commands,int enabled) {
 FILE *oldin=stdin,*oldout=stdout;
 stdin=tmpfile();stdout=tmpfile();assert(stdin&&stdout);fputs(commands,stdin);rewind(stdin);
 setters=renewals=queries=0;interrupted=0;session(0,0,enabled);fflush(stdout);
 long length=ftell(stdout);char *text=calloc((size_t)length+1,1);rewind(stdout);assert(fread(text,1,(size_t)length,stdout)==(size_t)length);
 fclose(stdin);fclose(stdout);stdin=oldin;stdout=oldout;return text;
}
int main(void) {
 char *text=run("mode 2\nfan max\nsample\nfan auto\nquit\n",1);assert(setters==3&&renewals==1&&queries==2);assert(strstr(text,"\"action_sequence\":2"));free(text);
 text=run("mode 3\nmode 1 extra\nfan 0\nmode -1\nfan max;whoami\nquit\n",1);assert(setters==0&&queries==0&&renewals==0);assert(strstr(text,"\"ok\":false"));free(text);
 text=run("mode 1\nfan max\nsample\nquit\n",0);assert(setters==0&&renewals==0&&queries==2);assert(strstr(text,"\"controls\":false"));free(text);
 failQuery=1;text=run("sample\nquit\n",1);assert(queries==1&&renewals==0);assert(strstr(text,"\"error\""));free(text);failQuery=0;
 char oversized[600];memset(oversized,'x',sizeof(oversized));strcpy(oversized,"mode 2 ");memset(oversized+7,'x',500);strcpy(oversized+507,"\nsample\nquit\n");
 text=run(oversized,1);assert(setters==0&&queries==2);assert(strstr(text,"line_too_long"));free(text);
 fakeCapabilities=1;
 uint64_t packed=g870_curve_pack_half(g870_default_curve(),0),high=g870_curve_pack_half(g870_default_curve(),1);char commands[100];snprintf(commands,sizeof(commands),"curve %016llx%016llx\nsample\nquit\n",(unsigned long long)packed,(unsigned long long)high);
 text=run(commands,1);assert(setters==1&&renewals==1&&queries==2);assert(strstr(text,"\"action\":\"curve\""));free(text);
 text=run("curve 0000000000000000\ncurve bad\ncurve 41323e283723232d;id\nquit\n",1);assert(setters==0);free(text);
 text=run("rgb 12ff0000\nquit\n",1);assert(setters==1);free(text);
 text=run("rgb 13000000\nrgb 12ff0000;id\nquit\n",1);assert(setters==0);free(text);
 text=run("rgbzone 5 12ff0000\nrgbzone 4 1200ff00\nrgbzone 3 120000ff\nquit\n",1);assert(setters==3);free(text);
 text=run("rgbzone 6 12ff0000\nrgbzone 5 12ff0000;id\nrgbzone 33 12ff0000\nquit\n",1);assert(setters==0);free(text);
 fakeCapabilities=0;
 text=run("rgbzone 5 12ff0000\nquit\n",1);assert(setters==0);free(text);
 fakeCapabilities=0;fakeRGBProof=1;
 text=run("rgb 12ff0000\nsample\nquit\n",1);assert(setters==1);assert(strstr(text,"\"rgb_supported\":true"));free(text);
 fakeRGBProof=0;text=run("rgb 12ff0000\nquit\n",1);assert(setters==0);free(text);
 puts("PASS: session command bounds, injection-like input rejection, old-driver controls disabled, telemetry failure stops renewal, oversized input rejected.");return 0;
}
