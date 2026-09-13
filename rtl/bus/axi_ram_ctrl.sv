// =============================================================================
// File: axi_ram_ctrl.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: AMBA AXI4-Lite Synchronous RAM Controller.
//              Implements a 64 KB (16,384 x 32-bit words) memory block.
//              Supports byte-write strobes (wstrb[3:0]), standard AXI4-Lite
//              handshake contracts, and generates OKAY (2'b00) responses.
// =============================================================================

`timescale 1ns / 1ps

module axi_ram_ctrl #(
    parameter int MEM_DEPTH_WORDS = 16384 // 16K words = 64 KB
)(
    input  logic        clk,
    input  logic        rst_n,

    // -------------------------------------------------------------------------
    // AXI4-Lite Slave Bus Interface
    // -------------------------------------------------------------------------
    // Write Address Channel (AW)
    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    // Write Data Channel (W)
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    // Write Response Channel (B)
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // Read Address Channel (AR)
    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // Read Data Channel (R)
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready
);

    // -------------------------------------------------------------------------
    // Internal Memory Array: 16K words of 32 bits = 64 KB
    // -------------------------------------------------------------------------
    logic [31:0] ram_memory [0:MEM_DEPTH_WORDS-1];

    // Local registers to latch address and control
    logic [13:0] write_word_addr;
    logic        aw_done_reg;
    logic        w_done_reg;

    // -------------------------------------------------------------------------
    // Write Channels (AW, W, B) FSM / Handshake
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        WR_IDLE = 2'b00,
        WR_DATA = 2'b01,
        WR_RESP = 2'b10
    } wr_state_t;

    wr_state_t wr_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state        <= WR_IDLE;
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= 2'b00; // OKAY
            write_word_addr <= 14'd0;
            aw_done_reg     <= 1'b0;
            w_done_reg      <= 1'b0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    s_axi_bvalid  <= 1'b0;
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;

                    // Address accepted
                    if (s_axi_awvalid && s_axi_awready) begin
                        write_word_addr <= s_axi_awaddr[15:2];
                        aw_done_reg     <= 1'b1;
                        s_axi_awready   <= 1'b0;
                    end

                    // Data accepted
                    if (s_axi_wvalid && s_axi_wready) begin
                        w_done_reg   <= 1'b1;
                        s_axi_wready <= 1'b0;
                        // Perform byte-strobed write
                        if (s_axi_wstrb[0]) ram_memory[s_axi_awaddr[15:2]][7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) ram_memory[s_axi_awaddr[15:2]][15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) ram_memory[s_axi_awaddr[15:2]][23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) ram_memory[s_axi_awaddr[15:2]][31:24] <= s_axi_wdata[31:24];
                    end

                    // If both arrived simultaneously in WR_IDLE
                    if ((s_axi_awvalid && s_axi_awready) && (s_axi_wvalid && s_axi_wready)) begin
                        wr_state     <= WR_RESP;
                        s_axi_bvalid <= 1'b1;
                        s_axi_bresp  <= 2'b00; // OKAY
                    end else if ((s_axi_awvalid && s_axi_awready) || (s_axi_wvalid && s_axi_wready)) begin
                        wr_state     <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    // Wait for the remaining channel
                    if (!aw_done_reg) begin
                        s_axi_awready <= 1'b1;
                        if (s_axi_awvalid && s_axi_awready) begin
                            write_word_addr <= s_axi_awaddr[15:2];
                            aw_done_reg     <= 1'b1;
                            s_axi_awready   <= 1'b0;
                        end
                    end

                    if (!w_done_reg) begin
                        s_axi_wready <= 1'b1;
                        if (s_axi_wvalid && s_axi_wready) begin
                            w_done_reg   <= 1'b1;
                            s_axi_wready <= 1'b0;
                            if (s_axi_wstrb[0]) ram_memory[write_word_addr][7:0]   <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1]) ram_memory[write_word_addr][15:8]  <= s_axi_wdata[15:8];
                            if (s_axi_wstrb[2]) ram_memory[write_word_addr][23:16] <= s_axi_wdata[23:16];
                            if (s_axi_wstrb[3]) ram_memory[write_word_addr][31:24] <= s_axi_wdata[31:24];
                        end
                    end

                    // Once both are finished, issue write response
                    if ((aw_done_reg || (s_axi_awvalid && s_axi_awready)) &&
                        (w_done_reg  || (s_axi_wvalid  && s_axi_wready))) begin
                        wr_state     <= WR_RESP;
                        s_axi_bvalid <= 1'b1;
                        s_axi_bresp  <= 2'b00; // OKAY
                    end
                end

                WR_RESP: begin
                    if (s_axi_bready && s_axi_bvalid) begin
                        s_axi_bvalid <= 1'b0;
                        aw_done_reg  <= 1'b0;
                        w_done_reg   <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Read Channels (AR, R) FSM / Handshake
    // -------------------------------------------------------------------------
    typedef enum logic {
        RD_IDLE = 1'b0,
        RD_RESP = 1'b1
    } rd_state_t;

    rd_state_t rd_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state      <= RD_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
            s_axi_rresp   <= 2'b00; // OKAY
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axi_arready <= 1'b1;
                    if (s_axi_arvalid && s_axi_arready) begin
                        s_axi_arready <= 1'b0;
                        // Synchronous RAM read
                        s_axi_rdata   <= ram_memory[s_axi_araddr[15:2]];
                        s_axi_rvalid  <= 1'b1;
                        s_axi_rresp   <= 2'b00; // OKAY
                        rd_state      <= RD_RESP;
                    end
                end

                RD_RESP: begin
                    if (s_axi_rready && s_axi_rvalid) begin
                        s_axi_rvalid  <= 1'b0;
                        s_axi_arready <= 1'b1;
                        rd_state      <= RD_IDLE;
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule
