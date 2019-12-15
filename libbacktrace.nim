# Copyright (c) 2019 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

# Don't warn that this module is unused (e.g.: when the Nim compiler supports it
# and users need to import it, even if they don't call getBacktrace() manually).
{.used.}

import libbacktrace_wrapper, os, system/ansi_c

{.passc: "-I" & currentSourcePath.parentDir().}

when defined(cpp):
  {.compile: "libbacktrace_wrapper.cpp".}
else:
  {.compile: "libbacktrace_wrapper.c".}

when defined(libbacktraceUseSystemLibs):
  {.passl: "-lbacktrace".}
  when defined(macosx):
    {.passl: "-lunwind".}
else:
  const installPath = currentSourcePath.parentDir() / "install" / "usr"
  {.passc: "-I" & installPath / "include".}
  {.passl: installPath / "lib" / "libbacktrace.a".}
  when defined(macosx):
    {.passl: installPath / "lib" / "libunwind.a".}


proc getBacktrace*(): string {.exportc.} =
  var
    bt: cstring = get_backtrace_c()
    btLen = len(bt)

  result = newString(btLen)
  if btLen > 0:
    copyMem(addr(result[0]), bt, btLen)
  c_free(bt)

