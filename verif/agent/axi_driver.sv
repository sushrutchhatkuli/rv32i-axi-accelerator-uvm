// =============================================================================
// File: axi_driver.sv
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: UVM Driver Component.
//              Fetches transaction objects (axi_seq_item) and converts them
//              into physical signal transitions on the AXI bus using the
//              driver_cb clocking block to guarantee zero delta-cycle races.
// =============================================================================

`timescale 1ns / 1ps

class axi_driver;

    virtual axi_if vif;

    // Constructor
    function new(virtual axi_if vif);
        this.vif = vif;
    endfunction

    // -------------------------------------------------------------------------
    // Main Driver Tasks
    // -------------------------------------------------------------------------

    // Drive a Write Transaction across AW, W, B channels
    task drive_write(axi_seq_item item);
        // Inter-transaction backpressure delay
        if (item.delay_cycles > 0) begin
            repeat (item.delay_cycles) @(vif.driver_cb);
        end

        // 1. Assert Address & Data simultaneously
        @(vif.driver_cb);
        vif.driver_cb.awaddr  <= item.addr;
        vif.driver_cb.awvalid <= 1'b1;
        vif.driver_cb.awprot  <= 3'b000;

        vif.driver_cb.wdata   <= item.data;
        vif.driver_cb.wstrb   <= item.strb;
        vif.driver_cb.wvalid  <= 1'b1;
        vif.driver_cb.bready  <= 1'b1;

        // 2. Wait for AW and W handshakes to complete
        fork
            begin
                while (!vif.driver_cb.awready) @(vif.driver_cb);
                @(vif.driver_cb);
                vif.driver_cb.awvalid <= 1'b0;
            end
            begin
                while (!vif.driver_cb.wready) @(vif.driver_cb);
                @(vif.driver_cb);
                vif.driver_cb.wvalid <= 1'b0;
            end
        join

        // 3. Wait for Write Response (B channel)
        while (!vif.driver_cb.bvalid) @(vif.driver_cb);
        item.resp = vif.driver_cb.bresp;
        @(vif.driver_cb);
        vif.driver_cb.bready <= 1'b0;
    endtask

    // Drive a Read Transaction across AR and R channels
    task drive_read(axi_seq_item item);
        if (item.delay_cycles > 0) begin
            repeat (item.delay_cycles) @(vif.driver_cb);
        end

        // 1. Assert Read Address
        @(vif.driver_cb);
        vif.driver_cb.araddr  <= item.addr;
        vif.driver_cb.arvalid <= 1'b1;
        vif.driver_cb.arprot  <= 3'b000;
        vif.driver_cb.rready  <= 1'b1;

        // 2. Wait for ARREADY
        while (!vif.driver_cb.arready) @(vif.driver_cb);
        @(vif.driver_cb);
        vif.driver_cb.arvalid <= 1'b0;

        // 3. Wait for Read Data (R channel)
        while (!vif.driver_cb.rvalid) @(vif.driver_cb);
        item.rdata = vif.driver_cb.rdata;
        item.resp  = vif.driver_cb.rresp;
        @(vif.driver_cb);
        vif.driver_cb.rready <= 1'b0;
    endtask

endclass
