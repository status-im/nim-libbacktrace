# Copyright (c) 2019 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0,
#  * MIT license
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

# Don't warn that this module is unused (e.g.: when the Nim compiler supports it
# and users need to import it, even if they don't call getBacktrace() manually).
{.used.}

import libbacktrace_wrapper, os, system/ansi_c

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
  var
    bt: cstring = get_backtrace_c()
    btLen = len(bt)

  result = newString(btLen)
  if btLen > 0:
    copyMem(addr(result[0]), bt, btLen)
  xfree_backtrace_c(bt)

when defined(nimStackTraceOverride):
  registerStackTraceOverride(getBacktrace)

