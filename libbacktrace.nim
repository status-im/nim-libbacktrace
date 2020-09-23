# Copyright (c) 2019-2020 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0,
#  * MIT license
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

when defined(nimStackTraceOverride) and defined(nimHasStacktracesModule):
  import system/stacktraces

# Don't warn that this module is unused (e.g.: when the Nim compiler supports it
# and users need to import it, even if they don't call getBacktrace() manually).
{.used.}

# There is no "copyMem()" in Nimscript, so "getBacktrace()" will not work in
# there, but we might still want to import this module with a global
# "--import:libbacktrace" Nim compiler flag.
when not (defined(nimscript) or defined(js)):
  import algorithm, libbacktrace_wrapper, os, system/ansi_c

  const installPath = currentSourcePath.parentDir() / "install" / "usr"

  {.passc: "-I" & currentSourcePath.parentDir().}

  when defined(cpp):
    {.passl: installPath / "lib" / "libbacktracenimcpp.a".}
  else:
    {.passl: installPath / "lib" / "libbacktracenim.a".}

  when defined(libbacktraceUseSystemLibs):
    {.passl: "-lbacktrace".}
    when defined(macosx) or defined(windows):
      {.passl: "-lunwind".}
  else:
    {.passc: "-I" & installPath / "include".}
    {.passl: installPath / "lib" / "libbacktrace.a".}
    when defined(macosx) or defined(windows):
      {.passl: installPath / "lib" / "libunwind.a".}

  when defined(windows):
    {.passl: "-lpsapi".}

  proc getBacktrace*(): string {.noinline.} =
    let
      # bt: cstring = get_backtrace_c()
      bt: cstring = get_backtrace_max_length_c(max_length = 128, skip = 3)
      btLen = len(bt)

    result = newString(btLen)
    if btLen > 0:
      copyMem(addr(result[0]), bt, btLen)
    c_free(bt)

  when defined(nimStackTraceOverride) and declared(registerStackTraceOverride):
    registerStackTraceOverride(getBacktrace)

  proc getProgramCounters*(maxLength: cint): seq[cuintptr_t] {.noinline.} =
    result = newSeqOfCap[cuintptr_t](maxLength)

    var
      pcPtr = get_program_counters_c(max_length = maxLength, skip = 2)
      iPtr = pcPtr

    while iPtr[] != 0:
      result.add(iPtr[])
      iPtr = cast[ptr cuintptr_t](cast[uint](iPtr) + sizeof(cuintptr_t).uint)

    c_free(pcPtr)

  when defined(nimStackTraceOverride) and declared(registerStackTraceOverrideGetProgramCounters):
    registerStackTraceOverrideGetProgramCounters(getProgramCounters)

  proc getDebuggingInfo*(programCounters: seq[cuintptr_t], maxLength: cint): seq[StackTraceEntry] {.noinline.} =
    result = newSeqOfCap[StackTraceEntry](maxLength)
    if programCounters.len == 0:
      return

    var
      functionInfoPtr = get_debugging_info_c(unsafeAddr programCounters[0], maxLength)
      iPtr = functionInfoPtr
      res: StackTraceEntry

    while iPtr[].filename != nil:
      # Older stdlib doesn't have this field in "StackTraceEntry".
      when compiles(res.filenameStr):
        let filenameLen = len(iPtr[].filename)
        res.filenameStr = newString(filenameLen)
        if filenameLen > 0:
          copyMem(addr(res.filenameStr[0]), iPtr[].filename, filenameLen)
        res.filename = res.filenameStr

      res.line = iPtr[].lineno

      when compiles(res.procnameStr):
        let functionLen = len(iPtr[].function)
        res.procnameStr = newString(functionLen)
        if functionLen > 0:
          copyMem(addr(res.procnameStr[0]), iPtr[].function, functionLen)
        res.procname = res.procnameStr

      c_free(iPtr[].filename)
      c_free(iPtr[].function)

      iPtr = cast[ptr DebuggingInfo](cast[uint](iPtr) + sizeof(DebuggingInfo).uint)
      result.add(res)

    c_free(functionInfoPtr)

    # Nim convention.
    reverse(result)

  when defined(nimStackTraceOverride) and declared(registerStackTraceOverrideGetDebuggingInfo):
    registerStackTraceOverrideGetDebuggingInfo(getDebuggingInfo)

