# Copyright (c) 2019 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0,
#  * MIT license
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import libbacktrace

proc f3(i: int): int =
  echo "getBacktrace():"
  echo getBacktrace()
  echo "writeStackTrace():"
  writeStackTrace()
  echo "\ngetBacktrace():"
  echo getBacktrace()
  return i + 4

proc f2(i: int): int =
  return f3(i + 2) + 2

proc f1(): int =
  return f2(1) + 1

echo "res = ", f1()

