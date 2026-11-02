module
prelude
public import Board.GPIO
public import Board.NVIC
public import Board.CMSISRTOS
public import Board.SysTick
public import Board.USART.LowLevel

/-! Reusable Cortex-M APIs. Import individual submodules to select the
firmware dependency closure. Vendor APIs are opt-in imports. -/
