// =============================================================================
// File: main.c
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Bare-metal C firmware for the RV32I Processor.
//              Autonomously:
//                1. Loads Matrix A & Matrix B into the accelerator buffer.
//                2. Configures matrix dimension N=2 and memory offsets.
//                3. Starts hardware accelerator computation and enables IRQ.
//                4. Waits for the computation to complete.
//                5. Reads back Matrix C and verifies against expected math.
//                6. Writes 0xCAFEBABE pass signature to RAM mailbox (0x1000).
// =============================================================================

// Memory-Mapped Accelerator Register Offsets on AMBA AXI4-Lite Bus
#define ACCEL_CTRL      ((volatile unsigned int *)0x40000000)
#define ACCEL_STATUS    ((volatile unsigned int *)0x40000004)
#define ACCEL_DIM       ((volatile unsigned int *)0x40000008)
#define ACCEL_SRC_A     ((volatile unsigned int *)0x40000010)
#define ACCEL_SRC_B     ((volatile unsigned int *)0x40000014)
#define ACCEL_DST       ((volatile unsigned int *)0x40000018)
#define ACCEL_BUFFER    ((volatile unsigned int *)0x40000100)

// RAM Mailbox for test status reporting
#define RESULT_MAILBOX  ((volatile unsigned int *)0x00001000)

// Helper macro: pack two 16-bit Q8.8 fixed-point numbers into one 32-bit word
#define PACK_Q88(a, b)  (((unsigned int)(b) << 16) | ((unsigned int)(a) & 0xFFFF))

int main(void) {
    // -------------------------------------------------------------------------
    // 1. Write Matrix A and Matrix B into Accelerator Dual-Port SRAM Buffer
    // Matrix A = [[1.0, 2.0], [3.0, 4.0]] -> Q8.8: [[0x0100, 0x0200], [0x0300, 0x0400]]
    // Matrix B = [[5.0, 6.0], [7.0, 8.0]] -> Q8.8: [[0x0500, 0x0600], [0x0700, 0x0800]]
    // -------------------------------------------------------------------------
    ACCEL_BUFFER[0] = PACK_Q88(0x0100, 0x0200); // Row 0 of A: {A[0][1], A[0][0]}
    ACCEL_BUFFER[1] = PACK_Q88(0x0300, 0x0400); // Row 1 of A: {A[1][1], A[1][0]}
    ACCEL_BUFFER[2] = PACK_Q88(0x0500, 0x0600); // Row 0 of B: {B[0][1], B[0][0]}
    ACCEL_BUFFER[3] = PACK_Q88(0x0700, 0x0800); // Row 1 of B: {B[1][1], B[1][0]}

    // -------------------------------------------------------------------------
    // 2. Configure Accelerator Control & Status Registers (CSRs)
    // -------------------------------------------------------------------------
    *ACCEL_DIM   = 2;          // 2x2 Matrix
    *ACCEL_SRC_A = 0;          // Matrix A base halfword offset = 0
    *ACCEL_SRC_B = 4;          // Matrix B base halfword offset = 4
    *ACCEL_DST   = 8;          // Matrix C base halfword offset = 8

    // -------------------------------------------------------------------------
    // 3. Command Accelerator to Start (Bit 0 = START, Bit 1 = IRQ_EN)
    // -------------------------------------------------------------------------
    *ACCEL_CTRL  = 0x00000003;

    // -------------------------------------------------------------------------
    // 4. Await Accelerator Completion (Poll STATUS bit 1: DONE)
    // -------------------------------------------------------------------------
    while ((*ACCEL_STATUS & 0x00000002) == 0) {
        // CPU loops while accelerator hardware computes 4-MAC dot products
    }

    // -------------------------------------------------------------------------
    // 5. Read Back Result Matrix C from Buffer
    // Expected: C = [[19.0, 22.0], [43.0, 50.0]]
    // Row 0: {0x1600, 0x1300} -> 0x16001300
    // Row 1: {0x3200, 0x2B00} -> 0x32002B00
    // -------------------------------------------------------------------------
    unsigned int c_row0 = ACCEL_BUFFER[4];
    unsigned int c_row1 = ACCEL_BUFFER[5];

    // -------------------------------------------------------------------------
    // 6. Mathematical Verification and Pass/Fail Reporting
    // -------------------------------------------------------------------------
    if (c_row0 == 0x16001300 && c_row1 == 0x32002B00) {
        *RESULT_MAILBOX = 0xCAFEBABE; // Signature: PASS
    } else {
        *RESULT_MAILBOX = 0xDEADDEAD; // Signature: FAIL
    }

    // Indefinite halt
    while (1);

    return 0;
}
