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
    input  logic [4:0]  alu_ctrl,   // 5-bit ALU operation selector (from control unit)
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

    // RV32M 64-bit full product calculation
    logic signed [63:0] mul_ss;
    logic        [63:0] mul_uu;
    logic signed [63:0] mul_su;

    assign mul_ss = signed_a * signed_b;
    assign mul_uu = a * b;
    assign mul_su = signed_a * $signed({1'b0, b});

    // Continuous assignments for product upper/lower words (clean compiler sensitivity)
    logic [31:0] mul_ss_lo, mul_ss_hi;
    logic [31:0] mul_uu_hi;
    logic [31:0] mul_su_hi;

    assign mul_ss_lo = mul_ss[31:0];
    assign mul_ss_hi = mul_ss[63:32];
    assign mul_uu_hi = mul_uu[63:32];
    assign mul_su_hi = mul_su[63:32];

    // RV32M Division & Remainder edge condition detection
    logic is_div_by_zero;
    logic is_signed_overflow;

    assign is_div_by_zero     = (b == 32'd0);
    assign is_signed_overflow = (a == 32'h8000_0000) && (b == 32'hFFFF_FFFF);

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

            // RV32M Hardware Multiplication & Division
            ALU_MUL:    result = mul_ss_lo;
            ALU_MULH:   result = mul_ss_hi;
            ALU_MULHSU: result = mul_su_hi;
            ALU_MULHU:  result = mul_uu_hi;

            ALU_DIV: begin
                if (is_div_by_zero)          result = 32'hFFFF_FFFF;
                else if (is_signed_overflow) result = 32'h8000_0000;
                else                         result = signed_a / signed_b;
            end

            ALU_DIVU: begin
                if (is_div_by_zero)          result = 32'hFFFF_FFFF;
                else                         result = a / b;
            end

            ALU_REM: begin
                if (is_div_by_zero)          result = a;
                else if (is_signed_overflow) result = 32'd0;
                else                         result = signed_a % signed_b;
            end

            ALU_REMU: begin
                if (is_div_by_zero)          result = a;
                else                         result = a % b;
            end

            default:    result = 32'd0;
        endcase
    end

    // Zero flag output
    assign zero = (result == 32'd0);

endmodule
