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
// Internal ALU Control Operations (4-bit control bus)
// -----------------------------------------------------------------------------
localparam logic [3:0] ALU_ADD         = 4'b0000; // Addition
localparam logic [3:0] ALU_SUB         = 4'b0001; // Subtraction
localparam logic [3:0] ALU_SLL         = 4'b0010; // Shift Left Logical
localparam logic [3:0] ALU_SLT         = 4'b0011; // Set Less Than (Signed)
localparam logic [3:0] ALU_SLTU        = 4'b0100; // Set Less Than Unsigned
localparam logic [3:0] ALU_XOR         = 4'b0101; // Bitwise XOR
localparam logic [3:0] ALU_SRL         = 4'b0110; // Shift Right Logical
localparam logic [3:0] ALU_SRA         = 4'b0111; // Shift Right Arithmetic
localparam logic [3:0] ALU_OR          = 4'b1000; // Bitwise OR
localparam logic [3:0] ALU_AND         = 4'b1001; // Bitwise AND
localparam logic [3:0] ALU_PASS_B      = 4'b1010; // Pass Operand B (for LUI)

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
