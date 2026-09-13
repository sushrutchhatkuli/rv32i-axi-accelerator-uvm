// =============================================================================
// File: mac_unit.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Single Q8.8 Signed Fixed-Point Multiply-Accumulate (MAC) Unit.
//              Computes: acc += (a * b) >> 8
//              Includes saturation clamping to prevent arithmetic wraparound.
//              Q8.8 format: 1 sign bit, 7 integer bits, 8 fractional bits.
//              Max positive: +127.996 (0x7FFF), Min negative: -128.0 (0x8000).
// =============================================================================

`timescale 1ns / 1ps

module mac_unit (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        clear,      // Synchronous clear of accumulator
    input  logic        enable,     // Latch product into accumulator

    input  logic signed [15:0] a,   // Q8.8 operand A
    input  logic signed [15:0] b,   // Q8.8 operand B

    output logic signed [31:0] acc, // 32-bit accumulator (upper bits for headroom)
    output logic        overflow    // Sticky saturation flag
);

    // 32-bit product of two 16-bit Q8.8 numbers produces Q16.16
    logic signed [31:0] product;
    // Arithmetic right shift by 8 bits aligns Q16.16 back to Q8.8
    logic signed [31:0] product_shifted;
    // Next accumulator value before saturation clamping
    logic signed [31:0] next_acc;

    assign product         = a * b;
    assign product_shifted = product >>> 8;
    assign next_acc        = acc + product_shifted;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc      <= 32'sd0;
            overflow <= 1'b0;
        end else if (clear) begin
            acc      <= 32'sd0;
            overflow <= 1'b0;
        end else if (enable) begin
            // Saturation clamping to 16-bit signed Q8.8 range extended to 32 bits
            if (next_acc > 32'sh0000_7FFF) begin
                acc      <= 32'sh0000_7FFF;
                overflow <= 1'b1;
            end else if (next_acc < -32'sh0000_8000) begin
                acc      <= -32'sh0000_8000;
                overflow <= 1'b1;
            end else begin
                acc      <= next_acc;
                overflow <= overflow; // Retain sticky state
            end
        end
    end

endmodule
