module
prelude
public import Blinky.Platform
public import Board.CMSISRTOS.LowLevel
import Board.Internal.CMSISRTOS
import Board.Internal.NVIC

namespace Blinky.Internal.Platform
public section
-- Trusted native ISR adapter; callers establish both closed gates.
@[extern "lean_blinky_claim_setup"] opaque claimSetup (selector : UInt32) : IO UInt32
@[extern "lean_blinky_bind_events"] private opaque bindEventsRaw (id : USize) (retention : UInt32) : IO UInt32
@[extern "lean_blinky_current_events"] opaque currentEvents : IO USize
@[extern "lean_blinky_current_retention"] private opaque currentRetention : IO UInt32

def bindEvents (id : Board.CMSISRTOS.LowLevel.EventFlagsId) : Board.HalM Unit := do
  let operation ← Board.Internal.CMSISRTOS.retain id
  let old ← Board.fromIO currentRetention
  let status ← Board.fromIO (bindEventsRaw id.toUSize operation)
  if status != 0 then
    Board.Internal.Resource.release operation
    throw (.rtos "button event binding" status)
  if old != 0 then Board.Internal.Resource.release old
end
end Blinky.Internal.Platform
