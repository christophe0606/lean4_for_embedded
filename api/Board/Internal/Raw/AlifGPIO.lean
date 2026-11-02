module
prelude
public import Init.System.IO

namespace Board.Internal.Raw.AlifGPIO

public section

@[extern "lean_board_alifgpio_getEnabledInterrupts"]
opaque getEnabledInterrupts (port : USize) : IO UInt8

@[extern "lean_board_alifgpio_disableInterrupt"]
opaque disableInterrupt (port : USize) (pin : UInt8) : IO Unit

@[extern "lean_board_alifgpio_enableInterrupt"]
opaque enableInterrupt (port : USize) (pin : UInt8) : IO Unit

@[extern "lean_board_alifgpio_maskInterrupt"]
opaque maskInterrupt (port : USize) (pin : UInt8) : IO Unit

@[extern "lean_board_alifgpio_unmaskInterrupt"]
opaque unmaskInterrupt (port : USize) (pin : UInt8) : IO Unit

@[extern "lean_board_alifgpio_interruptEoi"]
opaque interruptEoi (port : USize) (pin : UInt8) : IO Unit

end
end Board.Internal.Raw.AlifGPIO
