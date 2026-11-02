#include "bridge.h"
#include "Driver_GPIO.h"
_Static_assert(ARM_GPIO_INPUT == 0 && ARM_GPIO_OUTPUT == 1 &&
               ARM_GPIO_PUSH_PULL == 0 && ARM_GPIO_OPEN_DRAIN == 1 &&
               ARM_GPIO_PULL_NONE == 0 && ARM_GPIO_PULL_UP == 1 && ARM_GPIO_PULL_DOWN == 2 &&
               ARM_GPIO_TRIGGER_NONE == 0 && ARM_GPIO_TRIGGER_RISING_EDGE == 1 &&
               ARM_GPIO_TRIGGER_FALLING_EDGE == 2 && ARM_GPIO_TRIGGER_EITHER_EDGE == 3 &&
               ARM_GPIO_EVENT_RISING_EDGE == 1 && ARM_GPIO_EVENT_FALLING_EDGE == 2 &&
               ARM_GPIO_EVENT_EITHER_EDGE == 4, "Update Lean GPIO constants for this CMSIS API");
lean_object *lean_board_gpio_setup(size_t driver, uint32_t pin, size_t callback) {
    return board_ok_u32((uint32_t)(((ARM_DRIVER_GPIO *)driver)->Setup(pin, (ARM_GPIO_SignalEvent_t)callback)));
}

lean_object *lean_board_gpio_setDirection(size_t driver, uint32_t pin, uint32_t direction) {
    return board_ok_u32((uint32_t)(((ARM_DRIVER_GPIO *)driver)->SetDirection(pin, (ARM_GPIO_DIRECTION)direction)));
}

lean_object *lean_board_gpio_setOutputMode(size_t driver, uint32_t pin, uint32_t mode) {
    return board_ok_u32((uint32_t)(((ARM_DRIVER_GPIO *)driver)->SetOutputMode(pin, (ARM_GPIO_OUTPUT_MODE)mode)));
}

lean_object *lean_board_gpio_setPullResistor(size_t driver, uint32_t pin, uint32_t resistor) {
    return board_ok_u32((uint32_t)(((ARM_DRIVER_GPIO *)driver)->SetPullResistor(pin, (ARM_GPIO_PULL_RESISTOR)resistor)));
}

lean_object *lean_board_gpio_setEventTrigger(size_t driver, uint32_t pin, uint32_t trigger) {
    return board_ok_u32((uint32_t)(((ARM_DRIVER_GPIO *)driver)->SetEventTrigger(pin, (ARM_GPIO_EVENT_TRIGGER)trigger)));
}

lean_object *lean_board_gpio_setOutput(size_t driver, uint32_t pin, uint32_t value) {
    ((ARM_DRIVER_GPIO *)driver)->SetOutput(pin, value); return board_ok_unit();
}

lean_object *lean_board_gpio_getInput(size_t driver, uint32_t pin) {
    return board_ok_u32((uint32_t)(((ARM_DRIVER_GPIO *)driver)->GetInput(pin)));
}

