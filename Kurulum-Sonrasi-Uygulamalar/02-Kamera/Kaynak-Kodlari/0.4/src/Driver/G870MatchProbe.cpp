// Quanta-only CMIO redirect. USB video capture runs in the separate CMIO process.

#include <os/log.h>

#include <DriverKit/IOUserServer.h>
#include <DriverKit/IOLib.h>

#include "G870MatchProbe.h"

kern_return_t
IMPL(G870MatchProbe, Start)
{
    kern_return_t ret;
    ret = Start(provider, SUPERDISPATCH);
    os_log(OS_LOG_DEFAULT, "G870 Quanta redirect 0.4 Start returned %d", ret);
    return ret;
}
