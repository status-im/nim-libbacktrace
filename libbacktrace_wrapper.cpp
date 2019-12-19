/*
* Copyright (c) 2019 Status Research & Development GmbH
* Licensed under either of
*  * Apache License, version 2.0,
*  * MIT license
* at your option.
* This file may not be copied, modified, or distributed except according to
* those terms.
*/

#include "libbacktrace_wrapper.c"

/*
* Nim always uses a C compiler to compile *.c files with the {.compile: .}
* pragma , even when its C++ backend is enabled, so we resort to this silly
* .cpp wrapper to get the C++ compiler and make sure __cplusplus is defined.
*/

