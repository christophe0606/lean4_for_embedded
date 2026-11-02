module
prelude
public import Board.GPIO.LowLevel

namespace Board.GPIO
public section
abbrev Direction := LowLevel.Direction
abbrev Pull := LowLevel.Pull
abbrev Output (driver : USize) (pin : UInt32) := LowLevel.Pin driver pin .output true
abbrev Input (driver : USize) (pin : UInt32) (preloaded : Bool := false) :=
  LowLevel.Pin driver pin .input preloaded

def setupOutput (driver : LowLevel.Driver) (pin : UInt32) (initial : Bool := false) :
    HalM (Output driver.address pin) := do
  let ready ← LowLevel.setup driver pin
  let preloaded ← LowLevel.preloadOutput ready initial
  LowLevel.setDirection preloaded .output

def Output.set (output : Output driver pin) (value : Bool) : HalM Unit :=
  LowLevel.setOutput output value

/-- An application can write the same sequence from checked LowLevel operations. -/
def setupInput (driver : LowLevel.Driver) (pin : UInt32) (pull : Pull := .none) :
    HalM (Input driver.address pin) := do
  let ready ← LowLevel.setup driver pin
  LowLevel.setPullResistor ready pull
  LowLevel.setDirection ready .input

def Input.read (input : Input driver pin preloaded) : HalM Bool := LowLevel.getInput input
end
end Board.GPIO
