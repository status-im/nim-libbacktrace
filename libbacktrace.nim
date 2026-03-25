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

# Disable runtime checks in this module - since we're often collecting stack
# traces while processing exceptions, they wouldn't do much good anyway - we'll
# just have to be careful :)
{.push stacktrace: off, checks: off, linetrace: off.}

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

  import system/ansi_c, std/[algorithm, compilesettings, os], libbacktrace/wrapper

  const
    libbacktraceDemangle {.booldefine.} = true
      ## Enabling demangling causes a dependency on the C++, for demangling

    libbacktraceUseSystemLibs {.booldefine.} = false
      ## Use the system-wide installation of libbacktrace by linking to `-lbacktrace`

    libbacktraceLogErrors {.booldefine.} = false

  when libbacktraceUseSystemLibs:
    {.passl: "-lbacktrace".}
  else:
    import libbacktrace/build

  # Demangler seems to be missing from 32-bit windows, based on CI tests - needs
  # investigation
  const demangleSupported = not (defined(windows) and sizeof(int) == 4)

  when libbacktraceDemangle and demangleSupported:
    {.compile: "libbacktrace/demangle.cpp".}

    proc libbacktrace_demangler(name: cstring): cstring {.importc.}

  when not defined(nimStackTraceOverride) or not declared(libbacktrace_demangler):
    # When not overriding, we must allocate a copy of the string coming from
    # backtrace to avoid it getting released after the callback
    proc c_strdup(v: cstring): cstring {.importc: "strdup", header: "string.h".}

  when not declared(c_strstr):
    # nim < 2.2.2
    proc c_strstr*(
      haystack, needle: cstring
    ): cstring {.importc: "strstr", header: "<string.h>", noSideEffect.}

  proc error(data: pointer, msg: cstring, errnum: cint) {.cdecl.} =
    when libbacktraceLogErrors:
      c_fprintf(cstderr, "backtrace: %s (%d)\n", msg, errnum)

  var state = backtrace_create_state(nil, 1, error, nil)

  proc getProgramCounters*(maxLength: cint): seq[cuintptr_t] {.noinline.} =
    ## Capture the current stack trace up to `maxLength` depth

    type SimpleData = tuple[v: ptr seq[cuintptr_t], maxLength: cint]
    proc callback(data: pointer, pc: cuintptr_t): cint {.cdecl.} =
      let data = cast[ptr SimpleData](data)
      if data[].v[].len == int data[].maxLength:
        1 # Stop iterating
      else:
        data[].v[].add pc
        0 # Keep going

    var data: SimpleData = (addr result, maxLength)
    if backtrace_simple(state, 2, callback, error, addr data) == 0:
      reverse(result) # Nim convention is opposite of that of backtrace
    else:
      result.reset()

  template setString(
      entry: var StackTraceEntry, field: untyped, function: cstring, owned: bool
  ) =
    when compiles(entry.`field Str`):
      # In override mode, a `string` in the StackTraceEntry holds the GC ref
      # and a pointer to that ref is assigned to the public field (which might
      # lead to dangling pointers!)
      entry.`field Str` = $function
      entry.field = cstring(entry.`field Str`)

      if owned:
        c_free(function)
    else:
      # symname must be deallocated manually by the caller (!)
      entry.field =
        if owned:
          function
        else:
          c_strdup(function)

  template setString(entry: var StackTraceEntry, field: untyped, function: string) =
    when compiles(entry.`field Str`):
      entry.`field Str` = function
      entry.field = cstring(entry.`field Str`)
    else:
      # symname must be deallocated manually by the caller (!)
      entry.field = c_strdup(function)

  proc to0xHexLower(v: cuintptr_t): string =
    const HexChars = "0123456789abcdef"
    var v = v
    result = newString(sizeof(v) * 2 + 2)
    result.add "0x"
    for j in countdown(result.len - 1, 0):
      result[j] = HexChars[int(v and 0x0f)]
      v = v shr 4

  proc getDebuggingInfo*(
      programCounters: seq[cuintptr_t], maxLength: cint
  ): seq[StackTraceEntry] {.noinline.} =
    ## Translate a set of program counters into stacktrace entries. The returned
    ## sequence may be longer than the input if the debug information contains
    ## inlining information.
    ##
    ## If `-d:nimStackTraceOverride` is not enabled, you are responsible for
    ## freeing `filename` and `procname` with `c_free`.

    proc syminfo(
        data: pointer, pc: cuintptr_t, symname: cstring, symval, symsize: cuintptr_t
    ) {.cdecl.} =
      if symname != nil:
        # make a copy in case backtrace deallocates `symname`
        let function = cast[ptr cstring](data)
        function[] =
          when declared(libbacktrace_demangler):
            libbacktrace_demangler(symname)
          else:
            strdup(symname)

    type PcData = tuple[v: ptr seq[StackTraceEntry], maxLength: cint, done: bool]
    proc pcinfo(
        data: pointer,
        pc: cuintptr_t,
        filename: cstring,
        lineno: cint,
        function: cstring,
    ): cint {.cdecl.} =
      let data = cast[ptr PcData](data)
      if data.done or data.v[].len == int data.maxLength:
        # Because `pcinfo` might becalled multiple times per pc, we might outgrow
        # the allocated space!
        return 1 # Stop iterating

      var
        function = function
        owned = false
          # Flag for tracking whether we made a copy of `function` already -
          # ownership gets messy because we might have to extract it from the
          # symbol table

      if function == nil:
        # We could not get the function name from debug information - try
        # using the symbol name instead
        if backtrace_syminfo(state, pc, syminfo, error, addr function) != 1:
          function = nil
        elif function != nil:
          # the syminfo callback copies and demangles the function name, see above
          owned = true

      const projectName = querySetting(SingleValueSetting.projectName)

      if function != nil:
        # Functions in the nim standard library that we don't want to show in a
        # stack trace - a better option would be for the std lib to indicate how
        # many functions to remove from the stack trace but that ship sailed
        # unfortunately
        const skipped = [
          cstring "writeStackTrace", "rawWriteStackTrace",
          "auxWriteStackTraceWithOverride", "rawWriteStackTrace", "raiseExceptionEx",
        ]

        for v in skipped:
          if c_strstr(function, v) != nil:
            if owned: # In case we got the function name from syminfo
              c_free(function)
            return 0 # Skipped, but we need to keep going

      # Avoid moving StackTraceEntry around for above described reallocation reasons
      data[].v[].add StackTraceEntry()
      let entry = addr data[].v[][^1]

      if function == nil:
        # Function unknown - put the program counter as function name instead
        entry[].setString(procname, to0xHexLower(pc))
      elif c_strstr(function, "NimMainModule") != nil:
        # `NimMainModule` hosts all the code that lives outside of any proc/func
        entry[].setString(procname, projectName)
        data[].done = true
      else:
        when declared(libbacktrace_demangle):
          if not owned:
            # demangler makes a copy of the function
            function = libbacktrace_demangler(function)
            owned = true
        entry[].setString(procname, function, owned)

      if filename != nil and filename[0] != '\0':
        entry[].setString(filename, filename, false)

      entry[].line = lineno.int

    # Allocate the result up front to reduce allocations during traversal which
    # might mess up the internal pointers of StackTraceEntry - hopefully
    # reduces the incidence of https://github.com/nim-lang/Nim/issues/25306
    result = newSeqOfCap[StackTraceEntry](maxLength)

    var data: PcData = (addr result, maxLength, false)

    # Process `programCounters` backwards then `reverse` to account for the
    # order in which pcinfo calls the callback - also simplifies the logic for
    # stopping at `NimMainModule`
    for i in countdown(programCounters.high(), 0):
      if backtrace_pcinfo(state, programCounters[i], pcinfo, error, addr data) != 0:
        break

    reverse(result)

  proc getBacktrace*(): string {.noinline.} =
    ## Get a formatted backtrace of the current call stack - for more control,
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
        result.add "???"
      result.add "("
      result.add $entry.line
      result.add ")"

      if entry.procname != nil:
        result.add ": "
        result.add $entry.procname
        when not defined(nimStackTraceOverride):
          c_free(entry.procname)

      result.add "\p"

  when defined(nimStackTraceOverride):
    when declared(registerStackTraceOverrideGetProgramCounters):
      if not state.isNil:
        registerStackTraceOverrideGetProgramCounters(libbacktrace.getProgramCounters)

    when declared(registerStackTraceOverrideGetDebuggingInfo):
      if not state.isNil:
        registerStackTraceOverrideGetDebuggingInfo(libbacktrace.getDebuggingInfo)

    when declared(registerStackTraceOverride):
      if not state.isNil:
        registerStackTraceOverride(libbacktrace.getBacktrace)
