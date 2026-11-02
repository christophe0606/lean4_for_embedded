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
- The proved timer initialization validator checks all 256 four-command plans, twelve unknown-code cases, and seven period boundaries. The executor runs the valid plan on FVP SysTick and verifies that rejected plans leave its configuration unchanged; see [the sequence example](initialization-example.md).

The minimal profile requires eight PASS markers. The optional Console profile additionally runs Lean-written `Task.spawn`/`Task.map`, `IO.sleep`, and `IO.println`; its ninth PASS marker confirms that normal Lean console code executed. Both Console images are also checked against their current ELF and FVP configuration hashes.

The host compiler and runtime source commit are pinned to `eb6cafb7290e8bd5f2937522d8d804f58f02bafc` (Lean 4.35.0). The target compiler versions are GCC 14.3.1 and ATfE 23.1.0. The selected minimal Lean closure is eleven modules after adding the shared `Board.SysTick.Config` facade, listed in `out/LeanSmokeLib/<target>/Debug/generated/modules.txt`.

This verifies the model execution and listed behaviors, not physical board timing, worst-case interrupt latency, every runtime API, or GDB debugging on the old VM model. The runtime support table records those limits explicitly.

## Measured minimal-profile footprint

Before the shared Board API refactor, the ELF build-artifact reports gave these estimates (bytes):

| Compiler | ROM (`text + data`) | RAM (`data + bss`, including reservations) |
| --- | ---: | ---: |
| GCC 14.3.1 | 452,420 | 359,384 |
| ATfE 23.1.0 | 172,392 | 350,512 |

The RAM totals include the 128 KiB RTX pool, 192 KiB C heap, and 16 KiB MSP reservation. They are demonstration budgets, not a minimum live-heap requirement. Much of GCC's code footprint comes from its C++/C libraries. The optional standard-console profile has a larger dependency closure and uses a separate 1 MiB SRAM code region.

## Shared Board API

Run `python scripts/check-board-api.py` for elaboration/C generation of all
public Board modules and demos, compile-time acceptance/rejection checks for
GPIO pin/driver identities, IRQ identities and gates, and SysTick configuration
bounds, plus the generated FFI signature comparison. These checks do not access
hardware. See [the API guide](board-api.md) for native lifetime requirements.

The CMSIS environment check passed using `.cmsis/tools-environment.yml`
(format 1.0.0, generator `arm.cmsis-csolution` 1.72.0, matching the installed
extension). YAML parsing and validation against that extension's schema passed;
the solution resolved to this workspace's `LeanEmbedded.csolution.yml`, and all
selected tool paths existed. The generated PATH entries and variables were
applied only to the checking process. Toolbox came from the extension's
`tools/cmsis-toolbox/bin/cbuild.exe` and reported 2.15.0. It found CMake 3.31.5,
Ninja 1.12.1, GCC 14.3.1, and Clang 23.1.0 at the generated vcpkg paths, along
with the other installed compiler registrations. No fallback or installation
was needed.

On 2026-11-02, the checked low-level API changes passed all 38 accepted/rejected
compilation cases and the comparison of 84 native signatures. The accepted
cases compose GPIO, interrupt arming, SysTick, USART enable operations and pad
preparation directly from public low-level primitives, including both valid
GPIO pull/direction orders. Rejected cases cover missing prerequisites,
wrong identities, forged handles, exposed raw-call bypasses and missing gates.
They also reject output direction without the returned preload capability,
preload while driving, output through the interrupt API, and USART power-off
with unknown TX/RX enable states.

`python scripts/check-board-runtime.py` passed eight runtime test groups using
the actual Lean modules and native registry core with host peripheral fixtures.
They cover GPIO stale copies and duplicate ownership, actual IRQ gates/bounds
and mask restoration on HAL/IO errors, RTOS context/lock/mask/lifetime guards,
Alif attachment and arming, USART overlap/count/idle-completion/abort guards,
pad mapping/function/ownership checks, SysTick ownership/phase/replay checks,
and Lean resource cleanup on IO exceptions. Unmodeled native calls trap;
fixture signatures are checked against the production bridges.

The actual native registry core passed its host C17 test with MSVC 14.38,
`/W4 /WX`: stale epochs, duplicate ownership, shared retention versus exclusive
deletion, copied release tokens, native address reuse, failure poisoning,
same-state mutations, overlapping/adjacent/wrapping memory ranges, and registry
capacity. This tests the metadata guard;
it does not simulate the peripheral drivers or physical interrupts.

CMSIS builds passed for DevKit-E8 Blinky and minimal, and Corstone300 GCC/Clang
minimal. Blinky loaded on the E8 and printed its normal startup instructions
after the checked GPIO/IRQ setup completed. The target was left running.
No physical joystick press was observed in this verification; earlier joystick
results in the Blinky guide refer to preceding implementations. The new
checked SysTick/USART/PinConfig hardware paths were compiled and ABI checked,
without separate hardware execution of those paths.

The preceding shared-bridge refactor also built the E8 Console profile and
ran the full E8 minimal smoke suite, including seven SysTick boundaries and
256 initialization plans. Those results do not replace the separate FVP
evidence/hash checks above.
