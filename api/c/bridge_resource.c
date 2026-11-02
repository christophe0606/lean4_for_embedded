#include "bridge.h"
#include "resource_state.h"
#include "cmsis_device.h"

/* Single Cortex-M core, thread context only. ISRs never enter Lean or this
 * registry. Only the bounded metadata update runs under PRIMASK. */
#define GUARD(expr) uint32_t mask=__get_PRIMASK(); __disable_irq(); \
    uint32_t result=(expr); __set_PRIMASK(mask); return board_ok_u32(result)
lean_object *lean_board_resource_claim(uint32_t kind, size_t key, uint32_t subkey) {
    GUARD(board_resource_claim(kind,key,subkey));
}
lean_object *lean_board_resource_claim_range(uint32_t kind, size_t key, size_t extent) {
    GUARD(board_resource_claim_range(kind,key,extent));
}
lean_object *lean_board_resource_find(uint32_t kind, size_t key, uint32_t subkey) {
    GUARD(board_resource_find(kind,key,subkey));
}
lean_object *lean_board_resource_epoch(uint32_t ticket) { GUARD(board_resource_epoch(ticket)); }
lean_object *lean_board_resource_begin(uint32_t ticket, uint32_t epoch, uint32_t write) {
    GUARD(board_resource_begin(ticket,epoch,write));
}
lean_object *lean_board_resource_end(uint32_t operation, uint32_t outcome) {
    GUARD(board_resource_end(operation,outcome));
}
