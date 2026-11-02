#include "bridge.h"
#include "cmsis_device.h"
lean_object *lean_board_systick_config(uint32_t ticks) {
    return board_ok_u32((uint32_t)(SysTick_Config(ticks)));
}

lean_object *lean_board_systick_getCTRL(void) {
    return board_ok_u32((uint32_t)(SysTick->CTRL));
}

lean_object *lean_board_systick_getLOAD(void) {
    return board_ok_u32((uint32_t)(SysTick->LOAD));
}

lean_object *lean_board_systick_getVAL(void) {
    return board_ok_u32((uint32_t)(SysTick->VAL));
}

lean_object *lean_board_systick_getCALIB(void) {
    return board_ok_u32((uint32_t)(SysTick->CALIB));
}

lean_object *lean_board_systick_setCTRL(uint32_t value) {
    SysTick->CTRL = value; return board_ok_unit();
}

lean_object *lean_board_systick_setLOAD(uint32_t value) {
    SysTick->LOAD = value; return board_ok_unit();
}

lean_object *lean_board_systick_setVAL(uint32_t value) {
    SysTick->VAL = value; return board_ok_unit();
}

