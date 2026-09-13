// =============================================================================
// File: soc_top.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Top-Level System-on-Chip (SoC) Integration.
//              Connects:
//                1. 5-Stage Pipelined RV32I Processor Core
//                2. AXI4-Lite Master Bridge
//                3. AXI4-Lite 1-to-2 Interconnect Crossbar
//                4. 64 KB Synchronous RAM Controller (Slave 0)
//                5. Custom 4-MAC Q8.8 Matrix Accelerator (Slave 1)
//                6. Accelerator IRQ feedback to CPU
// =============================================================================

`timescale 1ns / 1ps

module soc_top (
    input  logic        clk,
    input  logic        rst_n,

    // Instruction memory bus (direct core fetch for single-cycle latency)
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,

    // External interrupt status
    output logic        accel_irq_out
);

    // -------------------------------------------------------------------------
    // Core Native Memory Interface
    // -------------------------------------------------------------------------
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic [3:0]  dmem_strb;
    logic        dmem_we;
    logic        dmem_re;
    logic [31:0] dmem_rdata;

    // -------------------------------------------------------------------------
    // AXI Master Bridge Interface
    // -------------------------------------------------------------------------
    logic        cpu_req;
    logic        cpu_ready;
    logic        cpu_err;

    assign cpu_req = dmem_we | dmem_re;

    // Master -> Interconnect AXI Channel Wires
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

    // -------------------------------------------------------------------------
    // Interconnect -> Slave 0 (RAM Controller) AXI Channel Wires
    // -------------------------------------------------------------------------
    logic [31:0] s0_axi_awaddr;
    logic        s0_axi_awvalid;
    logic        s0_axi_awready;

    logic [31:0] s0_axi_wdata;
    logic [3:0]  s0_axi_wstrb;
    logic        s0_axi_wvalid;
    logic        s0_axi_wready;

    logic [1:0]  s0_axi_bresp;
    logic        s0_axi_bvalid;
    logic        s0_axi_bready;

    logic [31:0] s0_axi_araddr;
    logic        s0_axi_arvalid;
    logic        s0_axi_arready;

    logic [31:0] s0_axi_rdata;
    logic [1:0]  s0_axi_rresp;
    logic        s0_axi_rvalid;
    logic        s0_axi_rready;

    // -------------------------------------------------------------------------
    // Interconnect -> Slave 1 (Accelerator) AXI Channel Wires
    // -------------------------------------------------------------------------
    logic [31:0] s1_axi_awaddr;
    logic        s1_axi_awvalid;
    logic        s1_axi_awready;

    logic [31:0] s1_axi_wdata;
    logic [3:0]  s1_axi_wstrb;
    logic        s1_axi_wvalid;
    logic        s1_axi_wready;

    logic [1:0]  s1_axi_bresp;
    logic        s1_axi_bvalid;
    logic        s1_axi_bready;

    logic [31:0] s1_axi_araddr;
    logic        s1_axi_arvalid;
    logic        s1_axi_arready;

    logic [31:0] s1_axi_rdata;
    logic [1:0]  s1_axi_rresp;
    logic        s1_axi_rvalid;
    logic        s1_axi_rready;

    // Accelerator Interrupt
    logic accel_irq;
    assign accel_irq_out = accel_irq;

    // =========================================================================
    // 1. RV32I 5-Stage Pipelined Processor Core
    // =========================================================================
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

    // =========================================================================
    // 2. AXI4-Lite Master Bridge
    // =========================================================================
    axi_lite_master u_axi_master (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_req(cpu_req),
        .cpu_we(dmem_we),
        .cpu_addr(dmem_addr),
        .cpu_wdata(dmem_wdata),
        .cpu_strb(dmem_strb),
        .cpu_rdata(dmem_rdata),
        .cpu_ready(cpu_ready),
        .cpu_err(cpu_err),
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

    // =========================================================================
    // 3. AXI4-Lite Interconnect Crossbar
    // =========================================================================
    axi_interconnect u_interconnect (
        .clk(clk),
        .rst_n(rst_n),
        .s_axi_awaddr(m_axi_awaddr),
        .s_axi_awvalid(m_axi_awvalid),
        .s_axi_awready(m_axi_awready),
        .s_axi_wdata(m_axi_wdata),
        .s_axi_wstrb(m_axi_wstrb),
        .s_axi_wvalid(m_axi_wvalid),
        .s_axi_wready(m_axi_wready),
        .s_axi_bresp(m_axi_bresp),
        .s_axi_bvalid(m_axi_bvalid),
        .s_axi_bready(m_axi_bready),
        .s_axi_araddr(m_axi_araddr),
        .s_axi_arvalid(m_axi_arvalid),
        .s_axi_arready(m_axi_arready),
        .s_axi_rdata(m_axi_rdata),
        .s_axi_rresp(m_axi_rresp),
        .s_axi_rvalid(m_axi_rvalid),
        .s_axi_rready(m_axi_rready),
        // Slave 0: RAM
        .m0_axi_awaddr(s0_axi_awaddr),
        .m0_axi_awvalid(s0_axi_awvalid),
        .m0_axi_awready(s0_axi_awready),
        .m0_axi_wdata(s0_axi_wdata),
        .m0_axi_wstrb(s0_axi_wstrb),
        .m0_axi_wvalid(s0_axi_wvalid),
        .m0_axi_wready(s0_axi_wready),
        .m0_axi_bresp(s0_axi_bresp),
        .m0_axi_bvalid(s0_axi_bvalid),
        .m0_axi_bready(s0_axi_bready),
        .m0_axi_araddr(s0_axi_araddr),
        .m0_axi_arvalid(s0_axi_arvalid),
        .m0_axi_arready(s0_axi_arready),
        .m0_axi_rdata(s0_axi_rdata),
        .m0_axi_rresp(s0_axi_rresp),
        .m0_axi_rvalid(s0_axi_rvalid),
        .m0_axi_rready(s0_axi_rready),
        // Slave 1: Accelerator
        .m1_axi_awaddr(s1_axi_awaddr),
        .m1_axi_awvalid(s1_axi_awvalid),
        .m1_axi_awready(s1_axi_awready),
        .m1_axi_wdata(s1_axi_wdata),
        .m1_axi_wstrb(s1_axi_wstrb),
        .m1_axi_wvalid(s1_axi_wvalid),
        .m1_axi_wready(s1_axi_wready),
        .m1_axi_bresp(s1_axi_bresp),
        .m1_axi_bvalid(s1_axi_bvalid),
        .m1_axi_bready(s1_axi_bready),
        .m1_axi_araddr(s1_axi_araddr),
        .m1_axi_arvalid(s1_axi_arvalid),
        .m1_axi_arready(s1_axi_arready),
        .m1_axi_rdata(s1_axi_rdata),
        .m1_axi_rresp(s1_axi_rresp),
        .m1_axi_rvalid(s1_axi_rvalid),
        .m1_axi_rready(s1_axi_rready)
    );

    // =========================================================================
    // 4. AXI Synchronous RAM Controller (64 KB)
    // =========================================================================
    axi_ram_ctrl #(
        .MEM_DEPTH_WORDS(16384)
    ) u_ram_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .s_axi_awaddr(s0_axi_awaddr),
        .s_axi_awvalid(s0_axi_awvalid),
        .s_axi_awready(s0_axi_awready),
        .s_axi_wdata(s0_axi_wdata),
        .s_axi_wstrb(s0_axi_wstrb),
        .s_axi_wvalid(s0_axi_wvalid),
        .s_axi_wready(s0_axi_wready),
        .s_axi_bresp(s0_axi_bresp),
        .s_axi_bvalid(s0_axi_bvalid),
        .s_axi_bready(s0_axi_bready),
        .s_axi_araddr(s0_axi_araddr),
        .s_axi_arvalid(s0_axi_arvalid),
        .s_axi_arready(s0_axi_arready),
        .s_axi_rdata(s0_axi_rdata),
        .s_axi_rresp(s0_axi_rresp),
        .s_axi_rvalid(s0_axi_rvalid),
        .s_axi_rready(s0_axi_rready)
    );

    // =========================================================================
    // 5. Custom 4-MAC Q8.8 Matrix Accelerator
    // =========================================================================
    accel_top u_accel (
        .clk(clk),
        .rst_n(rst_n),
        .s_axi_awaddr(s1_axi_awaddr),
        .s_axi_awvalid(s1_axi_awvalid),
        .s_axi_awready(s1_axi_awready),
        .s_axi_wdata(s1_axi_wdata),
        .s_axi_wstrb(s1_axi_wstrb),
        .s_axi_wvalid(s1_axi_wvalid),
        .s_axi_wready(s1_axi_wready),
        .s_axi_bresp(s1_axi_bresp),
        .s_axi_bvalid(s1_axi_bvalid),
        .s_axi_bready(s1_axi_bready),
        .s_axi_araddr(s1_axi_araddr),
        .s_axi_arvalid(s1_axi_arvalid),
        .s_axi_arready(s1_axi_arready),
        .s_axi_rdata(s1_axi_rdata),
        .s_axi_rresp(s1_axi_rresp),
        .s_axi_rvalid(s1_axi_rvalid),
        .s_axi_rready(s1_axi_rready),
        .irq(accel_irq)
    );

endmodule
