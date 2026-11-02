# Shared Board APIs

The `Board` Lake library lives under `api/`. Its public low-level modules
expose checked elementary operations. Convenience modules and applications
compose those operations into initialization and operating flows.

| Public module | Checked operations |
| --- | --- |
| `Board.GPIO.LowLevel` | Setup, direction, pull, output mode, latch/output writes, input reads, native callback setup and edge selection |
| `Board.NVIC.LowLevel` | IRQ-specific gated actions, mask/disable scopes, pending clear and bounded priority |
| `Board.CPU.LowLevel` | Mask query, barriers and a mask scope that restores the previous state |
| `Board.CMSISRTOS.LowLevel` | Kernel lifecycle/lock scopes, delay, event flags and native thread entries |
| `Board.SysTick.LowLevel` | Exclusive acquisition, stop, load, clear, polling start/read and stopped release |
| `Board.USART.LowLevel` | Initialization, power, asynchronous 8N1 configuration, TX/RX enable, bounded transfers, completion and abort |
| `Board.AlifGPIO.LowLevel` | Configured interrupt attachment, EOI, source unmask/enable/disable and pending clear |
| `Board.PinConfig.LowLevel` | Exclusive pad preparation and checked alternate-function selection |

Raw one-to-one FFI declarations are in `Board.Internal.Raw.*`, privately
imported by the implementations. They preserve native integer widths,
signed statuses/IRQ numbers, pointer-sized addresses, constants and units.
They are not re-exported by the public modules. The thin C bridges remain
under `api/c/`; their unchecked arguments are only used at this trusted boundary.

## GPIO operations and application-written flows

`setup` returns a private-constructor `Pin driver number .ready`.
`setDirection` returns a handle indexed by the resulting direction.
`setOutput` requires an output and `getInput` requires an input. Driver
and pin indices prevent substituting a different resource.

`Pin driver number state preloaded` also records latch evidence. Output
direction requires a proof that `preloaded = true`. `preloadOutput` accepts
only a non-output pin, writes the latch, and returns that evidence in a new
capability; its runtime epoch invalidates copies of the previous handle.
Ignoring the returned capability cannot satisfy the output prerequisite.
Callback pins only admit input direction, so they cannot bypass this rule.

```lean
def output (driver : Board.GPIO.LowLevel.Driver) (pin : UInt32) :
    Board.HalM (Board.GPIO.Output driver.address pin) := do
  let ready ← Board.GPIO.LowLevel.setup driver pin
  let preloaded ← Board.GPIO.LowLevel.preloadOutput ready false
  Board.GPIO.LowLevel.setDirection preloaded .output
```

An application can implement the same input setup as the convenience function:

```lean
module
prelude
public import Board.GPIO

def input (driver : Board.GPIO.LowLevel.Driver) (pin : UInt32) :
    Board.HalM (Board.GPIO.Input driver.address pin) := do
  let ready ← Board.GPIO.LowLevel.setup driver pin
  Board.GPIO.LowLevel.setPullResistor ready .up
  Board.GPIO.LowLevel.setDirection ready .input
```

Setting direction before pull is also accepted: retain the returned input
handle and pass it to `setPullResistor`. CMSIS 6.3.0 `Driver_GPIO.h` and
Ensemble 2.2.1 `Alif_CMSIS/Source/Driver_GPIO.c` do not impose a pull-before-
direction dependency. Output enable after a successful latch preload is the
checked API's known-initial-output contract. CMSIS Setup and the selected
Alif implementation establish input direction first. `Board.GPIO.setupOutput`
composes these elementary operations; callers may write the same flow.

A `Driver` is supplied by a trusted board adapter, which establishes a valid
permanent native pointer and a predicate of pins yielded exclusively to GPIO.
The predicate excludes native and other-peripheral owners; Blinky yields only
its six LED pins and center button. Applications cannot forge driver
addresses through the checked interface.

