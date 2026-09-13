// =============================================================================
// File: soc_scoreboard.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Verification Scoreboard with Golden Reference Predictor.
//              Compares output matrices from the hardware accelerator against
//              the bit-exact output computed by the golden model.
// =============================================================================

`timescale 1ns / 1ps

class soc_scoreboard;

    integer total_checks;
    integer passed_checks;
    integer failed_checks;

    function new();
        total_checks  = 0;
        passed_checks = 0;
        failed_checks = 0;
    endfunction

    // Direct Software Reference Algorithm in SystemVerilog
    task reference_matrix_multiply(
        input  logic signed [15:0] a00, input logic signed [15:0] a01,
        input  logic signed [15:0] a10, input logic signed [15:0] a11,
        input  logic signed [15:0] b00, input logic signed [15:0] b01,
        input  logic signed [15:0] b10, input logic signed [15:0] b11,
        output logic signed [15:0] c00, output logic signed [15:0] c01,
        output logic signed [15:0] c10, output logic signed [15:0] c11
    );
        int acc;

        // C[0][0] = A00*B00 + A01*B10
        acc = (int'(a00) * int'(b00) >>> 8) + (int'(a01) * int'(b10) >>> 8);
        c00 = (acc > 32767) ? 16'sh7FFF : ((acc < -32768) ? -16'sh8000 : acc[15:0]);

        // C[0][1] = A00*B01 + A01*B11
        acc = (int'(a00) * int'(b01) >>> 8) + (int'(a01) * int'(b11) >>> 8);
        c01 = (acc > 32767) ? 16'sh7FFF : ((acc < -32768) ? -16'sh8000 : acc[15:0]);

        // C[1][0] = A10*B00 + A11*B10
        acc = (int'(a10) * int'(b00) >>> 8) + (int'(a11) * int'(b10) >>> 8);
        c10 = (acc > 32767) ? 16'sh7FFF : ((acc < -32768) ? -16'sh8000 : acc[15:0]);

        // C[1][1] = A10*B01 + A11*B11
        acc = (int'(a10) * int'(b01) >>> 8) + (int'(a11) * int'(b11) >>> 8);
        c11 = (acc > 32767) ? 16'sh7FFF : ((acc < -32768) ? -16'sh8000 : acc[15:0]);
    endtask

    // Check DUT Result against Golden Prediction
    function void check_elem(string name, logic signed [15:0] actual, logic signed [15:0] expected);
        total_checks = total_checks + 1;
        if (actual === expected) begin
            passed_checks = passed_checks + 1;
            $display("  [SCOREBOARD MATCH] %-36s | Got: 0x%04h (%0d)", name, actual, actual);
        end else begin
            failed_checks = failed_checks + 1;
            $display("  [SCOREBOARD MISMATCH] %-33s | Got: 0x%04h | Expected: 0x%04h", name, actual, expected);
        end
    endfunction

    function void print_summary();
        $display("\n=======================================================");
        $display("  UVM SCOREBOARD & GOLDEN PREDICTOR SUMMARY");
        $display("  Total Checks  : %0d", total_checks);
        $display("  Passed Checks : %0d", passed_checks);
        $display("  Failed Checks : %0d", failed_checks);
        if (failed_checks == 0) begin
            $display("  VERDICT       : 100%% MATHEMATICAL ACCURACY CONFIRMED");
        end else begin
            $display("  VERDICT       : SCOREBOARD DETECTED MATHEMATICAL ERRORS");
        end
        $display("=======================================================\n");
    endfunction

endclass
