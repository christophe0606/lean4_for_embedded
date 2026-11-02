module
prelude
public import Init.System.IO

namespace Board.Internal.Raw.SysTick

public section

@[extern "lean_board_systick_config"]
opaque config (ticks : UInt32) : IO UInt32

@[extern "lean_board_systick_getCTRL"]
opaque getCTRL : IO UInt32

@[extern "lean_board_systick_getLOAD"]
opaque getLOAD : IO UInt32

@[extern "lean_board_systick_getVAL"]
opaque getVAL : IO UInt32

@[extern "lean_board_systick_getCALIB"]
opaque getCALIB : IO UInt32

@[extern "lean_board_systick_setCTRL"]
opaque setCTRL (value : UInt32) : IO Unit

@[extern "lean_board_systick_setLOAD"]
opaque setLOAD (value : UInt32) : IO Unit

@[extern "lean_board_systick_setVAL"]
opaque setVAL (value : UInt32) : IO Unit

end
end Board.Internal.Raw.SysTick
