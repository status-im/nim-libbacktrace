# Copyright (c) 2019-2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0,
#  * MIT license
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

mode = ScriptMode.Verbose

packageName   = "libbacktrace"
version       = "0.0.8"
author        = "Status Research & Development GmbH"
description   = "Nim wrapper for libbacktrace"
license       = "MIT or Apache License 2.0"
installDirs   = @["vendor/whereami/src", "install"]
installFiles  = @["libbacktrace_wrapper.c", "libbacktrace_wrapper.cpp", "libbacktrace_wrapper.h", "libbacktrace_wrapper.nim"]

requires "nim >= 1.0"

before install:
  exec "git submodule update --init"
  var make = "make"
  when defined(windows):
    make = "mingw32-make"
  exec make

