/* =============================================================================
 * File: linker.ld
 * Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
 * Description: GNU Linker Script for 64 KB On-Chip Synchronous RAM.
 *              Origin: 0x0000_0000, Length: 64 KB (0x10000).
 * =============================================================================
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
    . = 0x00000000;

    .text.boot : {
        *(.text.boot)
    } > RAM

    .text : {
        *(.text*)
    } > RAM

    .rodata : {
        *(.rodata*)
    } > RAM

    .data : {
        *(.data*)
    } > RAM

    .bss : {
        *(.bss*)
        *(COMMON)
    } > RAM

    _stack_top = 0x00002000;
}
