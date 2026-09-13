# =============================================================================
# File: start.s
# Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
# Description: Minimal bare-metal startup assembly bootloader.
#              1. Initializes stack pointer (sp) to top of RAM (0x2000).
#              2. Jumps to main() C entry point.
#              3. Catches termination in an infinite loop.
# =============================================================================

.section .text.boot
.global _start

_start:
    # 1. Initialize stack pointer to 8KB (0x00002000)
    li sp, 0x00002000

    # 2. Clear frame pointer
    li fp, 0

    # 3. Call main()
    call main

    # 4. If main returns, loop indefinitely
_halt:
    j _halt
