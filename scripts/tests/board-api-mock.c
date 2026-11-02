/* Host-only FFI fixture. Resource operations use the production registry core.
 * Fields: 0=IPSR, 1=PRIMASK, 2=BASEPRI, 3=FAULTMASK, 4=kernel,
 * 5=mutating calls, 6=source mask, 7=SysTick CTRL, 8=TX busy, 9=RX busy,
 * 10=TX count, 11=RX count, 12=abort stuck, 13=NVIC line 7 enabled. */
#include "resource_state.h"
static uint32_t fields[16] = { [4] = 2 };
static uint32_t lines[240];
static size_t next_event = 100;
static lean_object *changed(void) { ++fields[5]; return board_ok_u32(0); }
lean_object *lean_board_test_set(uint32_t field, uint32_t value) {
    fields[field] = value;
    if (field == 13) lines[7] = value;
    return board_ok_unit();
}
lean_object *lean_board_test_get(uint32_t field) {
    return board_ok_u32(field == 13 ? lines[7] : fields[field]);
}
lean_object *lean_board_resource_claim(uint32_t k, size_t p, uint32_t n) { return board_ok_u32(board_resource_claim(k,p,n)); }
lean_object *lean_board_resource_claim_range(uint32_t k, size_t p, size_t n) { return board_ok_u32(board_resource_claim_range(k,p,n)); }
lean_object *lean_board_resource_find(uint32_t k, size_t p, uint32_t n) { return board_ok_u32(board_resource_find(k,p,n)); }
lean_object *lean_board_resource_epoch(uint32_t t) { return board_ok_u32(board_resource_epoch(t)); }
lean_object *lean_board_resource_begin(uint32_t t, uint32_t e, uint32_t w) { return board_ok_u32(board_resource_begin(t,e,w)); }
lean_object *lean_board_resource_end(uint32_t o, uint32_t r) { return board_ok_u32(board_resource_end(o,r)); }
lean_object *lean_board_cpu_getIPSR(void) { return board_ok_u32(fields[0]); }
lean_object *lean_board_cpu_getPRIMASK(void) { return board_ok_u32(fields[1]); }
lean_object *lean_board_cpu_getBASEPRI(void) { return board_ok_u32(fields[2]); }
lean_object *lean_board_cpu_getFAULTMASK(void) { return board_ok_u32(fields[3]); }
lean_object *lean_board_cpu_setPRIMASK(uint32_t v) { fields[1]=v; return board_ok_unit(); }
lean_object *lean_board_cpu_disableIRQ(void) { fields[1]=1; return board_ok_unit(); }
lean_object *lean_board_cpu_dsb(void) { return board_ok_unit(); }
uint32_t lean_board_nvic_irq_count(lean_object *u) { (void)u; return 64; }
uint32_t lean_board_nvic_priority_bits(lean_object *u) { (void)u; return 4; }
lean_object *lean_board_nvic_getEnableIRQ(uint32_t irq) { return board_ok_u32(lines[irq]); }
lean_object *lean_board_nvic_enableIRQ(uint32_t irq) { lines[irq]=1; return board_ok_unit(); }
lean_object *lean_board_nvic_disableIRQ(uint32_t irq) { lines[irq]=0; return board_ok_unit(); }
lean_object *lean_board_nvic_clearPendingIRQ(uint32_t irq) { (void)irq; return changed(); }
lean_object *lean_board_nvic_setPriority(uint32_t irq, uint32_t p) { (void)irq; (void)p; return changed(); }
lean_object *lean_board_gpio_setup(size_t d, uint32_t p, size_t cb) {
    (void)d; if(cb) { fields[6] |= 1U << (p%8); lines[7]=1; } return changed();
}
lean_object *lean_board_gpio_setDirection(size_t d, uint32_t p, uint32_t v) { (void)d; (void)p; (void)v; return changed(); }
lean_object *lean_board_gpio_setPullResistor(size_t d, uint32_t p, uint32_t v) { (void)d; (void)p; (void)v; return changed(); }
lean_object *lean_board_gpio_setOutput(size_t d, uint32_t p, uint32_t v) { (void)d; (void)p; (void)v; return changed(); }
lean_object *lean_board_gpio_setEventTrigger(size_t d, uint32_t p, uint32_t v) { (void)d; (void)p; (void)v; return changed(); }
lean_object *lean_board_alifgpio_getEnabledInterrupts(size_t p) { (void)p; return lean_io_result_mk_ok(lean_box(fields[6])); }
lean_object *lean_board_alifgpio_disableInterrupt(size_t p, uint8_t b) { (void)p; fields[6] &= ~(1U<<b); return changed(); }
lean_object *lean_board_alifgpio_interruptEoi(size_t p, uint8_t b) { (void)p; (void)b; return changed(); }
lean_object *lean_board_alifgpio_unmaskInterrupt(size_t p, uint8_t b) { (void)p; (void)b; return changed(); }
lean_object *lean_board_alifgpio_enableInterrupt(size_t p, uint8_t b) { (void)p; fields[6] |= 1U<<b; return changed(); }
lean_object *lean_board_usart_getTxBusy(size_t d) { (void)d; return board_ok_u32(fields[8]); }
lean_object *lean_board_usart_getRxBusy(size_t d) { (void)d; return board_ok_u32(fields[9]); }
lean_object *lean_board_usart_getTxCount(size_t d) { (void)d; return board_ok_u32(fields[10]); }
lean_object *lean_board_usart_initialize(size_t d, size_t cb) { (void)d; (void)cb; return changed(); }
lean_object *lean_board_usart_powerControl(size_t d, uint32_t s) { (void)d; (void)s; return changed(); }
lean_object *lean_board_usart_control(size_t d, uint32_t c, uint32_t a) {
    (void)d; (void)a; if(c==0x18 && !fields[12]) fields[8]=0; return changed();
}
lean_object *lean_board_usart_send(size_t d, size_t p, uint32_t n) { (void)d; (void)p; (void)n; fields[8]=1; fields[10]=0; return changed(); }
lean_object *lean_board_usart_uninitialize(size_t d) { (void)d; return changed(); }
lean_object *lean_board_cmsisrtos_kernelGetState(void) { return board_ok_u32(fields[4]); }
lean_object *lean_board_cmsisrtos_kernelLock(void) { uint32_t prev=fields[4]==3; fields[4]=3; return board_ok_u32(prev); }
lean_object *lean_board_cmsisrtos_kernelRestoreLock(uint32_t prev) { fields[4]=prev ? 3 : 2; return changed(); }
lean_object *lean_board_cmsisrtos_delay(uint32_t n) { (void)n; return changed(); }
lean_object *lean_board_cmsisrtos_eventFlagsNew(size_t a) { (void)a; return board_ok_usize(next_event++); }
lean_object *lean_board_cmsisrtos_eventFlagsSet(size_t id, uint32_t f) { (void)id; (void)f; return changed(); }
lean_object *lean_board_cmsisrtos_eventFlagsDelete(size_t id) { (void)id; return changed(); }
lean_object *lean_board_cmsisrtos_threadNew(size_t f, size_t a, size_t attr) { (void)f; (void)a; (void)attr; ++fields[5]; return board_ok_usize(200); }
lean_object *lean_board_systick_getCTRL(void) { return board_ok_u32(fields[7]); }
lean_object *lean_board_systick_setCTRL(uint32_t v) { fields[7]=v; return changed(); }
lean_object *lean_board_systick_setLOAD(uint32_t v) { (void)v; return changed(); }
lean_object *lean_board_systick_setVAL(uint32_t v) { (void)v; return changed(); }
lean_object *lean_board_pinconfig_set(uint8_t p, uint8_t n, uint8_t f, uint8_t c) { (void)p; (void)n; (void)f; (void)c; return changed(); }
