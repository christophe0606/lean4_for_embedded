import Board
import Board.AlifGPIO.LowLevel
import Board.PinConfig.LowLevel
-- Only this native fixture imports trusted construction adapters.
import Board.Internal.GPIO
import Board.Internal.AlifGPIO
import Board.Internal.NVIC
import Board.Internal.USART
import Board.Internal.PinConfig
import Board.Internal.CMSISRTOS
import Board.Internal.Raw.AlifGPIO

open Board

@[extern "lean_board_test_set"] opaque setField (field value : UInt32) : IO Unit
@[extern "lean_board_test_get"] opaque getField (field : UInt32) : IO UInt32

def ensure (condition : Bool) (name : String) : HalM Unit :=
  unless condition do throw (.invalidState ("TEST FAILED: " ++ name))

def rejected (name : String) (action : HalM α) (reason : Option String := none) : HalM Unit := do
  let before ← fromIO (getField 5)
  match ← fromIO action.run with
  | .ok _ => throw (.invalidState ("TEST ACCEPTED: " ++ name))
  | .error error =>
    if let some expected := reason then ensure (error.describe == expected) (name ++ " rejected for wrong reason")
  ensure ((← fromIO (getField 5)) == before) (name ++ " touched hardware")

def passed (name : String) : HalM Unit := fromIO (IO.println ("PASS: " ++ name))

def driver : Board.GPIO.LowLevel.Driver := Board.Internal.GPIO.makeDriver 1 (fun n => n < 8)

def gpioTests : HalM Unit := do
  let ready ← Board.GPIO.LowLevel.setup driver 0
  let latched ← Board.GPIO.LowLevel.preloadOutput ready false
  rejected "preload invalidates old pin" (Board.GPIO.LowLevel.setDirection ready .input)
  let output ← Board.GPIO.LowLevel.setDirection latched .output
  rejected "repeated direction transition" (Board.GPIO.LowLevel.setDirection latched .output)
  Board.GPIO.LowLevel.setOutput output true
  let input ← Board.GPIO.LowLevel.setDirection output .input
  Board.GPIO.LowLevel.setPullResistor input .up
  let output ← Board.GPIO.LowLevel.setDirection input .output
  Board.GPIO.LowLevel.setOutput output false
  rejected "duplicate setup" (Board.GPIO.LowLevel.setup driver 0)
  rejected "invalid mapped pin" (Board.GPIO.LowLevel.setup driver 8)
  passed "GPIO preload evidence, stale copies, duplicate setup and mapped pins"

def gateTests : HalM Unit := do
  fromIO (setField 13 1)
  Board.NVIC.LowLevel.runOpen (irq := 7) <| Board.NVIC.LowLevel.masked <| Board.NVIC.LowLevel.disabled Board.NVIC.LowLevel.clearPendingIRQ
  ensure ((← fromIO (getField 1)) == 0 && (← fromIO (getField 13)) == 1) "gate restoration"
  rejected "priority range" <| Board.NVIC.LowLevel.runOpen (irq := 7) <| Board.NVIC.LowLevel.masked <| Board.NVIC.LowLevel.disabled (Board.NVIC.LowLevel.setPriority 16)
  rejected "unimplemented IRQ" <| Board.NVIC.LowLevel.runOpen (irq := 64) (pure ())
  rejected "kernel start from running" Board.CMSISRTOS.LowLevel.kernelStart
  let failed : HalM Unit := throw (.invalidState "injected")
  let _ ← fromIO (CPU.LowLevel.withInterruptsMasked failed).run
  ensure ((← fromIO (getField 1)) == 0) "HAL exception restored mask"
  let ioFailure : HalM Unit := fromIO (throw (IO.userError "injected"))
  let caught ← fromIO <| try
    let _ ← (CPU.LowLevel.withInterruptsMasked ioFailure).run
    pure false
  catch _ => pure true
  ensure (caught && (← fromIO (getField 1)) == 0) "IO exception restored mask"
  let changedGate : Board.NVIC.LowLevel.GateM 7 .blocked .disabled Unit :=
    Board.Internal.NVIC.lift (fromIO (setField 13 1))
  fromIO (setField 13 0)
  rejected "actual gate postcondition" <| Board.NVIC.LowLevel.runOpen <| Board.NVIC.LowLevel.masked <| Board.NVIC.LowLevel.disabled changedGate
  ensure ((← fromIO (getField 13)) == 0) "disabled line restored after rejected lift"
  let changedLine : Board.NVIC.LowLevel.GateM 7 .open .disabled Unit :=
    Board.Internal.NVIC.lift (fromIO (setField 13 1))
  rejected "initialization gate postcondition" <| Board.NVIC.LowLevel.runOpen <| Board.NVIC.LowLevel.initializeLine changedLine
  ensure ((← fromIO (getField 13)) == 0) "failed initialization left line disabled"
  passed "NVIC bounds, actual gates and CPU mask restoration on HAL/IO failure"

