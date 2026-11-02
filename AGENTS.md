Don't install nix

On a mac, to launch FVP:

* Use linuxvm identity to ssh in the VM containing the FVP
* Use /Volumes/Ext/VM_SharedFolder to share files with the VM. It contains bash script to launch the FVP. They must be run from inside the VM. The shared folder can be used to copy the elf before running it with FVP.

If you need to clone git repo, don't clone history. Use depth one to avoid downloading too many things.

FVP must not display any UI (we don't have one in the VM). So UI should be disabled in FVP config options.

Original lean c/cpp runtime must not be modified directly to make it easier to update. Changes should be recorded as a patch to apply to the original sources.

cmake is only used for the lean part. The remaining part of the build is handled as usual with csolution, cproject and CMSIS packs and components.
cmake should be kept to the minimum required to build the lean part.

Don't save any private info in this repo like keys, certificates, pass etc ...

## CMSIS APIs used by new demos

When a new demo introduces a CMSIS component or a device/system-header API
(such as NVIC), make its Lean bindings reusable under the shared `Board` library:

- Reuse or extend the existing API first. For a new interface, create
  `api/c/bridge_<component>.c`, `api/Board/Internal/Raw/<Component>.lean`,
  and `api/Board/<Component>/LowLevel.lean`.
  Keep one bridge per interface; do not put generic bindings in a demo.
- The C bridge mirrors native operations, arguments, return values, constants, and
  units. Preserve integer widths and signedness (`Int32` for signed statuses
  and IRQ numbers, `UInt8` where required); use `USize` for native pointers and
  handles. Check the selected pack's headers and documentation rather than
  guessing the API. Keep the bridge a thin forwarding layer. Any unchecked
  Lean FFI declarations belong to an explicitly internal/unsafe binding module;
  they are not the public low-level API and must not be re-exported as such.
- For every API, the public `Board.<Component>.LowLevel` layer exposes
  elementary operations and enforces their invariants. Express each operation's
  required state, valid arguments, resource identity, and resulting state in its
  types, using private constructors, indexed actions/handles, or proof arguments.
  A state transition is permitted only after the underlying operation succeeds.
  Reject invalid initialization/use order and missing interrupt gates at this
  layer, even when the caller writes the complete flow in application code.
- A comment, docstring, example, or caller instruction is never enforcement of
  a low-level API constraint. Every required precondition, ordering dependency,
  ownership/lifetime condition, and postcondition must be enforced by the API:
  use indexed types, private constructors, propositions/proof arguments and
  theorems where appropriate, with executable guards for dynamic facts. Check
  dynamic preconditions before hardware effects. A documented requirement with
  no enforcing type/proof/check is an implementation defect, not a completed
  API. Do not mark a review complete while such defects remain.
- Audit every public low-level entry point, including alternate operations
  that could bypass an invariant. Map each stated constraint to its enforcing
  definition and accepted/rejected or runtime regression tests. Check that
  returned states follow from successful operations; do not simply assign a
  stronger phantom state. For example, output enable must require evidence of
  a successful latch preload when the API promises a known initial output.
  Preload must return the updated capability, and stale copies must fail too.
- Keep genuinely external facts (such as a native symbol's valid address) at
  an explicit internal FFI/board boundary. Validate everything that can be
  checked there, and do not move an enforceable public precondition into a
  comment on a trusted adapter. State the remaining trusted facts separately
  from guarantees enforced by the public API.
- Low-level operations do not implement a complete initialization flow or
  choose and execute a state-machine path. They define and enforce the legal
  transitions. Higher-level modules (`api/Board/<Component>.lean`) and demos
  compose those primitives into flows. Functions such as `GPIO.setupInput` are
  conveniences: an application must be able to write an equivalent valid
  sequence itself, with the same low-level protection. Hiding primitive steps
  inside a private convenience implementation is not sufficient enforcement.
- Enforce actual hardware/driver requirements, not the incidental order chosen
  by a convenience function. For example, require Setup before configuration
  when the interface requires it; require SetPullResistor before SetDirection
  only if the applicable hardware/driver documentation establishes that order.
  Allow other documented valid orderings. Record the source of each restriction.
- Apply these rules to all APIs, including GPIO, NVIC/CPU, RTOS, SysTick, USART,
  and vendor helpers, and when extending existing APIs. Do not expose an
  unrestricted operation through another public module that bypasses the
  checked low-level interface. Explicit internal/unsafe adapters are trusted
  boundaries and must document which invariants their callers must establish.
- Propagate failures and preserve or invalidate state appropriately on errors;
  restore temporary hardware state when required. Lean values are not linear:
  a copyable state token alone does not establish exclusive ownership or prevent
  replay after a transition. Enforce dynamic lifetime, stale-handle, repeated-use,
  and concurrency constraints at the low-level boundary with runtime checks or
  scoped execution where static enforcement is insufficient. Document remaining
  external ownership assumptions without presenting them as proved guarantees.
- Keep board pin mappings, driver-instance selection, IRQ identities, and
  application policy in board/demo adapters. Interrupt callbacks must remain
  native C and must not call the Lean runtime; document asynchronous buffer
  lifetimes and callback requirements.
- Add or extend a reusable `api/<Component>.clayer.yml` and include it from
  the demo's cproject. CMSIS selects components, compiles bridges, and links
  firmware; CMake only tracks and builds the Lean sources/runtime. Add portable
  modules to `api/Board.lean`; keep vendor-specific imports opt-in. Demos should
  import the smallest submodules they need.
- Extend `scripts/check-board-api.py` to cover new modules, generated FFI
  signatures, and application-written compositions of low-level primitives.
  Include accepted valid orderings and compile-fail tests for omitted/reordered
  prerequisites, wrong resource identities, and invalid state transitions;
  test dynamic guards where types alone cannot enforce an invariant. Testing
  only the supplied convenience functions is insufficient. Extend and run
  `scripts/check-board-runtime.py` for Lean guards against host peripheral
  fixtures and `scripts/test-resource-state.c` for native ownership metadata.
  Build the affected CMSIS targets with `cmsis_action`, and verify relevant
  target behavior. Update `docs/board-api.md` and record what was actually
  verified, including any remaining runtime limits.
