module
prelude
public import Init.System.IO

/-!
The pin numbers are `8 * GPIO port + pin`, as in the Ensemble pack's
CMSIS GPIO driver. The two RGB LEDs and joystick center come from
Boards/DevKit-e8/board_defs.h in Ensemble@2.2.1.
-/

namespace Blinky

private def red0 : UInt32 := 99    -- GPIO12_3
private def green0 : UInt32 := 60  -- GPIO7_4
private def blue0 : UInt32 := 96   -- GPIO12_0
private def red1 : UInt32 := 50    -- GPIO6_2
private def green1 : UInt32 := 52  -- GPIO6_4
private def blue1 : UInt32 := 54   -- GPIO6_6
private def button : UInt32 := 124 -- LPGPIO15_4, joystick center, active low

-- These externs are thin CMSIS GPIO/RTX ABI calls. Pin selection, LED GPIO
-- initialization, sequencing, timing, debounce, and pattern state live in Lean.
@[extern "lean_blinky_gpio_setup"] opaque gpioSetup (pin : UInt32) : IO UInt32
@[extern "lean_blinky_gpio_direction"] opaque gpioDirection (pin : UInt32) (output : Bool) : IO UInt32
@[extern "lean_blinky_button_setup"] opaque buttonSetup (pin : UInt32) : IO UInt32
@[extern "lean_blinky_gpio_write"] opaque gpioWrite (pin : UInt32) (level : UInt32) : IO Unit
@[extern "lean_blinky_gpio_read"] opaque gpioRead (pin : UInt32) : IO UInt32
@[extern "lean_blinky_button_event"] opaque buttonEvent (timeoutMs : UInt32) : IO UInt32

private def requireOk (operation : String) (status : UInt32) : IO Unit := do
  if status != 0 then
    throw (IO.userError (operation ++ " failed"))

private def initLed (pin : UInt32) : IO Unit := do
  requireOk "GPIO setup" (← gpioSetup pin)
  requireOk "GPIO output direction" (← gpioDirection pin true)
  gpioWrite pin 0

private def initButton : IO Unit := do
  requireOk "button IRQ setup" (← buttonSetup button)

private def initGpio : IO Unit := do
  initLed red0
  initLed green0
  initLed blue0
  initLed red1
  initLed green1
  initLed blue1
  initButton

private def setPair (first second : UInt32) (on : Bool) : IO Unit := do
  let level : UInt32 := if on then 1 else 0
  gpioWrite first level
  gpioWrite second level

/- `buttonEvent` waits on an RTX event flag signalled by the GPIO interrupt.
   A press is checked after 30 ms and changes the mode at most once per 200 ms. -/
private def waitPhase (fast : Bool) (lastPress : Option Nat) : IO (Bool × Option Nat) := do
  let interval : UInt32 := if fast then 100 else 1000
  let event ← buttonEvent interval
  if event == 0 then
    return (fast, lastPress)
  if event != 1 then
    throw (IO.userError "button event wait failed")
  IO.sleep 30
  if (← gpioRead button) != 0 then
    return (fast, lastPress)
  let now ← IO.monoMsNow
  let oldEnough := match lastPress with
    | none => true
    | some previous => now >= previous + 200
  if !oldEnough then
    return (fast, lastPress)
  let next := !fast
  IO.println (if next then "Blinky: fast pattern (100 ms)" else "Blinky: slow pattern (1000 ms)")
  return (next, some now)

private def pulse (first second : UInt32) (fast : Bool) (lastPress : Option Nat) : IO (Bool × Option Nat) := do
  setPair first second true
  let (fast, lastPress) ← waitPhase fast lastPress
  setPair first second false
  waitPhase fast lastPress

private partial def blinkLoop (fast : Bool) (lastPress : Option Nat) : IO Unit := do
  let (fast, lastPress) ← pulse red0 red1 fast lastPress
  let (fast, lastPress) ← pulse green0 green1 fast lastPress
  let (fast, lastPress) ← pulse blue0 blue1 fast lastPress
  blinkLoop fast lastPress

private def application : IO Unit := do
  initGpio
  IO.println "Lean Blinky: RGB0 and RGB1, slow pattern (1000 ms)"
  IO.println "Press the joystick center to toggle the pattern."
  blinkLoop false none

-- The application runs as a Lean dedicated task backed by an RTX worker thread.
@[export lean_blinky_run]
def run : IO Unit := do
  let worker ← IO.asTask application Task.Priority.dedicated
  match worker.get with
  | .ok () => pure ()
  | .error err => throw err

end Blinky
