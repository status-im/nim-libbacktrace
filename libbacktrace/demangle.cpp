/*
 * Copyright (c) 2019-2026 Status Research & Development GmbH
 * Licensed under either of
 *  * Apache License, version 2.0,
 *  * MIT license
 * at your option.
 * This file may not be copied, modified, or distributed except according to
 * those terms.
 */

/* Demangler based on cxxabi, avaliable from GCC/clang at least */

#include <cxxabi.h>
#include <string.h>

/**
  Return the demangled version of `function` with the caller responsible for
  deallocating the string with `free`.

  Returns NULL if `function` is NULL.
*/
extern "C" {
char *libbacktrace_demangler(const char *function) {
  if (function == NULL)
    return NULL;

  char *res;
  int status;
  char *demangled = abi::__cxa_demangle(function, NULL, NULL, &status);
  if (demangled && status == 0) {
    res = demangled;
  } else {
    // Nim function mangling?
    res = strdup(function);
  }

  return res;
}
}
