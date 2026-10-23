module
prelude
public import Blinky.CMSISRTOS
public import Blinky.NVIC

/-! Pin roles and button phases rule out wrong pins and out-of-order setup.
Only the complete button initializer is public: callers cannot retain and
reuse an intermediate phase. Raw GPIO status codes remain runtime errors. -/
namespace Blinky.GPIO

public section

inductive Role where
  | led | button

inductive Pin : Role → Type where
  | red0 : Pin .led
  | green0 : Pin .led
  | blue0 : Pin .led
  | red1 : Pin .led
  | green1 : Pin .led
  | blue1 : Pin .led
  | center : Pin .button

def Pin.selector : Pin role → UInt32
  | .red0 => 0
  | .green0 => 1
  | .blue0 => 2
  | .red1 => 3
  | .green1 => 4
  | .blue1 => 5
  | .center => 6

private def requireOk (operation : String) (status : UInt32) : HalM Unit := do
  if status != 0 then throw (.gpio operation status)

@[extern "lean_hal_gpio_driver_setup"]
private opaque setupRaw (selector eventId : UInt32) : IO UInt32
@[extern "lean_hal_gpio_set_direction"]
private opaque setDirectionRaw (selector output : UInt32) : IO UInt32
@[extern "lean_hal_gpio_set_pull_up"]
private opaque setPullUpRaw (selector : UInt32) : IO UInt32
@[extern "lean_hal_gpio_set_falling"]
private opaque setFallingRaw (selector : UInt32) : IO UInt32
@[extern "lean_hal_gpio_set_output"]
private opaque setOutputRaw (selector : UInt32) (on : Bool) : IO UInt32
@[extern "lean_hal_gpio_disable_interrupt"]
private opaque disableInterruptRaw (selector : UInt32) : IO UInt32
@[extern "lean_hal_gpio_interrupt_eoi"]
private opaque interruptEoiRaw (selector : UInt32) : IO UInt32
@[extern "lean_hal_gpio_unmask_interrupt"]
private opaque unmaskInterruptRaw (selector : UInt32) : IO UInt32
@[extern "lean_hal_gpio_enable_interrupt"]
private opaque enableInterruptRaw (selector : UInt32) : IO UInt32

structure Output (_pin : Pin .led) where
  private mk ::
  private witness : Unit

structure Leds where
  private mk ::
  private red0Output : Output .red0
  private green0Output : Output .green0
  private blue0Output : Output .blue0
  private red1Output : Output .red1
  private green1Output : Output .green1
  private blue1Output : Output .blue1

def Leds.red0 (leds : Leds) : Output .red0 := leds.red0Output
def Leds.green0 (leds : Leds) : Output .green0 := leds.green0Output
def Leds.blue0 (leds : Leds) : Output .blue0 := leds.blue0Output
def Leds.red1 (leds : Leds) : Output .red1 := leds.red1Output
def Leds.green1 (leds : Leds) : Output .green1 := leds.green1Output
def Leds.blue1 (leds : Leds) : Output .blue1 := leds.blue1Output

inductive ButtonState where
  | muted | pulledUp | input | falling | cleared | unmasked | enabled
  deriving BEq, Repr

structure Button (_state : ButtonState) where
  private mk ::
  private pin : Pin .button

private def checked (operation : String) (raw : IO UInt32) :
    NVIC.GateM cpu line Unit :=
  NVIC.GateM.fromHal do
    requireOk operation (← fromIO raw)

/-- Setup, configure and turn off an LED. No partially configured LED token
escapes, so SetOutput needs no runtime "configured" flag. -/
private def setupOutput (pin : Pin .led) : HalM (Output pin) := do
  requireOk "Driver_GPIO.Setup" (← fromIO (setupRaw pin.selector 0))
  requireOk "Driver_GPIO.SetDirection(output)"
    (← fromIO (setDirectionRaw pin.selector 1))
  requireOk "Driver_GPIO.SetOutput" (← fromIO (setOutputRaw pin.selector false))
  return ⟨()⟩

