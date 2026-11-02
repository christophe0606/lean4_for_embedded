# DevKit-E8 M55_HP board layer

This layer targets `Alif Semiconductor::DevKit-E8:A1` with device
`AE822FA0E5597LS0:M55_HP` from `AlifSemiconductor::Ensemble@2.2.1`.
The stock pack's M55_HP layer is broader than the Lean demos: it includes NPU,
camera, display, Ethernet, USB, and secure service components. This project uses
the pack's Device:Startup and CMSIS USART4 driver with a small board-specific
runtime instead. `RTE/Device/AE822FA0E5597LS0_M55_HP` contains the pack's
configured headers needed by that startup and driver (original Alif notices are
preserved). Pack source files are selected by CMSIS components and are not vendored.

`memory.ld` places the HP image in the pack's default 2 MiB HP MRAM slice at
`0x80200000` and confines data, heap, and stack to 4 MiB SRAM0 at `0x02000000`.
`stdio.c` selects the pack's UART4 routing, P12_1/P12_2 alternate function 2,
at 115200 baud. The board's PRG USB switch SW4 must select UART4 (Alif E8
DevKit User Guide AUGD0023 v1.2, pp. 4, 7).

The example cprojects include this board layer directly. CMSIS resolves and builds
Device:Startup, PINCONF and USART from the Ensemble pack and generates
`RTE_Components.h` for each context. Blinky selects the additional GPIO component.
The configured device headers stay in this layer's `RTE/Device` directory.
The shared `runtime/Lean.clayer.yml` selects RTX source and its configuration;
CMake builds only the Lean library linked by each example.
