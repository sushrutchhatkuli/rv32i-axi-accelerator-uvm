// =============================================================================
// File: accel_fsm.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Matrix Multiplication Execution Sequencer FSM.
//              Iterates through Row i and Column j of matrices A and B,
//              reading vector elements from the scratchpad buffer, feeding the
//              MAC unit, and writing the final Q8.8 result into Matrix C.
//              Holds DONE and IRQ asserted until the next START pulse arrives.
// =============================================================================

`timescale 1ns / 1ps

module accel_fsm (
    input  logic        clk,
    input  logic        rst_n,

    // Control Inputs (from CSR)
    input  logic        start,
    input  logic        soft_reset,
    input  logic        irq_en,
    input  logic [7:0]  dim,
    input  logic [15:0] src_a_ptr,      // In halfword units
    input  logic [15:0] src_b_ptr,
    input  logic [15:0] dst_ptr,

    // Status & Interrupt Outputs
    output logic        busy,
    output logic        done,
    output logic        overflow_flag,
    output logic        irq,

    // Buffer Port B Interface (16-bit halfword access)
    output logic        buf_we,
    output logic [9:0]  buf_addr,
    output logic [15:0] buf_wdata,
    input  logic [15:0] buf_rdata,

    // MAC Unit Interface
    output logic        mac_clear,
    output logic        mac_enable,
    output logic signed [15:0] mac_a,
    output logic signed [15:0] mac_b,
    input  logic signed [31:0] mac_acc,
    input  logic        mac_overflow
);

    // FSM States
    typedef enum logic [2:0] {
        ST_IDLE         = 3'b000,
        ST_SETUP_A      = 3'b001, // Present buffer address for A element
        ST_READ_A       = 3'b010, // Latch A, present address for B element
        ST_READ_B_MAC   = 3'b011, // Latch B, fire mac_enable
        ST_ACC_WAIT     = 3'b100, // Wait 1 cycle for mac_acc to latch new sum
        ST_WRITE_RESULT = 3'b101, // Write accumulated cell C[i][j] into buffer
        ST_FINISH       = 3'b110  // Assert DONE and IRQ until next START
    } state_t;

    state_t state;

    // Iteration counters
    logic [7:0] row_i;
    logic [7:0] col_j;
    logic [7:0] k_idx;
    logic [7:0] dim_reg;

    // Latched buffer base pointers
    logic [15:0] a_base;
    logic [15:0] b_base;
    logic [15:0] c_base;

    // Latch element A
    logic signed [15:0] a_elem;
    logic overflow_sticky;

    // Address calculation in halfword units
    wire [9:0] addr_a = a_base[9:0] + (row_i * dim_reg) + k_idx;
    wire [9:0] addr_b = b_base[9:0] + (k_idx * dim_reg) + col_j;
    wire [9:0] addr_c = c_base[9:0] + (row_i * dim_reg) + col_j;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            row_i           <= 8'd0;
            col_j           <= 8'd0;
            k_idx           <= 8'd0;
            dim_reg         <= 8'd0;
            a_base          <= 16'd0;
            b_base          <= 16'd0;
            c_base          <= 16'd0;
            busy            <= 1'b0;
            done            <= 1'b0;
            irq             <= 1'b0;
            overflow_flag   <= 1'b0;
            overflow_sticky <= 1'b0;
            a_elem          <= 16'sd0;
            buf_we          <= 1'b0;
            buf_addr        <= 10'd0;
            buf_wdata       <= 16'd0;
            mac_clear       <= 1'b0;
            mac_enable      <= 1'b0;
            mac_a           <= 16'sd0;
            mac_b           <= 16'sd0;
        end else if (soft_reset) begin
            state           <= ST_IDLE;
            row_i           <= 8'd0;
            col_j           <= 8'd0;
            k_idx           <= 8'd0;
            dim_reg         <= 8'd0;
            a_base          <= 16'd0;
            b_base          <= 16'd0;
            c_base          <= 16'd0;
            busy            <= 1'b0;
            done            <= 1'b0;
            irq             <= 1'b0;
            overflow_flag   <= 1'b0;
            overflow_sticky <= 1'b0;
            a_elem          <= 16'sd0;
            buf_we          <= 1'b0;
            buf_addr        <= 10'd0;
            buf_wdata       <= 16'd0;
            mac_clear       <= 1'b0;
            mac_enable      <= 1'b0;
            mac_a           <= 16'sd0;
            mac_b           <= 16'sd0;
        end else begin
            // Default single-cycle pulses
            mac_clear  <= 1'b0;
            mac_enable <= 1'b0;
            buf_we     <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        dim_reg         <= dim;
                        a_base          <= src_a_ptr;
                        b_base          <= src_b_ptr;
                        c_base          <= dst_ptr;
                        row_i           <= 8'd0;
                        col_j           <= 8'd0;
                        k_idx           <= 8'd0;
                        busy            <= 1'b1;
                        done            <= 1'b0;
                        irq             <= 1'b0;
                        overflow_sticky <= 1'b0;
                        overflow_flag   <= 1'b0;
                        mac_clear       <= 1'b1;
                        state           <= ST_SETUP_A;
                    end
                end

                ST_SETUP_A: begin
                    buf_addr <= addr_a;
                    state    <= ST_READ_A;
                end

                ST_READ_A: begin
                    a_elem   <= $signed(buf_rdata);
                    buf_addr <= addr_b;
                    state    <= ST_READ_B_MAC;
                end

                ST_READ_B_MAC: begin
                    mac_a      <= a_elem;
                    mac_b      <= $signed(buf_rdata);
                    mac_enable <= 1'b1;

                    if (k_idx == dim_reg - 8'd1) begin
                        state <= ST_ACC_WAIT;
                    end else begin
                        k_idx <= k_idx + 8'd1;
                        state <= ST_SETUP_A;
                    end
                end

                // Wait 1 cycle for mac_acc to latch the final product sum
                ST_ACC_WAIT: begin
                    state <= ST_WRITE_RESULT;
                end

                ST_WRITE_RESULT: begin
                    buf_we    <= 1'b1;
                    buf_addr  <= addr_c;
                    buf_wdata <= mac_acc[15:0]; // Q8.8 result

                    if (mac_overflow) begin
                        overflow_sticky <= 1'b1;
                    end

                    if (col_j == dim_reg - 8'd1) begin
                        col_j <= 8'd0;
                        if (row_i == dim_reg - 8'd1) begin
                            state <= ST_FINISH;
                        end else begin
                            row_i     <= row_i + 8'd1;
                            k_idx     <= 8'd0;
                            mac_clear <= 1'b1;
                            state     <= ST_SETUP_A;
                        end
                    end else begin
                        col_j     <= col_j + 8'd1;
                        k_idx     <= 8'd0;
                        mac_clear <= 1'b1;
                        state     <= ST_SETUP_A;
                    end
                end

                ST_FINISH: begin
                    busy          <= 1'b0;
                    done          <= 1'b1;
                    overflow_flag <= overflow_sticky;
                    if (irq_en) begin
                        irq <= 1'b1;
                    end
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
