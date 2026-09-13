---
title: "UVM Scoreboard & C++ DPI Golden Reference Model"
tags:
 - scoreboard
 - dpi-c
 - golden-model
 - uvm
 - reference-predictor
date_created: 2026-09-10
status: "Completed"
---

# UVM Scoreboard & C++ DPI Golden Reference Model

> [!TIP] **How Do You Know the Math is Actually Correct?**
> A chip might execute transactions on the bus with zero timing errors, but still produce completely garbage mathematical results (e.g. $2 \times 2 = 5$).
> In high-level verification, the **Scoreboard** acts as an impartial supreme court judge:
> 1. It records every input matrix sent to the chip.
> 2. It sends that same data to an independent **Golden Reference Model** written in pure C++.
> 3. It compares the hardware's output against the C++ output bit-for-bit.

---

## 1. Why SystemVerilog DPI-C (Direct Programming Interface)?

Why write the reference model in C++ instead of SystemVerilog?
- **Speed**: Pure C++ compiles to native machine code. It can calculate 100,000 matrix multiplications in milliseconds.
- **Algorithm Reuse**: In companies like NVIDIA and Apple, AI algorithms are originally designed in Python (PyTorch) and ported to C++. Using **DPI-C**, verification engineers plug the exact same reference code directly into the SystemVerilog testbench!

---

## 2. The Golden C++ Reference Model (`golden_accel.cpp`)

Here is the exact C++ reference model that replicates our accelerator's 16-bit Q8.8 fixed-point arithmetic, including saturation logic:

```cpp
#include <stdint.h>
#include <svdpi.h>

extern "C" void golden_matrix_multiply_q8_8(
 const int16_t* mat_a, 
 const int16_t* mat_b, 
 int16_t* mat_c, 
 int dim
) {
 for (int i = 0; i < dim; i++) {
 for (int j = 0; j < dim; j++) {
 int32_t accumulator = 0;

 for (int k = 0; k < dim; k++) {
 int16_t a_val = mat_a[i * dim + k];
 int16_t b_val = mat_b[k * dim + j];

 // 16-bit x 16-bit = 32-bit product (Q16.16)
 int32_t prod = (int32_t)a_val * (int32_t)b_val;

 // Shift right by 8 to restore Q8.8 fractional alignment
 accumulator += (prod >> 8);
 }

 // Saturation logic (Clamping to Q8.8 range [-32768, 32767])
 if (accumulator > 32767) {
 mat_c[i * dim + j] = 32767;
 } else if (accumulator < -32768) {
 mat_c[i * dim + j] = -32768;
 } else {
 mat_c[i * dim + j] = (int16_t)accumulator;
 }
 }
 }
}
```

---

## 3. Importing C++ into SystemVerilog via DPI-C

In your SystemVerilog package, you bind the C function with a single line:

```systemverilog
package soc_pkg;
 import uvm_pkg::*;
 `include "uvm_macros.svh"

 // DPI-C Import Declaration
 import "DPI-C" context function void golden_matrix_multiply_q8_8(
 input shortint mat_a[],
 input shortint mat_b[],
 output shortint mat_c[],
 input int dim
 );
endpackage
```

---

## 4. The UVM Scoreboard Implementation (`soc_scoreboard.sv`)

```systemverilog
class soc_scoreboard extends uvm_scoreboard;
 `uvm_component_utils(soc_scoreboard)

 // Analysis Imp to receive transactions from Monitor
 `uvm_analysis_imp_decl(_axi)
 uvm_analysis_imp_axi #(axi_seq_item, soc_scoreboard) axi_export;

 // Golden model buffers
 shortint expected_c[16];
 shortint current_a[16];
 shortint current_b[16];

 int match_count = 0;
 int error_count = 0;

 function new(string name, uvm_component parent);
 super.new(name, parent);
 axi_export = new("axi_export", this);
 endfunction

 // Evaluates transactions received from Monitor
 virtual function void write_axi(axi_seq_item tr);
 // If accelerator writes back result to memory, verify it!
 if (tr.op_type == axi_seq_item::WRITE && tr.addr >= 32'h4000_0300) begin
 int element_idx = (tr.addr - 32'h4000_0300) / 2;
 shortint actual_hw_val = shortint'(tr.data[15:0]);
 shortint golden_val = expected_c[element_idx];

 if (actual_hw_val === golden_val) begin
 `uvm_info("SCB_PASS", $sformatf("Element [%0d] MATCH! HW: 0x%04h | Golden: 0x%04h", 
 element_idx, actual_hw_val, golden_val), UVM_HIGH)
 match_count++;
 end else begin
 `uvm_error("SCB_MISMATCH", $sformatf("Element [%0d] ERROR! HW: 0x%04h | Golden: 0x%04h", 
 element_idx, actual_hw_val, golden_val))
 error_count++;
 end
 end
 endfunction

 // End-of-test summary
 virtual function void check_phase(uvm_phase phase);
 super.check_phase(phase);
 `uvm_info("SCB_SUMMARY", $sformatf("\n==========================================\n SCOREBOARD SUMMARY\n Matches: %0d | Errors: %0d\n==========================================", 
 match_count, error_count), UVM_LOW)
 if (error_count > 0)
 `uvm_fatal("TEST_FAILED", "Simulation encountered mathematical mismatches!")
 endfunction
endclass
```

---

## Next Steps
Now that the scoreboard can verify transactions, how do we prove to executive engineering managers that our verification is 100% complete?
 [[05_Functional_Coverage_and_Closure|Proceed to Functional Coverage & Verification Closure]]
