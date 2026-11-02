#include "bridge.h"
#include "gpio.h"
lean_object *lean_board_alifgpio_getEnabledInterrupts(size_t port) {
    return lean_io_result_mk_ok(lean_box(gpio_get_enabled_interrupt((GPIO_Type *)port)));
}
lean_object *lean_board_alifgpio_disableInterrupt(size_t port, uint8_t pin) {
    gpio_disable_interrupt((GPIO_Type *)port, (uint8_t)pin); return board_ok_unit();
}

lean_object *lean_board_alifgpio_enableInterrupt(size_t port, uint8_t pin) {
    gpio_enable_interrupt((GPIO_Type *)port, (uint8_t)pin); return board_ok_unit();
}

lean_object *lean_board_alifgpio_maskInterrupt(size_t port, uint8_t pin) {
    gpio_mask_interrupt((GPIO_Type *)port, (uint8_t)pin); return board_ok_unit();
}

lean_object *lean_board_alifgpio_unmaskInterrupt(size_t port, uint8_t pin) {
    gpio_unmask_interrupt((GPIO_Type *)port, (uint8_t)pin); return board_ok_unit();
}

lean_object *lean_board_alifgpio_interruptEoi(size_t port, uint8_t pin) {
    gpio_interrupt_eoi((GPIO_Type *)port, (uint8_t)pin); return board_ok_unit();
}

