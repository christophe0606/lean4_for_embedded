#include <stdint.h>
#include <stdio.h>
#include "cmsis_os2.h"
#include "cmsis_device.h"

extern uint32_t lean_embedded_timer_sequence(uint32_t period, uint32_t a,
                                            uint32_t b, uint32_t c, uint32_t d);

enum { STOP, CONFIGURE, CLEAR, ENABLE };
static const uint32_t control_mask = SysTick_CTRL_ENABLE_Msk |
    SysTick_CTRL_TICKINT_Msk | SysTick_CTRL_CLKSOURCE_Msk;

/* Trusted executor: snapshot caller-owned commands, validate the complete plan,
 * then execute that same snapshot. Caller must own the timer and exclude other
 * writers throughout. Never execute a valid prefix of an invalid plan. */
static int execute_plan(uint32_t period, const uint32_t commands[4]) {
    uint32_t a = commands[0], b = commands[1], c = commands[2], d = commands[3];
    uint32_t reload = lean_embedded_timer_sequence(period, a, b, c, d);
    if (!reload) return 0;
    const uint32_t snapshot[] = {a, b, c, d};
    for (unsigned i = 0; i < 4; ++i) {
        switch (snapshot[i]) {
        case STOP: SysTick->CTRL = 0; break;
        case CONFIGURE: SysTick->LOAD = reload; break;
        case CLEAR: SysTick->VAL = 0; break;
        case ENABLE:
            /* No tick interrupt: this is a bounded driver integration test. */
            SysTick->CTRL = SysTick_CTRL_CLKSOURCE_Msk | SysTick_CTRL_ENABLE_Msk;
            break;
        default: return -1; /* Unreachable after the Lean validator succeeds. */
        }
        __DSB();
        if (snapshot[i] == STOP && (SysTick->CTRL & SysTick_CTRL_ENABLE_Msk)) return -1;
        if (snapshot[i] == CONFIGURE && SysTick->LOAD != reload) return -1;
        if (snapshot[i] == CLEAR && SysTick->VAL != 0) return -1;
    }
    return SysTick->LOAD == reload &&
        (SysTick->CTRL & control_mask) == (SysTick_CTRL_CLKSOURCE_Msk | SysTick_CTRL_ENABLE_Msk)
        ? 1 : -1;
}

int timer_sequence_test(void) {
    /* Exhaust all four-command plans over the four known commands. Only
     * STOP, CONFIGURE, CLEAR, ENABLE ends in the running state. */
    for (unsigned encoded = 0; encoded < 256; ++encoded) {
        uint32_t result = lean_embedded_timer_sequence(16777216, encoded & 3,
            (encoded >> 2) & 3, (encoded >> 4) & 3, (encoded >> 6) & 3);
        if (result != (encoded == 228 ? 16777215u : 0u)) return 1;
    }
    const uint32_t valid[] = {STOP, CONFIGURE, CLEAR, ENABLE};
    static const uint32_t invalid_codes[] = {4, 255, UINT32_MAX};
    for (unsigned position = 0; position < 4; ++position) {
        for (unsigned code = 0; code < 3; ++code) {
            uint32_t commands[] = {STOP, CONFIGURE, CLEAR, ENABLE};
            commands[position] = invalid_codes[code];
            if (lean_embedded_timer_sequence(1000, commands[0], commands[1],
                                             commands[2], commands[3])) return 2;
        }
    }
    static const struct { uint32_t period, reload; } bounds[] = {
        {0, 0}, {1, 0}, {2, 1}, {1000, 999}, {16777216, 16777215},
        {16777217, 0}, {UINT32_MAX, 0}
    };
    for (unsigned i = 0; i < sizeof(bounds) / sizeof(bounds[0]); ++i) {
        if (lean_embedded_timer_sequence(bounds[i].period, STOP, CONFIGURE, CLEAR, ENABLE)
            != bounds[i].reload) return 3;
    }

    /* RTX owns this timer: temporarily exclude it and interrupts, as in the
     * original reload test. Restoring VAL restarts the tick phase; this is a
     * test harness, not a production driver sharing the RTOS tick source.
     * Arm DDI0553 B.z pp.290,1857: VAL is word-write-to-clear. */
    int32_t lock = osKernelLock();
    if (lock < 0) return 4;
    uint32_t primask = __get_PRIMASK();
    __disable_irq();
    uint32_t saved_ctrl = SysTick->CTRL, saved_load = SysTick->LOAD;
    int failed = 0;
    /* Run the valid plan first. Rejected plans then face a running timer. */
    if (execute_plan(16777216, valid) != 1) failed = 5;
    uint32_t expected_ctrl = SysTick->CTRL & control_mask;
    uint32_t expected_load = SysTick->LOAD;
    for (unsigned encoded = 0; encoded < 256; ++encoded) {
        if (encoded == 228) continue;
        uint32_t commands[] = {encoded & 3, (encoded >> 2) & 3,
                              (encoded >> 4) & 3, (encoded >> 6) & 3};
        if (execute_plan(16777216, commands) != 0 || SysTick->LOAD != expected_load ||
            (SysTick->CTRL & control_mask) != expected_ctrl) failed = 6;
    }
    uint32_t unknown[] = {STOP, CONFIGURE, CLEAR, UINT32_MAX};
    if (execute_plan(1000, unknown) != 0 || execute_plan(1, valid) != 0 ||
        SysTick->LOAD != expected_load ||
        (SysTick->CTRL & control_mask) != expected_ctrl) failed = 7;
    SysTick->CTRL = 0;
    SysTick->LOAD = saved_load;
    SysTick->VAL = 0;
    SysTick->CTRL = saved_ctrl;
    __DSB();
    __set_PRIMASK(primask);
    if (osKernelRestoreLock(lock) < 0) return 8;
    if (!failed) puts("PASS: proved timer initialization sequence + MMIO (256 plans)");
    return failed;
}
