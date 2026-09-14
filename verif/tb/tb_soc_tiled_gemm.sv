// =============================================================================
// File: tb_soc_tiled_gemm.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Autonomous Hardware/Software Co-Verification Testbench for
//              Generic 4x4 Tiled Block GEMM (General Matrix Multiply).
//              Monitors 8 consecutive 2x2 coprocessor tile operations, software
//              accumulation, and verifies bit-exact 4x4 output matrix in RAM.
// =============================================================================

`timescale 1ns / 1ps

module tb_soc_tiled_gemm;

    logic        clk;
    logic        rst_n;
    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;
    logic        accel_irq_out;

    // 64 KB Instruction Memory (16384 x 32-bit words)
    logic [31:0] imem [0:16383];

    // Single-cycle instruction read
    assign imem_rdata = imem[imem_addr[15:2]];

    integer cycle_count;
    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer tile_calc_count;

    soc_top u_soc (
        .clk          (clk),
        .rst_n        (rst_n),
        .imem_addr    (imem_addr),
        .imem_rdata   (imem_rdata),
        .accel_irq_out(accel_irq_out)
    );

    // 50 MHz clock generation (20 ns period)
    always #10 clk = ~clk;

    // Helper assertion task
    task check_val(input string desc, input [31:0] actual, input [31:0] expected);
        total_tests = total_tests + 1;
        if (actual === expected) begin
            $display("  [PASS] %-48s | Got: 0x%08h (%0d)", desc, actual, actual);
            passed_tests = passed_tests + 1;
        end else begin
            $display("  [FAIL] %-48s | Got: 0x%08h | Expected: 0x%08h", desc, actual, expected);
            failed_tests = failed_tests + 1;
        end
    endtask

    initial begin
        $dumpfile("soc_tiled_gemm_trace.vcd");
        $dumpvars(0, tb_soc_tiled_gemm);

        clk             = 0;
        rst_n           = 0;
        cycle_count     = 0;
        total_tests     = 0;
        passed_tests    = 0;
        failed_tests    = 0;
        tile_calc_count = 0;

        // Initialize instruction memory with NOPs (0x00000013)
        for (int i = 0; i < 16384; i = i + 1) begin
            imem[i] = 32'h0000_0013;
            u_soc.u_ram_ctrl.ram_memory[i] = 32'd0;
        end

        // Load compiled Tiled GEMM firmware into instruction memory
        $readmemh("firmware/tiled_gemm.hex", imem);

        #40;
        rst_n = 1;
        $display("[BOOT] Reset released. RV32I Core fetching Tiled GEMM code from 0x0000_0000...\n");

        // Monitor execution until Tiled GEMM mailbox (RAM[0x1004] = word index 1025) is written
        while (cycle_count < 5000 && 
               u_soc.u_ram_ctrl.ram_memory[1025] !== 32'hFEED_C0DE && 
               u_soc.u_ram_ctrl.ram_memory[1025] !== 32'hDEAD_DEAD) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            if (u_soc.u_accel.u_fsm.state == 3'b001 && 
                u_soc.u_accel.u_fsm.row_i == 0 && 
                u_soc.u_accel.u_fsm.col_j == 0 && 
                u_soc.u_accel.u_fsm.k_idx == 0) begin
                tile_calc_count = tile_calc_count + 1;
                $display("[EVENT @ %0t ps] Accelerator Tile Run #%0d triggered via AXI MMIO!", $time, tile_calc_count);
            end
        end

        // Wait a few cycles for writeback completion
        repeat (20) @(posedge clk);

        $display("\n-------------------------------------------------------");
        $display("--- Step 1: Sub-Block C00 (Tiles A00*B00 + A01*B10 = 4*I) ---");
        check_val("C00 Row 0 (RAM[0x1010])", u_soc.u_ram_ctrl.ram_memory[1028], 32'h0000_0400);
        check_val("C00 Row 1 (RAM[0x1014])", u_soc.u_ram_ctrl.ram_memory[1029], 32'h0400_0000);

        $display("\n--- Step 2: Sub-Block C01 (Tiles A00*B01 + A01*B11 = 7*I) ---");
        check_val("C01 Row 0 (RAM[0x1018])", u_soc.u_ram_ctrl.ram_memory[1030], 32'h0000_0700);
        check_val("C01 Row 1 (RAM[0x101C])", u_soc.u_ram_ctrl.ram_memory[1031], 32'h0700_0000);

        $display("\n--- Step 3: Sub-Block C10 (Tiles A10*B00 + A11*B10 = 7*I) ---");
        check_val("C10 Row 0 (RAM[0x1020])", u_soc.u_ram_ctrl.ram_memory[1032], 32'h0000_0700);
        check_val("C10 Row 1 (RAM[0x1024])", u_soc.u_ram_ctrl.ram_memory[1033], 32'h0700_0000);

        $display("\n--- Step 4: Sub-Block C11 (Tiles A10*B01 + A11*B11 = 6*I) ---");
        check_val("C11 Row 0 (RAM[0x1028])", u_soc.u_ram_ctrl.ram_memory[1034], 32'h0000_0600);
        check_val("C11 Row 1 (RAM[0x102C])", u_soc.u_ram_ctrl.ram_memory[1035], 32'h0600_0000);

        $display("\n--- Step 5: Tiled GEMM Mailbox & Coprocessor Utilization ---");
        check_val("Total Accelerator Tile Runs Executed", tile_calc_count, 32'd8);
        check_val("Tiled GEMM Mailbox at 0x1004 (PASS Signature)", u_soc.u_ram_ctrl.ram_memory[1025], 32'hFEED_C0DE);

        $display("\n=======================================================");
        $display("  TILED BLOCK GEMM CO-VERIFICATION SUMMARY");
        $display("  Total Tests  : %0d", total_tests);
        $display("  Passed Tests : %0d", passed_tests);
        $display("  Failed Tests : %0d", failed_tests);
        $display("  Total Cycles : %0d", cycle_count);
        if (failed_tests == 0) begin
            $display("  RESULT       : ALL TESTS PASSED! 100%% SUCCESS");
            $display("  SYSTEM STATE : FULL 4x4 TILED GEMM BIT-EXACT ON SILICON");
        end else begin
            $display("  RESULT       : FAILURES DETECTED IN TILED GEMM EXECUTION");
        end
        $display("=======================================================\n");

        #50;
        $finish;
    end

endmodule
