/* Amalgamation build for libbacktrace that selectively includes the right
  c files hopefully matching whatever configure.ac/Makefile.am would have
  come up with */
#include "backtrace-supported.h"

#include "dwarf.c"
#include "fileline.c"
#include "posix.c"
#include "simple.c"
#include "sort.c"
#include "state.c"

#ifdef __ELF__
#include "elf.c"
#elif defined(_WIN32) || defined(_WIN64)
#include "pecoff.c"
#elif defined(__APPLE__)
#include "macho.c"
#else
#error "Unknown platform"
#endif

#if BACKTRACE_USES_MALLOC
#include "alloc.c"
#include "read.c"
#else
#include "mmap.c"
#include "mmapio.c"
#endif
