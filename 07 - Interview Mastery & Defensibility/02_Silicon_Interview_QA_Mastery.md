---
title: "Silicon Architecture & DV Technical Interview Master Guide"
tags:
 - interview
 - qa
 - apple
 - nvidia
 - arm
 - qualcomm
 - silicon
date_created: 2026-09-10
status: "Completed"
---

# Silicon Architecture & DV Technical Interview Master Guide

> [!NOTE] **The Real Interview Test**
> Having this project on your resume **guarantees** technical interview calls from Apple, NVIDIA, ARM, Qualcomm, AMD, and Intel.
> However, senior engineers will grill you on every wire, race condition, hazard, and class hierarchy. This guide provides the exact questions top silicon hiring managers ask—and the master-level answers that secure job offers.

---

## Part 1: RISC-V & Pipeline Microarchitecture

### Q1: Why did you choose a 5-stage pipeline instead of a 3-stage or 10-stage pipeline?
**Answer**:
A 5-stage pipeline (IF, ID, EX, MEM, WB) is the classic architectural sweet spot for RISC integer cores.
- A **single-cycle or 3-stage** core has long combinational paths (Instruction Memory fetch + ALU math + Data Memory access all in one cycle), which drags down the maximum clock frequency ($F_{\max}$).
- A **deep pipeline (10+ stages)** increases $F_{\max}$, but branch misprediction penalties skyrocket (wasting 8–10 cycles per flush) and hazard bypass networks become exponentially complex.
- The 5-stage pipeline cleanly balances combinational propagation delays across stages, keeping the pipeline stall penalty for load-use hazards to just 1 cycle and branch flush to 2 cycles, achieving near-ideal $\text{CPI} \approx 1$.

---

### Q2: What is the difference between Data Forwarding and a Pipeline Stall? When is a stall unavoidable?
**Answer**:
- **Forwarding (Bypassing)** routes calculation results from future pipeline registers (`EX/MEM` or `MEM/WB`) directly to the ALU inputs in the `EX` stage over dedicated multiplexers without pausing instruction flow ($\text{Penalty} = 0 \text{ cycles}$).
- A **Stall (Bubble)** pauses earlier pipeline stages by disabling the write enables of the $\text{PC}$ and `IF/ID` registers and injecting a `NOP` into `ID/EX` ($\text{Penalty} = 1 \text{ cycle}$).
- A stall is **unavoidable in a Load-Use Data Hazard**: when an instruction immediately depends on a value retrieved by a `LW` instruction. Because the loaded data only arrives from RAM at the end of the `MEM` stage, the data physically does not exist when the dependent instruction reaches the `EX` stage. The pipeline must insert a 1-cycle bubble before forwarding can supply the data.

---

### Q3: Why is register `x0` hardwired to 0 in RISC-V? What happens if an instruction attempts to write to `x0`?
**Answer**:
Hardwiring `x0` to zero eliminates the need for specialized instructions in the ISA:
- Moving data: `add rd, rs, x0`.
- Clearing a register: `add rd, x0, x0`.
- No-Operation (`NOP`): `addi x0, x0, 0` (encoded as `0x00000013`).
- In hardware, the register file decoder simply ignores any write where `rd == 5'b00000`, guaranteeing that `x0` can never be overwritten.

---

### Q4: How does your branch unit recover from a mispredicted branch?
**Answer**:
Our core uses static **Predict-Not-Taken** prediction (fetching $\text{PC}+4$). When a branch enters the `EX` stage and the comparator determines the condition is TRUE (branch taken):
1. The branch target address is sent to the Next-PC multiplexer.
2. Synchronous `flush` signals are asserted on the `IF/ID` and `ID/EX` pipeline registers.
3. On the next rising clock edge, both invalid instructions are cleared into `NOP`s, and the correct instruction at the branch target address is fetched.
The misprediction penalty is exactly 2 cycles.

---

## Part 2: AMBA AXI4-Lite Interconnect

### Q5: Can `AWREADY` wait for `AWVALID` before asserting, or can `AWVALID` wait for `AWREADY`?
**Answer**:
Under the ARM AMBA AXI specification:
- **`AWREADY` MAY wait for `AWVALID`**: A slave is fully permitted to wait until a master indicates a valid address is present before asserting its ready signal.
- **`AWVALID` MUST NEVER wait for `AWREADY`**: A master is strictly forbidden from waiting for a slave to assert ready before asserting valid.
- *Reason*: If both sides waited for the other to assert first, the system would enter a permanent **Deadlock**!

---

### Q6: What is the rule regarding signal stability after `VALID` is asserted?
**Answer**:
Once a master or slave asserts `VALID = 1`, it **MUST keep `VALID` high and keep all associated payload signals (address, data, byte strobes) completely constant** until the handshake occurs (`VALID && READY == 1`). A sender cannot "change its mind" or alter data while waiting for the receiver.

---

