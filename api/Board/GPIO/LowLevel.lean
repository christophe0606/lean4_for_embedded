module
prelude
public import Board.Error
public import Board.NVIC.LowLevel
import Board.Internal.Raw.GPIO
import Board.Internal.Raw.NVIC
import Board.Internal.Resource
import Board.Internal.NVIC

namespace Board.GPIO.LowLevel
public section

inductive Direction where | input | output
  deriving DecidableEq
inductive Pull where | none | up | down
inductive OutputMode where | pushPull | openDrain
inductive Edge where | rising | falling | either
inductive State where | ready | input | output
  deriving DecidableEq

@[expose] def Direction.state : Direction → State | .input => .input | .output => .output
private def Direction.code : Direction → UInt32 | .input => 0 | .output => 1
private def Pull.code : Pull → UInt32 | .none => 0 | .up => 1 | .down => 2
private def OutputMode.code : OutputMode → UInt32 | .pushPull => 0 | .openDrain => 1
private def Edge.code : Edge → UInt32 | .rising => 1 | .falling => 2 | .either => 3

/-- A trusted board adapter yields these valid pins to this checked owner.
Its predicate must exclude pins owned by another peripheral or native firmware. -/
structure Driver where
  private mk ::
  private raw : USize
  private validPin : UInt32 → Bool

def Driver.address (driver : Driver) : USize := driver.raw

private def check (operation : String) (action : IO Int32) : HalM Unit := do
  let status ← fromIO action
  if status != 0 then throw (.gpio operation status.toUInt32)

structure Pin (driver : USize) (number : UInt32) (_state : State)
    (_preloaded : Bool := false) where
  private mk ::
  private lease : Internal.Resource.Lease

/-- CMSIS GPIO Setup precedes configuration. A pin has one checked owner.
External native firmware must not independently reconfigure that pin. -/
def setup (driver : Driver) (number : UInt32) : HalM (Pin driver.address number .ready) :=
  Internal.Resource.serialized 6 driver.raw do
    if driver.raw == 0 || !driver.validPin number then
      throw (.invalidState "invalid GPIO instance or pin")
    let lease ← Internal.Resource.claim 1 driver.raw number
    let (lease, _) ← Internal.Resource.transition lease <|
      check "GPIO.Setup" (Internal.Raw.GPIO.setup driver.raw number 0)
    return Pin.mk lease

def setDirection (pin : Pin driver number before preloaded) (direction : Direction)
    (_readyForOutput : direction = .output → preloaded = true := by decide) :
    HalM (Pin driver number direction.state preloaded) := Internal.Resource.serialized 6 driver do
  let (lease, _) ← Internal.Resource.transition pin.lease <|
    check "GPIO.SetDirection" (Internal.Raw.GPIO.setDirection driver number direction.code)
  return Pin.mk lease

/-- Pull and direction may be configured in either order after Setup.
CMSIS Driver_GPIO.h and Alif Driver_GPIO.c impose no ordering between them. -/
def setPullResistor (pin : Pin driver number state preloaded) (pull : Pull) : HalM Unit :=
  Internal.Resource.serialized 6 driver <| Internal.Resource.modify pin.lease <|
    check "GPIO.SetPullResistor" (Internal.Raw.GPIO.setPullResistor driver number pull.code)

def setOutputMode (pin : Pin driver number state preloaded) (mode : OutputMode) : HalM Unit :=
  Internal.Resource.serialized 6 driver <| Internal.Resource.modify pin.lease <|
    check "GPIO.SetOutputMode" (Internal.Raw.GPIO.setOutputMode driver number mode.code)

/-- Establish the latch value while the pin is not driving. The returned
capability is the evidence required by output direction. Old copies are stale. -/
def preloadOutput (pin : Pin driver number state preloaded) (value : Bool)
    (_notDriving : state ≠ .output := by decide) : HalM (Pin driver number state true) :=
  Internal.Resource.serialized 6 driver do
    let (lease, _) ← Internal.Resource.transition pin.lease <|
      fromIO (Internal.Raw.GPIO.setOutput driver number (if value then 1 else 0))
    return Pin.mk lease

def setOutput (pin : Pin driver number .output true) (value : Bool) : HalM Unit :=
  Internal.Resource.serialized 6 driver <| Internal.Resource.modify pin.lease <|
    fromIO (Internal.Raw.GPIO.setOutput driver number (if value then 1 else 0))

def getInput (pin : Pin driver number .input preloaded) : HalM Bool :=
  Internal.Resource.serialized 6 driver <| Internal.Resource.use pin.lease do
    return (← fromIO (Internal.Raw.GPIO.getInput driver number)) != 0

/-- Trusted native callback/source mapping. Setup may enable the source and
NVIC internally: mute must close the source before the CPU mask is restored. -/
structure InterruptSource (driver : USize) (number irq : UInt32) where
  private mk ::
  private device : Driver
  private callback : USize
  private beforeSetup : HalM Unit
  private mute : IO Unit

structure InterruptPin (driver : USize) (number irq : UInt32) (_state : State)
    (_triggered : Bool) where
  private mk ::
  private lease : Internal.Resource.Lease

def setupInterrupt (source : InterruptSource driver number irq) :
    NVIC.LowLevel.GateM irq .blocked .disabled (InterruptPin driver number irq .ready false) :=
  Internal.NVIC.lift <| Internal.Resource.serialized 6 driver do
    if source.device.raw != driver || !source.device.validPin number || source.callback == 0 then
      throw (.invalidState "invalid native GPIO interrupt source")
    let lease ← Internal.Resource.claim 1 driver number
    let (lease, _) ← Internal.Resource.transition lease do
      source.beforeSetup
      ExceptT.mk <| try
        (check "GPIO.Setup(callback)" (Internal.Raw.GPIO.setup driver number source.callback)).run
      finally
        source.mute
        Internal.Raw.NVIC.disableIRQ irq.toInt32
    return InterruptPin.mk lease

def setInterruptPull (pin : InterruptPin driver number irq state triggered) (pull : Pull) :
    NVIC.LowLevel.GateM irq .blocked .disabled Unit :=
  Internal.NVIC.lift <| Internal.Resource.serialized 6 driver <| Internal.Resource.modify pin.lease <|
    check "GPIO.SetPullResistor" (Internal.Raw.GPIO.setPullResistor driver number pull.code)

def setInterruptDirection (pin : InterruptPin driver number irq before false) (direction : Direction)
    (_inputOnly : direction = .input := by decide) :
    NVIC.LowLevel.GateM irq .blocked .disabled (InterruptPin driver number irq direction.state false) :=
  Internal.NVIC.lift <| Internal.Resource.serialized 6 driver do
    let (lease, _) ← Internal.Resource.transition pin.lease <|
      check "GPIO.SetDirection" (Internal.Raw.GPIO.setDirection driver number direction.code)
    return InterruptPin.mk lease

def setEventTrigger (pin : InterruptPin driver number irq .input false) (edge : Edge) :
    NVIC.LowLevel.GateM irq .blocked .disabled (InterruptPin driver number irq .input true) :=
  Internal.NVIC.lift <| Internal.Resource.serialized 6 driver do
    let (lease, _) ← Internal.Resource.transition pin.lease <|
      check "GPIO.SetEventTrigger" (Internal.Raw.GPIO.setEventTrigger driver number edge.code)
    return InterruptPin.mk lease

end
end Board.GPIO.LowLevel
