// This file is a part of Julia. License is MIT: http://julialang.org/license

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "dtypes.h"

#if defined(_OS_WINDOWS_)
#include <malloc.h>
#include <sys/timeb.h>
#include <windows.h>
#else
#include <sys/time.h>
#include <sys/poll.h>
#include <unistd.h>
#endif

#include "timefuncs.h"

#ifdef __cplusplus
extern "C" {
#endif

int jl_gettimeofday(struct jl_timeval *jtv)
{
#if defined(_OS_WINDOWS_)
    struct __timeb64 tb;
    errno_t code = _ftime64_s(&tb);
    jtv->sec = tb.time;
    jtv->usec = tb.millitm * 1000;
#else
    struct timeval now;
    int code = gettimeofday(&now, NULL);
    jtv->sec = now.tv_sec;
    jtv->usec = now.tv_usec;
#endif
    return code;
}

static double jtv2float(struct jl_timeval *jtv)
{
    return (double)jtv->sec + (double)jtv->usec/1.0e6;
}

double clock_now(void)
{
    struct jl_timeval now;
    jl_gettimeofday(&now);
    return jtv2float(&now);
}

void sleep_ms(int ms)
{
    if (ms == 0)
        return;

#if defined(_OS_WINDOWS_)
    Sleep(ms);
#else
    struct timeval timeout;

    timeout.tv_sec = ms / 1000;
    timeout.tv_usec = (ms % 1000) * 1000;

    select(0, NULL, NULL, NULL, &timeout);
#endif
}

#ifdef __cplusplus
}
#endif