def rtosTests : HalM Unit := do
  for field in [0, 1, 2, 3] do
    fromIO (setField field 1)
    rejected "RTOS context" (Board.CMSISRTOS.LowLevel.delay 1)
    fromIO (setField field 0)
  rejected "zero delay" (Board.CMSISRTOS.LowLevel.delay 0)
  fromIO (setField 4 1)
  rejected "lock before scheduler start" (Board.CMSISRTOS.LowLevel.withKernelLocked (pure ()))
  fromIO (setField 4 2)
  Board.CMSISRTOS.LowLevel.withKernelLocked do rejected "blocking while locked" (Board.CMSISRTOS.LowLevel.delay 1)
  ensure ((← fromIO (getField 4)) == 2) "kernel lock restoration"
  ensure (Board.CMSISRTOS.LowLevel.Flags.ofUInt32? 0 |>.isNone) "zero flag mask"
  ensure (Board.CMSISRTOS.LowLevel.Flags.ofUInt32? 0x80000000 |>.isNone) "reserved flag bit"
  let event ← Board.CMSISRTOS.LowLevel.eventFlagsNew
  let retained ← Board.Internal.CMSISRTOS.retain event
  rejected "delete retained event" (Board.CMSISRTOS.LowLevel.eventFlagsDelete event)
  Board.Internal.Resource.release retained
  Board.CMSISRTOS.LowLevel.eventFlagsDelete event
  rejected "stale event" (Board.CMSISRTOS.LowLevel.eventFlagsSet event (Board.CMSISRTOS.LowLevel.Flags.single ⟨0, by decide⟩))
  rejected "static attributes without lifetime evidence" (Board.Internal.CMSISRTOS.threadEntry 500 0 1)
  let entry ← Board.Internal.CMSISRTOS.threadEntry 500 0 0
  let _ ← Board.CMSISRTOS.LowLevel.threadNew entry
  rejected "copied thread entry" (Board.CMSISRTOS.LowLevel.threadNew entry)
  passed "RTOS contexts, locks, masks, retained event lifetime and single-use thread entry"

