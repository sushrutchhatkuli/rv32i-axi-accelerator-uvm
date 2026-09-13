// =============================================================================
// File: tb_soc_firmware.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: End-to-End Hardware/Software Co-Verification Testbench.
//              Loads compiled RISC-V bare-metal firmware into RAM, releases
//              reset, and monitors the CPU autonomously executing instructions,
//              programming the matrix accelerator across the AMBA AXI4-Lite bus,
//              handling the hardware interrupt, and validating the math result.
// =============================================================================

`timescale 1ns / 1ps

module tb_soc_firmware;

    logic        clk;
    logic        rst_n;
    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;
    logic        accel_irq_out;

    // 64 KB Instruction Memory (16384 x 32-bit words)
    logic [31:0] imem [0:16383];

    // Single-cycle instruction read
    assign imem_rdata = imem[imem_addr[15:2]];

    // Instantiate Top-Level SoC DUT
    soc_top u_soc (
        .clk          (clk),
        .rst_n        (rst_n),
        .imem_addr    (imem_addr),
        .imem_rdata   (imem_rdata),
        .accel_irq_out(accel_irq_out)
    );

    // Clock Generation: 50 MHz (20ns period)
    always #10 clk = ~clk;

    // Verification statistics
    integer cycle_count;
    integer total_tests;
    integer passed_tests;
    integer failed_tests;

    task check_val(string name, logic [31:0] actual, logic [31:0] expected);
        total_tests = total_tests + 1;
        if (actual === expected) begin
            $display("  [PASS] %-48s | Got: 0x%08h (%0d)", name, actual, actual);
            passed_tests = passed_tests + 1;
        end else begin
            $display("  [FAIL] %-48s | Got: 0x%08h | Expected: 0x%08h", name, actual, expected);
            failed_tests = failed_tests + 1;
        end
    endtask

    initial begin
        $dumpfile("soc_firmware_trace.vcd");
        $dumpvars(0, tb_soc_firmware);

        clk          = 0;
        rst_n        = 0;
        cycle_count  = 0;
        total_tests  = 0;
        passed_tests = 0;
        failed_tests = 0;

        // Initialize instruction memory with NOPs (0x00000013)
        for (int i = 0; i < 16384; i = i + 1) begin
            imem[i] = 32'h0000_0013;
            u_soc.u_ram_ctrl.ram_memory[i] = 32'd0;
        end

        // Load compiled RISC-V machine code into instruction memory
        $readmemh("firmware/firmware.hex", imem);

        $display("\n=======================================================");
        $display("  STARTING HARDWARE / SOFTWARE CO-VERIFICATION LAB");
        $display("  Autonomous RISC-V Bare-Metal Execution on Silicon");
        $display("=======================================================\n");

        #40;
        rst_n = 1;
        $display("[BOOT] Power-on reset released. RV32I Core fetching from 0x0000_0000...\n");

        // Monitor CPU execution until mailbox signature is written or timeout occurs
        while (cycle_count < 2000 && u_soc.u_ram_ctrl.ram_memory[1024] !== 32'hCAFE_BABE && u_soc.u_ram_ctrl.ram_memory[1024] !== 32'hDEAD_DEAD) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            if (u_soc.u_accel.csr_we) begin
                $display("[CSR WRITE @ %0t ps] addr=0x%02h data=0x%08h", $time, u_soc.u_accel.csr_wr_addr, u_soc.u_accel.csr_wdata);
            end

            if (u_soc.u_accel.buf_a_we) begin
                $display("[BUF WRITE @ %0t ps] addr=0x%03h data=0x%08h", $time, u_soc.u_accel.buf_a_addr, u_soc.u_accel.buf_a_wdata);
            end

            // Log milestone events
            if (u_soc.u_accel.u_fsm.state == 3'b001 && u_soc.u_accel.u_fsm.row_i == 0 && u_soc.u_accel.u_fsm.col_j == 0 && u_soc.u_accel.u_fsm.k_idx == 0) begin
                $display("[EVENT @ %0t ps] Accelerator FSM triggered via AXI MMIO write!", $time);
            end

            if (accel_irq_out) begin
                $display("[EVENT @ %0t ps] Hardware interrupt (accel_irq_out) asserted by coprocessor!", $time);
            end
        end

        // Allow a few extra cycles for CPU to store final signature and halt
        repeat (20) @(posedge clk);

        $display("\n-------------------------------------------------------");
        $display("--- Step 1: Accelerator Buffer Contents Written by CPU ---");
        check_val("Matrix A Row 0 in Buffer (0x100)", u_soc.u_accel.u_buffer.mem[0], 32'h0200_0100);
        check_val("Matrix A Row 1 in Buffer (0x104)", u_soc.u_accel.u_buffer.mem[1], 32'h0400_0300);
        check_val("Matrix B Row 0 in Buffer (0x108)", u_soc.u_accel.u_buffer.mem[2], 32'h0600_0500);
        check_val("Matrix B Row 1 in Buffer (0x10C)", u_soc.u_accel.u_buffer.mem[3], 32'h0800_0700);

        $display("\n--- Step 2: Accelerator Configuration Written by CPU ---");
        check_val("Matrix Dimension CSR (REG_DIM)", u_soc.u_accel.u_csr.dim_reg, 32'd2);
        check_val("Matrix Source A Pointer (REG_SRC_A)", u_soc.u_accel.u_csr.src_a_reg, 32'd0);
        check_val("Matrix Source B Pointer (REG_SRC_B)", u_soc.u_accel.u_csr.src_b_reg, 32'd4);
        check_val("Matrix Destination Pointer (REG_DST)", u_soc.u_accel.u_csr.dst_reg, 32'd8);

        $display("\n--- Step 3: Hardware Accelerator Computation Status ---");
        check_val("Accelerator Done Flag Asserted", {31'd0, u_soc.u_accel.u_fsm.done}, 32'd1);
        check_val("Accelerator IRQ Raised", {31'd0, accel_irq_out}, 32'd1);

        $display("\n--- Step 4: Hardware Matrix Multiplication Output C ---");
        check_val("Result C[0][0]=19, C[0][1]=22 (Q8.8)", u_soc.u_accel.u_buffer.mem[4], 32'h1600_1300);
        check_val("Result C[1][0]=43, C[1][1]=50 (Q8.8)", u_soc.u_accel.u_buffer.mem[5], 32'h3200_2B00);

        $display("\n--- Step 5: CPU Software Mailbox Verification ---");
        $display("  [DEBUG] Reg t3 (actual C0)   = 0x%08h", u_soc.u_core.u_regfile.registers[28]);
        $display("  [DEBUG] Reg t5 (expected C0) = 0x%08h", u_soc.u_core.u_regfile.registers[30]);
        $display("  [DEBUG] Reg t4 (actual C1)   = 0x%08h", u_soc.u_core.u_regfile.registers[29]);
        $display("  [DEBUG] Reg t6 (expected C1) = 0x%08h", u_soc.u_core.u_regfile.registers[31]);
        check_val("RAM Mailbox at 0x1000 (PASS Signature)", u_soc.u_ram_ctrl.ram_memory[1024], 32'hCAFE_BABE);

        $display("\n=======================================================");
        $display("  AUTONOMOUS HW/SW CO-VERIFICATION SUMMARY");
        $display("  Total Tests  : %0d", total_tests);
        $display("  Passed Tests : %0d", passed_tests);
        $display("  Failed Tests : %0d", failed_tests);
        $display("  Total Cycles : %0d", cycle_count);
        if (failed_tests == 0) begin
            $display("  RESULT       : ALL TESTS PASSED! 100%% SUCCESS");
            $display("  SYSTEM STATE : FULL HW/SW INTEGRATION VERIFIED");
        end else begin
            $display("  RESULT       : FAILURES DETECTED IN FIRMWARE EXECUTION");
        end
        $display("=======================================================\n");

        #50;
        $finish;
    end

endmodule
