# Corstone-300 FVP board layer

This layer selects the BSP's `Device:Startup&C Startup` component and CMSIS
CORE. BSP 1.5.0 supports CMSIS 6; BSP 1.4.0 requires CMSIS 5.
The configured startup and system sources in `RTE/Device/SSE-300-MPS3` retain
the previous build's BSP 1.4.0 configuration. CMSIS manages and compiles them
as component configuration files.

The firmware runs entirely in secure state (`trustzone: secure-only`). The
Debug and Console profiles select their respective linker scripts here.
Both reserve the CMSIS startup stack seal above the initial MSP stack and
provide the GCC and Clang symbol spellings. GCC uses rdimon semihosting;
Clang uses its semihost library. RTX and the Lean adapters are selected by
`runtime/Lean.clayer.yml`.
