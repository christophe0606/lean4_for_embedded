# Lean Blinky on the Alif DevKit-E8

`DevKit-E8@blinky` builds a separate `LeanBlinky` project for the board's M55_HP core. Its image is `out/LeanBlinky/DevKit-E8/Debug/lean-blinky.elf`. The project compiles the Blinky module and does not include the smoke or console demos.

## Behavior

Both onboard RGB LEDs cycle red, green, then blue together. Each color is on and off for 1000 ms in the initial pattern. Pressing the joystick **center** changes to 100 ms on/off intervals; each subsequent press alternates between the two patterns. Lean accepts a falling-edge button event at most once every 200 ms. On the tested board, press the joystick firmly for about half a second; very brief taps did not register consistently.

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

[Blinky.lean](../examples/blinky/Blinky.lean) cycles the colors, owns the timing and pattern state, and prints pattern changes. `IO.asTask` runs the application on a dedicated Lean worker backed by an RTX thread. [Blinky/Board.lean](../examples/blinky/Blinky/Board.lean) creates the event flags, invokes the Lean GPIO/NVIC setup plans, selects the displayed color, and interprets button events. The initialized LEDs and armed button are stored in the private `Ready` capability.

[Blinky/GPIO.lean](../examples/blinky/Blinky/GPIO.lean) performs LED setup and a closed, typed button setup sequence. [Blinky/NVIC.lean](../examples/blinky/Blinky/NVIC.lean) defines actions indexed by the CPU mask and NVIC line states, with brackets that establish those states while executing the actions. [Blinky/CMSISRTOS.lean](../examples/blinky/Blinky/CMSISRTOS.lean) exposes `EventFlags.new`, `set`, and `wait`, plus a button-event binding action that requires both gates closed. Its private-constructor `EventFlagsId` is a Lean value; Lean can replace the binding through `Board.replaceEvents`.

[Blinky/HalError.lean](../examples/blinky/Blinky/HalError.lean) defines `HalM α = ExceptT HalError IO α`. GPIO and CMSIS-RTOS calls return `.gpio operation status` or `.rtos operation status`, preserving the raw numeric status. Resource exhaustion, dynamic state conflicts, and an unbound event sink have separate error constructors. The GPIO, NVIC, RTOS, board, and blink functions propagate these values through Lean `do` notation; callers can inspect them with `match ← action.run with | .ok value => ... | .error error => ...`. An event wait timeout is an ordinary `false` result. Only the exported application's `IO` boundary formats an unhandled `HalError` as an `IO.userError` for the C startup code.

[main.c](../examples/blinky/main.c) handles board UART setup, RTX kernel startup, Lean runtime/module initialization, and task-manager startup. [hardware_bridge.c](../examples/blinky/hardware_bridge.c) maps the board pack's pin IDs and forwards elementary CMSIS GPIO, NVIC, and RTOS calls. Its button IRQ callback only sets an RTX event flag; it never calls the Lean runtime from interrupt context. Lean waits for that event with a timeout, so a press can change the pattern during either the on or off interval.

### Enforced GPIO flow

The board API admits only `Color.red`, `Color.green`, `Color.blue` and `Speed.slow` or `Speed.fast`. GPIO pins form a closed Lean type with separate LED and button roles. Callers cannot pass an arbitrary GPIO number or set the button pin as an LED output. `Board.prepare : HalM Board.Ready` uses `GPIO.setupLeds` to initialize the six outputs in a fixed plan, then follows this typed button path:

```text
create event flags → disable LPGPIO IRQ4 → mask CPU IRQs
→ Driver_GPIO.Setup with callback → disable GPIO interrupt and LPGPIO IRQ4
→ pull-up → input direction → falling edge
→ mask CPU IRQs, clear GPIO and NVIC pending state, set priority
→ unmask and enable GPIO interrupt → enable LPGPIO IRQ4
```

`GPIO.ButtonState` and `GPIO.Button state` are Lean types: each private setup step requires the type returned by the previous step. Only `GPIO.prepareButton`, which finishes at `Button .enabled`, is public. The intermediate values cannot escape to application code or be replayed there. Each LED `Output` is indexed by its exact pin, so `GPIO.Leds` cannot be constructed with a red output in a green slot. `NVIC.GateM cpu line α` records the required gate states in the action's type. `NVIC.masked` and `NVIC.initializeLine` establish those states when executing it, so no copyable `Blocked` or `Disabled` token and no runtime `active` check are needed. `Board.display` and `Board.waitCenterPress` require `Ready`, returned only after setup succeeds.

These ordering rules use indexed types and private constructors directly; they do not need separate theorems. A saved gated action remains safe to execute later because the mask/disable brackets are entered each time it runs. Lean values are not linear, so a type alone cannot prove that a global event object or hardware setup was used exactly once across arbitrary calls.

The pack's GPIO `Setup` enables its interrupt before returning. `NVIC.masked` briefly masks configurable CPU interrupts while Lean calls Setup and closes both gates again. The previous PRIMASK is restored even if a typed HAL error occurs. The pull-up, direction, and edge calls run afterward with the specific NVIC line disabled. A second short guarded block clears pending state and enables the GPIO source; `NVIC.initializeLine` enables the NVIC line only after the whole setup action succeeds. The event ID is created by Lean after the kernel starts and handed to the C ISR at callback setup.

