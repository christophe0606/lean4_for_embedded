module
prelude
public import Blinky.GPIO

/-! Board policy is implemented in Lean. The lower layers expose individual
CMSIS operations, while their capabilities and state types enforce the legal
hardware setup sequence. -/
namespace Blinky.Board

public section

inductive Color where
  | red | green | blue
  deriving Repr, DecidableEq

inductive Speed where
  | slow | fast
  deriving Repr, DecidableEq

def Speed.toggle : Speed → Speed
  | .slow => .fast
  | .fast => .slow

def Speed.period : Speed → UInt32
  | .slow => 1000
  | .fast => 100

theorem Speed.toggle_twice (speed : Speed) : speed.toggle.toggle = speed := by
  cases speed <;> rfl

structure Ready where
  private mk ::
  private leds : GPIO.Leds
  private button : GPIO.Button .enabled
  -- A software guard: rebinding the ISR's event object during a wait would
  -- leave that wait listening to the old object. It is cleared in `finally`.
  private waiting : IO.Ref Bool

def prepare : HalM Ready := do
  let leds ← GPIO.setupLeds

  -- The event object belongs to Lean. The C ISR only posts its button flag.
  let events ← CMSISRTOS.EventFlags.new

  -- The GPIO plan is indexed by the CPU/NVIC gate states and button phase.
  let button ← GPIO.prepareButton events

  let waiting ← fromIO (IO.mkRef false)
  return ⟨leds, button, waiting⟩

/-- Change the callback's RTOS event object from Lean. The previous ID is
returned to the caller; rebinding is for the owner task between waits. -/
def replaceEvents (ready : Ready) (newEvents : CMSISRTOS.EventFlagsId) :
    HalM CMSISRTOS.EventFlagsId := do
  NVIC.runOpen <| NVIC.masked <| NVIC.temporarilyDisabled do
    if ← NVIC.GateM.fromHal (fromIO ready.waiting.get) then
      NVIC.GateM.fromHal (throw (.invalidState "cannot replace button events during a wait"))
    let oldEvents ← NVIC.GateM.fromHal CMSISRTOS.ButtonEventSink.current
    if oldEvents.toUInt32 == newEvents.toUInt32 then
      NVIC.GateM.fromHal (throw (.invalidState "replacement event ID is already bound"))
    GPIO.clearPending ready.button
    NVIC.clearPendingIRQ
    CMSISRTOS.ButtonEventSink.bind newEvents
    return oldEvents

-- Both RGB LEDs always show the same member of the closed Color type.
def display (ready : Ready) (color : Option Color) : HalM Unit := do
  GPIO.setOutput ready.leds.red0 false
  GPIO.setOutput ready.leds.green0 false
  GPIO.setOutput ready.leds.blue0 false
  GPIO.setOutput ready.leds.red1 false
  GPIO.setOutput ready.leds.green1 false
  GPIO.setOutput ready.leds.blue1 false
  match color with
  | none => pure ()
  | some .red => do
      GPIO.setOutput ready.leds.red0 true
      GPIO.setOutput ready.leds.red1 true
  | some .green => do
      GPIO.setOutput ready.leds.green0 true
      GPIO.setOutput ready.leds.green1 true
  | some .blue => do
      GPIO.setOutput ready.leds.blue0 true
      GPIO.setOutput ready.leds.blue1 true

-- A falling-edge event is one press; the application suppresses repeats for 200 ms.
def waitCenterPress (ready : Ready) (speed : Speed) : HalM Bool := do
  let _ := ready.button
  let events ← NVIC.runOpen <| NVIC.masked do
    if ← NVIC.GateM.fromHal (fromIO ready.waiting.get) then
      NVIC.GateM.fromHal (throw (.invalidState "button event wait is already active"))
    let events ← NVIC.GateM.fromHal CMSISRTOS.ButtonEventSink.current
    NVIC.GateM.fromHal (fromIO (ready.waiting.set true))
    return events
  try
    CMSISRTOS.EventFlags.wait events CMSISRTOS.Flags.buttonPress speed.period
  finally
    fromIO (ready.waiting.set false)

end
end Blinky.Board
