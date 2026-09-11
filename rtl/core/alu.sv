// =============================================================================
// File: alu.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: 32-bit Arithmetic Logic Unit (ALU) implementing RV32I operations:
//              ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND, and PASS_B.
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module alu (
    input  logic [31:0] a,          // Operand A (rs1 or forwarded data)
    input  logic [31:0] b,          // Operand B (rs2, immediate, or forwarded data)
    input  logic [3:0]  alu_ctrl,   // ALU operation selector (from control unit)
    output logic [31:0] result,     // ALU computation output
    output logic        zero        // High when result == 0 (used for branch equality)
);

    // Intermediate wires for signed comparisons and arithmetic shifts
    logic signed [31:0] signed_a;
    logic signed [31:0] signed_b;
    logic [4:0]         shamt;      // Shift amount (RV32I uses lower 5 bits of B)

    assign signed_a = a;
    assign signed_b = b;
    assign shamt    = b[4:0];

    always_comb begin
        case (alu_ctrl)
            ALU_ADD:    result = a + b;
            ALU_SUB:    result = a - b;
            ALU_SLL:    result = a << shamt;
            ALU_SLT:    result = (signed_a < signed_b) ? 32'd1 : 32'd0;
            ALU_SLTU:   result = (a < b)               ? 32'd1 : 32'd0;
            ALU_XOR:    result = a ^ b;
            ALU_SRL:    result = a >> shamt;
            ALU_SRA:    result = signed_a >>> shamt;
            ALU_OR:     result = a | b;
            ALU_AND:    result = a & b;
            ALU_PASS_B: result = b; // For LUI (Load Upper Immediate)
            default:    result = 32'd0;
        endcase
    end

    // Zero flag output
    assign zero = (result == 32'd0);

endmodule
