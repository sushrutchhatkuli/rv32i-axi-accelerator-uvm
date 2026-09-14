# ASIC Physical Synthesis & Gate-Level Utilization Report

> [!NOTE] **Physical Silicon Gate Mapping**
> Generated with Yosys Open-Source Synthesis Suite mapping synthesizable SystemVerilog
> to standard CMOS technology primitives.

## Subsystem Resource Utilization

| Subsystem / Module | Top Module | Total Standard Cells | Combinational Logic | Sequential Flip-Flops (DFF) |
|:---|:---|:---:|:---:|:---:|
| **RV32IM 5-Stage Pipelined Processor Core** | `rv32i_core_top` | 40,482 | 39,021 | 1,461 |
| **L1 Hardware Cache Controller (1 KB Direct-Mapped)** | `l1_cache_controller` | 49,742 | 39,938 | 9,804 |
| **AMBA AXI4-Lite Master Interface Bridge** | `axi_lite_master` | 257 | 151 | 106 |
| **AMBA AXI4-Lite Interconnect Crossbar** | `axi_interconnect` | 383 | 375 | 8 |
| **Hardware Direct Memory Access (DMA) Controller** | `dma_controller` | 3,269 | 2,298 | 971 |
| **4-MAC Matrix Accelerator Compute Engine** | `accel_top` | 67,252 | 52,442 | 14,810 |
| **TOTAL HETEROGENEOUS SOC LOGIC** | `soc_top` | **161,385** | **134,225** | **27,160** |

## Silicon Feasibility Verdict
- **Zero Unintentional Latches**: All state transitions and combinational logic paths are fully specified.
- **Synchronous Edge Purity**: Dedicated positive-edge clocks with separate asynchronous power-on resets.
- **Technology Portability**: Pure synthesizable SystemVerilog fully portable to TSMC, GlobalFoundries, SkyWater 130nm, or FPGA (Xilinx/Altera).
