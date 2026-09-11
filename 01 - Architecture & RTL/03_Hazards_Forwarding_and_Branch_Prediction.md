---
title: "Pipeline Hazards, Data Forwarding, and Branch Prediction"
tags:
  - riscv
  - hazards
  - forwarding
  - branch-prediction
  - microarchitecture
date_created: 2026-09-10
status: "Completed"
---

# ⚡ Pipeline Hazards, Data Forwarding, and Branch Prediction

> [!IMPORTANT] **Why Interviewers at Apple, NVIDIA, and ARM Obsess Over This Note**
> Any student can wire up an ALU and a program counter.
> What separates the **Top 1% Silicon Candidates** from everyone else is mastery of **Hazards, Bypass Networks, and Stall Mechanics**. In silicon interviews, over 50% of processor design questions focus on exactly how you resolve hazards without corrupting data or sacrificing clock frequency.

---

## 1. What is a Hazard?

A **Hazard** is an event where the next instruction in the pipeline cannot execute in its designated clock cycle because something is not ready.

There are three fundamental types of hazards:

```
                  +---------------------------+
                  |     Pipeline Hazards      |
                  +---------------------------+
                     /          |          \
                    /           |           \
         +-------------+  +-------------+  +-------------+
         | Structural  |  |    Data     |  |   Control   |
         |   Hazard    |  |   Hazard    |  |   Hazard    |
         +-------------+  +-------------+  +-------------+
```

1. **Structural Hazard**: Hardware resource conflict. (e.g. Trying to read and write to the same single-port memory at the exact same cycle. Resolved by separating Instruction and Data memory / caches).
2. **Data Hazard**: Instruction depends on the data output of a previous instruction that has not yet finished moving through the pipeline.
3. **Control Hazard**: Instruction to fetch next depends on a branch or jump decision that hasn't been evaluated yet.

---

## 2. Data Hazards: Read-After-Write (RAW)

Consider this ordinary assembly sequence:
```assembly
add x1, x2, x3    # Cycle 1: Computes x1 = x2 + x3
sub x4, x1, x5    # Cycle 2: Uses x1 to compute x4 = x1 - x5
and x6, x1, x7    # Cycle 3: Uses x1
```

Let's look at the pipeline timing diagram:

```
Clock Cycle:       1    2    3    4    5    6    7
------------------------------------------------------
add x1, x2, x3:   [IF] [ID] [EX] [MEM] [WB]
                              ^          |
                              |   Value of x1 written here!
                              |
sub x4, x1, x5:        [IF] [ID] [EX] [MEM] [WB]
                              ^
                              Needs value of x1 here!
```

### The Problem:
- `add` calculates the new value of `x1` during **Cycle 3 (EX stage)**.
- But `add` doesn't write that value back into the Register File until **Cycle 5 (WB stage)**!
- Meanwhile, `sub` tries to read `x1` from the Register File during **Cycle 3 (ID stage)**.
- `sub` reads the **old, stale value** of `x1`! This is a catastrophic **RAW (Read-After-Write) Hazard**.

---

## 3. The Solution: Forwarding (Bypassing)

Do we really need to wait until `add` writes to the Register File in Cycle 5?
**No!** 

The correct answer for `x1` was already computed by the ALU at the end of **Cycle 3** and is sitting right inside the `EX/MEM` pipeline register!

Instead of waiting for `add` to reach Writeback, we can build dedicated **Bypass Wires (Forwarding Multiplexers)** that send the result directly from `EX/MEM` back to the ALU input in the `EX` stage!

```
                    +--------------------+
                    |  Forwarding Unit   |
                    +--------------------+
                       |              |
         ForwardA Mux  |              |  ForwardB Mux
             v         v              v         v
             +---+                        +---+
  rs1_data ->| 0 |                        | 0 |<- rs2_data (or imm)
  EX/MEM ---->| 1 |--------+      +-------| 1 |<-- EX/MEM
  MEM/WB ---->| 2 |        |      |       | 2 |<-- MEM/WB
             +---+        |      |       +---+
                           v      v
                         +----------+
                         |   ALU    |
                         +----------+
```

### Forwarding Conditions & Boolean Logic:

#### 1. EX/MEM Hazard (Forward from immediately preceding instruction):
If the instruction in `EX/MEM` writes to a register (`RegWrite == 1`), that register is not `x0`, and its destination `rd` matches the source register `rs1` or `rs2` of the instruction currently in `EX`:
```systemverilog
if (ex_mem_regwrite && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs1))
    forward_a = 2'b10; // Forward from EX/MEM stage

if (ex_mem_regwrite && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs2))
    forward_b = 2'b10; // Forward from EX/MEM stage
```

