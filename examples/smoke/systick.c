#include <stdint.h>
#include <stdio.h>
#include "cmsis_os2.h"
#include "cmsis_device.h"
extern uint32_t lean_embedded_systick_reload(uint32_t period);

/* See arm/ddi0553-latest, B.z, pp.290 and 1859:
 * zero RELOAD stops counting; SYST_RVR[31:24] are reserved.
 * Proofs cover the Lean value. This boundary and the MMIO access are trusted C. */
int systick_contract_test(void) {
    static const struct { uint32_t period, reload; } cases[] = {
        {0, 0}, {1, 0}, {2, 1}, {1000, 999},
        {16777216, 16777215}, {16777217, 0}, {UINT32_MAX, 0}
    };
    uint32_t results[sizeof(cases)/sizeof(cases[0])];
    for (unsigned i=0; i<sizeof(cases)/sizeof(cases[0]); ++i) {
        results[i] = lean_embedded_systick_reload(cases[i].period);
        if (results[i] != cases[i].reload) return 1;
    }
    // RTX owns SysTick. Freeze it only for these bounded register checks after
    // workers have stopped, then restore the configuration and resume RTX.
    int32_t lock = osKernelLock();
    if (lock < 0) return 2;
    uint32_t primask = __get_PRIMASK();
    __disable_irq();
    uint32_t ctrl = SysTick->CTRL, load = SysTick->LOAD;
    SysTick->CTRL = 0;
    int failed = 0;
    for (unsigned i=0; i<sizeof(cases)/sizeof(cases[0]); ++i) {
        uint32_t before = SysTick->LOAD;
        if (results[i]) SysTick->LOAD = results[i];
        uint32_t after = SysTick->LOAD;
        if (after != (results[i] ? results[i] : before)) failed = 3;
    }
    SysTick->LOAD = load;
    SysTick->CTRL = ctrl;
    __set_PRIMASK(primask);
    if (osKernelRestoreLock(lock) < 0) return 4;
    if (!failed) puts("PASS: proved SysTick contract + register readback (7 boundaries)");
    return failed;
}