def interruptTests : HalM Unit := do
  let native ← Board.Internal.AlifGPIO.source (driver := (1 : USize)) (number := 6) (irq := 7) 4096 ⟨6, by decide⟩
  let source : Board.GPIO.LowLevel.InterruptSource driver.address 6 7 :=
    Board.Internal.GPIO.source driver 123 (pure ()) (Board.Internal.Raw.AlifGPIO.disableInterrupt 4096 6)
  Board.NVIC.LowLevel.runOpen (irq := 7) <| Board.NVIC.LowLevel.masked <| Board.NVIC.LowLevel.disabled do
    let ready ← Board.GPIO.LowLevel.setupInterrupt source
    let input ← Board.GPIO.LowLevel.setInterruptDirection ready .input
    let triggered ← Board.GPIO.LowLevel.setEventTrigger input .falling
    let muted ← Board.AlifGPIO.LowLevel.attach native triggered
    let cleared ← Board.AlifGPIO.LowLevel.interruptEoi muted
    let unmasked ← Board.AlifGPIO.LowLevel.unmaskInterrupt cleared
    let enabled ← Board.AlifGPIO.LowLevel.enableInterrupt unmasked
    let _ ← Board.AlifGPIO.LowLevel.disableInterrupt enabled
    pure ()
  let native ← Board.Internal.AlifGPIO.source (driver := (1 : USize)) (number := 7) (irq := 7) 4096 ⟨7, by decide⟩
  let source : Board.GPIO.LowLevel.InterruptSource driver.address 7 7 :=
    Board.Internal.GPIO.source driver 123 (pure ()) (Board.Internal.Raw.AlifGPIO.disableInterrupt 4096 7)
  let triggered ← Board.NVIC.LowLevel.runOpen (irq := 7) <| Board.NVIC.LowLevel.masked <| Board.NVIC.LowLevel.disabled do
    let ready ← Board.GPIO.LowLevel.setupInterrupt source
    let input ← Board.GPIO.LowLevel.setInterruptDirection ready .input
    Board.GPIO.LowLevel.setEventTrigger input .falling
  fromIO (setField 6 128)
  rejected "attach actually enabled source" (Board.NVIC.LowLevel.runOpen <| Board.NVIC.LowLevel.masked <| Board.NVIC.LowLevel.disabled (Board.AlifGPIO.LowLevel.attach native triggered))
    (some "GPIO interrupt source is still enabled")
  passed "GPIO callback setup cleanup, Alif arming and enabled-source rejection"

def usartTests : HalM Unit := do
  let instance_ := Board.Internal.USART.instance_ 2
  let initial ← Board.USART.LowLevel.initialize instance_
  let powered ← Board.USART.LowLevel.powerOn initial
  rejected "zero baud" (Board.USART.LowLevel.configure powered 0)
  let configured ← Board.USART.LowLevel.configure powered 115200
  let enabled ← Board.USART.LowLevel.setTransmitter configured true
  let buffer ← Board.Internal.USART.buffer 8192 16
  rejected "overlapping storage" (Board.Internal.USART.buffer 8200 16)
  let _ ← Board.Internal.USART.buffer 8208 16
  rejected "count beyond storage" (Board.USART.LowLevel.send enabled buffer 17)
  let transfer ← Board.USART.LowLevel.send enabled buffer 16
  rejected "active driver copy" (Board.USART.LowLevel.setReceiver enabled true)
  fromIO (setField 10 16)
  ensure ((← Board.USART.LowLevel.poll transfer).isNone) "busy completion did not release storage"
  fromIO (setField 8 0)
  let some configured ← Board.USART.LowLevel.poll transfer | throw (.invalidState "idle completion absent")
  rejected "replayed completion" (Board.USART.LowLevel.poll transfer)
  let transfer ← Board.USART.LowLevel.send configured buffer 16
  let configured ← Board.USART.LowLevel.abort transfer
  let transfer ← Board.USART.LowLevel.send configured buffer 16
  fromIO (setField 12 1)
  let result ← fromIO (Board.USART.LowLevel.abort transfer).run
  ensure (!result.isOk) "busy abort accepted"
  rejected "failed abort poisoned owner" (Board.USART.LowLevel.poll transfer)
  fromIO (setField 8 0)
  let initial ← Board.USART.LowLevel.initialize (Board.Internal.USART.instance_ 3)
  let powered ← Board.USART.LowLevel.powerOn initial
  let configured ← Board.USART.LowLevel.configure powered 9600
  let enabled ← Board.USART.LowLevel.setTransmitter configured true
  rejected "failed abort retained storage" (Board.USART.LowLevel.send enabled buffer 1)
  let disabled ← Board.USART.LowLevel.setTransmitter enabled false
  let disabled ← Board.USART.LowLevel.setReceiver disabled false
  let initial ← Board.USART.LowLevel.powerOff disabled
  Board.USART.LowLevel.uninitialize initial
  passed "USART range/count guards, idle completion, stale driver and failed-abort storage retention"

