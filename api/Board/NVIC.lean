module
prelude
public import Board.NVIC.LowLevel

namespace Board.NVIC
public section
abbrev CpuGate := LowLevel.CpuGate
abbrev LineGate := LowLevel.LineGate
abbrev GateM := LowLevel.GateM
abbrev runOpen := @LowLevel.runOpen
abbrev masked := @LowLevel.masked
abbrev initializeLine := @LowLevel.initializeLine
abbrev temporarilyDisabled := @LowLevel.disabled
abbrev clearPendingIRQ := @LowLevel.clearPendingIRQ
abbrev setPriority := @LowLevel.setPriority
end
end Board.NVIC
