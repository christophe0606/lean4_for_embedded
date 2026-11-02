module
prelude
public import Init.System.IO
public import Init.Data.SInt.Basic

namespace Board.Internal.Raw.CMSISRTOS

public section

def flagsWaitAny : UInt32 := 0
def flagsWaitAll : UInt32 := 1
def flagsNoClear : UInt32 := 2
def waitForever : UInt32 := 0xFFFFFFFF
def flagsError : UInt32 := 0x80000000
def flagsErrorTimeout : UInt32 := 0xFFFFFFFE
def flagsErrorResource : UInt32 := 0xFFFFFFFD

@[extern "lean_board_cmsisrtos_eventFlagsNew"]
opaque eventFlagsNew (attributes : USize) : IO USize

@[extern "lean_board_cmsisrtos_eventFlagsSet"]
opaque eventFlagsSet (id : USize) (flags : UInt32) : IO UInt32

@[extern "lean_board_cmsisrtos_eventFlagsClear"]
opaque eventFlagsClear (id : USize) (flags : UInt32) : IO UInt32

@[extern "lean_board_cmsisrtos_eventFlagsGet"]
opaque eventFlagsGet (id : USize) : IO UInt32

@[extern "lean_board_cmsisrtos_eventFlagsWait"]
opaque eventFlagsWait (id : USize) (flags : UInt32) (options : UInt32) (timeout : UInt32) : IO UInt32

@[extern "lean_board_cmsisrtos_eventFlagsDelete"]
opaque eventFlagsDelete (id : USize) : IO Int32

@[extern "lean_board_cmsisrtos_kernelGetState"]
opaque kernelGetState : IO Int32

@[extern "lean_board_cmsisrtos_kernelGetTickFreq"]
opaque kernelGetTickFreq : IO UInt32

@[extern "lean_board_cmsisrtos_kernelGetTickCount"]
opaque kernelGetTickCount : IO UInt32

@[extern "lean_board_cmsisrtos_kernelInitialize"]
opaque kernelInitialize : IO Int32

@[extern "lean_board_cmsisrtos_kernelStart"]
opaque kernelStart : IO Int32

@[extern "lean_board_cmsisrtos_kernelLock"]
opaque kernelLock : IO Int32

@[extern "lean_board_cmsisrtos_kernelUnlock"]
opaque kernelUnlock : IO Int32

@[extern "lean_board_cmsisrtos_kernelRestoreLock"]
opaque kernelRestoreLock (lock : Int32) : IO Int32

@[extern "lean_board_cmsisrtos_delay"]
opaque delay (ticks : UInt32) : IO Int32

@[extern "lean_board_cmsisrtos_threadNew"]
opaque threadNew (function : USize) (argument : USize) (attributes : USize) : IO USize

end
end Board.Internal.Raw.CMSISRTOS
