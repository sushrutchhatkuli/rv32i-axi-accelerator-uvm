---
title: "Automated Simulation Scripts, Makefiles, and Regression Flow"
tags:
  - makefile
  - simulation-scripts
  - regression
  - automation
  - uvm
date_created: 2026-09-10
status: "Completed"
---

# ⚙️ Automated Simulation Scripts, Makefiles, and Regression Flow

> [!TIP] **The Professional Difference: One-Click Automation**
> Silicon engineering teams never manually type out 50-argument compiler commands. Everything is orchestrated through a production **`Makefile`** and automated Python/Bash regression wrappers that run overnight, aggregate coverage, and alert you if a test fails.

---

## 1. Production-Grade `Makefile`

Create this file as `Makefile` in the root of your project:

```makefile
# ==============================================================================
# Makefile: RISC-V SoC + AXI Interconnect + UVM Testbench
# Supported Simulators: questasim, vcs, verilator, iverilog
# ==============================================================================

SIM       ?= questa
TEST      ?= accel_random_test
SEED      ?= random
VERBOSITY ?= UVM_MEDIUM
GUI       ?= 0

# Directories
RTL_DIR   = rtl
VERIF_DIR = verif
WORK_DIR  = sim_build

# Include Paths
INC_DIRS  = +incdir+$(RTL_DIR)/core \
            +incdir+$(RTL_DIR)/bus \
            +incdir+$(RTL_DIR)/accel \
            +incdir+$(VERIF_DIR)/tb \
            +incdir+$(VERIF_DIR)/seq \
            +incdir+$(VERIF_DIR)/agent \
            +incdir+$(VERIF_DIR)/env \
            +incdir+$(VERIF_DIR)/tests

# Source Files
RTL_SRCS   = $(wildcard $(RTL_DIR)/**/*.sv)
VERIF_SRCS = $(wildcard $(VERIF_DIR)/**/*.sv)
DPI_SRCS   = $(VERIF_DIR)/scb/golden_accel.cpp

.PHONY: all compile sim waves regress clean

all: compile sim

# ------------------------------------------------------------------------------
# Compilation Target
# ------------------------------------------------------------------------------
compile:
ifeq ($(SIM), questa)
	mkdir -p $(WORK_DIR)
	vlib $(WORK_DIR)/work
	g++ -c -fPIC -I$(QUESTA_HOME)/include $(DPI_SRCS) -o $(WORK_DIR)/golden_accel.o
	vlog -sv -work $(WORK_DIR)/work $(INC_DIRS) $(RTL_SRCS) $(VERIF_SRCS)
else ifeq ($(SIM), vcs)
	mkdir -p $(WORK_DIR)
	vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
	    $(INC_DIRS) $(RTL_SRCS) $(VERIF_SRCS) $(DPI_SRCS) \
	    -o $(WORK_DIR)/simv -l $(WORK_DIR)/compile.log
else ifeq ($(SIM), iverilog)
	mkdir -p $(WORK_DIR)
	iverilog -g2012 $(INC_DIRS) -o $(WORK_DIR)/sim.out $(RTL_SRCS) $(VERIF_DIR)/tb/tb_top.sv
endif

# ------------------------------------------------------------------------------
# Simulation Target
# ------------------------------------------------------------------------------
sim:
ifeq ($(SIM), questa)
	vsim -c -do "run -all; quit" \
	     -sv_seed $(SEED) \
	     +UVM_TESTNAME=$(TEST) \
	     +UVM_VERBOSITY=$(VERBOSITY) \
	     -work $(WORK_DIR)/work tb_top \
	     -l $(WORK_DIR)/$(TEST)_$(SEED).log
else ifeq ($(SIM), vcs)
	$(WORK_DIR)/simv +ntb_random_seed=$(SEED) \
	                 +UVM_TESTNAME=$(TEST) \
	                 +UVM_VERBOSITY=$(VERBOSITY) \
	                 -l $(WORK_DIR)/$(TEST)_$(SEED).log
else ifeq ($(SIM), iverilog)
	vvp $(WORK_DIR)/sim.out
endif

# ------------------------------------------------------------------------------
# Waveform Viewing
# ------------------------------------------------------------------------------
waves:
	gtkwave $(WORK_DIR)/sim_trace.vcd &

# ------------------------------------------------------------------------------
# Automated Multi-Seed Regression
# ------------------------------------------------------------------------------
regress:
	@echo "Starting 20-Seed Randomized Regression..."
	@python3 scripts/run_regression.py --runs 20 --test $(TEST) --sim $(SIM)

# ------------------------------------------------------------------------------
# Clean Build Artifacts
# ------------------------------------------------------------------------------
clean:
	rm -rf $(WORK_DIR) transcript *.vcd *.log *.key DVEfiles urgReport
```

---

## 2. Automated Regression Python Script (`scripts/run_regression.py`)

Save this script as `scripts/run_regression.py`:

```python
import subprocess
import random
import sys
import re

RUNS = 20
TEST = "accel_random_test"

print(f"==================================================")
print(f"  Starting UVM Regression: {RUNS} Randomized Seeds")
print(f"==================================================")

passes = 0
failures = 0

for i in range(1, RUNS + 1):
    seed = random.randint(1, 999999)
    log_file = f"sim_build/run_{i}_seed_{seed}.log"
    print(f"[{i}/{RUNS}] Running Test: {TEST} | Seed: {seed} ...", end="", flush=True)

    cmd = f"make sim TEST={TEST} SEED={seed}"
    proc = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    # Inspect log for UVM status
    if "UVM_ERROR :    0" in proc.stdout and "UVM_FATAL :    0" in proc.stdout:
        print(" PASS ✅")
        passes += 1
    else:
        print(" FAIL ❌")
        failures += 1
        with open(f"sim_build/fail_{seed}.log", "w") as f:
            f.write(proc.stdout)

print(f"\n==================================================")
print(f"  REGRESSION RESULTS: {passes}/{RUNS} PASSED")
print(f"  Final Pass Rate: {(passes/RUNS)*100:.1f}%")
print(f"==================================================")

if failures > 0:
    sys.exit(1)
```

---

## Next Steps
Now that your engineering workflow is fully automated, let's explore how to present this on your **Resume** and defend every single design decision during **Technical Interviews** at Apple, NVIDIA, and ARM:
👉 [[01_Resume_Bullet_Points_Guide|Proceed to Resume Bullet Points Guide]]
