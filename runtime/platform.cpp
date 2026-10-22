#include <lean/lean.h>
#include "runtime/alloc.h"
#include "runtime/debug.h"
#include "runtime/object.h"
#include "runtime/thread.h"
#include "runtime/stack_overflow.h"
#include "cmsis_os2.h"
#include "runtime/mutex.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace lean {
extern "C" void lean_initialize_runtime_module() {
    static bool initialized = false;
    if (initialized) return;
    initialized = true;
    initialize_alloc();
    initialize_debug();
    initialize_object();
    initialize_thread();
    initialize_mutex();
}
stack_guard::stack_guard() {}
stack_guard::~stack_guard() {}
void initialize_stack_overflow() {}
void finalize_stack_overflow() {}
extern "C" __attribute__((weak)) lean_object * lean_io_eprintln(lean_object * s) {
    fprintf(stderr, "%s\n", lean_string_cstr(s));
    lean_dec(s);
    return lean_io_result_mk_ok(lean_box(0));
}
}

extern "C" char __StackTop, __StackLimit;
extern "C" size_t lean_cmsis_stack_size() {
    return osThreadGetId() ? osThreadGetStackSize(osThreadGetId()) : size_t(&__StackTop - &__StackLimit);
}
extern "C" { void * __dso_handle = &__dso_handle; }
