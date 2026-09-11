---
title: "Custom Compute Accelerator Concepts & Fixed-Point Mathematics"
tags:
  - accelerator
  - dsa
  - matrix-multiplication
  - fixed-point
  - math
  - edge-ai
date_created: 2026-09-10
status: "Completed"
---

# 🧮 Custom Compute Accelerator Concepts & Fixed-Point Mathematics

> [!NOTE] **The Rise of Domain-Specific Silicon (DSA)**
> For 40 years, general-purpose CPUs got twice as fast every 18 months (Moore's Law & Dennard Scaling). That era is dead. Today, modern computing power comes from **Domain-Specific Hardware Accelerators**—custom silicon circuits tailored to do **one specific math operation** at superhuman speed with negligible power consumption (like Apple's Neural Engine, Google's TPU, or NVIDIA's Tensor Cores).

---

## 1. The Math of AI & DSP: Matrix Multiplication

Whether you are running a Large Language Model (like GPT), recognizing a face on an iPhone, or filtering noise from a 5G radio signal, **over 90% of the computation is Matrix Multiplication**.

### What is a Matrix?
A matrix is simply a grid of numbers organized into rows and columns:

$$A = \begin{bmatrix} a_{11} & a_{12} \\ a_{21} & a_{22} \end{bmatrix}, \quad B = \begin{bmatrix} b_{11} & b_{12} \\ b_{21} & b_{22} \end{bmatrix}$$

To multiply two matrices $C = A \times B$:
Every item in the result matrix $C$ is computed by taking a **Row from Matrix A**, taking a **Column from Matrix B**, multiplying matching pairs of numbers, and adding them all up! This is called a **Dot Product (Multiply-Accumulate / MAC)**:

$$C_{ij} = \sum_{k=1}^{N} A_{ik} \times B_{kj}$$

For example, the top-left cell of $C$:
$$C_{11} = (a_{11} \times b_{11}) + (a_{12} \times b_{21})$$

### Why CPUs are Terrible at This:
To multiply two $4 \times 4$ matrices on a CPU:
- The CPU must execute three nested loops: `for i`, `for j`, `for k`.
- For each step: load $A$ from memory, load $B$ from memory, branch loop counter, increment pointer, multiply, add, store.
- A standard RISC CPU burns over **300 instructions** just to calculate 16 numbers!

### Why Our Hardware Accelerator is Brilliant:
Our custom accelerator features **dedicated parallel Multiply-Accumulate (MAC) hardware units**. We feed entire rows and columns simultaneously. The multipliers and adders perform all calculations directly in hardware over a handful of clock cycles!

---

## 2. Number Representation: Fixed-Point Arithmetic (Q8.8)

In software on a laptop, numbers with decimals (like $3.14159$) are stored as **IEEE-754 32-bit Floating-Point (`float`)**.

### Why Not Floating-Point in Hardware?
- A 32-bit floating-point multiplier requires thousands of logic gates to normalize mantissas, align exponents, handle NaN/Infinity, and round bits.
- It consumes huge silicon area and high thermal power—unacceptable for mobile, automotive, or edge-AI chips.

### The Solution: Fixed-Point Format (Q8.8)
Instead of a floating decimal point, we fix the position of the decimal point permanently in hardware!

In **Q8.8 format**:
- Total Width: **16 bits**
- Bit 15: **Sign Bit** ($0 = \text{Positive}$, $1 = \text{Negative}$)
- Bits [14:8]: **7 Integer Bits** (representing integer values from $0$ to $127$)
- Bits [7:0]: **8 Fractional Bits** (representing binary fractions)

```
Bit:   15   14  13  12  11  10   9   8  .   7     6     5     4     3     2     1     0
      [ S |        Integer Part       ] . [              Fractional Part               ]
Sign: -2^7  2^6 2^5 2^4 2^3 2^2 2^1 2^0 . 2^-1  2^-2  2^-3  2^-4  2^-5  2^-6  2^-7  2^-8
                                        . (0.5)(0.25)(0.125)...
```

### Numerical Examples:

1. **The Number `+1.0`**:
   - Integer = $1$ (`0000001`), Fractional = $0$ (`00000000`)
   - Binary: `0000_0001_0000_0000` = **`0x0100`** (which is decimal 256).

2. **The Number `+2.5`**:
   - Integer = $2$ (`0000010`), Fractional = $0.5$ ($2^{-1} = \text{Bit 7 is 1}$)
   - Binary: `0000_0010_1000_0000` = **`0x0280`**.

3. **The Number `-1.0`** (Two's Complement):
   - Invert bits and add 1: **`0xFF00`**.

---

## 3. How Hardware Multiplies Q8.8 Fixed-Point Numbers

When you multiply two 16-bit Q8.8 numbers in hardware:
$$\text{Q8.8} \times \text{Q8.8} = \text{Q16.16 (32 bits!)}$$

- The result has **16 integer bits** and **16 fractional bits**.
- To store the result back into our standard 16-bit Q8.8 register, we must convert Q16.16 back to Q8.8:
  1. We **shift right by 8 bits** (`>> 8`) to truncate the lower 8 bits of extra fractional precision.
  2. We inspect the upper bits for **Saturation / Overflow**. If the number grew larger than $+127.99$ or smaller than $-128.0$, we clamp (saturate) it to the maximum allowable value instead of letting it wrap around!

```systemverilog
// 16-bit Q8.8 Signed Multiplication with Saturation
logic signed [15:0] a_q8_8, b_q8_8;
logic signed [31:0] raw_product;
logic signed [15:0] result_q8_8;

assign raw_product = a_q8_8 * b_q8_8; // 32-bit Q16.16 product

always_comb begin
    // Check for positive overflow (exceeds max Q8.8: +127.996 = 0x7FFF)
    if (raw_product > 32'sh007F_FFFF) begin
        result_q8_8 = 16'sh7FFF;
    // Check for negative overflow (below min Q8.8: -128.0 = 0x8000)
    end else if (raw_product < -32'sh0080_0000) begin
        result_q8_8 = 16'sh8000;
    // Normal case: truncate lower 8 fractional bits
    end else begin
        result_q8_8 = raw_product[23:8];
    end
end
```

---

## Next Steps
Now that the mathematics and numerical precision are established, let's look at the hardware datapath, register map, and finite state machine of the accelerator:
👉 [[02_Accelerator_Datapath_and_FSM|Proceed to Accelerator Datapath, CSR Registers & FSM]]
