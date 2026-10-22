/* Fatal diagnostics stay allocation-free, including when the C heap is damaged.
 * Semihosting is the FVP console transport; no UART/serial port is used. */
#include <stdint.h>
#include "SSE300MPS3.h"
static void console(const char * text) {
    register uint32_t operation __asm__("r0") = 4;
    register const char * argument __asm__("r1") = text;
    __asm__ volatile("bkpt 0xab" : "+r"(operation) : "r"(argument) : "memory");
}
static void hex(uint32_t value) {
    char text[11] = "0x00000000";
    for (unsigned i=0; i<8; ++i) text[9-i] = "0123456789abcdef"[(value >> (i*4)) & 15];
    console(text);
}
static __attribute__((noreturn)) void fatal_exit(void) {
    uint32_t block[2] = {0x20026, 100};
    register uint32_t operation __asm__("r0") = 0x20;
    register uint32_t * argument __asm__("r1") = block;
    __asm__ volatile("bkpt 0xab" : "+r"(operation) : "r"(argument) : "memory");
    for (;;) {}
}
void embedded_fault(uint32_t * frame) {
    console("FAIL: Cortex-M fault PC="); hex(frame[6]);
    console(" LR="); hex(frame[5]); console(" CFSR="); hex(SCB->CFSR);
    console(" HFSR="); hex(SCB->HFSR); console(" BFAR="); hex(SCB->BFAR); console("\n");
    fatal_exit();
}
__attribute__((naked)) void HardFault_Handler(void) {
    __asm__ volatile("tst lr, #4\n ite eq\n mrseq r0, msp\n mrsne r0, psp\n b embedded_fault");
}
void MemManage_Handler(void) __attribute__((alias("HardFault_Handler")));
void BusFault_Handler(void) __attribute__((alias("HardFault_Handler")));
void UsageFault_Handler(void) __attribute__((alias("HardFault_Handler")));
uint32_t osRtxErrorNotify(uint32_t code, void * object) {
    console("FAIL: RTX error="); hex(code); console(" object="); hex((uintptr_t)object); console("\n");
    fatal_exit();
}
