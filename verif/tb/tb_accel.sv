// =============================================================================
// File: tb_accel.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Self-checking Testbench for the Custom Matrix Accelerator.
//              Verifies CSR read/write, buffer load, 2x2 matrix multiply,
//              result correctness, IRQ assertion, and STATUS flags.
//              Uses the AXI4-Lite Master Bridge to drive transactions.
// =============================================================================

`timescale 1ns / 1ps

module tb_accel;

    logic        clk;
    logic        rst_n;
    logic        irq;

    // CPU Native Interface
    logic        cpu_req;
    logic        cpu_we;
    logic [31:0] cpu_addr;
    logic [31:0] cpu_wdata;
    logic [3:0]  cpu_strb;
    logic [31:0] cpu_rdata;
    logic        cpu_ready;
    logic        cpu_err;

    // AXI4-Lite Bus
    logic [31:0] axi_awaddr,  axi_araddr;
    logic        axi_awvalid, axi_arvalid;
    logic        axi_awready, axi_arready;
    logic [31:0] axi_wdata,   axi_rdata;
    logic [3:0]  axi_wstrb;
    logic        axi_wvalid,  axi_rvalid;
    logic        axi_wready,  axi_rready;
    logic [1:0]  axi_bresp,   axi_rresp;
    logic        axi_bvalid;
    logic        axi_bready;

    // Test Tracking
    int total_tests  = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    // -------------------------------------------------------------------------
    // DUT Instantiations
    // -------------------------------------------------------------------------
    axi_lite_master u_master (
        .clk(clk), .rst_n(rst_n),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_strb(cpu_strb),
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready), .cpu_err(cpu_err),
        .m_axi_awaddr(axi_awaddr), .m_axi_awvalid(axi_awvalid), .m_axi_awready(axi_awready),
        .m_axi_wdata(axi_wdata), .m_axi_wstrb(axi_wstrb),
        .m_axi_wvalid(axi_wvalid), .m_axi_wready(axi_wready),
        .m_axi_bresp(axi_bresp), .m_axi_bvalid(axi_bvalid), .m_axi_bready(axi_bready),
        .m_axi_araddr(axi_araddr), .m_axi_arvalid(axi_arvalid), .m_axi_arready(axi_arready),
        .m_axi_rdata(axi_rdata), .m_axi_rresp(axi_rresp),
        .m_axi_rvalid(axi_rvalid), .m_axi_rready(axi_rready)
    );

    accel_top u_accel (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(axi_awaddr), .s_axi_awvalid(axi_awvalid), .s_axi_awready(axi_awready),
        .s_axi_wdata(axi_wdata), .s_axi_wstrb(axi_wstrb),
        .s_axi_wvalid(axi_wvalid), .s_axi_wready(axi_wready),
        .s_axi_bresp(axi_bresp), .s_axi_bvalid(axi_bvalid), .s_axi_bready(axi_bready),
        .s_axi_araddr(axi_araddr), .s_axi_arvalid(axi_arvalid), .s_axi_arready(axi_arready),
        .s_axi_rdata(axi_rdata), .s_axi_rresp(axi_rresp),
        .s_axi_rvalid(axi_rvalid), .s_axi_rready(axi_rready),
        .irq(irq)
    );

    // Clock Generation: 100 MHz
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------
    task check_val(string name, logic [31:0] actual, logic [31:0] expected);
        total_tests++;
        if (actual === expected) begin
            $display("  [PASS] %-45s | Got: 0x%08h (%0d)", name, actual, actual);
            passed_tests++;
        end else begin
            $display("  [FAIL] %-45s | Got: 0x%08h | Expected: 0x%08h", name, actual, expected);
            failed_tests++;
        end
    endtask

    task cpu_write(logic [31:0] addr, logic [31:0] data, logic [3:0] strb = 4'b1111);
        @(posedge clk);
        cpu_req   <= 1'b1;
        cpu_we    <= 1'b1;
        cpu_addr  <= addr;
        cpu_wdata <= data;
        cpu_strb  <= strb;
        @(posedge clk);
        cpu_req   <= 1'b0;
        while (!cpu_ready) @(posedge clk);
    endtask

    task cpu_read(logic [31:0] addr, output logic [31:0] data);
        @(posedge clk);
        cpu_req   <= 1'b1;
        cpu_we    <= 1'b0;
        cpu_addr  <= addr;
        cpu_strb  <= 4'b0000;
        @(posedge clk);
        cpu_req   <= 1'b0;
        while (!cpu_ready) @(posedge clk);
        data = cpu_rdata;
    endtask

    // -------------------------------------------------------------------------
    // Accelerator Base Address Constants
    // -------------------------------------------------------------------------
    localparam ACCEL_BASE   = 32'h4000_0000;
    localparam REG_CTRL     = ACCEL_BASE + 32'h00;
    localparam REG_STATUS   = ACCEL_BASE + 32'h04;
    localparam REG_DIM      = ACCEL_BASE + 32'h08;
    localparam REG_SRC_A    = ACCEL_BASE + 32'h10;
    localparam REG_SRC_B    = ACCEL_BASE + 32'h14;
    localparam REG_DST      = ACCEL_BASE + 32'h18;
    localparam ACCEL_BUF    = ACCEL_BASE + 32'h100;

    // Q8.8 helper: pack two 16-bit integers into one 32-bit word {b, a}
    function logic [31:0] pack_q88(input int a, input int b);
        logic [15:0] va, vb;
        va = a * 256;
        vb = b * 256;
        return {vb, va};
    endfunction

    logic [31:0] rdata_temp;

    initial begin
        $dumpfile("accel_trace.vcd");
        $dumpvars(0, tb_accel);

        clk      = 0;
        rst_n    = 0;
        cpu_req  = 0;
        cpu_we   = 0;
        cpu_addr = 0;
        cpu_wdata= 0;
        cpu_strb = 0;

        $display("\n=======================================================");
        $display("  Starting Custom Matrix Accelerator Verification");
        $display("=======================================================\n");

        #20;
        rst_n = 1;
        #15;

        // ---------------------------------------------------------------------
        // Test 1: CSR Register Read/Write
        // ---------------------------------------------------------------------
        $display("--- Test 1: CSR Register Read/Write ---");

        // Write DIM = 2 (2x2 matrix)
        cpu_write(REG_DIM, 32'd2);
        cpu_read(REG_DIM, rdata_temp);
        check_val("CSR DIM == 2", rdata_temp, 32'd2);

        // Write source/dest pointers in halfword units
        cpu_write(REG_SRC_A, 32'h0000_0000); // Matrix A starts at halfword 0
        cpu_write(REG_SRC_B, 32'h0000_0004); // Matrix B starts at halfword 4
        cpu_write(REG_DST,   32'h0000_0008); // Matrix C starts at halfword 8

        cpu_read(REG_SRC_A, rdata_temp);
        check_val("CSR SRC_A == 0x0000", rdata_temp, 32'h0000_0000);

        cpu_read(REG_SRC_B, rdata_temp);
        check_val("CSR SRC_B == 0x0004", rdata_temp, 32'h0000_0004);

        cpu_read(REG_DST, rdata_temp);
        check_val("CSR DST == 0x0008", rdata_temp, 32'h0000_0008);

        cpu_read(REG_STATUS, rdata_temp);
        check_val("STATUS == 0 (idle)", rdata_temp, 32'd0);

        // ---------------------------------------------------------------------
        // Test 2: Load 2x2 Matrices into Scratchpad Buffer
        // Matrix A = [[1, 2], [3, 4]]
        // Matrix B = [[5, 6], [7, 8]]
        // Expected Matrix C = [[19, 22], [43, 50]]
        // ---------------------------------------------------------------------
        $display("\n--- Test 2: Load 2x2 Matrices A and B ---");

        cpu_write(ACCEL_BUF + 32'h00, pack_q88(1, 2)); // A row 0: {A[0][1]=2, A[0][0]=1}
        cpu_write(ACCEL_BUF + 32'h04, pack_q88(3, 4)); // A row 1: {A[1][1]=4, A[1][0]=3}
        cpu_write(ACCEL_BUF + 32'h08, pack_q88(5, 6)); // B row 0: {B[0][1]=6, B[0][0]=5}
        cpu_write(ACCEL_BUF + 32'h0C, pack_q88(7, 8)); // B row 1: {B[1][1]=8, B[1][0]=7}

        cpu_read(ACCEL_BUF + 32'h00, rdata_temp);
        check_val("Buffer A row0: {2, 1} Q8.8", rdata_temp, pack_q88(1, 2));

        cpu_read(ACCEL_BUF + 32'h04, rdata_temp);
        check_val("Buffer A row1: {4, 3} Q8.8", rdata_temp, pack_q88(3, 4));

        cpu_read(ACCEL_BUF + 32'h08, rdata_temp);
        check_val("Buffer B row0: {6, 5} Q8.8", rdata_temp, pack_q88(5, 6));

        cpu_read(ACCEL_BUF + 32'h0C, rdata_temp);
        check_val("Buffer B row1: {8, 7} Q8.8", rdata_temp, pack_q88(7, 8));

        // ---------------------------------------------------------------------
        // Test 3: Start Accelerator & Await Interrupt / Done Flag
        // ---------------------------------------------------------------------
        $display("\n--- Test 3: Start Computation & Wait for Done ---");

        cpu_write(REG_CTRL, 32'h0000_0003); // START=1, IRQ_EN=1

        // Poll STATUS until BUSY de-asserts
        rdata_temp = 32'h0000_0001;
        while (rdata_temp[0] == 1'b1) begin
            cpu_read(REG_STATUS, rdata_temp);
        end

        check_val("STATUS DONE == 1", rdata_temp[1], 1'b1);
        check_val("IRQ asserted", {31'd0, irq}, 32'd1);

        // ---------------------------------------------------------------------
        // Test 4: Read Back Result Matrix C
        // Word 4 at offset 0x10: {C[0][1]=22, C[0][0]=19}
        // Word 5 at offset 0x14: {C[1][1]=50, C[1][0]=43}
        // ---------------------------------------------------------------------
        $display("\n--- Test 4: Verify Result Matrix C ---");

        cpu_read(ACCEL_BUF + 32'h10, rdata_temp);
        check_val("C[0][0]=19, C[0][1]=22 (Q8.8)", rdata_temp, pack_q88(19, 22));

        cpu_read(ACCEL_BUF + 32'h14, rdata_temp);
        check_val("C[1][0]=43, C[1][1]=50 (Q8.8)", rdata_temp, pack_q88(43, 50));

        // ---------------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------------
        $display("\n=======================================================");
        $display("  CUSTOM MATRIX ACCELERATOR VERIFICATION SUMMARY");
        $display("  Total Tests  : %0d", total_tests);
        $display("  Passed Tests : %0d", passed_tests);
        $display("  Failed Tests : %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("  RESULT       : ALL TESTS PASSED! 100%% SUCCESS");
            $display("  ACCELERATOR  : MATRIX MATH VERIFIED CORRECT");
        end else begin
            $display("  RESULT       : VERIFICATION FAILED!");
        end
        $display("=======================================================\n");

        #50;
        $finish;
    end

endmodule
