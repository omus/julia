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
int gettimeofday(struct timeval *tv, void *tz)
{
    struct timeb tb;
    int status = ftime(&tb);
    if (status == 0) {
        now->tv_sec = tb.time;
        now->tv_usec = tb.millitm * 1e3;
    }
    return status;
}
#endif

static double tv2float(struct timeval *tv)
{
    return (double)tv->tv_sec + (double)tv->tv_usec/1.0e6;
}

int timeval_now(struct timeval *now)
{
    return gettimeofday(now, NULL);
}

double clock_now(void)
{
    struct timeval now;
    timeval_now(&now);
    return tv2float(&now);
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
