module
prelude
public import Board.Error
import Board.Internal.Context

namespace Board.Internal.Resource
public section

@[extern "lean_board_resource_claim"] private opaque claimRaw (kind : UInt32) (key : USize) (subkey : UInt32) : IO UInt32
@[extern "lean_board_resource_claim_range"] private opaque claimRangeRaw (kind : UInt32) (key extent : USize) : IO UInt32
@[extern "lean_board_resource_find"] private opaque findRaw (kind : UInt32) (key : USize) (subkey : UInt32) : IO UInt32
@[extern "lean_board_resource_epoch"] private opaque epochRaw (ticket : UInt32) : IO UInt32
@[extern "lean_board_resource_begin"] private opaque beginRaw (ticket epoch write : UInt32) : IO UInt32
@[extern "lean_board_resource_end"] private opaque endRaw (operation outcome : UInt32) : IO UInt32

/-- Trusted implementation detail; checked public handles hide this value. -/
structure Lease where
  ticket : UInt32
  epoch : UInt32

def claim (kind : UInt32) (key : USize) (subkey : UInt32 := 0) : HalM Lease := do
  Context.thread
  let ticket ← fromIO (claimRaw kind key subkey)
  if ticket == 0 then throw (.invalidState "resource already owned, poisoned, or registry exhausted")
  return ⟨ticket, 1⟩

def find (kind : UInt32) (key : USize) (subkey : UInt32 := 0) : HalM Lease := do
  Context.thread
  let ticket ← fromIO (findRaw kind key subkey)
  let epoch ← fromIO (epochRaw ticket)
  if epoch == 0 then throw (.invalidState "native resource has no live checked owner")
  return ⟨ticket, epoch⟩

def claimRange (kind : UInt32) (key extent : USize) : HalM Lease := do
  Context.thread
  let ticket ← fromIO (claimRangeRaw kind key extent)
  if ticket == 0 then throw (.invalidState "invalid, overlapping, already owned, or exhausted native memory range")
  return ⟨ticket, 1⟩

def acquire (lease : Lease) (write : Bool := false) : HalM UInt32 := do
  Context.thread
  let operation ← fromIO (beginRaw lease.ticket lease.epoch (if write then 1 else 0))
  if operation == 0 then throw (.invalidState "stale, closed, pinned, or busy resource")
  return operation

def release (operation : UInt32) : HalM Unit := do
  if (← fromIO (endRaw operation 1)) == 0 then
    throw (.invalidState "lease was already released")

def releaseUnchanged (operation : UInt32) : HalM Unit := do
  if (← fromIO (endRaw operation 3)) == 0 then
    throw (.invalidState "exclusive lease was already released")

def use (lease : Lease) (action : HalM α) : HalM α := do
  let operation ← acquire lease
  ExceptT.mk <| try action.run finally do
    let _ ← endRaw operation 1

private def finish (operation outcome : UInt32) (action : HalM α) : HalM (UInt32 × α) :=
  ExceptT.mk do
    try
      match ← action.run with
      | .error error =>
        let _ ← endRaw operation 0
        return .error error
      | .ok result =>
        let epoch ← endRaw operation outcome
        if epoch == 0 then return .error (.invalidState "resource transition exhausted")
        return .ok (epoch, result)
    catch error =>
      let _ ← endRaw operation 0
      throw error

private def exclusive (lease : Lease) (outcome : UInt32) (action : HalM α) : HalM (UInt32 × α) := do
  let operation ← acquire lease true
  finish operation outcome action

def transition (lease : Lease) (action : HalM α) : HalM (Lease × α) := do
  let (epoch, result) ← exclusive lease 1 action
  return (⟨lease.ticket, epoch⟩, result)

/-- Acquire the instance before reserving a second resource. Preparation must
only acquire metadata, without touching hardware. Rejecting a stale instance or
busy buffer preserves both resources; failures after hardware starts fail closed. -/
def transitionPrepared (lease : Lease) (prepare : HalM β) (action : β → HalM α) :
    HalM (Lease × α) := do
  let operation ← acquire lease true
  let prepared ← ExceptT.mk do
    try
      match ← prepare.run with
      | .ok value => return .ok value
      | .error error =>
        let _ ← endRaw operation 3
        return .error error
    catch error =>
      let _ ← endRaw operation 3
      throw error
  let (epoch, result) ← finish operation 1 (action prepared)
  return (⟨lease.ticket, epoch⟩, result)

def modify (lease : Lease) (action : HalM α) : HalM α := do
  return (← exclusive lease 3 action).2

def close (lease : Lease) (action : HalM Unit) : HalM Unit := do
  let _ ← exclusive lease 2 action

/-- A permanent keyed operation mutex, distinct from the resource's state.
Always release it on errors: the enclosed state transition owns invalidation.
Use outside pin guards so lock contention never consumes a pin transition. -/
def serialized (kind : UInt32) (key : USize) (action : HalM α) : HalM α := do
  Context.thread
  let found ← fromIO (findRaw kind key 0)
  let ticket ← if found != 0 then pure found else fromIO (claimRaw kind key 0)
  -- Another thread may have claimed the mutex between find and claim.
  let ticket ← if ticket != 0 then pure ticket else fromIO (findRaw kind key 0)
  if ticket == 0 then throw (.invalidState "operation mutex registry exhausted")
  let epoch ← fromIO (epochRaw ticket)
  let operation ← acquire ⟨ticket, epoch⟩ true
  ExceptT.mk <| try action.run finally do
    let _ ← endRaw operation 3

end
end Board.Internal.Resource
