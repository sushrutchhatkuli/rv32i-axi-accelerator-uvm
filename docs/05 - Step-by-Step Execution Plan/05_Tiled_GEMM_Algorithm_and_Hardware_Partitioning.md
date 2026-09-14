# Architectural Deep Dive: Tiled Block GEMM & Hardware/Software Partitioning

## 1. Executive Summary

In enterprise AI accelerators and domain-specific architectures (such as Google TPU, Apple Neural Engine, and NVIDIA Tensor Cores), the silicon compute array has a fixed physical dimension (e.g., 2x2, 16x16, or 128x128 systolic cells), whereas real-world deep neural network layers process matrices spanning thousands of dimensions.

To bridge this gap, computing systems employ **Tiled Matrix Multiplication (Block GEMM)**. Instead of requiring infinite silicon area, the software driver/firmware partitions large tensors into sub-blocks that match the physical accelerator dimensions, streams them across the system interconnect (AMBA AXI), triggers execution, and accumulates the partial products.

This document details the mathematical formulation, hardware/software co-design, assembly firmware driver implementation, and cycle-accurate co-verification of our **Generic 4x4 Tiled Block GEMM** running on a **2x2 4-MAC coprocessor**.

---

## 2. Mathematical Formulation

### 2.1 The Block Partitioning Principle

Let matrix $A \in \mathbb{R}^{4 \times 4}$ and matrix $B \in \mathbb{R}^{4 \times 4}$. We compute:
$$C = A \times B$$

We partition matrices $A$, $B$, and $C$ into $2 \times 2$ blocks:
$$
A = \begin{pmatrix} A_{00} & A_{01} \\ A_{10} & A_{11} \end{pmatrix}, \quad
B = \begin{pmatrix} B_{00} & B_{01} \\ B_{10} & B_{11} \end{pmatrix}, \quad
C = \begin{pmatrix} C_{00} & C_{01} \\ C_{10} & C_{11} \end{pmatrix}
$$

Where each sub-block $A_{ij}, B_{ij}, C_{ij} \in \mathbb{R}^{2 \times 2}$ perfectly matches our hardware accelerator dimensions.

### 2.2 Sub-Block Matrix Products and Accumulation

By block matrix multiplication rules:
$$
\begin{aligned}
C_{00} &= A_{00} B_{00} + A_{01} B_{10} \\
C_{01} &= A_{00} B_{01} + A_{01} B_{11} \\
C_{10} &= A_{10} B_{00} + A_{11} B_{10} \\
C_{11} &= A_{10} B_{01} + A_{11} B_{11}
\end{aligned}
$$

Each sub-block multiplication $A_{ik} B_{kj}$ is dispatched to the hardware accelerator as an autonomous hardware MAC run (requiring 8 coprocessor dispatches total). The resulting partial product matrices are accumulated either inside the CPU registers or in memory.

### 2.3 Verification Matrix Dataset

To ensure mathematical clarity and error-free bit-level traceability, test matrices are chosen using scaled identity structures:

$$
A = \begin{pmatrix} I & 2I \\ 3I & I \end{pmatrix}, \quad
B = \begin{pmatrix} 2I & I \\ I & 3I \end{pmatrix}
$$

Where $I = \begin{pmatrix} 1 & 0 \\ 0 & 1 \end{pmatrix}$.

Computing the four sub-blocks analytically:
1. **Block $C_{00}$**:
   $$C_{00} = (I)(2I) + (2I)(I) = 2I + 2I = 4I = \begin{pmatrix} 4 & 0 \\ 0 & 4 \end{pmatrix}$$
2. **Block $C_{01}$**:
   $$C_{01} = (I)(I) + (2I)(3I) = I + 6I = 7I = \begin{pmatrix} 7 & 0 \\ 0 & 7 \end{pmatrix}$$
3. **Block $C_{10}$**:
   $$C_{10} = (3I)(2I) + (I)(I) = 6I + I = 7I = \begin{pmatrix} 7 & 0 \\ 0 & 7 \end{pmatrix}$$
4. **Block $C_{11}$**:
   $$C_{11} = (3I)(I) + (I)(3I) = 3I + 3I = 6I = \begin{pmatrix} 6 & 0 \\ 0 & 6 \end{pmatrix}$$

Final Assembled $4 \times 4$ Matrix $C$:
$$
C = \begin{pmatrix}
4 & 0 & 7 & 0 \\
0 & 4 & 0 & 7 \\
7 & 0 & 6 & 0 \\
0 & 7 & 0 & 6
\end{pmatrix}
$$

---

## 3. Hardware/Software Partitioning

```
+-------------------------------------------------------------------------+
|                              RV32I Core                                 |
|                                                                         |
|  1. Loop Partitioning: Splits 4x4 matrices into 2x2 blocks              |
|  2. Interconnect Streaming: AXI MMIO writes to 0x4000_0100..0x4000_010C |
|  3. Dispatch & Synchronization: Triggers CTRL=0x3, polls STATUS[DONE]   |
|  4. Partial-Product Accumulation: RV32I ALU adds partial matrices       |
|  5. Result Assembly: Stores final 4x4 matrix into SRAM (0x1010..0x102C) |
+-------------------------------------------------------------------------+
                                    |
                          AMBA AXI4-Lite Bus
                                    |
+-------------------------------------------------------------------------+
|                     4-MAC Accelerator Hardware                          |
|                                                                         |
|  - Dual Input Buffers: 2x2 Matrix A (row-major), 2x2 Matrix B (col-maj) |
|  - Compute Engine: 4 Parallel DSP Multiply-Accumulate units             |
|  - Latency: Computes full 2x2 matrix product in single hardware burst   |
|  - Output Buffer: 2x2 Result Matrix C accessible via AXI readback       |
+-------------------------------------------------------------------------+
```

