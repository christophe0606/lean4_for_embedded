module
prelude
public import Init.System.IO
public import Init.Data.SInt.Basic

namespace Board.Internal.Raw.GPIO

public section

def input : UInt32 := 0
def output : UInt32 := 1
def pushPull : UInt32 := 0
def openDrain : UInt32 := 1
def pullNone : UInt32 := 0
def pullUp : UInt32 := 1
def pullDown : UInt32 := 2
def triggerNone : UInt32 := 0
def triggerRisingEdge : UInt32 := 1
def triggerFallingEdge : UInt32 := 2
def triggerEitherEdge : UInt32 := 3
def eventRisingEdge : UInt32 := 1
def eventFallingEdge : UInt32 := 2
def eventEitherEdge : UInt32 := 4

@[extern "lean_board_gpio_setup"]
opaque setup (driver : USize) (pin : UInt32) (callback : USize) : IO Int32

@[extern "lean_board_gpio_setDirection"]
opaque setDirection (driver : USize) (pin : UInt32) (direction : UInt32) : IO Int32

@[extern "lean_board_gpio_setOutputMode"]
opaque setOutputMode (driver : USize) (pin : UInt32) (mode : UInt32) : IO Int32

@[extern "lean_board_gpio_setPullResistor"]
opaque setPullResistor (driver : USize) (pin : UInt32) (resistor : UInt32) : IO Int32

@[extern "lean_board_gpio_setEventTrigger"]
opaque setEventTrigger (driver : USize) (pin : UInt32) (trigger : UInt32) : IO Int32

@[extern "lean_board_gpio_setOutput"]
opaque setOutput (driver : USize) (pin : UInt32) (value : UInt32) : IO Unit

@[extern "lean_board_gpio_getInput"]
opaque getInput (driver : USize) (pin : UInt32) : IO UInt32

end
end Board.Internal.Raw.GPIO
