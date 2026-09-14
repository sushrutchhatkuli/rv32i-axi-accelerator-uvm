# =============================================================================
# File: Makefile
# Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
# Description: Top-level build and simulation automation for Icarus Verilog.
# =============================================================================

PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
FLAGS = -g2012

CORE_INCS = -I rtl/core
BUS_INCS  = -I rtl/bus
ACCEL_INCS = -I rtl/accel
TOP_INCS  = -I rtl/core -I rtl/bus -I rtl/accel -I rtl/top

CORE_SRCS = $(wildcard rtl/core/*.sv)
BUS_SRCS  = $(wildcard rtl/bus/*.sv)
ACCEL_SRCS = $(wildcard rtl/accel/*.sv)
TOP_SRCS  = $(CORE_SRCS) $(BUS_SRCS) $(ACCEL_SRCS) $(wildcard rtl/top/*.sv)

SIM_DIR = sim_build

.PHONY: all regression clean firmware tiled-firmware test-firmware test-tiled test-core test-m-ext test-bus test-accel test-soc synth view-cpu wave help

help:
	@echo "Heterogeneous RISC-V SoC Build System"
	@echo "Available Targets:"
	@echo "  make regression    - Run entire 10-testbench regression suite"
	@echo "  make synth         - Run physical ASIC synthesis with Yosys"
	@echo "  make view-cpu      - Interactive cycle-accurate CPU & Accelerator visualizer"
	@echo "  make wave          - Open graphical digital waveforms in GTKWave"
	@echo "  make test-tiled    - Run 4x4 Tiled Block GEMM HW/SW co-verification"
	@echo "  make test-firmware - Run autonomous HW/SW co-verification simulation"
	@echo "  make test-core     - Run Phase 1 RISC-V Core testbenches (including RV32M)"
	@echo "  make test-m-ext    - Run RV32M Hardware Multiplier / Divider testbench"
	@echo "  make test-bus      - Run Phase 2 AXI4-Lite Interconnect testbench"
	@echo "  make test-accel    - Run Phase 3 4-MAC Accelerator testbench"
	@echo "  make test-soc      - Run Phase 3 SoC top integration testbench"
	@echo "  make clean         - Remove compilation artifacts and waveform dumps"

$(SIM_DIR):
	mkdir -p $(SIM_DIR)

firmware:
	$(PYTHON) scripts/asm_to_hex.py firmware/firmware.s firmware/firmware.hex

tiled-firmware:
	$(PYTHON) scripts/asm_to_hex.py firmware/tiled_gemm.s firmware/tiled_gemm.hex

test-firmware: $(SIM_DIR) firmware
	$(IVERILOG) $(FLAGS) $(TOP_INCS) $(TOP_SRCS) verif/tb/tb_soc_firmware.sv -o $(SIM_DIR)/tb_soc_firmware.out
	$(VVP) $(SIM_DIR)/tb_soc_firmware.out

test-tiled: $(SIM_DIR) tiled-firmware
	$(IVERILOG) $(FLAGS) $(TOP_INCS) $(TOP_SRCS) verif/tb/tb_soc_tiled_gemm.sv -o $(SIM_DIR)/tb_soc_tiled_gemm.out
	$(VVP) $(SIM_DIR)/tb_soc_tiled_gemm.out

test-core: $(SIM_DIR)
	$(IVERILOG) $(FLAGS) $(CORE_INCS) $(CORE_SRCS) verif/tb/tb_core_units.sv -o $(SIM_DIR)/tb_core_units.out
	$(VVP) $(SIM_DIR)/tb_core_units.out
	$(IVERILOG) $(FLAGS) $(CORE_INCS) $(CORE_SRCS) verif/tb/tb_control_branch.sv -o $(SIM_DIR)/tb_control_branch.out
	$(VVP) $(SIM_DIR)/tb_control_branch.out
	$(IVERILOG) $(FLAGS) $(CORE_INCS) $(CORE_SRCS) verif/tb/tb_pipeline_hazards.sv -o $(SIM_DIR)/tb_pipeline_hazards.out
	$(VVP) $(SIM_DIR)/tb_pipeline_hazards.out
	$(IVERILOG) $(FLAGS) $(CORE_INCS) $(CORE_SRCS) verif/tb/tb_rv32m_units.sv -o $(SIM_DIR)/tb_rv32m_units.out
	$(VVP) $(SIM_DIR)/tb_rv32m_units.out

test-m-ext: $(SIM_DIR)
	$(IVERILOG) $(FLAGS) $(CORE_INCS) $(CORE_SRCS) verif/tb/tb_rv32m_units.sv -o $(SIM_DIR)/tb_rv32m_units.out
	$(VVP) $(SIM_DIR)/tb_rv32m_units.out

test-bus: $(SIM_DIR)
	$(IVERILOG) $(FLAGS) $(BUS_INCS) $(BUS_SRCS) verif/tb/tb_axi_lite_bus.sv -o $(SIM_DIR)/tb_axi_lite_bus.out
	$(VVP) $(SIM_DIR)/tb_axi_lite_bus.out

test-accel: $(SIM_DIR)
	$(IVERILOG) $(FLAGS) -I rtl/bus -I rtl/accel $(BUS_SRCS) $(ACCEL_SRCS) verif/tb/tb_accel.sv -o $(SIM_DIR)/tb_accel.out
	$(VVP) $(SIM_DIR)/tb_accel.out

test-soc: $(SIM_DIR)
	$(IVERILOG) $(FLAGS) $(TOP_INCS) $(TOP_SRCS) verif/tb/tb_soc_top.sv -o $(SIM_DIR)/tb_soc_top.out
	$(VVP) $(SIM_DIR)/tb_soc_top.out
	$(IVERILOG) $(FLAGS) $(TOP_INCS) $(TOP_SRCS) verif/tb/axi_if.sv verif/tb/tb_top.sv -o $(SIM_DIR)/tb_top.out
	$(VVP) $(SIM_DIR)/tb_top.out

regression:
	$(PYTHON) scripts/run_regression.py

synth:
	$(PYTHON) scripts/run_synthesis.py

view-cpu:
	$(PYTHON) scripts/visualize_cpu.py

wave:
	gtkwave soc_tiled_gemm_trace.vcd soc_tiled_gemm.gtkw

clean:
	rm -rf $(SIM_DIR) *.vcd
