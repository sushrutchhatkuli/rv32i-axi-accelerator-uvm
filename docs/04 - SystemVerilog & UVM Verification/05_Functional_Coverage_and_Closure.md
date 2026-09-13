---
title: "Functional Coverage, Cross-Coverage, and Verification Closure"
tags:
 - coverage
 - functional-coverage
 - covergroup
 - cross-coverage
 - verification-closure
date_created: 2026-09-10
status: "Completed"
---

# Functional Coverage, Cross-Coverage, and Verification Closure

> [!IMPORTANT] **How Silicon Directors Decide to "Tape Out" (Send to Manufacturing)**
> An executive director at Apple or Qualcomm will **never** sign off on manufacturing a $20M chip just because you ran tests for 10 hours without an error.
> They demand mathematical proof of **Verification Closure**:
> 1. Did we test every instruction?
> 2. Did we trigger every hazard?
> 3. Did we hit every backpressure state on the bus?
> **Functional Coverage** is the quantitative scorecard that proves all features were exercised.

---

## 1. Code Coverage vs. Functional Coverage

| Metric | What it Measures | Analogy |
| :--- | :--- | :--- |
| **Code Coverage** (Line, Branch, Toggle, FSM) | Did the simulator execute line 42 of your Verilog code? | Reading every word in a flight manual. (Doesn't mean you know how to fly a plane in a thunderstorm!) |
| **Functional Coverage** (User-defined specifications) | Did the chip experience a Load-Use stall *while* receiving an AXI backpressure delay during a saturated matrix multiply? | Successfully landing a plane in a Category 5 hurricane with one engine failed. |

---

## 2. SystemVerilog Coverage Modeling: Covergroups & Bins

A **`covergroup`** defines what specific data values and scenarios we want to observe during simulation:

### Covergroup 1: RISC-V Pipeline Hazards & Branch Outcomes
```systemverilog
covergroup cg_pipeline_hazards @(posedge clk);
 // 1. Coverpoint: Types of Data Forwarding
 cp_forward_a: coverpoint dut.forward_a {
 bins no_forward = {2'b00};
 bins fwd_ex_mem = {2'b10}; // Forward from immediately preceding ALU op
 bins fwd_mem_wb = {2'b01}; // Forward from 2 instructions ago
 }

 // 2. Coverpoint: Load-Use Hazard Stalls
 cp_load_use_stall: coverpoint dut.hazard_unit.load_use_hazard {
 bins no_stall = {1'b0};
 bins stall_injected = {1'b1}; // Proves the 1-cycle bubble was exercised!
 }

 // 3. Coverpoint: Branch Decisions
 cp_branch_outcome: coverpoint dut.branch_taken {
 bins not_taken = {1'b0}; // Predict-not-taken was correct
 bins mispredicted = {1'b1}; // Mispredicted! Pipeline flush executed!
 }

 // 4. CROSS-COVERAGE: Test a branch misprediction WHILE a forward occurs!
 cross_branch_hazard: cross cp_forward_a, cp_branch_outcome;
endgroup
```

---

### Covergroup 2: AMBA AXI Interconnect Handshake Latency
```systemverilog
covergroup cg_axi_protocol @(posedge clk);
 // Measure how many cycles the slave kept READY low (Backpressure)
 cp_awready_latency: coverpoint axi_vif.awready_delay {
 bins zero_delay = {0};
 bins short_delay = {[1:2]};
 bins medium_delay = {[3:5]};
 bins extreme_backpressure = {[6:15]};
 }

 // Ensure all byte enables were exercised (Byte, Halfword, Word stores)
 cp_wstrb: coverpoint axi_vif.wstrb {
 bins byte_0 = {4'b0001};
 bins byte_1 = {4'b0010};
 bins half_0 = {4'b0011};
 bins half_1 = {4'b1100};
 bins full_word = {4'b1111};
 }

 // Response codes
 cp_resp: coverpoint axi_vif.bresp {
 bins okay = {2'b00};
 bins slverr = {2'b10};
 bins decerr = {2'b11}; // Proves unmapped memory access was tested!
 }
endgroup
```

---

### Covergroup 3: Custom Compute Accelerator Corner Cases
```systemverilog
covergroup cg_accel_math @(posedge clk);
 // Matrix dimensions tested
 cp_dim: coverpoint accel_vif.dim {
 bins dim_1x1 = {1};
 bins dim_2x2 = {2};
 bins dim_4x4 = {4};
 }

 // Input data value corner cases
 cp_matrix_values: coverpoint accel_vif.current_operand {
 bins zero = {16'h0000};
 bins positive_max = {16'h7FFF}; // Maximum positive Q8.8 (+127.996)
 bins negative_max = {16'h8000}; // Maximum negative Q8.8 (-128.0)
 bins normal_range = default;
 }

 // Saturation arithmetic flag
 cp_overflow: coverpoint accel_vif.status_overflow {
 bins no_overflow = {1'b0};
 bins saturated = {1'b1}; // Proves saturation logic was triggered!
 }
endgroup
```

---

## 3. The Definition of 100% Verification Closure

To achieve **Tapeout Approval**, your regression suite must hit:
1. **100% Functional Coverage** (Every bin in all covergroups sampled at least once).
2. **100% SVA Assertion Cleanliness** (Zero protocol violations across 100,000 randomized transactions).
3. **100% Scoreboard Match Rate** (Zero mathematical mismatches against the C++ DPI golden model).
4. **>95% Code Coverage** (Statement, Branch, Condition, and Toggle).

---

## Next Steps
Now that the entire architecture and verification environment are fully specified, let's look at the **Step-by-Step Execution Plan** to build this project from scratch:
 [[01_Phase_1_RISCV_Core_Implementation|Proceed to Phase 1 Execution: Building the RV32I Core]]
