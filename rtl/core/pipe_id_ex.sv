// =============================================================================
// File: pipe_id_ex.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Pipeline Register between Instruction Decode (ID) and
//              Execute (EX) stages. Latches decoded operands, register addresses,
//              immediates, and pipeline control lines.
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module pipe_id_ex (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush,          // Clears control signals on load-use stall or branch flush
    
    // Datapath Inputs from ID
    input  logic [31:0] id_pc,
    input  logic [31:0] id_rs1_data,
    input  logic [31:0] id_rs2_data,
    input  logic [31:0] id_imm_ext,
    input  logic [4:0]  id_rs1_addr,
    input  logic [4:0]  id_rs2_addr,
    input  logic [4:0]  id_rd_addr,
    input  logic [2:0]  id_funct3,
    
    // Control Inputs from ID
    input  logic        id_reg_write,
    input  logic        id_mem_read,
    input  logic        id_mem_write,
    input  logic        id_alu_src,
    input  logic [3:0]  id_alu_ctrl,
    input  logic        id_branch,
    input  logic [1:0]  id_jump,
    input  logic [1:0]  id_wb_sel,

    // Datapath Outputs to EX
    output logic [31:0] ex_pc,
    output logic [31:0] ex_rs1_data,
    output logic [31:0] ex_rs2_data,
    output logic [31:0] ex_imm_ext,
    output logic [4:0]  ex_rs1_addr,
    output logic [4:0]  ex_rs2_addr,
    output logic [4:0]  ex_rd_addr,
    output logic [2:0]  ex_funct3,
    
    // Control Outputs to EX
    output logic        ex_reg_write,
    output logic        ex_mem_read,
    output logic        ex_mem_write,
    output logic        ex_alu_src,
    output logic [3:0]  ex_alu_ctrl,
    output logic        ex_branch,
    output logic [1:0]  ex_jump,
    output logic [1:0]  ex_wb_sel
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_pc        <= 32'd0;
            ex_rs1_data  <= 32'd0;
            ex_rs2_data  <= 32'd0;
            ex_imm_ext   <= 32'd0;
            ex_rs1_addr  <= 5'd0;
            ex_rs2_addr  <= 5'd0;
            ex_rd_addr   <= 5'd0;
            ex_funct3    <= 3'd0;
            
            ex_reg_write <= 1'b0;
            ex_mem_read  <= 1'b0;
            ex_mem_write <= 1'b0;
            ex_alu_src   <= 1'b0;
            ex_alu_ctrl  <= ALU_ADD;
            ex_branch    <= 1'b0;
            ex_jump      <= 2'b00;
            ex_wb_sel    <= WBMUX_ALU;
        end else if (flush) begin
            // On flush, clear all control signals to 0 (inject a bubble!)
            ex_pc        <= 32'd0;
            ex_rs1_data  <= 32'd0;
            ex_rs2_data  <= 32'd0;
            ex_imm_ext   <= 32'd0;
            ex_rs1_addr  <= 5'd0;
            ex_rs2_addr  <= 5'd0;
            ex_rd_addr   <= 5'd0;
            ex_funct3    <= 3'd0;

            ex_reg_write <= 1'b0;
            ex_mem_read  <= 1'b0;
            ex_mem_write <= 1'b0;
            ex_alu_src   <= 1'b0;
            ex_alu_ctrl  <= ALU_ADD;
            ex_branch    <= 1'b0;
            ex_jump      <= 2'b00;
            ex_wb_sel    <= WBMUX_ALU;
        end else begin
            // Normal pipeline advance
            ex_pc        <= id_pc;
            ex_rs1_data  <= id_rs1_data;
            ex_rs2_data  <= id_rs2_data;
            ex_imm_ext   <= id_imm_ext;
            ex_rs1_addr  <= id_rs1_addr;
            ex_rs2_addr  <= id_rs2_addr;
            ex_rd_addr   <= id_rd_addr;
            ex_funct3    <= id_funct3;

            ex_reg_write <= id_reg_write;
            ex_mem_read  <= id_mem_read;
            ex_mem_write <= id_mem_write;
            ex_alu_src   <= id_alu_src;
            ex_alu_ctrl  <= id_alu_ctrl;
            ex_branch    <= id_branch;
            ex_jump      <= id_jump;
            ex_wb_sel    <= id_wb_sel;
        end
    end

endmodule
