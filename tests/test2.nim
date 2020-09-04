# Copyright (c) 2019-2020 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0,
#  * MIT license
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import libbacktrace
import asyncdispatch

proc f3(i: int): int =
  echo "getProgramCounters() and getDebuggingInfo():"
  let
    maxLength: cint = 128
    res = getDebuggingInfo(getProgramCounters(maxLength), maxLength)
  # old asyncdispatch's `$` can't handle our seq[StackTraceEntry]
  try:
    if res.len > 0 and res[0].procname != nil:
      echo res
  except Defect as e:
    echo e.msg
  echo "\n"
  stderr.flushFile()

  echo "writeStackTrace():"
  writeStackTrace()
  stderr.flushFile()

  echo "\ngetBacktrace():"
  echo getBacktrace()
  stderr.flushFile()

  if i == 3:
    raise newException(CatchableError, "exception1")

  return i + 4

proc f2(i: int): int =
  try:
    return f3(i + 2) + 2
  except CatchableError as e:
    raise e

proc f1(): int =
  return f2(1) + 1

# echo "res = ", f1()
try:
  echo "res = ", f1()
except CatchableError as e:
  echo e.msg
  echo getStackTraceEntries(e)

