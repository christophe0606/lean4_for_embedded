#include "cmsis_os2.h"
#include "cmsis_device.h"
#include <cstdint>
#include <cstdlib>
extern "C" {
#include <sys/lock.h>
}

/* Both installed libraries expose retargetable locks. Use a nested critical
 * section on the single Cortex-M core, preserving the caller's IRQ mask. */
extern "C" void __malloc_lock(void *);
extern "C" void __malloc_unlock(void *);
struct __lock { uint32_t unused; };
extern "C" {
__lock __lock___libc_recursive_mutex;
#ifndef __clang__
__lock __lock___sinit_recursive_mutex;
__lock __lock___sfp_recursive_mutex;
__lock __lock___atexit_recursive_mutex;
__lock __lock___at_quick_exit_mutex;
__lock __lock___malloc_recursive_mutex;
__lock __lock___env_recursive_mutex;
__lock __lock___tz_mutex;
__lock __lock___dd_hash_mutex;
__lock __lock___arc4random_mutex;
#endif
}
extern "C" void __retarget_lock_init(_LOCK_T * lock) { *lock = &__lock___libc_recursive_mutex; }
extern "C" void __retarget_lock_init_recursive(_LOCK_T * lock) { __retarget_lock_init(lock); }
extern "C" void __retarget_lock_close(_LOCK_T) {}
extern "C" void __retarget_lock_close_recursive(_LOCK_T) {}
extern "C" void __retarget_lock_acquire(_LOCK_T) { __malloc_lock(nullptr); }
extern "C" void __retarget_lock_acquire_recursive(_LOCK_T) { __malloc_lock(nullptr); }
extern "C" void __retarget_lock_release(_LOCK_T) { __malloc_unlock(nullptr); }
extern "C" void __retarget_lock_release_recursive(_LOCK_T) { __malloc_unlock(nullptr); }
extern "C" int __retarget_lock_try_acquire(_LOCK_T) { __malloc_lock(nullptr); return 1; }
extern "C" int __retarget_lock_try_acquire_recursive(_LOCK_T) { __malloc_lock(nullptr); return 1; }

/* The toolchain C++ libraries have no RTOS backend for local static guards.
 * Implement the ARM 32-bit guard ABI; bit zero means initialized. */
extern "C" int __cxa_guard_acquire(uint32_t * guard) {
    const auto owner = reinterpret_cast<uintptr_t>(osThreadGetId());
    for (;;) {
        uint32_t state = __atomic_load_n(guard, __ATOMIC_ACQUIRE);
        if (state & 1) return 0;
        if (!state && __atomic_compare_exchange_n(guard, &state, owner | 2, false,
                                                 __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) return 1;
        if ((state & ~uint32_t(3)) == owner) abort();
        if (osDelay(1) != osOK) abort();
    }
}
extern "C" void __cxa_guard_release(uint32_t * guard) { __atomic_store_n(guard, 1, __ATOMIC_RELEASE); }
extern "C" void __cxa_guard_abort(uint32_t * guard) { __atomic_store_n(guard, 0, __ATOMIC_RELEASE); }

#ifndef __clang__
/* This newlib build declares these file-lock hooks but does not supply them. */
#include <cstdio>
extern "C" void flockfile(FILE *) { __malloc_lock(nullptr); }
extern "C" void funlockfile(FILE *) { __malloc_unlock(nullptr); }
#endif