### Q7: What are the 4 AXI response status codes? How does your system handle `DECERR`?
**Answer**:
The 2-bit response codes (`BRESP` / `RRESP`) are:
1. `2'b00`: **`OKAY`** (Normal transfer successful).
2. `2'b01`: **`EXOKAY`** (Exclusive access successful - used in full AXI4).
3. `2'b10`: **`SLVERR`** (Slave error - peripheral accessed, but operation rejected).
4. `2'b11`: **`DECERR`** (Decode error - attempted access to an unmapped physical address).
In our interconnect crossbar, if an address does not match RAM (`< 0x2000_FFFF`) or Accelerator (`0x4000_0000 - 0x4000_07FF`), an internal default slave captures the transaction and returns `DECERR`. The CPU master bridges this into a load/store bus fault exception.

---

## Part 3: SystemVerilog & Assertions (SVA)

### Q8: What is a SystemVerilog Clocking Block, and what problem does it solve?
**Answer**:
A clocking block bundles synchronous signals and synchronizes their driving and sampling to a specific clock event (`@(posedge clk)`).
It solves **Verilog delta-cycle race conditions**:
- Using `default input #1step`, the testbench samples inputs in the **Preponed region** (just before the clock edge changes signals), guaranteeing stable, glitch-free values.
- Using `default output #1ns`, the testbench drives stimulus in the **Reactive region** with a small propagation delay, mimicking real silicon flip-flop setup/hold physical behavior.

---

### Q9: Explain the difference between overlapping (`|->`) and non-overlapping (`|=>`) implication in SVA.
**Answer**:
- **Overlapping (`|->`)**: The consequence is checked in the **exact same clock cycle** as the antecedent.
 - `(req) |-> (ack)` means: If `req` is high in cycle $N$, `ack` must also be high in cycle $N$.
- **Non-overlapping (`|=>`)**: The consequence is checked **1 clock cycle after** the antecedent (`##1`).
 - `(valid && !ready) |=> (valid)` means: If `valid` is high and `ready` is low in cycle $N$, `valid` must remain high in cycle $N+1$.

---

## Part 4: Universal Verification Methodology (UVM)

### Q10: Walk me through the UVM simulation phases. Which phase consumes simulation time?
**Answer**:
UVM phases execute in strict order:
1. `build_phase`: Constructs component instances top-down using `type_id::create`.
2. `connect_phase`: Connects TLM analysis ports and virtual interfaces bottom-up.
3. `end_of_elaboration_phase` & `start_of_simulation_phase`: Verification checks.
4. **`run_phase`**: The **ONLY** phase that consumes simulation time. It is declared as a SystemVerilog `task` (not a function), clocks advance, and stimuli are driven to the DUT.
5. `extract_phase`, `check_phase`, `report_phase`: Bottom-up functions that evaluate final scoreboard tallies and verify zero dropped packets.

---

### Q11: What is the purpose of the UVM Objection Mechanism?
**Answer**:
In UVM, the simulation will terminate at time 0 of `run_phase` unless an objection is raised.
- Before starting a sequence, the test calls `phase.raise_objection(this)`.
- The UVM engine keeps the simulation alive while objections are active.
- When all sequences complete and buffers are emptied, `phase.drop_objection(this)` is called.
- When the total objection count reaches zero (plus any drain time), UVM cleanly ends the `run_phase` and proceeds to the scoreboard check phase.

---

### Q12: Why did you use DPI-C for your Golden Reference Model instead of writing it in SystemVerilog?
**Answer**:
1. **Simulation Performance**: A pure C++ matrix multiplier compiles to native x86 machine instructions, executing millions of dot products orders of magnitude faster than interpreted SystemVerilog code.
2. **Algorithmic Portability**: Machine learning and DSP reference algorithms are authored by data scientists in Python or C++. Using **DPI-C**, we integrate the exact algorithmic reference model into the UVM scoreboard without re-writing and introducing human translation bugs in SystemVerilog.

---

## Part 5: Custom Compute Acceleration & Arithmetic

### Q13: What is Q8.8 fixed-point format? How do you prevent overflow when multiplying two Q8.8 numbers?
**Answer**:
Q8.8 is a 16-bit signed fixed-point format with 1 sign bit, 7 integer bits, and 8 fractional bits:
- Range: $[-128.0, +127.996]$ with resolution $2^{-8} \approx 0.0039$.
- When two Q8.8 numbers multiply:
 $$\text{Q8.8} \times \text{Q8.8} = \text{Q16.16 (32 bits!)}$$
- To convert back to Q8.8:
 1. We right-shift by 8 bits (`prod >> 8`).
 2. We apply **Saturation Arithmetic**: If the intermediate 32-bit value exceeds `+127.996` (`0x007F_FFFF`), we clamp the result to maximum positive `0x7FFF`. If it is less than `-128.0`, we clamp to `0x8000`. This prevents wrap-around inversion bugs (where a huge positive number becomes negative).

---

## Next Steps
Now review the architectural design trade-offs whitepaper to understand why specific design paths were chosen:
 [[03_Architecture_Tradeoffs_Whitepaper|Proceed to Architecture Trade-offs Whitepaper]]
