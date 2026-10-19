#include "QuietPolicy.h"
#include "RGBCodec.h"
#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOWorkLoop.h>
#include <IOKit/IOTimerEventSource.h>
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/RootDomain.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <libkern/OSByteOrder.h>
#include <libkern/c++/OSData.h>
#include <libkern/c++/OSNumber.h>

class G870Bridge : public IOService {
 OSDeclareDefaultStructors(G870Bridge)
 IOACPIPlatformDevice *acpi = nullptr;
 IOLock *lock = nullptr;
 IOWorkLoop *loop = nullptr;
 IOTimerEventSource *timer = nullptr;
 IONotifier *sleepNotifier = nullptr;
 IOUserClient *owner = nullptr; // compared only; never dereferenced
 bool timerAdded = false, suspended = false;
 bool fanOverride = false, modeOverride = false, restoring = false, stopping = false;
 uint32_t originalMode = 0, ticks = 0;
 G870Curve curve = g870_default_curve();
 bool quiet = false; unsigned quietDuty = 255, quietGrace = 0, quietMode = 2;
 void refreshRGBSupport();
 IOReturn updateQuiet();
 IOReturn disableQuiet(unsigned reason);
 IOReturn transact(uint16_t kind, uint16_t command, uint32_t a2, uint32_t a3, void *output);
 IOReturn claim(IOUserClient *client);
 void restore(); // all state/firmware operations require lock
 static void timerFired(OSObject *target, IOTimerEventSource *source);
 static IOReturn powerEvent(void *target, void *, UInt32 type, IOService *, void *argument, vm_size_t);
public:
 bool start(IOService *provider) override;
 void stop(IOService *provider) override;
 void free() override;
 IOReturn query(uint32_t command, void *output);
 IOReturn control(IOUserClient *client, uint32_t selector, uint64_t value, uint64_t high = 0);
 void releaseOwner(IOUserClient *client);
};
class G870Client : public IOUserClient {
 OSDeclareDefaultStructors(G870Client)
 G870Bridge *bridge = nullptr;
public:
 bool initWithTask(task_t task, void *token, UInt32 type) override {
  return clientHasPrivilege(token, kIOClientPrivilegeAdministrator) == kIOReturnSuccess && IOUserClient::initWithTask(task, token, type);
 }
 bool initWithTask(task_t task, void *token, UInt32 type, OSDictionary *properties) override {
  return clientHasPrivilege(token, kIOClientPrivilegeAdministrator) == kIOReturnSuccess && IOUserClient::initWithTask(task, token, type, properties);
 }
 bool start(IOService *provider) override {
  bridge = OSDynamicCast(G870Bridge, provider);
  return bridge && IOUserClient::start(provider);
 }
 IOReturn clientClose() override {
  if (bridge) bridge->releaseOwner(this);
  terminate(); return kIOReturnSuccess;
 }
 IOReturn clientDied() override { return clientClose(); }
 void stop(IOService *provider) override {
  if (bridge) bridge->releaseOwner(this);
  bridge = nullptr; IOUserClient::stop(provider);
 }
 IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *args,
  IOExternalMethodDispatch * = nullptr, OSObject * = nullptr, void * = nullptr) override {
  if (!bridge || isInactive() || args->asyncWakePort || args->scalarOutputCount || args->structureInputSize)
   return kIOReturnBadArgument;
  if (selector == 0) {
   if (args->scalarInputCount != 1 || args->structureOutputSize != 32 || !args->structureOutput || args->scalarInput[0] > 0xffff)
    return kIOReturnBadArgument;
   IOReturn result = bridge->query((uint32_t)args->scalarInput[0], args->structureOutput);
   args->structureOutputSize = result == kIOReturnSuccess ? 32 : 0;
   return result;
  }
  if (selector < 1 || selector > 6 || args->structureOutputSize || args->scalarInputCount != (selector == 3 ? 0u : selector == 5 ? 2u : 1u))
   return kIOReturnBadArgument;
  return bridge->control(this, selector, selector == 3 ? 0 : args->scalarInput[0], selector == 5 ? args->scalarInput[1] : 0);
 }
};
OSDefineMetaClassAndStructors(G870Bridge, IOService)
OSDefineMetaClassAndStructors(G870Client, IOUserClient)

