module
prelude
public import Blinky.HalError

/-! GateM cpu line α is an action that runs with the named interrupt gates
closed. There is no copyable "currently disabled" token: a gated action can
only be executed by a bracket that establishes its required hardware state. -/
namespace Blinky.NVIC

public section

inductive CpuGate where
  | open | blocked

inductive LineGate where
  | enabled | disabled

structure GateM (_cpu : CpuGate) (_line : LineGate) (α : Type) where
  private mk ::
  private run : HalM α

private def GateM.wrap (action : HalM α) : GateM cpu line α := ⟨action⟩

def GateM.pure (value : α) : GateM cpu line α := GateM.wrap (ExceptT.pure value)

def GateM.bind (action : GateM cpu line α) (next : α → GateM cpu line β) :
    GateM cpu line β := GateM.wrap do
  let value ← action.run
  (next value).run

instance : Monad (GateM cpu line) where
  pure := GateM.pure
  bind := GateM.bind

/-- Trusted adapter for an elementary HAL operation that preserves both gate
states. This is the boundary where an IO action enters the typed protocol;
callers must not lift an operation that changes PRIMASK or this NVIC line. -/
def GateM.fromHal (action : HalM α) : GateM cpu line α := GateM.wrap action

/-- Only an action requiring both gates open can run directly. -/
def runOpen (action : GateM .open .enabled α) : HalM α := action.run

@[extern "lean_hal_nvic_mask_all"] private opaque maskAllRaw : IO UInt32
@[extern "lean_hal_nvic_restore_all"] private opaque restoreAllRaw (previous : UInt32) : IO UInt32
@[extern "lean_hal_nvic_disable_irq"] private opaque disableRaw : IO UInt32
@[extern "lean_hal_nvic_enable_irq"] private opaque enableRaw : IO UInt32
@[extern "lean_hal_nvic_clear_pending_irq"] private opaque clearPendingRaw : IO UInt32
@[extern "lean_hal_nvic_set_priority"] private opaque setPriorityRaw (priority : UInt32) : IO UInt32

/-- Run the action under PRIMASK, restoring its previous value even on error.
An action may be saved and run later, but each run gets its own mask bracket. -/
def masked (action : GateM .blocked line α) : GateM .open line α := GateM.wrap do
  let previous ← fromIO maskAllRaw
  try
    action.run
  finally
    let _ ← fromIO (restoreAllRaw previous)

/-- Disable LPGPIO IRQ4 for button initialization. Enable it only if the
typed setup action completes; an unsuccessful setup leaves the line disabled. -/
def initializeLine (action : GateM .open .disabled α) : GateM .open .enabled α := GateM.wrap do
  let _ ← fromIO disableRaw
  let value ← action.run
  let previous ← fromIO maskAllRaw
  try
    let _ ← fromIO enableRaw
  finally
    let _ ← fromIO (restoreAllRaw previous)
  return value

/-- Rebinding an already configured button is temporary: always restore the
NVIC line before leaving the CPU-masked region, including on a typed error. -/
def temporarilyDisabled (action : GateM .blocked .disabled α) :
    GateM .blocked .enabled α := GateM.wrap do
  let _ ← fromIO disableRaw
  try
    action.run
  finally
    let _ ← fromIO enableRaw

/-- The pack's Setup enables this NVIC line internally. Close it again before
the enclosing CPU mask is restored. -/
def closeLineAfterSetup : GateM .blocked .disabled Unit := GateM.wrap do
  let _ ← fromIO disableRaw

def clearPendingIRQ : GateM .blocked .disabled Unit := GateM.wrap do
  let _ ← fromIO clearPendingRaw

def setPriority (priority : UInt32) : GateM .blocked .disabled Unit := GateM.wrap do
  let _ ← fromIO (setPriorityRaw priority)

end
end Blinky.NVIC
