#include <stdint.h>
#include <string.h>
#include "SSE300MPS3.h"
extern uint32_t __StackTop, __data_start__, __data_end__, __etext;
extern uint32_t __bss_start__, __bss_end__;
extern char __tls_base, __tdata_end, __tls_end, __tls_load;
extern void initialise_monitor_handles(void);
extern void __libc_init_array(void);
extern int main(void);
extern void _exit(int);
void _init(void) {}
void _fini(void) {}
void embedded_start(void) {
    memcpy(&__data_start__, &__etext, (uintptr_t)&__data_end__ - (uintptr_t)&__data_start__);
    memset(&__bss_start__, 0, (uintptr_t)&__bss_end__ - (uintptr_t)&__bss_start__);
    memcpy(&__tls_base, &__tls_load, &__tdata_end - &__tls_base);
    memset(&__tdata_end, 0, &__tls_end - &__tdata_end);
#ifndef __clang__
    initialise_monitor_handles();
#endif
    __libc_init_array();
    _exit(main());
}

/* RTX thread stacks are below the C heap. Newlib's generic rdimon _sbrk
 * compares against the current SP, which would reject allocations on PSP. */
#include <errno.h>
#include <stddef.h>
extern char __HeapBase, __HeapLimit;
void * _sbrk(ptrdiff_t increment) {
    static char * cursor;
    if (!cursor) cursor = &__HeapBase;
    uintptr_t amount = increment < 0 ? (uintptr_t)(-(increment + 1)) + 1 : (uintptr_t)increment;
    if ((increment < 0 && amount > (uintptr_t)cursor - (uintptr_t)&__HeapBase) ||
        (increment >= 0 && amount > (uintptr_t)&__HeapLimit - (uintptr_t)cursor)) {
        errno = ENOMEM;
        return (void *)-1;
    }
    void * previous = cursor;
    cursor += increment;
    return previous;
}
#ifdef __clang__
void * sbrk(ptrdiff_t increment) { return _sbrk(increment); }
#endif