Callback pins have a distinct `InterruptPin` type. Their operations require
the matching IRQ's gate scope; a callback pin cannot be used through the
ungated polled API. Native Setup is one elementary operation. Because Alif
Setup opens the source and NVIC internally, its adapter closes both before
returning under the CPU mask, including on failure. The application then
chooses pull, direction, edge and arming operations. Trigger selection requires
an input; Alif source operations require that configured callback pin and a
matching native source mapping.

The Alif arming contract clears stale pending status before exposing the
source: EOI, unmask, then enable, under closed CPU and NVIC gates. This is the
API's pending-event safety contract; it is not a claim that every other register
write ordering is physically forbidden. A caller chooses when to take these
transitions; low-level functions do not execute the complete button setup.

## Gates, lifetimes and errors

A **gate** is an interrupt mask or enable condition that controls interrupt
delivery. It is the API's name for these conditions, not a separate CMSIS
object. The API tracks two gates:

| Gate | Hardware condition required when closed | Type index |
| --- | --- | --- |
| CPU | PRIMASK is 1, globally masking configurable interrupts | `CpuGate.blocked` |
| IRQ line | The selected IRQ's NVIC enable bit is 0 | `LineGate.disabled` |

`GateM irq .blocked .disabled Unit` describes an action that requires both
gates closed while it executes. Its `irq` index identifies the particular
NVIC line; the CPU mask applies globally. `.open` and `.enabled` mean **no
closed-gate requirement** for their respective gates. These names do not
assert that interrupts are currently enabled, and `runOpen` does not enable
them.

For example, an application can clear an IRQ's pending state inside the
required scopes:

```lean
def clearPending (irq : UInt32) : Board.HalM Unit :=
  Board.NVIC.runOpen (irq := irq) <|
    Board.NVIC.masked <|
      Board.NVIC.temporarilyDisabled Board.NVIC.clearPendingIRQ
```

`masked` establishes the CPU requirement; `temporarilyDisabled` (named
`disabled` in `Board.NVIC.LowLevel`) establishes the IRQ-line requirement.
Both scopes restore the previous state afterward, including on errors.
Closing these gates prevents interrupt delivery through them; it does not
clear pending interrupts or disable interrupt generation inside the
peripheral. Clearing pending state and muting the peripheral source are
separate operations.

`GateM irq cpu line α` scopes requirements to execution. A saved gated
action must enter the scopes again every time it runs. `blocked` and
`disabled` guarantee closed gates; `open` and `enabled` impose no such
requirement and do not assert that a previously disabled gate is open.
Mask scopes restore the exact previous PRIMASK on HAL and IO errors. Disable
scopes restore the prior line state. Initialization enables the line only after
success; failure leaves it disabled. An IRQ-specific operation mutex prevents
another thread's scope from reopening the line during a disabled scope.
Gate requirements are checked against actual PRIMASK and NVIC enable state
before and after each elementary gated action, including internal lifts.
Supported external IRQs are bounded below 240 and by the device's ICTR line
count; priorities are checked against the device's `__NVIC_PRIO_BITS`.
There is no public unrestricted `GateM.fromHal` or raw mask/IRQ setter.

Lean handles are copyable. Every checked resource therefore also carries a
hidden runtime lease. Successful state transitions advance its epoch, so a
saved old handle is rejected before another native operation. Same-state
operations serialize without invalidating the current owner. Duplicate setup,
conflicting operations, deletion during use, and replayed releases are rejected.
A driver-wide operation mutex also protects GPIO calls across different pins:
Ensemble 2.2.1 `drivers/include/gpio.h` uses read/modify/write on shared port
direction and output registers. Contention rejects the call before consuming
its pin transition. The mutex is released on every HAL or IO exit.
A failed mutating operation poisons the resource until reset, since its actual
hardware state may be uncertain. HAL failures and IO exceptions both release
or invalidate the corresponding operation guard.

The registry supports 32 resource identities and 64 simultaneous operations.
Tickets and operation IDs never wrap; exhaustion fails closed. Only bounded
registry metadata updates mask interrupts; blocking RTOS waits do not hold
PRIMASK. The implementation supports one Cortex-M core and checks IPSR for
thread context before resource acquisition and gated operations.
Other cores and native firmware must honor ownership; the registry cannot
protect against an unrelated C write or DMA access.

