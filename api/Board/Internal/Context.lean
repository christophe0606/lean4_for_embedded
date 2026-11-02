module
prelude
public import Board.Error
import Board.Internal.Raw.CPU

namespace Board.Internal.Context
public section

def thread : HalM Unit := do
  if (← fromIO Raw.CPU.getIPSR) != 0 then
    throw (.invalidState "checked APIs require thread context")

def interruptsOpen : HalM Unit := do
  thread
  if (← fromIO Raw.CPU.getPRIMASK) != 0 ||
      (← fromIO Raw.CPU.getBASEPRI) != 0 || (← fromIO Raw.CPU.getFAULTMASK) != 0 then
    throw (.invalidState "operation requires unmasked interrupts")

end
end Board.Internal.Context
