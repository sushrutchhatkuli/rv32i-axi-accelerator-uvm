// =============================================================================
// File: dma_controller.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Autonomous AMBA AXI4-Lite Direct Memory Access (DMA) Engine.
//              Features:
//                1. Memory-mapped Slave port for CPU CSR configuration.
//                2. AXI Master port for autonomous memory block streaming.
//                3. 16-word internal circular FIFO decoupling read/write paths.
//                4. Programmable transfer length, source, and destination pointers.
//                5. Hardware interrupt generation (dma_irq_out) on transfer done.
// =============================================================================

`timescale 1ns / 1ps

module dma_controller #(
    parameter int FIFO_DEPTH = 16,
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // =========================================================================
    // AXI4-Lite Slave Interface (CPU CSR Programming)
    // =========================================================================
    input  logic [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  logic                   s_axi_awvalid,
    output logic                   s_axi_awready,

    input  logic [DATA_WIDTH-1:0]  s_axi_wdata,
    input  logic [3:0]             s_axi_wstrb,
    input  logic                   s_axi_wvalid,
    output logic                   s_axi_wready,

    output logic [1:0]             s_axi_bresp,
    output logic                   s_axi_bvalid,
    input  logic                   s_axi_bready,

    input  logic [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  logic                   s_axi_arvalid,
    output logic                   s_axi_arready,

    output logic [DATA_WIDTH-1:0]  s_axi_rdata,
    output logic [1:0]             s_axi_rresp,
    output logic                   s_axi_rvalid,
    input  logic                   s_axi_rready,

    // =========================================================================
    // AXI4-Lite Master Interface (Autonomous Bus Streaming)
    // =========================================================================
    // Write Address Channel (AW)
    output logic [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output logic                   m_axi_awvalid,
    input  logic                   m_axi_awready,

    // Write Data Channel (W)
    output logic [DATA_WIDTH-1:0]  m_axi_wdata,
    output logic [3:0]             m_axi_wstrb,
    output logic                   m_axi_wvalid,
    input  logic                   m_axi_wready,

    // Write Response Channel (B)
    input  logic [1:0]             m_axi_bresp,
    input  logic                   m_axi_bvalid,
    output logic                   m_axi_bready,

    // Read Address Channel (AR)
    output logic [ADDR_WIDTH-1:0]  m_axi_araddr,
    output logic                   m_axi_arvalid,
    input  logic                   m_axi_arready,

    // Read Data Channel (R)
    input  logic [DATA_WIDTH-1:0]  m_axi_rdata,
    input  logic [1:0]             m_axi_rresp,
    input  logic                   m_axi_rvalid,
    output logic                   m_axi_rready,

    // =========================================================================
    // Hardware Interrupt Output
    // =========================================================================
    output logic                   dma_irq_out
);

    // =========================================================================
    // Memory-Mapped CSR Offsets
    // =========================================================================
    localparam logic [4:0] REG_SRC_ADDR = 5'h00; // 0x00
    localparam logic [4:0] REG_DST_ADDR = 5'h04; // 0x04
    localparam logic [4:0] REG_LENGTH   = 5'h08; // 0x08 (Length in bytes)
    localparam logic [4:0] REG_CTRL     = 5'h0C; // 0x0C (Bit 0: START, Bit 1: IRQ_EN)
    localparam logic [4:0] REG_STATUS   = 5'h10; // 0x10 (Bit 0: BUSY, Bit 1: DONE, Bit 2: ERR)

    // CSR Storage Registers
    logic [31:0] reg_src_addr;
    logic [31:0] reg_dst_addr;
    logic [31:0] reg_length;
    logic        reg_irq_en;
    logic        status_busy;
    logic        status_done;
    logic        status_error;
    logic        dma_start_pulse;

    assign dma_irq_out = reg_irq_en & status_done;

    // =========================================================================
    // AXI Slave Port (CSR Read / Write Logic)
    // =========================================================================
    assign s_axi_bresp = 2'b00; // OKAY
    assign s_axi_rresp = 2'b00; // OKAY

    // Slave Write Channel FSM
    typedef enum logic [1:0] {
        S_WR_IDLE  = 2'd0,
        S_WR_DATA  = 2'd1,
        S_WR_RESP  = 2'd2
    } s_wr_state_t;

    s_wr_state_t s_wr_state;
    logic [4:0]  latched_wr_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_wr_state      <= S_WR_IDLE;
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            latched_wr_reg  <= 5'd0;
            reg_src_addr    <= 32'd0;
            reg_dst_addr    <= 32'd0;
            reg_length      <= 32'd0;
            reg_irq_en      <= 1'b0;
            dma_start_pulse <= 1'b0;
        end else begin
            dma_start_pulse <= 1'b0; // Default pulse low

            case (s_wr_state)
                S_WR_IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    if (s_axi_awvalid) begin
                        s_axi_awready  <= 1'b1;
                        latched_wr_reg <= s_axi_awaddr[4:0];
                        if (s_axi_wvalid) begin
                            s_axi_wready <= 1'b1;
                            s_wr_state   <= S_WR_RESP;
                            // Apply write immediately if both AW and W valid
                            case (s_axi_awaddr[4:0])
                                REG_SRC_ADDR: reg_src_addr <= s_axi_wdata;
                                REG_DST_ADDR: reg_dst_addr <= s_axi_wdata;
                                REG_LENGTH:   reg_length   <= s_axi_wdata;
                                REG_CTRL: begin
                                    if (s_axi_wdata[0] && !status_busy) begin
                                        dma_start_pulse <= 1'b1;
                                    end
                                    reg_irq_en <= s_axi_wdata[1];
                                end
                                default: ;
                            endcase
                        end else begin
                            s_wr_state <= S_WR_DATA;
                        end
                    end else begin
                        s_axi_awready <= 1'b0;
                    end
                end

                S_WR_DATA: begin
                    s_axi_awready <= 1'b0;
                    if (s_axi_wvalid) begin
                        s_axi_wready <= 1'b1;
                        s_wr_state   <= S_WR_RESP;
                        case (latched_wr_reg)
                            REG_SRC_ADDR: reg_src_addr <= s_axi_wdata;
                            REG_DST_ADDR: reg_dst_addr <= s_axi_wdata;
                            REG_LENGTH:   reg_length   <= s_axi_wdata;
                            REG_CTRL: begin
                                if (s_axi_wdata[0] && !status_busy) begin
                                    dma_start_pulse <= 1'b1;
                                end
                                reg_irq_en <= s_axi_wdata[1];
                            end
                            default: ;
                        endcase
                    end
                end

                S_WR_RESP: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b0;
                    s_axi_bvalid  <= 1'b1;
                    if (s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        s_wr_state   <= S_WR_IDLE;
                    end
                end

                default: s_wr_state <= S_WR_IDLE;
            endcase
        end
    end

    // Slave Read Channel FSM
    typedef enum logic {
        S_RD_IDLE = 1'b0,
        S_RD_RESP = 1'b1
    } s_rd_state_t;

    s_rd_state_t s_rd_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_rd_state    <= S_RD_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
        end else begin
            case (s_rd_state)
                S_RD_IDLE: begin
                    if (s_axi_arvalid) begin
                        s_axi_arready <= 1'b1;
                        s_axi_rvalid  <= 1'b1;
                        s_rd_state    <= S_RD_RESP;
                        case (s_axi_araddr[4:0])
                            REG_SRC_ADDR: s_axi_rdata <= reg_src_addr;
                            REG_DST_ADDR: s_axi_rdata <= reg_dst_addr;
                            REG_LENGTH:   s_axi_rdata <= reg_length;
                            REG_CTRL:     s_axi_rdata <= {30'd0, reg_irq_en, 1'b0};
                            REG_STATUS:   s_axi_rdata <= {29'd0, status_error, status_done, status_busy};
                            default:      s_axi_rdata <= 32'd0;
                        endcase
                    end else begin
                        s_axi_arready <= 1'b0;
                    end
                end

                S_RD_RESP: begin
                    s_axi_arready <= 1'b0;
                    if (s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        s_rd_state   <= S_RD_IDLE;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // Internal 16-Word FIFO Buffer
    // =========================================================================
    logic [DATA_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];
    logic [3:0]            fifo_wr_ptr;
    logic [3:0]            fifo_rd_ptr;
    logic [4:0]            fifo_count;

    logic                  fifo_push;
    logic                  fifo_pop;
    logic [DATA_WIDTH-1:0] fifo_wdata;
    logic [DATA_WIDTH-1:0] fifo_rdata;

    wire fifo_full  = (fifo_count == FIFO_DEPTH[4:0]);
    wire fifo_empty = (fifo_count == 5'd0);

    assign fifo_rdata = fifo_mem[fifo_rd_ptr];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr <= 4'd0;
            fifo_rd_ptr <= 4'd0;
            fifo_count  <= 5'd0;
            for (int i = 0; i < FIFO_DEPTH; i++) fifo_mem[i] <= 32'd0;
        end else if (dma_start_pulse) begin
            // Reset FIFO on new transfer
            fifo_wr_ptr <= 4'd0;
            fifo_rd_ptr <= 4'd0;
            fifo_count  <= 5'd0;
        end else begin
            if (fifo_push && !fifo_full) begin
                fifo_mem[fifo_wr_ptr] <= fifo_wdata;
                fifo_wr_ptr           <= fifo_wr_ptr + 4'd1;
            end

            if (fifo_pop && !fifo_empty) begin
                fifo_rd_ptr <= fifo_rd_ptr + 4'd1;
            end

            case ({fifo_push && !fifo_full, fifo_pop && !fifo_empty})
                2'b10: fifo_count <= fifo_count + 5'd1;
                2'b01: fifo_count <= fifo_count - 5'd1;
                default: ; // Both or neither: count unchanged
            endcase
        end
    end

    // =========================================================================
    // Master Engine: Total Words Calculation
    // =========================================================================
    logic [31:0] total_words;
    logic [31:0] words_read_cnt;
    logic [31:0] words_written_cnt;
    logic [31:0] current_src_ptr;
    logic [31:0] current_dst_ptr;

    // =========================================================================
    // Master Read Engine FSM (AR and R Channels)
    // =========================================================================
    typedef enum logic [1:0] {
        RD_IDLE = 2'd0,
        RD_AR   = 2'd1,
        RD_R    = 2'd2
    } rd_state_t;

    rd_state_t rd_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state        <= RD_IDLE;
            m_axi_araddr    <= 32'd0;
            m_axi_arvalid   <= 1'b0;
            m_axi_rready    <= 1'b0;
            words_read_cnt  <= 32'd0;
            current_src_ptr <= 32'd0;
            fifo_push       <= 1'b0;
            fifo_wdata      <= 32'd0;
        end else begin
            fifo_push <= 1'b0; // Default pulse

            case (rd_state)
                RD_IDLE: begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    if (dma_start_pulse) begin
                        words_read_cnt  <= 32'd0;
                        current_src_ptr <= reg_src_addr;
                        rd_state        <= RD_AR;
                    end
                end

                RD_AR: begin
                    if (words_read_cnt < total_words) begin
                        if (!fifo_full) begin
                            m_axi_araddr  <= current_src_ptr;
                            m_axi_arvalid <= 1'b1;
                            if (m_axi_arvalid && m_axi_arready) begin
                                m_axi_arvalid <= 1'b0;
                                m_axi_rready  <= 1'b1;
                                rd_state      <= RD_R;
                            end
                        end else begin
                            m_axi_arvalid <= 1'b0; // Wait for FIFO space
                        end
                    end else begin
                        m_axi_arvalid <= 1'b0;
                        rd_state      <= RD_IDLE;
                    end
                end

                RD_R: begin
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready    <= 1'b0;
                        fifo_push       <= 1'b1;
                        fifo_wdata      <= m_axi_rdata;
                        current_src_ptr <= current_src_ptr + 32'd4;
                        words_read_cnt  <= words_read_cnt + 32'd1;
                        rd_state        <= RD_AR;
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Master Write Engine FSM (AW, W, and B Channels)
    // =========================================================================
    typedef enum logic [1:0] {
        WR_IDLE   = 2'd0,
        WR_AW_W   = 2'd1,
        WR_B      = 2'd2
    } wr_state_t;

    wr_state_t wr_state;
    logic      wr_aw_done;
    logic      wr_w_done;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state          <= WR_IDLE;
            m_axi_awaddr      <= 32'd0;
            m_axi_awvalid     <= 1'b0;
            m_axi_wdata       <= 32'd0;
            m_axi_wstrb       <= 4'b0000;
            m_axi_wvalid      <= 1'b0;
            m_axi_bready      <= 1'b0;
            words_written_cnt <= 32'd0;
            current_dst_ptr   <= 32'd0;
            fifo_pop          <= 1'b0;
            wr_aw_done        <= 1'b0;
            wr_w_done         <= 1'b0;
            status_busy       <= 1'b0;
            status_done       <= 1'b0;
            status_error      <= 1'b0;
            total_words       <= 32'd0;
        end else begin
            fifo_pop <= 1'b0; // Default pulse

            if (dma_start_pulse) begin
                status_busy       <= 1'b1;
                status_done       <= 1'b0;
                status_error      <= 1'b0;
                total_words       <= reg_length >> 2;
                words_written_cnt <= 32'd0;
                current_dst_ptr   <= reg_dst_addr;
                wr_state          <= WR_AW_W;
                wr_aw_done        <= 1'b0;
                wr_w_done         <= 1'b0;
            end else begin
                case (wr_state)
                    WR_IDLE: begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b0;
                        m_axi_bready  <= 1'b0;
                    end

                    WR_AW_W: begin
                        if (words_written_cnt < total_words) begin
                            if (!fifo_empty) begin
                                m_axi_awaddr <= current_dst_ptr;
                                m_axi_wdata  <= fifo_rdata;
                                m_axi_wstrb  <= 4'b1111;

                                if (!wr_aw_done) m_axi_awvalid <= 1'b1;
                                if (!wr_w_done)  m_axi_wvalid  <= 1'b1;

                                if (m_axi_awvalid && m_axi_awready) begin
                                    m_axi_awvalid <= 1'b0;
                                    wr_aw_done    <= 1'b1;
                                end

                                if (m_axi_wvalid && m_axi_wready) begin
                                    m_axi_wvalid <= 1'b0;
                                    wr_w_done    <= 1'b1;
                                    fifo_pop     <= 1'b1; // Pop consumed word
                                end

                                if ((wr_aw_done || (m_axi_awvalid && m_axi_awready)) &&
                                    (wr_w_done  || (m_axi_wvalid  && m_axi_wready))) begin
                                    m_axi_awvalid <= 1'b0;
                                    m_axi_wvalid  <= 1'b0;
                                    m_axi_bready  <= 1'b1;
                                    wr_aw_done    <= 1'b0;
                                    wr_w_done     <= 1'b0;
                                    wr_state      <= WR_B;
                                end
                            end else begin
                                m_axi_awvalid <= 1'b0;
                                m_axi_wvalid  <= 1'b0;
                            end
                        end else begin
                            // Transfer completely finished!
                            status_busy <= 1'b0;
                            status_done <= 1'b1;
                            wr_state    <= WR_IDLE;
                        end
                    end

                    WR_B: begin
                        m_axi_bready <= 1'b1;
                        if (m_axi_bvalid && m_axi_bready) begin
                            m_axi_bready      <= 1'b0;
                            current_dst_ptr   <= current_dst_ptr + 32'd4;
                            words_written_cnt <= words_written_cnt + 32'd1;
                            wr_state          <= WR_AW_W;
                        end
                    end

                    default: wr_state <= WR_IDLE;
                endcase
            end
        end
    end

endmodule