def padTests : HalM Unit := do
  rejected "invalid pad mapping" (Board.Internal.PinConfig.pad 1 3 0 4 (fun _ => true))
  let pad ← Board.Internal.PinConfig.pad 1 3 0 3 (fun f => f <= 1)
  let owned ← Board.PinConfig.LowLevel.claim pad
  rejected "unavailable alternate function" (Board.PinConfig.LowLevel.set owned ⟨2, by decide⟩ 0)
  Board.PinConfig.LowLevel.set owned ⟨1, by decide⟩ 0
  rejected "reused preparation descriptor" (Board.PinConfig.LowLevel.claim pad)
  let _ ← Board.GPIO.LowLevel.setup driver 3
  rejected "remux GPIO-owned pad" (Board.Internal.PinConfig.pad 1 3 0 3 (fun _ => true))
  let pad ← Board.Internal.PinConfig.pad 1 124 15 4 (fun _ => true)
  let owned ← Board.PinConfig.LowLevel.claim pad
  rejected "LPGPIO alternate function" (Board.PinConfig.LowLevel.set owned ⟨1, by decide⟩ 0)
  Board.PinConfig.LowLevel.set owned ⟨0, by decide⟩ 0
  passed "PinConfig identity, function limits, exclusive ownership and descriptor replay"

def timerTests : HalM Unit := do
  rejected "RTOS owns SysTick" Board.SysTick.LowLevel.acquire
  fromIO (setField 4 0)
  fromIO (setField 7 1)
  rejected "native timer already active" Board.SysTick.LowLevel.acquire
  fromIO (setField 7 0)
  let timer ← Board.SysTick.LowLevel.acquire
  let stopped ← Board.SysTick.LowLevel.stop timer
  let config : Board.SysTick.Config 16 := { reload := ⟨15, by decide⟩, positive := by decide, exactPeriod := rfl }
  let loaded ← Board.SysTick.LowLevel.load stopped config
  rejected "reused stopped timer" (Board.SysTick.LowLevel.load stopped config)
  let cleared ← Board.SysTick.LowLevel.clear loaded
  let running ← Board.SysTick.LowLevel.start cleared
  rejected "replayed timer start" (Board.SysTick.LowLevel.start cleared)
  let stopped ← Board.SysTick.LowLevel.stop running
  Board.SysTick.LowLevel.release stopped
  rejected "closed timer" (Board.SysTick.LowLevel.stop stopped)
  passed "SysTick actual ownership, phase transitions, stale handles and release"

def cleanupTests : HalM Unit := do
  let lease ← Board.Internal.Resource.claim 99 10000
  let ioFailure : HalM Unit := fromIO (throw (IO.userError "injected"))
  let caught ← fromIO <| try
    let _ ← (Board.Internal.Resource.use lease ioFailure).run
    pure false
  catch _ => pure true
  ensure caught "injected IO error"
  Board.Internal.Resource.close lease (pure ())
  let lease ← Board.Internal.Resource.claim 99 10001
  let _ ← fromIO <| try
    let _ ← (Board.Internal.Resource.transition lease ioFailure).run
    pure ()
  catch _ => pure ()
  rejected "IO failure poisoned transition" (Board.Internal.Resource.find 99 10001)
  passed "real Lean resource cleanup on IO exceptions"

def main : IO Unit := do
  let result ← (do
    gpioTests
    gateTests
    rtosTests
    interruptTests
    usartTests
    padTests
    timerTests
    cleanupTests).run
  match result with
  | .ok _ => pure ()
  | .error error => throw (IO.userError error.describe)
