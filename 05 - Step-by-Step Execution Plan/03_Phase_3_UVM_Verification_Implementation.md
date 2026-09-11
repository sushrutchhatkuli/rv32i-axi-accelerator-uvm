---
title: "Phase 3 Execution Plan: Building the Production UVM Testbench"
tags:
  - execution-plan
  - phase-3
  - uvm
  - verification
  - methodology
  - dpi-c
date_created: 2026-09-10
status: "Completed"
---

# 📝 Phase 3 Execution Plan: Building the Production UVM Testbench

> [!IMPORTANT] **The Gold Standard Deliverable**
> This phase represents the skill set that commands **$150,000–$220,000+ starting compensation** in the semiconductor industry. You will build an automated, constrained-random **UVM (Universal Verification Methodology)** testbench conforming strictly to the **IEEE 1800.2** standard.

---

## 📁 Recommended Verification Directory Layout

```
verif/
├── tb/
│   ├── axi_if.sv              # Parameterized AXI interface with clocking blocks & SVA
│   └── tb_top.sv              # Top-level testbench module instantiating DUT and interfaces
├── seq/
│   ├── axi_seq_item.sv        # Constrained-random AXI transaction object
│   ├── axi_base_seq.sv        # Base UVM sequence
│   ├── axi_random_seq.sv      # Constrained-random traffic sequence
│   └── accel_stress_seq.sv    # Extreme corner-case matrix generator
├── agent/
│   ├── axi_sequencer.sv       # UVM Sequencer
│   ├── axi_driver.sv          # UVM Driver (drives virtual interface clocking block)
│   ├── axi_monitor.sv         # UVM Monitor (samples protocol & broadcasts via TLM)
│   └── axi_agent.sv           # UVM Agent (encapsulates sequencer, driver, monitor)
├── scb/
│   ├── golden_accel.cpp       # Pure C++ DPI mathematical reference model
│   └── soc_scoreboard.sv      # Scoreboard comparing DUT transactions vs. C++ golden truth
├── cov/
│   └── soc_coverage.sv        # Functional covergroups and cross-coverage subscriber
├── env/
│   └── soc_env.sv             # UVM Environment instantiating agent, scoreboard, coverage
└── tests/
    ├── soc_base_test.sv       # Base UVM test registering config_db
    └── accel_random_test.sv   # Constrained-random regression test
```

---

## 📅 Day-by-Day Implementation Roadmap

### Day 1–3: SystemVerilog Interfaces & Protocol Assertions (SVA)
- [ ] **Step 3.1**: Implement `axi_if.sv` using the code in [[02_SystemVerilog_Interfaces_and_SVA#1-systemverilog-parameterized-interface-axi_if|axi_if.sv]].
- [ ] **Step 3.2**: Add `clocking driver_cb` and `clocking monitor_cb` to completely isolate the testbench from Verilog delta-cycle races.
- [ ] **Step 3.3**: Embed concurrent SystemVerilog Assertions directly inside the interface:
  - `p_awvalid_held`: Verify `AWVALID` stays high until `AWREADY`.
  - `p_wdata_stable`: Verify `WDATA` does not change during wait states.
  - `p_no_x_control`: Verify no floating unknown states appear on bus control lines.

---

### Day 4–7: UVM Sequences, Driver & Monitor
- [ ] **Step 3.4**: Implement `axi_seq_item.sv` with random address alignment and backpressure latency constraints.
- [ ] **Step 3.5**: Implement `axi_driver.sv`:
  - Fetch transaction via `seq_item_port.get_next_item(req)`.
  - Drive `driver_cb` pins.
  - Signal completion with `seq_item_port.item_done()`.
- [ ] **Step 3.6**: Implement `axi_monitor.sv`:
  - Passively sample `monitor_cb` handshakes on every clock edge.
  - Construct completed `axi_seq_item` and write to `uvm_analysis_port`.
- [ ] **Step 3.7**: Bundle them inside `axi_agent.sv`.

---

### Day 8–10: C++ DPI Golden Predictor & Scoreboard
- [ ] **Step 3.8**: Implement `golden_accel.cpp` implementing the Q8.8 matrix multiplication algorithm with saturation logic from [[04_Scoreboard_and_DPI_C_Golden_Model#2-the-golden-c-reference-model-golden_accelcpp|golden_accel.cpp]].
- [ ] **Step 3.9**: Compile the C++ file using GCC into an object library:
  ```bash
  g++ -c -fPIC -I$SIM_HOME/include golden_accel.cpp -o golden_accel.o
  ```
- [ ] **Step 3.10**: Implement `soc_scoreboard.sv`:
  - Import the DPI-C function: `import "DPI-C" context function void golden_matrix_multiply_q8_8(...)`.
  - Compare hardware monitor transactions against the C++ predicted values.
  - Raise `uvm_error` upon any mismatch.

---

### Day 11–14: Functional Coverage Closure & Regression
- [ ] **Step 3.11**: Implement `soc_coverage.sv` containing the covergroups from [[05_Functional_Coverage_and_Closure#2-systemverilog-coverage-modeling-covergroups--bins|Functional Coverage]]:
  - Instruction opcodes coverpoint.
  - Pipeline hazards & forwarding paths coverpoint.
  - AXI backpressure latency bins ($0, 1, 2\text{--}5, >5$ cycles).
  - Matrix dimension and corner-case value bins (`0x0000`, `0x7FFF`, `0x8000`).
  - Cross-coverage: `branch_outcome` $\times$ `hazard_type`.
- [ ] **Step 3.12**: Assemble `soc_env.sv`, `soc_base_test.sv`, and `tb_top.sv`.
- [ ] **Step 3.13**: Run a regression of 1,000+ randomized seeds.
- [ ] **Step 3.14**: Generate coverage reports and verify that Functional Coverage reaches **100%**!

---

## 🏁 Phase 3 Verification Gate
Your Phase 3 is complete when:
1. The testbench runs 1,000+ randomized matrix computations without a single testbench freeze or deadlock.
2. The UVM Scoreboard reports:
   ```
   ================================================
     SCOREBOARD SUMMARY
     Transactions Checked : 16,000
     Mathematical Matches : 16,000
     Errors / Mismatches  : 0
     STATUS               : 100% TEST PASSED
   ================================================
   ```
3. SystemVerilog Assertion (SVA) violations = **0**.
4. Functional Coverage report shows **100.0% Coverage Achieved** across all covergroups and cross-bins!

---

## Next Steps
Now that the entire 3-phase execution roadmap is laid out, let's explore the **Toolchain Installation & Simulation Labs** so you can run everything on your machine:
👉 [[01_Toolchain_Setup_and_Installation|Proceed to Toolchain Setup & Installation]]
