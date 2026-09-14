# =============================================================================
# File: tiled_gemm.s
# Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
# Description: Autonomous Tiled Block GEMM (General Matrix Multiply) Driver.
#              Computes full 4x4 matrix multiplication using 2x2 hardware engine:
#                C = A x B where A and B are 4x4 matrices in Q8.8 fixed-point.
#              Partitions into 4 sub-blocks:
#                C00 = A00*B00 + A01*B10 = 4*I
#                C01 = A00*B01 + A01*B11 = 7*I
#                C10 = A10*B00 + A11*B10 = 7*I
#                C11 = A10*B01 + A11*B11 = 6*I
#              Writes 0xFEEDC0DE to RAM[0x1004] upon bit-exact verification.
# =============================================================================

.section .text
.global _start

_start:
    # -------------------------------------------------------------------------
    # 1. Base Pointers Setup
    # -------------------------------------------------------------------------
    lui  s0, 0x40000          # s0 = 0x4000_0000 (Accelerator Base)
    lui  s1, 0x00001          # s1 = 0x0000_1000 (RAM Mailbox & Buffer Base)

    # Configure static CSRs: DIM=2, SRC_A=0, SRC_B=4, DST=8
    addi t0, zero, 2
    sw   t0, 8(s0)            # REG_DIM (0x4000_0008)
    nop
    nop
    addi t0, zero, 0
    sw   t0, 16(s0)           # REG_SRC_A (0x4000_0010)
    nop
    nop
    addi t0, zero, 4
    sw   t0, 20(s0)           # REG_SRC_B (0x4000_0014)
    nop
    nop
    addi t0, zero, 8
    sw   t0, 24(s0)           # REG_DST (0x4000_0018)
    nop
    nop

    # =========================================================================
    # TILE 0,0: C00 = A00*B00 + A01*B10
    # =========================================================================
    # Pass 1: A00 (1*I) * B00 (2*I) -> P1 = 2*I
    lui  t0, 0x00000
    ori  t0, t0, 0x0100       # Row 0: {0x0000, 0x0100}
    sw   t0, 256(s0)          # Buffer[0]
    nop
    nop
    lui  t0, 0x01000          # Row 1: {0x0100, 0x0000}
    sw   t0, 260(s0)          # Buffer[1]
    nop
    nop
    lui  t0, 0x00000
    ori  t0, t0, 0x0200       # Row 0: {0x0000, 0x0200}
    sw   t0, 264(s0)          # Buffer[2]
    nop
    nop
    lui  t0, 0x02000          # Row 1: {0x0200, 0x0000}
    sw   t0, 268(s0)          # Buffer[3]
    nop
    nop
    addi t0, zero, 3
    sw   t0, 0(s0)            # START=1
    nop
    nop
poll_t00_1:
    lw   t1, 4(s0)
    nop
    nop
    nop
    nop
    andi t2, t1, 2
    beq  t2, zero, poll_t00_1
    # Readback P1
    lw   t3, 272(s0)          # Trigger read 272
    nop
    nop
    nop
    nop
    lw   t3, 276(s0)          # Latches P1_row0, trigger read 276
    nop
    nop
    nop
    nop
    lw   t4, 276(s0)          # Latches P1_row1
    nop
    nop
    nop
    nop

    # Pass 2: A01 (2*I) * B10 (1*I) -> P2 = 2*I
    lui  t0, 0x00000
    ori  t0, t0, 0x0200       # Row 0: {0x0000, 0x0200}
    sw   t0, 256(s0)
    nop
    nop
    lui  t0, 0x02000          # Row 1: {0x0200, 0x0000}
    sw   t0, 260(s0)
    nop
    nop
    lui  t0, 0x00000
    ori  t0, t0, 0x0100       # Row 0: {0x0000, 0x0100}
    sw   t0, 264(s0)
    nop
    nop
    lui  t0, 0x01000          # Row 1: {0x0100, 0x0000}
    sw   t0, 268(s0)
    nop
    nop
    addi t0, zero, 3
    sw   t0, 0(s0)            # START=1
    nop
    nop
