module
prelude
import all Board.USART.LowLevel
public import Board.USART.LowLevel
public import Board.Internal.Resource

namespace Board.Internal.USART
public section

/-- The instance must remain valid and be exclusively yielded by native firmware. -/
def instance_ (address : USize) : Board.USART.LowLevel.Instance :=
  Board.USART.LowLevel.Instance.mk address

/-- Trusted permanent memory, accessible by the selected driver/DMA. Capacity
must be truthful; the registry rejects overlapping ranges. No native or
Lean code may touch it while a transfer owns it. -/
def buffer (address : USize) (capacity : UInt32) : HalM Board.USART.LowLevel.Buffer := do
  if address == 0 || capacity == 0 then throw (.invalidState "invalid USART native storage")
  let lease ← Resource.claimRange 5 address capacity.toUSize
  return Board.USART.LowLevel.Buffer.mk address capacity lease
end
end Board.Internal.USART
