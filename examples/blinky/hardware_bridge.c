#include <lean/lean.h>
#include <stdint.h>
#include "cmsis_os2.h"
#include "Driver_GPIO.h"
#include "board_defs.h"
#include "gpio.h"
#include "soc.h"

extern ARM_DRIVER_GPIO Driver_GPIO;

#define GPIO_PIN(port, number) (((port) * 8U) + (number))
#define BUTTON_PIN GPIO_PIN(BOARD_JOY_SW_CENTER_GPIO_PORT, BOARD_JOY_SW_CENTER_GPIO_PIN)
#define BUTTON_SELECTOR 6U
#define BUTTON_FLAG 1U

_Static_assert(sizeof(osEventFlagsId_t) == sizeof(uint32_t), "Event IDs must fit a Lean UInt32");
_Static_assert(BOARD_JOY_SW_CENTER_GPIO_PORT == 15 &&
               BOARD_JOY_SW_CENTER_GPIO_PIN == 4,
               "Update the joystick IRQ mapping when the board pin changes");

/* Pin identities are data from the board pack; setup policy lives in Lean. */
static const ARM_GPIO_Pin_t pins[] = {
    GPIO_PIN(BOARD_LEDRGB0_R_GPIO_PORT, BOARD_LEDRGB0_R_GPIO_PIN),
    GPIO_PIN(BOARD_LEDRGB0_G_GPIO_PORT, BOARD_LEDRGB0_G_GPIO_PIN),
    GPIO_PIN(BOARD_LEDRGB0_B_GPIO_PORT, BOARD_LEDRGB0_B_GPIO_PIN),
    GPIO_PIN(BOARD_LEDRGB1_R_GPIO_PORT, BOARD_LEDRGB1_R_GPIO_PIN),
    GPIO_PIN(BOARD_LEDRGB1_G_GPIO_PORT, BOARD_LEDRGB1_G_GPIO_PIN),
    GPIO_PIN(BOARD_LEDRGB1_B_GPIO_PORT, BOARD_LEDRGB1_B_GPIO_PIN),
    BUTTON_PIN
};
static uint32_t setup_mask;
/* The ISR and Lean's wait wrapper both read this one binding. */
static volatile osEventFlagsId_t button_events;

/* Interrupt context only posts an event. Lean owns the event ID and setup flow. */
static void button_irq(ARM_GPIO_Pin_t pin, uint32_t event) {
    if (button_events && pin == BUTTON_PIN && (event & ARM_GPIO_EVENT_FALLING_EDGE))
        (void)osEventFlagsSet(button_events, BUTTON_FLAG);
}

static lean_object *ok_u32(uint32_t value) {
    return lean_io_result_mk_ok(lean_box_uint32(value));
}

static uint32_t invalid_argument(void) {
    return (uint32_t)ARM_DRIVER_ERROR_PARAMETER;
}

lean_object *lean_hal_gpio_driver_setup(uint32_t selector, uint32_t event_id) {
    if (selector >= sizeof(pins) / sizeof(pins[0])) return ok_u32(invalid_argument());
    if (setup_mask & (1U << selector)) return ok_u32(invalid_argument());
    if (selector == BUTTON_SELECTOR) {
        /* The pack's Setup enables both IRQ gates. The Lean mask capability
         * must correspond to a real CPU mask and an already disabled line. */
        if (!event_id || !(__get_PRIMASK() & 1U) ||
            NVIC_GetEnableIRQ(LPGPIO_IRQ4_IRQn) != 0U ||
            osKernelGetState() != osKernelRunning)
            return ok_u32(invalid_argument());
        button_events = (osEventFlagsId_t)(uintptr_t)event_id;
        int32_t status = Driver_GPIO.Setup(pins[selector], button_irq);
        if (status == ARM_DRIVER_OK) setup_mask |= 1U << selector;
        return ok_u32((uint32_t)status);
    }
    if (event_id) return ok_u32(invalid_argument());
    int32_t status = Driver_GPIO.Setup(pins[selector], NULL);
    if (status == ARM_DRIVER_OK) setup_mask |= 1U << selector;
    return ok_u32((uint32_t)status);
}

lean_object *lean_hal_gpio_set_direction(uint32_t selector, uint32_t output) {
    if (selector >= sizeof(pins) / sizeof(pins[0]) || output > 1U)
        return ok_u32(invalid_argument());
    return ok_u32((uint32_t)Driver_GPIO.SetDirection(
        pins[selector], output ? ARM_GPIO_OUTPUT : ARM_GPIO_INPUT));
}

lean_object *lean_hal_gpio_set_pull_up(uint32_t selector) {
    if (selector != BUTTON_SELECTOR) return ok_u32(invalid_argument());
    return ok_u32((uint32_t)Driver_GPIO.SetPullResistor(pins[selector], ARM_GPIO_PULL_UP));
}

