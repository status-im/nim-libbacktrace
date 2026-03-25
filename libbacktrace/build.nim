# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

# libbacktrace build configuration that mirrors configure.ac and Makefile.am
#
# The following things are generated:
#
# * `backtrace-supported.h` needed by libbacktrace
# * `config.h` - empty, but must be present
# * A set of defines that would normally be written to said config.h (we
#   equivalently pass them as flags instead)
#
# Features from libbacktrace that we're not using (TODO?):
# * Compression
# * Exotic platforms

import std/[compilesettings, os, strutils]

# Platform-specific file format support
when defined(linux):
  const pdefs = [
    "-DBACKTRACE_ELF_SIZE=" & $(sizeof(pointer) * 8), "-DHAVE_DL_ITERATE_PHDR=1",
    "-DHAVE_DECL_PAGESIZE=1", "-DHAVE_FCNTL=1", "-DHAVE_LINK_H=1", "-DHAVE_READLINK=1",
  ]
elif defined(macosx):
  const pdefs = ["-DHAVE_DECL_PAGESIZE=1", "-DHAVE_FCNTL=1", "-DHAVE_MACH_O_DYLD_H=1"]
elif defined(windows):
  const pdefs = ["-DHAVE__PGMPTR=1", "-DHAVE_TLHELP32_H=1", "-DHAVE_WINDOWS_H=1"]
elif defined(freebsd) or defined(openbsd):
  const pdefs = [
    "-DBACKTRACE_ELF_SIZE=" & $(sizeof(pointer) * 8), "-DHAVE_DL_ITERATE_PHDR=1",
    "-DHAVE_FCNTL=1", "-DHAVE_LINK_H=1", "-DKERN_PROC=1", "-DHAVE_READLINK=1",
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
  backtraceSupportedH = outputDir & "/backtrace-supported.h"
  includes = ["-I" & outputDir, " -I" & sourcePath & "/../vendor/libbacktrace-upstream"]

  # General defines that are at worst harmless on all platformss
  defs = [
    "-D_GNU_SOURCE=1", "-D_LARGE_FILES=1", "-DHAVE_ATOMIC_FUNCTIONS=1",
    "-DHAVE_DECL_STRNLEN=1", "-DHAVE_GETIPINFO=1", "-DHAVE_LSTAT=1",
    "-DHAVE_SYNC_FUNCTIONS=1",
  ]

  flags = includes.join(" ") & " " & defs.join(" ") & " " & pdefs.join(" ")

{.compile("backtrace_all.c", flags).}

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
