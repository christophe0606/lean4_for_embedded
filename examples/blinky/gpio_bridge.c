#include <lean/lean.h>
#include <stdint.h>
#include "cmsis_os2.h"
#include "Driver_GPIO.h"
#include "board_defs.h"
#include "gpio.h"
#include "soc.h"

extern ARM_DRIVER_GPIO Driver_GPIO;

#define BUTTON_PIN ((BOARD_JOY_SW_CENTER_GPIO_PORT * 8U) + BOARD_JOY_SW_CENTER_GPIO_PIN)
#define BUTTON_FLAG 1U

static osEventFlagsId_t button_events;

int blinky_events_init(void) {
    button_events = osEventFlagsNew(NULL);
    return button_events ? 0 : -1;
}

/* The IRQ does no Lean work. It only wakes the Lean task through RTX. */
static void button_irq(ARM_GPIO_Pin_t pin, uint32_t event) {
    if (pin == BUTTON_PIN && (event & ARM_GPIO_EVENT_FALLING_EDGE))
        (void)osEventFlagsSet(button_events, BUTTON_FLAG);
}

static lean_object *ok_u32(uint32_t value) {
    return lean_io_result_mk_ok(lean_box_uint32(value));
}

lean_object *lean_blinky_gpio_setup(uint32_t pin) {
    return ok_u32((uint32_t)Driver_GPIO.Setup(pin, NULL));
}

lean_object *lean_blinky_gpio_direction(uint32_t pin, uint8_t output) {
    return ok_u32((uint32_t)Driver_GPIO.SetDirection(pin, output ? ARM_GPIO_OUTPUT : ARM_GPIO_INPUT));
}

/* GPIO Setup enables the NVIC line before Lean can make another call. An
 * interrupt during that gap can flood RTX's ISR queue. Keep the
 * button's setup, pull-up, edge selection, and pending-IRQ clear atomic. */
lean_object *lean_blinky_button_setup(uint32_t pin) {
    if (pin != BUTTON_PIN) return ok_u32((uint32_t)ARM_GPIO_ERROR_PIN);
    uint32_t primask = __get_PRIMASK();
    __disable_irq();
    int32_t status = Driver_GPIO.Setup(pin, button_irq);
    if (status == ARM_DRIVER_OK)
        status = Driver_GPIO.SetPullResistor(pin, ARM_GPIO_PULL_UP);
    if (status == ARM_DRIVER_OK)
        status = Driver_GPIO.SetDirection(pin, ARM_GPIO_INPUT);
    if (status == ARM_DRIVER_OK)
        status = Driver_GPIO.SetEventTrigger(pin, ARM_GPIO_TRIGGER_FALLING_EDGE);
    if (status == ARM_DRIVER_OK) {
        gpio_interrupt_eoi((GPIO_Type *)LPGPIO_BASE, BOARD_JOY_SW_CENTER_GPIO_PIN);
        NVIC_ClearPendingIRQ(LPGPIO_IRQ4_IRQn);
        NVIC_SetPriority(LPGPIO_IRQ4_IRQn, 5U);
    } else {
        gpio_disable_interrupt((GPIO_Type *)LPGPIO_BASE, BOARD_JOY_SW_CENTER_GPIO_PIN);
        NVIC_DisableIRQ(LPGPIO_IRQ4_IRQn);
    }
    __set_PRIMASK(primask);
    return ok_u32((uint32_t)status);
}

lean_object *lean_blinky_gpio_write(uint32_t pin, uint32_t level) {
    Driver_GPIO.SetOutput(pin, level);
    return lean_io_result_mk_ok(lean_box(0));
}

lean_object *lean_blinky_gpio_read(uint32_t pin) {
    return ok_u32(Driver_GPIO.GetInput(pin));
}

lean_object *lean_blinky_button_event(uint32_t timeout_ms) {
    uint32_t result = osEventFlagsWait(button_events, BUTTON_FLAG, osFlagsWaitAny, timeout_ms);
    if (result == osFlagsErrorTimeout) return ok_u32(0U);
    if (result & osFlagsError) return ok_u32(2U);
    return ok_u32(1U);
}
