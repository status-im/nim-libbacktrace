/*
* Copyright (c) 2019 Status Research & Development GmbH
* Licensed under either of
*  * Apache License, version 2.0,
*  * MIT license
* at your option.
* This file may not be copied, modified, or distributed except according to
* those terms.
*/

#include <backtrace-supported.h>
#include <backtrace.h>
#include <errno.h>
#include <inttypes.h>
#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libbacktrace_wrapper.h"

// https://stackoverflow.com/a/44383330
#ifdef _WIN32
# ifdef _WIN64
#  define PRI_SIZET PRIu64
# else
#  define PRI_SIZET PRIu32
# endif
#else
# define PRI_SIZET "zu"
#endif

// https://sourceforge.net/p/mingw/mailman/mingw-users/thread/46C99879.8070205@cox.net/
#ifdef __MINGW32__
# define snprintf __mingw_snprintf
#endif

#define ALIGN(v, a)	(((size_t)(v) + (a) - 1) & ~((a) - 1))

// macOS Clang wants this before the WAI_MALLOC define
static void *xmalloc(size_t size)
{
#ifdef _WIN32
	void *res = _aligned_malloc(ALIGN(size, 16), 16);
#else
	void *res = malloc(size);
#endif
	if (res == NULL) {
		fprintf(stderr, "FATAL: malloc() failed to allocate %" PRI_SIZET " bytes.\n", size);
		exit(1);
	}
	return res;
}

void xfree(void *ptr)
{
	if (ptr == NULL) {
		fprintf(stderr, "BUG: xfree() received a NULL pointer.\n");
		return;
	}
#ifdef _WIN32
	_aligned_free(ptr);
#else
	free(ptr);
#endif
}

#define WAI_MALLOC(size) xmalloc(size)
#define WAI_FREE(p) xfree(p)
#include "vendor/whereami/src/whereami.h"
// Yes, this is ugly. Using the Nim compiler as a build system is uglier.
#include "vendor/whereami/src/whereami.c"

// Saw this limit somewhere in the Nim compiler source.
#define MAX_BACKTRACE_LINES 128

#define INITIAL_LINE_SIZE 100
#define DEBUG_ENV_VAR_NAME "NIM_LIBBACKTRACE_DEBUG"
static __thread int debug = 0;

struct callback_data {
	struct backtrace_state *state;
	int bt_lineno;
	int backtrace_line_size; // Buffer size for a single backtrace line. Starts at INITIAL_LINE_SIZE and is doubled when exceeded.
	char *backtrace_lines[MAX_BACKTRACE_LINES];
	int backtrace_line_lengths[MAX_BACKTRACE_LINES]; // Excluding the terminating null byte.
	int nim_main_module_seen; // Did we already see NimMainModule?
};

static __thread struct callback_data cb_data;
// Is this going to be zero in all threads?
static __thread int cb_data_initialised = 0;

static char *xstrdup(const char *s)
{
	size_t len = strlen(s) + 1;
	char *res = (char*)xmalloc(len);
	memcpy(res, s, len);
	return res;
}

static void error_callback(void *data __attribute__ ((__unused__)),
	const char *msg, int errnum)
{
	fprintf(stderr, "libbacktrace error: %s (%d)\n", msg, errnum);
}

static int strings_equal(const char *str1, const char *str2)
{
	if (!str1 || !str2) {
		return 0;
	} else {
		size_t len2 = strlen(str2);
		return strlen(str1) == len2 && strncmp(str1, str2, len2) == 0;
	}
}

#ifdef __cplusplus
# include <cxxabi.h>
#endif // __cplusplus

static char *demangle(const char *function)
{
	if (function == NULL) {
		fprintf(stderr, "demangle() called with a NULL pointer. Aborting.\n");
		exit(1);
	}

	char *res = xstrdup(function);

#ifdef __cplusplus
	// C++ function name demangling.
	size_t demangled_len;
	int status;
	char* demangled = abi::__cxa_demangle(function, NULL, &demangled_len, &status);
	if (demangled && status == 0) {
		demangled[demangled_len] = '\0';
		// Get rid of function parenthesis and params.
		char *par_pos = strchr(demangled, '(');
		if (par_pos)
			*par_pos = '\0';
		xfree(res);
		res = xstrdup(demangled);
		free(demangled);
	}
#endif // __cplusplus

	// Nim demangling.
	char *pos = strstr(res, "__");
	if (pos)
		*pos = '\0';

	return res;
}

