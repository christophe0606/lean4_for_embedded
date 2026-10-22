# Validation

Validation is performed through the CMSIS Solution build and Run actions, against the installed Cortex-M55 Corstone-300 model in `linuxvm`.

Both `Corstone300-GCC` and `Corstone300-CLANG` must produce and run their own ELF. `scripts/verify-evidence.py` rejects stale evidence by comparing SHA-256 with each current artifact. Use `--console` to additionally verify the optional standard-console profile for each compiler. The detailed records are under `.build/evidence/`; generated artifacts are not committed.

The required checks are:

- Lean-generated arithmetic computes `(100000 + 42) * (100000 + 1) = 10004300042`, exercising a result larger than a 32-bit immediate Nat.
- The upstream scheduler executes 24 tasks returning allocated big Nats across thread boundaries, plus mapped/bound/dedicated work on RTX threads distinct from the caller.
- Thread-local heartbeat state remains isolated over thread exit and RTX ID reuse, while heartbeat limits propagate as upstream specifies. Worker C++ exceptions are caught correctly.
- Recursive and shared mutex modes behave correctly; task waits exercise condition-variable enrollment/notification.
- Promise resolution wakes a waiting caller. Three threads stress arbitrary-precision allocation/free. A contested C++ local static is constructed exactly once.
- Upstream shared ST.Ref get/swap primitives work, RTX monotonic time progresses across a delay, and a native FPU/boxed Float round trip is checked.
- The proved SysTick function passes seven boundary cases and actual FVP register readback.

The optional Console profile additionally runs Lean-written `Task.spawn`/`Task.map`, `IO.sleep`, and `IO.println`; its eighth PASS marker confirms that normal Lean console code executed. Both Console images are also checked against their current ELF and FVP configuration hashes.

The host compiler and runtime source commit are pinned to `eb6cafb7290e8bd5f2937522d8d804f58f02bafc` (Lean 4.35.0). The target compiler versions are GCC 14.3.1 and ATfE 23.1.0. The selected Lean closure is five modules, listed in each target's `generated/modules.txt`.

This verifies the model execution and listed behaviors, not physical board timing, worst-case interrupt latency, every runtime API, or GDB debugging on the old VM model. The runtime support table records those limits explicitly.

## Measured minimal-profile footprint

The final ELF build-artifact reports give these estimates (bytes):

| Compiler | ROM (`text + data`) | RAM (`data + bss`, including reservations) |
| --- | ---: | ---: |
| GCC 14.3.1 | 448,548 | 359,320 |
| ATfE 23.1.0 | 166,712 | 350,456 |

The RAM totals include the 128 KiB RTX pool, 192 KiB C heap, and 16 KiB MSP reservation. They are demonstration budgets, not a minimum live-heap requirement. Much of GCC's code footprint comes from its C++/C libraries; the minimal Lean module closure remains five modules. The optional standard-console profile has a larger dependency closure and uses a separate 1 MiB SRAM code region.
