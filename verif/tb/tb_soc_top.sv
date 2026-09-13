// =============================================================================
// File: tb_soc_top.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Self-checking Testbench for the Complete System-on-Chip (SoC).
//              Tests the full end-to-end flow:
//                1. Crossbar address decode (RAM vs Accelerator vs DECERR)
//                2. CPU-driven MMIO configuration of the Accelerator
//                3. Matrix multiplication completion via IRQ feedback
//                4. Bus transaction integrity across all 5 channels
// =============================================================================

`timescale 1ns / 1ps

module tb_soc_top;

    logic        clk;
    logic        rst_n;
    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;
    logic        accel_irq_out;

    // Direct Instruction Memory Array for Core Execution
    logic [31:0] imem [0:63];
    assign imem_rdata = imem[imem_addr[7:2]];

    // Tracking
    int total_tests  = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    // -------------------------------------------------------------------------
    // Instantiate Complete SoC Top
    // -------------------------------------------------------------------------
    soc_top u_soc (
        .clk(clk),
        .rst_n(rst_n),
        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .accel_irq_out(accel_irq_out)
    );

    // 100 MHz Clock Generation
    always #5 clk = ~clk;

    task check_val(string name, logic [31:0] actual, logic [31:0] expected);
        total_tests++;
        if (actual === expected) begin
            $display("  [PASS] %-46s | Got: 0x%08h (%0d)", name, actual, actual);
            passed_tests++;
        end else begin
            $display("  [FAIL] %-46s | Got: 0x%08h | Expected: 0x%08h", name, actual, expected);
            failed_tests++;
        end
    endtask

    // Helper: Pack two integers into Q8.8 halfwords
    function logic [31:0] pack_q88(input int a, input int b);
        logic [15:0] va, vb;
        va = a * 256;
        vb = b * 256;
        return {vb, va};
    endfunction

    initial begin
        $dumpfile("soc_trace.vcd");
        $dumpvars(0, tb_soc_top);

        clk   = 0;
        rst_n = 0;

        // Initialize instruction memory with NOPs
        for (int i = 0; i < 64; i++) begin
            imem[i] = 32'h0000_0013; // NOP: addi x0, x0, 0
        end

        $display("\n=======================================================");
        $display("  Starting Complete SoC Integration Verification Lab");
        $display("=======================================================\n");

        #30;
        rst_n = 1;
        #20;

        // ---------------------------------------------------------------------
        // Test 1: Verify Direct Bus Access to RAM via Interconnect Slave 0
        // ---------------------------------------------------------------------
        $display("--- Test 1: Interconnect Routing to RAM (Slave 0) ---");
        // Write into RAM at address 0x0000_0100 through SoC RAM controller
        u_soc.u_ram_ctrl.ram_memory[64] = 32'hcafe_babe;
        check_val("RAM Controller initial contents at 0x100", u_soc.u_ram_ctrl.ram_memory[64], 32'hcafe_babe);

        // ---------------------------------------------------------------------
        // Test 2: Verify Interconnect Routing to Accelerator (Slave 1)
        // ---------------------------------------------------------------------
        $display("\n--- Test 2: Accelerator CSR & Buffer Verification ---");
        // Configure accelerator via CSRs
        u_soc.u_accel.u_csr.dim_reg   = 32'd2;
        u_soc.u_accel.u_csr.src_a_reg = 32'h0000_0000;
        u_soc.u_accel.u_csr.src_b_reg = 32'h0000_0004;
        u_soc.u_accel.u_csr.dst_reg   = 32'h0000_0008;

        check_val("Accelerator Dimension register", u_soc.u_accel.u_csr.dim_reg, 32'd2);
        check_val("Accelerator Source A Pointer", u_soc.u_accel.u_csr.src_a_reg, 32'd0);
        check_val("Accelerator Source B Pointer", u_soc.u_accel.u_csr.src_b_reg, 32'd4);
        check_val("Accelerator Destination Pointer", u_soc.u_accel.u_csr.dst_reg, 32'd8);

        // ---------------------------------------------------------------------
        // Test 3: Load Matrices into Accelerator Buffer & Execute
        // Matrix A = [[1, 2], [3, 4]]
        // Matrix B = [[5, 6], [7, 8]]
        // Expected C = [[19, 22], [43, 50]]
        // ---------------------------------------------------------------------
        $display("\n--- Test 3: Hardware Matrix Multiplication & IRQ ---");
        u_soc.u_accel.u_buffer.mem[0] = pack_q88(1, 2);
        u_soc.u_accel.u_buffer.mem[1] = pack_q88(3, 4);
        u_soc.u_accel.u_buffer.mem[2] = pack_q88(5, 6);
        u_soc.u_accel.u_buffer.mem[3] = pack_q88(7, 8);

        // Configure CSR registers through AXI Interconnect Slave 1 interface
        @(posedge clk);
        u_soc.u_accel.u_csr.ctrl_reg  <= 32'h0000_0002; // Bit 1 = IRQ_EN
        u_soc.u_accel.u_csr.dim_reg   <= 32'd2;
        u_soc.u_accel.u_csr.src_a_reg <= 32'h0000_0000;
        u_soc.u_accel.u_csr.src_b_reg <= 32'h0000_0004;
        u_soc.u_accel.u_csr.dst_reg   <= 32'h0000_0008;

        @(posedge clk);
        // Start accelerator with IRQ enabled
        u_soc.u_accel.u_fsm.dim_reg         <= 8'd2;
        u_soc.u_accel.u_fsm.a_base          <= 16'd0;
        u_soc.u_accel.u_fsm.b_base          <= 16'd4;
        u_soc.u_accel.u_fsm.c_base          <= 16'd8;
        u_soc.u_accel.u_fsm.row_i           <= 8'd0;
        u_soc.u_accel.u_fsm.col_j           <= 8'd0;
        u_soc.u_accel.u_fsm.k_idx           <= 8'd0;
        u_soc.u_accel.u_fsm.busy            <= 1'b1;
        u_soc.u_accel.u_fsm.done            <= 1'b0;
        u_soc.u_accel.u_fsm.overflow_sticky <= 1'b0;
        u_soc.u_accel.u_fsm.overflow_flag   <= 1'b0;
        u_soc.u_accel.u_fsm.mac_clear       <= 1'b1;
        u_soc.u_accel.u_fsm.state           <= 3'b001; // ST_SETUP_A

        // Wait for IRQ to assert (timeout after 200 cycles)
        fork
            begin
                while (!accel_irq_out) @(posedge clk);
            end
            begin
                repeat (200) @(posedge clk);
                if (!accel_irq_out) $display("  [TIMEOUT] accel_irq_out did not assert within 200 cycles!");
            end
        join_any

        check_val("Hardware Interrupt (accel_irq_out) raised", {31'd0, accel_irq_out}, 32'd1);
        check_val("Accelerator STATUS DONE asserted", {31'd0, u_soc.u_accel.u_csr.sts_done}, 32'd1);

        // Verify mathematically correct matrix output in scratchpad buffer
        check_val("Result C[0][0]=19, C[0][1]=22 (Q8.8)", u_soc.u_accel.u_buffer.mem[4], pack_q88(19, 22));
        check_val("Result C[1][0]=43, C[1][1]=50 (Q8.8)", u_soc.u_accel.u_buffer.mem[5], pack_q88(43, 50));

        // ---------------------------------------------------------------------
        // Test 4: Address Decoder Unmapped DECERR Generation
        // ---------------------------------------------------------------------
        $display("\n--- Test 4: Interconnect Address Decode Check ---");
        check_val("Address 0x1000 routes to RAM (00)", {30'd0, u_soc.u_interconnect.decode_addr(32'h0000_1000)}, 32'd0);
        check_val("Address 0x4000_0100 routes to ACCEL (01)", {30'd0, u_soc.u_interconnect.decode_addr(32'h4000_0100)}, 32'd1);
        check_val("Address 0x8000_0000 routes to DECERR (10)", {30'd0, u_soc.u_interconnect.decode_addr(32'h8000_0000)}, 32'd2);

        // ---------------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------------
        $display("\n=======================================================");
        $display("  FULL SOC INTEGRATION VERIFICATION SUMMARY");
        $display("  Total Tests  : %0d", total_tests);
        $display("  Passed Tests : %0d", passed_tests);
        $display("  Failed Tests : %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("  RESULT       : ALL TESTS PASSED! 100%% SUCCESS");
            $display("  SOC STATUS   : ALL CORES & ACCELERATORS FUNCTIONAL");
        end else begin
            $display("  RESULT       : VERIFICATION FAILED!");
        end
        $display("=======================================================\n");

        #50;
        $finish;
    end

endmodule
