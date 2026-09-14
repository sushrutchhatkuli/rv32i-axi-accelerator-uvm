// =============================================================================
// File: riscv_defines.svh
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Architectural constants, opcodes, and control encodings for
//              the RV32I Base Integer Instruction Set Architecture.
// =============================================================================

`ifndef RISCV_DEFINES_SVH
`define RISCV_DEFINES_SVH

// -----------------------------------------------------------------------------
// RV32I Major Opcodes (instr[6:0])
// -----------------------------------------------------------------------------
localparam logic [6:0] OPCODE_R_TYPE   = 7'b0110011; // Register arithmetic (ADD, SUB, SLL, etc.)
localparam logic [6:0] OPCODE_I_TYPE   = 7'b0010011; // Immediate arithmetic (ADDI, SLTI, etc.)
localparam logic [6:0] OPCODE_LOAD     = 7'b0000011; // Memory load (LB, LH, LW, LBU, LHU)
localparam logic [6:0] OPCODE_STORE    = 7'b0100011; // Memory store (SB, SH, SW)
localparam logic [6:0] OPCODE_BRANCH   = 7'b1100011; // Conditional branches (BEQ, BNE, BLT, etc.)
localparam logic [6:0] OPCODE_JAL      = 7'b1101111; // Jump and Link (Unconditional)
localparam logic [6:0] OPCODE_JALR     = 7'b1100111; // Jump and Link Register (Indirect)
localparam logic [6:0] OPCODE_LUI      = 7'b0110111; // Load Upper Immediate
localparam logic [6:0] OPCODE_AUIPC    = 7'b0010111; // Add Upper Immediate to PC
localparam logic [6:0] OPCODE_SYSTEM   = 7'b1110011; // System instructions (ECALL, EBREAK, CSR)
localparam logic [6:0] OPCODE_FENCE    = 7'b0001111; // Memory barrier ordering

// -----------------------------------------------------------------------------
// Funct7 Field Encodings (instr[31:25])
// -----------------------------------------------------------------------------
localparam logic [6:0] FUNCT7_STANDARD = 7'b0000000;
localparam logic [6:0] FUNCT7_SUB_SRA  = 7'b0100000;
localparam logic [6:0] FUNCT7_M_EXT    = 7'b0000001; // RISC-V Standard M-Extension

// -----------------------------------------------------------------------------
// Funct3 Field Encodings (instr[14:12])
// -----------------------------------------------------------------------------
// Arithmetic & Logic Funct3 (R-Type and I-Type)
localparam logic [2:0] FUNCT3_ADD_SUB  = 3'b000;
localparam logic [2:0] FUNCT3_SLL      = 3'b001;
localparam logic [2:0] FUNCT3_SLT      = 3'b010;
localparam logic [2:0] FUNCT3_SLTU     = 3'b011;
localparam logic [2:0] FUNCT3_XOR      = 3'b100;
localparam logic [2:0] FUNCT3_SRL_SRA  = 3'b101;
localparam logic [2:0] FUNCT3_OR       = 3'b110;
localparam logic [2:0] FUNCT3_AND      = 3'b111;

// RV32M Standard Extension Funct3
localparam logic [2:0] FUNCT3_MUL      = 3'b000; // Multiply (lower 32 bits)
localparam logic [2:0] FUNCT3_MULH     = 3'b001; // Multiply High Signed
localparam logic [2:0] FUNCT3_MULHSU   = 3'b010; // Multiply High Signed x Unsigned
localparam logic [2:0] FUNCT3_MULHU    = 3'b011; // Multiply High Unsigned
localparam logic [2:0] FUNCT3_DIV      = 3'b100; // Divide Signed
localparam logic [2:0] FUNCT3_DIVU     = 3'b101; // Divide Unsigned
localparam logic [2:0] FUNCT3_REM      = 3'b110; // Remainder Signed
localparam logic [2:0] FUNCT3_REMU     = 3'b111; // Remainder Unsigned

