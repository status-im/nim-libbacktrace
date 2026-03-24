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

const
  sourcePath = currentSourcePath.rsplit({DirSep, AltSep}, 1)[0]
  # Place output in a separate folder since we have to generate a file named "config.h"
  outputDir =
    querySetting(SingleValueSetting.nimcacheDir).replace('\\', '/') & "/nim-libbacktrace"
  amalgamation = outputDir & "/backtrace_all.c"
  backtraceSupportedH = outputDir & "/backtrace-supported.h"
  includes = "-I" & outputDir & " -I" & sourcePath & "/../vendor/libbacktrace-upstream"

static:
  when not fileExists(amalgamation):
    const configh = outputDir & "/config.h"

    const src = ["dwarf.c", "fileline.c", "posix.c", "simple.c", "sort.c", "state.c"]

    # General defines that are at worst harmless on all platformss
    const defs = [
      "_GNU_SOURCE 1", "_LARGE_FILES 1", "HAVE_ATOMIC_FUNCTIONS 1",
      "HAVE_DECL_STRNLEN 1", "HAVE_GETIPINFO 1", "HAVE_LSTAT 1", "HAVE_SYNC_FUNCTIONS 1",
    ]

    # Platform-specific file format support
    when defined(linux):
      const psrc = ["elf.c", "mmap.c", "mmapio.c"]

      const pdefs = [
        "BACKTRACE_ELF_SIZE " & $(sizeof(pointer) * 8), "HAVE_DL_ITERATE_PHDR 1",
        "HAVE_DECL_PAGESIZE 1", "HAVE_FCNTL 1", "HAVE_LINK_H 1", "HAVE_READLINK 1",
      ]
    elif defined(macosx):
      const psrc = ["alloc.c", "macho.c", "read.c"]

      const pdefs = ["HAVE_DECL_PAGESIZE 1", "HAVE_FCNTL 1", "HAVE_MACH_O_DYLD_H 1"]
    elif defined(windows):
      const psrc = ["alloc.c", "pecoff.c", "read.c"]
      const pdefs = ["HAVE__PGMPTR 1", "HAVE_TLHELP32_H 1", "HAVE_WINDOWS_H 1"]
    elif defined(freebsd) or defined(openbsd):
      const psrc = ["elf.c", "mmap.c", "mmapio.c"]

      const pdefs = [
        "BACKTRACE_ELF_SIZE " & $(sizeof(pointer) * 8), "HAVE_DL_ITERATE_PHDR 1",
        "HAVE_FCNTL 1", "HAVE_LINK_H 1", "KERN_PROC 1", "HAVE_READLINK 1",
      ]
    else:
      {.
        error:
          "nim-libbacktrace has not been ported to your platform, please provide a PR!"
      .}

    proc generateAmalgamation(): string =
      var res: string
      for v in defs:
        res.add "#define "
        res.add v
        res.add "\n"

      for v in pdefs:
        res.add "#define "
        res.add v
        res.add "\n"

      for v in src:
        res.add "#include \""
        res.add v
        res.add "\"\n"

      for v in psrc:
        res.add "#include \""
        res.add v
        res.add "\"\n"

      res

    {.hint: "Generating " & amalgamation.}
    createDir(outputDir)
    writeFile(amalgamation, generateAmalgamation())
    writeFile(configh, "") # Has to exist..

{.compile(amalgamation, includes).}

# Platform-specific configuration
when defined(gcc) or defined(clang):
  # Unwind tables are needed for libunwind to do its job
  {.passC: "-funwind-tables".}

static:
  when not fileExists(backtraceSupportedH):
    # Generate backtrace-supported.h from template
    # This file is needed by the libbacktrace library to determine feature support

    # Platform-specific configuration
    when defined(linux):
      # Linux supports all features
      const backtraceSupported = "1"
      const backtraceUsesMalloc = "0" # Uses mmap
      const backtraceSupportsThreads = "1"
      const backtraceSupportsData = "1"
    elif defined(macosx):
      # macOS supports all features
      const backtraceSupported = "1"
      const backtraceUsesMalloc = "0" # Uses mmap
      const backtraceSupportsThreads = "1"
      const backtraceSupportsData = "1"
    elif defined(windows):
      # Windows supports basic features
      const backtraceSupported = "1"
      const backtraceUsesMalloc = "1" # Windows version uses malloc
      const backtraceSupportsThreads = "1"
      const backtraceSupportsData = "1"
    elif defined(freebsd) or defined(openbsd):
      # BSD supports all features
      const backtraceSupported = "1"
      const backtraceUsesMalloc = "0"
      const backtraceSupportsThreads = "1"
      const backtraceSupportsData = "1"
    else:
      {.
        warning: "nim-libbacktrace has not been ported to your system yet, file a PR!"
      .}
      const backtraceSupported = "0"
      const backtraceUsesMalloc = "0"
      const backtraceSupportsThreads = "0"
      const backtraceSupportsData = "0"

    const
      templatePath =
        sourcePath & "/../vendor/libbacktrace-upstream/backtrace-supported.h.in"
      templateContent = slurp(templatePath)

    writeFile(
      backtraceSupportedH,
      templateContent
        .replace("@BACKTRACE_SUPPORTED@", backtraceSupported)
        .replace("@BACKTRACE_USES_MALLOC@", backtraceUsesMalloc)
        .replace("@BACKTRACE_SUPPORTS_THREADS@", backtraceSupportsThreads)
        .replace("@BACKTRACE_SUPPORTS_DATA@", backtraceSupportsData),
    )

# Platform-specific linker flags
when defined(linux):
  # Link with rt for clock_gettime
  {.passl: "-lrt".}

  # Link with dl for dl_iterate_phdr
  {.passl: "-ldl".}

  # Link with pthread
  {.passl: "-lpthread".}

when defined(macosx):
  # Link with System framework
  {.passl: "-framework System".}

when defined(windows):
  # Link with appropriate Windows libraries
  {.passl: "-lpsapi -lkernel32".}
