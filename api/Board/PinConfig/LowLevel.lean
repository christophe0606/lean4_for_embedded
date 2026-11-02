module
prelude
public import Board.Error
import Board.Internal.Raw.PinConfig
import Board.Internal.Resource

namespace Board.PinConfig.LowLevel
public section

/-- Trusted Alif mapping to the same resource identity used by CMSIS GPIO.
The adapter supplies the device/package's allowed alternate functions. -/
structure Pad where
  private mk ::
  private driver : USize
  private number : UInt32
  private port : UInt8
  private pin : UInt8
  private validFunction : UInt8 → Bool
  private lease : Internal.Resource.Lease

structure OwnedPad where
  private mk ::
  private pad : Pad
  private lease : Internal.Resource.Lease

/-- Only an unowned pad can be changed. A live GPIO owner prevents remuxing. -/
def claim (pad : Pad) : HalM OwnedPad := do
  let (lease, _) ← Internal.Resource.transition pad.lease (pure ())
  return OwnedPad.mk pad lease

/-- One elementary native operation; retire the preparation handle on success.
Function width follows pinconf.c's 3-bit field; legality comes from the package
mapping. Native firmware must honor the same exclusive ownership boundary. -/
def set (owned : OwnedPad) (function : Fin 8) (control : UInt8) : HalM Unit := do
  if owned.pad.port == 15 && function.val != 0 then
    throw (.invalidState "LPGPIO has no alternate function")
  if !owned.pad.validFunction function.val.toUInt8 then
    throw (.invalidState "alternate function unavailable on this pad")
  Internal.Resource.close owned.lease do
    let status ← fromIO (Internal.Raw.PinConfig.set owned.pad.port owned.pad.pin function.val.toUInt8 control)
    if status != 0 then throw (.pinConfig status.toUInt32)

end
end Board.PinConfig.LowLevel