poll_t00_2:
    lw   t1, 4(s0)
    nop
    nop
    nop
    nop
    andi t2, t1, 2
    beq  t2, zero, poll_t00_2
    # Readback P2
    lw   t5, 272(s0)
    nop
    nop
    nop
    nop
    lw   t5, 276(s0)          # Latches P2_row0
    nop
    nop
    nop
    nop
    lw   t6, 276(s0)          # Latches P2_row1
    nop
    nop
    nop
    nop

    # Accumulate C00 = P1 + P2 = 4*I
    add  s2, t3, t5           # C00_row0 = 0x0000_0400
    add  s3, t4, t6           # C00_row1 = 0x0400_0000
    sw   s2, 16(s1)           # Store to RAM[0x1010]
    nop
    nop
    sw   s3, 20(s1)           # Store to RAM[0x1014]
    nop
    nop

    # =========================================================================
    # TILE 0,1: C01 = A00*B01 + A01*B11 = 1*I + 6*I = 7*I
    # =========================================================================
    # Pass 1: A00 (1*I) * B01 (1*I) -> P1 = 1*I
    lui  t0, 0x00000
    ori  t0, t0, 0x0100
    sw   t0, 256(s0)
    nop
    nop
    lui  t0, 0x01000
    sw   t0, 260(s0)
    nop
    nop
    lui  t0, 0x00000
    ori  t0, t0, 0x0100
    sw   t0, 264(s0)
    nop
    nop
    lui  t0, 0x01000
    sw   t0, 268(s0)
    nop
    nop
    addi t0, zero, 3
    sw   t0, 0(s0)
    nop
    nop
poll_t01_1:
    lw   t1, 4(s0)
    nop
    nop
    nop
    nop
    andi t2, t1, 2
    beq  t2, zero, poll_t01_1
    lw   t3, 272(s0)
    nop
    nop
    nop
    nop
    lw   t3, 276(s0)
    nop
    nop
    nop
    nop
    lw   t4, 276(s0)
    nop
    nop
    nop
    nop

    # Pass 2: A01 (2*I) * B11 (3*I) -> P2 = 6*I
    lui  t0, 0x00000
    ori  t0, t0, 0x0200
    sw   t0, 256(s0)
    nop
    nop
    lui  t0, 0x02000
    sw   t0, 260(s0)
    nop
    nop
    lui  t0, 0x00000
    ori  t0, t0, 0x0300
    sw   t0, 264(s0)
    nop
    nop
    lui  t0, 0x03000
    sw   t0, 268(s0)
    nop
    nop
    addi t0, zero, 3
    sw   t0, 0(s0)
    nop
    nop
poll_t01_2:
    lw   t1, 4(s0)
    nop
    nop
    nop
    nop
    andi t2, t1, 2
    beq  t2, zero, poll_t01_2
    lw   t5, 272(s0)
    nop
    nop
    nop
    nop
    lw   t5, 276(s0)
    nop
    nop
    nop
    nop
    lw   t6, 276(s0)
    nop
    nop
    nop
    nop

    # Accumulate C01 = P1 + P2 = 7*I
    add  s4, t3, t5           # C01_row0 = 0x0000_0700
    add  s5, t4, t6           # C01_row1 = 0x0700_0000
    sw   s4, 24(s1)           # Store to RAM[0x1018]
    nop
    nop
    sw   s5, 28(s1)           # Store to RAM[0x101C]
    nop
    nop

    # =========================================================================
    # TILE 1,0: C10 = A10*B00 + A11*B10 = 6*I + 1*I = 7*I
    # =========================================================================
    # Pass 1: A10 (3*I) * B00 (2*I) -> P1 = 6*I
    lui  t0, 0x00000
    ori  t0, t0, 0x0300
    sw   t0, 256(s0)
    nop
    nop
    lui  t0, 0x03000
    sw   t0, 260(s0)
    nop
    nop
    lui  t0, 0x00000
    ori  t0, t0, 0x0200
    sw   t0, 264(s0)
    nop
    nop
    lui  t0, 0x02000
    sw   t0, 268(s0)
    nop
    nop
    addi t0, zero, 3
    sw   t0, 0(s0)
    nop
    nop
poll_t10_1:
    lw   t1, 4(s0)
    nop
    nop
    nop
    nop
    andi t2, t1, 2
    beq  t2, zero, poll_t10_1
    lw   t3, 272(s0)
    nop
    nop
    nop
    nop
    lw   t3, 276(s0)
    nop
    nop
    nop
    nop
    lw   t4, 276(s0)
    nop
    nop
    nop
    nop

    # Pass 2: A11 (1*I) * B10 (1*I) -> P2 = 1*I
    lui  t0, 0x00000
    ori  t0, t0, 0x0100
    sw   t0, 256(s0)
    nop
    nop
    lui  t0, 0x01000
    sw   t0, 260(s0)
    nop
    nop
    lui  t0, 0x00000
    ori  t0, t0, 0x0100
    sw   t0, 264(s0)
    nop
    nop
    lui  t0, 0x01000
    sw   t0, 268(s0)
    nop
    nop
    addi t0, zero, 3
    sw   t0, 0(s0)
    nop
    nop
