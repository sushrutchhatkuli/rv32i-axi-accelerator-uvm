#!/usr/bin/env python3
# =============================================================================
# File: run_regression.py
# Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
# Description: Automated CI/CD Regression Suite.
#              Executes full test suite (12 testbenches) across all architectural
#              phases using Icarus Verilog and vvp.
# =============================================================================

import os
import subprocess
import sys
import time

TESTS = [
    {
        "name": "Phase 1: RV32I Core Execution Units",
        "tb": "verif/tb/tb_core_units.sv",
        "includes": ["rtl/core"],
        "sources": ["rtl/core/*.sv"],
    },
    {
        "name": "Phase 1: RV32I Branch & Control Flow",
        "tb": "verif/tb/tb_control_branch.sv",
        "includes": ["rtl/core"],
        "sources": ["rtl/core/*.sv"],
    },
    {
        "name": "Phase 1: RV32I Pipeline Hazards & Forwarding",
        "tb": "verif/tb/tb_pipeline_hazards.sv",
        "includes": ["rtl/core"],
        "sources": ["rtl/core/*.sv"],
    },
    {
        "name": "Phase 1: RV32M Hardware Multiplier & Divider",
        "tb": "verif/tb/tb_rv32m_units.sv",
        "includes": ["rtl/core"],
        "sources": ["rtl/core/*.sv"],
    },
    {
        "name": "Phase 1: L1 Hardware Cache Controller",
        "tb": "verif/tb/tb_l1_cache.sv",
        "includes": ["rtl/core"],
        "sources": ["rtl/core/*.sv"],
    },
    {
        "name": "Phase 2: AMBA AXI4-Lite Interconnect & Protocol",
        "tb": "verif/tb/tb_axi_lite_bus.sv",
        "includes": ["rtl/bus"],
        "sources": ["rtl/bus/*.sv"],
    },
    {
        "name": "Phase 2: Hardware Direct Memory Access (DMA) Controller",
        "tb": "verif/tb/tb_dma_controller.sv",
        "includes": ["rtl/bus"],
        "sources": ["rtl/bus/*.sv"],
    },
    {
        "name": "Phase 3: 4-MAC Matrix Accelerator Engine",
        "tb": "verif/tb/tb_accel.sv",
        "includes": ["rtl/bus", "rtl/accel"],
        "sources": ["rtl/bus/*.sv", "rtl/accel/*.sv"],
    },
    {
        "name": "Phase 3: Heterogeneous SoC Hardware Integration",
        "tb": "verif/tb/tb_soc_top.sv",
        "includes": ["rtl/core", "rtl/bus", "rtl/accel", "rtl/top"],
        "sources": ["rtl/core/*.sv", "rtl/bus/*.sv", "rtl/accel/*.sv", "rtl/top/*.sv"],
    },
    {
        "name": "Phase 3: End-to-End System Integration & Matrix Pipeline",
        "tb": "verif/tb/tb_top.sv",
        "includes": ["rtl/core", "rtl/bus", "rtl/accel", "rtl/top"],
        "sources": ["rtl/core/*.sv", "rtl/bus/*.sv", "rtl/accel/*.sv", "rtl/top/*.sv", "verif/tb/axi_if.sv"],
    },
    {
        "name": "Phase 4: Autonomous Bare-Metal Firmware Co-Verification",
        "tb": "verif/tb/tb_soc_firmware.sv",
        "includes": ["rtl/core", "rtl/bus", "rtl/accel", "rtl/top"],
        "sources": ["rtl/core/*.sv", "rtl/bus/*.sv", "rtl/accel/*.sv", "rtl/top/*.sv"],
        "pre_cmd": ["python3", "scripts/asm_to_hex.py", "firmware/firmware.s", "firmware/firmware.hex"]
    },
    {
        "name": "Phase 4: 4x4 Tiled Block GEMM Driver Co-Verification",
        "tb": "verif/tb/tb_soc_tiled_gemm.sv",
        "includes": ["rtl/core", "rtl/bus", "rtl/accel", "rtl/top"],
        "sources": ["rtl/core/*.sv", "rtl/bus/*.sv", "rtl/accel/*.sv", "rtl/top/*.sv"],
        "pre_cmd": ["python3", "scripts/asm_to_hex.py", "firmware/tiled_gemm.s", "firmware/tiled_gemm.hex"]
    }
]

