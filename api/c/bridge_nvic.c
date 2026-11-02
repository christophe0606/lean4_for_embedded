#include "bridge.h"
#include "cmsis_device.h"

uint32_t lean_board_nvic_irq_count(lean_object *unit) {
    (void)unit;
#if defined(ICB_ICTR_INTLINESNUM_Msk)
    return 32U * (((ICB->ICTR & ICB_ICTR_INTLINESNUM_Msk) >> ICB_ICTR_INTLINESNUM_Pos) + 1U);
#else
    return 32U * (((SCnSCB->ICTR & SCnSCB_ICTR_INTLINESNUM_Msk) >> SCnSCB_ICTR_INTLINESNUM_Pos) + 1U);
#endif
}

uint32_t lean_board_nvic_priority_bits(lean_object *unit) {
    (void)unit;
    return __NVIC_PRIO_BITS;
}
lean_object *lean_board_nvic_enableIRQ(uint32_t irq) {
    NVIC_EnableIRQ((IRQn_Type)(int32_t)irq); return board_ok_unit();
}

lean_object *lean_board_nvic_disableIRQ(uint32_t irq) {
    NVIC_DisableIRQ((IRQn_Type)(int32_t)irq); return board_ok_unit();
}

lean_object *lean_board_nvic_setPendingIRQ(uint32_t irq) {
    NVIC_SetPendingIRQ((IRQn_Type)(int32_t)irq); return board_ok_unit();
}

lean_object *lean_board_nvic_clearPendingIRQ(uint32_t irq) {
    NVIC_ClearPendingIRQ((IRQn_Type)(int32_t)irq); return board_ok_unit();
}

lean_object *lean_board_nvic_getEnableIRQ(uint32_t irq) {
    return board_ok_u32((uint32_t)(NVIC_GetEnableIRQ((IRQn_Type)(int32_t)irq)));
}

lean_object *lean_board_nvic_getPendingIRQ(uint32_t irq) {
    return board_ok_u32((uint32_t)(NVIC_GetPendingIRQ((IRQn_Type)(int32_t)irq)));
}

lean_object *lean_board_nvic_getActive(uint32_t irq) {
    return board_ok_u32((uint32_t)(NVIC_GetActive((IRQn_Type)(int32_t)irq)));
}

lean_object *lean_board_nvic_getPriority(uint32_t irq) {
    return board_ok_u32((uint32_t)(NVIC_GetPriority((IRQn_Type)(int32_t)irq)));
}

lean_object *lean_board_nvic_setPriority(uint32_t irq, uint32_t priority) {
    NVIC_SetPriority((IRQn_Type)(int32_t)irq, priority); return board_ok_unit();
}