poll_t10_2:
    lw   t1, 4(s0)
    nop
    nop
    nop
    nop
    andi t2, t1, 2
    beq  t2, zero, poll_t10_2
    lw   t5, 272(s0)
    nop
    nop
    nop
    nop
    lw   t5, 276(s0)
    nop
    nop
    nop
    nop
    lw   t6, 276(s0)
    nop
    nop
    nop
    nop

    # Accumulate C10 = P1 + P2 = 7*I
    add  s6, t3, t5           # C10_row0 = 0x0000_0700
    add  s7, t4, t6           # C10_row1 = 0x0700_0000
    sw   s6, 32(s1)           # Store to RAM[0x1020]
    nop
    nop
    sw   s7, 36(s1)           # Store to RAM[0x1024]
    nop
    nop

    # =========================================================================
    # TILE 1,1: C11 = A10*B01 + A11*B11 = 3*I + 3*I = 6*I
    # =========================================================================
    # Pass 1: A10 (3*I) * B01 (1*I) -> P1 = 3*I
    lui  t0, 0x00000
    ori  t0, t0, 0x0300
    sw   t0, 256(s0)
    nop
    nop
    lui  t0, 0x03000
    sw   t0, 260(s0)
    nop
    nop
    lui  t0, 0x00000
    ori  t0, t0, 0x0100
    sw   t0, 264(s0)
    nop
    nop
    lui  t0, 0x01000
    sw   t0, 268(s0)
    nop
    nop
    addi t0, zero, 3
    sw   t0, 0(s0)
    nop
    nop
poll_t11_1:
    lw   t1, 4(s0)
    nop
    nop
    nop
    nop
    andi t2, t1, 2
    beq  t2, zero, poll_t11_1
    lw   t3, 272(s0)
    nop
    nop
    nop
    nop
    lw   t3, 276(s0)
    nop
    nop
    nop
    nop
    lw   t4, 276(s0)
    nop
    nop
    nop
    nop

    # Pass 2: A11 (1*I) * B11 (3*I) -> P2 = 3*I
    lui  t0, 0x00000
    ori  t0, t0, 0x0100
    sw   t0, 256(s0)
    nop
    nop
    lui  t0, 0x01000
    sw   t0, 260(s0)
    nop
    nop
    lui  t0, 0x00000
    ori  t0, t0, 0x0300
    sw   t0, 264(s0)
    nop
    nop
    lui  t0, 0x03000
    sw   t0, 268(s0)
    nop
    nop
    addi t0, zero, 3
    sw   t0, 0(s0)
    nop
    nop
poll_t11_2:
    lw   t1, 4(s0)
    nop
    nop
    nop
    nop
    andi t2, t1, 2
    beq  t2, zero, poll_t11_2
    lw   t5, 272(s0)
    nop
    nop
    nop
    nop
    lw   t5, 276(s0)
    nop
    nop
    nop
    nop
    lw   t6, 276(s0)
    nop
    nop
    nop
    nop

    # Accumulate C11 = P1 + P2 = 6*I
    add  s8, t3, t5           # C11_row0 = 0x0000_0600
    add  s9, t4, t6           # C11_row1 = 0x0600_0000
    sw   s8, 40(s1)           # Store to RAM[0x1028]
    nop
    nop
    sw   s9, 44(s1)           # Store to RAM[0x102C]
    nop
    nop

    # =========================================================================
    # 3. Complete 4x4 Output Matrix Verification
    # =========================================================================
    # Check C00_row0 == 0x0000_0400
    lui  t0, 0x00000
    ori  t0, t0, 0x0400
    bne  s2, t0, fail_branch

    # Check C00_row1 == 0x0400_0000
    lui  t0, 0x04000
    bne  s3, t0, fail_branch

    # Check C01_row0 == 0x0000_0700
    lui  t0, 0x00000
    ori  t0, t0, 0x0700
    bne  s4, t0, fail_branch

    # Check C01_row1 == 0x0700_0000
    lui  t0, 0x07000
    bne  s5, t0, fail_branch

    # Check C10_row0 == 0x0000_0700
    lui  t0, 0x00000
    ori  t0, t0, 0x0700
    bne  s6, t0, fail_branch

    # Check C10_row1 == 0x0700_0000
    lui  t0, 0x07000
    bne  s7, t0, fail_branch

    # Check C11_row0 == 0x0000_0600
    lui  t0, 0x00000
    ori  t0, t0, 0x0600
    bne  s8, t0, fail_branch

    # Check C11_row1 == 0x0600_0000
    lui  t0, 0x06000
    bne  s9, t0, fail_branch

pass_branch:
    # Signature 0xFEEDC0DE -> RAM[0x1004] (Tiled GEMM Mailbox)
    lui  t0, 0xFEEDC
    addi t0, t0, 222          # 0xFEEDC000 + 0xDE (222) = 0xFEEDC0DE
    sw   t0, 4(s1)            # Store to RAM[0x1004]
    nop
    nop
    beq  zero, zero, halt

fail_branch:
    lui  t0, 0xDEADE
    addi t0, t0, -339         # 0xDEADDEAD
    sw   t0, 4(s1)            # Store to RAM[0x1004]
    nop
    nop

halt:
    beq  zero, zero, halt
