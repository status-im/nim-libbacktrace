# Copyright (c) 2019-2026 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0,
#  * MIT license
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

## Stack traces based on https://github.com/ianlancetaylor/libbacktrace
##
## Errata:
## https://github.com/nim-lang/Nim/pull/25313 (< 2.2.8)

# Don't warn that this module is unused (e.g.: when the Nim compiler supports it
# and users need to import it, even if they don't call getBacktrace() manually).
{.used.}

# There is no "copyMem()" in Nimscript, so "getBacktrace()" will not work in
# there, but we might still want to import this module with a global
# "--import:libbacktrace" Nim compiler flag.
when not (defined(nimscript) or defined(js)):
  when defined(nimStackTraceOverride) and defined(nimHasStacktracesModule):
    when not compileOption("debuginfo"):
      {.
        warning:
          "libbacktrace: no debugging symbols available. Compile with '--debugger:native'.\n"
      .}

    import system/stacktraces
  else:
    {.
      hint:
        "Without -d:nimStackTraceOverride, results from getStacktrace must be manually deallocated"
    .}

  import
    system/ansi_c, std/[algorithm, compilesettings, os, strutils], libbacktrace/wrapper

  const
    libbacktraceDemangle {.booldefine.} = true
      ## Enabling demangling causes a dependency on the C++, for demangling

    libbacktraceUseSystemLibs {.booldefine.} = false
      ## Use the system-wide installation of libbacktrace by linking to `-lbacktrace`

  when libbacktraceUseSystemLibs:
    {.passl: "-lbacktrace".}
  else:
    import libbacktrace/build

  when libbacktraceDemangle and (not (defined(windows) and sizeof(int) == 4)):
    {.compile: "libbacktrace/demangle.cpp".}

    proc libbacktrace_demangler(name: cstring): cstring {.importc.}

  when not defined(nimStackTraceOverride):
    proc c_strdup(v: cstring): cstring {.importc: "strdup", header: "string.h".}

  when defined(windows):
    {.passl: "-lpsapi".}

  var state = backtrace_create_state(cstring(getAppFileName()), 1, nil, nil)

  proc error(data: pointer, msg: cstring, errnum: cint) {.cdecl.} =
    c_fprintf(cstderr, "backtrace: %s (%d)\n", msg, errnum)

  proc getProgramCounters*(maxLength: cint): seq[cuintptr_t] {.noinline.} =
    ## Capture the current stack trace up to `maxLength` depth
    result.setLen(maxLength.int)

    type SimpleData = tuple[v: ptr UncheckedArray[cuintptr_t], n: cuint, maxlen: cuint]
    var data: SimpleData =
      (cast[ptr UncheckedArray[cuintptr_t]](addr result[0]), 0, cuint maxLength)
    proc callback(data: pointer, pc: cuintptr_t): cint {.cdecl.} =
      let data = cast[ptr SimpleData](data)
      if data.n == data.maxlen:
        1
      else:
        data.v[data.n] = pc
        data.n += 1
        0

    if backtrace_simple(state, 2, callback, error, addr data) == 0:
      result.setLen(data.n.int)
    else:
      result.reset()

  when not declared(c_strstr):
    # nim < 2.2.2
    proc c_strstr*(
      haystack, needle: cstring
    ): cstring {.importc: "strstr", header: "<string.h>", noSideEffect.}

  when defined(nimStackTraceOverride) and
      declared(registerStackTraceOverrideGetProgramCounters):
    registerStackTraceOverrideGetProgramCounters(libbacktrace.getProgramCounters)

  proc setProcName(entry: ptr StackTraceEntry, function: cstring) =
    const projectName = querySetting(SingleValueSetting.projectName)
    when compiles(entry[].procnameStr):
      let function =
        if c_strstr(function, "NimMainModule") != nil:
          projectName
        else:
          # 32-bit windows does not ship a demangler in our tests!
          when declared(libbacktrace_demangler):
            let sn = libbacktrace_demangler(function)
            let res = $sn
            c_free(sn)
            res
          else:
            $function

      entry[].procnameStr = function
      entry[].procname = cstring(entry[].procnameStr)
    else:
      # symname must be deallocated manually by the caller (!)
      let function =
        if c_strstr(function, "NimMainModule") != nil:
          c_strdup(cstring(projectName))
        else:
          when declared(libbacktrace_demangler):
            libbacktrace_demangler(function)
          else:
            c_strdup(function)

      entry[].procname = function

  proc getDebuggingInfo*(
      programCounters: seq[cuintptr_t], maxLength: cint
  ): seq[StackTraceEntry] {.noinline.} =
    ## Translate a set of program counters into stacktrace entries. The returned
    ## sequence may be longer than the input if the debug information contains
    ## inlining information.
    ##
    ## If `-d:nimStacktraceOverride` is not enabled, you are responsible for
    ## freeing `filename` nad `procname` with `c_free`.
    result.setLen(maxLength)

    type PcData =
      tuple[v: ptr UncheckedArray[StackTraceEntry], n: cuint, maxlen: cuint, done: bool]

    var data: PcData = (
      cast[ptr UncheckedArray[StackTraceEntry]](addr result[0]),
      0,
      cuint maxLength,
      false,
    )

    proc symInfo(
        data: pointer,
        pc: cuintptr_t,
        symname: cstring,
        symval: cuintptr_t,
        symsize: cuintptr_t,
    ) {.cdecl.} =
      let entry = cast[ptr StackTraceEntry](data)
      if symname == nil or symname[0] == '\0':
        when compiles(entry[].procnameStr):
          entry[].procnameStr = toHex(pc)
          entry[].procname = cstring(entry[].procnameStr)
        else:
          entry[].procname = c_strdup(cstring(toHex(pc)))
      else:
        setProcName(entry, symname)

    proc pcInfo(
        data: pointer,
        pc: cuintptr_t,
        filename: cstring,
        lineno: cint,
        function: cstring,
    ): cint {.cdecl.} =
      let data = cast[ptr PcData](data)
      if data.done or data.n == data.maxlen:
        return
      let entry = addr data.v[data.n]
      data.n += 1

      if function == nil or function[0] == '\0':
        when compiles(entry[].procnameStr):
          entry[].procnameStr = toHex(pc)
          entry[].procname = cstring(entry[].procnameStr)
        else:
          entry[].procname = c_strdup(cstring(toHex(pc)))
      else:
        const skipped = [
          cstring "writeStackTrace", "rawWriteStackTrace",
          "auxWriteStackTraceWithOverride", "rawWriteStackTrace", "raiseExceptionEx",
        ]
        for v in skipped:
          if c_strstr(function, v) != nil:
            return

        if c_strstr(function, "NimMainModule") != nil:
          data.done = true

        setProcName(entry, function)

      if filename != nil and filename[0] != '\0':
        when compiles(entry[].filenameStr):
          entry[].filenameStr = $filename
          entry[].filename = cstring(entry[].filenameStr)
        else:
          entry[].filename = c_strdup(filename)

        entry[].line = lineno.int

    for pc in programCounters:
      if backtrace_pcinfo(state, pc, pcInfo, error, addr data) != 0:
        break

    result.setLen(data.n.int)

    # Nim convention.
    reverse(result)

  when defined(nimStackTraceOverride) and
      declared(registerStackTraceOverrideGetDebuggingInfo):
    registerStackTraceOverrideGetDebuggingInfo(libbacktrace.getDebuggingInfo)

  proc getBacktrace*(): string {.noinline.} =
    ## Get a formatted backtrace    of the current call stack - for more control,
    ## use `getProgramCounters` and `getDebuggingInfo`.

    result = newStringOfCap(2048)

    let
      pcs = getProgramCounters(128)
      entries = getDebuggingInfo(pcs, 128)
    for entry in entries:
      if entry.filename != nil:
        result.add entry.filename
        when not defined(nimStackTraceOverride):
          c_free(entry.filename)
      else:
        result.add "(unknown)"
      result.add "("
      result.add $entry.line
      result.add ")"

      if entry.procname != nil:
        result.add ": "
        result.add $entry.procname
        when not defined(nimStackTraceOverride):
          c_free(entry.procname)

      result.add "\p"

  when defined(nimStackTraceOverride) and declared(registerStackTraceOverride):
    registerStackTraceOverride(libbacktrace.getBacktrace)