---

## 4. Firmware Driver Implementation

The driver program (`firmware/tiled_gemm.s`) is assembled into machine code (`firmware/tiled_gemm.hex`) and preloaded into instruction memory:

1. **Hardware Addressing**:
   - Accelerator Base Address: `s0 = 0x4000_0000`
   - SRAM Data Memory Base Address: `s1 = 0x0000_1000`
2. **Sub-Block Execution Flow**:
   - Sub-block pass 1: Write input sub-blocks to accelerator, set `START=1`.
   - Poll `STATUS[1]` until `DONE` is high.
   - Read back partial product 1 ($P_1$) across AXI.
   - Sub-block pass 2: Write next input sub-blocks, set `START=1`.
   - Poll `STATUS[1]` until `DONE` is high.
   - Read back partial product 2 ($P_2$) across AXI.
   - Accumulate $C_{ij} = P_1 + P_2$ using RV32I `add` instructions.
   - Write assembled sub-block $C_{ij}$ to SRAM.
3. **Autonomous Mailbox Verification**:
   - The firmware checks all 8 output rows against known-good golden constants.
   - On full success, the firmware writes signature `0xFEEDC0DE` to `RAM[0x1004]`.
   - On mismatch, it writes `0xDEADDEAD`.

---

## 5. Simulation & Co-Verification Results

The co-verification testbench (`verif/tb/tb_soc_tiled_gemm.sv`) asserts execution correctness in real hardware time:

```
[BOOT] Reset released. RV32I Core fetching Tiled GEMM code from 0x0000_0000...

[EVENT @ 930000 ps] Accelerator Tile Run #1 triggered via AXI MMIO!
[EVENT @ 2710000 ps] Accelerator Tile Run #2 triggered via AXI MMIO!
[EVENT @ 4650000 ps] Accelerator Tile Run #3 triggered via AXI MMIO!
[EVENT @ 6430000 ps] Accelerator Tile Run #4 triggered via AXI MMIO!
[EVENT @ 8370000 ps] Accelerator Tile Run #5 triggered via AXI MMIO!
[EVENT @ 10150000 ps] Accelerator Tile Run #6 triggered via AXI MMIO!
[EVENT @ 12090000 ps] Accelerator Tile Run #7 triggered via AXI MMIO!
[EVENT @ 13870000 ps] Accelerator Tile Run #8 triggered via AXI MMIO!

-------------------------------------------------------
--- Step 1: Sub-Block C00 (Tiles A00*B00 + A01*B10 = 4*I) ---
  [PASS] C00 Row 0 (RAM[0x1010])                          | Got: 0x00000400 (1024)
  [PASS] C00 Row 1 (RAM[0x1014])                          | Got: 0x04000000 (67108864)

--- Step 2: Sub-Block C01 (Tiles A00*B01 + A01*B11 = 7*I) ---
  [PASS] C01 Row 0 (RAM[0x1018])                          | Got: 0x00000700 (1792)
  [PASS] C01 Row 1 (RAM[0x101C])                          | Got: 0x07000000 (117440512)

--- Step 3: Sub-Block C10 (Tiles A10*B00 + A11*B10 = 7*I) ---
  [PASS] C10 Row 0 (RAM[0x1020])                          | Got: 0x00000700 (1792)
  [PASS] C10 Row 1 (RAM[0x1024])                          | Got: 0x07000000 (117440512)

--- Step 4: Sub-Block C11 (Tiles A10*B01 + A11*B11 = 6*I) ---
  [PASS] C11 Row 0 (RAM[0x1028])                          | Got: 0x00000600 (1536)
  [PASS] C11 Row 1 (RAM[0x102C])                          | Got: 0x06000000 (100663296)

--- Step 5: Tiled GEMM Mailbox & Coprocessor Utilization ---
  [PASS] Total Accelerator Tile Runs Executed             | Got: 0x00000008 (8)
  [PASS] Tiled GEMM Mailbox at 0x1004 (PASS Signature)    | Got: 0xfeedc0de (4276994270)

=======================================================
  TILED BLOCK GEMM CO-VERIFICATION SUMMARY
  Total Tests  : 10
  Passed Tests : 10
  Failed Tests : 0
  Total Cycles : 790
  RESULT       : ALL TESTS PASSED! 100% SUCCESS
  SYSTEM STATE : FULL 4x4 TILED GEMM BIT-EXACT ON SILICON
=======================================================
```

---

## 6. Significance for Systems & Silicon Engineering Roles

1. **Compiler & Driver Understanding**: Demonstrates mastery of how compute workloads exceeding physical hardware capacities are partitioned and mapped to domain-specific silicon.
2. **True Full-Stack Co-Design**: Connects RISC-V assembly firmware, AXI MMIO bus handshaking, hardware coprocessor scheduling, and SystemVerilog scoreboarding into a unified solution.
3. **Deterministic Cycle-Accurate Execution**: Completes the full 4x4 tiled workload with 8 hardware coprocessor runs in only 790 clock cycles.
