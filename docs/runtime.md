# Runtime design

## Build boundaries

`LeanEmbedded.csolution.yml` selects GCC or CLANG and delegates the native project to CMake. `scripts/lean-sources.py` asks stock Lake for package modules' C facets and generates matching built-in module C from the pinned Lean source. The generated manifest contains the selected runtime import closure. Explicit meta imports are omitted for module-system roots; legacy modules retain their full initializer dependencies. Local source changes and Lake configuration changes trigger regeneration.

Module-system roots use their real `runtime_initialize_*` entry point. This avoids running elaborator-side metaprogram initializers on the MCU. Legacy modules fall back to their actual `initialize_*` entry point. Every selected initializer is linked; there are no successful placeholder module initializers.

The compiler commit, runtime commit, and release are checked. `scripts/prepare-runtime.py` checks that upstream runtime/header/util sources have not been edited, copies them into the build directory, and applies a few checked platform edits. It writes `upstream/changes.patch` beside the generated sources for review. The fetched repository stays unchanged.

## Upstream changes

The arithmetic, allocation/reference-counting algorithms, strings, arrays, closures, thunks, promises, and task scheduling remain upstream code. The compatibility edits are limited to:

- Selecting a CMSIS thread backend in `thread.h` and `thread.cpp`; the upstream thread entry, heartbeat propagation, task queues, task dependency handling, and finalizers remain in use.
- Reading stack size from CMSIS instead of POSIX resource limits.
- Using the CMSIS monotonic clock for task-wait profiling.
- Replacing unavailable C++ atomic wait/notify with an atomic retry loop on the single core.
- Excluding POSIX signal-stack fields and terminating failed assertions without spawning a desktop debugger.

The optional console stream/handle implementation, and the platform-independent ST/reference and BaseIO task primitives, are extracted directly from upstream `runtime/io.cpp`; the time primitives use the CMSIS clock. Console stream initialization is lazy so the core does not pull in `Init.System.IO`; error reporting uses the real `IO.Error.otherError` constructor with the C error number and message, without a libuv dependency. This avoids forking all of the desktop IO implementation.

The port supplies its own runtime lifecycle because the desktop lifecycle unconditionally initializes processes and libuv. Mimalloc and GMP are not enabled; the existing upstream malloc and multiprecision backends are used. `LEAN_MULTI_THREAD` remains defined for both compilers.

## Platform adapters

`runtime/cmsis_thread.*` supplies priority-inheriting mutexes, recursive mutexes, a writer-preferring shared mutex, and condition variables. A condition waiter is enrolled before releasing its associated mutex; each waiter owns a semaphore so an early notification is retained. RTX threads are joinable until joined or detached, preserving the upstream dedicated-worker lifetime behavior.

GCC uses emulated TLS. `cmsis_tls.cpp` implements the compiler TLS descriptor ABI with a storage registry per `osThreadId_t`, preserving initial values and alignment and reclaiming storage at thread exit. ATfE and picolibc use native ARM TLS, with a copied TLS template per RTX thread. The ARM `__aeabi_read_tp` helper uses an assembly wrapper because its ABI requires preserving r1-r3, unlike an ordinary C call. C++ exception state is also per-thread.

The installed C++ libraries have no RTX backend. Local-static initialization guards are supplied using the ARM guard ABI. Newlib/picolibc retargetable locks and the allocator lock use nested interrupt critical sections on this single core. This is suitable for the FVP/semihosting demonstration, but does not give a bounded worst-case interrupt latency for arbitrary C-library calls.

The bounded C heap is independent of the currently running thread's PSP; a generic semihosting `_sbrk` stack-pointer check would incorrectly reject allocations in RTX threads. Thread stacks and RTX objects come from the separate RTX memory pool.

## Capability boundaries

| Capability | Status |
| --- | --- |
| Arbitrary-precision Nat/Int, object allocation and reference counting | Upstream implementation; big Nat arithmetic exercised |
| Arrays, byte arrays, strings, closures, thunks | Upstream implementation compiled; not every API independently tested |
| Task spawn, map, bind, dedicated workers, promise wait/resolve | Tested on real RTX threads with both toolchains |
| ST.Ref / IO.Ref runtime primitives | Upstream implementations; shared-reference get/swap tested |
| BaseIO task bridge, cancellation, task state and wait primitives | Upstream code included; cancellation/wait-any not separately stress-tested |
| Mutexes, recursive mutexes, shared mutexes, condition variables | RTX adapters; task synchronization and mutex modes tested |
| TLS, thread reuse/finalization, C++ exceptions and initialization guards | Tested with both toolchains |
| Monotonic milliseconds/nanoseconds | RTX tick clock; millisecond progression tested |
| Stack checks | RTX stack checking and upstream software stack accounting; no POSIX signal recovery |
| Console | Optional stock `IO.println` / FS.Stream console backend, per-thread stream redirection, and semihosted C stdio; `IO.println`, Lean Tasks and `IO.sleep` tested in the Console profile |
| Filesystem, child processes, dynamic loading, OS signals | Not enabled for this target |
| libuv event loop, sockets, OpenSSL, cryptographic random source | Not enabled; no fake success or deterministic substitute |
| Object compaction / memory-mapped persistence | Not enabled |

A selected library can require an unavailable platform API. Such an application fails to link until a real backend is added. Additional modules do not automatically make an OS facility available.

The GCC newlib build keeps its ordinary shared reentrancy state/errno. Its heap and retargetable locks are protected, but this port does not claim arbitrary concurrent POSIX/newlib usage. ATfE picolibc TLS is per-thread. Avoid relying on cross-thread `errno` in GCC application FFI; capture/serialize such operations or add a proper newlib context-switch integration.

## Scheduling and memory limits

The FVP has one CPU. `hardware_concurrency()` correctly reports one; the validation deliberately requests two Lean workers to test concurrency. This gives concurrency, not parallel execution or hard real-time guarantees. Workers use normal RTX priority. Busy retry paths inherited from upstream assume that the thread making progress can be scheduled; avoid higher-priority callers spinning on lower-priority Lean work.

The default example reserves a 128 KiB RTX pool, 192 KiB C heap, and 16 KiB initial MSP stack. The application RTX thread uses 32 KiB and worker threads 16 KiB. These are explicit demonstration budgets in CMake/linker/startup files, not minimum RAM requirements for Lean. Dedicated tasks and nested waits may create extra workers and exhaust the pool; allocation errors terminate explicitly.

Monotonic time extends the 32-bit RTX tick count when sampled. For multi-wrap uptime accuracy it must be sampled at least once per full tick wrap (about 49.7 days at 1 kHz). Nanosecond values have tick resolution, not nanosecond hardware precision.

Arbitrary nontrivial C++ `thread_local` destructor registration in application FFI is not provided; use the Lean thread-finalizer mechanism for owned resources.

Foreign RTX threads that call Lean must invoke `lean_initialize_thread()` first, then `lean_finalize_thread()` and `lean_cmsis_tls_cleanup()` before exiting. Runtime-created workers do this automatically. Initialize the runtime/modules once in a running RTX thread before exposing Lean work to other threads.

Useful primary references: [Arm runtime ABI](https://github.com/ARM-software/abi-aa/blob/main/rtabi32/rtabi32.rst), [GCC emulated TLS ABI implementation](https://github.com/gcc-mirror/gcc/blob/releases/gcc-14/libgcc/emutls.c), and [newlib retargetable lock contract](https://sourceware.org/newlib/libc.html#Reentrancy).
