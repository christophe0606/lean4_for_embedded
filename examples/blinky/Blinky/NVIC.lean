module
prelude
public import Board.NVIC
public import Blinky.Platform

namespace Blinky.NVIC
public section
abbrev GateM := Board.NVIC.GateM Platform.buttonIRQ
abbrev runOpen {α : Type} := Board.NVIC.runOpen (irq := Platform.buttonIRQ) (α := α)
abbrev masked {α : Type} {line : Board.NVIC.LineGate} :=
  Board.NVIC.masked (irq := Platform.buttonIRQ) (α := α) (line := line)
abbrev initializeLine {α : Type} := Board.NVIC.initializeLine (irq := Platform.buttonIRQ) (α := α)
abbrev temporarilyDisabled {α : Type} := Board.NVIC.temporarilyDisabled
  (irq := Platform.buttonIRQ) (cpu := .blocked) (α := α)
abbrev clearPendingIRQ := Board.NVIC.clearPendingIRQ (irq := Platform.buttonIRQ)
abbrev setPriority := Board.NVIC.setPriority (irq := Platform.buttonIRQ)
end
end Blinky.NVIC
