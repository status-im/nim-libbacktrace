# All the backtrace, none of the overhead

[![CI](https://github.com/status-im/nim-libbacktrace/actions/workflows/ci.yml/badge.svg)](https://github.com/status-im/nim-libbacktrace/actions/workflows/ci.yml)
[![License: Apache](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Stability: experimental](https://img.shields.io/badge/stability-experimental-orange.svg)

`libbacktrace` provides efficient stack traces for Nim using platform-specific
methods based on debug and symbol information produced by the C compiler.

Nim's default stack tracing functionality comes with significant performance
overhead, by adding `nimln_()`, `nimfr_()` calls all over the place. The
problem is being discussed upstream in [this GitHub
issue](https://github.com/nim-lang/Nim/issues/12702).

In practice, you can get as much as 66% improved performance by disabling the
default stack tracing: https://github.com/status-im/nimbus-eth2/pull/3466

That `popFrame()` at the end of each C function is particularly problematic,
since it prevents the C compiler from doing tail-call optimisations.

This is a lightweight alternative based on libbacktrace, meant to offer the
same stack traces without the runtime overhead.

## Usage

`libbacktrace` can be used either stand-alone or by overriding the system stack
trace generation. The latter approach is recommended. In both cases, you can
add it as a nimble dependency:

```nim
requires "libbacktrace"
```

### Stand-alone operation

bttest.nim:

```nim
import libbacktrace

# presumably in some procedure:
echo getBacktrace()

# Should be the same output as writeStackTrace() - minus the header.
```

```bash
nim c -r --debugger:native --stacktrace:off bttest.nim
```

`--stacktrace:off` will disable nim-generated stack traces which in turn will
make your application run twice as fast.

`--debugger:native` enables native debug information which allows you to debug
your application with system debuggers like GDB, but it also enables writing
debug information to the binary that `libbacktrace` uses to generate stack traces.

### System stack trace override

You can enable the usage of `libbacktrace` for all stack traces, including those
used in exceptions, by using the stack trace override feature - this is the
recommended way of using `libbacktrace`:

```bash
nim c -r --debugger:native --stacktrace:off -d:nimStackTraceOverride --import:libbacktrace bttest.nim
```

`-d:nimStackTraceOverride` makes Nim call `libbacktrace` whenever a stack trace
is needed.

 `--import:libbacktrace` adds libbacktrace as a global import before all other
 modules to make sure that the backtrace support is installed properly.

The easiest thing to do is to create a file named `nim.cfg` in your project and
add the options there:

```ini
--debugger:native
--stacktrace:off
--import:libbacktrace
--define:nimStackTraceOverride
```

### Demangling

By default, Nim will generate function names mangled according to the C++
[Itanium ABI](https://github.com/nim-lang/Nim/pull/23302). Demangling decodes
the mangling improving readablility of function names.

Demangling is implemented by using the `cxxabi` functions present in modern C++
compilers and therefore adds a dependency on C++ and its standard library.

Turning it off with `-d:libbacktraceDemangle=false` also removes the C++ dependency
allowing the library to be used with plain C.

### Advanced options

By default, the Nim compiler passes "-g3" to the C compiler, with
"--debugger:native", which almost doubles the resulting binary's size (only on
disk, not in memory). If we don't need to use GDB on that binary, we can get
away with significantly fewer debugging symbols by switching to "-g1":

```bash
# for the C backend
nim c -d:release --debugger:native --gcc.options.debug:'-g1' somefile.nim

# for the C++ backend
nim cpp -d:release --debugger:native --gcc.cpp.options.debug:'-g1' somefile.nim

# Clang needs a different argument
nim c -d:release --cc:clang --debugger:native --clang.options.debug:'-gline-tables-only' somefile.nim
```

When the C compiler inlines some functions, or does tail-call optimisation -
usually with `-d:release` or `-d:danger` - your stack trace might be incomplete.

If that's a problem, you can use `--passC:"-fno-inline -fno-optimize-sibling-calls"`.

## Building & Testing

`libbacktrace` is built and tested with `nimble` and uses submodules to track
the backtrace backend.

```bash
git clone https://github.com/status-im/nim-libbacktrace.git
cd nim-libbacktrace
git submodule update --init
```

## Supported platforms

Tested with GCC and LLVM on Linux, macOS and 64-bit Windows (with Mingw-w64 and
the MSYS that comes with "Git for Windows").

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

If you have multiple backtraces - and you do with a re-raised exception - you
should pass subsets of program counters representing complete stack traces to
`getDebuggingInfo()`, because there's some logic inside it that keeps track of
certain inlined functions in order to change the output

You may get more StackTraceEntry objects than the program counters you passed
to `getDebuggingInfo()`, when you have inlined functions and the debugging
format knows about them (DWARF does).

### Nim compiler support

Stack trace overrides are supported as of Nim [v1.0.6](https://github.com/nim-lang/Nim/pull/12922).

Name mangling was added in Nim [v1.6.20+](https://github.com/nim-lang/Nim/commit/d08bba579da7df36c51d987c04085628d81cb92f)

v2.2.8 includes a [critical bug fix](https://github.com/nim-lang/Nim/issues/25306)
that otherwise might cause corruption during stack trace formatting.

## Dependencies

Backtraces and debug information is read using
[libbacktrace](https://github.com/ianlancetaylor/libbacktrace) which gets built
automatically as needed.

To use `libbacktrace` provided by the system, add `-d:libbacktraceUseSystemLibs`
to the flags.

## License

Licensed and distributed under either of

* MIT license: [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT

or

* Apache License, Version 2.0, ([LICENSE-APACHEv2](LICENSE-APACHEv2) or http://www.apache.org/licenses/LICENSE-2.0)

at your option. These files may not be copied, modified, or distributed except according to those terms.
