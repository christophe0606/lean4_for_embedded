/* RTABI32 TLS helper preserves r1-r3 (unlike an ordinary C function).
 * https://github.com/ARM-software/abi-aa/blob/main/rtabi32/rtabi32.rst */
#ifdef __clang__
.syntax unified
.thumb
.section .text.__aeabi_read_tp,"ax",%progbits
.global __aeabi_read_tp
.type __aeabi_read_tp,%function
.thumb_func
__aeabi_read_tp:
    push {r1-r3, lr}
    vpush {d0-d7}
    bl lean_cmsis_native_tp
    vpop {d0-d7}
    pop {r1-r3, pc}
.size __aeabi_read_tp, .-__aeabi_read_tp
#endif
