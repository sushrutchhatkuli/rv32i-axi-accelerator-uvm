// =============================================================================
// File: regfile.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: 32x32-bit General-Purpose Register File (x0-x31).
//              Features dual asynchronous read ports and a single synchronous
//              write port. Register x0 is hardwired to 32'b0.
// =============================================================================

`timescale 1ns / 1ps

module regfile (
    input  logic        clk,
    input  logic        rst_n,
    
    // Asynchronous Read Port 1 (rs1)
    input  logic [4:0]  rs1_addr,
    output logic [31:0] rs1_data,
    
    // Asynchronous Read Port 2 (rs2)
    input  logic [4:0]  rs2_addr,
    output logic [31:0] rs2_data,
    
    // Synchronous Write Port (rd)
    input  logic        we,         // Write enable from WB stage
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data
);

    // 32 registers, each 32 bits wide
    logic [31:0] registers [31:0];

    // Asynchronous Read Logic (x0 is permanently 0)
    assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 : registers[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 : registers[rs2_addr];

    // Synchronous Write Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i++) begin
                registers[i] <= 32'd0;
            end
        end else if (we && (rd_addr != 5'd0)) begin
            // Writes to x0 are silently discarded
            registers[rd_addr] <= rd_data;
        end
    end

endmodule
