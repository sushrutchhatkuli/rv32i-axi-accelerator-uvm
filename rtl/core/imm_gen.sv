// =============================================================================
// File: imm_gen.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Immediate Value Generator for RV32I instructions. Decodes and
//              sign-extends immediate bitfields for I, S, B, U, and J formats.
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module imm_gen (
    input  logic [31:0] instr,      // Raw 32-bit fetched instruction
    output logic [31:0] imm_ext     // 32-bit decoded sign-extended immediate
);

    logic [6:0] opcode;
    assign opcode = instr[6:0];

    always @(*) begin
        case (opcode)
            // I-Type: Immediate arithmetic (ADDI, SLTI, etc.), Loads (LW), JALR
            OPCODE_I_TYPE, OPCODE_LOAD, OPCODE_JALR: begin
                imm_ext = {{20{instr[31]}}, instr[31:20]};
            end

            // S-Type: Stores (SW, SH, SB)
            OPCODE_STORE: begin
                imm_ext = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end

            // B-Type: Conditional Branches (BEQ, BNE, BLT, etc.)
            // Note: Bit 0 is implicitly 0 because branch targets are halfword-aligned
            OPCODE_BRANCH: begin
                imm_ext = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            end

            // U-Type: Upper Immediate (LUI, AUIPC)
            OPCODE_LUI, OPCODE_AUIPC: begin
                imm_ext = {instr[31:12], 12'b0};
            end

            // J-Type: Jump and Link (JAL)
            // Note: Bit 0 is implicitly 0
            OPCODE_JAL: begin
                imm_ext = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            end

            default: begin
                imm_ext = 32'd0;
            end
        endcase
    end

endmodule
