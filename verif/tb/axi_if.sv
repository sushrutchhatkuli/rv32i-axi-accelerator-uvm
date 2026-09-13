// =============================================================================
// File: axi_if.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Parameterized SystemVerilog Interface for AMBA AXI4-Lite.
//              Contains 5 independent channels (AW, W, B, AR, R) and
//              protocol validation checkers.
// =============================================================================

`timescale 1ns / 1ps

interface axi_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);

    // Write Address Channel (AW)
    logic [ADDR_WIDTH-1:0]      awaddr;
    logic [2:0]                 awprot;
    logic                       awvalid;
    logic                       awready;

    // Write Data Channel (W)
    logic [DATA_WIDTH-1:0]      wdata;
    logic [(DATA_WIDTH/8)-1:0]  wstrb;
    logic                       wvalid;
    logic                       wready;

    // Write Response Channel (B)
    logic [1:0]                 bresp;
    logic                       bvalid;
    logic                       bready;

    // Read Address Channel (AR)
    logic [ADDR_WIDTH-1:0]      araddr;
    logic [2:0]                 arprot;
    logic                       arvalid;
    logic                       arready;

    // Read Data Channel (R)
    logic [DATA_WIDTH-1:0]      rdata;
    logic [1:0]                 rresp;
    logic                       rvalid;
    logic                       rready;

    // Registers to track previous cycle state for protocol checking
    logic awvalid_prev;
    logic awready_prev;
    logic wvalid_prev;
    logic wready_prev;
    logic arvalid_prev;
    logic arready_prev;
    logic [DATA_WIDTH-1:0] wdata_prev;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awvalid_prev <= 1'b0;
            awready_prev <= 1'b0;
            wvalid_prev  <= 1'b0;
            wready_prev  <= 1'b0;
            arvalid_prev <= 1'b0;
            arready_prev <= 1'b0;
            wdata_prev   <= '0;
        end else begin
            // Rule 1: AWVALID must stay high until AWREADY
            if (awvalid_prev && !awready_prev && !awvalid) begin
                $display("[PROTOCOL CHECK ERROR] AWVALID dropped before AWREADY at time %0t!", $time);
            end

            // Rule 2: WVALID must stay high until WREADY
            if (wvalid_prev && !wready_prev && !wvalid) begin
                $display("[PROTOCOL CHECK ERROR] WVALID dropped before WREADY at time %0t!", $time);
            end

            // Rule 3: ARVALID must stay high until ARREADY
            if (arvalid_prev && !arready_prev && !arvalid) begin
                $display("[PROTOCOL CHECK ERROR] ARVALID dropped before ARREADY at time %0t!", $time);
            end

            // Rule 4: WDATA must not change while waiting for WREADY
            if (wvalid_prev && !wready_prev && wvalid && (wdata_prev !== wdata)) begin
                $display("[PROTOCOL CHECK ERROR] WDATA corrupted while waiting for WREADY at time %0t!", $time);
            end

            // Latch history
            awvalid_prev <= awvalid;
            awready_prev <= awready;
            wvalid_prev  <= wvalid;
            wready_prev  <= wready;
            arvalid_prev <= arvalid;
            arready_prev <= arready;
            wdata_prev   <= wdata;
        end
    end

endinterface : axi_if
