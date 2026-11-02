#include "bridge.h"
#include "Driver_USART.h"
lean_object *lean_board_usart_getTxBusy(size_t driver) {
    return board_ok_u32(((ARM_DRIVER_USART *)driver)->GetStatus().tx_busy);
}
lean_object *lean_board_usart_getRxBusy(size_t driver) {
    return board_ok_u32(((ARM_DRIVER_USART *)driver)->GetStatus().rx_busy);
}
lean_object *lean_board_usart_initialize(size_t driver, size_t callback) {
    return board_ok_u32((uint32_t)(((ARM_DRIVER_USART *)driver)->Initialize((ARM_USART_SignalEvent_t)callback)));
}

lean_object *lean_board_usart_uninitialize(size_t driver) {
    return board_ok_u32((uint32_t)(((ARM_DRIVER_USART *)driver)->Uninitialize()));
}

lean_object *lean_board_usart_powerControl(size_t driver, uint32_t state) {
    return board_ok_u32((uint32_t)(((ARM_DRIVER_USART *)driver)->PowerControl((ARM_POWER_STATE)state)));
}

lean_object *lean_board_usart_control(size_t driver, uint32_t control, uint32_t argument) {
    return board_ok_u32((uint32_t)(((ARM_DRIVER_USART *)driver)->Control(control, argument)));
}

lean_object *lean_board_usart_send(size_t driver, size_t data, uint32_t count) {
    return board_ok_u32((uint32_t)(((ARM_DRIVER_USART *)driver)->Send((void *)data, count)));
}

lean_object *lean_board_usart_receive(size_t driver, size_t data, uint32_t count) {
    return board_ok_u32((uint32_t)(((ARM_DRIVER_USART *)driver)->Receive((void *)data, count)));
}

lean_object *lean_board_usart_getTxCount(size_t driver) {
    return board_ok_u32((uint32_t)(((ARM_DRIVER_USART *)driver)->GetTxCount()));
}

lean_object *lean_board_usart_getRxCount(size_t driver) {
    return board_ok_u32((uint32_t)(((ARM_DRIVER_USART *)driver)->GetRxCount()));
}