Event flags use checked nonzero 31-bit masks. Wait timeouts are kernel ticks;
timeout and an empty zero-time poll return `false`. Deletion needs exclusive
access, rejects active waits or native callback retention, and invalidates all
copies even if RTX later reuses the address. Blinky retains the object while
its native ISR slot points to it, and releases the previous retention only
after rebinding under both closed gates. Raw event-ID borrowing is internal.
Blocking calls check that the kernel is running/unlocked and PRIMASK, BASEPRI,
and FAULTMASK are clear. Kernel lifecycle, object creation/deletion, thread
creation, and lock scopes check their execution context too. Native thread
entry descriptors are single-use leases. The checked subset accepts only
default RTX-owned attributes, stack and control block; arbitrary static
attributes require additional lifetime/ownership evidence before exposure.

SysTick uses public phase-indexed primitives, each guarded by the same runtime
lease. `Config period` retains the nonzero 24-bit reload and exact-period
proofs from HardwareContracts. A running or uncleared timer cannot be loaded
or started through the wrong primitive. Kernel initialization and direct
SysTick acquisition share an ownership key; direct timer operations also
reject an initialized RTX kernel. Acquisition also reads CTRL and rejects an
already enabled timer or enabled SysTick interrupt. Native startup must yield
ownership too.
The checked timer API starts a polling timer, without enabling an unowned
handler. Smoke imports only the pure `Board.SysTick.Config` facade and retains
its separate bounded RTX snapshot/restore test executor.

USART exposes a limited checked subset: callback-free asynchronous 8N1,
separate TX/RX enable operations in either order, and one active transfer per
instance. Format configuration returns unknown TX/RX enable states; explicit
enable operations establish their `Option Bool` indices. Power-off requires
both sides explicitly disabled. Initialization, control operations and transfer
submission check the actual driver busy flags before forwarding mutations.
Transfers require a permanent native buffer descriptor with truthful capacity
and a valid DMA-accessible address. Native address validity/capacity belongs to
the trusted adapter; null, empty, wrapping and overlapping registered ranges
are rejected by the API/registry. The buffer remains exclusively
reserved until completion or successful abort; power/configuration operations
cannot accept an active transfer. A failed transfer leaves uncertain hardware
and storage reserved. Completion requires the requested count and the native
busy flag to clear. Abort also verifies idle before releasing storage; an
acknowledged abort that remains busy fails closed. Full duplex and other serial
formats are not yet exposed.

PinConfig uses the same driver/pin ownership key as GPIO. A live GPIO owner
prevents remuxing. Preparation descriptors are single-use runtime leases:
copying an old descriptor cannot reacquire a pad after its ownership is handed
off. The pack adapter supplies the exact port/pin mapping and
allowed alternate functions; the public operation limits function width and
checks the mapping before the native call.

Expected native failures remain structured `HalError` values with status bit
patterns preserved. Argument/state guards precede the corresponding hardware
mutation; dynamic guards can read native state. No capability proves facts that the board adapter or other firmware
has not established.

## Board adapters, layers and extension

`Board.Internal.*` adapters are explicit trusted boundaries. They can construct
native instance/source/buffer descriptors, recover existing checked event
owners, retain ISR objects, and lift actions with gate checks at entry/exit.
They are privately imported where needed, never re-exported by a convenience
module. Deliberately importing these internals or using `import all` opts out
of the checked boundary; Lean module privacy is not a security sandbox.

The remaining trusted facts are native symbol/address validity, actual storage
capacity and DMA accessibility, the device/package mapping predicates, and
native callback/entry code honoring ownership and not calling Lean from an
ISR. These describe external native code and memory. They do not replace
public ordering, state, context or lifetime checks with caller instructions.

## Constraint review

Comments state contracts; the definitions below enforce them. The compilation
suite is `scripts/check-board-api.py`. The host runtime suite is
`scripts/check-board-runtime.py`, which links the actual Lean modules and
`resource_state.c` to simulated peripheral bridges. Unmodeled native calls trap.

