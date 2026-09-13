// =============================================================================
// File: axi_seq_item.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Transaction item representing an AXI4-Lite transfer.
//              Features randomized generation of addresses, data, strobes,
//              and cycle delays.
// =============================================================================

`timescale 1ns / 1ps

class axi_seq_item;

    typedef enum { READ, WRITE } trans_type_e;

    trans_type_e trans_type;
    bit [31:0]   addr;
    bit [31:0]   data;
    bit [3:0]    strb;
    int          delay_cycles;
    bit [1:0]    resp;
    bit [31:0]   rdata;

    function new(string name = "axi_seq_item");
    endfunction

    // Custom randomized generator for toolchain compatibility
    function void randomize_item();
        int r_type;
        int r_addr_sel;
        int r_strb_sel;
        r_type = ($random & 32'h7FFFFFFF) % 2;
        trans_type = (r_type == 0) ? WRITE : READ;

        // Generate 4-byte aligned addresses across RAM, CSRs, Buffer, and DECERR
        r_addr_sel = ($random & 32'h7FFFFFFF) % 4;
        if (r_addr_sel == 0) begin
            addr = 32'h0000_0000 + (($random & 32'h0000_00FF) & ~32'd3); // RAM
        end else if (r_addr_sel == 1) begin
            addr = 32'h4000_0000 + (($random & 32'h0000_001C) & ~32'd3); // CSRs
        end else if (r_addr_sel == 2) begin
            addr = 32'h4000_0100 + (($random & 32'h0000_003C) & ~32'd3); // Buffer
        end else begin
            addr = 32'h8000_0000 + (($random & 32'h0000_003C) & ~32'd3); // DECERR
        end

        data = $random;
        r_strb_sel = ($random & 32'h7FFFFFFF) % 3;
        if (r_strb_sel == 0)      strb = 4'b1111;
        else if (r_strb_sel == 1) strb = 4'b0011;
        else                      strb = 4'b0001;

        delay_cycles = ($random & 32'h7FFFFFFF) % 4;
    endfunction

    function void print(string prefix = "");
        if (trans_type == WRITE) begin
            $display("  %s [AXI_WRITE] Addr: 0x%08h | Data: 0x%08h | Strb: %04b | Delay: %0d",
                     prefix, addr, data, strb, delay_cycles);
        end else begin
            $display("  %s [AXI_READ]  Addr: 0x%08h | Data: 0x%08h | Resp: %02b | Delay: %0d",
                     prefix, addr, rdata, resp, delay_cycles);
        end
    endfunction

endclass
