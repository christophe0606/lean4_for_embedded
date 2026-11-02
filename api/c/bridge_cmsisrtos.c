#include "bridge.h"
#include "cmsis_os2.h"
_Static_assert(osFlagsWaitAny == 0 && osFlagsWaitAll == 1 && osFlagsNoClear == 2 &&
               osWaitForever == 0xFFFFFFFFU && osFlagsError == 0x80000000U &&
               osFlagsErrorTimeout == 0xFFFFFFFEU && osFlagsErrorResource == 0xFFFFFFFDU,
               "Update Lean RTOS constants for this CMSIS API");
lean_object *lean_board_cmsisrtos_eventFlagsNew(size_t attributes) {
    return board_ok_usize((size_t)(osEventFlagsNew((const osEventFlagsAttr_t *)attributes)));
}

lean_object *lean_board_cmsisrtos_eventFlagsSet(size_t id, uint32_t flags) {
    return board_ok_u32((uint32_t)(osEventFlagsSet((osEventFlagsId_t)id, flags)));
}

lean_object *lean_board_cmsisrtos_eventFlagsClear(size_t id, uint32_t flags) {
    return board_ok_u32((uint32_t)(osEventFlagsClear((osEventFlagsId_t)id, flags)));
}

lean_object *lean_board_cmsisrtos_eventFlagsGet(size_t id) {
    return board_ok_u32((uint32_t)(osEventFlagsGet((osEventFlagsId_t)id)));
}

lean_object *lean_board_cmsisrtos_eventFlagsWait(size_t id, uint32_t flags, uint32_t options, uint32_t timeout) {
    return board_ok_u32((uint32_t)(osEventFlagsWait((osEventFlagsId_t)id, flags, options, timeout)));
}

lean_object *lean_board_cmsisrtos_eventFlagsDelete(size_t id) {
    return board_ok_u32((uint32_t)(osEventFlagsDelete((osEventFlagsId_t)id)));
}

lean_object *lean_board_cmsisrtos_kernelGetState(void) {
    return board_ok_u32((uint32_t)(osKernelGetState()));
}

lean_object *lean_board_cmsisrtos_kernelGetTickFreq(void) {
    return board_ok_u32((uint32_t)(osKernelGetTickFreq()));
}

lean_object *lean_board_cmsisrtos_kernelGetTickCount(void) {
    return board_ok_u32((uint32_t)(osKernelGetTickCount()));
}

lean_object *lean_board_cmsisrtos_kernelInitialize(void) {
    return board_ok_u32((uint32_t)(osKernelInitialize()));
}

lean_object *lean_board_cmsisrtos_kernelStart(void) {
    return board_ok_u32((uint32_t)(osKernelStart()));
}

lean_object *lean_board_cmsisrtos_kernelLock(void) {
    return board_ok_u32((uint32_t)(osKernelLock()));
}

lean_object *lean_board_cmsisrtos_kernelUnlock(void) {
    return board_ok_u32((uint32_t)(osKernelUnlock()));
}

lean_object *lean_board_cmsisrtos_kernelRestoreLock(uint32_t lock) {
    return board_ok_u32((uint32_t)(osKernelRestoreLock((int32_t)lock)));
}

lean_object *lean_board_cmsisrtos_delay(uint32_t ticks) {
    return board_ok_u32((uint32_t)(osDelay(ticks)));
}

lean_object *lean_board_cmsisrtos_threadNew(size_t function, size_t argument, size_t attributes) {
    return board_ok_usize((size_t)(osThreadNew((osThreadFunc_t)function, (void *)argument, (const osThreadAttr_t *)attributes)));
}

