// =============================================================================
// File: branch_unit.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Branch Comparator & Target Address Calculator for RV32I.
//              Evaluates condition codes (BEQ, BNE, BLT, BGE, BLTU, BGEU) and
//              computes PC-relative branch target addresses.
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module branch_unit (
    input  logic [31:0] rs1_data,       // Operand 1 value
    input  logic [31:0] rs2_data,       // Operand 2 value
    input  logic [2:0]  funct3,         // Branch condition selector
    input  logic        branch_enable,  // High if current instruction is a branch
    input  logic [31:0] current_pc,     // PC of the branch instruction
    input  logic [31:0] imm_ext,        // Sign-extended branch offset
    
    output logic        branch_taken,   // 1 = Condition met, branch must jump!
    output logic [31:0] branch_target   // Computed target PC: current_pc + imm_ext
);

    logic signed [31:0] signed_rs1;
    logic signed [31:0] signed_rs2;
    logic               condition_met;

    assign signed_rs1 = rs1_data;
    assign signed_rs2 = rs2_data;

    // Evaluate conditional branch comparison
    always_comb begin
        case (funct3)
            FUNCT3_BEQ:  condition_met = (rs1_data == rs2_data);
            FUNCT3_BNE:  condition_met = (rs1_data != rs2_data);
            FUNCT3_BLT:  condition_met = (signed_rs1 < signed_rs2);
            FUNCT3_BGE:  condition_met = (signed_rs1 >= signed_rs2);
            FUNCT3_BLTU: condition_met = (rs1_data < rs2_data);
            FUNCT3_BGEU: condition_met = (rs1_data >= rs2_data);
            default:     condition_met = 1'b0;
        endcase
    end

    // Assert branch_taken only if this is an active branch instruction AND condition met
    assign branch_taken  = branch_enable && condition_met;

    // Branch Target Address is PC-relative: PC + imm_ext
    assign branch_target = current_pc + imm_ext;

endmodule
