module
prelude
public import Board.SysTick.LowLevel

namespace Board.SysTick
public section

/-- Convenience only: applications can compose the same checked primitives. -/
def «initialize» (config : Config period) : HalM (LowLevel.Timer .running) :=
  CPU.LowLevel.withInterruptsMasked do
    let timer ← LowLevel.acquire
    let stopped ← LowLevel.stop timer
    let loaded ← LowLevel.load stopped config
    let cleared ← LowLevel.clear loaded
    LowLevel.start cleared

end
end Board.SysTick
