---
title: "RISC-V RV32I Architecture & Instruction Set Specification"
tags:
 - riscv
 - rv32i
 - isa
 - instruction-set
 - microarchitecture
date_created: 2026-09-10
status: "Completed"
---

# RISC-V RV32I Architecture & ISA Specification

> [!NOTE] **What is an ISA?**
> An **Instruction Set Architecture (ISA)** is the sacred contract between software and hardware.
> - Software compilers (like GCC or LLVM) translate high-level C/C++ code into binary numbers defined by the ISA.
> - The hardware processor is an electronic engine built specifically to decode and execute those exact binary patterns.
> - **RISC-V** (pronounced "risk-five") is the world's leading open standard ISA, originating from UC Berkeley.

---

## 1. RISC vs. CISC: The Philosophical Foundation

To understand why RISC-V looks the way it does, compare it to Intel's x86:

| Attribute | CISC (Complex Instruction Set Computer, e.g. x86) | RISC (Reduced Instruction Set Computer, e.g. RISC-V, ARM) |
| :--- | :--- | :--- |
| **Philosophy** | "Provide one massive instruction for every complex job." | "Provide a small, razor-sharp set of simple instructions." |
| **Instruction Length** | Variable (1 to 15 bytes long). Hard to decode in hardware. | **Fixed 32 bits** (always exactly 4 bytes). Ultra-fast decode. |
| **Memory Operations** | Arithmetic instructions can directly read from RAM. | **Load/Store Architecture**: Math ONLY happens inside registers. To use RAM, you must explicitly Load and Store. |
| **Silicon Complexity** | Enormous, power-hungry decode logic. | Clean, highly pipelinable, power-efficient datapath. |

---

## 2. The Register File: The CPU's Scratchpad

The RV32I core has **32 general-purpose registers**, numbered `x0` through `x31`. Each register is **32 bits wide** (holds one 4-byte integer).

In software, programmers use standard **ABI (Application Binary Interface) names** for these registers:

| Register | ABI Name | Description | Preserved across function calls? |
| :--- | :--- | :--- | :---: |
| **`x0`** | **`zero`** | **Hardwired to constant 0**. Writes to `x0` are silently discarded! | N/A |
| **`x1`** | **`ra`** | Return Address (where a function returns to). | No |
| **`x2`** | **`sp`** | Stack Pointer (points to current top of memory stack). | **Yes** |
| **`x3`** | **`gp`** | Global Pointer (points to global variable base). | N/A |
| **`x4`** | **`tp`** | Thread Pointer (multi-threading). | N/A |
| **`x5` - `x7`** | **`t0` - `t2`** | Temporary registers (scratchpad math). | No |
| **`x8`** | **`s0` / `fp`** | Saved register / Frame Pointer. | **Yes** |
| **`x9`** | **`s1`** | Saved register. | **Yes** |
| **`x10` - `x11`** | **`a0` - `a1`** | Function Arguments / Return Values. | No |
| **`x12` - `x17`** | **`a2` - `a7`** | Function Arguments. | No |
| **`x18` - `x27`** | **`s2` - `s11`** | Saved registers (must be saved to stack before use). | **Yes** |
| **`x28` - `x31`** | **`t3` - `t6`** | Temporary registers. | No |
| **`pc`** | **`pc`** | **Program Counter**: Memory address of current instruction. | N/A |

> [!TIP] **Why is `x0` hardwired to Zero?**
> In hardware, having a permanent zero value simplifies everything:
> - Want to copy `x1` into `x2`? Just do `add x2, x1, x0` ($x2 = x1 + 0$).
> - Want a `NOP` (No Operation / do nothing)? Just do `addi x0, x0, 0` ($0 = 0 + 0$).
> - Want to set a register to zero? Just do `add x5, x0, x0`.
> You don't need dedicated silicon instructions for `COPY`, `CLEAR`, or `NOP`!

---

## 3. The 6 Standard RISC-V Instruction Formats

Every single instruction in RV32I is encoded in **exactly 32 bits** (Bit 31 down to Bit 0).
To make decoding blisteringly fast in silicon, the register addresses (`rs1`, `rs2`, `rd`) are placed at the **exact same bit positions** across all formats!

