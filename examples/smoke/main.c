#include <lean/lean.h>
#include <lean/cmsis.h>
#include <stdio.h>
#include <stdlib.h>
#include "cmsis_os2.h"
#include "lean_app_init.h"
extern lean_object * lean_embedded_smoke(lean_object *);
extern int lean_cmsis_selftest(void);
extern int systick_contract_test(void);
extern int timer_sequence_test(void);
#ifdef LEAN_CONSOLE_EXAMPLE
extern lean_object * lean_console_demo(lean_object * message);
#endif
static int run_tests(void) {
    puts("Lean Cortex-M55: runtime start");
    lean_initialize_runtime_module();
    lean_object * init = lean_app_initialize(1);
    if (!lean_io_result_is_ok(init)) { puts("FAIL: module initialization"); return 1; }
    lean_dec(init);
    lean_io_mark_end_initialization();
#ifdef LEAN_CONSOLE_EXAMPLE
    lean_init_task_manager_using(2);
    lean_object * console = lean_console_demo(lean_mk_string("Hello from stock Lean IO on Cortex-M55"));
    if (lean_io_result_is_error(console)) { puts("FAIL: Lean console"); lean_dec(console); return 1; }
    lean_dec(console);
    lean_finalize_task_manager();
#endif
    lean_object * value = lean_embedded_smoke(lean_unsigned_to_nat(100000));
    lean_object * expected = lean_cstr_to_nat("10004300042");
    int ok = lean_nat_dec_eq(value, expected);
    lean_dec(value);
    lean_dec(expected);
    puts(ok ? "PASS: Lean Nat arithmetic (32-bit target, big result)" : "FAIL: Lean arithmetic");
    if (ok) lean_cmsis_selftest();
    if (ok && systick_contract_test() != 0) { puts("FAIL: SysTick contract"); ok = 0; }
    if (ok && timer_sequence_test() != 0) { puts("FAIL: timer initialization sequence"); ok = 0; }
    fflush(stdout);
    return ok ? 0 : 1;
}

static void app_thread(void * argument) {
    (void)argument;
    exit(run_tests());
}
int main(void) {
#ifdef LEAN_BOARD_ALIF_E8
    extern int board_stdio_init(void);
    if (board_stdio_init() != 0) return 6;
#endif
    if (osKernelInitialize() != osOK) return 2;
    const osThreadAttr_t attr = { .name = "lean-main", .stack_size = 32768 };
    if (!osThreadNew(app_thread, NULL, &attr)) return 3;
    if (osKernelStart() != osOK) return 4;
    return 5;
}
