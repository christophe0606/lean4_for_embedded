module
prelude
import all Board.PinConfig.LowLevel
public import Board.PinConfig.LowLevel
import Board.Internal.Resource

namespace Board.Internal.PinConfig
public section
/-- Trusted pack mapping: driver/number and port/pin name the same pad.
The validFunction predicate must describe the selected device and package. -/
def pad (driver : USize) (number : UInt32) (port pin : UInt8)
    (validFunction : UInt8 → Bool) : HalM Board.PinConfig.LowLevel.Pad := do
  if driver == 0 || port >= 16 || pin >= 8 || number != port.toUInt32 * 8 + pin.toUInt32 then
    throw (.invalidState "invalid Alif GPIO/pad identity mapping")
  let lease ← Board.Internal.Resource.claim 1 driver number
  return Board.PinConfig.LowLevel.Pad.mk driver number port pin validFunction lease
end
end Board.Internal.PinConfig