| API | Enforcement | Regression coverage |
| --- | --- | --- |
| GPIO | Private driver/pin constructors, state/resource indices, preload and input-only proofs, whitelist, epoch transitions, per-driver mutex | Valid pull/direction orders; rejected missing/discarded preload, interrupt output bypass and identities; runtime stale copies and duplicate setup |
| NVIC | Private indexed `GateM`, IRQ/priority bounds, actual gate checks, per-IRQ mutex, restoring scopes | Missing scopes/wrong IRQ compile failures; runtime bounds, gate postconditions and restored line/mask |
| CPU | Thread-context guard and `finally` restoring exact PRIMASK; raw setters internal | Raw bypass compile failure; runtime HAL and IO exception restoration |
| CMSISRTOS | Context/kernel guards, private checked masks/IDs, retained operation leases, exclusive deletion, single-use native entry | Forged masks/IDs compile failures; runtime CPU masks, locked scheduler, retained/stale events and entry replay |
| SysTick | Private phase handles, proved `Config`, shared kernel ownership key, actual CTRL/kernel guards and epochs | Missing/reordered phases and invalid reload compile failures; runtime ownership, replay and release |
| USART | Private phase/enable indices, idle guards, capacity checks, nonoverlapping buffer leases, pinned storage until idle completion/abort | Power/config/enable and forged buffer compile failures; runtime counts, overlap, busy completion, failed abort and stale driver |
| AlifGPIO | Matching pin/source/IRQ indices, checked source-disabled attachment, gated phase transitions and epochs | Wrong identity/arming order compile failures; runtime native Setup cleanup, arming and enabled-source rejection |
| PinConfig | Validated pad mapping, bounded/allowed function, shared GPIO ownership, single-use preparation lease | Forged descriptor compile failure; runtime mapping, function limits, GPIO conflict and replay |

The C registry suite independently tests operation replay, concurrent retention,
failure poisoning, address reuse, overlapping/wrapping ranges and bounded
capacity. Host peripherals verify API behavior, not physical electrical timing
or arbitrary native firmware outside the ownership boundary.

Board pin mappings, callback pointers, IRQ identities and application policy
stay in the board/demo. Callbacks and RTOS thread entries are native C, never
Lean closures; interrupt context must never enter the Lean runtime.

CMSIS layers compile and link the bridges: `Core.clayer.yml` provides
CPU/NVIC/RTOS/SysTick and the resource registry; `GPIO.clayer.yml` selects
Driver:GPIO; `USART.clayer.yml` uses the board's USART component;
`Alif.clayer.yml` supplies the Alif helpers and PINCONF dependency.
The cproject supplies upstream Lean headers and the board's core/RTX/device
components. CMake only builds Lean-generated code and the patched runtime.

For a new component, add a thin bridge and internal raw declarations, then
public elementary checked primitives. Define valid arguments, identity,
preconditions, postconditions and failure/lifetime behavior there. Put chosen
flows in the convenience module or application. Follow [AGENTS.md](../AGENTS.md).

Run `python scripts/check-board-api.py` for module compilation,
application-written valid compositions, compile-fail misuse cases and generated
FFI signature checks. The native registry test uses the actual target core
implementation without MCU dependencies:

```sh
cc -std=c11 -Wall -Wextra -Werror -Iapi/c scripts/test-resource-state.c api/c/resource_state.c -o .build/test-resource-state
.build/test-resource-state
```

On Windows, the same test builds from a Visual Studio developer prompt with
`cl /std:c17 /W4 /WX /Iapi/c scripts/test-resource-state.c api/c/resource_state.c /Fe:.build/test-resource-state.exe /Fo:.build/`.
Firmware verification uses CMSIS tools; see [validation](validation.md).

Run `python scripts/check-board-runtime.py` for the Lean runtime guard suite.
It uses the pinned host Lean compiler, builds under `.build/board-api-runtime`,
and does not access hardware or change the production Lake configuration.
