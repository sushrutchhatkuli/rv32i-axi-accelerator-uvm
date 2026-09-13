// =============================================================================
// File: accel_csr.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Control & Status Register (CSR) Bank for the Matrix Accelerator.
//              Memory map offsets:
//                0x00: CTRL (bit 0 = START, bit 1 = IRQ_EN, bit 2 = SOFT_RESET)
//                0x04: STATUS (bit 0 = BUSY, bit 1 = DONE, bit 2 = OVERFLOW)
//                0x08: DIM (Matrix dimension N)
//                0x10: SRC_A_PTR (Halfword offset to Matrix A)
//                0x14: SRC_B_PTR (Halfword offset to Matrix B)
//                0x18: DST_PTR (Halfword offset to Result C)
// =============================================================================

`timescale 1ns / 1ps

module accel_csr (
    input  logic        clk,
    input  logic        rst_n,

    // Register Read/Write Ports (from AXI Slave logic)
    input  logic        reg_we,
    input  logic [4:0]  reg_wr_addr,
    input  logic [31:0] reg_wdata,
    input  logic [4:0]  reg_rd_addr,
    output logic [31:0] reg_rdata,

    // Hardware Control Outputs (to FSM)
    output logic        ctrl_start,
    output logic        ctrl_irq_en,
    output logic        ctrl_soft_reset,
    output logic [7:0]  cfg_dim,
    output logic [15:0] cfg_src_a_ptr,
    output logic [15:0] cfg_src_b_ptr,
    output logic [15:0] cfg_dst_ptr,

    // Hardware Status Inputs (from FSM)
    input  logic        sts_busy,
    input  logic        sts_done,
    input  logic        sts_overflow
);

    logic [31:0] ctrl_reg;
    logic [31:0] dim_reg;
    logic [31:0] src_a_reg;
    logic [31:0] src_b_reg;
    logic [31:0] dst_reg;

    // Status register is assembled dynamically
    logic [31:0] status_reg;
    assign status_reg = {29'd0, sts_overflow, sts_done, sts_busy};

    // Drive static control signals
    assign ctrl_irq_en   = ctrl_reg[1];
    assign cfg_dim       = dim_reg[7:0];
    assign cfg_src_a_ptr = src_a_reg[15:0];
    assign cfg_src_b_ptr = src_b_reg[15:0];
    assign cfg_dst_ptr   = dst_reg[15:0];

    // Single-cycle self-clearing command pulses
    logic start_pulse;
    logic reset_pulse;

    assign ctrl_start      = start_pulse;
    assign ctrl_soft_reset = reset_pulse;

    // -------------------------------------------------------------------------
    // Synchronous Register Writes
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_reg    <= 32'd0;
            dim_reg     <= 32'd4;          // Default 4x4 matrix
            src_a_reg   <= 32'h0000_0000;
            src_b_reg   <= 32'h0000_0004;
            dst_reg     <= 32'h0000_0008;
            start_pulse <= 1'b0;
            reset_pulse <= 1'b0;
        end else begin
            start_pulse <= 1'b0;
            reset_pulse <= 1'b0;

            if (reg_we) begin
                case (reg_wr_addr)
                    5'h00: begin
                        ctrl_reg <= reg_wdata;
                        if (reg_wdata[0]) start_pulse <= 1'b1;
                        if (reg_wdata[2]) reset_pulse <= 1'b1;
                    end
                    // 5'h04 is STATUS (read-only, writes ignored)
                    5'h08: dim_reg   <= reg_wdata;
                    5'h10: src_a_reg <= reg_wdata;
                    5'h14: src_b_reg <= reg_wdata;
                    5'h18: dst_reg   <= reg_wdata;
                    default: ;
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // Combinational Register Reads
    // -------------------------------------------------------------------------
    always_comb begin
        case (reg_rd_addr)
            5'h00:   reg_rdata = ctrl_reg;
            5'h04:   reg_rdata = status_reg;
            5'h08:   reg_rdata = dim_reg;
            5'h10:   reg_rdata = src_a_reg;
            5'h14:   reg_rdata = src_b_reg;
            5'h18:   reg_rdata = dst_reg;
            default: reg_rdata = 32'd0;
        endcase
    end

endmodule
