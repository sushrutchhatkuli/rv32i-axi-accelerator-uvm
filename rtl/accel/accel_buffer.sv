// =============================================================================
// File: accel_buffer.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: True Dual-Port Synchronous Scratchpad SRAM for Matrix Storage.
//              Port A: 32-bit word read/write with byte strobes for AXI interface.
//              Port B: 16-bit halfword read/write for Accelerator FSM datapath.
//              All memory locations initialize to zero.
// =============================================================================

`timescale 1ns / 1ps

module accel_buffer #(
    parameter int DEPTH_WORDS = 448 // 448 words = 1792 bytes (offsets 0x100 - 0x7FF)
)(
    input  logic        clk,
    input  logic        rst_n,

    // -------------------------------------------------------------------------
    // Port A: 32-Bit AXI Interface
    // -------------------------------------------------------------------------
    input  logic        a_we,
    input  logic [8:0]  a_addr,     // 0 to DEPTH_WORDS-1
    input  logic [31:0] a_wdata,
    input  logic [3:0]  a_wstrb,
    output logic [31:0] a_rdata,

    // -------------------------------------------------------------------------
    // Port B: 16-Bit Datapath Interface (Q8.8 Halfwords)
    // -------------------------------------------------------------------------
    input  logic        b_we,
    input  logic [9:0]  b_addr,     // 0 to (2*DEPTH_WORDS)-1
    input  logic [15:0] b_wdata,
    output logic [15:0] b_rdata
);

    // 32-bit wide internal storage array
    logic [31:0] mem [0:DEPTH_WORDS-1];

    // Initialize all memory to 0 to prevent uninitialized 'x' propagation
    integer init_i;
    initial begin
        for (init_i = 0; init_i < DEPTH_WORDS; init_i = init_i + 1) begin
            mem[init_i] = 32'd0;
        end
    end

    // -------------------------------------------------------------------------
    // Port A: Synchronous Write & Read
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (a_we) begin
            if (a_wstrb[0]) mem[a_addr][7:0]   <= a_wdata[7:0];
            if (a_wstrb[1]) mem[a_addr][15:8]  <= a_wdata[15:8];
            if (a_wstrb[2]) mem[a_addr][23:16] <= a_wdata[23:16];
            if (a_wstrb[3]) mem[a_addr][31:24] <= a_wdata[31:24];
        end
    end

    // Combinational read for Port A allows zero-latency read access
    assign a_rdata = mem[a_addr];

    // -------------------------------------------------------------------------
    // Port B: Synchronous 16-Bit Halfword Write & Combinational Read
    // b_addr[0] == 0: lower halfword [15:0]
    // b_addr[0] == 1: upper halfword [31:16]
    // -------------------------------------------------------------------------
    logic [8:0] b_word_addr;
    logic       b_half_sel;

    assign b_word_addr = b_addr[9:1];
    assign b_half_sel  = b_addr[0];

    always_ff @(posedge clk) begin
        if (b_we) begin
            if (b_half_sel) begin
                mem[b_word_addr][31:16] <= b_wdata;
            end else begin
                mem[b_word_addr][15:0]  <= b_wdata;
            end
        end
    end

    // Combinational read for Port B
    assign b_rdata = b_half_sel ? mem[b_word_addr][31:16] : mem[b_word_addr][15:0];

endmodule
