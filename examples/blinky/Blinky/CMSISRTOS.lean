module
prelude
public import Board.CMSISRTOS
public import Blinky.NVIC
import Board.Internal.CMSISRTOS
import Board.Internal.NVIC
import Blinky.Internal.Platform

namespace Blinky.CMSISRTOS
public section
abbrev EventFlagsId := Board.CMSISRTOS.EventFlagsId
abbrev Flags := Board.CMSISRTOS.Flags
def Flags.buttonPress : Flags := Board.CMSISRTOS.Flags.single ⟨0, by decide⟩

namespace EventFlags
abbrev new := Board.CMSISRTOS.EventFlags.new
abbrev set := Board.CMSISRTOS.EventFlags.set
abbrev delete := Board.CMSISRTOS.EventFlags.delete
def wait (id : EventFlagsId) (flags : Flags) (timeoutMs : UInt32) : HalM Bool := do
  let frequency ← fromIO Board.CMSISRTOS.LowLevel.kernelGetTickFreq
  let ticks := (timeoutMs.toNat * frequency.toNat + 999) / 1000
  if ticks >= 0xFFFFFFFF then throw (.invalidState "event timeout exceeds finite RTOS range")
  Board.CMSISRTOS.EventFlags.wait id flags ticks.toUInt32
end EventFlags

namespace ButtonEventSink
/-- This read does not extend ownership: native binding already retains the object. -/
def current : HalM EventFlagsId := do
  let raw ← fromIO Internal.Platform.currentEvents
  if raw == 0 then throw .eventSinkUnbound
  Board.Internal.CMSISRTOS.fromNative raw

def bind (id : EventFlagsId) : NVIC.GateM .blocked .disabled Unit :=
  Board.Internal.NVIC.lift (Internal.Platform.bindEvents id)
end ButtonEventSink
end
end Blinky.CMSISRTOS