The gate state belongs to the *action*, not a token claiming that hardware is currently masked. A saved action can be run again, but each run enters a fresh mask/disable bracket. `GateM.fromHal` is the trusted adapter for elementary HAL actions that preserve the stated gate state; the FFI and other firmware remain outside Lean's proof. The C adapter checks actual PRIMASK, NVIC, kernel state, and repeated setup at the boundary.

| Validation | Where it happens now |
| --- | --- |
| Pin role, button setup order, and the gates required by each step | Lean types and private setup steps, at compile time |
| A partially configured LED used as an output, or a caller choosing a duplicate LED within one setup | Impossible through the public Lean API; only the fixed `setupLeds` plan returns the six outputs |
| Driver/RTOS failure, event allocation, or dynamically supplied flag bits | Runtime status or value check |
| A second hardware setup, concurrent button wait/rebind, or rebinding the same event object | Runtime check; these depend on call history or concurrent activity |
| Hardware changed by C, another core, or another thread | C boundary checks or hardware status; Lean's action types cannot establish external ownership |

The ISR requires a persistent C event-ID slot because the CMSIS GPIO callback has no user context pointer. `Board.waitCenterPress` now reads that same slot before waiting; it does not keep a second copy in `Ready`. `Board.replaceEvents` changes the slot from Lean while CPU delivery and LPGPIO IRQ4 are disabled, clears pending state, and returns the old ID. It rejects a replacement during an active wait. The caller can delete the detached old object with `EventFlags.delete`; the C adapter rejects deletion of the currently bound object. The normal blinking loop does not rebind.

The joystick is active low, so its falling edge signals a press. `waitCenterPress` consumes the RTX event in Lean; the application accepts at most one change per 200 ms to suppress contact bounce. GPIO multiplexing and ownership still depend on board configuration and other firmware: the Alif device documentation says pins can have only one assigned function and LPGPIO access across bus masters needs serialization (ASRM0002 v1.8 p.53; ADTS0013 v1.2 pp.52–53). These Lean capabilities cannot rule out a second core or unrelated C code changing the same hardware.

## Build and run

1. Power the DevKit through PRG USB, use the existing M55_HP application/ATOC provisioning, and connect the ULINKplus probe.
2. In CMSIS View select `DevKit-E8@blinky`, then **Build** and **Load & Debug**. The target set specifies `ULINKplus@pyOCD`.
3. Set SW4 to UART4 with power off, then open the board's UART at 115200 8N1. On the tested setup it enumerated as COM5.
4. Resume from the initial `main` breakpoint. The UART prints `Lean Blinky: RGB0 and RGB1, slow pattern (1000 ms)` and the joystick instruction. Press the joystick center firmly for about half a second and release it; the UART reports the new pattern.

The board startup, MRAM linker layout, UART4 retargeting, and RTX runtime are shared with the existing E8 target sets. The native CMake project mirrors the [board layer](../board/DevKit-E8/Board.clayer.yml); CMSIS-Toolbox 2.15 does not attach `.clayer.yml` components directly to a native `cmake:` project.

## Verification

On the DevKit-E8 A1 with ULINKplus, the refactored standalone project built, loaded, and printed the Lean startup instructions. The debugger observed the Lean worker waiting on an RTX event flag. A joystick press entered `button_irq` with pin 124 and falling-edge event 2; after the callback posted the flag and execution resumed, Lean changed the blink pattern. With no breakpoint active, another press changed the LEDs and UART reported `Blinky: fast pattern (100 ms)`. The final rebuilt image also changed from slow to fast on a firm press, confirmed by the board operator and UART. One earlier press after loading that image did not register; button response remains intermittent on this board. The separate `DevKit-E8@minimal` target was not changed by this refactor.

The event-binding correction was tested in a temporary startup variant: Lean created a second event object, rebound the ISR to it, deleted the detached first object, then started the normal loop. The debugger confirmed that the ISR slot held the new ID; setting LPGPIO IRQ4 pending made the ISR post to it and Lean reported `Blinky: fast pattern (100 ms)`. The temporary swap was removed from the delivered Blinky application. The final image was rebuilt and loaded, printed its startup message, and also changed to fast when LPGPIO IRQ4 was set pending through the debugger.

After the typed-error change, `DevKit-E8@blinky` built and loaded successfully. The board printed the normal Lean startup instructions, and the target was left running. The joystick was not pressed during this verification.

The compile-time gate and GPIO refactor also built and loaded on the DevKit-E8. After one reported missed press, live debugging of this image found LPGPIO IRQ4 enabled in the NVIC, center-pin interrupt generation enabled and unmasked, and the Lean worker waiting on the event object bound to the ISR. A physical press reached `button_irq` with pin 124 and falling-edge event 2; `osEventFlagsSet` returned success. With the breakpoint removed, subsequent presses produced UART reports for fast, slow, then fast. The operator confirmed the last change was visible, and the debugger observed the worker waiting with a 100 ms timeout. The cause of the earlier missed press was not captured. The target was left running.
