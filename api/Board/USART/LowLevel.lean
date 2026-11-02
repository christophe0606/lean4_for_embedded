module
prelude
public import Board.Error
import Board.Internal.Raw.USART
import Board.Internal.Resource

namespace Board.USART.LowLevel
public section

inductive State where
  | initialized | powered | configured (tx rx : Option Bool)
structure Instance where
  private mk ::
  private raw : USize
def Instance.address (instance_ : Instance) : USize := instance_.raw

structure Driver (address : USize) (_state : State) where
  private mk ::
  private lease : Internal.Resource.Lease

private def check (name : String) (action : IO Int32) : HalM Unit := do
  let value ← fromIO action
  if value != 0 then throw (.usart name value.toUInt32)

private def requireIdle (address : USize) : HalM Unit := do
  if (← fromIO (Internal.Raw.USART.getTxBusy address)) != 0 ||
      (← fromIO (Internal.Raw.USART.getRxBusy address)) != 0 then
    throw (.invalidState "USART driver is busy")

private def step (driver : Driver address before) (action : IO Int32) :
    HalM (Driver address after) := do
  let (lease, _) ← Internal.Resource.transition driver.lease do
    requireIdle address
    check "USART" action
  return Driver.mk lease

/-- Callback-free native initialization. Board adapters supply a permanent
valid instance and exclusive ownership; application code cannot forge addresses. -/
def «initialize» (instance_ : Instance) : HalM (Driver instance_.address .initialized) := do
  if instance_.raw == 0 then throw (.invalidState "null USART instance")
  let lease ← Internal.Resource.claim 4 instance_.raw
  let (lease, _) ← Internal.Resource.transition lease <|
    do
      requireIdle instance_.raw
      check "USART.Initialize" (Internal.Raw.USART.initialize instance_.raw 0)
  return Driver.mk lease

def powerOn (driver : Driver address .initialized) : HalM (Driver address .powered) :=
  step driver (Internal.Raw.USART.powerControl address 2)

/-- CMSIS Driver_USART.h: asynchronous 8N1, no flow control. Other formats
can be added as checked variants instead of exposing an arbitrary control word. -/
def configure (driver : Driver address .powered) (baud : UInt32) :
    HalM (Driver address (.configured none none)) := do
  if baud == 0 then throw (.invalidState "USART baud must be nonzero")
  step driver (Internal.Raw.USART.control address 1 baud)

def setTransmitter (driver : Driver address (.configured tx rx)) (enabled : Bool) :
    HalM (Driver address (.configured (some enabled) rx)) :=
  step driver (Internal.Raw.USART.control address 0x15 (if enabled then 1 else 0))

def setReceiver (driver : Driver address (.configured tx rx)) (enabled : Bool) :
    HalM (Driver address (.configured tx (some enabled))) :=
  step driver (Internal.Raw.USART.control address 0x16 (if enabled then 1 else 0))

def powerOff (driver : Driver address (.configured (some false) (some false))) :
    HalM (Driver address .initialized) :=
  step driver (Internal.Raw.USART.powerControl address 0)

def uninitialize (driver : Driver address .initialized) : HalM Unit :=
  Internal.Resource.close driver.lease do
    requireIdle address
    check "USART.Uninitialize" (Internal.Raw.USART.uninitialize address)

/-- Permanent native storage from a trusted adapter. No borrowed Lean array or
stack address can be submitted. The registry prevents overlapping buffer users.
The adapter must not access/free the storage until the transfer completes. -/
structure Buffer where
  private mk ::
  private raw : USize
  private capacity : UInt32
  private lease : Internal.Resource.Lease

inductive TransferKind where | send | receive
structure Transfer (address : USize) (tx rx : Option Bool) (_kind : TransferKind) where
  private mk ::
  private lease : Internal.Resource.Lease
  private bufferOperation : UInt32
  private count : UInt32

private def beginTransfer (driver : Driver address (.configured tx rx)) (buffer : Buffer)
    (count : UInt32) (action : IO Int32) : HalM (Transfer address tx rx kind) := do
  if count == 0 || count > buffer.capacity then throw (.invalidState "USART buffer count outside capacity")
  -- On a driver failure keep the buffer reserved: an uncertain DMA state
  -- must never make storage available to another transfer.
  let (lease, operation) ← Internal.Resource.transitionPrepared driver.lease
      (Internal.Resource.acquire buffer.lease true) fun operation => do
    requireIdle address
    check "USART transfer" action
    return operation
  return Transfer.mk lease operation count

def send (driver : Driver address (.configured (some true) rx)) (buffer : Buffer) (count : UInt32) :
    HalM (Transfer address (some true) rx .send) :=
  beginTransfer driver buffer count (Internal.Raw.USART.send address buffer.raw count)

def receive (driver : Driver address (.configured tx (some true))) (buffer : Buffer) (count : UInt32) :
    HalM (Transfer address tx (some true) .receive) :=
  beginTransfer driver buffer count (Internal.Raw.USART.receive address buffer.raw count)

/-- Poll without changing state until the count is complete and the driver
reports idle. No configuration or buffer reuse can race an active transfer.
One transfer per checked instance; full-duplex ownership is not yet exposed. -/
def poll (transfer : Transfer address tx rx kind) :
    HalM (Option (Driver address (.configured tx rx))) := do
  let completed ← Internal.Resource.modify transfer.lease do
    let count ← fromIO <| match kind with
      | .send => Internal.Raw.USART.getTxCount address
      | .receive => Internal.Raw.USART.getRxCount address
    let busy ← fromIO <| match kind with
      | .send => Internal.Raw.USART.getTxBusy address
      | .receive => Internal.Raw.USART.getRxBusy address
    return decide (count >= transfer.count) && busy == 0
  if !completed then return none
  let (lease, _) ← Internal.Resource.transition transfer.lease do
    Internal.Resource.releaseUnchanged transfer.bufferOperation
  return some (Driver.mk lease)

def abort (transfer : Transfer address tx rx kind) :
    HalM (Driver address (.configured tx rx)) := do
  let control := match kind with | .send => 0x18 | .receive => 0x19
  let (lease, _) ← Internal.Resource.transition transfer.lease do
    check "USART.Abort" (Internal.Raw.USART.control address control 0)
    let busy ← fromIO <| match kind with
      | .send => Internal.Raw.USART.getTxBusy address
      | .receive => Internal.Raw.USART.getRxBusy address
    if busy != 0 then throw (.invalidState "USART remains busy after abort")
    Internal.Resource.releaseUnchanged transfer.bufferOperation
  return Driver.mk lease

end
end Board.USART.LowLevel
