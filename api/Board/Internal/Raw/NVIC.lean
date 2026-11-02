module
prelude
public import Init.System.IO
public import Init.Data.SInt.Basic

namespace Board.Internal.Raw.NVIC

public section

@[extern "lean_board_nvic_enableIRQ"]
opaque enableIRQ (irq : Int32) : IO Unit

@[extern "lean_board_nvic_disableIRQ"]
opaque disableIRQ (irq : Int32) : IO Unit

@[extern "lean_board_nvic_setPendingIRQ"]
opaque setPendingIRQ (irq : Int32) : IO Unit

@[extern "lean_board_nvic_clearPendingIRQ"]
opaque clearPendingIRQ (irq : Int32) : IO Unit

@[extern "lean_board_nvic_getEnableIRQ"]
opaque getEnableIRQ (irq : Int32) : IO UInt32

@[extern "lean_board_nvic_getPendingIRQ"]
opaque getPendingIRQ (irq : Int32) : IO UInt32

@[extern "lean_board_nvic_getActive"]
opaque getActive (irq : Int32) : IO UInt32

@[extern "lean_board_nvic_getPriority"]
opaque getPriority (irq : Int32) : IO UInt32

@[extern "lean_board_nvic_setPriority"]
opaque setPriority (irq : Int32) (priority : UInt32) : IO Unit

end
end Board.Internal.Raw.NVIC
