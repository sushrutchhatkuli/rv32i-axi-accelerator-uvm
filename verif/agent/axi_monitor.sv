// =============================================================================
// File: axi_monitor.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: UVM Monitor Component.
//              Passively samples the AXI bus pins on every posedge clk using
//              the monitor_cb clocking block (#1step preponed sampling).
//              Reconstructs completed write/read transactions and passes them
//              to the Scoreboard and Coverage collectors.
// =============================================================================

`timescale 1ns / 1ps

class axi_monitor;

    virtual axi_if vif;

    // Mailboxes / Queues to collect observed transactions
    axi_seq_item captured_writes[$];
    axi_seq_item captured_reads[$];

    // Constructor
    function new(virtual axi_if vif);
        this.vif = vif;
    endfunction

    // -------------------------------------------------------------------------
    // Monitoring Loop: Run continuously in background
    // -------------------------------------------------------------------------
    task run();
        fork
            monitor_writes();
            monitor_reads();
        join
    endtask

    // Passively capture Write Transactions
    task monitor_writes();
        bit [31:0] sampled_addr;
        bit [31:0] sampled_data;
        bit [3:0]  sampled_strb;

        forever begin
            @(vif.monitor_cb);

            // Capture address handshake
            if (vif.monitor_cb.awvalid && vif.monitor_cb.awready) begin
                sampled_addr = vif.monitor_cb.awaddr;
            end

            // Capture data handshake
            if (vif.monitor_cb.wvalid && vif.monitor_cb.wready) begin
                sampled_data = vif.monitor_cb.wdata;
                sampled_strb = vif.monitor_cb.wstrb;
            end

            // When response handshake completes, record the transaction
            if (vif.monitor_cb.bvalid && vif.monitor_cb.bready) begin
                axi_seq_item item = new("mon_wr_item");
                item.trans_type = axi_seq_item::WRITE;
                item.addr       = sampled_addr;
                item.data       = sampled_data;
                item.strb       = sampled_strb;
                item.resp       = vif.monitor_cb.bresp;
                captured_writes.push_back(item);
            end
        end
    endtask

    // Passively capture Read Transactions
    task monitor_reads();
        bit [31:0] sampled_addr;

        forever begin
            @(vif.monitor_cb);

            // Capture read address handshake
            if (vif.monitor_cb.arvalid && vif.monitor_cb.arready) begin
                sampled_addr = vif.monitor_cb.araddr;
            end

            // Capture read data handshake
            if (vif.monitor_cb.rvalid && vif.monitor_cb.rready) begin
                axi_seq_item item = new("mon_rd_item");
                item.trans_type = axi_seq_item::READ;
                item.addr       = sampled_addr;
                item.rdata      = vif.monitor_cb.rdata;
                item.resp       = vif.monitor_cb.rresp;
                captured_reads.push_back(item);
            end
        end
    endtask

endclass
