# =============================================================================
# File: firmware.s
# Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
# Description: Complete RV32I assembly implementation of bare-metal driver.
#              1. Loads Matrix A and B into accelerator SRAM buffer (0x4000_0100).
#              2. Programs dimension N=2 and pointers in CSRs.
#              3. Asserts START and IRQ_EN in CTRL CSR (0x4000_0000).
#              4. Polls STATUS (0x4000_0004) until DONE bit 1 asserts.
#              5. Reads back Matrix C from buffer offsets 0x4000_0110 and 0x4000_0114.
#              6. Verifies results: C0 = 0x16001300, C1 = 0x32002B00.
#              7. If match, stores 0xCAFEBABE to RAM at 0x0000_1000.
# =============================================================================

.section .text
.global _start

_start:
    # 1. Setup Base Address Pointers
    lui  s0, 0x40000          # s0 = 0x4000_0000 (Accelerator Base)
    lui  s1, 0x00001          # s1 = 0x0000_1000 (Mailbox Base in RAM)

    # 2. Populate Matrix A and Matrix B into Accelerator Buffer (Offset 0x100)
    # A[0] = {0x0200, 0x0100} = 0x02000100
    lui  t0, 0x02000
    ori  t0, t0, 0x0100
    sw   t0, 256(s0)          # 0x100 = 256
    nop
    nop

    # A[1] = {0x0400, 0x0300} = 0x04000300
    lui  t0, 0x04000
    ori  t0, t0, 0x0300
    sw   t0, 260(s0)          # 0x104 = 260
    nop
    nop

    # B[0] = {0x0600, 0x0500} = 0x06000500
    lui  t0, 0x06000
    ori  t0, t0, 0x0500
    sw   t0, 264(s0)          # 0x108 = 264
    nop
    nop

    # B[1] = {0x0800, 0x0700} = 0x08000700
    lui  t0, 0x08000
    ori  t0, t0, 0x0700
    sw   t0, 268(s0)          # 0x10C = 268
    nop
    nop

    # 3. Configure Accelerator CSRs
    # DIM = 2
    addi t0, zero, 2
    sw   t0, 8(s0)            # REG_DIM (0x4000_0008)
    nop
    nop

    # SRC_A = 0
    sw   zero, 16(s0)         # REG_SRC_A (0x4000_0010)
    nop
    nop

    # SRC_B = 4
    addi t0, zero, 4
    sw   t0, 20(s0)           # REG_SRC_B (0x4000_0014)
    nop
    nop

    # DST = 8
    addi t0, zero, 8
    sw   t0, 24(s0)           # REG_DST (0x4000_0018)
    nop
    nop

    # 4. Trigger Accelerator (START = 1, IRQ_EN = 1 -> 0x3)
    addi t0, zero, 3
    sw   t0, 0(s0)            # REG_CTRL (0x4000_0000)
    nop
    nop

    # 5. Poll STATUS until DONE (bit 1) is asserted
poll_loop:
    lw   t1, 4(s0)            # Read REG_STATUS (0x4000_0004)
    nop
    nop
    andi t2, t1, 2            # Check bit 1 (DONE)
    beq  t2, zero, poll_loop  # If not done, continue polling

    # 6. Readback Result Matrix C from Buffer (Halfword 8 = Byte 0x110 = 272)
    # Trigger AXI read for C[0] (address 272)
    lw   t3, 272(s0)
    nop
    nop
    nop
    nop
    # Latches C[0] into t3 and triggers AXI read for C[1] (address 276)
    lw   t3, 276(s0)
    nop
    nop
    nop
    nop
    # Latches C[1] into t4
    lw   t4, 276(s0)
    nop
    nop
    nop
    nop

    # 7. Check C[0] == 0x16001300
    lui  t5, 0x16001
    addi t5, t5, 768          # 768 = 0x300 -> 0x16001300
    bne  t3, t5, fail_branch

    # Check C[1] == 0x32002B00
    lui  t6, 0x32003
    addi t6, t6, -1280        # 0x32003000 - 1280 = 0x32002B00
    bne  t4, t6, fail_branch

pass_branch:
    lui  t0, 0xCAFEC
    addi t0, t0, -1346        # 0xCAFEC000 - 1346 = 0xCAFEBABE
    sw   t0, 0(s1)            # Store to RAM[0x1000]
    nop
    nop
    beq  zero, zero, halt

fail_branch:
    lui  t0, 0xDEADE
    addi t0, t0, -339         # 0xDEADE000 - 339 = 0xDEADDEAD
    sw   t0, 0(s1)            # Store to RAM[0x1000]
    nop
    nop

halt:
    beq  zero, zero, halt
