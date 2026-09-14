// =============================================================================
// File: tb_dma_controller.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Comprehensive Self-Checking Testbench for Hardware DMA Engine.
//              Verifies:
//                1. Memory-mapped CSR programming & readback.
//                2. RAM-to-RAM 16-byte block transfer.
//                3. 64-byte streaming through the internal 16-word FIFO.
//                4. RAM-to-Accelerator scratchpad buffer streaming.
//                5. Hardware interrupt generation (dma_irq_out).
//                6. Back-to-back sequential DMA transfers.
// =============================================================================

`timescale 1ns / 1ps

module tb_dma_controller;

    logic        clk;
    logic        rst_n;

    // AXI Slave Port (CPU -> DMA CSRs)
    logic [31:0] s_axi_awaddr;
    logic        s_axi_awvalid;
    logic        s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic [3:0]  s_axi_wstrb;
    logic        s_axi_wvalid;
    logic        s_axi_wready;
    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;
    logic [31:0] s_axi_araddr;
    logic        s_axi_arvalid;
    logic        s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [1:0]  s_axi_rresp;
    logic        s_axi_rvalid;
    logic        s_axi_rready;

    // AXI Master Port (DMA -> Memory / Interconnect)
    logic [31:0] m_axi_awaddr;
    logic        m_axi_awvalid;
    logic        m_axi_awready;
    logic [31:0] m_axi_wdata;
    logic [3:0]  m_axi_wstrb;
    logic        m_axi_wvalid;
    logic        m_axi_wready;
    logic [1:0]  m_axi_bresp;
    logic        m_axi_bvalid;
    logic        m_axi_bready;
    logic [31:0] m_axi_araddr;
    logic        m_axi_arvalid;
    logic        m_axi_arready;
    logic [31:0] m_axi_rdata;
    logic [1:0]  m_axi_rresp;
    logic        m_axi_rvalid;
    logic        m_axi_rready;

    // Interrupt
    logic        dma_irq_out;

    // Verification Scoreboard Counters
    int total_tests  = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    // -------------------------------------------------------------------------
    // Device Under Test (DUT)
    // -------------------------------------------------------------------------
    dma_controller #(
        .FIFO_DEPTH(16),
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .dma_irq_out(dma_irq_out)
    );

    // -------------------------------------------------------------------------
    // Clock Generation (50 MHz)
    // -------------------------------------------------------------------------
    always #10 clk = ~clk;

    // -------------------------------------------------------------------------
    // Simulated Main Memory & Accelerator Slave Arrays
    // -------------------------------------------------------------------------
    logic [31:0] simulated_ram   [0:4095];
    logic [31:0] simulated_accel [0:15]; // Accelerator Buffer (0x4000_0000)

    // Master bus target responder
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awready <= 1'b0;
            m_axi_wready  <= 1'b0;
            m_axi_bvalid  <= 1'b0;
            m_axi_bresp   <= 2'b00;
            m_axi_arready <= 1'b0;
            m_axi_rvalid  <= 1'b0;
            m_axi_rdata   <= 32'd0;
            m_axi_rresp   <= 2'b00;
        end else begin
            // Read Address Channel
            if (m_axi_arvalid && !m_axi_arready) begin
                m_axi_arready <= 1'b1;
            end else begin
                m_axi_arready <= 1'b0;
            end

            // Read Data Channel
            if (m_axi_arvalid && m_axi_arready) begin
                m_axi_rvalid <= 1'b1;
                m_axi_rdata  <= simulated_ram[m_axi_araddr[13:2]];
            end else if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
            end

            // Write Channels
            if (m_axi_awvalid && !m_axi_awready) m_axi_awready <= 1'b1;
            else m_axi_awready <= 1'b0;

            if (m_axi_wvalid && !m_axi_wready) begin
                m_axi_wready <= 1'b1;
                if (m_axi_awaddr >= 32'h4000_0000) begin
                    simulated_accel[m_axi_awaddr[5:2]] <= m_axi_wdata;
                end else begin
                    simulated_ram[m_axi_awaddr[13:2]] <= m_axi_wdata;
                end
            end else begin
                m_axi_wready <= 1'b0;
            end

            if (m_axi_wvalid && m_axi_wready) begin
                m_axi_bvalid <= 1'b1;
            end else if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Verification Check Tasks
    // -------------------------------------------------------------------------
    task automatic check(
        input string desc,
        input logic  condition
    );
        total_tests++;
        if (condition) begin
            $display("  [PASS] %-50s", desc);
            passed_tests++;
        end else begin
            $display("  [FAIL] %-50s", desc);
            failed_tests++;
        end
    endtask

    // CPU CSR Write Task
    task automatic cpu_write_csr(
        input logic [4:0]  reg_offset,
        input logic [31:0] data_in
    );
        @(posedge clk);
        #1;
        s_axi_awaddr  = {27'd0, reg_offset};
        s_axi_awvalid = 1'b1;
        s_axi_wdata   = data_in;
        s_axi_wstrb   = 4'b1111;
        s_axi_wvalid  = 1'b1;
        s_axi_bready  = 1'b0;

        while (!(s_axi_awready && s_axi_wready)) begin
            @(posedge clk);
            #1;
        end

        @(posedge clk);
        #1;
        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b1;

        while (!s_axi_bvalid) begin
            @(posedge clk);
            #1;
        end

        @(posedge clk);
        #1;
        s_axi_bready = 1'b0;
    endtask

    // CPU CSR Read Task
    task automatic cpu_read_csr(
        input  logic [4:0]  reg_offset,
        output logic [31:0] data_out
    );
        @(posedge clk);
        #1;
        s_axi_araddr  = {27'd0, reg_offset};
        s_axi_arvalid = 1'b1;
        s_axi_rready  = 1'b0;

        while (!s_axi_arready) begin
            @(posedge clk);
            #1;
        end

        @(posedge clk);
        #1;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b1;

        while (!s_axi_rvalid) begin
            @(posedge clk);
            #1;
        end

        data_out = s_axi_rdata;
        @(posedge clk);
        #1;
        s_axi_rready = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Test Scenario Execution
    // -------------------------------------------------------------------------
    logic [31:0] rdata;
    int          cycles_waited;

    initial begin
        $dumpfile("dma_controller_trace.vcd");
        $dumpvars(0, tb_dma_controller);

        clk   = 0;
        rst_n = 0;
        s_axi_awaddr  = 0;
        s_axi_awvalid = 0;
        s_axi_wdata   = 0;
        s_axi_wstrb   = 0;
        s_axi_wvalid  = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0;
        s_axi_arvalid = 0;
        s_axi_rready  = 0;

        // Initialize RAM
        for (int i = 0; i < 4096; i++) begin
            simulated_ram[i] = 32'hA000_0000 + i;
        end
        for (int i = 0; i < 16; i++) begin
            simulated_accel[i] = 32'd0;
        end

        #30;
        rst_n = 1;
        #20;

        $display("\n=======================================================");
        $display("  Starting Hardware DMA Controller Verification Lab");
        $display("=======================================================");

        // ---------------------------------------------------------------------
        // Step 1: CSR Configuration & Readback
        // ---------------------------------------------------------------------
        $display("\n--- Step 1: Testing Memory-Mapped CSR Register R/W ---");
        cpu_write_csr(5'h00, 32'h0000_1000); // SRC_ADDR
        cpu_read_csr(5'h00, rdata);
        check("Write & Readback SRC_ADDR (0x0000_1000)", rdata == 32'h0000_1000);

        cpu_write_csr(5'h04, 32'h0000_2000); // DST_ADDR
        cpu_read_csr(5'h04, rdata);
        check("Write & Readback DST_ADDR (0x0000_2000)", rdata == 32'h0000_2000);

        cpu_write_csr(5'h08, 32'd16); // LENGTH (16 bytes = 4 words)
        cpu_read_csr(5'h08, rdata);
        check("Write & Readback LENGTH (16 bytes)", rdata == 32'd16);

        cpu_write_csr(5'h0C, 32'h0000_0002); // CTRL (IRQ_EN=1, START=0)
        cpu_read_csr(5'h0C, rdata);
        check("Write & Readback CTRL (IRQ_EN=1)", rdata[1] == 1'b1);

        cpu_read_csr(5'h10, rdata); // STATUS
        check("Initial STATUS register (Busy=0, Done=0)", rdata[1:0] == 2'b00);

        // ---------------------------------------------------------------------
        // Step 2: RAM-to-RAM Block Copy (16 bytes / 4 words)
        // ---------------------------------------------------------------------
        $display("\n--- Step 2: Testing RAM-to-RAM Block Transfer (16 Bytes) ---");
        simulated_ram[32'h0100 >> 2] = 32'h1111_2222;
        simulated_ram[32'h0104 >> 2] = 32'h3333_4444;
        simulated_ram[32'h0108 >> 2] = 32'h5555_6666;
        simulated_ram[32'h010C >> 2] = 32'h7777_8888;

        // Clear destination
        simulated_ram[32'h0200 >> 2] = 32'd0;
        simulated_ram[32'h0204 >> 2] = 32'd0;
        simulated_ram[32'h0208 >> 2] = 32'd0;
        simulated_ram[32'h020C >> 2] = 32'd0;

        cpu_write_csr(5'h00, 32'h0000_0100); // SRC = 0x0100
        cpu_write_csr(5'h04, 32'h0000_0200); // DST = 0x0200
        cpu_write_csr(5'h08, 32'd16);         // LEN = 16
        cpu_write_csr(5'h0C, 32'h0000_0003); // START=1, IRQ_EN=1

        // Poll STATUS done
        cycles_waited = 0;
        rdata = 0;
        while (!rdata[1] && cycles_waited < 100) begin
            cpu_read_csr(5'h10, rdata);
            cycles_waited++;
        end

        check("DMA Transfer completed (STATUS[DONE] == 1)", rdata[1] == 1'b1);
        check("Hardware Interrupt asserted (dma_irq_out == 1)", dma_irq_out == 1'b1);
        check("Transferred Word 0 bit-exact (0x11112222)", simulated_ram[32'h0200 >> 2] == 32'h1111_2222);
        check("Transferred Word 1 bit-exact (0x33334444)", simulated_ram[32'h0204 >> 2] == 32'h3333_4444);
        check("Transferred Word 2 bit-exact (0x55556666)", simulated_ram[32'h0208 >> 2] == 32'h5555_6666);
        check("Transferred Word 3 bit-exact (0x77778888)", simulated_ram[32'h020C >> 2] == 32'h7777_8888);

        // ---------------------------------------------------------------------
        // Step 3: Full 16-Word (64-Byte) Streaming via Internal FIFO
        // ---------------------------------------------------------------------
        $display("\n--- Step 3: Testing 64-Byte Stream via 16-Word FIFO ---");
        for (int i = 0; i < 16; i++) begin
            simulated_ram[(32'h0400 >> 2) + i] = 32'hCAFE_0000 + i;
            simulated_ram[(32'h0600 >> 2) + i] = 32'd0;
        end

        cpu_write_csr(5'h00, 32'h0000_0400); // SRC = 0x0400
        cpu_write_csr(5'h04, 32'h0000_0600); // DST = 0x0600
        cpu_write_csr(5'h08, 32'd64);         // LEN = 64 bytes (16 words)
        cpu_write_csr(5'h0C, 32'h0000_0003); // START=1, IRQ_EN=1

        rdata = 0;
        cycles_waited = 0;
        while (!rdata[1] && cycles_waited < 200) begin
            cpu_read_csr(5'h10, rdata);
            cycles_waited++;
        end

        check("64-Byte Streaming completed (STATUS[DONE] == 1)", rdata[1] == 1'b1);

        // Verify all 16 words match
        begin
            logic all_match;
            all_match = 1;
            for (int i = 0; i < 16; i++) begin
                if (simulated_ram[(32'h0600 >> 2) + i] != (32'hCAFE_0000 + i))
                    all_match = 0;
            end
            check("All 16 streamed words verified bit-exact", all_match == 1);
        end

        // ---------------------------------------------------------------------
        // Step 4: RAM-to-Accelerator Matrix Buffer Streaming
        // ---------------------------------------------------------------------
        $display("\n--- Step 4: Streaming Matrix Tile to Coprocessor Buffer ---");
        // Matrix 2x2 tile: A00, A01, A10, A11
        simulated_ram[32'h0800 >> 2] = 32'h0200_0100; // Row 0
        simulated_ram[32'h0804 >> 2] = 32'h0400_0300; // Row 1
        simulated_ram[32'h0808 >> 2] = 32'h0600_0500; // Matrix B Row 0
        simulated_ram[32'h080C >> 2] = 32'h0800_0700; // Matrix B Row 1

        cpu_write_csr(5'h00, 32'h0000_0800); // SRC = 0x0800
        cpu_write_csr(5'h04, 32'h4000_0000); // DST = Accelerator Buffer (0x4000_0000)
        cpu_write_csr(5'h08, 32'd16);         // LEN = 16 bytes (4 matrix words)
        cpu_write_csr(5'h0C, 32'h0000_0003); // START=1, IRQ_EN=1

        rdata = 0;
        cycles_waited = 0;
        while (!rdata[1] && cycles_waited < 100) begin
            cpu_read_csr(5'h10, rdata);
            cycles_waited++;
        end

        check("Matrix Buffer stream completed", rdata[1] == 1'b1);
        check("Accelerator Buffer[0] matches Matrix A Row 0", simulated_accel[0] == 32'h0200_0100);
        check("Accelerator Buffer[1] matches Matrix A Row 1", simulated_accel[1] == 32'h0400_0300);
        check("Accelerator Buffer[2] matches Matrix B Row 0", simulated_accel[2] == 32'h0600_0500);
        check("Accelerator Buffer[3] matches Matrix B Row 1", simulated_accel[3] == 32'h0800_0700);

        // ---------------------------------------------------------------------
        // Step 5: Back-to-Back Sequential Transfer Resilience
        // ---------------------------------------------------------------------
        $display("\n--- Step 5: Testing Back-to-Back Chained Transfers ---");
        // Transfer 1
        cpu_write_csr(5'h00, 32'h0000_0100);
        cpu_write_csr(5'h04, 32'h0000_0300);
        cpu_write_csr(5'h08, 32'd8);          // 2 words
        cpu_write_csr(5'h0C, 32'h0000_0001); // START=1

        rdata = 0;
        while (!rdata[1]) cpu_read_csr(5'h10, rdata);
        check("Transfer 1 completed cleanly", rdata[1] == 1'b1);

        // Transfer 2 immediately
        cpu_write_csr(5'h00, 32'h0000_0108);
        cpu_write_csr(5'h04, 32'h0000_0308);
        cpu_write_csr(5'h08, 32'd8);          // 2 words
        cpu_write_csr(5'h0C, 32'h0000_0001); // START=1

        rdata = 0;
        while (!rdata[1]) cpu_read_csr(5'h10, rdata);
        check("Transfer 2 completed with zero deadlocks", rdata[1] == 1'b1);

        // ---------------------------------------------------------------------
        // Summary Scorecard
        // ---------------------------------------------------------------------
        $display("\n=======================================================");
        $display("  HARDWARE DMA CONTROLLER VERIFICATION SUMMARY");
        $display("  Total Tests  : %0d", total_tests);
        $display("  Passed Tests : %0d", passed_tests);
        $display("  Failed Tests : %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("  RESULT       : ALL TESTS PASSED! 100%% SUCCESS");
            $display("  SYSTEM STATE : HARDWARE DMA CONTROLLER FULLY VERIFIED");
        end else begin
            $display("  RESULT       : FAILURES DETECTED IN DMA EXECUTION");
        end
        $display("=======================================================\n");

        $finish;
    end

endmodule