#### 2. MEM/WB Hazard (Forward from instruction 2 cycles ago):
```systemverilog
if (mem_wb_regwrite && (mem_wb_rd != 5'b0) && 
    !(ex_mem_regwrite && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs1)) &&
    (mem_wb_rd == id_ex_rs1))
    forward_a = 2'b01; // Forward from MEM/WB stage

if (mem_wb_regwrite && (mem_wb_rd != 5'b0) && 
    !(ex_mem_regwrite && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs2)) &&
    (mem_wb_rd == id_ex_rs2))
    forward_b = 2'b01; // Forward from MEM/WB stage
```

---

## 4. The Unavoidable Hazard: Load-Use Data Hazard

Can forwarding solve *every* data hazard?
**No!** Because of the laws of physics, forwarding cannot travel backwards in time.

Look at this sequence:
```assembly
lw  x1, 0(x2)     # Load word from memory into x1
add x4, x1, x3    # Immediately use x1!
```

```
Clock Cycle:       1    2    3    4    5    6
------------------------------------------------
lw  x1, 0(x2):    [IF] [ID] [EX] [MEM] [WB]
                                    |
                                    Data arrives from RAM here! (Cycle 4)
                                    |
add x4, x1, x3:        [IF] [ID]  [EX]  [MEM] [WB]
                                    ^
                                    Needs data at START of Cycle 4!
```

Data from a `LW` instruction is only retrieved from RAM at the **end of Stage 4 (MEM)**.
The `add` instruction needs that data at the **start of Stage 3 (EX)** in Cycle 4.
Even with a forwarding wire, the data does not physically exist yet!

### The Solution: The Hazard Detection Unit (Pipeline Stall / Bubble)

The **Hazard Detection Unit** detects this specific scenario:
```systemverilog
assign load_use_hazard = id_ex_memread && 
                         ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));
```

When `load_use_hazard == 1`, the hardware automatically does three things for **1 clock cycle**:

1. **Freezes the Program Counter ($\text{PC}$)**: `pc_write_enable = 0`. The CPU doesn't fetch the next instruction.
2. **Freezes the `IF/ID` Pipeline Register**: `if_id_write_enable = 0`. The `add` instruction remains safely frozen in the Decode stage.
3. **Injects a "Bubble" (NOP) into the `ID/EX` Register**: `id_ex_flush = 1`. All control wires (`RegWrite`, `MemWrite`) are cleared to `0`. A harmless empty bubble floats down the pipeline!

After this 1-cycle pause, `lw` has advanced to the `MEM` stage. The loaded data is now available to be forwarded directly into the ALU input!

```
Cycle 1:  [lw IF]
Cycle 2:  [lw ID]   [add IF]
Cycle 3:  [lw EX]   [add ID]  <-- HAZARD DETECTED! FREEZE PC & IF/ID!
Cycle 4:  [lw MEM]  [BUBBLE]  [add ID (frozen)]
Cycle 5:  [lw WB]   [add EX]  <-- Forwarded from MEM/WB to EX! Execution continues!
```

---

## 5. Control Hazards: Branch Prediction & Flushes

When a branch instruction like `beq x1, x2, target` enters the pipeline, we don't know whether the branch is **Taken** (jump to target) or **Not Taken** (continue to $\text{PC}+4$) until the comparator in the **EX stage** evaluates the condition!

While the branch is in Decode and Execute, what should the Fetch stage do? If it stops and waits, we lose 2 clock cycles on *every single branch*!

### Strategy: Static Branch Prediction (Predict-Not-Taken)
- The processor assumes that the branch will **NOT be taken**.
- It aggressively fetches the next sequential instructions: $\text{PC}+4$, $\text{PC}+8$, etc.

### What Happens on a Misprediction (Branch is TAKEN)?
If the ALU evaluates the branch in the EX stage and determines that $x1 == x2$, our prediction was wrong!
The instructions that were fetched into `IF/ID` and `ID/EX` are invalid and must **never** be allowed to write their results or alter memory!

```
Misprediction Recovery Action:
1. Assert if_id_flush  = 1 (Clears IF/ID into a NOP)
2. Assert id_ex_flush   = 1 (Clears ID/EX into a NOP)
3. Update PC <= branch_target_address
```

The pipeline throws away the 2 incorrectly fetched instructions in a single clock cycle and redirects the $\text{PC}$ to the correct branch destination!

---

## Next Steps
Now that we have designed the complete 5-stage RV32I Core with full hazard recovery, we need to connect it to memory and peripherals using the industry-standard **AMBA AXI Bus**:
👉 [[01_AMBA_AXI4_Lite_Protocol_Deep_Dive|Proceed to Pillar 2: AMBA AXI4-Lite Protocol Deep Dive]]
