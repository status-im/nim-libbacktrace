# Copyright (c) 2019 Status Research & Development GmbH. Licensed under
# either of:
# - Apache License, version 2.0
# - MIT license
# at your option. This file may not be copied, modified, or distributed except
# according to those terms.

SHELL := bash # the shell used internally by Make

NIM_PARAMS := -f --outdir:build --skipParentCfg:on $(NIMFLAGS)
BUILD_MSG := "\\e[92mBuilding:\\e[39m"

# verbosity level
V := 0
NIM_PARAMS := $(NIM_PARAMS) --verbosity:$(V)
HANDLE_OUTPUT :=
SILENT_TARGET_PREFIX := disabled
ifeq ($(V), 0)
  NIM_PARAMS := $(NIM_PARAMS) --hints:off --warnings:off
  HANDLE_OUTPUT := &>/dev/null
  SILENT_TARGET_PREFIX :=
endif

USE_SYSTEM_LIBS := 0
ifneq ($(USE_SYSTEM_LIBS), 0)
  NIM_PARAMS := $(NIM_PARAMS) -d:libbacktraceUseSystemLibs
endif

ECHO_AND_RUN = echo -e "\n$(CMD)\n"; $(CMD) $(MACOS_DEBUG_SYMBOLS) && ./build/$@

TESTS := test1

.PHONY: all libbacktrace libunwind clean test $(TESTS)

ifeq ($(USE_SYSTEM_LIBS), 0)
all: libbacktrace
else
all:
endif

$(SILENT_TARGET_PREFIX).SILENT:

libbacktrace: install/usr/lib/libbacktrace.a

#########
# macOS #
#########
ifeq ($(shell uname), Darwin)
# libbacktrace needs to find libunwind during compilation
export CPPFLAGS := $(CPPFLAGS) -I"$(CURDIR)/install/usr/include"
export LDFLAGS := $(LDFLAGS) -L"$(CURDIR)/install/usr/lib"

# TODO: disable when this issue is fixed: https://github.com/nim-lang/Nim/issues/12735
MACOS_DEBUG_SYMBOLS = && dsymutil build/$@

BUILD_MSG := "Building:"

#- macOS Clang needs the LLVM libunwind variant
#  (GCC comes with its own, in libgcc_s.so.1, used even by Clang itself, on other platforms)
#- this library doesn't support parallel builds, hence the "-j1"
#- libtool can't handle paths with spaces on Windows, so we can't do `mingw32-make install`
install/usr/lib/libbacktrace.a: install/usr/lib/libunwind.a
else
install/usr/lib/libbacktrace.a:
endif # macOS
	echo -e $(BUILD_MSG) "libbacktrace" && \
	cd vendor/libbacktrace && \
		./configure --prefix="/usr" --disable-shared --enable-static MAKE="$(MAKE)" $(HANDLE_OUTPUT) && \
		$(MAKE) -j1 clean all $(HANDLE_OUTPUT) && \
		mkdir -p "$(CURDIR)"/install/usr/{include,lib} && \
		cp -a backtrace.h backtrace-supported.h "$(CURDIR)/install/usr/include/" && \
		cp -a .libs/libbacktrace.a libbacktrace.la "$(CURDIR)/install/usr/lib/"

libunwind: install/usr/lib/libunwind.a

install/usr/lib/libunwind.a:
	+ echo -e $(BUILD_MSG) "libunwind" && \
	cd vendor/libunwind && \
		rm -f CMakeCache.txt && \
		cmake -DLIBUNWIND_ENABLE_SHARED=OFF -DLIBUNWIND_ENABLE_STATIC=ON -DLIBUNWIND_INCLUDE_DOCS=OFF \
			-DLIBUNWIND_LIBDIR_SUFFIX="" -DCMAKE_INSTALL_PREFIX=/usr . $(HANDLE_OUTPUT) && \
		$(MAKE) DESTDIR="$(CURDIR)/install" clean install $(HANDLE_OUTPUT) && \
		cp -a include "$(CURDIR)/install/usr/"

test: $(TESTS)

ifeq ($(USE_SYSTEM_LIBS), 0)
$(TESTS): libbacktrace
else
$(TESTS):
endif
	$(eval CMD := nim c $(NIM_PARAMS) tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native --stackTrace:off tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native -d:debug tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native -d:release tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native -d:danger tests/$@.nim) $(ECHO_AND_RUN)
	# one for the C++ backend:
	$(eval CMD := nim cpp $(NIM_PARAMS) --debugger:native tests/$@.nim) $(ECHO_AND_RUN)

clean:
	rm -rf install build

