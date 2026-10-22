module
prelude
public import Init.Notation
public import HardwareContracts

@[expose] public section

/-- Runs through actual reference-counted arbitrary-precision Nat arithmetic. -/
@[export lean_embedded_smoke]
def smoke (n : Nat) : Nat := (n + 42) * (n + 1)

@[export lean_embedded_systick_reload]
def sysTickReload (period : UInt32) : UInt32 :=
  HardwareContracts.sysTickReload period