```
 31 25 24 20 19 15 14 12 11 7 6 0
+------------+------------+------------+------+------------+--------------+
| funct7 | rs2 | rs1 |funct3| rd | opcode | R-type
+------------+------------+------------+------+------------+--------------+
| imm[11:0] | rs1 |funct3| rd | opcode | I-type
+------------+------------+------------+------+------------+--------------+
| imm[11:5] | rs2 | rs1 |funct3| imm[4:0] | opcode | S-type
+------------+------------+------------+------+------------+--------------+
| imm[12|10:5] | rs2 | rs1 |funct3|imm[4:1|11] | opcode | B-type
+------------+------------+------------+------+------------+--------------+
| imm[31:12] | rd | opcode | U-type
+------------+------------+------------+------+------------+--------------+
| imm[20|10:1|11|19:12] | rd | opcode | J-type
+---------------------------------------------+------------+--------------+
```

### Explanation of Fields:
- **`opcode` (7 bits, [6:0])**: Identifies the major operation category (e.g. ALU register math, Immediate math, Load, Store, Branch).
- **`rd` (5 bits, [11:7])**: **Destination Register** (`x0` through `x31`) where the result of the calculation is written.
- **`funct3` (3 bits, [14:12])**: Sub-category selector (e.g. distinguishes `ADD` from `SLL` from `SLT`).
- **`rs1` (5 bits, [19:15])**: **Source Register 1** (first operand).
- **`rs2` (5 bits, [24:20])**: **Source Register 2** (second operand).
- **`funct7` (7 bits, [31:25])**: Additional selector (e.g. distinguishes `ADD` from `SUB` or `SRL` from `SRA`).
- **`imm` (Immediate)**: A constant numerical value embedded directly inside the instruction code itself!

---

## 4. Complete RV32I Instruction Catalog

### A. R-Type (Register-to-Register Arithmetic & Logic)
Takes two source registers (`rs1`, `rs2`), performs an operation, and stores the result into `rd`.
$$rd \leftarrow rs1 \text{ OP } rs2$$

| Instruction | Name | funct7 | funct3 | opcode | Operation |
| :--- | :--- | :---: | :---: | :---: | :--- |
| `add rd, rs1, rs2` | Add | `0000000` | `000` | `0110011` | $rd = rs1 + rs2$ |
| `sub rd, rs1, rs2` | Subtract | `0100000` | `000` | `0110011` | $rd = rs1 - rs2$ |
| `sll rd, rs1, rs2` | Shift Left Logical | `0000000` | `001` | `0110011` | $rd = rs1 \ll rs2[4:0]$ |
| `slt rd, rs1, rs2` | Set Less Than (Signed) | `0000000` | `010` | `0110011` | $rd = (rs1 <_{signed} rs2) \text{ ? } 1 : 0$ |
| `sltu rd, rs1, rs2`| Set Less Than Unsigned | `0000000` | `011` | `0110011` | $rd = (rs1 <_{unsigned} rs2) \text{ ? } 1 : 0$ |
| `xor rd, rs1, rs2` | Bitwise XOR | `0000000` | `100` | `0110011` | $rd = rs1 \oplus rs2$ |
| `srl rd, rs1, rs2` | Shift Right Logical | `0000000` | `101` | `0110011` | $rd = rs1 \gg rs2[4:0]$ (zero fill) |
| `sra rd, rs1, rs2` | Shift Right Arithmetic | `0100000` | `101` | `0110011` | $rd = rs1 \gg rs2[4:0]$ (sign extend) |
| `or rd, rs1, rs2` | Bitwise OR | `0000000` | `110` | `0110011` | $rd = rs1 \mid rs2$ |
| `and rd, rs1, rs2` | Bitwise AND | `0000000` | `111` | `0110011` | $rd = rs1 \ \& \ rs2$ |

---

### B. I-Type (Immediate Arithmetic & Loads)
Uses a constant 12-bit signed immediate value: $imm \in [-2048, +2047]$.
$$rd \leftarrow rs1 \text{ OP } \text{SignExtend}(imm)$$

| Instruction | Name | funct3 | opcode | Operation |
| :--- | :--- | :---: | :---: | :--- |
| `addi rd, rs1, imm` | Add Immediate | `000` | `0010011` | $rd = rs1 + imm$ |
| `slti rd, rs1, imm` | Set Less Than Imm | `010` | `0010011` | $rd = (rs1 <_{signed} imm) \text{ ? } 1 : 0$ |
| `sltiu rd, rs1, imm`| Set Less Than Imm Unsigned | `011` | `0010011` | $rd = (rs1 <_{unsigned} imm) \text{ ? } 1 : 0$ |
| `xori rd, rs1, imm` | Bitwise XOR Imm | `100` | `0010011` | $rd = rs1 \oplus imm$ |
| `ori rd, rs1, imm` | Bitwise OR Imm | `110` | `0010011` | $rd = rs1 \mid imm$ |
| `andi rd, rs1, imm` | Bitwise AND Imm | `111` | `0010011` | $rd = rs1 \ \& \ imm$ |
| `slli rd, rs1, shamt`| Shift Left Logical Imm | `001` | `0010011` | $rd = rs1 \ll shamt$ |
| `srli rd, rs1, shamt`| Shift Right Logical Imm| `101` | `0010011` | $rd = rs1 \gg shamt$ |
| `srai rd, rs1, shamt`| Shift Right Arith Imm | `101` | `0010011` | $rd = rs1 \gg shamt$ (sign filled) |

