module
prelude
public import Board.SysTick.Config
public import Board.Error
public import Board.CPU.LowLevel
import Board.Internal.Resource
import Board.Internal.Context
import Board.Internal.Raw.SysTick
import Board.Internal.Raw.CMSISRTOS

namespace Board.SysTick.LowLevel
public section

inductive State where | acquired | stopped | loaded | cleared | running
structure Timer (_state : State) where
  private mk ::
  private lease : Internal.Resource.Lease

private def requireOwnership : HalM Unit := do
  Internal.Context.thread
  if (← fromIO Internal.Raw.CMSISRTOS.kernelGetState) != 0 then
    throw (.invalidState "SysTick belongs to the initialized RTOS kernel")

def acquire : HalM (Timer .acquired) := do
  requireOwnership
  if (← fromIO Internal.Raw.SysTick.getCTRL) &&& 3 != 0 then
    throw (.invalidState "SysTick is already enabled or has an interrupt owner")
  return Timer.mk (← Internal.Resource.claim 2 0)

private def step (timer : Timer before) (action : IO Unit) : HalM (Timer after) := do
  requireOwnership
  let (lease, _) ← Internal.Resource.transition timer.lease (fromIO action)
  return Timer.mk lease

def stop (timer : Timer state) : HalM (Timer .stopped) :=
  step timer do
    Internal.Raw.SysTick.setCTRL 0
    CPU.LowLevel.dsb

def load (timer : Timer .stopped) (config : Config period) : HalM (Timer .loaded) :=
  step timer (Internal.Raw.SysTick.setLOAD config.reload.val.toUInt32)

def clear (timer : Timer .loaded) : HalM (Timer .cleared) :=
  step timer (Internal.Raw.SysTick.setVAL 0)

/-- Polling timer. Installing a native SysTick handler is a separate trusted
ownership contract; this API does not enable an unowned interrupt. -/
def start (timer : Timer .cleared) : HalM (Timer .running) :=
  step timer do
    Internal.Raw.SysTick.setCTRL 5
    CPU.LowLevel.dsb

def read (timer : Timer .running) : HalM UInt32 := do
  requireOwnership
  Internal.Resource.use timer.lease (fromIO Internal.Raw.SysTick.getVAL)

def release (timer : Timer .stopped) : HalM Unit := do
  requireOwnership
  Internal.Resource.close timer.lease (pure ())

end
end Board.SysTick.LowLevel
