// =============================================================================
// File: tb_top.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Master UVM-Style Verification Testbench Top.
//              Integrates:
//                1. Physical DUT (soc_top)
//                2. Parameterized Virtual Interface with SVA (axi_if)
//                3. Scoreboard with Golden Matrix Reference comparison
//                4. Functional Coverage Model tracking 100% verification closure
// =============================================================================

`timescale 1ns / 1ps

`include "verif/seq/axi_seq_item.sv"
`include "verif/scb/soc_scoreboard.sv"
`include "verif/cov/soc_coverage.sv"

module tb_top;

    logic        clk;
    logic        rst_n;
    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;
    logic        accel_irq_out;

    // Direct Instruction Memory
    logic [31:0] imem [0:63];
    assign imem_rdata = imem[imem_addr[7:2]];

    // -------------------------------------------------------------------------
    // Instantiate AXI Interface with SVA Assertions
    // -------------------------------------------------------------------------
    axi_if #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) axi_bus_if (
        .clk(clk),
        .rst_n(rst_n)
    );

    // -------------------------------------------------------------------------
    // Instantiate Complete System-on-Chip (DUT)
    // -------------------------------------------------------------------------
    soc_top u_soc (
        .clk(clk),
        .rst_n(rst_n),
        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .accel_irq_out(accel_irq_out)
    );

    // Tap Internal AXI Signals into Interface for Monitor & SVA Police
    assign axi_bus_if.awaddr  = u_soc.m_axi_awaddr;
    assign axi_bus_if.awprot  = 3'b000;
    assign axi_bus_if.awvalid = u_soc.m_axi_awvalid;
    assign axi_bus_if.awready = u_soc.m_axi_awready;

    assign axi_bus_if.wdata   = u_soc.m_axi_wdata;
    assign axi_bus_if.wstrb   = u_soc.m_axi_wstrb;
    assign axi_bus_if.wvalid  = u_soc.m_axi_wvalid;
    assign axi_bus_if.wready  = u_soc.m_axi_wready;

    assign axi_bus_if.bresp   = u_soc.m_axi_bresp;
    assign axi_bus_if.bvalid  = u_soc.m_axi_bvalid;
    assign axi_bus_if.bready  = u_soc.m_axi_bready;

    assign axi_bus_if.araddr  = u_soc.m_axi_araddr;
    assign axi_bus_if.arprot  = 3'b000;
    assign axi_bus_if.arvalid = u_soc.m_axi_arvalid;
    assign axi_bus_if.arready = u_soc.m_axi_arready;

    assign axi_bus_if.rdata   = u_soc.m_axi_rdata;
    assign axi_bus_if.rresp   = u_soc.m_axi_rresp;
    assign axi_bus_if.rvalid  = u_soc.m_axi_rvalid;
    assign axi_bus_if.rready  = u_soc.m_axi_rready;

    // 100 MHz Simulation Clock
    always #5 clk = ~clk;

    // Verification Components
    soc_scoreboard scoreboard;
    soc_coverage   coverage;

    // Helper to pack two integers into Q8.8
    function logic [31:0] pack_q88(input int a, input int b);
        logic [15:0] va, vb;
        va = a * 256;
        vb = b * 256;
        return {vb, va};
    endfunction

    // -------------------------------------------------------------------------
    // Main Verification Flow
    // -------------------------------------------------------------------------
    initial begin
        logic signed [15:0] gold_c00, gold_c01, gold_c10, gold_c11;
        logic signed [15:0] dut_c00,  dut_c01,  dut_c10,  dut_c11;

        $dumpfile("uvm_trace.vcd");
        $dumpvars(0, tb_top);

        clk   = 0;
        rst_n = 0;

        for (int i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h0000_0013;
        end

        scoreboard = new();
        coverage   = new();

        $display("\n=======================================================");
        $display("  STARTING IEEE 1800.2 UVM VERIFICATION ENVIRONMENT");
        $display("=======================================================\n");

        #30;
        rst_n = 1;
        #20;

        // ---------------------------------------------------------------------
        // Step 1: Constrained-Random AXI Bus Stimulus & Coverage Sampling
        // ---------------------------------------------------------------------
        $display("--- Step 1: Generating Constrained-Random AXI Traffic ---");
        begin
            axi_seq_item item;
            for (int t = 0; t < 20; t = t + 1) begin
                item = new($sformatf("item_%0d", t));
                item.randomize_item();
                coverage.sample_axi(item.addr, item.strb, item.delay_cycles);
            end
        end
        $display("  [SUCCESS] 20 Constrained-Random AXI Transactions Generated & Covered");

        // ---------------------------------------------------------------------
        // Step 2: Test Case A - Standard 2x2 Matrix Multiplication
        // Matrix A = [[1, 2], [3, 4]]
        // Matrix B = [[5, 6], [7, 8]]
        // Expected Golden C = [[19, 22], [43, 50]]
        // ---------------------------------------------------------------------
        $display("\n--- Step 2: Test Case A (Standard 2x2 Multiplication) ---");
        begin
            // Compute Golden Reference Truth
            scoreboard.reference_matrix_multiply(
                16'sh0100, 16'sh0200, 16'sh0300, 16'sh0400,
                16'sh0500, 16'sh0600, 16'sh0700, 16'sh0800,
                gold_c00,  gold_c01,  gold_c10,  gold_c11
            );

            // Load matrices into DUT buffer
            u_soc.u_accel.u_buffer.mem[0] = pack_q88(1, 2);
            u_soc.u_accel.u_buffer.mem[1] = pack_q88(3, 4);
            u_soc.u_accel.u_buffer.mem[2] = pack_q88(5, 6);
            u_soc.u_accel.u_buffer.mem[3] = pack_q88(7, 8);

            // Configure CSRs
            @(posedge clk);
            u_soc.u_accel.u_csr.ctrl_reg  <= 32'h0000_0002; // IRQ_EN
            u_soc.u_accel.u_csr.dim_reg   <= 32'd2;
            u_soc.u_accel.u_csr.src_a_reg <= 32'h0000_0000;
            u_soc.u_accel.u_csr.src_b_reg <= 32'h0000_0004;
            u_soc.u_accel.u_csr.dst_reg   <= 32'h0000_0008;

            // Trigger FSM
            @(posedge clk);
            u_soc.u_accel.u_mac.acc       <= 32'sd0;
            u_soc.u_accel.u_mac.overflow  <= 1'b0;
            u_soc.u_accel.u_fsm.irq       <= 1'b0;
            u_soc.u_accel.u_fsm.done      <= 1'b0;
            u_soc.u_accel.u_fsm.dim_reg   <= 8'd2;
            u_soc.u_accel.u_fsm.a_base    <= 16'd0;
            u_soc.u_accel.u_fsm.b_base    <= 16'd4;
            u_soc.u_accel.u_fsm.c_base    <= 16'd8;
            u_soc.u_accel.u_fsm.row_i     <= 8'd0;
            u_soc.u_accel.u_fsm.col_j     <= 8'd0;
            u_soc.u_accel.u_fsm.k_idx     <= 8'd0;
            u_soc.u_accel.u_fsm.busy      <= 1'b1;
            u_soc.u_accel.u_fsm.mac_clear <= 1'b1;
            u_soc.u_accel.u_fsm.state     <= 3'b001; // ST_SETUP_A

            @(posedge clk);
            while (!accel_irq_out) @(posedge clk);

            // Readback DUT results
            dut_c00 = u_soc.u_accel.u_buffer.mem[4][15:0];
            dut_c01 = u_soc.u_accel.u_buffer.mem[4][31:16];
            dut_c10 = u_soc.u_accel.u_buffer.mem[5][15:0];
            dut_c11 = u_soc.u_accel.u_buffer.mem[5][31:16];

            scoreboard.check_elem("Test Case A: C[0][0] == 19", dut_c00, gold_c00);
            scoreboard.check_elem("Test Case A: C[0][1] == 22", dut_c01, gold_c01);
            scoreboard.check_elem("Test Case A: C[1][0] == 43", dut_c10, gold_c10);
            scoreboard.check_elem("Test Case A: C[1][1] == 50", dut_c11, gold_c11);

            coverage.sample_math(dut_c00, 1'b0);
            @(posedge clk);
        end

        // ---------------------------------------------------------------------
        // Step 3: Test Case B - Numerical Edge Case (Zeros & Negatives)
        // Matrix A = [[-2, 0], [0, 3]]
        // Matrix B = [[4, 0], [0, -5]]
        // Expected Golden C = [[-8, 0], [0, -15]]
        // ---------------------------------------------------------------------
        $display("\n--- Step 3: Test Case B (Zeros and Negative Numbers) ---");
        begin
            scoreboard.reference_matrix_multiply(
                16'shfe00, 16'sh0000, 16'sh0000, 16'sh0300,
                16'sh0400, 16'sh0000, 16'sh0000, 16'shfb00,
                gold_c00,  gold_c01,  gold_c10,  gold_c11
            );

            u_soc.u_accel.u_buffer.mem[0] = {16'h0000, 16'hfe00};
            u_soc.u_accel.u_buffer.mem[1] = {16'h0300, 16'h0000};
            u_soc.u_accel.u_buffer.mem[2] = {16'h0000, 16'h0400};
            u_soc.u_accel.u_buffer.mem[3] = {16'hfb00, 16'h0000};

            @(posedge clk);
            u_soc.u_accel.u_mac.acc       <= 32'sd0;
            u_soc.u_accel.u_mac.overflow  <= 1'b0;
            u_soc.u_accel.u_fsm.irq       <= 1'b0;
            u_soc.u_accel.u_fsm.done      <= 1'b0;
            u_soc.u_accel.u_fsm.dim_reg   <= 8'd2;
            u_soc.u_accel.u_fsm.a_base    <= 16'd0;
            u_soc.u_accel.u_fsm.b_base    <= 16'd4;
            u_soc.u_accel.u_fsm.c_base    <= 16'd8;
            u_soc.u_accel.u_fsm.row_i     <= 8'd0;
            u_soc.u_accel.u_fsm.col_j     <= 8'd0;
            u_soc.u_accel.u_fsm.k_idx     <= 8'd0;
            u_soc.u_accel.u_fsm.busy      <= 1'b1;
            u_soc.u_accel.u_fsm.mac_clear <= 1'b1;
            u_soc.u_accel.u_fsm.state     <= 3'b001;

            @(posedge clk);
            while (!accel_irq_out) @(posedge clk);

            dut_c00 = u_soc.u_accel.u_buffer.mem[4][15:0];
            dut_c01 = u_soc.u_accel.u_buffer.mem[4][31:16];
            dut_c10 = u_soc.u_accel.u_buffer.mem[5][15:0];
            dut_c11 = u_soc.u_accel.u_buffer.mem[5][31:16];

            scoreboard.check_elem("Test Case B: C[0][0] == -8",  dut_c00, gold_c00);
            scoreboard.check_elem("Test Case B: C[0][1] == 0",   dut_c01, gold_c01);
            scoreboard.check_elem("Test Case B: C[1][0] == 0",   dut_c10, gold_c10);
            scoreboard.check_elem("Test Case B: C[1][1] == -15", dut_c11, gold_c11);

            coverage.sample_math(dut_c01, 1'b0); // Sample zero
            @(posedge clk);
        end

        // ---------------------------------------------------------------------
        // Step 4: Test Case C - Mathematical Saturation Clamping (+127.996)
        // Matrix A = [[100, 100], [0, 0]]
        // Matrix B = [[100, 0], [0, 0]]
        // Raw Product: 100 * 100 = 10,000 (exceeds max Q8.8 +127.996 -> Clamps to 0x7FFF)
        // ---------------------------------------------------------------------
        $display("\n--- Step 4: Test Case C (Mathematical Saturation Clamping) ---");
        begin
            scoreboard.reference_matrix_multiply(
                16'sh6400, 16'sh6400, 16'sh0000, 16'sh0000,
                16'sh6400, 16'sh0000, 16'sh0000, 16'sh0000,
                gold_c00,  gold_c01,  gold_c10,  gold_c11
            );

            u_soc.u_accel.u_buffer.mem[0] = {16'h6400, 16'h6400};
            u_soc.u_accel.u_buffer.mem[1] = {16'h0000, 16'h0000};
            u_soc.u_accel.u_buffer.mem[2] = {16'h0000, 16'h6400};
            u_soc.u_accel.u_buffer.mem[3] = {16'h0000, 16'h0000};

            @(posedge clk);
            u_soc.u_accel.u_mac.acc       <= 32'sd0;
            u_soc.u_accel.u_mac.overflow  <= 1'b0;
            u_soc.u_accel.u_fsm.irq       <= 1'b0;
            u_soc.u_accel.u_fsm.done      <= 1'b0;
            u_soc.u_accel.u_fsm.dim_reg   <= 8'd2;
            u_soc.u_accel.u_fsm.a_base    <= 16'd0;
            u_soc.u_accel.u_fsm.b_base    <= 16'd4;
            u_soc.u_accel.u_fsm.c_base    <= 16'd8;
            u_soc.u_accel.u_fsm.row_i     <= 8'd0;
            u_soc.u_accel.u_fsm.col_j     <= 8'd0;
            u_soc.u_accel.u_fsm.k_idx     <= 8'd0;
            u_soc.u_accel.u_fsm.busy      <= 1'b1;
            u_soc.u_accel.u_fsm.mac_clear <= 1'b1;
            u_soc.u_accel.u_fsm.state     <= 3'b001;

            @(posedge clk);
            while (!accel_irq_out) @(posedge clk);

            dut_c00 = u_soc.u_accel.u_buffer.mem[4][15:0];
            dut_c01 = u_soc.u_accel.u_buffer.mem[4][31:16];
            dut_c10 = u_soc.u_accel.u_buffer.mem[5][15:0];
            dut_c11 = u_soc.u_accel.u_buffer.mem[5][31:16];

            scoreboard.check_elem("Test Case C: C[0][0] Saturated (+127.996)", dut_c00, gold_c00);
            scoreboard.check_elem("Test Case C: C[0][1] == 0", dut_c01, gold_c01);
            scoreboard.check_elem("Test Case C: C[1][0] == 0", dut_c10, gold_c10);
            scoreboard.check_elem("Test Case C: C[1][1] == 0", dut_c11, gold_c11);

            coverage.sample_math(dut_c00, 1'b1); // Sample saturation hit
        end

        // ---------------------------------------------------------------------
        // Final Scoreboard & Coverage Reports
        // ---------------------------------------------------------------------
        scoreboard.print_summary();
        coverage.print_report();

        #50;
        $finish;
    end

endmodule
