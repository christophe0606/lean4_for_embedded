module
prelude
import all Board.AlifGPIO.LowLevel
public import Board.AlifGPIO.LowLevel

namespace Board.Internal.AlifGPIO
public section
/-- Trust boundary: port/bit must name this exact GPIO pin and IRQ, with native
Setup's mute operation closing the same source. Never forge arbitrary addresses. -/
def source (port : USize) (bit : Fin 8) : HalM (Board.AlifGPIO.LowLevel.Source driver number irq) := do
  if driver == 0 || port == 0 || number >= 128 || number % 8 != bit.val.toUInt32 || irq >= 240 then
    throw (.invalidState "invalid Alif GPIO source identity mapping")
  return Board.AlifGPIO.LowLevel.Source.mk port bit
end
end Board.Internal.AlifGPIO
