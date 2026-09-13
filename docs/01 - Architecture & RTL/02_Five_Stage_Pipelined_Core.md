---
title: "The 5-Stage Pipelined RISC-V Datapath Microarchitecture"
tags:
 - riscv
 - pipeline
 - datapath
 - microarchitecture
 - systemverilog
date_created: 2026-09-10
status: "Completed"
---

# The 5-Stage Pipelined RISC-V Datapath Microarchitecture

> [!TIP] **The Core Intuition: The Automobile Assembly Line**
> If one worker built an entire car from start to finish alone, building a car would take 5 days.
> In an assembly line:
> - Station 1 welds the chassis.
> - Station 2 drops in the engine.
> - Station 3 attaches doors and windows.
> - Station 4 installs the interior and electronics.
> - Station 5 paints and inspects the car.
>
> While Car #5 is being painted, Car #4 is getting its interior, Car #3 is getting doors, Car #2 is getting an engine, and Car #1 is having its chassis welded. Once the assembly line is full, **one completed car rolls off the line every single day**!

---

## 1. High-Level 5-Stage Pipeline Overview

```
+-------------+ +-------------+ +-------------+ +-------------+ +-------------+
| IF | | ID | | EX | | MEM | | WB |
| Instruction | --> | Instruction | --> | Execute | --> | Memory | --> | Writeback |
| Fetch | | Decode | | | | Access | | |
+-------------+ +-------------+ +-------------+ +-------------+ +-------------+
 | | | | |
 [ IF/ID Reg ] [ ID/EX Reg ] [ EX/MEM Reg ] [ MEM/WB Reg ] v
 RegFile[rd]
```

At every rising clock edge (`posedge clk`), the intermediate answers are captured into **Pipeline Registers** (`IF_ID`, `ID_EX`, `EX_MEM`, `MEM_WB`).

---

## 2. Deep Dive: The 5 Pipeline Stages

### Stage 1: Instruction Fetch (IF)
- **Objective**: Retrieve the 32-bit instruction from memory and determine the address of the next instruction.
- **Hardware Elements**:
 1. **Program Counter ($\text{PC}$ Register)**: Holds the current instruction's byte address.
 2. **$\text{PC} + 4$ Adder**: In RV32I, each instruction is 4 bytes (32 bits), so standard execution increments $\text{PC} \leftarrow \text{PC} + 4$.
 3. **Next-PC Multiplexer**: Selects between $\text{PC} + 4$ (normal sequential execution) or the Target Address (if a Branch or Jump was taken).
 4. **Instruction Memory (I-Mem)**: High-speed SRAM providing the 32-bit `instr` word.

---

