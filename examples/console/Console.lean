module
prelude
public import Init.System.IO

@[expose] public section

@[export lean_console_demo]
def greet (message : String) : IO Unit := do
  let work := Task.spawn (fun _ => (100000 : Nat) + 42)
  let doubled := work.map (fun n => n * 2)
  if doubled.get != 200084 then
    throw (IO.userError "Lean Task result mismatch")
  IO.sleep 3
  IO.println message
  IO.println "PASS: standard Lean IO.println on RTX"
