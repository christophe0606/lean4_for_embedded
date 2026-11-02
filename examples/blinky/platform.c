#include "bridge.h"
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
static uint32_t button_retention;

/* Interrupt context only posts an event. Lean owns the event ID and setup flow. */
static void button_irq(ARM_GPIO_Pin_t pin, uint32_t event) {
    if (button_events && pin == BUTTON_PIN && (event & ARM_GPIO_EVENT_FALLING_EDGE))
        (void)osEventFlagsSet(button_events, BUTTON_FLAG);
}


size_t lean_blinky_gpio_driver(lean_object *unit) { (void)unit; return (size_t)&Driver_GPIO; }
uint32_t lean_blinky_pin(uint32_t selector) {
    return selector < sizeof(pins)/sizeof(pins[0]) ? pins[selector] : UINT32_MAX;
}
uint32_t lean_blinky_button_irq(lean_object *unit) { (void)unit; return LPGPIO_IRQ4_IRQn; }
size_t lean_blinky_button_port(lean_object *unit) { (void)unit; return LPGPIO_BASE; }
uint32_t lean_blinky_button_pin(lean_object *unit) { (void)unit; return BOARD_JOY_SW_CENTER_GPIO_PIN; }
size_t lean_blinky_callback(lean_object *unit) { (void)unit; return (size_t)button_irq; }

lean_object *lean_blinky_claim_setup(uint32_t selector) {
    uint32_t previous = __get_PRIMASK();
    __disable_irq();
    uint32_t status = 0;
    if (selector > BUTTON_SELECTOR || (setup_mask & (1U << selector)) ||
        (selector == BUTTON_SELECTOR &&
         (!(previous & 1U) || NVIC_GetEnableIRQ(LPGPIO_IRQ4_IRQn) ||
          osKernelGetState() != osKernelRunning))) {
        status = (uint32_t)ARM_DRIVER_ERROR_PARAMETER;
    } else {
        /* Reserve before calling the driver. A failed setup cannot be replayed
         * against partially configured hardware without a board reset. */
        setup_mask |= 1U << selector;
    }
    __set_PRIMASK(previous);
    return board_ok_u32(status);
}
lean_object *lean_blinky_bind_events(size_t id, uint32_t retention) {
    if (!id || !retention || !(setup_mask & (1U << BUTTON_SELECTOR)) ||
        !(__get_PRIMASK() & 1U) || NVIC_GetEnableIRQ(LPGPIO_IRQ4_IRQn))
        return board_ok_u32((uint32_t)ARM_DRIVER_ERROR_PARAMETER);
    button_events = (osEventFlagsId_t)id;
    button_retention = retention;
    return board_ok_u32(0);
}
lean_object *lean_blinky_current_events(void) {
    return board_ok_usize((size_t)button_events);
}
lean_object *lean_blinky_current_retention(void) {
    return board_ok_u32(button_retention);
}
