// =============================================================================
// File: tb_core_units.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Self-checking unit testbench verifying the core mathematical
//              and storage units: ALU, Register File, and Immediate Generator.
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module tb_core_units;

    // Clock and Reset Signals
    logic clk;
    logic rst_n;

    // ALU Signals
    logic [31:0] alu_a, alu_b, alu_result;
    logic [3:0]  alu_ctrl;
    logic        alu_zero;

    // Register File Signals
    logic [4:0]  rf_rs1_addr, rf_rs2_addr, rf_rd_addr;
    logic [31:0] rf_rs1_data, rf_rs2_data, rf_rd_data;
    logic        rf_we;

    // ImmGen Signals
    logic [31:0] imm_instr, imm_ext;

    // Test Tracking Variables
    int total_tests = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    // Instantiate Device Under Test (DUT) Modules
    alu u_alu (
        .a(alu_a),
        .b(alu_b),
        .alu_ctrl(alu_ctrl),
        .result(alu_result),
        .zero(alu_zero)
    );

    regfile u_regfile (
        .clk(clk),
        .rst_n(rst_n),
        .rs1_addr(rf_rs1_addr),
        .rs1_data(rf_rs1_data),
        .rs2_addr(rf_rs2_addr),
        .rs2_data(rf_rs2_data),
        .we(rf_we),
        .rd_addr(rf_rd_addr),
        .rd_data(rf_rd_data)
    );

    imm_gen u_imm_gen (
        .instr(imm_instr),
        .imm_ext(imm_ext)
    );

    // Clock Generation: 100 MHz (10ns period)
    always #5 clk = ~clk;

    // Helper task to check results
    task check_val(string test_name, logic [31:0] actual, logic [31:0] expected);
        total_tests++;
        if (actual === expected) begin
            $display("  [PASS] %-30s | Got: 0x%08h", test_name, actual);
            passed_tests++;
        end else begin
            $display("  [FAIL] %-30s | Got: 0x%08h | Expected: 0x%08h", test_name, actual, expected);
            failed_tests++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        // Waveform dump for GTKWave
        $dumpfile("core_units_trace.vcd");
        $dumpvars(0, tb_core_units);

        // Initialize signals
        clk = 0;
        rst_n = 0;
        alu_a = 0; alu_b = 0; alu_ctrl = 0;
        rf_rs1_addr = 0; rf_rs2_addr = 0; rf_rd_addr = 0; rf_rd_data = 0; rf_we = 0;
        imm_instr = 0;

        $display("\n=======================================================");
        $display("  Starting RV32I Core Units Unit Verification Lab");
        $display("=======================================================\n");

        // Apply Reset
        #15 rst_n = 1;

        // ---------------------------------------------------------------------
        // TEST 1: ALU Arithmetic & Logic Operations
        // ---------------------------------------------------------------------
        $display("--- Step 1: Testing Arithmetic Logic Unit (ALU) ---");
        
        // ADD: 15 + 25 = 40 (0x28)
        alu_a = 32'd15; alu_b = 32'd25; alu_ctrl = ALU_ADD; #2;
        check_val("ALU ADD: 15 + 25", alu_result, 32'd40);

        // SUB: 10 - 25 = -15 (Two's complement: 0xFFFFFFF1)
        alu_a = 32'd10; alu_b = 32'd25; alu_ctrl = ALU_SUB; #2;
        check_val("ALU SUB: 10 - 25", alu_result, 32'hFFFF_FFF1);

        // ZERO FLAG: 42 - 42 = 0
        alu_a = 32'd42; alu_b = 32'd42; alu_ctrl = ALU_SUB; #2;
        check_val("ALU Zero Flag", {31'b0, alu_zero}, 32'd1);

        // Bitwise AND / OR / XOR
        alu_a = 32'hF0F0_AAAA; alu_b = 32'h0F0F_5555;
        alu_ctrl = ALU_AND; #2;
        check_val("ALU Bitwise AND", alu_result, 32'h0000_0000);
        alu_ctrl = ALU_OR;  #2;
        check_val("ALU Bitwise OR", alu_result, 32'hFFFF_FFFF);
        alu_ctrl = ALU_XOR; #2;
        check_val("ALU Bitwise XOR", alu_result, 32'hFFFF_FFFF);

        // Shifts: SLL, SRL, SRA (Arithmetic right shift preserves sign)
        alu_a = 32'hF000_0000; alu_b = 32'd4;
        alu_ctrl = ALU_SRL; #2;
        check_val("ALU SRL: 0xF0000000 >> 4", alu_result, 32'h0F00_0000);
        alu_ctrl = ALU_SRA; #2;
        check_val("ALU SRA: 0xF0000000 >>> 4", alu_result, 32'hFF00_0000);

        // Comparisons: SLT vs SLTU (-5 vs +2)
        alu_a = -32'd5; alu_b = 32'd2;
        alu_ctrl = ALU_SLT;  #2; // Signed: -5 < 2 is TRUE (1)
        check_val("ALU SLT: Signed -5 < 2", alu_result, 32'd1);
        alu_ctrl = ALU_SLTU; #2; // Unsigned: 0xFFFFFFFB < 2 is FALSE (0)
        check_val("ALU SLTU: Unsigned -5 < 2", alu_result, 32'd0);

        // ---------------------------------------------------------------------
        // TEST 2: Register File (RegFile)
        // ---------------------------------------------------------------------
        $display("\n--- Step 2: Testing Register File (RegFile) ---");

        // Write 0xDEADBEEF into Register x1
        @(posedge clk);
        rf_we = 1; rf_rd_addr = 5'd1; rf_rd_data = 32'hDEAD_BEEF;
        @(posedge clk);
        rf_we = 0;

        // Read x1 from both read ports
        rf_rs1_addr = 5'd1; rf_rs2_addr = 5'd1; #2;
        check_val("RegFile Read x1 (Port 1)", rf_rs1_data, 32'hDEAD_BEEF);
        check_val("RegFile Read x1 (Port 2)", rf_rs2_data, 32'hDEAD_BEEF);

        // Crucial Architectural Check: Attempt to write to x0!
        @(posedge clk);
        rf_we = 1; rf_rd_addr = 5'd0; rf_rd_data = 32'h1234_5678;
        @(posedge clk);
        rf_we = 0;

        // Verify x0 remains hardwired to 0
        rf_rs1_addr = 5'd0; #2;
        check_val("RegFile Hardwired x0 == 0", rf_rs1_data, 32'd0);

        // ---------------------------------------------------------------------
        // TEST 3: Immediate Generator (ImmGen)
        // ---------------------------------------------------------------------
        $display("\n--- Step 3: Testing Immediate Generator (ImmGen) ---");

        // I-Type: addi x1, x2, -4 (imm = 12'hFFC) -> Sign-extended to 32'hFFFF_FFFC
        // opcode: 0010011, rd: 00001, funct3: 000, rs1: 00010, imm: 111111111100
        imm_instr = 32'hFFC10093; #2;
        check_val("ImmGen I-Type (-4)", imm_ext, 32'hFFFF_FFFC);

        // U-Type: lui x1, 0x12345 (imm = 20'h12345) -> 32'h1234_5000
        // opcode: 0110111, rd: 00001, imm: 0x12345
        imm_instr = 32'h1234_50B7; #2;
        check_val("ImmGen U-Type (LUI)", imm_ext, 32'h1234_5000);

        // ---------------------------------------------------------------------
        // Final Summary Banner
        // ---------------------------------------------------------------------
        $display("\n=======================================================");
        $display("  CORE UNITS VERIFICATION LAB SUMMARY");
        $display("  Total Tests  : %0d", total_tests);
        $display("  Passed Tests : %0d", passed_tests);
        $display("  Failed Tests : %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("  RESULT       : ALL TESTS PASSED! 100%% SUCCESS");
        end else begin
            $display("  RESULT       : VERIFICATION FAILED WITH %0d ERRORS", failed_tests);
        end
        $display("=======================================================\n");

        #20 $finish;
    end

endmodule
