# Lean Blinky on the Alif DevKit-E8

`DevKit-E8@blinky` builds a separate `LeanBlinky` project for the board's M55_HP core. Its image is `out/LeanBlinky/DevKit-E8/Debug/lean-blinky.elf`. The project compiles the Blinky module and does not include the smoke or console demos.

## Behavior

Both onboard RGB LEDs cycle red, green, then blue together. Each color is on and off for 1000 ms in the initial pattern. Pressing the joystick **center** changes to 100 ms on/off intervals; each subsequent press alternates between the two patterns. The button press is debounced for 30 ms and accepted at most once every 200 ms.

This combines two examples from `AlifSemiconductor::Ensemble@2.2.1`:

- `Boards/DevKit-e8/Examples/Blinky_HP/M55_HP/main.c` supplies the paired RGB color sequence. That example uses a bare-metal SysTick delay and has no button handling.
- `Boards/DevKit-e8/Examples/DualCore/M55_HP/app_main.c` supplies the idea of changing a blink pattern in response to a button event. The pack's `Boards/DevKit-e8/Drivers/vio_DevKit-E8.c` maps its button to the joystick center.

The DevKit-E8 user guide identifies the joystick and RGB LEDs on the top side (AUGD0023 v1.2 p.8); the pack's `Boards/DevKit-e8/board_defs.h` gives the GPIO assignments used here:

| Signal | GPIO | CMSIS pin number |
| --- | --- | ---: |
| RGB0 red / green / blue | P12_3 / P7_4 / P12_0 | 99 / 60 / 96 |
| RGB1 red / green / blue | P6_2 / P6_4 / P6_6 | 50 / 52 / 54 |
| Joystick center | LPGPIO15_4 | 124 |

The joystick center is active low. The GPIO driver treats output level `1` as LED on, as in the pack's VIO implementation.

## Lean and C boundary

[Blinky.lean](../examples/blinky/Blinky.lean) selects the pins, initializes all six LED outputs, cycles their colors, owns the timing and pattern state, debounces the button, and prints pattern changes. `IO.asTask` runs the application on a dedicated Lean worker backed by an RTX thread.

[main.c](../examples/blinky/main.c) handles board UART setup, RTX kernel startup, Lean runtime/module initialization, and task-manager startup. [gpio_bridge.c](../examples/blinky/gpio_bridge.c) exposes the CMSIS GPIO calls to Lean. Its button IRQ callback only sets an RTX event flag; it never calls the Lean runtime from interrupt context. Lean waits for that event with a timeout, so a press can change the pattern during either the on or off interval.

The joystick interrupt must be armed atomically. The pack's GPIO `Setup` enables the NVIC line before returning, so a separate Lean call to configure the pull-up and falling-edge trigger can allow repeated IRQs and overflow RTX's ISR queue. The C bridge masks interrupts while configuring that one input, clears the pending request, and restores interrupts after the pin is ready. The application logic remains in Lean.

## Build and run

1. Power the DevKit through PRG USB, use the existing M55_HP application/ATOC provisioning, and connect the ULINKplus probe.
2. In CMSIS View select `DevKit-E8@blinky`, then **Build** and **Load & Debug**. The target set specifies `ULINKplus@pyOCD`.
3. Set SW4 to UART4 with power off, then open the board's UART at 115200 8N1. On the tested setup it enumerated as COM5.
4. Resume from the initial `main` breakpoint. The UART prints `Lean Blinky: RGB0 and RGB1, slow pattern (1000 ms)` and the joystick instruction. Press and release the joystick center; the UART reports the new pattern.

The board startup, MRAM linker layout, UART4 retargeting, and RTX runtime are shared with the existing E8 target sets. The native CMake project mirrors the [board layer](../board/DevKit-E8/Board.clayer.yml); CMSIS-Toolbox 2.15 does not attach `.clayer.yml` components directly to a native `cmake:` project.

## Verification

On the DevKit-E8 A1 with ULINKplus, the standalone project built and loaded through CMSIS View. UART4 printed the startup instructions and then `Blinky: fast pattern (100 ms)` and `Blinky: slow pattern (1000 ms)` on two joystick-center presses. The board operator confirmed the visible RGB blink sped up and returned to the slower rate. The existing `DevKit-E8@minimal` target also built after the shared CMake change.
