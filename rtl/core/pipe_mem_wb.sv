// =============================================================================
// File: pipe_mem_wb.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Pipeline Register between Memory (MEM) and Writeback (WB) stages.
//              Latches calculation results, memory read data, return addresses,
//              and writeback control signals.
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module pipe_mem_wb (
    input  logic        clk,
    input  logic        rst_n,
    
    // Datapath Inputs from MEM
    input  logic [31:0] mem_alu_result,
    input  logic [31:0] mem_read_data,   // Data read from RAM
    input  logic [31:0] mem_pc_plus_4,   // Return address for JAL/JALR
    input  logic [4:0]  mem_rd_addr,

    // Control Inputs from MEM
    input  logic        mem_reg_write,
    input  logic [1:0]  mem_wb_sel,

    // Datapath Outputs to WB
    output logic [31:0] wb_alu_result,
    output logic [31:0] wb_read_data,
    output logic [31:0] wb_pc_plus_4,
    output logic [4:0]  wb_rd_addr,

    // Control Outputs to WB
    output logic        wb_reg_write,
    output logic [1:0]  wb_wb_sel
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_alu_result <= 32'd0;
            wb_read_data  <= 32'd0;
            wb_pc_plus_4  <= 32'd0;
            wb_rd_addr    <= 5'd0;
            wb_reg_write  <= 1'b0;
            wb_wb_sel     <= WBMUX_ALU;
        end else begin
            wb_alu_result <= mem_alu_result;
            wb_read_data  <= mem_read_data;
            wb_pc_plus_4  <= mem_pc_plus_4;
            wb_rd_addr    <= mem_rd_addr;
            wb_reg_write  <= mem_reg_write;
            wb_wb_sel     <= mem_wb_sel;
        end
    end

endmodule