lean_object *lean_hal_gpio_set_falling(uint32_t selector) {
    if (selector != BUTTON_SELECTOR) return ok_u32(invalid_argument());
    return ok_u32((uint32_t)Driver_GPIO.SetEventTrigger(
        pins[selector], ARM_GPIO_TRIGGER_FALLING_EDGE));
}

lean_object *lean_hal_gpio_set_output(uint32_t selector, uint8_t on) {
    if (selector >= BUTTON_SELECTOR || on > 1U) return ok_u32(invalid_argument());
    Driver_GPIO.SetOutput(pins[selector], on);
    return ok_u32(0U);
}

lean_object *lean_hal_gpio_disable_interrupt(uint32_t selector) {
    if (selector != BUTTON_SELECTOR) return ok_u32(invalid_argument());
    gpio_disable_interrupt((GPIO_Type *)LPGPIO_BASE, BOARD_JOY_SW_CENTER_GPIO_PIN);
    return ok_u32(0U);
}

lean_object *lean_hal_gpio_interrupt_eoi(uint32_t selector) {
    if (selector != BUTTON_SELECTOR) return ok_u32(invalid_argument());
    gpio_interrupt_eoi((GPIO_Type *)LPGPIO_BASE, BOARD_JOY_SW_CENTER_GPIO_PIN);
    return ok_u32(0U);
}

lean_object *lean_hal_gpio_unmask_interrupt(uint32_t selector) {
    if (selector != BUTTON_SELECTOR) return ok_u32(invalid_argument());
    gpio_unmask_interrupt((GPIO_Type *)LPGPIO_BASE, BOARD_JOY_SW_CENTER_GPIO_PIN);
    return ok_u32(0U);
}

lean_object *lean_hal_gpio_enable_interrupt(uint32_t selector) {
    if (selector != BUTTON_SELECTOR) return ok_u32(invalid_argument());
    gpio_enable_interrupt((GPIO_Type *)LPGPIO_BASE, BOARD_JOY_SW_CENTER_GPIO_PIN);
    return ok_u32(0U);
}

lean_object *lean_hal_nvic_mask_all(void) {
    uint32_t previous = __get_PRIMASK();
    __disable_irq();
    return ok_u32(previous);
}

lean_object *lean_hal_nvic_restore_all(uint32_t previous) {
    __set_PRIMASK(previous);
    return ok_u32(0U);
}

lean_object *lean_hal_nvic_disable_irq(void) {
    NVIC_DisableIRQ(LPGPIO_IRQ4_IRQn);
    return ok_u32(0U);
}

lean_object *lean_hal_nvic_enable_irq(void) {
    NVIC_EnableIRQ(LPGPIO_IRQ4_IRQn);
    return ok_u32(0U);
}

lean_object *lean_hal_nvic_clear_pending_irq(void) {
    NVIC_ClearPendingIRQ(LPGPIO_IRQ4_IRQn);
    return ok_u32(0U);
}

lean_object *lean_hal_nvic_set_priority(uint32_t priority) {
    NVIC_SetPriority(LPGPIO_IRQ4_IRQn, priority);
    return ok_u32(0U);
}

lean_object *lean_hal_rtos_event_flags_new(void) {
    osEventFlagsId_t id = osEventFlagsNew(NULL);
    return ok_u32((uint32_t)(uintptr_t)id);
}

lean_object *lean_hal_rtos_event_flags_set(uint32_t event_id, uint32_t flags) {
    if (!event_id) return ok_u32(osFlagsErrorParameter);
    return ok_u32(osEventFlagsSet((osEventFlagsId_t)(uintptr_t)event_id, flags));
}

lean_object *lean_hal_rtos_event_flags_wait(uint32_t event_id, uint32_t flags,
                                           uint32_t timeout_ms) {
    if (!event_id) return ok_u32(osFlagsErrorParameter);
    return ok_u32(osEventFlagsWait((osEventFlagsId_t)(uintptr_t)event_id,
                                   flags, osFlagsWaitAny, timeout_ms));
}

lean_object *lean_hal_rtos_event_flags_delete(uint32_t event_id) {
    osEventFlagsId_t id = (osEventFlagsId_t)(uintptr_t)event_id;
    if (!id || id == button_events) return ok_u32((uint32_t)osErrorParameter);
    return ok_u32((uint32_t)osEventFlagsDelete(id));
}

lean_object *lean_hal_rtos_button_event_sink_get(void) {
    return ok_u32((uint32_t)(uintptr_t)button_events);
}

lean_object *lean_hal_rtos_button_event_sink_set(uint32_t event_id) {
    /* Rebinding is only legal after callback installation, while this IRQ is
     * disabled at both the CPU and NVIC. The Lean API supplies both proofs. */
    if (!event_id || !(setup_mask & (1U << BUTTON_SELECTOR)) ||
        !(__get_PRIMASK() & 1U) || NVIC_GetEnableIRQ(LPGPIO_IRQ4_IRQn) != 0U)
        return ok_u32(invalid_argument());
    button_events = (osEventFlagsId_t)(uintptr_t)event_id;
    return ok_u32(0U);
}
