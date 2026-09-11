---
title: "UVM Architecture Hierarchy, Components, and Execution Phases"
tags:
 - uvm
 - verification
 - methodology
 - ieee1800-2
 - object-oriented
date_created: 2026-09-10
status: "Completed"
---

# UVM Architecture Hierarchy, Components, and Execution Phases

> [!NOTE] **What is UVM (Universal Verification Methodology)?**
> Standardized as **IEEE 1800.2**, UVM is a world-wide accepted framework of SystemVerilog base classes. It ensures that verification testbenches built at Apple, NVIDIA, Qualcomm, or Intel follow the exact same architecture, naming conventions, and transaction-level modeling (TLM) rules.

---

## 1. The Real-World Analogy: The Gourmet Restaurant

To understand why UVM has so many different classes, imagine a 5-star restaurant:

```
+-------------------------------------------------------------------------+
| UVM Test (The Restaurant Director) |
| Selects today's menu: "Run 5,000 randomized AXI matrix transactions!" |
+-------------------------------------------------------------------------+
 |
 v
+-------------------------------------------------------------------------+
| UVM Environment (The Restaurant) |
+-------------------------------------------------------------------------+
 | | |
 v v v
+-----------------------+ +---------------+ +-------------+
| UVM Agent | | UVM Scoreboard| | UVM Coverage|
| (The Kitchen Station) | | (The Food | | Collector |
+-----------------------+ | Inspector) | | (The Book- |
 | | +---------------+ | keeper) |
 | v ^ +-------------+
 | +---------------+ | ^
 | | UVM Sequencer | (The Order Board) | |
 | +---------------+ | |
 | | [Orders: uvm_sequence] | |
 | v | |
 | +---------------+ | |
 | | UVM Driver | (The Hands/Cook) | |
 | +---------------+ | |
 | | (Wiggles Physical Pins) | |
 v v | |
+-----------------------+ | |
| UVM Monitor | ---------------------------+----------------+
| (The Camera Observer) | (Broadcasts observed transactions via TLM)
+-----------------------+
```

1. **`uvm_sequence`**: The customer order ("I want a $4 \times 4$ matrix filled with random numbers and a 2-cycle backpressure delay").
2. **`uvm_sequencer`**: The order board. It queues up transactions and passes them one-by-one to the driver.
3. **`uvm_driver`**: The cook's hands. It takes the abstract order and physically wiggles the wires on the chip (`awvalid`, `wdata`, etc.).
4. **`uvm_monitor`**: The security camera. It passively watches the bus wires, reconstructs what was transmitted, and sends it to the inspector.
5. **`uvm_agent`**: The department encapsulating the driver, sequencer, and monitor into one reusable package.
6. **`uvm_scoreboard`**: The quality control inspector. It takes what the monitor saw and compares it against the golden mathematical truth!
7. **`uvm_env`**: The container holding all agents, scoreboards, and coverage collectors.
8. **`uvm_test`**: The director that sets up the environment and starts the test sequence.

---

## 2. The UVM Phasing Mechanism: How Time Advances

Unlike traditional scripts that start and stop arbitrarily, every UVM component automatically executes through **predefined phases** managed by the UVM simulation engine:

```
[ Build Phase ] --> Constructs classes top-down (new, factory create)
[ Connect Phase ] --> Hooks up TLM ports & interfaces bottom-up
[ End-of-Elaboration] -> Final configuration checks
[ Start-of-Simulation]-> Prints simulation banner
========================================================================
[ Run Phase ] --> TIME CONSUMING (task run_phase). Clocks tick!
========================================================================
[ Extract Phase ] --> Collects final scoreboard tallies
[ Check Phase ] --> Ensures no leftover packets or dropped data
[ Report Phase ] --> Prints FINAL PASS / FAIL banner!
```

---

## 3. The Objection Mechanism: Controlling Simulation Life

In UVM, time in the `run_phase` will **instantly terminate at time 0** unless at least one component **raises an objection**:

