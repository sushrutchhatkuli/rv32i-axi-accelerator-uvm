// =============================================================================
// File: l1_cache_controller.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: L1 Hardware Cache Subsystem.
//              Implements a 1 KB Direct-Mapped Cache (64 lines x 16 bytes).
//              Features:
//                1. Single-cycle cache hit detection (0 wait states).
//                2. 4-word sequential AXI line refill on read miss.
//                3. Write-Through coherence to main memory.
//                4. Non-Cacheable MMIO bypass for peripheral registers (0x4000_XXXX).
//                5. Hit and Miss performance telemetry counters.
// =============================================================================

`timescale 1ns / 1ps

module l1_cache_controller #(
    parameter int NUM_LINES      = 64,  // 64 cache lines
    parameter int WORDS_PER_LINE = 4,   // 4 words = 16 bytes per line
    parameter int ADDR_WIDTH     = 32,
    parameter int DATA_WIDTH     = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // =========================================================================
    // CPU Native Bus Interface (From CPU Data/Memory Stage)
    // =========================================================================
    input  logic                   cpu_req,
    input  logic                   cpu_we,
    input  logic [ADDR_WIDTH-1:0]  cpu_addr,
    input  logic [DATA_WIDTH-1:0]  cpu_wdata,
    input  logic [3:0]             cpu_strb,
    output logic [DATA_WIDTH-1:0]  cpu_rdata,
    output logic                   cpu_ready,
    output logic                   cache_hit,

    // Performance Telemetry
    output logic [31:0]            perf_hits,
    output logic [31:0]            perf_misses,

    // =========================================================================
    // AXI4-Lite Master Interface (To Interconnect Crossbar)
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
    output logic                   m_axi_rready
);

    // =========================================================================
    // Address Field Extraction
    // =========================================================================
    // [31:10] Tag (22 bits)
    // [9:4]   Index (6 bits, 64 lines)
    // [3:2]   Word Offset (2 bits, 4 words)
    // [1:0]   Byte Offset (2 bits)
    localparam int TAG_WIDTH   = 22;
    localparam int INDEX_WIDTH = 6;
    localparam int WORD_WIDTH  = 2;

    wire [TAG_WIDTH-1:0]   cpu_tag      = cpu_addr[31:10];
    wire [INDEX_WIDTH-1:0] cpu_index    = cpu_addr[9:4];
    wire [WORD_WIDTH-1:0]  cpu_word_idx = cpu_addr[3:2];

    // Non-cacheable MMIO region: 0x4000_0000 and above (Accelerator registers)
    wire is_mmio = (cpu_addr >= 32'h4000_0000);

    // =========================================================================
    // Cache Storage Arrays
    // =========================================================================
    logic                  valid_array [0:NUM_LINES-1];
    logic [TAG_WIDTH-1:0]  tag_array   [0:NUM_LINES-1];
    logic [DATA_WIDTH-1:0] data_array  [0:NUM_LINES-1][0:WORDS_PER_LINE-1];

    // Combinational Hit Detection for Current CPU Request
    wire line_valid = valid_array[cpu_index];
    wire tag_match  = (tag_array[cpu_index] == cpu_tag);
    wire raw_hit    = (!is_mmio) && line_valid && tag_match;

    // =========================================================================
    // Cache Controller FSM State Encoding
    // =========================================================================
    typedef enum logic [3:0] {
        ST_IDLE          = 4'd0,
        ST_REFILL_AR     = 4'd1,
        ST_REFILL_R      = 4'd2,
        ST_REFILL_DONE   = 4'd3,
        ST_WRITE_AW_W    = 4'd4,
        ST_WRITE_B       = 4'd5,
        ST_MMIO_RD_AR    = 4'd6,
        ST_MMIO_RD_R     = 4'd7,
        ST_MMIO_WR_AW_W  = 4'd8,
        ST_MMIO_WR_B     = 4'd9
    } cache_state_t;

    cache_state_t state, next_state;

    // Latched request registers for multi-cycle refill / write-through
    logic [ADDR_WIDTH-1:0]  latched_addr;
    logic [DATA_WIDTH-1:0]  latched_wdata;
    logic [3:0]             latched_strb;
    logic [TAG_WIDTH-1:0]   latched_tag;
    logic [INDEX_WIDTH-1:0] latched_idx;
    logic [WORD_WIDTH-1:0]  latched_word_idx;
    logic [1:0]             refill_cnt;

    // AXI handshake flags for concurrent AW/W channels
    logic aw_done;
    logic w_done;

    // Telemetry Registers
    logic [31:0] hit_counter;
    logic [31:0] miss_counter;
    assign perf_hits   = hit_counter;
    assign perf_misses = miss_counter;

    // Output holding register for multi-cycle responses
    logic [DATA_WIDTH-1:0] latched_rdata;

    // Helper: apply byte-write strobe to 32-bit word
    function automatic [31:0] apply_strb(
        input [31:0] orig_word,
        input [31:0] new_word,
        input [3:0]  strobe
    );
        apply_strb[7:0]   = strobe[0] ? new_word[7:0]   : orig_word[7:0];
        apply_strb[15:8]  = strobe[1] ? new_word[15:8]  : orig_word[15:8];
        apply_strb[23:16] = strobe[2] ? new_word[23:16] : orig_word[23:16];
        apply_strb[31:24] = strobe[3] ? new_word[31:24] : orig_word[31:24];
    endfunction

    // =========================================================================
    // Cache Controller Main Sequential Process
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            refill_cnt       <= 2'b00;
            aw_done          <= 1'b0;
            w_done           <= 1'b0;
            hit_counter      <= 32'd0;
            miss_counter     <= 32'd0;
            latched_addr     <= 32'd0;
            latched_wdata    <= 32'd0;
            latched_strb     <= 4'd0;
            latched_tag      <= '0;
            latched_idx      <= '0;
            latched_word_idx <= '0;
            latched_rdata    <= 32'd0;

            // Invalidate all cache lines on reset
            for (int i = 0; i < NUM_LINES; i++) begin
                valid_array[i] <= 1'b0;
                tag_array[i]   <= '0;
                for (int w = 0; w < WORDS_PER_LINE; w++) begin
                    data_array[i][w] <= 32'd0;
                end
            end
        end else begin
            state <= next_state;

            case (state)
                ST_IDLE: begin
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;

                    if (cpu_req) begin
                        latched_addr     <= cpu_addr;
                        latched_wdata    <= cpu_wdata;
                        latched_strb     <= cpu_strb;
                        latched_tag      <= cpu_tag;
                        latched_idx      <= cpu_index;
                        latched_word_idx <= cpu_word_idx;

                        if (is_mmio) begin
                            // Non-cacheable MMIO bypass
                        end else if (!cpu_we) begin
                            // Cacheable Read
                            if (raw_hit) begin
                                hit_counter <= hit_counter + 32'd1;
                            end else begin
                                miss_counter <= miss_counter + 32'd1;
                                refill_cnt   <= 2'b00;
                            end
                        end else begin
                            // Cacheable Write (Write-Through)
                            if (raw_hit) begin
                                // Update cached copy immediately
                                data_array[cpu_index][cpu_word_idx] <= apply_strb(
                                    data_array[cpu_index][cpu_word_idx],
                                    cpu_wdata,
                                    cpu_strb
                                );
                            end
                        end
                    end
                end

                // -------------------------------------------------------------
                // Cache Miss Refill: Read 4 consecutive words over AXI
                // -------------------------------------------------------------
                ST_REFILL_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        // Address handshake completed
                    end
                end

                ST_REFILL_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        // Latch incoming word into data array
                        data_array[latched_idx][refill_cnt] <= m_axi_rdata;

                        if (refill_cnt == 2'd3) begin
                            // Line refill complete! Validate line & tag
                            valid_array[latched_idx] <= 1'b1;
                            tag_array[latched_idx]   <= latched_tag;
                        end else begin
                            refill_cnt <= refill_cnt + 2'd1;
                        end
                    end
                end

                ST_REFILL_DONE: begin
                    // Hold data ready for CPU
                    latched_rdata <= data_array[latched_idx][latched_word_idx];
                end

                // -------------------------------------------------------------
                // Write-Through to Main Memory over AXI
                // -------------------------------------------------------------
                ST_WRITE_AW_W: begin
                    if (m_axi_awvalid && m_axi_awready) aw_done <= 1'b1;
                    if (m_axi_wvalid  && m_axi_wready)  w_done  <= 1'b1;
                end

                ST_WRITE_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        aw_done <= 1'b0;
                        w_done  <= 1'b0;
                    end
                end

                // -------------------------------------------------------------
                // Non-Cacheable MMIO Read / Write
                // -------------------------------------------------------------
                ST_MMIO_RD_AR: begin
                    // Waiting for AR handshake
                end

                ST_MMIO_RD_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        latched_rdata <= m_axi_rdata;
                    end
                end

                ST_MMIO_WR_AW_W: begin
                    if (m_axi_awvalid && m_axi_awready) aw_done <= 1'b1;
                    if (m_axi_wvalid  && m_axi_wready)  w_done  <= 1'b1;
                end

                ST_MMIO_WR_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        aw_done <= 1'b0;
                        w_done  <= 1'b0;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // Next-State Combinational Logic
    // =========================================================================
    always_comb begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (cpu_req) begin
                    if (is_mmio) begin
                        if (cpu_we) next_state = ST_MMIO_WR_AW_W;
                        else        next_state = ST_MMIO_RD_AR;
                    end else if (!cpu_we) begin
                        if (raw_hit) next_state = ST_IDLE;
                        else         next_state = ST_REFILL_AR;
                    end else begin
                        next_state = ST_WRITE_AW_W;
                    end
                end
            end

            // Refill: Address phase
            ST_REFILL_AR: begin
                if (m_axi_arready) begin
                    next_state = ST_REFILL_R;
                end
            end

            // Refill: Data phase
            ST_REFILL_R: begin
                if (m_axi_rvalid) begin
                    if (refill_cnt == 2'd3) begin
                        next_state = ST_REFILL_DONE;
                    end else begin
                        next_state = ST_REFILL_AR;
                    end
                end
            end

            // Refill complete: deliver word to CPU in this cycle
            ST_REFILL_DONE: begin
                next_state = ST_IDLE;
            end

            // Write-Through: send AW and W
            ST_WRITE_AW_W: begin
                logic aw_ok;
                logic w_ok;
                aw_ok = aw_done || (m_axi_awvalid && m_axi_awready);
                w_ok  = w_done  || (m_axi_wvalid  && m_axi_wready);
                if (aw_ok && w_ok) begin
                    next_state = ST_WRITE_B;
                end
            end

            ST_WRITE_B: begin
                if (m_axi_bvalid) begin
                    next_state = ST_IDLE;
                end
            end

            // MMIO Read
            ST_MMIO_RD_AR: begin
                if (m_axi_arready) begin
                    next_state = ST_MMIO_RD_R;
                end
            end

            ST_MMIO_RD_R: begin
                if (m_axi_rvalid) begin
                    next_state = ST_IDLE;
                end
            end

            // MMIO Write
            ST_MMIO_WR_AW_W: begin
                logic aw_ok;
                logic w_ok;
                aw_ok = aw_done || (m_axi_awvalid && m_axi_awready);
                w_ok  = w_done  || (m_axi_wvalid  && m_axi_wready);
                if (aw_ok && w_ok) begin
                    next_state = ST_MMIO_WR_B;
                end
            end

            ST_MMIO_WR_B: begin
                if (m_axi_bvalid) begin
                    next_state = ST_IDLE;
                end
            end

            default: next_state = ST_IDLE;
        endcase
    end

    // =========================================================================
    // AXI Bus Channel Outputs (Combinational Driving)
    // =========================================================================
    always_comb begin
        m_axi_awaddr  = 32'd0;
        m_axi_awvalid = 1'b0;
        m_axi_wdata   = 32'd0;
        m_axi_wstrb   = 4'b0000;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b0;
        m_axi_araddr  = 32'd0;
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b0;

        case (state)
            ST_REFILL_AR: begin
                m_axi_araddr  = {latched_tag, latched_idx, refill_cnt, 2'b00};
                m_axi_arvalid = 1'b1;
            end

            ST_REFILL_R: begin
                m_axi_rready = 1'b1;
            end

            ST_WRITE_AW_W: begin
                m_axi_awaddr  = latched_addr;
                m_axi_awvalid = !aw_done;
                m_axi_wdata   = latched_wdata;
                m_axi_wstrb   = latched_strb;
                m_axi_wvalid  = !w_done;
            end

            ST_WRITE_B: begin
                m_axi_bready = 1'b1;
            end

            ST_MMIO_RD_AR: begin
                m_axi_araddr  = latched_addr;
                m_axi_arvalid = 1'b1;
            end

            ST_MMIO_RD_R: begin
                m_axi_rready = 1'b1;
            end

            ST_MMIO_WR_AW_W: begin
                m_axi_awaddr  = latched_addr;
                m_axi_awvalid = !aw_done;
                m_axi_wdata   = latched_wdata;
                m_axi_wstrb   = latched_strb;
                m_axi_wvalid  = !w_done;
            end

            ST_MMIO_WR_B: begin
                m_axi_bready = 1'b1;
            end

            default: ;
        endcase
    end

    // =========================================================================
    // CPU Interface Output Multiplexing
    // =========================================================================
    always_comb begin
        cpu_ready = 1'b0;
        cpu_rdata = 32'd0;
        cache_hit = 1'b0;

        case (state)
            ST_IDLE: begin
                if (cpu_req && !is_mmio && !cpu_we) begin
                    if (raw_hit) begin
                        cpu_ready = 1'b1;
                        cache_hit = 1'b1;
                        cpu_rdata = data_array[cpu_index][cpu_word_idx];
                    end else begin
                        cpu_ready = 1'b0;
                        cache_hit = 1'b0;
                    end
                end
            end

            ST_REFILL_DONE: begin
                cpu_ready = 1'b1;
                cpu_rdata = data_array[latched_idx][latched_word_idx];
                cache_hit = 1'b0;
            end

            ST_WRITE_B: begin
                if (m_axi_bvalid) begin
                    cpu_ready = 1'b1;
                end
            end

            ST_MMIO_RD_R: begin
                if (m_axi_rvalid) begin
                    cpu_ready = 1'b1;
                    cpu_rdata = m_axi_rdata;
                end
            end

            ST_MMIO_WR_B: begin
                if (m_axi_bvalid) begin
                    cpu_ready = 1'b1;
                end
            end

            default: ;
        endcase
    end

endmodule
