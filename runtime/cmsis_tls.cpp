/* GCC emulated-TLS ABI with storage owned by each CMSIS thread.
 * Clean implementation against GCC's documented control-object layout;
 * no changes to Lean's thread-local declarations are necessary. */
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include "cmsis_os2.h"
#include "cmsis_device.h"

namespace {
struct emutls_control { size_t size, align; void * location; const void * initial; };
struct slot { const emutls_control * control; void * allocation; void * value; slot * next; };
struct thread_state { osThreadId_t owner; slot * slots; thread_state * next; void * native; };
thread_state * states;
struct irq_guard {
    uint32_t previous = __get_PRIMASK();
    irq_guard() { __disable_irq(); }
    ~irq_guard() { __set_PRIMASK(previous); }
};
thread_state * current_state() {
    auto id = osThreadGetId();
    for (auto p = states; p; p = p->next) if (p->owner == id) return p;
    auto p = static_cast<thread_state *>(calloc(1, sizeof(thread_state)));
    if (!p) abort();
    p->owner = id;
    p->next = states;
    states = p;
    return p;
}
}
extern "C" void * __emutls_get_address(void * descriptor) {
    irq_guard guard;
    auto control = static_cast<emutls_control *>(descriptor);
    auto state = current_state();
    for (auto p = state->slots; p; p = p->next) if (p->control == control) return p->value;
    size_t align = control->align;
    if (!align || (align & (align - 1)) || control->size > SIZE_MAX - align) abort();
    auto p = static_cast<slot *>(calloc(1, sizeof(slot)));
    if (!p) abort();
    p->allocation = malloc(control->size + align - 1);
    if (!p->allocation) abort();
    p->value = reinterpret_cast<void *>((uintptr_t(p->allocation) + align - 1) & ~(align - 1));
    if (control->initial) memcpy(p->value, control->initial, control->size);
    else memset(p->value, 0, control->size);
    p->control = control;
    p->next = state->slots;
    state->slots = p;
    return p->value;
}
extern "C" void lean_cmsis_tls_cleanup() {
    irq_guard guard;
    auto id = osThreadGetId();
    thread_state ** link = &states;
    while (*link && (*link)->owner != id) link = &(*link)->next;
    if (!*link) return;
    auto state = *link;
    *link = state->next;
    while (state->slots) {
        auto p = state->slots;
        state->slots = p->next;
        free(p->allocation);
        free(p);
    }
    free(state->native);
    free(state);
}
/* Newlib's allocator was built without an RTOS: serialize it on this single core.
 * Preserve PRIMASK and nesting, including calls made by the TLS allocator. */
static unsigned malloc_depth;
static uint32_t malloc_primask;
extern "C" void __malloc_lock(void *) {
    auto previous = __get_PRIMASK();
    __disable_irq();
    if (!malloc_depth++) malloc_primask = previous;
}
extern "C" void __malloc_unlock(void *) {
    if (!malloc_depth) abort();
    if (!--malloc_depth) __set_PRIMASK(malloc_primask);
}
/* The bare-metal libstdc++ exception helper also needs per-thread state. */
namespace { struct exception_globals { void * caught; unsigned uncaught; void * propagating; }; }
extern "C" void * __cxa_get_globals() {
    static __thread exception_globals globals{};
    return &globals;
}
extern "C" void * __cxa_get_globals_fast() { return __cxa_get_globals(); }

#ifdef __clang__
// Picolibc itself uses ARM native TLS even though Lean uses emulated TLS.
extern "C" char __tls_base, __tls_end, __tls_load, __tdata_end;
extern "C" void * lean_cmsis_native_tp() {
    irq_guard guard;
    auto state = current_state();
    if (!state->native) {
        size_t size = size_t(&__tls_end - &__tls_base);
        state->native = calloc(1, size + 16);
        if (!state->native) abort();
        auto base = reinterpret_cast<void *>((uintptr_t(state->native) + 15) & ~uintptr_t(7));
        memcpy(base, &__tls_load, size_t(&__tdata_end - &__tls_base));
    }
    return reinterpret_cast<void *>(((uintptr_t(state->native) + 15) & ~uintptr_t(7)) - 8);
}
#endif
