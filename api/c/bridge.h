#pragma once
#include <lean/lean.h>
#include <stdint.h>
#include <stddef.h>
static inline lean_object *board_ok_unit(void) {
    return lean_io_result_mk_ok(lean_box(0));
}
static inline lean_object *board_ok_u32(uint32_t value) {
    return lean_io_result_mk_ok(lean_box_uint32(value));
}
static inline lean_object *board_ok_usize(size_t value) {
    return lean_io_result_mk_ok(lean_box_usize(value));
}
