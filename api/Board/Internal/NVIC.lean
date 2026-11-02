module
prelude
import all Board.NVIC.LowLevel
public import Board.NVIC.LowLevel

namespace Board.Internal.NVIC
public section

/-- Trusted boundary: preserve PRIMASK and the indexed line. Native setup
that opens gates must close them before returning, including on errors. -/
@[noinline] def lift (action : HalM α) : Board.NVIC.LowLevel.GateM irq cpu line α :=
  Board.NVIC.LowLevel.GateM.wrap action

end
end Board.Internal.NVIC
