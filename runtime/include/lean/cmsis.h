#pragma once
#include <lean/lean.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Call once, in a running CMSIS thread, before initializing application modules. */
void lean_initialize_runtime_module(void);
/* Call after all application module initializers succeed. */
void lean_io_mark_end_initialization(void);
/* Foreign RTX threads must finalize Lean first, then release platform TLS. */
void lean_initialize_thread(void);
void lean_finalize_thread(void);
void lean_cmsis_tls_cleanup(void);
#ifdef __cplusplus
}
#endif
