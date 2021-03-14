# All the backtrace, none of the overhead

[![Build Status](https://travis-ci.org/status-im/nim-libbacktrace.svg?branch=master)](https://travis-ci.org/status-im/nim-libbacktrace)
[![Build status](https://ci.appveyor.com/api/projects/status/mrvu6ks50dl5y5y4/branch/master?svg=true)](https://ci.appveyor.com/project/nimbus/nim-libbacktrace/branch/master)
[![License: Apache](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Stability: experimental](https://img.shields.io/badge/stability-experimental-orange.svg)

Nim's default stack tracing functionality comes with significant
overhead, by adding `nimln_()`, `nimfr_()` calls all over the place. The
problem is being discussed upstream in [this GitHub
issue](https://github.com/nim-lang/Nim/issues/12702).

That `popFrame()` at the end of each C function is particularly problematic,
since it prevents the C compiler from doing tail-call optimisations.

This is a lightweight alternative based on libbacktrace, meant to offer the
same stack traces without the runtime overhead.

C++ function name demangling is supported using "\_\_cxa\_demangle()".

## Building & Testing

This project uses Git submodules, so get it with:

```bash
git clone https://github.com/status-im/nim-libbacktrace.git
cd nim-libbacktrace
git submodule update --init
```

You build the library (or libraries, on macOS) with `make`. You test it with
`make test`.

Nimble is grudgingly supported, so `nimble install` works. (No, we will not
let a silly package manager dictate our project's structure. People have the
power!)

## Supported platforms

Tested with GCC and LLVM on Linux, macOS and 64-bit Windows (with Mingw-w64 and
the MSYS that comes with "Git for Windows").

## Usage

bttest.nim:

```nim
import libbacktrace

# presumably in some procedure:
echo getBacktrace()

# Should be the same output as writeStackTrace() - minus the header.
```


We need debugging symbols in the binary and we can do without Nim's bloated and
slow stack trace implementation:

```bash
# `-f` needed if you've changed nim-libbacktrace
# just use `c` if you're just compiling
nim r --debugger:native --stacktrace:off bttest.nim
```

When the C compiler inlines some functions, or does tail-call optimisation -
usually with `-d:release` or `-d:danger` - your stack trace might be incomplete.

If that's a problem, you can use `--passC:"-fno-inline -fno-optimize-sibling-calls"`.

### Two-step backtraces

When you store backtraces in re-raised exceptions, you won't need to print them
most of the time, so it makes sense to delay the expensive part of debugging
info collection until it's actually needed:

```nim
let maxLength: cint = 128

# Unwind the stack and get a seq of program counters - the fast step:
let programCounters = getProgramCounters(maxLength)

# Later on, when you need to print these backtraces, get the debugging
# info - the relatively slow step:
let entries = getDebuggingInfo(programCounters, maxLength)
```

If you have multiple backtraces - and yo do with a re-raised exception - you
should pass subsets of program counters representing complete stack traces to
`getDebuggingInfo()`, because there's some logic inside it that keeps track of
certain inlined functions in order to change the output

You may get more StackTraceEntry objects than the program counters you passed
to `getDebuggingInfo()`, when you have inlined functions and the debugging
format knows about them (DWARF does).

### Debugging

`export NIM_LIBBACKTRACE_DEBUG=1` to see the trace lines hidden by default.

### Nim compiler support

Nim 1.0.6 supports [replacing the default stack tracing mechanism with an
external one](https://github.com/nim-lang/Nim/pull/12922).

This means you no longer have to call `getBacktrace()` yourself, if you compile
your program like this:

`nim c -r --debugger:native --stacktrace:off -d:nimStackTraceOverride --import:libbacktrace foo.nim`

You can even use libbacktrace in the Nim compiler itself, by building it with:

`./koch boot -d:release --debugger:native -d:nimStackTraceOverride --import:libbacktrace`

(`-d:release` implies `--stacktrace:off`)

## Dependencies

You need Make, CMake and, of course, Nim up and running.

The other dependencies are bundled, for your convenience. We use a [libbacktrace
fork](https://github.com/status-im/libbacktrace)
with macOS support and [LLVM's libunwind
variant](https://github.com/llvm-mirror/libunwind) that's needed on macOS and Windows.

If you know better and want to use your system's libbacktrace package instead
of the bundled one, you can, with `make USE_SYSTEM_LIBS=1` and by passing
`-d:libbacktraceUseSystemLibs` to the Nim compiler.

How does libbacktrace work on systems without libunwind installed, I hear you
asking? It uses GCC's basic unwind support in libgcc\_s.so.1 - that runtime's so
good that even Clang links it by default ;-)

If you don't want to build the C++ wrapper, for some reason, pass `BUILD_CXX_LIB=0` to Make.

To get the running binary's path in a cross-platform way, we rely on
[whereami](https://github.com/gpakosz/whereami).

## License

Licensed and distributed under either of

* MIT license: [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT

or

* Apache License, Version 2.0, ([LICENSE-APACHEv2](LICENSE-APACHEv2) or http://www.apache.org/licenses/LICENSE-2.0)

at your option. These files may not be copied, modified, or distributed except according to those terms.

