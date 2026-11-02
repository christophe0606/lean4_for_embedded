#include "bridge.h"
#include "cmsis_device.h"
lean_object *lean_board_cpu_getIPSR(void) { return board_ok_u32(__get_IPSR()); }
lean_object *lean_board_cpu_getBASEPRI(void) { return board_ok_u32(__get_BASEPRI()); }
lean_object *lean_board_cpu_getFAULTMASK(void) { return board_ok_u32(__get_FAULTMASK()); }
lean_object *lean_board_cpu_getPRIMASK(void) {
    return board_ok_u32((uint32_t)(__get_PRIMASK()));
}

lean_object *lean_board_cpu_setPRIMASK(uint32_t value) {
    __set_PRIMASK(value); return board_ok_unit();
}

lean_object *lean_board_cpu_disableIRQ(void) {
    __disable_irq(); return board_ok_unit();
}

lean_object *lean_board_cpu_enableIRQ(void) {
    __enable_irq(); return board_ok_unit();
}

lean_object *lean_board_cpu_dsb(void) {
    __DSB(); return board_ok_unit();
}

lean_object *lean_board_cpu_isb(void) {
    __ISB(); return board_ok_unit();
}