static int success_callback(void *data, uintptr_t pc __attribute__((unused)),
	const char *filename, int lineno, const char *function)
{
	// clang++ makes us do all these pointer casts.
	struct callback_data *cbd = (struct callback_data*)data;
	char *backtrace_line = (char*)xmalloc(cbd->backtrace_line_size);
	int output_size; // Excludes the terminating null byte.

	cbd->bt_lineno++;

	if (cbd->bt_lineno == MAX_BACKTRACE_LINES) {
		xfree(backtrace_line);
		return 1; // Stop printing the backtrace.
	}

	if (function == NULL || filename == NULL) {
		if (cbd->bt_lineno == 0)
			fprintf(stderr, "libbacktrace error: no debugging symbols available. Compile with '--debugger:native'.\n");
		xfree(backtrace_line);
		if (debug) {
			cbd->bt_lineno--;
			return 0; // Keep going.
		} else {
			return 1; // Stop printing the backtrace.
		}
	}

	char *demangled_function = demangle(function);

	// skip internal Nim functions
	if ((strings_equal(demangled_function, "NimMainInner") ||
			strings_equal(demangled_function, "NimMain")) &&
				cbd->nim_main_module_seen) {
		/*
		* If we skip them unconditionally, we may end up with an empty
		* backtrace when `-d:release` leads to NimMainModule being
		* inlined.
		*/
		if (!debug) {
			xfree(backtrace_line);
			xfree(demangled_function);
			return 1; // Stop printing the backtrace.
		}
	}

	// these ones appear when we're used inside the Nim compiler
	if (strings_equal(demangled_function, "auxWriteStackTraceWithOverride") ||
			strings_equal(demangled_function, "rawWriteStackTrace") ||
			strings_equal(demangled_function, "writeStackTrace") ||
			strings_equal(demangled_function, "raiseExceptionAux") ||
			strings_equal(demangled_function, "raiseExceptionEx")) {
		if (!debug) {
			xfree(backtrace_line);
			xfree(demangled_function);
			cbd->bt_lineno--;
			return 0; // Skip it, but continue the backtrace.
		}
	}

	if (strings_equal(demangled_function, "NimMainModule")) {
		cbd->nim_main_module_seen = 1;

		// "/foo/bar/test2.nim" -> "test2"
		char *nim_file = xstrdup(filename);
		char *pos = basename(nim_file);
		size_t len = strlen(pos);
		if (len > 4)
			pos[len - 4] = '\0';
		xfree(demangled_function);
		demangled_function = xstrdup(pos);
		xfree(nim_file);
	}

	while(1) {
		// We're mirroring Nim's default stack trace format.
		output_size = snprintf(backtrace_line, cbd->backtrace_line_size,
			"%s(%d) %s\n",
			filename,
			lineno,
			demangled_function);
		if (output_size + 1 <= cbd->backtrace_line_size) {
			break;
		} else {
			cbd->backtrace_line_size *= 2;
			xfree(backtrace_line);
			backtrace_line = (char*)xmalloc(cbd->backtrace_line_size);
		}
	}
	xfree(demangled_function);

	cbd->backtrace_lines[cbd->bt_lineno] = backtrace_line;
	cbd->backtrace_line_lengths[cbd->bt_lineno] = output_size;

	return 0;
}

// The returned string needs to be freed by the caller.
char *get_backtrace_c(void)
{
#ifdef BACKTRACE_SUPPORTED
	if (!cb_data_initialised) {
		cb_data_initialised = 1;

		char *debug_env_var_value = getenv(DEBUG_ENV_VAR_NAME);
		if (strings_equal(debug_env_var_value, "1"))
			debug = 1;

		memset(&cb_data, '\0', sizeof(struct callback_data));

		// Using https://github.com/gpakosz/whereami
		int self_exec_path_length = wai_getExecutablePath(NULL, 0, NULL);
		if (self_exec_path_length == -1)
			return xstrdup("whereami error: could not get the program's path on this platform.\n");
		char *self_exec_path = (char*)xmalloc(self_exec_path_length + 1);
		wai_getExecutablePath(self_exec_path, self_exec_path_length, NULL);
		self_exec_path[self_exec_path_length] = '\0';

		/*
		* We shouldn't initialise this state more than once per thread:
		* https://github.com/ianlancetaylor/libbacktrace/issues/13
		*/
		cb_data.state = backtrace_create_state(self_exec_path, BACKTRACE_SUPPORTS_THREADS, error_callback, NULL);
		cb_data.backtrace_line_size = INITIAL_LINE_SIZE;
		cb_data.bt_lineno = -1;
	}

	if (cb_data.state != NULL) {
		if (debug)
			backtrace_full(cb_data.state, 0, success_callback, error_callback, &cb_data);
		else
			backtrace_full(cb_data.state, 2, success_callback, error_callback, &cb_data);
	} else {
		return xstrdup(""); // The error callback has already been called.
	}

	if (cb_data.bt_lineno == MAX_BACKTRACE_LINES)
		cb_data.bt_lineno--;

	int total_length = 0;
	int i;

	// The Nim tradition wants them in reverse order.
	for (i = cb_data.bt_lineno; i >= 0; i--) {
		if (cb_data.backtrace_lines[i] != NULL)
			total_length += cb_data.backtrace_line_lengths[i];
	}

	char *backtrace = (char*)xmalloc(total_length + 1);
	char *last_null_byte = backtrace;
	*last_null_byte = '\0';

	// Besides producing the string result, we also initialise cb_data for the next run.
	for (i = cb_data.bt_lineno; i >= 0; i--) {
		if (cb_data.backtrace_lines[i] != NULL) {
			last_null_byte = (char*)memccpy(last_null_byte,
					cb_data.backtrace_lines[i],
					'\0',
					cb_data.backtrace_line_lengths[i] + 1) - 1;
			xfree(cb_data.backtrace_lines[i]);
			cb_data.backtrace_lines[i] = NULL;
		}
	}
	cb_data.bt_lineno = -1;

	return backtrace;
#else
	return xstrdup("ERROR: libbacktrace is not supported on this platform.\n");
#endif // BACKTRACE_SUPPORTED
}