/-- The only public LED initializer. Each of the six closed pin choices is
configured once in this plan; no caller receives a partly configured LED. -/
def setupLeds : HalM Leds := do
  let red0 ← setupOutput .red0
  let green0 ← setupOutput .green0
  let blue0 ← setupOutput .blue0
  let red1 ← setupOutput .red1
  let green1 ← setupOutput .green1
  let blue1 ← setupOutput .blue1
  return ⟨red0, green0, blue0, red1, green1, blue1⟩

def setOutput {pin : Pin .led} (_output : Output pin) (on : Bool) : HalM Unit := do
  requireOk "Driver_GPIO.SetOutput"
    (← fromIO (setOutputRaw pin.selector on))

/-- The pack briefly enables both gates inside Setup. PRIMASK stays set until
Lean has closed the GPIO source and NVIC line again, even on a driver error. -/
private def setupInterrupt (pin : Pin .button) (events : CMSISRTOS.EventFlagsId) :
    NVIC.GateM .open .disabled (Button .muted) :=
  NVIC.masked do
    let status ← NVIC.GateM.fromHal (fromIO (setupRaw pin.selector events.toUInt32))
    let gpioStatus ← NVIC.GateM.fromHal
      (fromIO (disableInterruptRaw pin.selector))
    NVIC.closeLineAfterSetup
    NVIC.clearPendingIRQ
    NVIC.GateM.fromHal (requireOk "gpio_disable_interrupt" gpioStatus)
    NVIC.GateM.fromHal (requireOk "Driver_GPIO.Setup" status)
    return ⟨pin⟩

private def setPullUp (button : Button .muted) :
    NVIC.GateM .open .disabled (Button .pulledUp) := do
  checked "Driver_GPIO.SetPullResistor" (setPullUpRaw button.pin.selector)
  return ⟨button.pin⟩

private def setInputDirection (button : Button .pulledUp) :
    NVIC.GateM .open .disabled (Button .input) := do
  checked "Driver_GPIO.SetDirection(input)"
    (setDirectionRaw button.pin.selector 0)
  return ⟨button.pin⟩

private def setFallingEdge (button : Button .input) :
    NVIC.GateM .open .disabled (Button .falling) := do
  checked "Driver_GPIO.SetEventTrigger(falling)"
    (setFallingRaw button.pin.selector)
  return ⟨button.pin⟩

private def interruptEoi (button : Button .falling) :
    NVIC.GateM .blocked .disabled (Button .cleared) := do
  checked "gpio_interrupt_eoi" (interruptEoiRaw button.pin.selector)
  return ⟨button.pin⟩

private def unmaskInterrupt (button : Button .cleared) :
    NVIC.GateM .blocked .disabled (Button .unmasked) := do
  checked "gpio_unmask_interrupt" (unmaskInterruptRaw button.pin.selector)
  return ⟨button.pin⟩

private def enableInterrupt (button : Button .unmasked) :
    NVIC.GateM .blocked .disabled (Button .enabled) := do
  checked "gpio_enable_interrupt" (enableInterruptRaw button.pin.selector)
  return ⟨button.pin⟩

/-- The only public button setup path. The phase types reject reordering and
the gate indices ensure each action runs under its required interrupt gates. -/
def prepareButton (events : CMSISRTOS.EventFlagsId) : HalM (Button .enabled) :=
  NVIC.runOpen <| NVIC.initializeLine do
    let muted ← setupInterrupt .center events
    let pulledUp ← setPullUp muted
    let input ← setInputDirection pulledUp
    let falling ← setFallingEdge input
    NVIC.masked do
      let cleared ← interruptEoi falling
      NVIC.clearPendingIRQ
      NVIC.setPriority 5
      let unmasked ← unmaskInterrupt cleared
      enableInterrupt unmasked

/-- Discard a pending button edge while the CPU and NVIC gates are closed. -/
def clearPending (button : Button .enabled) : NVIC.GateM .blocked .disabled Unit :=
  checked "gpio_interrupt_eoi" (interruptEoiRaw button.pin.selector)

end
end Blinky.GPIO
