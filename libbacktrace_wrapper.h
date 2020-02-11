/*
* Copyright (c) 2019 Status Research & Development GmbH
* Licensed under either of
*  * Apache License, version 2.0,
*  * MIT license
* at your option.
* This file may not be copied, modified, or distributed except according to
* those terms.
*/

#ifndef LIBBACKTRACE_WRAPPER_H
#define LIBBACKTRACE_WRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

// The returned string needs to be freed by the caller.
char *get_backtrace_c(void) __attribute__((noinline));

void xfree(void *ptr);

#ifdef __cplusplus
} // extern "C"
#endif

#endif

