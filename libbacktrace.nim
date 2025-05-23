# Copyright (c) 2019-2024 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0,
#  * MIT license
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

when not compileOption("debuginfo"):
  stderr.write("libbacktrace error: no debugging symbols available. Compile with '--debugger:native'.\n")
  stderr.flushFile()

when defined(nimStackTraceOverride) and defined(nimHasStacktracesModule):
  import system/stacktraces

# Don't warn that this module is unused (e.g.: when the Nim compiler supports it
# and users need to import it, even if they don't call getBacktrace() manually).
{.used.}

# There is no "copyMem()" in Nimscript, so "getBacktrace()" will not work in
# there, but we might still want to import this module with a global
# "--import:libbacktrace" Nim compiler flag.
when not (defined(nimscript) or defined(js)):
  import std/algorithm, libbacktrace/wrapper, std/os, system/ansi_c, std/strutils

  const
    topLevelPath = currentSourcePath.parentDir().replace('\\', '/')
    installPath = topLevelPath & "/install/usr"

  {.passc: "-I" & escape(topLevelPath).}

  when defined(cpp):
    {.passl: escape(installPath & "/lib/libbacktracenimcpp.a").}
  else:
    {.passl: escape(installPath & "/lib/libbacktracenim.a").}

  when defined(libbacktraceUseSystemLibs):
    {.passl: "-lbacktrace".}
  else:
    {.passc: "-I" & escape(installPath & "/include").}
    {.passl: escape(installPath & "/lib/libbacktrace.a").}

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
    registerStackTraceOverride(libbacktrace.getBacktrace)

  proc getProgramCounters*(maxLength: cint): seq[cuintptr_t] {.noinline.} =
    var
      length {.noinit.}: cint
      pcPtr = get_program_counters_c(maxLength, addr length, skip = 2)
      iPtr = pcPtr

    result = newSeqOfCap[cuintptr_t](length)
    for i in 0 ..< length:
      if iPtr[] == 0:
        break
      result.add(iPtr[])
      iPtr = cast[ptr cuintptr_t](cast[uint](iPtr) + sizeof(cuintptr_t).uint)

    c_free(pcPtr)

  when defined(nimStackTraceOverride) and declared(registerStackTraceOverrideGetProgramCounters):
    registerStackTraceOverrideGetProgramCounters(libbacktrace.getProgramCounters)

  proc getDebuggingInfo*(
      programCounters: seq[cuintptr_t],
      maxLength: cint): seq[StackTraceEntry] {.noinline.} =
    doAssert programCounters.len <= cint.high

    if programCounters.len == 0:
      return @[]

    var
      length {.noinit.}: cint
      functionInfoPtr = get_debugging_info_c(  # Nim 1.6 needs `unsafeAddr`
        unsafeAddr programCounters[0], programCounters.len.cint,
        maxLength, addr length)
      iPtr = functionInfoPtr
      res: StackTraceEntry

    result = newSeqOfCap[StackTraceEntry](length.int)
    for i in 0 ..< length:
      if iPtr[].filename == nil:
        break

      # Older stdlib doesn't have this field in "StackTraceEntry".
      when compiles(res.filenameStr):
        let filenameLen = len(iPtr[].filename)
        res.filenameStr = newString(filenameLen)
        if filenameLen > 0:
          copyMem(addr(res.filenameStr[0]), iPtr[].filename, filenameLen)
        res.filename = cstring res.filenameStr

      res.line = iPtr[].lineno

      when compiles(res.procnameStr):
        let functionLen = len(iPtr[].function)
        res.procnameStr = newString(functionLen)
        if functionLen > 0:
          copyMem(addr(res.procnameStr[0]), iPtr[].function, functionLen)
        res.procname = cstring res.procnameStr

      result.add(res)

      c_free(iPtr[].filename)
      c_free(iPtr[].function)
      iPtr = cast[ptr DebuggingInfo](
        cast[uint](iPtr) + sizeof(DebuggingInfo).uint)

    c_free(functionInfoPtr)

    # Nim convention.
    reverse(result)

  when defined(nimStackTraceOverride) and declared(registerStackTraceOverrideGetDebuggingInfo):
    registerStackTraceOverrideGetDebuggingInfo(libbacktrace.getDebuggingInfo)
