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

[Blinky/GPIO.lean](../examples/blinky/Blinky/GPIO.lean) adds the LED roles and typed button setup sequence above the reusable [Board.GPIO](../api/Board/GPIO.lean) API. [Blinky/NVIC.lean](../examples/blinky/Blinky/NVIC.lean) specializes the shared [Board.NVIC](../api/Board/NVIC.lean) gate protocol to the joystick IRQ. The shared protocol indexes actions by the IRQ number and CPU/NVIC gate states. [Blinky/CMSISRTOS.lean](../examples/blinky/Blinky/CMSISRTOS.lean) uses the shared event-flags API, converts milliseconds to kernel ticks, and adds a button-event binding action that requires both gates closed. Its private-constructor `EventFlagsId` is a Lean value; Lean can replace the binding through `Board.replaceEvents`.

[Board/Error.lean](../api/Board/Error.lean), re-exported by Blinky, defines `HalM α = ExceptT HalError IO α`. GPIO and CMSIS-RTOS calls return `.gpio operation status` or `.rtos operation status`, preserving the raw numeric status. Resource exhaustion, dynamic state conflicts, and an unbound event sink have separate error constructors. The GPIO, NVIC, RTOS, board, and blink functions propagate these values through Lean `do` notation; callers can inspect them with `match ← action.run with | .ok value => ... | .error error => ...`. An event wait timeout is an ordinary `false` result. Only the exported application's `IO` boundary formats an unhandled `HalError` as an `IO.userError` for the C startup code.

[main.c](../examples/blinky/main.c) handles board UART setup, RTX kernel startup, Lean runtime/module initialization, and task-manager startup. The shared [Board API bridges](board-api.md) forward individual CMSIS GPIO, NVIC, CPU, and RTOS calls. [platform.c](../examples/blinky/platform.c) supplies board pin/IRQ identities, setup reservations, and the native event-slot adapter. Its button IRQ callback only sets an RTX event flag; it never calls the Lean runtime from interrupt context. Lean waits for that event with a timeout, so a press can change the pattern during either the on or off interval.

### Enforced GPIO operations

The board API admits only `Color.red`, `Color.green`, `Color.blue` and
`Speed.slow` or `Speed.fast`. LED and button roles remain distinct, and each
LED output is indexed by its exact pin. `Board.prepare` chooses this button flow:

```text
create event flags → disable LPGPIO IRQ4 → mask CPU IRQs
→ Driver_GPIO.Setup with retained native callback object
→ close GPIO source and LPGPIO IRQ4 before Setup returns
→ pull-up → input direction → falling-edge selection
→ attach source → EOI → clear NVIC pending state → set priority
→ unmask and enable GPIO source → restore CPU mask → enable LPGPIO IRQ4
```

Every step uses public elementary checked operations from
`Board.GPIO.LowLevel`, `Board.NVIC.LowLevel` and `Board.AlifGPIO.LowLevel`.
Applications can compose the same primitives themselves. Pull-up may also be
set after input direction; the selected driver does not require their displayed
order. Callback setup, trigger selection and arming have distinct typed
preconditions. The low-level functions enforce those preconditions without
choosing the complete board flow.

The pack's GPIO Setup briefly enables the source and NVIC line internally.
Its trusted callback/source adapter closes both under PRIMASK, including on
failure. Gated actions require the matching IRQ and CPU/NVIC scopes when
executed; there is no public unrestricted lift that can bypass those gates.
PRIMASK is restored on both HAL errors and IO exceptions. Initialization enables
the NVIC line only after success.

Private constructors and indices enforce resource roles and state at compile
time. Hidden runtime leases reject duplicate setup, stale copies after a
transition, conflicting operations, and use after deletion. Failed mutations
reserve the uncertain resource until reset. The registry is shared with the
reusable API, rather than relying on a private demo setup path.

The native ISR slot holds the event ID and its retention token. Rebinding under
closed CPU/NVIC gates retains the new object before publishing it and releases
the detached object's retention afterward. The checked event-flags API rejects
deletion while an ISR retention or active wait exists. `Board.replaceEvents`
also rejects replacement during its owner's active wait and returns the old
object for deletion. Raw event-ID recovery and native slot access are internal.