#### Load Instructions (Reading from Memory):
Target Address is calculated as $\text{Effective Address} = rs1 + \text{SignExtend}(imm)$.
- `lw rd, offset(rs1)`: **Load Word** (32 bits / 4 bytes).
- `lh rd, offset(rs1)`: **Load Halfword** (16 bits, sign-extended to 32 bits).
- `lhu rd, offset(rs1)`: **Load Halfword Unsigned** (16 bits, zero-extended to 32 bits).
- `lb rd, offset(rs1)`: **Load Byte** (8 bits, sign-extended to 32 bits).
- `lbu rd, offset(rs1)`: **Load Byte Unsigned** (8 bits, zero-extended to 32 bits).

---

### C. S-Type (Stores: Writing to Memory)
Writes the value in `rs2` into the memory address pointed to by $rs1 + \text{SignExtend}(imm)$.
Notice there is no `rd` register because stores write to RAM, not registers!
- `sw rs2, offset(rs1)`: **Store Word** (writes 32 bits).
- `sh rs2, offset(rs1)`: **Store Halfword** (writes lower 16 bits).
- `sb rs2, offset(rs1)`: **Store Byte** (writes lower 8 bits).

---

### D. B-Type (Conditional Branches)
Compares `rs1` and `rs2`. If the condition is true, jumps by adding the 12-bit signed offset to the $\text{PC}$:
$$\text{If Condition True: } \text{PC} \leftarrow \text{PC} + \text{SignExtend}(imm \ll 1)$$
- `beq rs1, rs2, label`: Branch if Equal ($rs1 == rs2$).
- `bne rs1, rs2, label`: Branch if Not Equal ($rs1 \neq rs2$).
- `blt rs1, rs2, label`: Branch if Less Than (Signed: $rs1 < rs2$).
- `bge rs1, rs2, label`: Branch if Greater/Equal (Signed: $rs1 \ge rs2$).
- `bltu rs1, rs2, label`: Branch if Less Than (Unsigned).
- `bgeu rs1, rs2, label`: Branch if Greater/Equal (Unsigned).

---

### E. U-Type (Upper Immediate)
Handles large 20-bit numerical constants loaded into the upper 20 bits of a register.
- `lui rd, imm`: **Load Upper Immediate**. $rd = imm[31:12] \ll 12$.
- `auipc rd, imm`: **Add Upper Immediate to PC**. $rd = \text{PC} + (imm[31:12] \ll 12)$. Critical for position-independent code!

---

### F. J-Type (Unconditional Jump & Link)
Used for function calls and loops:
- `jal rd, offset`: **Jump and Link**. Stores the return address ($\text{PC} + 4$) into register `rd` (usually `ra`), and sets $\text{PC} \leftarrow \text{PC} + offset$.
- `jalr rd, offset(rs1)`: **Jump and Link Register** (I-type opcode). Jumps to an absolute address in a register: $\text{PC} \leftarrow (rs1 + offset) \ \& \ \sim 1$.

---

## 5. Immediate Generation Logic (ImmGen)

In hardware, the Immediate Generator takes the raw 32-bit instruction `instr[31:0]` and assembles the correct sign-extended 32-bit immediate value:

```systemverilog
always_comb begin
 case (opcode)
 7'b0010011, 7'b0000011, 7'b1100111: // I-Type (ALUi, Load, JALR)
 imm_ext = {{20{instr[31]}}, instr[31:20]};
 
 7'b0100011: // S-Type (Store)
 imm_ext = {{20{instr[31]}}, instr[31:25], instr[11:7]};
 
 7'b1100011: // B-Type (Branch)
 imm_ext = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
 
 7'b0110111, 7'b0010111: // U-Type (LUI, AUIPC)
 imm_ext = {instr[31:12], 12'b0};
 
 7'b1101111: // J-Type (JAL)
 imm_ext = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
 
 default: imm_ext = 32'b0;
 endcase
end
```

---

## Next Steps
Now that we know the instruction language, let's see how the hardware pipeline executes these instructions cycle by cycle:
 [[02_Five_Stage_Pipelined_Core|Proceed to the 5-Stage Pipelined Datapath]]
