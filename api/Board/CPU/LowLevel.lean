module
prelude
public import Board.Error
import Board.Internal.Raw.CPU
import Board.Internal.Context

namespace Board.CPU.LowLevel
public section

def getPRIMASK : IO UInt32 := Internal.Raw.CPU.getPRIMASK
def dsb : IO Unit := Internal.Raw.CPU.dsb
def isb : IO Unit := Internal.Raw.CPU.isb

/-- Restore the exact previous mask on both HAL and IO errors.
Only trusted internal adapters can directly change PRIMASK. -/
def withInterruptsMasked (action : HalM α) : HalM α := do
  Internal.Context.thread
  ExceptT.mk do
    let previous ← Internal.Raw.CPU.getPRIMASK
    Internal.Raw.CPU.disableIRQ
    try action.run finally Internal.Raw.CPU.setPRIMASK previous

end
end Board.CPU.LowLevel
