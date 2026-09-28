// LD_PRELOAD shim that moves the wall clock forward by SHIFT_SECONDS while
// leaving the monotonic clock alone, so timers and Stopwatch behave normally.
// Used by run.sh to find tests that compare recorded expiry times with "now"
// (docs/modules/M4.U time-bomb audit, 2026-09-29).
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <sys/time.h>
#include <time.h>

static long long offset = -1;

static long long shift(void) {
  if (offset < 0) {
    const char *value = getenv("SHIFT_SECONDS");
    offset = value ? atoll(value) : 0;
  }
  return offset;
}

typedef int (*clock_gettime_t)(clockid_t, struct timespec *);

int clock_gettime(clockid_t id, struct timespec *ts) {
  static clock_gettime_t real = 0;
  if (!real) real = (clock_gettime_t)dlsym(RTLD_NEXT, "clock_gettime");
  int result = real(id, ts);
  if (result == 0 && (id == CLOCK_REALTIME || id == CLOCK_REALTIME_COARSE)) ts->tv_sec += shift();
  return result;
}

typedef int (*gettimeofday_t)(struct timeval *, void *);

int gettimeofday(struct timeval *tv, void *tz) {
  static gettimeofday_t real = 0;
  if (!real) real = (gettimeofday_t)dlsym(RTLD_NEXT, "gettimeofday");
  int result = real(tv, tz);
  if (result == 0 && tv) tv->tv_sec += shift();
  return result;
}

time_t time(time_t *out) {
  struct timeval tv;
  gettimeofday(&tv, 0);
  if (out) *out = tv.tv_sec;
  return tv.tv_sec;
}
