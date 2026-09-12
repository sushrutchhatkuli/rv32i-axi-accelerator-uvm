// =============================================================================
// File: hazard_unit.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Pipeline Hazard Detection & Resolution Unit.
//              1. Detects Load-Use Data Hazards and automatically stalls the
//                 pipeline for 1 cycle (freezes PC and IF/ID, flushes ID/EX).
//              2. Detects Branch Mispredictions and flushes both IF/ID and
//                 ID/EX pipeline stages in a single cycle.
// =============================================================================

`timescale 1ns / 1ps

module hazard_unit (
    // Instruction currently in EX stage
    input  logic       id_ex_mem_read,     // 1 if instruction in EX is a Load (LW)
    input  logic [4:0] id_ex_rd_addr,      // Destination register of the Load
    
    // Instruction currently in ID stage
    input  logic [4:0] if_id_rs1_addr,     // Source register 1 being decoded
    input  logic [4:0] if_id_rs2_addr,     // Source register 2 being decoded
    
    // Branch evaluation from EX stage
    input  logic       branch_taken,       // 1 if branch/jump condition is satisfied
    
    // Pipeline Control Outputs
    output logic       stall_pc,           // Freeze Program Counter
    output logic       stall_if_id,        // Freeze IF/ID pipeline register
    output logic       flush_if_id,        // Clear IF/ID register (inject NOP)
    output logic       flush_id_ex         // Clear ID/EX register (inject NOP)
);

    logic load_use_hazard;

    // A Load-Use hazard occurs when an instruction in ID depends on a value
    // being fetched from memory by the immediately preceding instruction in EX!
    assign load_use_hazard = id_ex_mem_read && (id_ex_rd_addr != 5'd0) &&
                             ((id_ex_rd_addr == if_id_rs1_addr) || 
                              (id_ex_rd_addr == if_id_rs2_addr));

    always_comb begin
        // Default: pipeline flows freely
        stall_pc    = 1'b0;
        stall_if_id = 1'b0;
        flush_if_id = 1'b0;
        flush_id_ex = 1'b0;

        // Priority 1: Control Hazard (Branch Taken / Misprediction)
        // Discard the 2 speculatively fetched instructions!
        if (branch_taken) begin
            flush_if_id = 1'b1; // Turn instruction in IF/ID into NOP
            flush_id_ex = 1'b1; // Turn instruction in ID/EX into NOP
        // Priority 2: Data Hazard (Load-Use Dependency)
        // Pause earlier stages for 1 cycle until memory data arrives!
        end else if (load_use_hazard) begin
            stall_pc    = 1'b1; // Freeze Program Counter
            stall_if_id = 1'b1; // Freeze IF/ID register
            flush_id_ex = 1'b1; // Insert a bubble (clear ID/EX controls)
        end
    end

endmodule
