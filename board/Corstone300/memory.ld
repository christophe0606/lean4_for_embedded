/* Cortex-M55 secure ITCM and DTCM aliases from ARM BSP 1.4.0 pdsc.
 * Layout follows the BSP GNU linker script, with ARM TLS added. */
ENTRY(Reset_Handler)
MEMORY {
  FLASH (rx) : ORIGIN = 0x10000000, LENGTH = 512K
  RAM (rwx) : ORIGIN = 0x30000000, LENGTH = 512K
}
PHDRS { code PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); bss PT_LOAD FLAGS(6); tls PT_TLS FLAGS(4); }
SECTIONS {
  .text : {
    KEEP(*(.vectors))
    *(.text*) *(.rodata*)
    KEEP(*(.init)) KEEP(*(.fini))
  } > FLASH :code
  .ARM.extab : { *(.ARM.extab*) } > FLASH :code
  .ARM.exidx : {
    __exidx_start = .; *(.ARM.exidx*) __exidx_end = .;
  } > FLASH :code
  .data : ALIGN(8) {
    __data_start__ = .; *(.data*) *(.got*)
    . = ALIGN(4);
    __preinit_array_start = .; KEEP(*(.preinit_array)) __preinit_array_end = .;
    __init_array_start = .; KEEP(*(SORT(.init_array.*))) KEEP(*(.init_array)) __init_array_end = .;
    __fini_array_start = .; KEEP(*(SORT(.fini_array.*))) KEEP(*(.fini_array)) __fini_array_end = .;
    . = ALIGN(8); __data_end__ = .;
  } > RAM AT> FLASH :data
  __etext = LOADADDR(.data);
  .tdata : ALIGN(8) { __tls_base = .; *(.tdata*) __tdata_end = .; } > RAM AT> FLASH :data :tls
  __tls_load = LOADADDR(.tdata);
  .tbss (NOLOAD) : ALIGN(8) { __tbss_start = .; *(.tbss*) . = ALIGN(8); __tls_end = .; } > RAM :data :tls
  .bss (NOLOAD) : ALIGN(8) {
    __bss_start__ = .; *(.bss*) *(COMMON) . = ALIGN(8); __bss_end__ = .;
  } > RAM AT> RAM :bss
  .heap (NOLOAD) : ALIGN(8) {
    end = .; __end__ = .; __HeapBase = .; . += 192K; __HeapLimit = .;
  } > RAM :NONE
  .stack (NOLOAD) : ALIGN(8) {
    __StackLimit = .; . += 16K; __StackTop = .;
  } > RAM :NONE
  PROVIDE(__stack = __StackTop);
  PROVIDE(__stack_limit = __StackLimit);
  PROVIDE(__heap_start = __HeapBase);
  PROVIDE(__heap_end = __HeapLimit);
  PROVIDE(__StackSeal = __StackTop);
  ASSERT(__StackTop <= ORIGIN(RAM) + LENGTH(RAM), "RAM overflow")
}
