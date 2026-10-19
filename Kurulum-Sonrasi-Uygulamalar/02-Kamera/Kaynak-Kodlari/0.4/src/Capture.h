#include <CoreFoundation/CoreFoundation.h>
#ifdef __cplusplus
extern "C" {
#endif
int g870_stream(void (* _Nonnull logfn)(const char * _Nonnull), void (* _Nonnull framefn)(CFDataRef _Nonnull, void * _Nonnull), void * _Nonnull context);
void g870_cancel(void);
void g870_prepare(void);
#ifdef __cplusplus
}
#endif
