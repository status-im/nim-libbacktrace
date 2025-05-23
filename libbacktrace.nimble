# Copyright (c) 2019-2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0,
#  * MIT license
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

mode = ScriptMode.Verbose

packageName   = "libbacktrace"
version       = "0.0.9"
author        = "Status Research & Development GmbH"
description   = "Nim wrapper for libbacktrace"
license       = "MIT or Apache License 2.0"
installDirs   = @["vendor/whereami/src", "install"]
installFiles  = @["libbacktrace_wrapper.c", "libbacktrace_wrapper.cpp", "libbacktrace_wrapper.h", "libbacktrace/wrapper.nim"]

requires "nim >= 1.6"

# Enable `nimble check` to work before `nimble install` is invoked
import std/os
mkDir("install")

before install:
  exec "git submodule update --init"
  var make = "make"
  when defined(windows):
    make = "mingw32-make"
  exec make
