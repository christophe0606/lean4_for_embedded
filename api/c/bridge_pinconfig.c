#include "bridge.h"
#include "pinconf.h"
lean_object *lean_board_pinconfig_set(uint8_t port, uint8_t pin, uint8_t function, uint8_t control) {
    return board_ok_u32((uint32_t)(pinconf_set(port, pin, function, control)));
}

