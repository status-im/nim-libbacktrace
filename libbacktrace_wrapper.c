/*
 * Copyright (c) 2019-2024 Status Research & Development GmbH
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

// macOS Clang wants this before the WAI_MALLOC define
static void *xmalloc(size_t size)
{
	void *res = malloc(size);
	if (res == NULL) {
		fprintf(stderr, "FATAL: malloc() failed to allocate %" PRI_SIZET " bytes.\n", size);
		exit(1);
	}
	return res;
}

static void xfree_inner(void **ptr)
{
	if (ptr == NULL) {
		fprintf(stderr, "FATAL: xfree_inner() was called with a NULL pointer.\n");
		exit(1);
	} else {
		free(*ptr);
		*ptr = NULL;
	}
}
#define xfree(ptr) xfree_inner((void**) &ptr)

#define WAI_MALLOC(size) xmalloc(size)
#include "vendor/whereami/src/whereami.h"
// Yes, this is ugly. Using the Nim compiler as a build system is uglier.
#include "vendor/whereami/src/whereami.c"

// Saw this limit somewhere in the Nim compiler source.
#define MAX_BACKTRACE_LINES 128

#define INITIAL_LINE_SIZE 100
#define DEBUG_ENV_VAR_NAME "NIM_LIBBACKTRACE_DEBUG"
static __thread int debug = 0;

struct callback_data {
	struct debugging_info *di_data;
	int next_index;
	int max_length;
	int nim_main_module_seen; // Did we already see NimMainModule?
};

struct simple_callback_data {
	uintptr_t *program_counters;
	int next_index;
	int max_length;
};

static __thread struct backtrace_state *state;
// Is this going to be zero in all threads?
static __thread int cb_data_initialised = 0;

static char *xstrdup(const char *s)
{
	char *res = strdup(s);
	if (res == NULL) {
		fprintf(stderr, "FATAL: strdup() failure.\n");
		exit(1);
	}
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

static int string_starts_with(const char *str1, const char *str2)
{
	if (!str1 || !str2) {
		return 0;
	} else {
		size_t len2 = strlen(str2);
		return strlen(str1) >= len2 && strncmp(str1, str2, len2) == 0;
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
		res = demangled;
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
	struct callback_data *cb_data = (struct callback_data*) data;

	if (cb_data->next_index >= cb_data->max_length)
		return 1; // Stop building the backtrace.

	if (function == NULL || filename == NULL) {
		// see https://github.com/status-im/nim-libbacktrace/issues/9, we need to keep going here.
		return 0;
	}

	char *demangled_function = demangle(function);

	// skip internal Nim functions
	if ((strings_equal(demangled_function, "NimMainInner") ||
			strings_equal(demangled_function, "NimMain") ||
			strings_equal(demangled_function, "main")) &&
				cb_data->nim_main_module_seen) {
		/*
		 * If we skip them unconditionally, we may end up with an empty
		 * backtrace when `-d:release` leads to NimMainModule being
		 * inlined.
		 */
		if (!debug) {
			xfree(demangled_function);
			return 1; // Stop building the backtrace.
		}
	}

	// these ones appear when we're used inside the Nim compiler
	if (strings_equal(demangled_function, "auxWriteStackTraceWithOverride") ||
			strings_equal(demangled_function, "rawWriteStackTrace") ||
			strings_equal(demangled_function, "writeStackTrace") ||
			strings_equal(demangled_function, "raiseExceptionAux") ||
			string_starts_with(demangled_function, "raiseExceptionEx")) {
		if (!debug) {
			xfree(demangled_function);
			return 0; // Skip it, but continue the backtrace.
		}
	}

	// Replace "NimMainModule" with the file name (minus the extension).
	if (strings_equal(demangled_function, "NimMainModule")) {
		cb_data->nim_main_module_seen = 1;

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

	cb_data->di_data[cb_data->next_index].filename = xstrdup(filename);
	cb_data->di_data[cb_data->next_index].lineno = lineno;
	cb_data->di_data[cb_data->next_index].function = demangled_function;

	cb_data->next_index++;

	return 0;
}

static int simple_success_callback(void *data, uintptr_t pc)
{
	struct simple_callback_data *scb_data = (struct simple_callback_data*)data;
	if (scb_data->next_index >= scb_data->max_length) {
		return 1; // stop traversing the stack
	} else {
		scb_data->program_counters[scb_data->next_index] = pc;
		scb_data->next_index++;
		return 0; // continue traversing the stack
	}
}

static char *internal_init(void)
{
	if (!cb_data_initialised) {
		cb_data_initialised = 1;

		char *debug_env_var_value = getenv(DEBUG_ENV_VAR_NAME);
		if (strings_equal(debug_env_var_value, "1"))
			debug = 1;

		// Using https://github.com/gpakosz/whereami
		int self_exec_path_length = wai_getExecutablePath(NULL, 0, NULL);
		if (self_exec_path_length == -1)
			return xstrdup("whereami error: could not get the program's path on this platform.\n");
		char *self_exec_path = (char*) xmalloc(self_exec_path_length + 1);
		wai_getExecutablePath(self_exec_path, self_exec_path_length, NULL);
		self_exec_path[self_exec_path_length] = '\0';

		/*
		 * We shouldn't initialise this state more than once per thread:
		 * https://github.com/ianlancetaylor/libbacktrace/issues/13
		 */
		state = backtrace_create_state(self_exec_path, 0, error_callback, NULL);
	}

	return xstrdup("");
}