// Branch Funct3
localparam logic [2:0] FUNCT3_BEQ      = 3'b000;
localparam logic [2:0] FUNCT3_BNE      = 3'b001;
localparam logic [2:0] FUNCT3_BLT      = 3'b100;
localparam logic [2:0] FUNCT3_BGE      = 3'b101;
localparam logic [2:0] FUNCT3_BLTU     = 3'b110;
localparam logic [2:0] FUNCT3_BGEU     = 3'b111;

// Load / Store Funct3
localparam logic [2:0] FUNCT3_BYTE     = 3'b000; // LB / SB
localparam logic [2:0] FUNCT3_HALF     = 3'b001; // LH / SH
localparam logic [2:0] FUNCT3_WORD     = 3'b010; // LW / SW
localparam logic [2:0] FUNCT3_BYTE_U   = 3'b100; // LBU
localparam logic [2:0] FUNCT3_HALF_U   = 3'b101; // LHU

// -----------------------------------------------------------------------------
// Internal ALU Control Operations (5-bit control bus)
// -----------------------------------------------------------------------------
localparam logic [4:0] ALU_ADD         = 5'b00000; // Addition
localparam logic [4:0] ALU_SUB         = 5'b00001; // Subtraction
localparam logic [4:0] ALU_SLL         = 5'b00010; // Shift Left Logical
localparam logic [4:0] ALU_SLT         = 5'b00011; // Set Less Than (Signed)
localparam logic [4:0] ALU_SLTU        = 5'b00100; // Set Less Than Unsigned
localparam logic [4:0] ALU_XOR         = 5'b00101; // Bitwise XOR
localparam logic [4:0] ALU_SRL         = 5'b00110; // Shift Right Logical
localparam logic [4:0] ALU_SRA         = 5'b00111; // Shift Right Arithmetic
localparam logic [4:0] ALU_OR          = 5'b01000; // Bitwise OR
localparam logic [4:0] ALU_AND         = 5'b01001; // Bitwise AND
localparam logic [4:0] ALU_PASS_B      = 5'b01010; // Pass Operand B (for LUI)
localparam logic [4:0] ALU_MUL         = 5'b01011; // Signed x Signed Multiply (lower 32)
localparam logic [4:0] ALU_MULH        = 5'b01100; // Signed x Signed Multiply (upper 32)
localparam logic [4:0] ALU_MULHSU      = 5'b01101; // Signed x Unsigned Multiply (upper 32)
localparam logic [4:0] ALU_MULHU       = 5'b01110; // Unsigned x Unsigned Multiply (upper 32)
localparam logic [4:0] ALU_DIV         = 5'b01111; // Signed Division
localparam logic [4:0] ALU_DIVU        = 5'b10000; // Unsigned Division
localparam logic [4:0] ALU_REM         = 5'b10001; // Signed Remainder
localparam logic [4:0] ALU_REMU        = 5'b10010; // Unsigned Remainder

// -----------------------------------------------------------------------------
// Forwarding Mux Select Codes
// -----------------------------------------------------------------------------
localparam logic [1:0] FWD_NONE        = 2'b00; // Use operand from ID/EX register
localparam logic [1:0] FWD_EX_MEM      = 2'b10; // Forward from EX/MEM pipeline stage
localparam logic [1:0] FWD_MEM_WB      = 2'b01; // Forward from MEM/WB pipeline stage

// -----------------------------------------------------------------------------
// Writeback Result Mux Select Codes
// -----------------------------------------------------------------------------
localparam logic [1:0] WBMUX_ALU       = 2'b00; // ALU Result
localparam logic [1:0] WBMUX_MEM       = 2'b01; // Data Memory Read Data
localparam logic [1:0] WBMUX_PC4       = 2'b10; // Return Address (PC + 4)

`endif // RISCV_DEFINES_SVH
