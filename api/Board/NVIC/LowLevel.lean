module
prelude
public import Board.Error
public import Board.CPU.LowLevel
import Board.Internal.Raw.NVIC
import Board.Internal.Resource
import Board.Internal.Context

namespace Board.NVIC.LowLevel
public section

/-- CPU interrupt-delivery requirement: `blocked` requires PRIMASK = 1;
`open` imposes no PRIMASK requirement and does not assert interrupts are enabled. -/
inductive CpuGate where | open | blocked
/-- IRQ-line delivery requirement: `disabled` requires this IRQ's NVIC enable
bit to be 0; `enabled` imposes no requirement and does not assert it is 1. -/
inductive LineGate where | enabled | disabled

/-- An action indexed by IRQ identity and interrupt-delivery requirements.
For example, `GateM irq .blocked .disabled Unit` requires both CPU and line
gates closed during execution, with runtime checks at elementary action boundaries.
Open/enabled impose no closed-gate requirement. Closing a delivery gate neither
clears pending interrupts nor mutes the peripheral's own interrupt source. -/
structure GateM (irq : UInt32) (_cpu : CpuGate) (_line : LineGate) (α : Type) where
  private mk ::
  private run : HalM α

@[extern "lean_board_nvic_irq_count"] private opaque irqCount (_unit : Unit) : UInt32

private def validate (irq : UInt32) : HalM Unit := do
  Internal.Context.thread
  if irq >= 240 || irq >= irqCount () then
    throw (.invalidState "IRQ outside implemented supported external NVIC range")

private def requireGates (irq : UInt32) (cpu : CpuGate) (line : LineGate) : HalM Unit := do
  validate irq
  match cpu with
  | .open => pure ()
  | .blocked =>
    if (← fromIO CPU.LowLevel.getPRIMASK) != 1 then
      throw (.invalidState "CPU gate is not closed")
  match line with
  | .enabled => pure ()
  | .disabled =>
    if (← fromIO (Internal.Raw.NVIC.getEnableIRQ irq.toInt32)) != 0 then
      throw (.invalidState "NVIC line gate is not closed")

private def GateM.wrap (action : HalM α) : GateM irq cpu line α := ⟨do
  requireGates irq cpu line
  let result ← action
  requireGates irq cpu line
  return result⟩

def GateM.pure (value : α) : GateM irq cpu line α := GateM.wrap (ExceptT.pure value)
def GateM.bind (action : GateM irq cpu line α) (next : α → GateM irq cpu line β) :
    GateM irq cpu line β := GateM.wrap do
  (next (← action.run)).run

instance : Monad (GateM irq cpu line) where
  pure := GateM.pure
  bind := GateM.bind

/-- Execute an action with no remaining closed-gate requirements.
This does not enable CPU interrupts or the NVIC line. -/
def runOpen (action : GateM irq .open .enabled α) : HalM α := do
  validate irq
  action.run

/-- Close the CPU gate for the action and restore the exact previous PRIMASK,
including on HAL and IO errors. -/
def masked (action : GateM irq .blocked line α) : GateM irq .open line α :=
  GateM.wrap (CPU.LowLevel.withInterruptsMasked action.run)

/-- Disable for the scope, restoring the previous enable state on all errors. -/
def disabled (action : GateM irq cpu .disabled α) : GateM irq cpu .enabled α :=
  GateM.wrap <| Internal.Resource.serialized 7 irq.toUSize do
    validate irq
    let previous ← fromIO (Internal.Raw.NVIC.getEnableIRQ irq.toInt32)
    fromIO (Internal.Raw.NVIC.disableIRQ irq.toInt32)
    ExceptT.mk <| try action.run.run finally
      if previous != 0 then Internal.Raw.NVIC.enableIRQ irq.toInt32
      else Internal.Raw.NVIC.disableIRQ irq.toInt32

/-- Enable only after successful initialization. Failure leaves the line closed. -/
def initializeLine (action : GateM irq .open .disabled α) : GateM irq .open .enabled α :=
  GateM.wrap <| Internal.Resource.serialized 7 irq.toUSize do
    validate irq
    fromIO (Internal.Raw.NVIC.disableIRQ irq.toInt32)
    ExceptT.mk do
      try
        match ← action.run.run with
        | .ok result =>
          Internal.Raw.NVIC.enableIRQ irq.toInt32
          return .ok result
        | .error error =>
          Internal.Raw.NVIC.disableIRQ irq.toInt32
          return .error error
      catch error =>
        Internal.Raw.NVIC.disableIRQ irq.toInt32
        throw error

def clearPendingIRQ : GateM irq .blocked .disabled Unit :=
  GateM.wrap (fromIO (Internal.Raw.NVIC.clearPendingIRQ irq.toInt32))

@[extern "lean_board_nvic_priority_bits"] private opaque priorityBits (_unit : Unit) : UInt32

def setPriority (priority : UInt32) : GateM irq .blocked .disabled Unit := GateM.wrap do
  if priority.toNat >= 2 ^ (priorityBits ()).toNat then
    throw (.invalidState "NVIC priority exceeds implemented priority bits")
  fromIO (Internal.Raw.NVIC.setPriority irq.toInt32 priority)

end
end Board.NVIC.LowLevel
