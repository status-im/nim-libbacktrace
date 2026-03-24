# Copyright (c) 2019-2026 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0,
#  * MIT license
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

mode = ScriptMode.Verbose

packageName = "libbacktrace"
version = "0.2.0"
author = "Status Research & Development GmbH"
description = "Nim wrapper for libbacktrace"
license = "MIT or Apache License 2.0"
installExt = @["nim", "h", "c", "cpp", "in"]

requires "nim >= 2.0"

task test, "Run tests":
  for test in ["test1", "test2"]:
    for be in ["c", "cpp"]:
      for mode in ["debug", "release", "danger"]:
        for override in ["", " -d:nimStackTraceOverride"]:
          for mm in [" --mm:refc", " --mm:orc"]:
            if defined(windows) and sizeof(int) == 4 and "orc" in mm:
              continue # Seems to crash somewhere in nim..

            exec "nim " & be &
              " -r --debugger:native --outdir:build --skipParentCfg:on --skipUserCfg:on -f -d:" &
              mode & override & mm & " tests/" & test
