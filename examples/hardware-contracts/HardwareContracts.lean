module
prelude
public import Init.Prelude

@[expose] public section
namespace HardwareContracts

/-- A nonzero 24-bit SysTick reload representing exactly the requested period.
The proof fields are erased when Lean generates C. -/
structure SysTickConfig (period : Nat) where
  reload : Fin 16777216
  positive : LT.lt 0 reload.val
  exactPeriod : Eq period (Nat.succ reload.val)

/-- Reject periods 0 and 1, and periods exceeding the 24-bit counter range. -/
def checkedSysTick : (period : Nat) → Option (SysTickConfig period)
  | Nat.zero => Option.none
  | Nat.succ Nat.zero => Option.none
  | Nat.succ (Nat.succ n) =>
    match Nat.decLt (Nat.succ n) 16777216 with
    | Decidable.isTrue h =>
      Option.some { reload := ⟨Nat.succ n, h⟩,
                    positive := Nat.zero_lt_succ n,
                    exactPeriod := rfl }
    | Decidable.isFalse _ => Option.none

/-- No accepted configuration writes reserved bits of SYST_RVR. -/
theorem noReservedBits {period : Nat} (config : SysTickConfig period) :
    LT.lt config.reload.val 16777216 := config.reload.isLt

/-- No accepted configuration uses the ineffective zero reload. -/
theorem nonzeroReload {period : Nat} (config : SysTickConfig period) :
    LT.lt 0 config.reload.val := config.positive

/-- The programmed reload has no off-by-one error relative to the requested period. -/
theorem exactPeriod {period : Nat} (config : SysTickConfig period) :
    Eq period (Nat.succ config.reload.val) := config.exactPeriod

/-- The two degenerate periods are rejected, proved by reduction. -/
theorem rejectsZero : Eq (checkedSysTick 0) Option.none := rfl

theorem rejectsOne : Eq (checkedSysTick 1) Option.none := rfl

/-- At the C boundary, zero is the rejection sentinel, never a valid reload. -/
def sysTickReload (period : UInt32) : UInt32 :=
  match checkedSysTick period.toNat with
  | Option.none => UInt32.ofNatLT 0 (of_decide_eq_true rfl)
  | Option.some config => UInt32.ofNatLT config.reload.val
      (Nat.lt_trans config.reload.isLt (of_decide_eq_true rfl))

end HardwareContracts
