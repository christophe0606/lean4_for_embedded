#include <lean/lean.h>
#include <lean/cmsis.h>
#include <stdio.h>
#include "cmsis_os2.h"
#include "lean_app_init.h"

extern int board_stdio_init(void);
extern lean_object *lean_blinky_run(void);

static void app_thread(void *argument) {
    (void)argument;
    lean_initialize_runtime_module();
    lean_object *init = lean_app_initialize(1);
    if (lean_io_result_is_error(init)) {
        puts("Lean Blinky: module initialization failed");
        lean_dec(init);
        return;
    }
    lean_dec(init);
    lean_io_mark_end_initialization();
    lean_init_task_manager_using(2);

    lean_object *result = lean_blinky_run();
    if (lean_io_result_is_error(result))
        puts("Lean Blinky: application failed");
    lean_dec(result);
    lean_finalize_task_manager();
}

int main(void) {
    if (board_stdio_init() != 0) return 1;
    if (osKernelInitialize() != osOK) return 2;
    const osThreadAttr_t attr = { .name = "blinky-boot", .stack_size = 32768 };
    if (!osThreadNew(app_thread, NULL, &attr)) return 4;
    if (osKernelStart() != osOK) return 5;
    return 6;
}
