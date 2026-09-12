// =============================================================================
// File: rv32i_core_top.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Complete 5-Stage Pipelined RV32I Processor Core Top-Level.
//              Integrates IF, ID, EX, MEM, WB stages with Hazard Detection,
//              Data Forwarding (Bypass), and Branch Prediction Units.
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module rv32i_core_top (
    input  logic        clk,
    input  logic        rst_n,

    // Instruction Memory Interface (Fetch Stage)
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,

    // Data Memory Interface (Memory Stage)
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0]  dmem_strb,
    output logic        dmem_we,
    output logic        dmem_re,
    input  logic [31:0] dmem_rdata
);

    // =========================================================================
    // STAGE 1: INSTRUCTION FETCH (IF)
    // =========================================================================
    logic [31:0] if_pc, if_pc_next, if_pc_plus_4;
    logic        stall_pc;
    logic        branch_taken;
    logic [31:0] branch_target;

    assign if_pc_plus_4 = if_pc + 32'd4;

    // Next-PC Mux: Normal sequential (PC+4) vs. Branch/Jump Target
    assign if_pc_next = branch_taken ? branch_target : if_pc_plus_4;

    // Program Counter (PC) Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_pc <= 32'h0000_0000;
        end else if (!stall_pc) begin
            if_pc <= if_pc_next;
        end
        // If stall_pc is high, PC freezes (holds previous value)
    end

    assign imem_addr = if_pc;

    // -------------------------------------------------------------------------
    // Pipeline Register: IF -> ID
    // -------------------------------------------------------------------------
    logic [31:0] id_pc, id_instr;
    logic        stall_if_id, flush_if_id;

    pipe_if_id u_pipe_if_id (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall_if_id),
        .flush(flush_if_id),
        .if_pc(if_pc),
        .if_instr(imem_rdata),
        .id_pc(id_pc),
        .id_instr(id_instr)
    );

    // =========================================================================
    // STAGE 2: INSTRUCTION DECODE (ID)
    // =========================================================================
    logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    logic [31:0] id_rs1_data, id_rs2_data, id_imm_ext;
    logic [2:0]  id_funct3;
    logic [6:0]  id_opcode, id_funct7;

    assign id_opcode   = id_instr[6:0];
    assign id_rd_addr  = id_instr[11:7];
    assign id_funct3   = id_instr[14:12];
    assign id_rs1_addr = id_instr[19:15];
    assign id_rs2_addr = id_instr[24:20];
    assign id_funct7   = id_instr[31:25];

    // Control Unit (The Brain)
    logic       id_reg_write, id_mem_read, id_mem_write, id_alu_src, id_branch;
    logic [3:0] id_alu_ctrl;
    logic [1:0] id_jump, id_wb_sel;

    control_unit u_control (
        .opcode(id_opcode),
        .funct3(id_funct3),
        .funct7(id_funct7),
        .reg_write(id_reg_write),
        .mem_read(id_mem_read),
        .mem_write(id_mem_write),
        .alu_src(id_alu_src),
        .alu_ctrl(id_alu_ctrl),
        .branch(id_branch),
        .jump(id_jump),
        .wb_sel(id_wb_sel)
    );

    // Register File Writeback connections (from WB stage)
    logic        wb_reg_write;
    logic [4:0]  wb_rd_addr;
    logic [31:0] wb_final_data;

    regfile u_regfile (
        .clk(clk),
        .rst_n(rst_n),
        .rs1_addr(id_rs1_addr),
        .rs1_data(id_rs1_data),
        .rs2_addr(id_rs2_addr),
        .rs2_data(id_rs2_data),
        .we(wb_reg_write),
        .rd_addr(wb_rd_addr),
        .rd_data(wb_final_data)
    );

    // Immediate Generator
    imm_gen u_imm_gen (
        .instr(id_instr),
        .imm_ext(id_imm_ext)
    );

    // -------------------------------------------------------------------------
    // Pipeline Register: ID -> EX
    // -------------------------------------------------------------------------
    logic        flush_id_ex;
    logic [31:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm_ext;
    logic [4:0]  ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    logic [2:0]  ex_funct3;
    logic        ex_reg_write, ex_mem_read, ex_mem_write, ex_alu_src, ex_branch;
    logic [3:0]  ex_alu_ctrl;
    logic [1:0]  ex_jump, ex_wb_sel;

    pipe_id_ex u_pipe_id_ex (
        .clk(clk),
        .rst_n(rst_n),
        .flush(flush_id_ex),
        .id_pc(id_pc),
        .id_rs1_data(id_rs1_data),
        .id_rs2_data(id_rs2_data),
        .id_imm_ext(id_imm_ext),
        .id_rs1_addr(id_rs1_addr),
        .id_rs2_addr(id_rs2_addr),
        .id_rd_addr(id_rd_addr),
        .id_funct3(id_funct3),
        .id_reg_write(id_reg_write),
        .id_mem_read(id_mem_read),
        .id_mem_write(id_mem_write),
        .id_alu_src(id_alu_src),
        .id_alu_ctrl(id_alu_ctrl),
        .id_branch(id_branch),
        .id_jump(id_jump),
        .id_wb_sel(id_wb_sel),
        
        .ex_pc(ex_pc),
        .ex_rs1_data(ex_rs1_data),
        .ex_rs2_data(ex_rs2_data),
        .ex_imm_ext(ex_imm_ext),
        .ex_rs1_addr(ex_rs1_addr),
        .ex_rs2_addr(ex_rs2_addr),
        .ex_rd_addr(ex_rd_addr),
        .ex_funct3(ex_funct3),
        .ex_reg_write(ex_reg_write),
        .ex_mem_read(ex_mem_read),
        .ex_mem_write(ex_mem_write),
        .ex_alu_src(ex_alu_src),
        .ex_alu_ctrl(ex_alu_ctrl),
        .ex_branch(ex_branch),
        .ex_jump(ex_jump),
        .ex_wb_sel(ex_wb_sel)
    );

    // =========================================================================
    // STAGE 3: EXECUTE (EX)
    // =========================================================================
    logic [1:0]  forward_a, forward_b;
    logic [31:0] mem_alu_result;
    logic [31:0] ex_alu_op_a, ex_alu_op_b, ex_forward_b_data;
    logic [31:0] ex_alu_result;
    logic        ex_alu_zero;

    // Forwarding Mux A (Operand 1)
    always_comb begin
        case (forward_a)
            FWD_EX_MEM: ex_alu_op_a = mem_alu_result;
            FWD_MEM_WB: ex_alu_op_a = wb_final_data;
            default:    ex_alu_op_a = ex_rs1_data;
        endcase
    end

    // Forwarding Mux B (Operand 2 before immediate selection)
    always_comb begin
        case (forward_b)
            FWD_EX_MEM: ex_forward_b_data = mem_alu_result;
            FWD_MEM_WB: ex_forward_b_data = wb_final_data;
            default:    ex_forward_b_data = ex_rs2_data;
        endcase
    end

    // ALUSrc Mux: Second ALU operand is either forwarded register data or immediate
    assign ex_alu_op_b = ex_alu_src ? ex_imm_ext : ex_forward_b_data;

    // 32-bit Arithmetic Logic Unit
    alu u_alu (
        .a(ex_alu_op_a),
        .b(ex_alu_op_b),
        .alu_ctrl(ex_alu_ctrl),
        .result(ex_alu_result),
        .zero(ex_alu_zero)
    );

    // Branch Unit
    branch_unit u_branch (
        .rs1_data(ex_alu_op_a),
        .rs2_data(ex_forward_b_data),
        .funct3(ex_funct3),
        .branch_enable(ex_branch),
        .current_pc(ex_pc),
        .imm_ext(ex_imm_ext),
        .branch_taken(branch_taken),
        .branch_target(branch_target)
    );

    logic [31:0] ex_pc_plus_4;
    assign ex_pc_plus_4 = ex_pc + 32'd4;

    // -------------------------------------------------------------------------
    // Pipeline Register: EX -> MEM
    // -------------------------------------------------------------------------
    logic [31:0] mem_write_data, mem_pc_plus_4;
    logic [4:0]  mem_rd_addr;
    logic [2:0]  mem_funct3;
    logic        mem_reg_write, mem_mem_read, mem_mem_write;
    logic [1:0]  mem_wb_sel;

    pipe_ex_mem u_pipe_ex_mem (
        .clk(clk),
        .rst_n(rst_n),
        .ex_alu_result(ex_alu_result),
        .ex_write_data(ex_forward_b_data),
        .ex_rd_addr(ex_rd_addr),
        .ex_pc_plus_4(ex_pc_plus_4),
        .ex_funct3(ex_funct3),
        .ex_reg_write(ex_reg_write),
        .ex_mem_read(ex_mem_read),
        .ex_mem_write(ex_mem_write),
        .ex_wb_sel(ex_wb_sel),

        .mem_alu_result(mem_alu_result),
        .mem_write_data(mem_write_data),
        .mem_rd_addr(mem_rd_addr),
        .mem_pc_plus_4(mem_pc_plus_4),
        .mem_funct3(mem_funct3),
        .mem_reg_write(mem_reg_write),
        .mem_mem_read(mem_mem_read),
        .mem_mem_write(mem_mem_write),
        .mem_wb_sel(mem_wb_sel)
    );

    // =========================================================================
    // STAGE 4: MEMORY ACCESS (MEM)
    // =========================================================================
    assign dmem_addr  = mem_alu_result;
    assign dmem_wdata = mem_write_data;
    assign dmem_we    = mem_mem_write;
    assign dmem_re    = mem_mem_read;
    assign dmem_strb  = 4'b1111; // Full word access default

    // -------------------------------------------------------------------------
    // Pipeline Register: MEM -> WB
    // -------------------------------------------------------------------------
    logic [31:0] wb_alu_result, wb_read_data, wb_pc_plus_4;
    logic [1:0]  wb_wb_sel;

    pipe_mem_wb u_pipe_mem_wb (
        .clk(clk),
        .rst_n(rst_n),
        .mem_alu_result(mem_alu_result),
        .mem_read_data(dmem_rdata),
        .mem_pc_plus_4(mem_pc_plus_4),
        .mem_rd_addr(mem_rd_addr),
        .mem_reg_write(mem_reg_write),
        .mem_wb_sel(mem_wb_sel),

        .wb_alu_result(wb_alu_result),
        .wb_read_data(wb_read_data),
        .wb_pc_plus_4(wb_pc_plus_4),
        .wb_rd_addr(wb_rd_addr),
        .wb_reg_write(wb_reg_write),
        .wb_wb_sel(wb_wb_sel)
    );

    // =========================================================================
    // STAGE 5: WRITEBACK (WB)
    // =========================================================================
    always_comb begin
        case (wb_wb_sel)
            WBMUX_MEM:  wb_final_data = wb_read_data;
            WBMUX_PC4:  wb_final_data = wb_pc_plus_4;
            default:    wb_final_data = wb_alu_result;
        endcase
    end

    // =========================================================================
    // ADVANCED ARCHITECTURAL UNITS (HAZARDS & FORWARDING)
    // =========================================================================
    // 1. Data Forwarding Unit
    forwarding_unit u_forwarding_unit (
        .ex_rs1_addr(ex_rs1_addr),
        .ex_rs2_addr(ex_rs2_addr),
        .mem_reg_write(mem_reg_write),
        .mem_rd_addr(mem_rd_addr),
        .wb_reg_write(wb_reg_write),
        .wb_rd_addr(wb_rd_addr),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    // 2. Hazard Detection Unit
    hazard_unit u_hazard_unit (
        .id_ex_mem_read(ex_mem_read),
        .id_ex_rd_addr(ex_rd_addr),
        .if_id_rs1_addr(id_rs1_addr),
        .if_id_rs2_addr(id_rs2_addr),
        .branch_taken(branch_taken),
        .stall_pc(stall_pc),
        .stall_if_id(stall_if_id),
        .flush_if_id(flush_if_id),
        .flush_id_ex(flush_id_ex)
    );

endmodule
