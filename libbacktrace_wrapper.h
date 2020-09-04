/*
 * Copyright (c) 2019-2020 Status Research & Development GmbH
 * Licensed under either of
 *  * Apache License, version 2.0,
 *  * MIT license
 * at your option.
 * This file may not be copied, modified, or distributed except according to
 * those terms.
 */

#ifndef LIBBACKTRACE_WRAPPER_H
#define LIBBACKTRACE_WRAPPER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// The returned string needs to be freed by the caller.
char *get_backtrace_max_length_c(int max_length, int skip) __attribute__((noinline));

// The returned string needs to be freed by the caller.
char *get_backtrace_c(void) __attribute__((noinline));

/*
 * The returned array needs to be freed by the caller.
 * It holds at least a zero sentinel value at the end.
 */
uintptr_t *get_program_counters_c(int max_length, int skip) __attribute__((noinline));

struct debugging_info {
	char *filename;
	int lineno;
	char *function;
};

/*
 * The returned array needs to be freed by the caller.
 * Char pointers in the returned structs need to be freed by the caller.
 */
struct debugging_info *get_debugging_info_c(uintptr_t *program_counters, int max_length);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // LIBBACKTRACE_WRAPPER_H

