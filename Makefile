# Copyright (c) 2019-2020 Status Research & Development GmbH. Licensed under
# either of:
# - Apache License, version 2.0
# - MIT license
# at your option. This file may not be copied, modified, or distributed except
# according to those terms.

SHELL := bash # the shell used internally by Make

NIM_PARAMS := -f --gc:refc --outdir:build --skipParentCfg:on --skipUserCfg:on $(NIMFLAGS)
BUILD_MSG := "\\x1B[92mBuilding:\\x1B[39m"

# verbosity level
V := 0
NIM_PARAMS := $(NIM_PARAMS) --verbosity:$(V)
HANDLE_OUTPUT :=
SILENT_TARGET_PREFIX := disabled
ifeq ($(V), 0)
  NIM_PARAMS := $(NIM_PARAMS) --hints:off
  HANDLE_OUTPUT := &>/dev/null
  SILENT_TARGET_PREFIX :=
endif

USE_SYSTEM_LIBS := 0
ifneq ($(USE_SYSTEM_LIBS), 0)
  NIM_PARAMS := $(NIM_PARAMS) -d:libbacktraceUseSystemLibs
endif

ECHO_AND_RUN = echo -e "\n$(CMD)\n"; $(CMD) $(MACOS_DEBUG_SYMBOLS) && ./build/$@
LIBDIR := install/usr/lib
INCLUDEDIR := install/usr/include
CFLAGS += -g -O3 -std=gnu11 -pipe -Wall -Wextra -fPIC
CXXFLAGS += -g -O3 -std=gnu++11 -pipe -Wall -Wextra -fPIC
CPPFLAGS := -I"$(CURDIR)/$(INCLUDEDIR)"
LDLIBS := -L"$(CURDIR)/$(LIBDIR)"
AR := ar

ifeq ($(OS),Windows_NT)
  CC := gcc
  CXX := g++
else
  UNAME_S := $(shell uname -s)
  ifeq ($(UNAME_S),Linux)
    CC = gcc
    CXX = g++
  else
    CC ?= gcc
    CXX ?= g++
  endif
endif

TESTS := test1 \
	test2

.PHONY: all \
	clean \
	test \
	$(TESTS)

ifeq ($(USE_SYSTEM_LIBS), 0)
LIBBACKTRACE_DEP := $(LIBDIR)/libbacktrace.a
else
LIBBACKTRACE_DEP :=
endif

all: $(LIBBACKTRACE_DEP) $(LIBDIR)/libbacktracenim.a

BUILD_CXX_LIB := 1
ifeq ($(BUILD_CXX_LIB), 1)
all: $(LIBDIR)/libbacktracenimcpp.a
endif

$(LIBDIR)/libbacktracenim.a: libbacktrace_wrapper.o | $(LIBDIR)
	echo -e $(BUILD_MSG) "$@" && \
		rm -f $@ && \
		$(AR) rcs $@ $<

# it doesn't link to libbacktrace.a, but it needs the headers installed by that target
libbacktrace_wrapper.o: libbacktrace_wrapper.c libbacktrace_wrapper.h $(LIBBACKTRACE_DEP)

$(LIBDIR)/libbacktracenimcpp.a: libbacktrace_wrapper_cpp.o | $(LIBDIR)
	echo -e $(BUILD_MSG) "$@" && \
		rm -f $@ && \
		$(AR) rcs $@ $<

# implicit rule doesn't kick in
libbacktrace_wrapper_cpp.o: libbacktrace_wrapper.cpp libbacktrace_wrapper.c libbacktrace_wrapper.h $(LIBBACKTRACE_DEP)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c -o $@ $<

$(LIBDIR):
	mkdir -p $@

#########
# macOS #
#########
ifeq ($(shell uname), Darwin)
# TODO: disable when this issue is fixed: https://github.com/nim-lang/Nim/issues/12735
MACOS_DEBUG_SYMBOLS = && dsymutil build/$@

BUILD_MSG := "Building:"
endif # macOS

###########
# Windows #
###########
ifeq ($(OS), Windows_NT)
BUILD_MSG := "Building:"
CPPFLAGS += -D__STDC_FORMAT_MACROS -D_WIN32_WINNT=0x0600

LIBBACKTRACE_SED := sed -i 's/\$$[({]SHELL[)}]/"$$(SHELL)"/g' Makefile
else
LIBBACKTRACE_SED := true
endif # Windows

export CFLAGS
export CXXFLAGS

# We need to enable cross-compilation here, by passing "--build" and "--host"
# to "./configure". We already set CC in the environment, so it doesn't matter
# what the target host is, as long as it's a valid one.
$(LIBDIR)/libbacktrace.a:
	+ echo -e $(BUILD_MSG) "$@" && \
		cd vendor/libbacktrace-upstream && \
		./configure --prefix="/usr" --libdir="/usr/lib" --disable-shared --enable-static \
			--with-pic --build=$(./config.guess) --host=arm MAKE="$(MAKE)" $(HANDLE_OUTPUT) && \
		$(LIBBACKTRACE_SED) && \
		$(MAKE) -j1 DESTDIR="$(CURDIR)/install" clean all install $(HANDLE_OUTPUT)

test: $(TESTS)

$(TESTS): all
	$(eval CMD := nim c $(NIM_PARAMS) tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native --stackTrace:off tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native -d:debug tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native -d:release tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native -d:release -d:nimStackTraceOverride tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native -d:danger tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native -d:danger -d:nimStackTraceOverride tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native -d:release --gcc.options.debug:'-g1' -d:nimStackTraceOverride tests/$@.nim) $(ECHO_AND_RUN)
ifeq ($(shell uname), Darwin)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native -d:release --passC:-flto=thin --passL:"-flto=thin -Wl,-object_path_lto,build/$@.lto" tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native -d:release -d:nimStackTraceOverride --passC:-flto=thin --passL:"-flto=thin -Wl,-object_path_lto,build/$@.lto" tests/$@.nim) $(ECHO_AND_RUN)
else
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native -d:release --passC:-flto=auto --passL:-flto=auto tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim c $(NIM_PARAMS) --debugger:native -d:release -d:nimStackTraceOverride --passC:-flto=auto --passL:-flto=auto tests/$@.nim) $(ECHO_AND_RUN)
endif
ifeq ($(BUILD_CXX_LIB), 1)
	# for the C++ backend:
	$(eval CMD := nim cpp $(NIM_PARAMS) --debugger:native tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim cpp $(NIM_PARAMS) --debugger:native -d:release -d:nimStackTraceOverride tests/$@.nim) $(ECHO_AND_RUN)
	$(eval CMD := nim cpp $(NIM_PARAMS) --debugger:native -d:release --gcc.cpp.options.debug:'-g1' -d:nimStackTraceOverride tests/$@.nim) $(ECHO_AND_RUN)
endif

clean:
	rm -rf install build *.o
	cd vendor/libbacktrace-upstream && \
		{ [[ -e Makefile ]] && $(MAKE) clean $(HANDLE_OUTPUT) || true; }

$(SILENT_TARGET_PREFIX).SILENT:
