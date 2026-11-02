module
prelude
public import Init.System.IO
public import Init.Data.SInt.Basic

namespace Board.Internal.Raw.USART

public section

@[extern "lean_board_usart_getTxBusy"] opaque getTxBusy (driver : USize) : IO UInt32
@[extern "lean_board_usart_getRxBusy"] opaque getRxBusy (driver : USize) : IO UInt32

@[extern "lean_board_usart_initialize"]
opaque «initialize» (driver : USize) (callback : USize) : IO Int32

@[extern "lean_board_usart_uninitialize"]
opaque uninitialize (driver : USize) : IO Int32

@[extern "lean_board_usart_powerControl"]
opaque powerControl (driver : USize) (state : UInt32) : IO Int32

@[extern "lean_board_usart_control"]
opaque control (driver : USize) (control : UInt32) (argument : UInt32) : IO Int32

@[extern "lean_board_usart_send"]
opaque send (driver : USize) (data : USize) (count : UInt32) : IO Int32

@[extern "lean_board_usart_receive"]
opaque receive (driver : USize) (data : USize) (count : UInt32) : IO Int32

@[extern "lean_board_usart_getTxCount"]
opaque getTxCount (driver : USize) : IO UInt32

@[extern "lean_board_usart_getRxCount"]
opaque getRxCount (driver : USize) : IO UInt32

end
end Board.Internal.Raw.USART
