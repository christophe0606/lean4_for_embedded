module
prelude
public import Blinky.CMSISRTOS
public import Board.GPIO
public import Board.AlifGPIO.LowLevel
import Board.Internal.GPIO
import Board.Internal.AlifGPIO
import Board.Internal.NVIC
import Board.Internal.Raw.AlifGPIO
import Blinky.Internal.Platform

namespace Blinky.GPIO
public section

inductive Role where | led | button
inductive Pin : Role → Type where
  | red0 : Pin .led | green0 : Pin .led | blue0 : Pin .led
  | red1 : Pin .led | green1 : Pin .led | blue1 : Pin .led
  | center : Pin .button

def Pin.selector : Pin role → UInt32
  | .red0 => 0 | .green0 => 1 | .blue0 => 2
  | .red1 => 3 | .green1 => 4 | .blue1 => 5 | .center => 6

def driver : Board.GPIO.LowLevel.Driver :=
  Board.Internal.GPIO.makeDriver Platform.gpioDriver (fun pin =>
    pin == Platform.pin 0 || pin == Platform.pin 1 || pin == Platform.pin 2 ||
    pin == Platform.pin 3 || pin == Platform.pin 4 || pin == Platform.pin 5 ||
    pin == Platform.pin 6)

structure Output (pin : Pin .led) where
  private mk ::
  private output : Board.GPIO.Output driver.address (Platform.pin pin.selector)

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

private def setupOutput (pin : Pin .led) : HalM (Output pin) := do
  return Output.mk (← Board.GPIO.setupOutput driver (Platform.pin pin.selector))

def setupLeds : HalM Leds := do
  let red0 ← setupOutput .red0
  let green0 ← setupOutput .green0
  let blue0 ← setupOutput .blue0
  let red1 ← setupOutput .red1
  let green1 ← setupOutput .green1
  let blue1 ← setupOutput .blue1
  return Leds.mk red0 green0 blue0 red1 green1 blue1

def setOutput (output : Output pin) (on : Bool) : HalM Unit := output.output.set on

abbrev Button := Board.AlifGPIO.LowLevel.Interrupt driver.address
  (Platform.pin 6) Platform.buttonIRQ

/-- Board identities and native callback lifetime are the trusted boundary.
The shared low-level APIs enforce every subsequent operation and transition. -/
private def callbackSource (events : CMSISRTOS.EventFlagsId) :
    Board.GPIO.LowLevel.InterruptSource driver.address (Platform.pin 6) Platform.buttonIRQ :=
  Board.Internal.GPIO.source driver Platform.callback (do
    let status ← fromIO (Internal.Platform.claimSetup 6)
    if status != 0 then throw (.gpio "button setup claim" status)
    Internal.Platform.bindEvents events)
    (Board.Internal.Raw.AlifGPIO.disableInterrupt Platform.buttonPort Platform.buttonPin.toUInt8)

private def nativeSource : HalM (Board.AlifGPIO.LowLevel.Source driver.address (Platform.pin 6) Platform.buttonIRQ) :=
  Board.Internal.AlifGPIO.source Platform.buttonPort ⟨4, by decide⟩

/-- Board policy composed from public, elementary checked primitives. -/
def prepareButton (events : CMSISRTOS.EventFlagsId) : HalM (Button .enabled) :=
  NVIC.runOpen <| NVIC.initializeLine <| NVIC.masked do
    let ready ← Board.GPIO.LowLevel.setupInterrupt (callbackSource events)
    Board.GPIO.LowLevel.setInterruptPull ready .up
    let input ← Board.GPIO.LowLevel.setInterruptDirection ready .input
    let falling ← Board.GPIO.LowLevel.setEventTrigger input .falling
    let source ← Board.Internal.NVIC.lift nativeSource
    let muted ← Board.AlifGPIO.LowLevel.attach source falling
    let cleared ← Board.AlifGPIO.LowLevel.interruptEoi muted
    NVIC.clearPendingIRQ
    NVIC.setPriority 5
    let unmasked ← Board.AlifGPIO.LowLevel.unmaskInterrupt cleared
    Board.AlifGPIO.LowLevel.enableInterrupt unmasked

def clearPending (button : Button .enabled) : NVIC.GateM .blocked .disabled Unit :=
  Board.AlifGPIO.LowLevel.clearPending button

end
end Blinky.GPIO
