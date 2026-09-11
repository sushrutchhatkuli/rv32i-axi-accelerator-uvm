// =============================================================================
// File: tb_control_branch.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Self-checking unit testbench verifying the Control Unit and
//              Branch Unit (Decoder, Control Muxes, and Branch Comparisons).
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module tb_control_branch;

    // Control Unit Signals
    logic [6:0] ctrl_opcode;
    logic [2:0] ctrl_funct3;
    logic [6:0] ctrl_funct7;
    logic       ctrl_reg_write;
    logic       ctrl_mem_read;
    logic       ctrl_mem_write;
    logic       ctrl_alu_src;
    logic [3:0] ctrl_alu_ctrl;
    logic       ctrl_branch;
    logic [1:0] ctrl_jump;
    logic [1:0] ctrl_wb_sel;

    // Branch Unit Signals
    logic [31:0] br_rs1_data;
    logic [31:0] br_rs2_data;
    logic [2:0]  br_funct3;
    logic        br_branch_enable;
    logic [31:0] br_current_pc;
    logic [31:0] br_imm_ext;
    logic        br_branch_taken;
    logic [31:0] br_branch_target;

    // Test Tracking
    int total_tests = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    // Instantiate Control Unit
    control_unit u_control (
        .opcode(ctrl_opcode),
        .funct3(ctrl_funct3),
        .funct7(ctrl_funct7),
        .reg_write(ctrl_reg_write),
        .mem_read(ctrl_mem_read),
        .mem_write(ctrl_mem_write),
        .alu_src(ctrl_alu_src),
        .alu_ctrl(ctrl_alu_ctrl),
        .branch(ctrl_branch),
        .jump(ctrl_jump),
        .wb_sel(ctrl_wb_sel)
    );

    // Instantiate Branch Unit
    branch_unit u_branch (
        .rs1_data(br_rs1_data),
        .rs2_data(br_rs2_data),
        .funct3(br_funct3),
        .branch_enable(br_branch_enable),
        .current_pc(br_current_pc),
        .imm_ext(br_imm_ext),
        .branch_taken(br_branch_taken),
        .branch_target(br_branch_target)
    );

    // Helper task to check a single bit/signal
    task check_bool(string test_name, logic actual, logic expected);
        total_tests++;
        if (actual === expected) begin
            $display("  [PASS] %-35s | Got: %0b", test_name, actual);
            passed_tests++;
        end else begin
            $display("  [FAIL] %-35s | Got: %0b | Expected: %0b", test_name, actual, expected);
            failed_tests++;
        end
    endtask

    // Helper task to check 32-bit values
    task check_val(string test_name, logic [31:0] actual, logic [31:0] expected);
        total_tests++;
        if (actual === expected) begin
            $display("  [PASS] %-35s | Got: 0x%08h", test_name, actual);
            passed_tests++;
        end else begin
            $display("  [FAIL] %-35s | Got: 0x%08h | Expected: 0x%08h", test_name, actual, expected);
            failed_tests++;
        end
    endtask

    initial begin
        $display("\n=======================================================");
        $display("  Starting Control Unit & Branch Unit Verification Lab");
        $display("=======================================================\n");

        // ---------------------------------------------------------------------
        // STEP 1: Control Unit Decoding Tests
        // ---------------------------------------------------------------------
        $display("--- Step 1: Testing Control Unit Instruction Decoding ---");

        // Test 1.1: Decode R-Type ADD
        ctrl_opcode = OPCODE_R_TYPE; ctrl_funct3 = FUNCT3_ADD_SUB; ctrl_funct7 = 7'b0000000; #2;
        check_bool("Decode ADD: reg_write == 1", ctrl_reg_write, 1'b1);
        check_bool("Decode ADD: alu_src == 0 (rs2)", ctrl_alu_src, 1'b0);
        check_bool("Decode ADD: alu_ctrl == ADD", (ctrl_alu_ctrl == ALU_ADD), 1'b1);

        // Test 1.2: Decode R-Type SUB (funct7[5] == 1)
        ctrl_opcode = OPCODE_R_TYPE; ctrl_funct3 = FUNCT3_ADD_SUB; ctrl_funct7 = 7'b0100000; #2;
        check_bool("Decode SUB: alu_ctrl == SUB", (ctrl_alu_ctrl == ALU_SUB), 1'b1);

        // Test 1.3: Decode I-Type ADDI
        ctrl_opcode = OPCODE_I_TYPE; ctrl_funct3 = FUNCT3_ADD_SUB; ctrl_funct7 = 7'b0000000; #2;
        check_bool("Decode ADDI: reg_write == 1", ctrl_reg_write, 1'b1);
        check_bool("Decode ADDI: alu_src == 1 (imm)", ctrl_alu_src, 1'b1);

        // Test 1.4: Decode Load (LW)
        ctrl_opcode = OPCODE_LOAD; ctrl_funct3 = FUNCT3_WORD; #2;
        check_bool("Decode LW: mem_read == 1", ctrl_mem_read, 1'b1);
        check_bool("Decode LW: wb_sel == MEM", (ctrl_wb_sel == WBMUX_MEM), 1'b1);

        // Test 1.5: Decode Store (SW)
        ctrl_opcode = OPCODE_STORE; ctrl_funct3 = FUNCT3_WORD; #2;
        check_bool("Decode SW: mem_write == 1", ctrl_mem_write, 1'b1);
        check_bool("Decode SW: reg_write == 0", ctrl_reg_write, 1'b0);

        // Test 1.6: Decode Branch (BEQ)
        ctrl_opcode = OPCODE_BRANCH; ctrl_funct3 = FUNCT3_BEQ; #2;
        check_bool("Decode BEQ: branch == 1", ctrl_branch, 1'b1);

        // Test 1.7: Decode Jump (JAL)
        ctrl_opcode = OPCODE_JAL; #2;
        check_bool("Decode JAL: jump == 01", (ctrl_jump == 2'b01), 1'b1);
        check_bool("Decode JAL: wb_sel == PC4", (ctrl_wb_sel == WBMUX_PC4), 1'b1);

        // ---------------------------------------------------------------------
        // STEP 2: Branch Unit Comparison & Target Tests
        // ---------------------------------------------------------------------
        $display("\n--- Step 2: Testing Branch Unit Condition Checks ---");

        br_branch_enable = 1'b1;
        br_current_pc    = 32'h0000_1000;
        br_imm_ext       = 32'h0000_0020; // Jump ahead +32 bytes

        // Test 2.1: BEQ (Branch if Equal) with matching numbers (10 == 10)
        br_funct3 = FUNCT3_BEQ; br_rs1_data = 32'd10; br_rs2_data = 32'd10; #2;
        check_bool("BEQ: 10 == 10 -> TAKEN", br_branch_taken, 1'b1);

        // Test 2.2: BEQ with mismatch (10 == 20) -> NOT TAKEN
        br_rs1_data = 32'd10; br_rs2_data = 32'd20; #2;
        check_bool("BEQ: 10 == 20 -> NOT TAKEN", br_branch_taken, 1'b0);

        // Test 2.3: BNE (Branch if Not Equal) with mismatch (10 != 20) -> TAKEN
        br_funct3 = FUNCT3_BNE; #2;
        check_bool("BNE: 10 != 20 -> TAKEN", br_branch_taken, 1'b1);

        // Test 2.4: BLT (Branch if Less Than - Signed): -15 < 5 -> TAKEN
        br_funct3 = FUNCT3_BLT; br_rs1_data = -32'd15; br_rs2_data = 32'd5; #2;
        check_bool("BLT Signed: -15 < 5 -> TAKEN", br_branch_taken, 1'b1);

        // Test 2.5: BGE (Branch Greater/Equal - Signed): -15 >= 5 -> NOT TAKEN
        br_funct3 = FUNCT3_BGE; #2;
        check_bool("BGE Signed: -15 >= 5 -> NOT TAKEN", br_branch_taken, 1'b0);

        // Test 2.6: BLTU (Branch Less Than - Unsigned): 0xFFFFFFF1 < 5 -> NOT TAKEN (4.2B is NOT < 5!)
        br_funct3 = FUNCT3_BLTU; #2;
        check_bool("BLTU Unsigned: -15 < 5 -> NOT TAKEN", br_branch_taken, 1'b0);

        // Test 2.7: Target Address Math: PC (0x1000) + offset (+0x20) = 0x1020
        check_val("Branch Target: 0x1000 + 0x20", br_branch_target, 32'h0000_1020);

        // ---------------------------------------------------------------------
        // Final Summary Banner
        // ---------------------------------------------------------------------
        $display("\n=======================================================");
        $display("  CONTROL & BRANCH UNIT VERIFICATION SUMMARY");
        $display("  Total Tests  : %0d", total_tests);
        $display("  Passed Tests : %0d", passed_tests);
        $display("  Failed Tests : %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("  RESULT       : ALL TESTS PASSED! 100%% SUCCESS");
        end else begin
            $display("  RESULT       : VERIFICATION FAILED WITH %0d ERRORS", failed_tests);
        end
        $display("=======================================================\n");

        #10 $finish;
    end

endmodule
