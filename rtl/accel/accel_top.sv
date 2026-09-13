// =============================================================================
// File: accel_top.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Top-Level Custom Matrix Accelerator Wrapper.
//              Integrates AXI4-Lite slave interface, CSR register bank,
//              dual-port scratchpad buffer, MAC unit, and FSM sequencer.
//              Memory mapping:
//                0x00 - 0x1C: CSR registers
//                0x100 - 0x7FF: Scratchpad buffer (matrix data)
// =============================================================================

`timescale 1ns / 1ps

module accel_top (
    input  logic        clk,
    input  logic        rst_n,

    // -------------------------------------------------------------------------
    // AXI4-Lite Slave Bus Interface
    // -------------------------------------------------------------------------
    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // -------------------------------------------------------------------------
    // Hardware Interrupt
    // -------------------------------------------------------------------------
    output logic        irq
);

    // -------------------------------------------------------------------------
    // Internal Wiring
    // -------------------------------------------------------------------------
    // CSR Interface
    logic        csr_we;
    logic [4:0]  csr_wr_addr;
    logic [31:0] csr_wdata;
    logic [4:0]  csr_rd_addr;
    logic [31:0] csr_rdata;

    logic        ctrl_start;
    logic        ctrl_irq_en;
    logic        ctrl_soft_reset;
    logic [7:0]  cfg_dim;
    logic [15:0] cfg_src_a_ptr;
    logic [15:0] cfg_src_b_ptr;
    logic [15:0] cfg_dst_ptr;

    logic        sts_busy;
    logic        sts_done;
    logic        sts_overflow;

    // Buffer Port A (AXI Side)
    logic        buf_a_we;
    logic [8:0]  buf_a_addr;
    logic [31:0] buf_a_wdata;
    logic [3:0]  buf_a_wstrb;
    logic [31:0] buf_a_rdata;

    // Buffer Port B (FSM Side)
    logic        buf_b_we;
    logic [9:0]  buf_b_addr;
    logic [15:0] buf_b_wdata;
    logic [15:0] buf_b_rdata;

    // MAC Signals
    logic        mac_clear;
    logic        mac_enable;
    logic signed [15:0] mac_a;
    logic signed [15:0] mac_b;
    logic signed [31:0] mac_acc;
    logic        mac_overflow;

    // -------------------------------------------------------------------------
    // Address Decoding (within 2KB window: offsets 0x000 to 0x7FF)
    // -------------------------------------------------------------------------
    logic [10:0] aw_offset;
    logic [10:0] ar_offset;

    assign aw_offset = s_axi_awaddr[10:0];
    assign ar_offset = s_axi_araddr[10:0];

    // Combinational Read Address Routing
    assign csr_rd_addr = ar_offset[4:0];
    wire [8:0] buf_rd_word_addr = (ar_offset >= 11'h100) ? (ar_offset - 11'h100) >> 2 : 9'd0;

    // Buffer Port A Address Mux: use write address when writing, read address otherwise
    assign buf_a_addr = buf_a_we ? ((aw_offset - 11'h100) >> 2) : buf_rd_word_addr;

    // -------------------------------------------------------------------------
    // AXI4-Lite Slave Write FSM
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        WR_IDLE = 2'b00,
        WR_DATA = 2'b01,
        WR_RESP = 2'b10
    } wr_state_t;

    wr_state_t wr_state;
    logic [10:0] latched_aw_offset;
    logic        aw_done_reg;
    logic        w_done_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state          <= WR_IDLE;
            s_axi_awready     <= 1'b0;
            s_axi_wready      <= 1'b0;
            s_axi_bvalid      <= 1'b0;
            s_axi_bresp       <= 2'b00;
            latched_aw_offset <= 11'd0;
            aw_done_reg       <= 1'b0;
            w_done_reg        <= 1'b0;
            csr_we            <= 1'b0;
            csr_wr_addr       <= 5'd0;
            csr_wdata         <= 32'd0;
            buf_a_we          <= 1'b0;
            buf_a_wdata       <= 32'd0;
            buf_a_wstrb       <= 4'd0;
        end else begin
            csr_we   <= 1'b0;
            buf_a_we <= 1'b0;

            case (wr_state)
                WR_IDLE: begin
                    s_axi_bvalid  <= 1'b0;
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;

                    if (s_axi_awvalid && s_axi_awready) begin
                        latched_aw_offset <= aw_offset;
                        aw_done_reg       <= 1'b1;
                        s_axi_awready     <= 1'b0;
                    end

                    if (s_axi_wvalid && s_axi_wready) begin
                        w_done_reg   <= 1'b1;
                        s_axi_wready <= 1'b0;
                    end

                    // Both handshake channels arrived together
                    if ((s_axi_awvalid && s_axi_awready) && (s_axi_wvalid && s_axi_wready)) begin
                        if (aw_offset < 11'h100) begin
                            csr_we      <= 1'b1;
                            csr_wr_addr <= aw_offset[4:0];
                            csr_wdata   <= s_axi_wdata;
                        end else begin
                            buf_a_we    <= 1'b1;
                            buf_a_wdata <= s_axi_wdata;
                            buf_a_wstrb <= s_axi_wstrb;
                        end
                        wr_state     <= WR_RESP;
                        s_axi_bvalid <= 1'b1;
                        s_axi_bresp  <= 2'b00;
                    end else if ((s_axi_awvalid && s_axi_awready) || (s_axi_wvalid && s_axi_wready)) begin
                        wr_state <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (!aw_done_reg) begin
                        s_axi_awready <= 1'b1;
                        if (s_axi_awvalid && s_axi_awready) begin
                            latched_aw_offset <= aw_offset;
                            aw_done_reg       <= 1'b1;
                            s_axi_awready     <= 1'b0;
                        end
                    end

                    if (!w_done_reg) begin
                        s_axi_wready <= 1'b1;
                        if (s_axi_wvalid && s_axi_wready) begin
                            w_done_reg   <= 1'b1;
                            s_axi_wready <= 1'b0;
                        end
                    end

                    if ((aw_done_reg || (s_axi_awvalid && s_axi_awready)) &&
                        (w_done_reg  || (s_axi_wvalid  && s_axi_wready))) begin
                        if (latched_aw_offset < 11'h100) begin
                            csr_we      <= 1'b1;
                            csr_wr_addr <= latched_aw_offset[4:0];
                            csr_wdata   <= s_axi_wdata;
                        end else begin
                            buf_a_we    <= 1'b1;
                            buf_a_wdata <= s_axi_wdata;
                            buf_a_wstrb <= s_axi_wstrb;
                        end
                        wr_state     <= WR_RESP;
                        s_axi_bvalid <= 1'b1;
                        s_axi_bresp  <= 2'b00;
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
    // AXI4-Lite Slave Read FSM
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
            s_axi_rresp   <= 2'b00;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axi_arready <= 1'b1;
                    if (s_axi_arvalid && s_axi_arready) begin
                        s_axi_arready <= 1'b0;
                        if (ar_offset < 11'h100) begin
                            s_axi_rdata <= csr_rdata;
                        end else begin
                            s_axi_rdata <= buf_a_rdata;
                        end
                        s_axi_rvalid <= 1'b1;
                        s_axi_rresp  <= 2'b00;
                        rd_state     <= RD_RESP;
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

    // -------------------------------------------------------------------------
    // Submodule Instantiations
    // -------------------------------------------------------------------------
    accel_csr u_csr (
        .clk(clk),
        .rst_n(rst_n),
        .reg_we(csr_we),
        .reg_wr_addr(csr_wr_addr),
        .reg_wdata(csr_wdata),
        .reg_rd_addr(csr_rd_addr),
        .reg_rdata(csr_rdata),
        .ctrl_start(ctrl_start),
        .ctrl_irq_en(ctrl_irq_en),
        .ctrl_soft_reset(ctrl_soft_reset),
        .cfg_dim(cfg_dim),
        .cfg_src_a_ptr(cfg_src_a_ptr),
        .cfg_src_b_ptr(cfg_src_b_ptr),
        .cfg_dst_ptr(cfg_dst_ptr),
        .sts_busy(sts_busy),
        .sts_done(sts_done),
        .sts_overflow(sts_overflow)
    );

    accel_buffer #(
        .DEPTH_WORDS(448)
    ) u_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .a_we(buf_a_we),
        .a_addr(buf_a_addr),
        .a_wdata(buf_a_wdata),
        .a_wstrb(buf_a_wstrb),
        .a_rdata(buf_a_rdata),
        .b_we(buf_b_we),
        .b_addr(buf_b_addr),
        .b_wdata(buf_b_wdata),
        .b_rdata(buf_b_rdata)
    );

    mac_unit u_mac (
        .clk(clk),
        .rst_n(rst_n),
        .clear(mac_clear),
        .enable(mac_enable),
        .a(mac_a),
        .b(mac_b),
        .acc(mac_acc),
        .overflow(mac_overflow)
    );

    accel_fsm u_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .start(ctrl_start),
        .soft_reset(ctrl_soft_reset),
        .irq_en(ctrl_irq_en),
        .dim(cfg_dim),
        .src_a_ptr(cfg_src_a_ptr),
        .src_b_ptr(cfg_src_b_ptr),
        .dst_ptr(cfg_dst_ptr),
        .busy(sts_busy),
        .done(sts_done),
        .overflow_flag(sts_overflow),
        .irq(irq),
        .buf_we(buf_b_we),
        .buf_addr(buf_b_addr),
        .buf_wdata(buf_b_wdata),
        .buf_rdata(buf_b_rdata),
        .mac_clear(mac_clear),
        .mac_enable(mac_enable),
        .mac_a(mac_a),
        .mac_b(mac_b),
        .mac_acc(mac_acc),
        .mac_overflow(mac_overflow)
    );

endmodule