### Stage 2: Instruction Decode & Register Fetch (ID)
- **Objective**: Break down the 32-bit instruction, figure out what operation to perform, generate the immediate value, and read the operands from the register file.
- **Hardware Elements**:
 1. **Register File ($32 \times 32$-bit)**:
 - Two read ports: `rs1_addr` (bits [19:15]) and `rs2_addr` (bits [24:20]). Outputs `rs1_data` and `rs2_data` combinatorially.
 - One write port: `rd_addr` (bits [11:7]) and `rd_data` (active only during WB stage).
 - Register `x0` is hardwired to zero.
 2. **Immediate Generator (ImmGen)**: Reconstructs 32-bit sign-extended immediate values from instruction fields (see [[01_RISCV_RV32I_Architecture#5-immediate-generation-logic-immgen|ImmGen]]).
 3. **Main Control Unit**: Reads `opcode`, `funct3`, and `funct7` to generate all pipeline control signals:
 - `RegWrite`: Will this instruction write a result back to a register?
 - `MemRead` / `MemWrite`: Does this instruction access data memory?
 - `ALUSrc`: Does the second ALU input come from register `rs2` or the immediate value?
 - `Branch` / `Jump`: Is this a control-flow change?

---

### Stage 3: Execute & Address Calculation (EX)
- **Objective**: Perform the actual mathematical computation or calculate the effective memory address.
- **Hardware Elements**:
 1. **ALU (Arithmetic Logic Unit)**:
 - Input A: Operand 1 (usually `rs1_data` or forwarded data).
 - Input B: Operand 2 (selected by `ALUSrc` mux between `rs2_data` or `imm_ext`).
 - Performs addition, subtraction, bitwise logic, or shifts based on `ALUControl`.
 2. **Branch Target Adder**: Calculates $\text{Branch Target} = \text{PC}_{\text{EX}} + imm_{\text{ext}}$.
 3. **Branch Condition Comparator**: Compares operands to check if conditions like `rs1 == rs2` (`BEQ`) or `rs1 < rs2` (`BLT`) are satisfied.
 4. **Forwarding Multiplexers**: Selects whether ALU inputs come from the ID/EX register or are bypassed directly from EX/MEM or MEM/WB stages!

---

### Stage 4: Memory Access (MEM)
- **Objective**: Read from or write to the Data RAM (for Load and Store instructions) or Memory-Mapped I/O.
- **Hardware Elements**:
 1. **Data Memory Interface**:
 - `MemWrite` asserted: Writes `rs2_data` to memory at address `ALU_Result`.
 - `MemRead` asserted: Reads 32-bit data from `ALU_Result` and presents it on `ReadData`.
 - Byte enable logic (`wstrb`) handles byte (`SB`) and halfword (`SH`) stores.
 2. For non-memory instructions (like `ADD` or `SUB`), this stage does nothing except pass the `ALU_Result` through to the next pipeline register.

---

### Stage 5: Writeback (WB)
- **Objective**: Write the final calculation result back into the Register File at address `rd`.
- **Hardware Elements**:
 1. **Result Mux**: Selects which value is written to register `rd`:
 - ResultSrc = 00: `ALU_Result` (for normal arithmetic).
 - ResultSrc = 01: `ReadData` (for load instructions like `LW`).
 - ResultSrc = 10: $\text{PC} + 4$ (for jump instructions like `JAL`, storing return address).
 2. **RegFile Write Port**: When `RegWrite` is asserted and $rd \neq 0$, the chosen value is locked into register `rd` on the clock edge.

---

## 3. The Pipeline Registers: What Travels Down the Pipe?

Between each stage sits a synchronous pipeline register that latches data on every `posedge clk`.

```
Stage IF ----> [ IF/ID Register ]
 - PC
 - Instruction (instr)

Stage ID ----> [ ID/EX Register ]
 - PC
 - rs1_data, rs2_data
 - imm_ext
 - rs1_addr, rs2_addr, rd_addr
 - Control Signals (RegWrite, MemRead, MemWrite, ALUSrc, ALUOp, Branch, Jump)

Stage EX ----> [ EX/MEM Register ]
 - ALU_Result
 - WriteData (rs2_data forwarded)
 - rd_addr
 - Branch_Target, Zero_flag
 - Control Signals (RegWrite, MemRead, MemWrite, ResultSrc)

Stage MEM ---> [ MEM/WB Register ]
 - ALU_Result
 - ReadData (from RAM)
 - rd_addr
 - Control Signals (RegWrite, ResultSrc)
```

---

## 4. Main Control Unit Truth Table

The Control Unit in the Decode stage inspects `opcode[6:0]` and outputs the following control bus:

| Instruction Type | Opcode | RegWrite | ALUSrc | MemRead | MemWrite | Branch | Jump | ALUOp | ResultSrc |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **R-Type** (`add, sub`) | `0110011` | **1** | 0 (rs2) | 0 | 0 | 0 | 0 | `10` (R-type) | 00 (ALU) |
| **I-Type ALU** (`addi`) | `0010011` | **1** | 1 (Imm) | 0 | 0 | 0 | 0 | `10` (I-type) | 00 (ALU) |
| **Load** (`lw`) | `0000011` | **1** | 1 (Imm) | **1** | 0 | 0 | 0 | `00` (Add) | 01 (Mem) |
| **Store** (`sw`) | `0100011` | 0 | 1 (Imm) | 0 | **1** | 0 | 0 | `00` (Add) | xx |
| **Branch** (`beq, bne`)| `1100011` | 0 | 0 (rs2) | 0 | 0 | **1** | 0 | `01` (Branch)| xx |
| **JAL** (Jump & Link) | `1101111` | **1** | x | 0 | 0 | 0 | **1** | `xx` | 10 (PC+4) |
| **LUI** | `0110111` | **1** | 1 (Imm) | 0 | 0 | 0 | 0 | `11` (Pass B) | 00 (ALU) |

---

## 5. SystemVerilog Implementation Snapshot

Here is the clean, synthesizable SystemVerilog implementation of the `IF/ID` pipeline register with synchronous enable (for stalling) and clear (for branch flushing):

```systemverilog
module if_id_reg (
 input logic clk,
 input logic rst_n,
 input logic stall, // Hazard unit stalls pipeline
 input logic flush, // Branch misprediction flushes stage
 input logic [31:0] if_pc,
 input logic [31:0] if_instr,
 output logic [31:0] id_pc,
 output logic [31:0] id_instr
);

 always_ff @(posedge clk or negedge rst_n) begin
 if (!rst_n) begin
 id_pc <= 32'b0;
 id_instr <= 32'h0000_0013; // NOP (addi x0, x0, 0)
 end else if (flush) begin
 id_pc <= 32'b0;
 id_instr <= 32'h0000_0013; // Inject NOP bubble
 end else if (!stall) begin
 id_pc <= if_pc;
 id_instr <= if_instr; // Normal pipeline advance
 end
 // If stall is 1, register holds previous values (freezes)!
 end

endmodule
```

---

## Next Steps
In an ideal pipeline, every stage takes 1 clock cycle. But what happens if an instruction needs an answer that the previous instruction hasn't finished calculating yet?
 [[03_Hazards_Forwarding_and_Branch_Prediction|Proceed to Hazard Detection, Forwarding & Branch Prediction]]
