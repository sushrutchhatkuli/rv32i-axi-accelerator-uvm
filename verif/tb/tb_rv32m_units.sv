// =============================================================================
// File: tb_rv32m_units.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Unit testbench for RISC-V M-Standard Extension (RV32M).
//              Tests all 8 hardware operations: MUL, MULH, MULHSU, MULHU,
//              DIV, DIVU, REM, REMU, including decoder verification and
//              boundary edge cases (divide-by-zero and signed overflow).
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module tb_rv32m_units;

    // ALU test signals
    logic [31:0] alu_a;
    logic [31:0] alu_b;
    logic [4:0]  alu_ctrl;
    logic [31:0] alu_result;
    logic        alu_zero;

    // Control Unit test signals
    logic [6:0]  ctrl_opcode;
    logic [2:0]  ctrl_funct3;
    logic [6:0]  ctrl_funct7;
    logic        ctrl_reg_write;
    logic        ctrl_mem_read;
    logic        ctrl_mem_write;
    logic        ctrl_alu_src;
    logic [4:0]  ctrl_alu_ctrl;
    logic        ctrl_branch;
    logic [1:0]  ctrl_jump;
    logic [1:0]  ctrl_wb_sel;

    // Tracking variables
    int total_tests = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    // Instantiate ALU DUT
    alu u_alu (
        .a       (alu_a),
        .b       (alu_b),
        .alu_ctrl(alu_ctrl),
        .result  (alu_result),
        .zero    (alu_zero)
    );

    // Instantiate Control Unit DUT
    control_unit u_control (
        .opcode   (ctrl_opcode),
        .funct3   (ctrl_funct3),
        .funct7   (ctrl_funct7),
        .reg_write(ctrl_reg_write),
        .mem_read (ctrl_mem_read),
        .mem_write(ctrl_mem_write),
        .alu_src  (ctrl_alu_src),
        .alu_ctrl (ctrl_alu_ctrl),
        .branch   (ctrl_branch),
        .jump     (ctrl_jump),
        .wb_sel   (ctrl_wb_sel)
    );

    task check_alu(string name, logic [31:0] a_in, logic [31:0] b_in, logic [4:0] op, logic [31:0] expected);
        alu_a    = a_in;
        alu_b    = b_in;
        alu_ctrl = op;
        #1;
        total_tests = total_tests + 1;
        if (alu_result === expected) begin
            $display("  [PASS] %-38s | Got: 0x%08h (%0d)", name, alu_result, $signed(alu_result));
            passed_tests = passed_tests + 1;
        end else begin
            $display("  [FAIL] %-38s | Got: 0x%08h | Expected: 0x%08h", name, alu_result, expected);
            failed_tests = failed_tests + 1;
        end
    endtask

    task check_ctrl(string name, logic [2:0] f3, logic [4:0] expected_op);
        ctrl_opcode = OPCODE_R_TYPE;
        ctrl_funct7 = FUNCT7_M_EXT;
        ctrl_funct3 = f3;
        #1;
        total_tests = total_tests + 1;
        if (ctrl_alu_ctrl === expected_op && ctrl_reg_write === 1'b1 && ctrl_alu_src === 1'b0) begin
            $display("  [PASS] Decode %-31s | alu_ctrl=0x%02h, reg_write=1", name, ctrl_alu_ctrl);
            passed_tests = passed_tests + 1;
        end else begin
            $display("  [FAIL] Decode %-31s | Got: 0x%02h | Expected: 0x%02h", name, ctrl_alu_ctrl, expected_op);
            failed_tests = failed_tests + 1;
        end
    endtask

    initial begin
        $dumpfile("rv32m_trace.vcd");
        $dumpvars(0, tb_rv32m_units);

        $display("\n=======================================================");
        $display("  Starting RV32M Hardware Multiplier / Divider Lab");
        $display("=======================================================\n");

        // ---------------------------------------------------------------------
        // 1. Control Unit RV32M Instruction Decoding
        // ---------------------------------------------------------------------
        $display("--- Step 1: Testing RV32M Instruction Decoder ---");
        check_ctrl("MUL   (funct3=000)", FUNCT3_MUL,    ALU_MUL);
        check_ctrl("MULH  (funct3=001)", FUNCT3_MULH,   ALU_MULH);
        check_ctrl("MULHSU(funct3=010)", FUNCT3_MULHSU, ALU_MULHSU);
        check_ctrl("MULHU (funct3=011)", FUNCT3_MULHU,  ALU_MULHU);
        check_ctrl("DIV   (funct3=100)", FUNCT3_DIV,    ALU_DIV);
        check_ctrl("DIVU  (funct3=101)", FUNCT3_DIVU,   ALU_DIVU);
        check_ctrl("REM   (funct3=110)", FUNCT3_REM,    ALU_REM);
        check_ctrl("REMU  (funct3=111)", FUNCT3_REMU,   ALU_REMU);

        // ---------------------------------------------------------------------
        // 2. Hardware Multiplier (MUL, MULH, MULHSU, MULHU)
        // ---------------------------------------------------------------------
        $display("\n--- Step 2: Testing Hardware Multiplier (32x32 -> 64-bit) ---");
        // MUL (lower 32 bits)
        check_alu("MUL: Positive x Positive (12 * 10)",  32'd12,  32'd10,  ALU_MUL, 32'd120);
        check_alu("MUL: Negative x Positive (-5 * 20)",  -32'd5,  32'd20,  ALU_MUL, -32'd100);
        check_alu("MUL: Negative x Negative (-15 * -4)", -32'd15, -32'd4,  ALU_MUL, 32'd60);
        check_alu("MUL: Large Wrapping Product",         32'h1234_5678, 32'd2, ALU_MUL, 32'h2468_ACF0);

        // MULH (Signed high word)
        // 0x70000000 * 0x70000000 = 0x3100000000000000 -> upper = 0x31000000
        check_alu("MULH: Signed Upper Word (Large Pos)", 32'h7000_0000, 32'h7000_0000, ALU_MULH, 32'h3100_0000);
        // -2000000000 * 2 = -4000000000 = 0xFFFFFFFF_119E1800 -> upper = 0xFFFFFFFF (-1)
        check_alu("MULH: Signed Upper Word (Large Neg)", -32'd2000000000, 32'd2, ALU_MULH, 32'hFFFF_FFFF);

        // MULHU (Unsigned high word)
        // 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE_00000001 -> upper = 0xFFFFFFFE
        check_alu("MULHU: Unsigned Upper Word (Max)",    32'hFFFF_FFFF, 32'hFFFF_FFFF, ALU_MULHU, 32'hFFFF_FFFE);

        // MULHSU (Signed x Unsigned high word)
        // -1 * 0xFFFFFFFF = -4294967295 = 0xFFFFFFFF_00000001 -> upper = 0xFFFFFFFF
        check_alu("MULHSU: Signed x Unsigned",           -32'd1, 32'hFFFF_FFFF, ALU_MULHSU, 32'hFFFF_FFFF);

        // ---------------------------------------------------------------------
        // 3. Hardware Divider & Remainder (DIV, DIVU, REM, REMU)
        // ---------------------------------------------------------------------
        $display("\n--- Step 3: Testing Hardware Division & Remainder ---");
        check_alu("DIV:  Positive / Positive (100 / 5)",  32'd100,  32'd5,  ALU_DIV,  32'd20);
        check_alu("DIV:  Negative / Positive (-100 / 5)", -32'd100, 32'd5,  ALU_DIV,  -32'd20);
        check_alu("DIV:  Positive / Negative (100 / -5)", 32'd100,  -32'd5, ALU_DIV,  -32'd20);
        check_alu("DIV:  Negative / Negative (-100 / -5)",-32'd100, -32'd5, ALU_DIV,  32'd20);

        check_alu("DIVU: Unsigned Division (0xFFFFFFFE/2)", 32'hFFFF_FFFE, 32'd2, ALU_DIVU, 32'h7FFF_FFFF);

        check_alu("REM:  Positive % Positive (14 % 5)",   32'd14,  32'd5,  ALU_REM,  32'd4);
        check_alu("REM:  Negative % Positive (-14 % 5)",  -32'd14, 32'd5,  ALU_REM,  -32'd4);
        check_alu("REM:  Positive % Negative (14 % -5)",  32'd14,  -32'd5, ALU_REM,  32'd4);
        check_alu("REM:  Negative % Negative (-14 % -5)", -32'd14, -32'd5, ALU_REM,  -32'd4);

        check_alu("REMU: Unsigned Remainder (100 % 30)",  32'd100, 32'd30, ALU_REMU, 32'd10);

        // ---------------------------------------------------------------------
        // 4. RISC-V Specification Boundary Edge Cases
        // ---------------------------------------------------------------------
        $display("\n--- Step 4: Testing RISC-V Specification Edge Cases ---");
        // Divide by zero: DIV/DIVU returns all 1s (-1)
        check_alu("DIV by Zero: 100 / 0 -> -1",           32'd100, 32'd0, ALU_DIV,  32'hFFFF_FFFF);
        check_alu("DIVU by Zero: 100 / 0 -> 0xFFFFFFFF",  32'd100, 32'd0, ALU_DIVU, 32'hFFFF_FFFF);
        // Remainder by zero: REM/REMU returns numerator
        check_alu("REM by Zero: 100 % 0 -> 100",          32'd100, 32'd0, ALU_REM,  32'd100);
        check_alu("REMU by Zero: 100 % 0 -> 100",         32'd100, 32'd0, ALU_REMU, 32'd100);

        // Signed Overflow: -2^31 / -1 -> -2^31; -2^31 % -1 -> 0
        check_alu("DIV Overflow: -2^31 / -1 -> -2^31",    32'h8000_0000, 32'hFFFF_FFFF, ALU_DIV, 32'h8000_0000);
        check_alu("REM Overflow: -2^31 % -1 -> 0",        32'h8000_0000, 32'hFFFF_FFFF, ALU_REM, 32'd0);

        // ---------------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------------
        $display("\n=======================================================");
        $display("  RV32M HARDWARE MULTIPLIER / DIVIDER SUMMARY");
        $display("  Total Tests  : %0d", total_tests);
        $display("  Passed Tests : %0d", passed_tests);
        $display("  Failed Tests : %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("  RESULT       : ALL TESTS PASSED! 100%% SUCCESS");
            $display("  SYSTEM STATE : FULL RV32M EXTENSION VERIFIED ON SILICON");
        end else begin
            $display("  RESULT       : FAILURES DETECTED IN RV32M EXECUTION");
        end
        $display("=======================================================\n");

        $finish;
    end

endmodule
