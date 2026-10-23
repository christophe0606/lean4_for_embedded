module
prelude
public import Blinky.NVIC

/-! Typed handles and flag masks for the CMSIS-RTOS event-flags API. Lean
creates event objects; the button ISR and Lean's wait use one guarded binding
to the current object. A raw handle cannot be forged by ordinary callers. -/
namespace Blinky.CMSISRTOS

public section

structure EventFlagsId where
  private mk ::
  private raw : UInt32

def EventFlagsId.toUInt32 (id : EventFlagsId) : UInt32 := id.raw

structure Flags where
  private mk ::
  private raw : UInt32

def Flags.ofUInt32? (value : UInt32) : Option Flags :=
  if value == 0 || value >= 0x80000000 then none else some ⟨value⟩

def Flags.toUInt32 (flags : Flags) : UInt32 := flags.raw

def Flags.buttonPress : Flags := ⟨1⟩

@[extern "lean_hal_rtos_event_flags_new"]
private opaque newRaw : IO UInt32
@[extern "lean_hal_rtos_event_flags_set"]
private opaque setRaw (id flags : UInt32) : IO UInt32
@[extern "lean_hal_rtos_event_flags_wait"]
private opaque waitRaw (id flags timeoutMs : UInt32) : IO UInt32
@[extern "lean_hal_rtos_event_flags_delete"]
private opaque deleteRaw (id : UInt32) : IO UInt32
@[extern "lean_hal_rtos_button_event_sink_get"]
private opaque buttonSinkGetRaw : IO UInt32
@[extern "lean_hal_rtos_button_event_sink_set"]
private opaque buttonSinkSetRaw (id : UInt32) : IO UInt32

namespace EventFlags

def new : HalM EventFlagsId := do
  let raw ← fromIO newRaw
  if raw == 0 then throw (.resourceUnavailable "osEventFlagsNew")
  return ⟨raw⟩

def set (id : EventFlagsId) (flags : Flags) : HalM Unit := do
  let result ← fromIO (setRaw id.raw flags.raw)
  if result >= 0x80000000 then
    throw (.rtos "osEventFlagsSet" result)

/-- `true` means that the requested flag was received; `false` is a timeout. -/
def wait (id : EventFlagsId) (flags : Flags) (timeoutMs : UInt32) : HalM Bool := do
  let result ← fromIO (waitRaw id.raw flags.raw timeoutMs)
  if result == 0xFFFFFFFE then return false
  if result >= 0x80000000 then
    throw (.rtos "osEventFlagsWait" result)
  return (result &&& flags.raw) != 0

/-- Delete an event object that is no longer the button ISR's destination. -/
def delete (id : EventFlagsId) : HalM Unit := do
  let status ← fromIO (deleteRaw id.raw)
  if status != 0 then throw (.rtos "osEventFlagsDelete" status)

end EventFlags

namespace ButtonEventSink

/-- Read the same current event ID that the C ISR uses. -/
def current : HalM EventFlagsId := do
  let raw ← fromIO buttonSinkGetRaw
  if raw == 0 then throw .eventSinkUnbound
  return ⟨raw⟩

/-- This action can run only under a CPU mask with the NVIC line disabled. -/
def bind (id : EventFlagsId) : NVIC.GateM .blocked .disabled Unit :=
  NVIC.GateM.fromHal do
    let status ← fromIO (buttonSinkSetRaw id.raw)
    if status != 0 then throw (.rtos "button event sink rebinding" status)

end ButtonEventSink
end
end Blinky.CMSISRTOS
