// =============================================================================
// File: control_unit.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Main instruction decoder and ALU control logic for RV32I.
//              Inspects opcode, funct3, and funct7 to generate pipeline control signals.
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module control_unit (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    
    // Pipeline Control Signals
    output logic       reg_write,  // 1 = Write result to rd register in WB stage
    output logic       mem_read,   // 1 = Read data from memory in MEM stage (Load)
    output logic       mem_write,  // 1 = Write data to memory in MEM stage (Store)
    output logic       alu_src,    // 0 = ALU Operand B is rs2; 1 = Operand B is imm_ext
    output logic [3:0] alu_ctrl,   // 4-bit ALU operation selector
    output logic       branch,     // 1 = Conditional branch instruction
    output logic [1:0] jump,       // 2'b00 = No jump, 2'b01 = JAL, 2'b10 = JALR
    output logic [1:0] wb_sel      // 2'b00 = ALU result, 2'b01 = Mem read data, 2'b10 = PC+4
);

    always @(*) begin
        // Default control settings (safe inactive defaults)
        reg_write = 1'b0;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        alu_src   = 1'b0;
        alu_ctrl  = ALU_ADD;
        branch    = 1'b0;
        jump      = 2'b00;
        wb_sel    = WBMUX_ALU;

        case (opcode)
            // -----------------------------------------------------------------
            // R-Type: Register-Register Arithmetic & Logic (ADD, SUB, SLL, etc.)
            // -----------------------------------------------------------------
            OPCODE_R_TYPE: begin
                reg_write = 1'b1;
                alu_src   = 1'b0;       // Second operand is rs2_data
                wb_sel    = WBMUX_ALU;  // Write ALU result back to rd

                case (funct3)
                    FUNCT3_ADD_SUB: begin
                        // funct7[5] distinguishes ADD (0) from SUB (1)
                        if (funct7[5]) alu_ctrl = ALU_SUB;
                        else           alu_ctrl = ALU_ADD;
                    end
                    FUNCT3_SLL:     alu_ctrl = ALU_SLL;
                    FUNCT3_SLT:     alu_ctrl = ALU_SLT;
                    FUNCT3_SLTU:    alu_ctrl = ALU_SLTU;
                    FUNCT3_XOR:     alu_ctrl = ALU_XOR;
                    FUNCT3_SRL_SRA: begin
                        // funct7[5] distinguishes SRL (0) from SRA (1)
                        if (funct7[5]) alu_ctrl = ALU_SRA;
                        else           alu_ctrl = ALU_SRL;
                    end
                    FUNCT3_OR:      alu_ctrl = ALU_OR;
                    FUNCT3_AND:     alu_ctrl = ALU_AND;
                    default:        alu_ctrl = ALU_ADD;
                endcase
            end

            // -----------------------------------------------------------------
            // I-Type: Immediate Arithmetic (ADDI, SLTI, XORI, etc.)
            // -----------------------------------------------------------------
            OPCODE_I_TYPE: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;       // Second operand is imm_ext
                wb_sel    = WBMUX_ALU;

                case (funct3)
                    FUNCT3_ADD_SUB: alu_ctrl = ALU_ADD;
                    FUNCT3_SLL:     alu_ctrl = ALU_SLL;
                    FUNCT3_SLT:     alu_ctrl = ALU_SLT;
                    FUNCT3_SLTU:    alu_ctrl = ALU_SLTU;
                    FUNCT3_XOR:     alu_ctrl = ALU_XOR;
                    FUNCT3_SRL_SRA: begin
                        // funct7[5] distinguishes SRLI (0) from SRAI (1)
                        if (funct7[5]) alu_ctrl = ALU_SRA;
                        else           alu_ctrl = ALU_SRL;
                    end
                    FUNCT3_OR:      alu_ctrl = ALU_OR;
                    FUNCT3_AND:     alu_ctrl = ALU_AND;
                    default:        alu_ctrl = ALU_ADD;
                endcase
            end

            // -----------------------------------------------------------------
            // Load Instructions (LW, LH, LB, LHU, LBU)
            // -----------------------------------------------------------------
            OPCODE_LOAD: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;       // Add rs1 + imm_ext to get memory address
                alu_ctrl  = ALU_ADD;
                mem_read  = 1'b1;       // Read from Data Memory
                wb_sel    = WBMUX_MEM;  // Write Memory ReadData into rd
            end

            // -----------------------------------------------------------------
            // Store Instructions (SW, SH, SB)
            // -----------------------------------------------------------------
            OPCODE_STORE: begin
                alu_src   = 1'b1;       // Add rs1 + imm_ext to get memory address
                alu_ctrl  = ALU_ADD;
                mem_write = 1'b1;       // Write rs2_data into Data Memory
            end

            // -----------------------------------------------------------------
            // Conditional Branch Instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU)
            // -----------------------------------------------------------------
            OPCODE_BRANCH: begin
                branch   = 1'b1;
                alu_src  = 1'b0;
                alu_ctrl = ALU_SUB;     // Evaluates difference for branch checks
            end

            // -----------------------------------------------------------------
            // JAL (Jump and Link - Unconditional)
            // -----------------------------------------------------------------
            OPCODE_JAL: begin
                reg_write = 1'b1;       // Save return address in rd (ra)
                jump      = 2'b01;      // JAL active
                wb_sel    = WBMUX_PC4;  // Write PC + 4 into rd
            end

            // -----------------------------------------------------------------
            // JALR (Jump and Link Register - Indirect Jump)
            // -----------------------------------------------------------------
            OPCODE_JALR: begin
                reg_write = 1'b1;       // Save return address in rd (ra)
                jump      = 2'b10;      // JALR active
                alu_src   = 1'b1;       // Target = rs1 + imm_ext
                alu_ctrl  = ALU_ADD;
                wb_sel    = WBMUX_PC4;  // Write PC + 4 into rd
            end

            // -----------------------------------------------------------------
            // LUI (Load Upper Immediate)
            // -----------------------------------------------------------------
            OPCODE_LUI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;       // Pass imm_ext
                alu_ctrl  = ALU_PASS_B; // ALU outputs imm_ext directly
                wb_sel    = WBMUX_ALU;
            end

            // -----------------------------------------------------------------
            // AUIPC (Add Upper Immediate to PC)
            // -----------------------------------------------------------------
            OPCODE_AUIPC: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_ctrl  = ALU_ADD;    // Evaluates PC + imm_ext
                wb_sel    = WBMUX_ALU;
            end

            default: begin
                // All defaults remain 0
            end
        endcase
    end

endmodule
