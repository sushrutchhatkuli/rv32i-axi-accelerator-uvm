---
title: "Complete Toolchain Setup and Installation Guide"
tags:
 - toolchain
 - simulation
 - verilator
 - questasim
 - vcs
 - riscv-gcc
 - gtkwave
date_created: 2026-09-10
status: "Completed"
---

# Complete Toolchain Setup and Installation Guide

> [!NOTE] **Zero-Dollar Engineering: You Can Build Everything for 100% Free**
> While semiconductor companies pay hundreds of thousands of dollars for licenses from Synopsys and Siemens, you can build, simulate, and verify this entire system on your personal computer using **100% free open-source software** or free browser-based simulators.

---

## 1. Toolchain Options Overview

| Toolchain Option | Best For | UVM Support | Cost | Setup Effort |
| :--- | :--- | :---: | :---: | :---: |
| **Option A: EDA Playground (Web)** | Instant testing without installing anything | **Yes (Full UVM 1.2)** | **Free** | **Zero (Runs in browser)** |
| **Option B: Siemens QuestaSim / Synopsys VCS** | Commercial industry simulation (University ECE servers) | **Yes (Full UVM 1.2)** | Free via School License | Medium (SSH to server) |
| **Option C: Verilator + C++ (Local)** | High-speed local SystemVerilog simulation & DPI-C | C++ Testbenches | **Free Open-Source** | Low (via WSL / Linux) |
| **Option D: Icarus Verilog (iverilog) + GTKWave** | Local RTL unit testing & waveform inspection | Directed SV | **Free Open-Source** | Minimal |

---

## 2. Option A: EDA Playground (Zero-Install, Instant UVM)

If you do not want to configure Linux packages or server licenses, you can run full IEEE 1800.2 UVM simulations directly in your web browser:

1. Navigate to **[EDAPlayground.com](https://www.edaplayground.com)** and create a free account (use your university `.edu` email to unlock commercial simulators like Synopsys VCS and Aldec Riviera-PRO).
2. In the left panel:
 - **Target**: Select **SystemVerilog/Verilog**.
 - **Simulator**: Select **Aldec Riviera-PRO** or **Synopsys VCS**.
 - **UVM / OVM**: Check the box for **UVM 1.2**.
 - **Open EPWave after run**: Checked (provides instant waveform viewing).
3. Copy your RTL into the right pane, your UVM testbench into the left pane, and click **Run**!

---

## 3. Option B: Industry Simulators via University Servers (QuestaSim / VCS)

Most top engineering universities (e.g. WPI, Georgia Tech, Purdue, Berkeley) maintain site licenses for **Synopsys VCS** or **Siemens QuestaSim** on their ECE computing clusters.

### Connecting via SSH:
```bash
ssh -X your_username@ece-servers.university.edu
```

### Loading Environment Modules:
```bash
module load vcs
# or
module load questasim
```

### Compiling and Running UVM in QuestaSim:
```bash
# Compile UVM package and SystemVerilog files
vlog -sv +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv \
 +incdir+rtl/core +incdir+rtl/bus +incdir+verif/tb \
 rtl/**/*.sv verif/**/*.sv verif/scb/golden_accel.cpp

# Elaborate and simulate with random seed
vsim -c -voptargs=+acc tb_top +UVM_TESTNAME=accel_random_test -sv_seed random -do "run -all; quit"
```

---

## 4. Option C: Local Open-Source Setup on Windows (via WSL2 / Ubuntu)

For rapid local simulation on your Windows machine, the best path is **WSL2 (Windows Subsystem for Linux)**.

### Step 1: Install WSL2 Ubuntu
Open PowerShell as Administrator and run:
```powershell
wsl --install -d Ubuntu
```
Restart your computer when prompted.

### Step 2: Install Open-Source Simulation Tools
Open your Ubuntu terminal and run:
```bash
sudo apt update && sudo apt upgrade -y
# Install Icarus Verilog and GTKWave
sudo apt install -y iverilog gtkwave

# Install Verilator (C++ SystemVerilog simulator)
sudo apt install -y verilator make g++

# Install RISC-V 32-bit GCC Cross-Compiler
sudo apt install -y gcc-riscv64-unknown-elf
```

---

## 5. Compiling C Code with RISC-V GCC

To run real C programs on your RV32I core:

```bash
# 1. Compile C source to RV32I bare-metal object file
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -O2 -c main.c -o main.o

# 2. Link object file with memory linker script
riscv64-unknown-elf-ld -T link.ld main.o -o firmware.elf

# 3. Convert ELF to Verilog Hex memory file format
riscv64-unknown-elf-objcopy -O verilog firmware.elf firmware.hex

# 4. (Optional) Disassemble to inspect compiled assembly code
riscv64-unknown-elf-objdump -d firmware.elf > firmware.asm
```

Inside your SystemVerilog RAM module, load `firmware.hex` directly into memory at time 0:
```systemverilog
initial begin
 $readmemh("firmware.hex", ram_memory);
end
```

---

## 6. How to View Waveforms in GTKWave

1. In your top-level testbench (`tb_top.sv`), add this dump block:
 ```systemverilog
 initial begin
 $dumpfile("sim_trace.vcd");
 $dumpvars(0, tb_top);
 end
 ```
2. Run simulation to produce `sim_trace.vcd`.
3. Launch GTKWave:
 ```bash
 gtkwave sim_trace.vcd
 ```
4. In the GTKWave hierarchy tree:
 - Expand `tb_top` $\rightarrow$ `dut` $\rightarrow$ `cpu`.
 - Add `clk`, `pc`, `id_instr`, `forward_a`, and `hazard_unit.load_use_hazard`.
 - Expand `axi_if` and add `awvalid`, `awready`, `wdata`, and `bvalid`.
 - Observe the exact handshake cycles and pipeline bubbles!

---

## Next Steps
Now let's look at the automated Makefiles and regression scripts to run your simulations with a single command:
 [[02_Simulation_Scripts_and_Makefiles|Proceed to Simulation Scripts & Makefiles]]
