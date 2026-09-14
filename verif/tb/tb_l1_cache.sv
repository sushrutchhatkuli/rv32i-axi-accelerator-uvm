// =============================================================================
// File: tb_l1_cache.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Comprehensive Self-Checking Testbench for L1 Hardware Cache.
//              Verifies:
//                1. Cold miss and 4-word AXI burst line refill.
//                2. Temporal locality single-cycle hit (0 wait states).
//                3. Spatial locality adjacent word hits (Words 1, 2, 3).
//                4. Write-Through coherence and synchronous RAM update.
//                5. Conflict miss line eviction and tag replacement.
//                6. Non-Cacheable MMIO bypass for accelerator registers.
// =============================================================================

`timescale 1ns / 1ps

module tb_l1_cache;

    logic        clk;
    logic        rst_n;

    // CPU Side Interface
    logic        cpu_req;
    logic        cpu_we;
    logic [31:0] cpu_addr;
    logic [31:0] cpu_wdata;
    logic [3:0]  cpu_strb;
    logic [31:0] cpu_rdata;
    logic        cpu_ready;
    logic        cache_hit;
    logic [31:0] perf_hits;
    logic [31:0] perf_misses;

    // AXI Master Interface
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

    // Verification Scoreboard Counters
    int total_tests  = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    // -------------------------------------------------------------------------
    // Device Under Test (DUT)
    // -------------------------------------------------------------------------
    l1_cache_controller #(
        .NUM_LINES(64),
        .WORDS_PER_LINE(4),
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_req(cpu_req),
        .cpu_we(cpu_we),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_strb(cpu_strb),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),
        .cache_hit(cache_hit),
        .perf_hits(perf_hits),
        .perf_misses(perf_misses),
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
        .m_axi_rready(m_axi_rready)
    );

    // -------------------------------------------------------------------------
    // Clock Generation (50 MHz, 20 ns period)
    // -------------------------------------------------------------------------
    always #10 clk = ~clk;

    // -------------------------------------------------------------------------
    // Simulated Main Memory & Accelerator MMIO Slave
    // -------------------------------------------------------------------------
    logic [31:0] simulated_ram [0:4095];
    logic [31:0] mmio_csr_ctrl;
    logic [31:0] mmio_csr_status;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awready   <= 1'b0;
            m_axi_wready    <= 1'b0;
            m_axi_bvalid    <= 1'b0;
            m_axi_bresp     <= 2'b00;
            m_axi_arready   <= 1'b0;
            m_axi_rvalid    <= 1'b0;
            m_axi_rdata     <= 32'd0;
            m_axi_rresp     <= 2'b00;
            mmio_csr_ctrl   <= 32'd0;
            mmio_csr_status <= 32'h0000_0001; // Done flag = 1
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
                if (m_axi_araddr >= 32'h4000_0000) begin
                    // MMIO Read
                    if (m_axi_araddr == 32'h4000_0004)
                        m_axi_rdata <= mmio_csr_status;
                    else
                        m_axi_rdata <= mmio_csr_ctrl;
                end else begin
                    // RAM Read
                    m_axi_rdata <= simulated_ram[m_axi_araddr[13:2]];
                end
            end else if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
            end

            // Write Channels
            if (m_axi_awvalid && !m_axi_awready) m_axi_awready <= 1'b1;
            else m_axi_awready <= 1'b0;

            if (m_axi_wvalid && !m_axi_wready) begin
                m_axi_wready <= 1'b1;
                if (m_axi_awaddr >= 32'h4000_0000) begin
                    if (m_axi_awaddr == 32'h4000_0000) mmio_csr_ctrl <= m_axi_wdata;
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

    // CPU Read Helper Task
    task automatic cpu_read_word(
        input  logic [31:0] addr,
        output logic [31:0] data_out,
        output logic        was_hit,
        output int          cycles_taken
    );
        cycles_taken = 0;
        @(posedge clk);
        #1;
        cpu_req  = 1'b1;
        cpu_we   = 1'b0;
        cpu_addr = addr;
        cpu_strb = 4'b0000;

        // Check if hit immediately in cycle 0
        #1;
        was_hit = cache_hit;

        while (!cpu_ready) begin
            @(posedge clk);
            cycles_taken++;
            #1;
        end

        data_out = cpu_rdata;
        @(posedge clk);
        #1;
        cpu_req  = 1'b0;
    endtask

    // CPU Write Helper Task
    task automatic cpu_write_word(
        input logic [31:0] addr,
        input logic [31:0] data_in,
        input logic [3:0]  strb
    );
        @(posedge clk);
        #1;
        cpu_req   = 1'b1;
        cpu_we    = 1'b1;
        cpu_addr  = addr;
        cpu_wdata = data_in;
        cpu_strb  = strb;

        #1;
        while (!cpu_ready) begin
            @(posedge clk);
            #1;
        end

        @(posedge clk);
        #1;
        cpu_req = 1'b0;
        cpu_we  = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Test Scenario Execution
    // -------------------------------------------------------------------------
    logic [31:0] rdata;
    logic        hit;
    int          latency;

    initial begin
        $dumpfile("l1_cache_trace.vcd");
        $dumpvars(0, tb_l1_cache);

        clk     = 0;
        rst_n   = 0;
        cpu_req = 0;
        cpu_we  = 0;
        cpu_addr  = 0;
        cpu_wdata = 0;
        cpu_strb  = 0;

        // Initialize RAM contents with recognizable pattern
        for (int i = 0; i < 4096; i++) begin
            simulated_ram[i] = 32'h1000_0000 + (i * 4);
        end
        // Specifically set Line 0x0100 (4 words)
        simulated_ram[32'h0100 >> 2] = 32'hAAAA_0001; // Word 0
        simulated_ram[32'h0104 >> 2] = 32'hBBBB_0002; // Word 1
        simulated_ram[32'h0108 >> 2] = 32'hCCCC_0003; // Word 2
        simulated_ram[32'h010C >> 2] = 32'hDDDD_0004; // Word 3

        // Line 0x0500 (Same cache index as 0x0100, different tag)
        simulated_ram[32'h0500 >> 2] = 32'h1111_AAAA;
        simulated_ram[32'h0504 >> 2] = 32'h2222_BBBB;

        #30;
        rst_n = 1;
        #20;

        $display("\n=======================================================");
        $display("  Starting L1 Hardware Cache Controller Lab");
        $display("=======================================================");

        // ---------------------------------------------------------------------
        // Step 1: Cold Miss & Line Refill
        // ---------------------------------------------------------------------
        $display("\n--- Step 1: Cold Read Miss & 4-Word AXI Line Refill ---");
        cpu_read_word(32'h0000_0100, rdata, hit, latency);
        check("Cold Miss correctly detected (hit == 0)", hit == 0);
        check("Data received matches RAM Word 0 (0xAAAA0001)", rdata == 32'hAAAA_0001);
        check("Telemetry: Miss counter incremented to 1", perf_misses == 1);
        check("Telemetry: Hit counter remains 0", perf_hits == 0);

        // ---------------------------------------------------------------------
        // Step 2: Temporal Locality (Single-Cycle Hit)
        // ---------------------------------------------------------------------
        $display("\n--- Step 2: Temporal Locality (Single-Cycle Cache Hit) ---");
        cpu_read_word(32'h0000_0100, rdata, hit, latency);
        check("Immediate Cache Hit detected (hit == 1)", hit == 1);
        check("Zero wait-states latency (latency == 0)", latency == 0);
        check("Data verified from cached SRAM (0xAAAA0001)", rdata == 32'hAAAA_0001);
        check("Telemetry: Hit counter incremented to 1", perf_hits == 1);

        // ---------------------------------------------------------------------
        // Step 3: Spatial Locality (Adjacent Words in Refilled Line)
        // ---------------------------------------------------------------------
        $display("\n--- Step 3: Spatial Locality (Adjacent Word Hits) ---");
        cpu_read_word(32'h0000_0104, rdata, hit, latency);
        check("Word 1 Hit in refilled line (0xBBBB0002)", hit == 1 && rdata == 32'hBBBB_0002);

        cpu_read_word(32'h0000_0108, rdata, hit, latency);
        check("Word 2 Hit in refilled line (0xCCCC0003)", hit == 1 && rdata == 32'hCCCC_0003);

        cpu_read_word(32'h0000_010C, rdata, hit, latency);
        check("Word 3 Hit in refilled line (0xDDDD0004)", hit == 1 && rdata == 32'hDDDD_0004);
        check("Telemetry: 4 total cache hits recorded", perf_hits == 4);

        // ---------------------------------------------------------------------
        // Step 4: Write-Through Coherence
        // ---------------------------------------------------------------------
        $display("\n--- Step 4: Write-Through & Memory Coherence ---");
        cpu_write_word(32'h0000_0104, 32'h9999_7777, 4'b1111);
        check("Main RAM updated by Write-Through", simulated_ram[32'h0104 >> 2] == 32'h9999_7777);

        cpu_read_word(32'h0000_0104, rdata, hit, latency);
        check("Cache line updated: Hit returns new value", hit == 1 && rdata == 32'h9999_7777);

        // Partial Byte Strobe Write
        cpu_write_word(32'h0000_0104, 32'h0000_00AA, 4'b0001);
        cpu_read_word(32'h0000_0104, rdata, hit, latency);
        check("Byte strobe applied (lower byte updated to 0xAA)", rdata == 32'h9999_77AA);

        // ---------------------------------------------------------------------
        // Step 5: Conflict Miss & Tag Replacement
        // ---------------------------------------------------------------------
        $display("\n--- Step 5: Conflict Miss & Line Eviction ---");
        // Address 0x0500 maps to index 16 (same as 0x0100), but has tag = 1 instead of 0
        cpu_read_word(32'h0000_0500, rdata, hit, latency);
        check("Conflict miss detected on different Tag", hit == 0);
        check("New line refilled from RAM (0x1111AAAA)", rdata == 32'h1111_AAAA);
        check("Telemetry: Miss counter incremented to 2", perf_misses == 2);

        // Subsequent read of 0x0500 should now hit
        cpu_read_word(32'h0000_0500, rdata, hit, latency);
        check("New line now hits on subsequent access", hit == 1 && rdata == 32'h1111_AAAA);

        // Word 1 of new line should also hit
        cpu_read_word(32'h0000_0504, rdata, hit, latency);
        check("Adjacent word in new line hits (0x2222BBBB)", hit == 1 && rdata == 32'h2222_BBBB);

        // Old address 0x0100 was evicted; reading it must miss again
        cpu_read_word(32'h0000_0100, rdata, hit, latency);
        check("Evicted line correctly detects miss on re-access", hit == 0 && rdata == 32'hAAAA_0001);

        // ---------------------------------------------------------------------
        // Step 6: Non-Cacheable MMIO Peripheral Bypass
        // ---------------------------------------------------------------------
        $display("\n--- Step 6: Non-Cacheable MMIO Peripheral Bypass ---");
        // Write to Accelerator START CSR (0x4000_0000)
        cpu_write_word(32'h4000_0000, 32'h0000_0001, 4'b1111);
        check("MMIO Write bypassed cache to peripheral CSR", mmio_csr_ctrl == 32'h0000_0001);

        // Read Accelerator STATUS CSR (0x4000_0004)
        cpu_read_word(32'h4000_0004, rdata, hit, latency);
        check("MMIO Read bypassed cache directly (Done=1)", rdata == 32'h0000_0001);
        check("MMIO Read not counted as cache hit", hit == 0);
        check("Telemetry: Cache hit counter untouched by MMIO", perf_hits == 8);

        // ---------------------------------------------------------------------
        // Summary Scorecard
        // ---------------------------------------------------------------------
        $display("\n=======================================================");
        $display("  L1 HARDWARE CACHE CONTROLLER SUMMARY");
        $display("  Total Tests  : %0d", total_tests);
        $display("  Passed Tests : %0d", passed_tests);
        $display("  Failed Tests : %0d", failed_tests);
        $display("  Performance  : %0d Cache Hits, %0d Cache Misses", perf_hits, perf_misses);
        if (failed_tests == 0) begin
            $display("  RESULT       : ALL TESTS PASSED! 100%% SUCCESS");
            $display("  SYSTEM STATE : L1 CACHE CONTROLLER FULLY VERIFIED");
        end else begin
            $display("  RESULT       : FAILURES DETECTED IN L1 CACHE EXECUTION");
        end
        $display("=======================================================\n");

        $finish;
    end

endmodule
