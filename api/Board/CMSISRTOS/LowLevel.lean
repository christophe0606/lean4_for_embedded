module
prelude
public import Board.Error
public import Init.Data.SInt.Basic
import Board.Internal.Raw.CMSISRTOS
import Board.Internal.Raw.CPU
import Board.Internal.Resource
import Board.Internal.Context

namespace Board.CMSISRTOS.LowLevel
public section

def kernelGetState : IO Int32 := Internal.Raw.CMSISRTOS.kernelGetState
def kernelGetTickFreq : IO UInt32 := Internal.Raw.CMSISRTOS.kernelGetTickFreq
def kernelGetTickCount : IO UInt32 := Internal.Raw.CMSISRTOS.kernelGetTickCount
def waitForever : UInt32 := 0xFFFFFFFF

private def status (name : String) (action : IO Int32) : HalM Unit := do
  let value ← fromIO action
  if value != 0 then throw (.rtos name value.toUInt32)

private def requireKernel : HalM Unit := do
  Internal.Context.thread
  let state ← fromIO kernelGetState
  if state != 1 && state != 2 && state != 3 then
    throw (.invalidState "RTOS kernel is not initialized")

private def requireBlockingContext : HalM Unit := do
  Internal.Context.interruptsOpen
  if (← fromIO kernelGetState) != 2 then
    throw (.invalidState "blocking RTOS operation requires a running unlocked kernel and open CPU gate")

/-- Kernel initialization and direct SysTick use share one ownership key.
Native startup must also yield ownership; kernel queries reject preexisting RTX ownership. -/
def kernelInitialize : HalM Unit := do
  Internal.Context.interruptsOpen
  if (← fromIO kernelGetState) != 0 then throw (.invalidState "kernel already initialized")
  let lease ← Internal.Resource.claim 2 0
  let _ ← Internal.Resource.transition lease <|
    status "osKernelInitialize" Internal.Raw.CMSISRTOS.kernelInitialize

def kernelStart : HalM Unit := do
  Internal.Context.interruptsOpen
  if (← fromIO kernelGetState) != 1 then throw (.invalidState "kernel is not ready to start")
  status "osKernelStart" Internal.Raw.CMSISRTOS.kernelStart

def withKernelLocked (action : HalM α) : HalM α := do
  Internal.Context.interruptsOpen
  let state ← fromIO kernelGetState
  if state != 2 && state != 3 then throw (.invalidState "kernel lock requires a running scheduler")
  let previous ← fromIO Internal.Raw.CMSISRTOS.kernelLock
  if previous < 0 then throw (.rtos "osKernelLock" previous.toUInt32)
  ExceptT.mk <| try action.run finally do
    let restored ← Internal.Raw.CMSISRTOS.kernelRestoreLock previous
    if restored < 0 then throw (IO.userError "osKernelRestoreLock failed")

def delay (ticks : UInt32) : HalM Unit := do
  requireBlockingContext
  if ticks == 0 then throw (.invalidState "osDelay requires nonzero ticks")
  status "osDelay" (Internal.Raw.CMSISRTOS.delay ticks)

structure Flags where
  private mk ::
  private raw : UInt32

def Flags.ofUInt32? (value : UInt32) : Option Flags :=
  if value == 0 || value >= 0x80000000 then none else some ⟨value⟩
def Flags.toUInt32 (flags : Flags) : UInt32 := flags.raw
def Flags.single (bit : Fin 31) : Flags := ⟨(1 : UInt32) <<< bit.val.toUInt32⟩

structure EventFlagsId where
  private mk ::
  private raw : USize
  private lease : Internal.Resource.Lease

def EventFlagsId.toUSize (id : EventFlagsId) : USize := id.raw

inductive WaitMode where | any | all
structure WaitOptions where
  mode : WaitMode := .any
  clear : Bool := true

private def checkFlags (name : String) (action : IO UInt32) : HalM UInt32 := do
  let result ← fromIO action
  if result >= 0x80000000 then throw (.rtos name result)
  return result

def eventFlagsNew : HalM EventFlagsId := do
  Internal.Context.interruptsOpen
  requireKernel
  let raw ← fromIO (Internal.Raw.CMSISRTOS.eventFlagsNew 0)
  if raw == 0 then throw (.resourceUnavailable "osEventFlagsNew")
  let lease ← (Internal.Resource.claim 3 raw).run |> fromIO
  match lease with
  | .ok lease => return EventFlagsId.mk raw lease
  | .error error =>
    let _ ← fromIO (Internal.Raw.CMSISRTOS.eventFlagsDelete raw)
    throw error

def eventFlagsSet (id : EventFlagsId) (flags : Flags) : HalM Unit :=
  Internal.Resource.use id.lease do
    let _ ← checkFlags "osEventFlagsSet" (Internal.Raw.CMSISRTOS.eventFlagsSet id.raw flags.raw)

def eventFlagsClear (id : EventFlagsId) (flags : Flags) : HalM Unit :=
  Internal.Resource.use id.lease do
    let _ ← checkFlags "osEventFlagsClear" (Internal.Raw.CMSISRTOS.eventFlagsClear id.raw flags.raw)

def eventFlagsGet (id : EventFlagsId) : HalM UInt32 :=
  Internal.Resource.use id.lease <|
    checkFlags "osEventFlagsGet" (Internal.Raw.CMSISRTOS.eventFlagsGet id.raw)

def eventFlagsWait (id : EventFlagsId) (flags : Flags) (timeoutTicks : UInt32)
    (options : WaitOptions := {}) : HalM Bool := do
  requireBlockingContext
  Internal.Resource.use id.lease do
    let mode := match options.mode with | .any => 0 | .all => 1
    let result ← fromIO (Internal.Raw.CMSISRTOS.eventFlagsWait id.raw flags.raw
      (mode + if options.clear then 0 else 2) timeoutTicks)
    if result == 0xFFFFFFFE || (timeoutTicks == 0 && result == 0xFFFFFFFD) then return false
    if result >= 0x80000000 then throw (.rtos "osEventFlagsWait" result)
    return (result &&& flags.raw) != 0

/-- Exclusive deletion rejects active waits and native ISR retention. Every
copy of the old handle becomes stale, including after a native address is reused. -/
def eventFlagsDelete (id : EventFlagsId) : HalM Unit := do
  Internal.Context.interruptsOpen
  Internal.Resource.close id.lease <|
    status "osEventFlagsDelete" (Internal.Raw.CMSISRTOS.eventFlagsDelete id.raw)

/-- Single-use native-only thread entry with RTX-owned stack/control block.
No Lean closure may be used as an RTOS entry or interrupt callback. -/
structure ThreadEntry where
  private mk ::
  private function : USize
  private argument : USize
  private attributes : USize
  private lease : Internal.Resource.Lease

structure ThreadId where
  private mk ::
  private raw : USize

def threadNew (entry : ThreadEntry) : HalM ThreadId := do
  Internal.Context.interruptsOpen
  requireKernel
  if entry.function == 0 then throw (.invalidState "null native thread entry")
  let (_, id) ← Internal.Resource.transition entry.lease do
    let raw ← fromIO (Internal.Raw.CMSISRTOS.threadNew entry.function entry.argument entry.attributes)
    if raw == 0 then throw (.resourceUnavailable "osThreadNew")
    return ThreadId.mk raw
  return id

end
end Board.CMSISRTOS.LowLevel
