---
title: "Phase 4 Execution Plan: Bare-Metal Firmware & HW/SW Co-Verification"
tags:
  - execution-plan
  - phase-4
  - firmware
  - bare-metal
  - risc-v
  - co-verification
  - mmio
  - interrupts
date_created: 2026-09-13
status: "Completed"
---

# Phase 4 Execution Plan: Bare-Metal Firmware & HW/SW Co-Verification

> [!IMPORTANT] **The Silicon Reality Check**
> Having working RTL hardware is only half the engineering equation. Modern silicon chips are useless without firmware to control them. In this phase, we bridge the hardware-software divide by developing a bare-metal RISC-V software stack that runs natively on our pipelined RV32I processor, orchestrating the 4-MAC matrix accelerator over the AMBA AXI4-Lite bus without an operating system.

---

## Architectural Overview

Bare-metal firmware executes directly on silicon hardware without an operating system (like Linux or FreeRTOS) managing memory or processes. The processor powers on, initializes its stack pointer, and immediately executes compiled instructions from Instruction RAM starting at address `0x0000_0000`.

### Analogy: The Symphony Conductor and Soloist
- The **RISC-V CPU** is the conductor: it reads musical score instructions, oversees timing, and gives cues.
- The **AXI Bus** is the acoustic stage: carrying commands and notes reliably between performers.
- The **Matrix Accelerator** is the virtuoso soloist: capable of blazing-fast mathematical execution when cued.
- The **RAM Mailbox** is the conductor's podium notebook: recording whether the performance succeeded (`0xCAFEBABE`) or failed (`0xDEADDEAD`).

```
+-----------------------------------------------------------------------------------+
|                            HETEROGENEOUS RISC-V SOC                               |
|                                                                                   |
|  +---------------------+        +--------------------+        +----------------+  |
|  |   RV32I Pipelined   |  MMIO  |     AMBA AXI4      |  MMIO  |  4-MAC Matrix  |  |
|  |     CPU Core        |=======>|   Crossbar Bus     |=======>|   Accelerator  |  |
|  | (Executes Firmware) |        |    Interconnect    |        | (Coprocessor)  |  |
|  +---------------------+        +--------------------+        +----------------+  |
|             |                              |                           |          |
|             | Fetch                        | Memory Write              | Done IRQ |
|             v                              v                           |          |
|  +---------------------+        +--------------------+                 |          |
|  |   Instruction RAM   |        |   Data RAM Mailbox |                 |          |
|  | (firmware.hex @ 0x0)|        |    (at 0x0000_1000)|<----------------+          |
|  +---------------------+        +--------------------+                            |
+-----------------------------------------------------------------------------------+
```

---

## Software and Toolchain Stack

### 1. GNU Linker Script (`firmware/linker.ld`)
Defines the memory map of the SoC:
- `RAM` Region: Origin `0x0000_0000`, Length 64 KB (`0x0001_0000`).
- Code (`.text`) sits at `0x0000_0000`.
- Data (`.data`, `.rodata`, `.bss`) follow consecutively.
- Initial Stack Pointer set to `0x0000_2000` (top of initial 8KB scratch region).
- Mailbox result word mapped at `0x0000_1000`.

### 2. C Hardware Abstraction Layer (`firmware/main.c`)
Defines Memory-Mapped I/O (MMIO) register addresses and control bitmasks:
- `ACCEL_REG_CTRL`: `0x4000_0000` (bit 0 = START, bit 1 = IRQ_EN).
- `ACCEL_REG_STATUS`: `0x4000_0004` (bit 0 = BUSY, bit 1 = DONE).
- `ACCEL_REG_DIM`: `0x4000_0008` (Matrix dimension N).
- `ACCEL_REG_SRC_A`: `0x4000_0010` (Offset in buffer for Matrix A).
- `ACCEL_REG_SRC_B`: `0x4000_0014` (Offset in buffer for Matrix B).
- `ACCEL_REG_DST`: `0x4000_0018` (Offset in buffer for Result C).
- `ACCEL_BUF_BASE`: `0x4000_0100` (SRAM scratchpad buffer).
- `RAM_MAILBOX`: `0x0000_1000` (Software status mailbox).

### 3. Native RV32I Assembly Driver (`firmware/firmware.s`)
Zero-dependency assembly implementation tailored for the 5-stage pipeline:
- Configures base pointer registers (`s0 = 0x4000_0000`, `s1 = 0x0000_1000`).
- Writes input matrices A and B into the accelerator buffer via AXI stores (`sw`).
- Configures dimension and buffer offset CSRs.
- Triggers computation by asserting START and IRQ_EN in `REG_CTRL`.
- Polls `REG_STATUS` until the DONE flag is asserted.
- Reads back computed output matrix C from buffer offsets `0x110` and `0x114`.
- Verifies results bit-for-bit against expected fixed-point Q8.8 numbers.
- Writes success signature `0xCAFEBABE` or failure signature `0xDEADDEAD` to RAM mailbox.

