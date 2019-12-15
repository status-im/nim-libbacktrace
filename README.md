# nim-libbacktrace - all the backtrace, none of the overhead

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

Tested with GCC and LLVM on Linux and macOS.

libbacktrace can't find debugging symbols in Mingw-w64 8.1.0 (posix-seh-rev0)
64-bit PE-COFF binaries, for some unknown reason.

## Usage

bttest.nim:

```nim
import libbacktrace

# presumably in some procedure:
echo getBacktrace()

# Should be the same output as writeStackTrace() - minus the header.
# When the C compiler inlines some procs, libbacktrace might get confused with proc names,
# but it gets the files and line numbers right nonetheless.
```

We need debugging symbols in the binary and we can do without Nim's bloated and
slow stack trace implementation:

```bash
nim c -f --debugger:native --stacktrace:off bttest.nim
```

If you're unfortunate enough to need this on macOS, [there's an extra
step](https://github.com/nim-lang/Nim/issues/12735) for creating debugging
symbols:

```bash
dsymutil bttest
```

Now you can run it:

```bash
./bttest
```

## Dependencies

You need Make, CMake and, of course, Nim up and running.

The other dependencies are bundled, for your convenience. We use a [libbacktrace
fork](https://github.com/rust-lang-nursery/libbacktrace/tree/rust-snapshot-2018-05-22)
with macOS support and [LLVM's libunwind
variant](https://github.com/llvm-mirror/libunwind) that's only needed on,
you've guessed it, macOS.

If you know better and want to use your system's libbacktrace package instead
of the bundled one, you can, with `make USE_SYSTEM_LIBS=1` and by passing
`-d:libbacktraceUseSystemLibs` to the Nim compiler.

How does libbacktrace work on systems without libunwind installed, I hear you
asking? It uses GCC's basic unwind support in libgcc\_s.so.1 - that runtime's so
good that even Clang links it by default ;-)

To get the running binary's path in a cross-platform way, we rely on
[whereami](https://github.com/gpakosz/whereami).

## License

Licensed and distributed under either of

* MIT license: [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT

or

* Apache License, Version 2.0, ([LICENSE-APACHEv2](LICENSE-APACHEv2) or http://www.apache.org/licenses/LICENSE-2.0)

at your option. These files may not be copied, modified, or distributed except according to those terms.

