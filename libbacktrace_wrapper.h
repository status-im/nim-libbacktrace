/*
* Copyright (c) 2019 Status Research & Development GmbH
* Licensed under either of
*  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
*  * MIT license ([LICENSE-MIT](LICENSE-MIT))
* at your option.
* This file may not be copied, modified, or distributed except according to
* those terms.
*/

#ifndef LIBBACKTRACE_WRAPPER_H
#define LIBBACKTRACE_WRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

char *get_backtrace_c(void) __attribute__((noinline));

#ifdef __cplusplus
} // extern "C"
#endif

#endif

