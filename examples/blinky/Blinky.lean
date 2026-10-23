module
prelude
public import Blinky.Board

namespace Blinky

private def waitPhase (board : Board.Ready) (speed : Board.Speed)
    (lastPress : Option Nat) : HalM (Board.Speed × Option Nat) := do
  if !(← Board.waitCenterPress board speed) then
    return (speed, lastPress)
  let now ← fromIO IO.monoMsNow
  let oldEnough := match lastPress with
    | none => true
    | some previous => now >= previous + 200
  if !oldEnough then
    return (speed, lastPress)
  let next := speed.toggle
  fromIO <| IO.println (match next with
    | .fast => "Blinky: fast pattern (100 ms)"
    | .slow => "Blinky: slow pattern (1000 ms)")
  return (next, some now)

private def pulse (board : Board.Ready) (color : Board.Color)
    (speed : Board.Speed) (lastPress : Option Nat) : HalM (Board.Speed × Option Nat) := do
  Board.display board (some color)
  let (speed, lastPress) ← waitPhase board speed lastPress
  Board.display board none
  waitPhase board speed lastPress

private partial def blinkLoop (board : Board.Ready) (speed : Board.Speed)
    (lastPress : Option Nat) : HalM Unit := do
  let (speed, lastPress) ← pulse board .red speed lastPress
  let (speed, lastPress) ← pulse board .green speed lastPress
  let (speed, lastPress) ← pulse board .blue speed lastPress
  blinkLoop board speed lastPress

private def application : HalM Unit := do
  let board ← Board.prepare
  fromIO <| IO.println "Lean Blinky: RGB0 and RGB1, slow pattern (1000 ms)"
  fromIO <| IO.println "Press the joystick center to toggle the pattern."
  blinkLoop board .slow none

-- The C entry point expects IO. Convert a typed HAL failure only here.
private def applicationIO : IO Unit := do
  match ← application.run with
  | .ok () => pure ()
  | .error err => throw (IO.userError err.describe)

-- The application runs on a dedicated Lean worker backed by an RTX thread.
@[export lean_blinky_run]
def run : IO Unit := do
  let worker ← IO.asTask applicationIO Task.Priority.dedicated
  match worker.get with
  | .ok () => pure ()
  | .error err => throw err

end Blinky
