// =============================================================================
// File: forwarding_unit.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Data Hazard Forwarding (Bypass) Unit. Detects RAW hazards
//              between instructions in EX/MEM and MEM/WB stages and routes
//              the most recent results directly to ALU inputs with zero stalls.
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module forwarding_unit (
    // Source registers used by current instruction in EX stage
    input  logic [4:0] ex_rs1_addr,
    input  logic [4:0] ex_rs2_addr,
    
    // Destination register & write enable from MEM stage (1 cycle ahead)
    input  logic       mem_reg_write,
    input  logic [4:0] mem_rd_addr,
    
    // Destination register & write enable from WB stage (2 cycles ahead)
    input  logic       wb_reg_write,
    input  logic [4:0] wb_rd_addr,
    
    // Forwarding Mux Select Outputs:
    // 2'b00 = FWD_NONE   (Use normal operand from ID/EX register)
    // 2'b10 = FWD_EX_MEM (Forward directly from EX/MEM pipeline stage)
    // 2'b01 = FWD_MEM_WB (Forward directly from MEM/WB pipeline stage)
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    always_comb begin
        // ---------------------------------------------------------------------
        // Forwarding Logic for ALU Operand A (rs1)
        // ---------------------------------------------------------------------
        // Priority 1: EX/MEM Hazard (Most recent value from immediately preceding instruction)
        if (mem_reg_write && (mem_rd_addr != 5'd0) && (mem_rd_addr == ex_rs1_addr)) begin
            forward_a = FWD_EX_MEM;
        // Priority 2: MEM/WB Hazard (Value from instruction 2 cycles ago)
        end else if (wb_reg_write && (wb_rd_addr != 5'd0) && (wb_rd_addr == ex_rs1_addr)) begin
            forward_a = FWD_MEM_WB;
        // No hazard: use operand read from register file
        end else begin
            forward_a = FWD_NONE;
        end

        // ---------------------------------------------------------------------
        // Forwarding Logic for ALU Operand B (rs2)
        // ---------------------------------------------------------------------
        // Priority 1: EX/MEM Hazard
        if (mem_reg_write && (mem_rd_addr != 5'd0) && (mem_rd_addr == ex_rs2_addr)) begin
            forward_b = FWD_EX_MEM;
        // Priority 2: MEM/WB Hazard
        end else if (wb_reg_write && (wb_rd_addr != 5'd0) && (wb_rd_addr == ex_rs2_addr)) begin
            forward_b = FWD_MEM_WB;
        // No hazard
        end else begin
            forward_b = FWD_NONE;
        end
    end

endmodule