The joystick is active low, so a falling edge signals a press. Lean accepts at
most one change per 200 ms. The trusted board adapter establishes native
pointer, pin, port, IRQ and callback mappings. Other cores and native firmware
must honor ownership; these checks cannot prevent unrelated register writes.
See [the shared API guide](board-api.md) for the exact scope and lifetime rules.

## Build and run

1. Power the DevKit through PRG USB, use the existing M55_HP application/ATOC provisioning, and connect the ULINKplus probe.
2. In CMSIS View select `DevKit-E8@blinky`, then **Build** and **Load & Debug**. The target set specifies `ULINKplus@pyOCD`.
3. Set SW4 to UART4 with power off, then open the board's UART at 115200 8N1. On the tested setup it enumerated as COM5.
4. Resume from the initial `main` breakpoint. The UART prints `Lean Blinky: RGB0 and RGB1, slow pattern (1000 ms)` and the joystick instruction. Press the joystick center firmly for about half a second and release it; the UART reports the new pattern.

The board startup, MRAM linker layout, UART4 retargeting, and RTX runtime are shared with the existing E8 target sets. The [Blinky cproject](../examples/blinky/LeanBlinky.cproject.yml) includes the [board layer](../board/DevKit-E8/Board.clayer.yml) and shared Lean CMSIS layer, adds the GPIO component, and compiles `main.c`, `platform.c`, and the selected per-component bridges from `api/c/`. Its dependent `LeanBlinkyLib` CMake project builds only the Lean archive.

## Verification

For the shared low-level invariant changes on 2026-11-02, the Lean checks
passed 38 compilation cases and 84 native signature comparisons. Eight host
runtime test groups and the native lease registry tests passed. DevKit-E8 Blinky
built, loaded and printed the
normal startup instructions after GPIO and IRQ setup completed; the target
was left running. No physical joystick press or event-object rebinding was
performed for this version. The records below describe earlier iterations.

On the DevKit-E8 A1 with ULINKplus, the refactored standalone project built, loaded, and printed the Lean startup instructions. The debugger observed the Lean worker waiting on an RTX event flag. A joystick press entered `button_irq` with pin 124 and falling-edge event 2; after the callback posted the flag and execution resumed, Lean changed the blink pattern. With no breakpoint active, another press changed the LEDs and UART reported `Blinky: fast pattern (100 ms)`. The final rebuilt image also changed from slow to fast on a firm press, confirmed by the board operator and UART. One earlier press after loading that image did not register; button response remains intermittent on this board. The separate `DevKit-E8@minimal` target was not changed by this refactor.

The event-binding correction was tested in a temporary startup variant: Lean created a second event object, rebound the ISR to it, deleted the detached first object, then started the normal loop. The debugger confirmed that the ISR slot held the new ID; setting LPGPIO IRQ4 pending made the ISR post to it and Lean reported `Blinky: fast pattern (100 ms)`. The temporary swap was removed from the delivered Blinky application. The final image was rebuilt and loaded, printed its startup message, and also changed to fast when LPGPIO IRQ4 was set pending through the debugger.

After the typed-error change, `DevKit-E8@blinky` built and loaded successfully. The board printed the normal Lean startup instructions, and the target was left running. The joystick was not pressed during this verification.

The compile-time gate and GPIO refactor also built and loaded on the DevKit-E8. After one reported missed press, live debugging of this image found LPGPIO IRQ4 enabled in the NVIC, center-pin interrupt generation enabled and unmasked, and the Lean worker waiting on the event object bound to the ISR. A physical press reached `button_irq` with pin 124 and falling-edge event 2; `osEventFlagsSet` returned success. With the breakpoint removed, subsequent presses produced UART reports for fast, slow, then fast. The operator confirmed the last change was visible, and the debugger observed the worker waiting with a 100 ms timeout. The cause of the earlier missed press was not captured. The target was left running.
