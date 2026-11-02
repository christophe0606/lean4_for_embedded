module
prelude
public import Init.System.IO

namespace Board

public section

/-- Expected hardware and API failures. CMSIS status words are kept intact so
callers can inspect them without parsing a message or catching an IO error. -/
inductive HalError where
  | gpio (operation : String) (status : UInt32)
  | rtos (operation : String) (status : UInt32)
  | usart (operation : String) (status : UInt32)
  | pinConfig (status : UInt32)
  | resourceUnavailable (operation : String)
  | invalidState (reason : String)
  | eventSinkUnbound
  deriving Repr

abbrev HalM (α : Type) := ExceptT HalError IO α

/-- Lift an underlying IO action without turning its result into a HAL error. -/
def fromIO (action : IO α) : HalM α := ExceptT.lift action

def HalError.describe : HalError → String
  | .gpio operation status => operation ++ " failed (GPIO status " ++ toString status ++ ")"
  | .rtos operation status => operation ++ " failed (RTOS status " ++ toString status ++ ")"
  | .usart operation status => operation ++ " failed (USART status " ++ toString status ++ ")"
  | .pinConfig status => "pinconf_set failed (status " ++ toString status ++ ")"
  | .resourceUnavailable operation => operation ++ " could not allocate a resource"
  | .invalidState reason => reason
  | .eventSinkUnbound => "button event sink is not bound"

end
end Board
