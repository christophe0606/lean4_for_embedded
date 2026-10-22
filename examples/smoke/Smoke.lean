module
prelude
public import Init.Notation
public import HardwareContracts
public import HardwareContracts.TimerSequence

@[expose] public section

/-- Runs through actual reference-counted arbitrary-precision Nat arithmetic. -/
@[export lean_embedded_smoke]
def smoke (n : Nat) : Nat := (n + 42) * (n + 1)

@[export lean_embedded_systick_reload]
def sysTickReload (period : UInt32) : UInt32 :=
  HardwareContracts.sysTickReload period

@[export lean_embedded_timer_sequence]
def timerSequence (period : UInt32) (a b c d : UInt32) : UInt32 :=
  HardwareContracts.TimerSequence.checkedReload period a b c d
