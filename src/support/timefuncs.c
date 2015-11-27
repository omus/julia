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

#if defined(_OS_WINDOWS_)
JL_DLLEXPORT int gettimeofday(struct timeval *tv, void *tzp)
{
    struct _timeb tb;
    errno_t code = _ftime_s(&tb);
    tv->tv_sec = tb.time;
    tv->tv_usec = tb.millitm * 1000;
    return code;
}
#endif

double clock_now(void)
{
    struct timeval now;
    gettimeofday(&now, NULL);
    return now.tv_sec + now.tv_usec/1.0e6;
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