// The returned array needs to be freed by the caller.
uintptr_t *get_program_counters_c(
	int max_program_counters, int *num_program_counters, int skip)
{
	if (!num_program_counters) {
		fprintf(stderr, "FATAL: get_program_counters_c called with NULL argument.\n");
		exit(1);
	}
	*num_program_counters = 0;
	size_t program_counters_size = sizeof(uintptr_t) * max_program_counters;
	uintptr_t *program_counters = (uintptr_t*) xmalloc(program_counters_size);

#ifdef BACKTRACE_SUPPORTED
	char *err = internal_init();
	if (!strings_equal(err , "")) {
		error_callback(NULL, err, 0);
		xfree(err);
		return program_counters;
	}
	xfree(err);

	// Get the program counters.
	if (state != NULL) {
		struct simple_callback_data scb_data = {program_counters, 0, max_program_counters};
		backtrace_simple(state, skip, simple_success_callback, error_callback, &scb_data);
		*num_program_counters = scb_data.next_index;
	}
#endif // BACKTRACE_SUPPORTED

	return program_counters;
}

// The returned array needs to be freed by the caller.
struct debugging_info *get_debugging_info_c(
	const uintptr_t *program_counters, int num_program_counters,
	int max_debugging_infos, int *num_debugging_infos)
{
	if (!num_debugging_infos) {
		fprintf(stderr, "FATAL: get_debugging_info_c called with NULL argument.\n");
		exit(1);
	}
	*num_debugging_infos = 0;
	size_t di_data_size = sizeof(struct debugging_info) * max_debugging_infos;
	struct debugging_info *di_data = (struct debugging_info*) xmalloc(di_data_size);

#ifdef BACKTRACE_SUPPORTED
	char *err = internal_init();
	if (!strings_equal(err , "")) {
		xfree(err);
		return di_data;
	}
	xfree(err);

	if (state != NULL) {
		struct callback_data cb_data;
		memset(&cb_data, '\0', sizeof(struct callback_data));
		cb_data.di_data = di_data;
		cb_data.max_length = max_debugging_infos;
		for (int i = 0; i < num_program_counters && program_counters[i] != 0; i++) {
			/*
			* "success_callback()" may be called multiple times for the
			* same program counter, if inlined functions are involved.
			*/
			int res = backtrace_pcinfo(state, program_counters[i],
				success_callback, error_callback, &cb_data);

			// We stop when the callback decided to skip something.
			if (res != 0)
				break;
		}
		*num_debugging_infos = cb_data.next_index;
	}
#endif // BACKTRACE_SUPPORTED

	return di_data;
}

// The returned string needs to be freed by the caller.
char *get_backtrace_max_length_c(int max_length, int skip)
{
#ifdef BACKTRACE_SUPPORTED
	char *err = internal_init();
	if (!strings_equal(err , "") || !state)
		return err;
	xfree(err);

	if (state != NULL) {
		char **backtrace_lines = (char**) xmalloc(sizeof(char*) * max_length);
		int *backtrace_line_lengths = (int*) xmalloc(sizeof(int) * max_length);
		int total_length = 0;

		// Get the program counters.
		int skip_functions = 0;
		if (!debug)
			skip_functions = skip;

		int num_program_counters;
		uintptr_t *program_counters = get_program_counters_c(
			max_length, &num_program_counters, skip_functions);

		/*
		 * Get the filename, line number and function name for each
		 * program counter. In the case of inlined functions, we may
		 * get multiple hits from DWARF metadata for the same program
		 * counter. That's OK, we want those.
		 */
		int num_debugging_infos;
		struct debugging_info *di_data = get_debugging_info_c(
			program_counters, num_program_counters,
			max_length, &num_debugging_infos);
		xfree(program_counters);

		// String building.
		int backtrace_line_size = INITIAL_LINE_SIZE;
		int i;
		for (i = 0; i < num_debugging_infos && di_data[i].filename != NULL; i++) {
			int output_size; // Excludes the terminating null byte.
			char *backtrace_line = (char*) xmalloc(backtrace_line_size);
			while (1) {
				// We're mirroring Nim's default stack trace format.
				output_size = snprintf(backtrace_line, backtrace_line_size,
					"%s(%d) %s\n",
					di_data[i].filename,
					di_data[i].lineno,
					di_data[i].function);
				if (output_size < 0) {
					fprintf(stderr, "FATAL: snprintf failed unexpectedly: %d.\n", output_size);
					exit(1);
				} else if (output_size < backtrace_line_size) {
					break;
				} else {
					xfree(backtrace_line);
					backtrace_line_size *= 2;
					backtrace_line = (char*) xmalloc(backtrace_line_size);
				}
			}
			backtrace_lines[i] = backtrace_line;
			backtrace_line_lengths[i] = output_size;
			total_length += output_size;
		}

		char *backtrace = (char*) xmalloc(total_length + 1);
		char *bt = backtrace;

		// Produce the string result.
		// The Nim tradition wants them in reverse order.
		while (--i >= 0) {
			memcpy(bt, backtrace_lines[i], backtrace_line_lengths[i]);
			bt += backtrace_line_lengths[i];
			xfree(backtrace_lines[i]);
		}
		*bt = '\0';

		// Cleanup.
		xfree(backtrace_lines);
		xfree(backtrace_line_lengths);

		return backtrace;
	} else {
		return xstrdup(""); // The error callback has already been called.
	}
#else // BACKTRACE_SUPPORTED
	return xstrdup("ERROR: libbacktrace is not supported on this platform.\n");
#endif // BACKTRACE_SUPPORTED
}

// The returned string needs to be freed by the caller.
char *get_backtrace_c(void)
{
	return get_backtrace_max_length_c(MAX_BACKTRACE_LINES, 3);
}