bool G870Bridge::start(IOService *provider) {
 if (!IOService::start(provider)) return false;
 acpi = OSDynamicCast(IOACPIPlatformDevice, provider);
 if (!acpi || strcmp(provider->getName(), "GWMI") || acpi->validateObject("WSAA") || acpi->validateObject("WQAA")) return false;
 OSObject *object = nullptr;
 IOReturn status = acpi->evaluateObject("_WDG", &object);
 auto data = OSDynamicCast(OSData, object);
 const uint8_t expected[] = {0x91,0x57,0x4c,0x64,0xb0,0xb7,0x23,0x41,0xa9,0x0b,0xe9,0x38,0x76,0xe0,0xda,0xad,0x41,0x41,0x01,0x00};
 bool valid = status == kIOReturnSuccess && data && data->getLength() == 60 && !memcmp(data->getBytesNoCopy(), expected, sizeof(expected));
 if (object) object->release();
 if (!valid || !(lock = IOLockAlloc()) || !(loop = IOWorkLoop::workLoop())) return false;
 timer = IOTimerEventSource::timerEventSource(this, timerFired);
 if (!timer || loop->addEventSource(timer) != kIOReturnSuccess) return false;
 timerAdded = true;
 sleepNotifier = registerPrioritySleepWakeInterest(powerEvent, this);
 if (!sleepNotifier) return false;
 setProperty("Protocol", "G870-GWMI-controls-v5");
 setProperty("CurveSupported", true);
 setProperty("RGBSupported", acpi->validateObject("\\_SB.GRGB") == kIOReturnSuccess);
 setProperty("CurveAllModes", true);
 setProperty("CurvePointCount", (unsigned long long)8,32);
 setProperty("CurvePackedLow", (unsigned long long)g870_curve_pack_half(curve,0),64);
 setProperty("CurvePackedHigh", (unsigned long long)g870_curve_pack_half(curve,1),64);
 setProperty("QuietSupported", true);
 setProperty("QuietActive", false);
 setProperty("QuietReason", (unsigned long long)0, 32);
 setProperty("QuietDuty", (unsigned long long)255, 32);
 setProperty("HardwareControlEnabled", true);
 setProperty("FanOverrideActive", false);
 setProperty("ControlLeaseActive", false);
 timer->setTimeoutMS(2000);
 registerService(); return true;
}
void G870Bridge::stop(IOService *provider) {
 if (sleepNotifier) { sleepNotifier->remove(); sleepNotifier = nullptr; }
 IOLockLock(lock); stopping = true; restore(); IOLockUnlock(lock);
 if (timer) { timer->cancelTimeout(); loop->removeEventSource(timer); timerAdded = false; }
 IOService::stop(provider);
}
void G870Bridge::free() {
 if (sleepNotifier) { sleepNotifier->remove(); sleepNotifier = nullptr; }
 if (timer) { timer->cancelTimeout(); if (loop && timerAdded) loop->removeEventSource(timer); timer->release(); }
 if (loop) loop->release();
 if (lock) IOLockFree(lock);
 IOService::free();
}
IOReturn G870Bridge::transact(uint16_t kind, uint16_t command, uint32_t a2, uint32_t a3, void *output) {
 uint8_t packet[32] = {};
 OSWriteLittleInt16(packet, 0, kind); OSWriteLittleInt16(packet, 2, command);
 OSWriteLittleInt32(packet, 4, a2); OSWriteLittleInt32(packet, 8, a3);
 auto index = OSNumber::withNumber((unsigned long long)0, 32);
 auto request = OSData::withBytes(packet, 32);
 if (!index || !request) { if (index) index->release(); if (request) request->release(); return kIOReturnNoMemory; }
 OSObject *parameters[] = {index, request};
 OSObject *response = nullptr;
 IOReturn result = acpi->evaluateObject("WSAA", nullptr, parameters, 2);
 if (result == kIOReturnSuccess) {
  OSObject *readParameters[] = {index};
  result = acpi->evaluateObject("WQAA", &response, readParameters, 1);
 }
 if (result == kIOReturnSuccess) {
  auto data = OSDynamicCast(OSData, response);
  if (!data || data->getLength() != 32) result = kIOReturnBadMessageID;
  else {
   auto bytes = (const uint8_t *)data->getBytesNoCopy();
   if (OSReadLittleInt16(bytes, 0) == 0x1000) result = kIOReturnUnsupported;
   else if (output) memcpy(output, bytes, 32);
  }
 }
 if (response) response->release();
 request->release(); index->release(); return result;
}
void G870Bridge::refreshRGBSupport() {
 UInt32 identity = 0;
 IOReturn result = acpi->evaluateInteger("GRCQ", &identity);
 setProperty("RGBSupported", result == kIOReturnSuccess && (identity == 0x47524201 || identity == 0x47524202));
 setProperty("RGBZonesSupported", result == kIOReturnSuccess && identity == 0x47524202);
}
IOReturn G870Bridge::query(uint32_t command, void *output) {
 if (command != 0x200 && command != 0x201 && command != 0x202 && command != 0x205 && command != 0x207 && command != 0x300)
  return kIOReturnUnsupported;
 IOLockLock(lock);
 if (!stopping && !suspended && !isInactive()) refreshRGBSupport();
 IOReturn result = stopping || suspended || isInactive() ? kIOReturnNotAttached : transact(0xfa00, (uint16_t)command, 0, 0, output);
 IOLockUnlock(lock); return result;
}
IOReturn G870Bridge::claim(IOUserClient *client) {
 if (restoring || (owner && owner != client)) return kIOReturnExclusiveAccess;
 if (!owner) {
  uint8_t response[32];
  IOReturn result = transact(0xfa00, 0x300, 0, 0, response);
  if (result != kIOReturnSuccess) return result;
  originalMode = OSReadLittleInt32(response, 4);
  if (originalMode > 2) return kIOReturnUnsupported;
  owner = client; setProperty("ControlLeaseActive", true);
 }
 ticks = 0; return kIOReturnSuccess;
}
IOReturn G870Bridge::control(IOUserClient *client, uint32_t selector, uint64_t value, uint64_t high) {
 if ((selector == 1 && value > 2) || (selector == 2 && value != 100 && value != 255) || (selector == 4 && value > 1) || (selector == 5 && !g870_curve_valid(g870_curve_unpack(value,high))) || (selector == 6 && !g870_rgb_valid(value))) return kIOReturnBadArgument;
 IOLockLock(lock);
 IOReturn result = kIOReturnNotAttached;
 if (!stopping && !suspended && !isInactive()) {
  if (selector == 6) {
   if (value >> 32) {
    UInt32 identity = 0;
    result = acpi->evaluateInteger("GRCQ", &identity);
    if (result != kIOReturnSuccess || identity != 0x47524202) { IOLockUnlock(lock); return kIOReturnUnsupported; }
   }
   setProperty("LastRGBRequest", (unsigned long long)value,64);
   setProperty("LastRGBStage", (unsigned long long)1,32);
   auto input = OSNumber::withNumber((unsigned long long)value,64);
   if (!input) result = kIOReturnNoMemory;
   else {
    OSObject *parameters[] = {input}; OSObject *output = nullptr;
    result = acpi->evaluateObject(G870_RGB_METHOD, &output, parameters,1);
    input->release();
    setProperty("LastRGBACPIResult",(unsigned long long)(uint32_t)result,32);
    setProperty("LastRGBStage",(unsigned long long)2,32);
    if (result == kIOReturnSuccess) {
     auto number = OSDynamicCast(OSNumber, output);
     if (!number) result = kIOReturnBadMessageID;
     else {
      UInt32 response = number->unsigned32BitValue();
      setProperty("LastRGBFirmwareResult",(unsigned long long)response,32);
      setProperty("LastRGBStage",(unsigned long long)3,32);
      result = response == 1 ? kIOReturnSuccess : response == 2 ? kIOReturnUnsupported : response == 3 ? kIOReturnTimeout : kIOReturnBusy;
      if (result == kIOReturnSuccess) { setProperty("LastRGBValue",(unsigned long long)value,64); setProperty("RGBSupported", true); }
     }
    }
    if (output) output->release();
   }
   setProperty("LastRGBResult",(unsigned long long)(uint32_t)result,32);
  } else if (selector == 3) {
   result = owner == client ? kIOReturnSuccess : kIOReturnNotOpen;
   if (result == kIOReturnSuccess) ticks = 0;
  } else if ((result = claim(client)) == kIOReturnSuccess) {
   if (selector == 4 || selector == 5) {
    if (selector == 4 && !value) result = disableQuiet(QuietPolicy::Off);
    else {
     if (selector == 5) { curve = g870_curve_unpack(value,high); setProperty("CurvePackedLow", (unsigned long long)value,64); setProperty("CurvePackedHigh", (unsigned long long)high,64); }
     if (selector == 4) {
      modeOverride = true;
      result = transact(0xfb00, 0x300, 2, 0, nullptr);
      quietMode = 2;
     } else {
      uint8_t response[32];
      result = transact(0xfa00, 0x300, 0, 0, response);
      if (result == kIOReturnSuccess) {
       quietMode = OSReadLittleInt32(response, 4);
       if (quietMode > 2) result = kIOReturnUnsupported;
      }
     }
     if (result == kIOReturnSuccess) {
      quiet = true; quietGrace = 0; quietDuty = 255;
      result = updateQuiet();
     }
    }
   } else if (selector == 1) {
    if (quiet) result = disableQuiet(QuietPolicy::Mode);
    if (result != kIOReturnSuccess) { restore(); IOLockUnlock(lock); return result; }
    modeOverride = true; // preserve restoration even if firmware partially executes
    result = transact(0xfb00, 0x300, (uint32_t)value, 0, nullptr);
    if (result == kIOReturnSuccess) {
     uint8_t response[32]; result = transact(0xfa00, 0x300, 0, 0, response);
     if (result == kIOReturnSuccess && OSReadLittleInt32(response, 4) != value) result = kIOReturnIOError;
    }
   } else {
    quiet = false; setProperty("QuietActive", false);
    setProperty("QuietReason", (unsigned long long)QuietPolicy::Off, 32);
    fanOverride = true;
    result = transact(0xfb00, 0x205, (uint32_t)value, (uint32_t)value, nullptr);
    if (result == kIOReturnSuccess && value == 255) fanOverride = false;
    setProperty("FanOverrideActive", fanOverride);
   }
   if (result != kIOReturnSuccess) restore();
  }
 }
 IOLockUnlock(lock); return result;
}
IOReturn G870Bridge::disableQuiet(unsigned reason) {
 quiet = false;
 setProperty("QuietActive", false);
 setProperty("QuietReason", (unsigned long long)reason, 32);
 fanOverride = true; // keep retry ownership if even automatic restoration fails
 IOReturn result = transact(0xfb00, 0x205, 255, 255, nullptr);
 if (result == kIOReturnSuccess) {
  fanOverride = false; quietDuty = 255;
  setProperty("FanOverrideActive", false);
  setProperty("QuietDuty", (unsigned long long)255, 32);
 }
 return result;
}
IOReturn G870Bridge::updateQuiet() {
 uint8_t mode[32], status[32];
 if (transact(0xfa00, 0x300, 0, 0, mode) != kIOReturnSuccess ||
     transact(0xfa00, 0x200, 0, 0, status) != kIOReturnSuccess)
  return disableQuiet(QuietPolicy::Communication);
 if (OSReadLittleInt32(mode, 4) != quietMode) return disableQuiet(QuietPolicy::Mode);
 auto decision = QuietPolicy::decide(OSReadLittleInt32(status,4), OSReadLittleInt32(status,8),
   OSReadLittleInt32(status,12), OSReadLittleInt32(status,16), quietDuty, quietGrace, curve);
 if (decision.reason != QuietPolicy::Active) return disableQuiet(decision.reason);
 if (quietGrace < 4) quietGrace++;
 if (decision.duty != quietDuty) {
  fanOverride = true;
  IOReturn result = transact(0xfb00,0x205,decision.duty,decision.duty,nullptr);
  if (result != kIOReturnSuccess) return result;
  quietDuty = decision.duty;
 }
 setProperty("QuietActive", true);
 setProperty("QuietReason", (unsigned long long)QuietPolicy::Active,32);
 setProperty("QuietDuty", (unsigned long long)quietDuty,32);
 setProperty("FanOverrideActive", true);
 return kIOReturnSuccess;
}
void G870Bridge::restore() {
 // Retain failed restoration work for the watchdog to retry without keeping a dead client pointer.
 owner = nullptr;
 quiet = false; setProperty("QuietActive", false);
 if (fanOverride && transact(0xfb00, 0x205, 255, 255, nullptr) == kIOReturnSuccess) fanOverride = false;
 if (modeOverride) {
  IOReturn result = transact(0xfb00, 0x300, originalMode, 0, nullptr);
  uint8_t response[32];
  if (result == kIOReturnSuccess && transact(0xfa00, 0x300, 0, 0, response) == kIOReturnSuccess && OSReadLittleInt32(response, 4) == originalMode)
   modeOverride = false;
 }
 restoring = fanOverride || modeOverride;
 setProperty("FanOverrideActive", fanOverride);
 setProperty("ControlLeaseActive", restoring);
 setProperty("RestorationPending", restoring);
}
void G870Bridge::releaseOwner(IOUserClient *client) {
 IOLockLock(lock); if (owner == client) restore(); IOLockUnlock(lock);
}
void G870Bridge::timerFired(OSObject *target, IOTimerEventSource *source) {
 auto self = OSDynamicCast(G870Bridge, target);
 if (!self) return;
 IOLockLock(self->lock);
 if (!self->stopping) {
  if (!self->suspended && (self->restoring || (self->owner && ++self->ticks >= 6))) self->restore();
  if (!self->suspended && !self->restoring && self->owner && self->quiet) {
   if (self->updateQuiet() != kIOReturnSuccess) self->restore();
  }
  source->setTimeoutMS(2000);
 }
 IOLockUnlock(self->lock);
}
IOReturn G870Bridge::powerEvent(void *target, void *, UInt32 type, IOService *, void *argument, vm_size_t) {
 auto self = static_cast<G870Bridge *>(target);
 if (type == kIOMessageCanSystemSleep) {
  acknowledgeSleepWakeNotification(argument);
  return kIOReturnSuccess;
 }
 if (type == kIOMessageSystemHasPoweredOn || type == kIOMessageSystemWillNotSleep) {
  IOLockLock(self->lock); self->suspended = false; IOLockUnlock(self->lock);
 }
 if (type == kIOMessageSystemWillSleep || type == kIOMessageSystemWillPowerOff || type == kIOMessageSystemWillRestart) {
  IOLockLock(self->lock);
  self->suspended = true;
  if (self->owner || self->restoring) self->restore();
  IOLockUnlock(self->lock);
  if (type == kIOMessageSystemWillSleep) acknowledgeSleepWakeNotification(argument);
 }
 return kIOReturnSuccess;
}
#include <mach/kmod.h>
extern "C" {
extern kern_return_t _start(kmod_info_t *, void *);
extern kern_return_t _stop(kmod_info_t *, void *);
KMOD_EXPLICIT_DECL(local.g870.G870Bridge, "0.8.0", _start, _stop)
__attribute__((visibility("hidden"))) kmod_start_func_t *_realmain = nullptr;
__attribute__((visibility("hidden"))) kmod_stop_func_t *_antimain = nullptr;
__attribute__((visibility("hidden"))) int _kext_apple_cc = __APPLE_CC__;
}
