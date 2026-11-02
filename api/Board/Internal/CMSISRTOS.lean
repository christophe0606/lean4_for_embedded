module
prelude
import all Board.CMSISRTOS.LowLevel
public import Board.CMSISRTOS.LowLevel
public import Board.Internal.Resource

namespace Board.Internal.CMSISRTOS
public section

/-- Recover only an existing live checked owner, never claim an arbitrary native ID. -/
def fromNative (raw : USize) : HalM Board.CMSISRTOS.LowLevel.EventFlagsId := do
  let lease ← Resource.find 3 raw
  return Board.CMSISRTOS.LowLevel.EventFlagsId.mk raw lease

/-- Keep this operation token in the native binding until its ISR is detached.
Release exactly once only after the source and NVIC line are closed. -/
def retain (id : Board.CMSISRTOS.LowLevel.EventFlagsId) : HalM UInt32 :=
  Resource.acquire id.lease

def threadEntry (function argument attributes : USize) : HalM Board.CMSISRTOS.LowLevel.ThreadEntry := do
  if function == 0 then throw (.invalidState "null native thread entry")
  if attributes != 0 then
    throw (.invalidState "checked thread creation requires RTX-owned attributes, stack and control block")
  let lease ← Resource.claim 8 function
  return Board.CMSISRTOS.LowLevel.ThreadEntry.mk function argument attributes lease

end
end Board.Internal.CMSISRTOS
