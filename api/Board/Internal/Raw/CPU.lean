module
prelude
public import Init.System.IO

namespace Board.Internal.Raw.CPU

public section

@[extern "lean_board_cpu_getIPSR"] opaque getIPSR : IO UInt32
@[extern "lean_board_cpu_getBASEPRI"] opaque getBASEPRI : IO UInt32
@[extern "lean_board_cpu_getFAULTMASK"] opaque getFAULTMASK : IO UInt32

@[extern "lean_board_cpu_getPRIMASK"]
opaque getPRIMASK : IO UInt32

@[extern "lean_board_cpu_setPRIMASK"]
opaque setPRIMASK (value : UInt32) : IO Unit

@[extern "lean_board_cpu_disableIRQ"]
opaque disableIRQ : IO Unit

@[extern "lean_board_cpu_enableIRQ"]
opaque enableIRQ : IO Unit

@[extern "lean_board_cpu_dsb"]
opaque dsb : IO Unit

@[extern "lean_board_cpu_isb"]
opaque isb : IO Unit

end
end Board.Internal.Raw.CPU
