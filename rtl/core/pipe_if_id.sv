// =============================================================================
// File: pipe_if_id.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Pipeline Register between Instruction Fetch (IF) and
//              Instruction Decode (ID) stages. Supports synchronous stall
//              (pipeline freeze) and flush (NOP injection on branch mispredict).
// =============================================================================

`timescale 1ns / 1ps

module pipe_if_id (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        stall,      // Hazard Unit asserts: freeze register contents
    input  logic        flush,      // Branch Unit asserts: inject NOP bubble
    
    // Inputs from IF Stage
    input  logic [31:0] if_pc,
    input  logic [31:0] if_instr,
    
    // Outputs to ID Stage
    output logic [31:0] id_pc,
    output logic [31:0] id_instr
);

    // Standard RISC-V NOP: addi x0, x0, 0 (0x00000013)
    localparam logic [31:0] NOP_INSTR = 32'h0000_0013;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc    <= 32'd0;
            id_instr <= NOP_INSTR;
        end else if (flush) begin
            // Clear stage with NOP bubble on branch misprediction
            id_pc    <= 32'd0;
            id_instr <= NOP_INSTR;
        end else if (!stall) begin
            // Normal pipeline advance
            id_pc    <= if_pc;
            id_instr <= if_instr;
        end
        // If stall == 1, hold previous values (pipeline frozen)
    end

endmodule
