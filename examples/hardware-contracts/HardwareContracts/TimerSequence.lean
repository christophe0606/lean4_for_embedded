module
prelude
public import HardwareContracts
public import Init.Core
public import Init.Data.List.Notation

@[expose] public section
namespace HardwareContracts.TimerSequence

/-- A software protocol for a timer owned exclusively by this driver. -/
inductive State where
  | unknown | stopped | configured | ready | running

inductive Command where
  | stop | configure | clear | enable

/-- The specification: configuration writes require a stopped timer;
enabling requires configuration followed by clearing the current count. -/
inductive Allowed : State → Command → State → Prop where
  | stop (s) : Allowed s .stop .stopped
  | configure : Allowed .stopped .configure .configured
  | clear : Allowed .configured .clear .ready
  | enable : Allowed .ready .enable .running

/-- The executable validator, kept separate from the specification. -/
def next : State → Command → Option State
  | _, .stop => some .stopped
  | .stopped, .configure => some .configured
  | .configured, .clear => some .ready
  | .ready, .enable => some .running
  | _, _ => none

def check (s : State) : List Command → Option State
  | [] => some s
  | command :: rest =>
    match next s command with
    | none => none
    | some after => check after rest

/-- Every prefix follows a permitted transition, not just the final command. -/
inductive SafeTrace : State → List Command → State → Prop where
  | done (s) : SafeTrace s [] s
  | step : Allowed before command after → SafeTrace after rest final →
      SafeTrace before (command :: rest) final

theorem next_sound {s command after} (h : next s command = some after) :
    Allowed s command after := by
  cases command <;> cases s <;> cases h <;> constructor

/-- Soundness for arbitrary lists, proved by induction on the whole program. -/
theorem check_sound (commands : List Command) (s final : State)
    (h : check s commands = some final) : SafeTrace s commands final := by
  induction commands generalizing s with
  | nil =>
    cases h
    exact .done _
  | cons command rest ih =>
    cases transition : next s command with
    | none =>
      unfold check at h
      rw [transition] at h
      cases h
    | some after =>
      unfold check at h
      rw [transition] at h
      exact .step (next_sound transition) (ih after h)

theorem no_live_configuration {after} (h : Allowed .running .configure after) :
    False := by cases h

theorem enable_requires_ready {before after} (h : Allowed before .enable after) :
    before = .ready ∧ after = .running := by
  cases h
  exact ⟨rfl, rfl⟩

/-- A plan carries both the numeric hardware contract and its sequencing proof. -/
structure ApprovedPlan (period : Nat) (commands : List Command) where
  config : SysTickConfig period
  safe : SafeTrace .unknown commands .running

def approve (period : Nat) (commands : List Command) :
    Option (ApprovedPlan period commands) :=
  match checkedSysTick period with
  | none => none
  | some config =>
    match accepted : check .unknown commands with
    | some .running => some ⟨config, check_sound commands .unknown .running accepted⟩
    | _ => none

/-- The command codes shared with the small trusted C executor. -/
def decode (byte : UInt32) : Option Command :=
  match byte.toNat with
  | 0 => some .stop
  | 1 => some .configure
  | 2 => some .clear
  | 3 => some .enable
  | _ => none

/-- Validate the entire four-command plan before any MMIO. Zero rejects it;
otherwise return the already-proved nonzero, 24-bit reload value. -/
def checkedReload (period : UInt32) (a b c d : UInt32) : UInt32 :=
  match decode a, decode b, decode c, decode d with
  | some a, some b, some c, some d =>
    match approve period.toNat [a, b, c, d] with
    | some plan => UInt32.ofNatLT plan.config.reload.val
        (Nat.lt_trans plan.config.reload.isLt (of_decide_eq_true rfl))
    | none => UInt32.ofNatLT 0 (of_decide_eq_true rfl)
  | _, _, _, _ => UInt32.ofNatLT 0 (of_decide_eq_true rfl)

theorem valid_initialization :
    check .unknown [.stop, .configure, .clear, .enable] = some .running := rfl

theorem rejects_live_configuration :
    check .running [.configure] = none := rfl

theorem rejects_missing_clear :
    check .unknown [.stop, .configure, .enable] = none := rfl

end HardwareContracts.TimerSequence