```systemverilog
task run_phase(uvm_phase phase);
 // 1. Tell UVM: "Do NOT stop the simulator! I have work to do!"
 phase.raise_objection(this);

 // 2. Start the randomized stimulus sequence
 my_seq.start(m_sequencer);

 // 3. Work is finished. Allow the simulator to exit cleanly.
 phase.drop_objection(this);
endtask
```

---

## 4. Complete Code Breakdown of UVM Building Blocks

### A. The Transaction Item (`axi_seq_item.sv`)
```systemverilog
class axi_seq_item extends uvm_sequence_item;
 `uvm_object_utils(axi_seq_item)

 typedef enum { READ, WRITE } op_type_e;

 rand op_type_e op_type;
 rand bit [31:0] addr;
 rand bit [31:0] data;
 rand bit [3:0] strb;
 rand int unsigned ready_delay; // Latency injection

 // Response from DUT
 bit [1:0] resp;

 // Constraints
 constraint c_align { addr[1:0] == 2'b00; }
 constraint c_delay { ready_delay inside {[0:5]}; }

 function new(string name = "axi_seq_item");
 super.new(name);
 endfunction
endclass
```

---

### B. The Driver (`axi_driver.sv`)
```systemverilog
class axi_driver extends uvm_driver #(axi_seq_item);
 `uvm_component_utils(axi_driver)

 virtual axi_if vif;

 function new(string name, uvm_component parent);
 super.new(name, parent);
 endfunction

 function void build_phase(uvm_phase phase);
 super.build_phase(phase);
 if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
 `uvm_fatal("NO_VIF", "Virtual interface not found in config_db!")
 endfunction

 task run_phase(uvm_phase phase);
 forever begin
 // 1. Get next item from sequencer
 seq_item_port.get_next_item(req);
 
 // 2. Drive physical pins using clocking block
 drive_transfer(req);
 
 // 3. Inform sequencer that item is done
 seq_item_port.item_done();
 end
 endtask

 task drive_transfer(axi_seq_item tr);
 if (tr.op_type == axi_seq_item::WRITE) begin
 @(vif.driver_cb);
 vif.driver_cb.awaddr <= tr.addr;
 vif.driver_cb.awvalid <= 1'b1;
 vif.driver_cb.wdata <= tr.data;
 vif.driver_cb.wstrb <= tr.strb;
 vif.driver_cb.wvalid <= 1'b1;

 // Wait for handshake
 do @(vif.driver_cb);
 while (!(vif.driver_cb.awready && vif.driver_cb.wready));

 vif.driver_cb.awvalid <= 1'b0;
 vif.driver_cb.wvalid <= 1'b0;
 vif.driver_cb.bready <= 1'b1;

 do @(vif.driver_cb);
 while (!vif.driver_cb.bvalid);
 vif.driver_cb.bready <= 1'b0;
 end
 endtask
endclass
```

---

### C. The Monitor (`axi_monitor.sv`)
```systemverilog
class axi_monitor extends uvm_monitor;
 `uvm_component_utils(axi_monitor)

 virtual axi_if vif;
 uvm_analysis_port #(axi_seq_item) ap; // Broadcasts to Scoreboard

 function new(string name, uvm_component parent);
 super.new(name, parent);
 ap = new("ap", this);
 endfunction

 function void build_phase(uvm_phase phase);
 super.build_phase(phase);
 uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif);
 endfunction

 task run_phase(uvm_phase phase);
 forever begin
 @(vif.monitor_cb);
 // Sample read/write handshakes
 if (vif.monitor_cb.awvalid && vif.monitor_cb.awready) begin
 axi_seq_item item = axi_seq_item::type_id::create("item");
 item.op_type = axi_seq_item::WRITE;
 item.addr = vif.monitor_cb.awaddr;
 item.data = vif.monitor_cb.wdata;
 ap.write(item); // Broadcast to Scoreboard!
 end
 end
 endtask
endclass
```

---

## Next Steps
Now that we have transactions streaming through the driver and monitor, how does the Scoreboard verify mathematical correctness?
 [[04_Scoreboard_and_DPI_C_Golden_Model|Proceed to Scoreboard & C++ DPI Golden Model]]