def run_test(test):
    test_name = test["name"]
    tb_file = test["tb"]
    out_file = os.path.join("sim_build", os.path.basename(tb_file).replace(".sv", ".out"))
    os.makedirs("sim_build", exist_ok=True)

    if "pre_cmd" in test:
        res = subprocess.run(test["pre_cmd"], capture_output=True, text=True)
        if res.returncode != 0:
            print(f"[FAIL] Pre-requisite step failed for {test_name}:")
            print(res.stderr)
            return False, 0, 1

    inc_args = []
    for inc in test["includes"]:
        inc_args.extend(["-I", inc])

    import glob
    src_files = []
    for pattern in test["sources"]:
        src_files.extend(glob.glob(pattern))

    compile_cmd = ["iverilog", "-g2012"] + inc_args + src_files + [tb_file, "-o", out_file]
    comp_res = subprocess.run(compile_cmd, capture_output=True, text=True)
    if comp_res.returncode != 0:
        print(f"[COMPILATION ERROR] {test_name}:")
        print(comp_res.stderr)
        return False, 0, 1

    run_cmd = ["vvp", out_file]
    run_res = subprocess.run(run_cmd, capture_output=True, text=True)
    out = run_res.stdout

    # Parse passed/failed counts from summary or tags
    import re
    p_match = re.search(r"Passed (?:Tests|Checks)\s*:\s*(\d+)", out)
    f_match = re.search(r"Failed (?:Tests|Checks)\s*:\s*(\d+)", out)

    if p_match and f_match:
        passes = int(p_match.group(1))
        fails = int(f_match.group(1))
    else:
        passes = out.count("[PASS]") + out.count("[SCOREBOARD MATCH]")
        fails = out.count("[FAIL]")

    success = (run_res.returncode == 0) and (fails == 0) and (passes > 0)
    status_str = "PASS" if success else "FAIL"
    print(f"[{status_str}] {test_name:<55} | Passed: {passes:>3} | Failed: {fails:>3}")

    if not success:
        print("--- Simulation Output ---")
        print(out)
        print("-------------------------")

    return success, passes, fails

def main():
    print("================================================================================")
    print("  HETEROGENEOUS RISC-V SOC REGRESSION SUITE")
    print("================================================================================")
    start_time = time.time()

    total_passed_tests = 0
    total_failed_tests = 0
    testbenches_passed = 0
    testbenches_failed = 0

    for test in TESTS:
        success, passes, fails = run_test(test)
        total_passed_tests += passes
        total_failed_tests += fails
        if success:
            testbenches_passed += 1
        else:
            testbenches_failed += 1

    elapsed = time.time() - start_time
    print("================================================================================")
    print(f"  REGRESSION SUMMARY")
    print(f"  Testbenches Run    : {len(TESTS)}")
    print(f"  Testbenches Passed : {testbenches_passed}")
    print(f"  Testbenches Failed : {testbenches_failed}")
    print(f"  Total Assertions   : {total_passed_tests + total_failed_tests}")
    print(f"  Total Passed Checks: {total_passed_tests}")
    print(f"  Total Failed Checks: {total_failed_tests}")
    print(f"  Execution Time     : {elapsed:.2f} seconds")
    print("================================================================================")

    if testbenches_failed == 0 and total_failed_tests == 0:
        print("  OVERALL STATUS: 100% REGRESSION PASS")
        print("================================================================================")
        sys.exit(0)
    else:
        print("  OVERALL STATUS: REGRESSION FAILED")
        print("================================================================================")
        sys.exit(1)

if __name__ == "__main__":
    main()
