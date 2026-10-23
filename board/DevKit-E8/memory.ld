/* DK-E8 M55_HP default application MRAM and SRAM from Ensemble 2.2.1.
 * The HP MRAM slice starts at 0x80200000 after the HE slice. */
ENTRY(Reset_Handler)
MEMORY {
  MRAM (rx) : ORIGIN = 0x80200000, LENGTH = 2M
  SRAM (rwx) : ORIGIN = 0x02000000, LENGTH = 4M
}
PHDRS { code PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); bss PT_LOAD FLAGS(6); tls PT_TLS FLAGS(4); }
SECTIONS {
  .text : ALIGN(2048) {
    KEEP(*(.vectors))
    *(.text*) *(.rodata*)
    KEEP(*(.init)) KEEP(*(.fini))
  } > MRAM :code
  .ARM.extab : { *(.ARM.extab*) } > MRAM :code
  .ARM.exidx : { __exidx_start = .; *(.ARM.exidx*) __exidx_end = .; } > MRAM :code
  .data : ALIGN(8) {
    __data_start__ = .; *(.data*) *(.got*)
    . = ALIGN(4);
    __preinit_array_start = .; KEEP(*(.preinit_array)) __preinit_array_end = .;
    __init_array_start = .; KEEP(*(SORT(.init_array.*))) KEEP(*(.init_array)) __init_array_end = .;
    __fini_array_start = .; KEEP(*(SORT(.fini_array.*))) KEEP(*(.fini_array)) __fini_array_end = .;
    . = ALIGN(8); __data_end__ = .;
  } > SRAM AT> MRAM :data
  __etext = LOADADDR(.data);
  .tdata : ALIGN(8) { __tls_base = .; *(.tdata*) __tdata_end = .; } > SRAM AT> MRAM :data :tls
  __tls_load = LOADADDR(.tdata);
  .tbss (NOLOAD) : ALIGN(8) { *(.tbss*) . = ALIGN(8); __tls_end = .; } > SRAM :data :tls
  .bss (NOLOAD) : ALIGN(8) { __bss_start__ = .; *(.bss*) *(COMMON) . = ALIGN(8); __bss_end__ = .; } > SRAM :bss
  .heap (NOLOAD) : ALIGN(8) { __HeapBase = .; . += 2M; __HeapLimit = .; } > SRAM :NONE
  .stack (NOLOAD) : ALIGN(8) { __StackLimit = .; . += 16K; __StackTop = .; } > SRAM :NONE
  __INITIAL_SP = __StackTop;
  __STACK_LIMIT = __StackLimit;
  PROVIDE(__stack = __StackTop);
  PROVIDE(__stack_limit = __StackLimit);
  PROVIDE(__heap_start = __HeapBase);
  PROVIDE(__heap_end = __HeapLimit);
  PROVIDE(__StackSeal = __StackTop);
  ASSERT(__StackTop <= ORIGIN(SRAM) + LENGTH(SRAM), "SRAM overflow")
}
