// =============================================================================
// File: axi_lite_master.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: AMBA AXI4-Lite Master Bridge. Translates single-cycle CPU
//              memory requests (cpu_req, cpu_we, cpu_addr, cpu_wdata) into
//              standard 5-channel AXI4-Lite transactions (AW, W, B, AR, R)
//              with strict VALID/READY handshake compliance.
// =============================================================================

`timescale 1ns / 1ps

module axi_lite_master (
    input  logic        clk,
    input  logic        rst_n,

    // -------------------------------------------------------------------------
    // CPU Native Core Memory Interface
    // -------------------------------------------------------------------------
    input  logic        cpu_req,        // 1 = CPU initiates memory transaction
    input  logic        cpu_we,         // 1 = Write (SW), 0 = Read (LW)
    input  logic [31:0] cpu_addr,       // Target byte address
    input  logic [31:0] cpu_wdata,      // Data to write
    input  logic [3:0]  cpu_strb,       // Byte lane write enable mask
    output logic [31:0] cpu_rdata,      // Data returned from read
    output logic        cpu_ready,      // 1 = Transaction completed
    output logic        cpu_err,        // 1 = Slave returned SLVERR or DECERR

    // -------------------------------------------------------------------------
    // AXI4-Lite Master Bus Interface (5 Independent Channels)
    // -------------------------------------------------------------------------
    // Write Address Channel (AW)
    output logic [31:0] m_axi_awaddr,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,

    // Write Data Channel (W)
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,

    // Write Response Channel (B)
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,

    // Read Address Channel (AR)
    output logic [31:0] m_axi_araddr,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,

    // Read Data Channel (R)
    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);

    // -------------------------------------------------------------------------
    // State Definitions
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        ST_IDLE       = 3'b000,
        ST_WRITE_TX   = 3'b001,
        ST_WRITE_RESP = 3'b010,
        ST_READ_ADDR  = 3'b011,
        ST_READ_DATA  = 3'b100
    } state_t;

    state_t state, next_state;

    // Registers to latch request inputs and decouple CPU changes
    logic [31:0] reg_addr;
    logic [31:0] reg_wdata;
    logic [3:0]  reg_strb;
    logic [31:0] reg_rdata;
    logic        reg_err;

    // Handshake tracking flags for write channels (AW and W can finish independently)
    logic aw_done;
    logic w_done;

    // -------------------------------------------------------------------------
    // Sequential State & Register Updates
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            reg_addr  <= 32'd0;
            reg_wdata <= 32'd0;
            reg_strb  <= 4'd0;
            reg_rdata <= 32'd0;
            reg_err   <= 1'b0;
            aw_done   <= 1'b0;
            w_done    <= 1'b0;
        end else begin
            state <= next_state;

            case (state)
                ST_IDLE: begin
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;
                    if (cpu_req) begin
                        reg_addr  <= cpu_addr;
                        reg_wdata <= cpu_wdata;
                        reg_strb  <= (cpu_strb != 4'd0) ? cpu_strb : 4'b1111;
                        reg_err   <= 1'b0;
                    end
                end

                ST_WRITE_TX: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        aw_done <= 1'b1;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        w_done <= 1'b1;
                    end
                end

                ST_WRITE_RESP: begin
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;
                    if (m_axi_bvalid && m_axi_bready) begin
                        reg_err <= (m_axi_bresp != 2'b00); // 2'b00 is OKAY
                    end
                end

                ST_READ_ADDR: begin
                    // Address transmitted
                end

                ST_READ_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        reg_rdata <= m_axi_rdata;
                        reg_err   <= (m_axi_rresp != 2'b00);
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Next State & Combinational Output Logic
    // -------------------------------------------------------------------------
    always_comb begin
        next_state    = state;

        // Default AXI outputs
        m_axi_awaddr  = reg_addr;
        m_axi_awvalid = 1'b0;
        m_axi_wdata   = reg_wdata;
        m_axi_wstrb   = reg_strb;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b0;

        m_axi_araddr  = reg_addr;
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b0;

        // Default CPU outputs
        cpu_ready     = 1'b0;
        cpu_rdata     = reg_rdata;
        cpu_err       = reg_err;

        case (state)
            ST_IDLE: begin
                if (cpu_req) begin
                    if (cpu_we) begin
                        next_state = ST_WRITE_TX;
                    end else begin
                        next_state = ST_READ_ADDR;
                    end
                end
            end

            ST_WRITE_TX: begin
                // Keep asserting valid until the corresponding channel handshake completes
                m_axi_awvalid = !aw_done;
                m_axi_wvalid  = !w_done;

                // Check if both address and data channels have completed their transfers
                if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
                    (w_done  || (m_axi_wvalid  && m_axi_wready))) begin
                    next_state = ST_WRITE_RESP;
                end
            end

            ST_WRITE_RESP: begin
                m_axi_bready = 1'b1;
                if (m_axi_bvalid) begin
                    cpu_ready  = 1'b1;
                    cpu_err    = (m_axi_bresp != 2'b00);
                    next_state = ST_IDLE;
                end
            end

            ST_READ_ADDR: begin
                m_axi_arvalid = 1'b1;
                if (m_axi_arready) begin
                    next_state = ST_READ_DATA;
                end
            end

            ST_READ_DATA: begin
                m_axi_rready = 1'b1;
                if (m_axi_rvalid) begin
                    cpu_ready  = 1'b1;
                    cpu_rdata  = m_axi_rdata;
                    cpu_err    = (m_axi_rresp != 2'b00);
                    next_state = ST_IDLE;
                end
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

endmodule
