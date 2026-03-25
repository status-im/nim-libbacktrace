# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

# libbacktrace build configuration that mirrors configure.ac and Makefile.am
#
# The following things are generated:
#
# * A C amalgamation that includes all the relevant .c files for the platform
# * `backtrace-supported.h` for libbactrace itself
# * Constants at the Nim level that can be used to detect backtrace support
#
# Features from libbacktrace that we're not using (TODO?):
# * Compression
# * Exotic platforms

import std/[compilesettings, os, strutils]

# Platform-specific file format support
when defined(linux):
  const pdefs = [
    "BACKTRACE_ELF_SIZE=" & $(sizeof(pointer) * 8), "HAVE_DL_ITERATE_PHDR=1",
    "HAVE_DECL_PAGESIZE=1", "HAVE_FCNTL=1", "HAVE_LINK_H=1", "HAVE_READLINK=1",
  ]
elif defined(macosx):
  const pdefs = ["HAVE_DECL_PAGESIZE=1", "HAVE_FCNTL=1", "HAVE_MACH_O_DYLD_H=1"]
elif defined(windows):
  const pdefs = ["HAVE__PGMPTR=1", "HAVE_TLHELP32_H=1", "HAVE_WINDOWS_H=1"]
elif defined(freebsd) or defined(openbsd):
  const pdefs = [
    "BACKTRACE_ELF_SIZE=" & $(sizeof(pointer) * 8), "HAVE_DL_ITERATE_PHDR=1",
    "HAVE_FCNTL=1", "HAVE_LINK_H=1", "KERN_PROC=1", "HAVE_READLINK=1",
  ]
else:
  {.
    error: "nim-libbacktrace has not been ported to your platform, please provide a PR!"
  .}

const
  sourcePath = currentSourcePath.rsplit({DirSep, AltSep}, 1)[0]
  # Place output in a separate folder since we have to generate a file named "config.h"
  outputDir =
    querySetting(SingleValueSetting.nimcacheDir).replace('\\', '/') & "/nim-libbacktrace"
  amalgamation = outputDir & "/backtrace_all.c"
  backtraceSupportedH = outputDir & "/backtrace-supported.h"
  includes = "-I" & outputDir & " -I" & sourcePath & "/../vendor/libbacktrace-upstream"

  # General defines that are at worst harmless on all platformss
  defs = [
    "_GNU_SOURCE=1", "_LARGE_FILES=1", "HAVE_ATOMIC_FUNCTIONS=1", "HAVE_DECL_STRNLEN=1",
    "HAVE_GETIPINFO=1", "HAVE_LSTAT=1", "HAVE_SYNC_FUNCTIONS=1",
  ]

  flags = block:
    var res: string
    for v in defs:
      res.add " -D"
      res.add v
    for v in pdefs:
      res.add " -D"
      res.add v
    res

{.compile(amalgamation, includes & flags).}

static:
  when not fileExists(backtraceSupportedH):
    # Generate backtrace-supported.h from template
    # This file is needed by the libbacktrace library to determine feature support

    const
      backtraceUsesMalloc = if defined(macosx) or defined(windows): "1" else: "0"
      templatePath =
        sourcePath & "/../vendor/libbacktrace-upstream/backtrace-supported.h.in"
      configH = outputDir & "/config.h"

      templateContent = slurp(templatePath)

    createDir(outputDir)
    writeFile(
      backtraceSupportedH,
      templateContent
        .replace("@BACKTRACE_SUPPORTED@", "1")
        .replace("@BACKTRACE_USES_MALLOC@", backtraceUsesMalloc)
        .replace("@BACKTRACE_SUPPORTS_THREADS@", "1")
        .replace("@BACKTRACE_SUPPORTS_DATA@", "1"),
    )
    writeFile(configH, "") # Has to exist..

when defined(gcc) or defined(clang):
  # Unwind tables are needed for libunwind to do its job
  {.passC: "-funwind-tables".}

# Platform-specific linker flags
when defined(linux):
  # Link with dl for dl_iterate_phdr
  {.passl: "-ldl".}

  # Link with pthread
  {.passl: "-lpthread".}
elif defined(macosx):
  # Link with System framework
  {.passl: "-framework System".}
elif defined(windows):
  # Link with appropriate Windows libraries
  {.passl: "-lpsapi -lkernel32".}
