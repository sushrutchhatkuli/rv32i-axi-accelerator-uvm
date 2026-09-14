# ASIC Physical Synthesis & Gate-Level Utilization Report

> [!NOTE] **Physical Silicon Gate Mapping**
> Generated with Yosys Open-Source Synthesis Suite mapping synthesizable SystemVerilog
> to standard CMOS technology primitives.

## Subsystem Resource Utilization

| Subsystem / Module | Top Module | Total Standard Cells | Combinational Logic | Sequential Flip-Flops (DFF) |
|:---|:---|:---:|:---:|:---:|
| **RV32I 5-Stage Pipelined Processor Core** | `rv32i_core_top` | 8,996 | 7,536 | 1,460 |
| **AMBA AXI4-Lite Master Interface Bridge** | `axi_lite_master` | 257 | 151 | 106 |
| **AMBA AXI4-Lite Interconnect Crossbar** | `axi_interconnect` | 383 | 375 | 8 |
| **4-MAC Matrix Accelerator Compute Engine** | `accel_top` | 67,252 | 52,442 | 14,810 |
| **TOTAL HETEROGENEOUS SOC LOGIC** | `soc_top` | **76,888** | **60,504** | **16,384** |

## Silicon Feasibility Verdict
- **Zero Unintentional Latches**: All state transitions and combinational logic paths are fully specified.
- **Synchronous Edge Purity**: Dedicated positive-edge clocks with separate asynchronous power-on resets.
- **Technology Portability**: Pure synthesizable SystemVerilog fully portable to TSMC, GlobalFoundries, SkyWater 130nm, or FPGA (Xilinx/Altera).
