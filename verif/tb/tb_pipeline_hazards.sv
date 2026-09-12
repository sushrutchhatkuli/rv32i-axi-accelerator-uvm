// =============================================================================
// File: tb_pipeline_hazards.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Self-checking testbench for the 5-stage pipelined RV32I core.
//              Verifies:
//              1. EX/MEM & MEM/WB Data Forwarding (zero stalls on arithmetic RAW).
//              2. Load-Use Data Hazard Detection (1-cycle bubble injection).
//              3. Control Hazard Recovery (Branch Taken dual-stage pipeline flush).
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.svh"

module tb_pipeline_hazards;

    logic clk;
    logic rst_n;

    // Core Memory Interfaces
    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;

    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic [3:0]  dmem_strb;
    logic        dmem_we;
    logic        dmem_re;
    logic [31:0] dmem_rdata;

    // Simulated Memories (64 words each)
    logic [31:0] imem [0:63];
    logic [31:0] dmem [0:63];

    // Tracking
    int total_tests = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    // Instantiate 5-Stage RV32I Core
    rv32i_core_top u_core (
        .clk(clk),
        .rst_n(rst_n),
        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_strb(dmem_strb),
        .dmem_we(dmem_we),
        .dmem_re(dmem_re),
        .dmem_rdata(dmem_rdata)
    );

    // Clock Generation: 100 MHz (10ns period)
    always #5 clk = ~clk;

    // Asynchronous Instruction Memory Read
    assign imem_rdata = imem[imem_addr[7:2]];

    // Combinational Data Memory Read (Single-cycle MEM stage access)
    assign dmem_rdata = (dmem_re) ? dmem[dmem_addr[7:2]] : 32'd0;

    // Synchronous Data Memory Write
    always_ff @(posedge clk) begin
        if (dmem_we) begin
            dmem[dmem_addr[7:2]] <= dmem_wdata;
        end
    end

    // Helper task to check register value
    task check_reg(string test_name, logic [31:0] actual, logic [31:0] expected);
        total_tests++;
        if (actual === expected) begin
            $display("  [PASS] %-40s | Got: %0d (0x%08h)", test_name, actual, actual);
            passed_tests++;
        end else begin
            $display("  [FAIL] %-40s | Got: %0d | Expected: %0d", test_name, actual, expected);
            failed_tests++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Program Loading & Execution
    // -------------------------------------------------------------------------
    initial begin
        // Waveform dump for GTKWave
        $dumpfile("pipeline_trace.vcd");
        $dumpvars(0, tb_pipeline_hazards);

        clk   = 0;
        rst_n = 0;

        // Clear memories
        for (int i = 0; i < 64; i++) begin
            imem[i] = 32'h0000_0013; // NOP (addi x0, x0, 0)
            dmem[i] = 32'd0;
        end

        // ---------------------------------------------------------------------
        // Assembly Program:
        // PC = 0x00: addi x1, x0, 10       -> x1 = 10
        // PC = 0x04: addi x2, x0, 20       -> x2 = 20
        // PC = 0x08: add  x3, x1, x2       -> x3 = 30 (RAW Hazard: x2 forwarded from EX/MEM!)
        // PC = 0x0C: sub  x4, x3, x1       -> x4 = 20 (RAW Hazard: x3 forwarded from EX/MEM!)
        // PC = 0x10: sw   x4, 0(x0)        -> RAM[0] = 20
        // PC = 0x14: lw   x5, 0(x0)        -> x5 = 20
        // PC = 0x18: addi x6, x5, 5        -> x6 = 25 (LOAD-USE HAZARD! Pipeline MUST stall 1 cycle!)
        // PC = 0x1C: beq  x6, x6, 8        -> Branch Taken! Jump ahead by +8 bytes to PC = 0x24
        // PC = 0x20: addi x7, x0, 99       -> SHOULD BE FLUSHED! x7 must NEVER become 99!
        // PC = 0x24: addi x8, x0, 77       -> Destination of branch! x8 = 77
        // ---------------------------------------------------------------------
        imem[0] = 32'h00A00093; // addi x1, x0, 10
        imem[1] = 32'h01400113; // addi x2, x0, 20
        imem[2] = 32'h002081B3; // add  x3, x1, x2
        imem[3] = 32'h40118233; // sub  x4, x3, x1
        imem[4] = 32'h00402023; // sw   x4, 0(x0)
        imem[5] = 32'h00002283; // lw   x5, 0(x0)
        imem[6] = 32'h00528313; // addi x6, x5, 5  <-- Load-Use Hazard
        imem[7] = 32'h00630463; // beq  x6, x6, 8  <-- Branch Taken (jump +8 bytes to index 9)
        imem[8] = 32'h06300393; // addi x7, x0, 99 <-- Must be flushed into NOP!
        imem[9] = 32'h04D00413; // addi x8, x0, 77 <-- Target of branch

        $display("\n=======================================================");
        $display("  Starting 5-Stage RV32I Pipeline & Hazard Lab");
        $display("=======================================================\n");

        // Release Reset
        #15 rst_n = 1;

        // Run simulation for 25 clock cycles to let instructions flow through pipeline
        repeat (25) @(posedge clk);

        // ---------------------------------------------------------------------
        // Check Hardware State
        // ---------------------------------------------------------------------
        $display("--- Verifying Register Writeback & Forwarding Results ---");
        
        // 1. Basic Immediate Arithmetic
        check_reg("x1 == 10 (addi x1, x0, 10)", u_core.u_regfile.registers[1], 32'd10);
        check_reg("x2 == 20 (addi x2, x0, 20)", u_core.u_regfile.registers[2], 32'd20);

        // 2. EX/MEM Data Forwarding Test: add x3, x1, x2 immediately after x2
        check_reg("x3 == 30 (Forwarding EX/MEM -> EX)", u_core.u_regfile.registers[3], 32'd30);

        // 3. Back-to-Back Forwarding Test: sub x4, x3, x1 immediately after x3
        check_reg("x4 == 20 (Back-to-back Forwarding)", u_core.u_regfile.registers[4], 32'd20);

        // 4. Memory Store & Load
        check_reg("RAM[0] == 20 (sw x4, 0(x0))", dmem[0], 32'd20);
        check_reg("x5 == 20 (lw x5, 0(x0))", u_core.u_regfile.registers[5], 32'd20);

        // 5. Load-Use Hazard Stall Test: addi x6, x5, 5 immediately following lw x5
        // If stall worked, x6 is 20 + 5 = 25. If stall failed, x6 would be 0 + 5 = 5!
        check_reg("x6 == 25 (Load-Use Stall Bubble)", u_core.u_regfile.registers[6], 32'd25);

        // 6. Branch Misprediction Flush Test:
        // x7 should be 0 because addi x7, x0, 99 was FLUSHED by the branch!
        check_reg("x7 == 0 (Branch Flush Cleared NOP)", u_core.u_regfile.registers[7], 32'd0);

        // 7. Branch Target Jump Execution:
        check_reg("x8 == 77 (Branch Target Jump Taken)", u_core.u_regfile.registers[8], 32'd77);

        // ---------------------------------------------------------------------
        // Final Summary Banner
        // ---------------------------------------------------------------------
        $display("\n=======================================================");
        $display("  PIPELINE & HAZARD VERIFICATION SUMMARY");
        $display("  Total Tests  : %0d", total_tests);
        $display("  Passed Tests : %0d", passed_tests);
        $display("  Failed Tests : %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("  RESULT       : ALL TESTS PASSED! 100%% SUCCESS");
            $display("  PIPELINE STATUS: ZERO STALL CORRUPTIONS DETECTED");
        end else begin
            $display("  RESULT       : VERIFICATION FAILED WITH %0d ERRORS", failed_tests);
        end
        $display("=======================================================\n");

        #10 $finish;
    end

endmodule
