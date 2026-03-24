# Copyright (c) 2019-2024 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0,
#  * MIT license
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

## This file contains the API of the subset of libbacktrace that is useful to us

{.pragma: capi, cdecl, raises: [], gcsafe.}

when defined(nimStackTraceOverride) and defined(nimHasStacktracesModule):
  import system/stacktraces

when not declared(cuintptr_t):
  # There is a disparity on macOS where Nim's `uint` is `unsigned long long` and
  # `uintptr_t` is `unsigned long`. Even though both data types are the same
  # size (64 bits), clang++ refuses to do automatic conversion between them.
  type cuintptr_t* {.importc: "uintptr_t", nodecl.} = uint

type
  BacktraceState* = distinct pointer

  BacktraceErrorCallback* = proc(data: pointer, msg: cstring, errnum: cint) {.capi.}
    ##[
   The type of the error callback argument to backtrace functions.
   This function, if not NULL, will be called for certain error cases.
   The DATA argument is passed to the function that calls this one.
   The MSG argument is an error message.  The ERRNUM argument, if
   greater than 0, holds an errno value.  The MSG buffer may become
   invalid after this function returns.

   As a special case, the ERRNUM argument will be passed as -1 if no
   debug info can be found for the executable, or if the debug info
   exists but has an unsupported version, but the function requires
   debug info (e.g., backtrace_full, backtrace_pcinfo).  The MSG in
   this case will be something along the lines of "no debug info".
   Similarly, ERRNUM will be passed as -1 if there is no symbol table,
   but the function requires a symbol table (e.g., backtrace_syminfo).
   This may be used as a signal that some other approach should be
   tried.
   ]##

  BacktraceFullCallback* = proc(
    data: pointer, pc: cuintptr_t, filename: cstring, lineno: cint, function: cstring
  ): cint {.capi.}

  BacktraceSimpleCallback* = proc(data: pointer, pc: cuintptr_t): cint {.capi.}

  BacktraceSyminfoCallback* = proc(
    data: pointer,
    pc: cuintptr_t,
    symname: cstring,
    symval: cuintptr_t,
    symsize: cuintptr_t,
  ) {.capi.}

proc backtrace_create_state*(
  filename: cstring,
  threaded: cint,
  error_callback: BacktraceErrorCallback,
  data: pointer,
): BacktraceState {.importc, capi.}
  ##[
   Create state information for the backtrace routines.  This must be
   called before any of the other routines, and its return value must
   be passed to all of the other routines.  FILENAME is the path name
   of the executable file; if it is NULL the library will try
   system-specific path names.  If not NULL, FILENAME must point to a
   permanent buffer.  If THREADED is non-zero the state may be
   accessed by multiple threads simultaneously, and the library will
   use appropriate atomic operations.  If THREADED is zero the state
   may only be accessed by one thread at a time.  This returns a state
   pointer on success, NULL on error.  If an error occurs, this will
   call the ERROR_CALLBACK routine.

   Calling this function allocates resources that cannot be freed.
   There is no backtrace_free_state function.  The state is used to
   cache information that is expensive to recompute.  Programs are
   expected to call this function at most once and to save the return
   value for all later calls to backtrace functions.  */
  ]##

proc backtrace_simple*(
  state: BacktraceState,
  skip: cint,
  callback: BacktraceSimpleCallback,
  error_callback: BacktraceErrorCallback,
  data: pointer,
): cint {.importc, capi.}
  ##[
   Get a simple backtrace.  SKIP is the number of frames to skip, as
   in backtrace.  DATA is passed to the callback routine.  If any call
   to CALLBACK returns a non-zero value, the stack backtrace stops,
   and backtrace_simple returns that value.  Otherwise
   backtrace_simple returns 0.  The backtrace_simple function will
   make at least one call to either CALLBACK or ERROR_CALLBACK.  This
   function does not require any debug info for the executable.
  ]##

proc backtrace_pcinfo*(
  state: BacktraceState,
  pc: cuintptr_t,
  callback: BacktraceFullCallback,
  error_callback: BacktraceErrorCallback,
  data: pointer,
): cint {.importc, capi.}
  ##[
   Given PC, a program counter in the current program, call the
   callback function with filename, line number, and function name
   information.  This will normally call the callback function exactly
   once.  However, if the PC happens to describe an inlined call, and
   the debugging information contains the necessary information, then
   this may call the callback function multiple times.  This will make
   at least one call to either CALLBACK or ERROR_CALLBACK.  This
   returns the first non-zero value returned by CALLBACK, or 0.
  ]##

proc backtrace_syminfo*(
  state: BacktraceState,
  address: cuintptr_t,
  callback: BacktraceSyminfoCallback,
  error_callback: BacktraceErrorCallback,
  data: pointer,
): cint {.importc, capi.}
  ##[
   Given ADDR, an address or program counter in the current program,
   call the callback information with the symbol name and value
   describing the function or variable in which ADDR may be found.
   This will call either CALLBACK or ERROR_CALLBACK exactly once.
   This returns 1 on success, 0 on failure.  This function requires
   the symbol table but does not require the debug info.  Note that if
   the symbol table is present but ADDR could not be found in the
   table, CALLBACK will be called with a NULL SYMNAME argument.
   Returns 1 on success, 0 on error.
  ]##
