// =============================================================================
// File: pipe_ex_mem.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Pipeline Register between Execute (EX) and Memory (MEM) stages.
//              Latches ALU computation results, memory write data, destination
//              register addresses, and memory/writeback control signals.
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module pipe_ex_mem (
    input  logic        clk,
    input  logic        rst_n,
    
    // Datapath Inputs from EX
    input  logic [31:0] ex_alu_result,
    input  logic [31:0] ex_write_data,  // Forwarded rs2 data to be written into RAM
    input  logic [4:0]  ex_rd_addr,
    input  logic [31:0] ex_pc_plus_4,   // Saved return address for JAL/JALR
    input  logic [2:0]  ex_funct3,      // Memory access size (byte, half, word)

    // Control Inputs from EX
    input  logic        ex_reg_write,
    input  logic        ex_mem_read,
    input  logic        ex_mem_write,
    input  logic [1:0]  ex_wb_sel,

    // Datapath Outputs to MEM
    output logic [31:0] mem_alu_result,
    output logic [31:0] mem_write_data,
    output logic [4:0]  mem_rd_addr,
    output logic [31:0] mem_pc_plus_4,
    output logic [2:0]  mem_funct3,

    // Control Outputs to MEM
    output logic        mem_reg_write,
    output logic        mem_mem_read,
    output logic        mem_mem_write,
    output logic [1:0]  mem_wb_sel
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_alu_result <= 32'd0;
            mem_write_data <= 32'd0;
            mem_rd_addr    <= 5'd0;
            mem_pc_plus_4  <= 32'd0;
            mem_funct3     <= 3'd0;

            mem_reg_write  <= 1'b0;
            mem_mem_read   <= 1'b0;
            mem_mem_write  <= 1'b0;
            mem_wb_sel     <= WBMUX_ALU;
        end else begin
            mem_alu_result <= ex_alu_result;
            mem_write_data <= ex_write_data;
            mem_rd_addr    <= ex_rd_addr;
            mem_pc_plus_4  <= ex_pc_plus_4;
            mem_funct3     <= ex_funct3;

            mem_reg_write  <= ex_reg_write;
            mem_mem_read   <= ex_mem_read;
            mem_mem_write  <= ex_mem_write;
            mem_wb_sel     <= ex_wb_sel;
        end
    end

endmodule
