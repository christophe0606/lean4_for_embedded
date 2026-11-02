module
prelude
import all Board.GPIO.LowLevel
public import Board.GPIO.LowLevel
public import Board.Internal.Resource

namespace Board.Internal.GPIO
public section
/-- Trusted mapping: native pointer remains valid; predicate describes valid
pins yielded exclusively to this API. Exclude native/other-peripheral owners. -/
def makeDriver (raw : USize) (validPin : UInt32 → Bool) : Board.GPIO.LowLevel.Driver :=
  Board.GPIO.LowLevel.Driver.mk raw validPin

/-- Trusted callback is native-only. mute must disable this exact source.
beforeSetup preserves both closed gates and retains every ISR-owned object. -/
def source (device : Board.GPIO.LowLevel.Driver) (callback : USize)
    (beforeSetup : HalM Unit) (mute : IO Unit) :
    Board.GPIO.LowLevel.InterruptSource device.address number irq :=
  Board.GPIO.LowLevel.InterruptSource.mk device callback beforeSetup mute

def lease (pin : Board.GPIO.LowLevel.InterruptPin driver number irq state triggered) : Resource.Lease :=
  pin.lease

def reindex (lease : Resource.Lease) :
    Board.GPIO.LowLevel.InterruptPin driver number irq state triggered :=
  Board.GPIO.LowLevel.InterruptPin.mk lease
end
end Board.Internal.GPIO
