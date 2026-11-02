module
prelude
public import Init.System.IO
public import Init.Data.SInt.Basic

namespace Board.Internal.Raw.PinConfig

public section

@[extern "lean_board_pinconfig_set"]
opaque set (port : UInt8) (pin : UInt8) (function : UInt8) (control : UInt8) : IO Int32

end
end Board.Internal.Raw.PinConfig