### 4. Custom RV32I Assembler (`scripts/asm_to_hex.py`)
A standalone Python tool that parses RV32I assembly instructions, resolves symbolic labels, calculates branch and jump immediate offsets, and emits Verilog `$readmemh`-compatible 32-bit hex files.

---

## Hardware/Software Co-Verification Testbench (`verif/tb/tb_soc_firmware.sv`)

The testbench orchestrates complete end-to-end silicon bring-up:
1. Loads `firmware.hex` into the SoC's instruction and data memories.
2. Asserts power-on reset for 40 ns, then releases it.
3. Observes autonomous CPU instruction fetching from `0x0000_0000`.
4. Monitored milestones:
   - Buffer writes over AXI bus.
   - CSR configuration writes over AXI bus.
   - Coprocessor FSM activation.
   - Hardware interrupt (`accel_irq_out`) generation.
   - Mailbox writeback by the CPU core.
5. Verifies 13 distinct assertions across 5 verification phases.

---

## Verification Scorecard

```
=======================================================
  AUTONOMOUS HW/SW CO-VERIFICATION SUMMARY
  Total Tests  : 13
  Passed Tests : 13
  Failed Tests : 0
  Total Cycles : 117
  RESULT       : ALL TESTS PASSED! 100% SUCCESS
  SYSTEM STATE : FULL HW/SW INTEGRATION VERIFIED
=======================================================
```

| Verification Checkpoint | Expected Value | Measured Value | Status |
|---|---|---|---|
| Matrix A Row 0 Buffer | `0x0200_0100` | `0x0200_0100` | PASS |
| Matrix A Row 1 Buffer | `0x0400_0300` | `0x0400_0300` | PASS |
| Matrix B Row 0 Buffer | `0x0600_0500` | `0x0600_0500` | PASS |
| Matrix B Row 1 Buffer | `0x0800_0700` | `0x0800_0700` | PASS |
| Dimension CSR (REG_DIM) | `0x0000_0002` | `0x0000_0002` | PASS |
| Source A Pointer CSR | `0x0000_0000` | `0x0000_0000` | PASS |
| Source B Pointer CSR | `0x0000_0004` | `0x0000_0004` | PASS |
| Destination Pointer CSR | `0x0000_0008` | `0x0000_0008` | PASS |
| Accelerator Done Flag | `1` | `1` | PASS |
| Accelerator Interrupt Out | `1` | `1` | PASS |
| Matrix C[0] Calculation | `0x1600_1300` | `0x1600_1300` | PASS |
| Matrix C[1] Calculation | `0x3200_2B00` | `0x3200_2B00` | PASS |
| RAM Mailbox at 0x1000 | `0xCAFE_BABE` | `0xCAFE_BABE` | PASS |

---

## Full CI/CD Regression Suite

The project includes an automated regression test harness (`scripts/run_regression.py`) and top-level `Makefile`:

```bash
make regression
```

Output:
```
================================================================================
  HETEROGENEOUS RISC-V SOC REGRESSION SUITE
================================================================================
[PASS] Phase 1: RV32I Core Execution Units                     | Passed:  15 | Failed:   0
[PASS] Phase 1: RV32I Branch & Control Flow                    | Passed:  20 | Failed:   0
[PASS] Phase 1: RV32I Pipeline Hazards & Forwarding            | Passed:   9 | Failed:   0
[PASS] Phase 2: AMBA AXI4-Lite Interconnect & Protocol         | Passed:  10 | Failed:   0
[PASS] Phase 3: 4-MAC Matrix Accelerator Engine                | Passed:  13 | Failed:   0
[PASS] Phase 3: Heterogeneous SoC Hardware Integration         | Passed:  12 | Failed:   0
[PASS] Phase 3: End-to-End System Integration & Matrix Pipeline | Passed:  12 | Failed:   0
[PASS] Phase 4: Autonomous Bare-Metal Firmware Co-Verification | Passed:  13 | Failed:   0
================================================================================
  REGRESSION SUMMARY
  Testbenches Run    : 8
  Testbenches Passed : 8
  Testbenches Failed : 0
  Total Assertions   : 104
  Total Passed Checks: 104
  Total Failed Checks: 0
  Execution Time     : 2.88 seconds
================================================================================
  OVERALL STATUS: 100% REGRESSION PASS
================================================================================
```
