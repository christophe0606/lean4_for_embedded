module
prelude
public import HardwareContracts
public import HardwareContracts.TimerSequence

namespace Board.SysTick
public section

abbrev Config := HardwareContracts.SysTickConfig
abbrev checkedConfig := HardwareContracts.checkedSysTick
abbrev checkedReload := HardwareContracts.sysTickReload
abbrev checkedSequence := HardwareContracts.TimerSequence.checkedReload

end
end Board.SysTick
