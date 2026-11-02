module
prelude
public import Board.GPIO.LowLevel
import Board.Internal.GPIO
import Board.Internal.NVIC
import Board.Internal.Raw.AlifGPIO

namespace Board.AlifGPIO.LowLevel
public section

/-- Trusted mapping of a CMSIS GPIO pin to its Alif register port, bit, and IRQ. -/
structure Source (driver : USize) (number irq : UInt32) where
  private mk ::
  private port : USize
  private bit : Fin 8

inductive State where | muted | cleared | unmasked | enabled
structure Interrupt (driver : USize) (number irq : UInt32) (_state : State) where
  private mk ::
  private source : Source driver number irq
  private pin : GPIO.LowLevel.InterruptPin driver number irq .input true

/-- Transfer the configured callback pin only after checking the native source
is actually disabled; a phantom muted state is never assigned from a comment. -/
def attach (source : Source driver number irq)
    (pin : GPIO.LowLevel.InterruptPin driver number irq .input true) :
    NVIC.LowLevel.GateM irq .blocked .disabled (Interrupt driver number irq .muted) :=
  Internal.NVIC.lift do
    let (lease, _) ← Internal.Resource.transition (Internal.GPIO.lease pin) do
      let enabled ← fromIO (Internal.Raw.AlifGPIO.getEnabledInterrupts source.port)
      if enabled &&& ((1 : UInt8) <<< source.bit.val.toUInt8) != 0 then
        throw (.invalidState "GPIO interrupt source is still enabled")
    return Interrupt.mk source (Internal.GPIO.reindex lease)

private def step (interrupt : Interrupt driver number irq before) (action : IO Unit) :
    HalM (Interrupt driver number irq after) := do
  let (lease, _) ← Internal.Resource.transition (Internal.GPIO.lease interrupt.pin) (fromIO action)
  return Interrupt.mk interrupt.source (Internal.GPIO.reindex lease)

/-- Alif gpio.h: clear stale status before unmasking and enabling the source.
All mutations require CPU and NVIC gates closed. -/
def interruptEoi (interrupt : Interrupt driver number irq .muted) :
    NVIC.LowLevel.GateM irq .blocked .disabled (Interrupt driver number irq .cleared) :=
  Internal.NVIC.lift <| step interrupt <|
    Internal.Raw.AlifGPIO.interruptEoi interrupt.source.port interrupt.source.bit.val.toUInt8

def unmaskInterrupt (interrupt : Interrupt driver number irq .cleared) :
    NVIC.LowLevel.GateM irq .blocked .disabled (Interrupt driver number irq .unmasked) :=
  Internal.NVIC.lift <| step interrupt <|
    Internal.Raw.AlifGPIO.unmaskInterrupt interrupt.source.port interrupt.source.bit.val.toUInt8

def enableInterrupt (interrupt : Interrupt driver number irq .unmasked) :
    NVIC.LowLevel.GateM irq .blocked .disabled (Interrupt driver number irq .enabled) :=
  Internal.NVIC.lift <| step interrupt <|
    Internal.Raw.AlifGPIO.enableInterrupt interrupt.source.port interrupt.source.bit.val.toUInt8

def disableInterrupt (interrupt : Interrupt driver number irq .enabled) :
    NVIC.LowLevel.GateM irq .blocked .disabled (Interrupt driver number irq .muted) :=
  Internal.NVIC.lift <| step interrupt <|
    Internal.Raw.AlifGPIO.disableInterrupt interrupt.source.port interrupt.source.bit.val.toUInt8

def clearPending (interrupt : Interrupt driver number irq .enabled) :
    NVIC.LowLevel.GateM irq .blocked .disabled Unit :=
  Internal.NVIC.lift <| Internal.Resource.modify (Internal.GPIO.lease interrupt.pin) <|
    fromIO (Internal.Raw.AlifGPIO.interruptEoi interrupt.source.port interrupt.source.bit.val.toUInt8)

end
end Board.AlifGPIO.LowLevel
