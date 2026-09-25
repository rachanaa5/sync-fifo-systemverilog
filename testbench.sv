`timescale 1ns/1ps

// ============================================================
// 1. SystemVerilog Interface with Clocking Blocks & Modports
// ============================================================
interface fifo_if #(parameter DATA_WIDTH = 8)(input logic clk);
    logic                  rst_n;
    logic                  wr_en;
    logic                  rd_en;
    logic [DATA_WIDTH-1:0] wr_data;
    logic [DATA_WIDTH-1:0] rd_data;
    logic                  full;
    logic                  empty;

    // Clocking Block for Driver: drives outputs with skew, samples inputs
    clocking driver_cb @(posedge clk);
        default input #1ns output #1ns;
        output wr_en;
        output rd_en;
        output wr_data;
        output rst_n;
        input  full;
        input  empty;
        input  rd_data;
    endclocking

    // Clocking Block for Monitor: pure inputs with sampling skew
    clocking monitor_cb @(posedge clk);
        default input #1ns output #1ns;
        input wr_en;
        input rd_en;
        input wr_data;
        input rd_data;
        input full;
        input empty;
        input rst_n;
    endclocking

    // Modports segregating roles
    modport DRV (clocking driver_cb, input clk);
    modport MON (clocking monitor_cb, input clk);

    // Interface Protocol Assertions
    property p_no_overflow;
        @(posedge clk) disable iff (!rst_n)
        (full && wr_en) |-> 1'b0;
    endproperty
    assert_if_overflow: assert property (p_no_overflow)
        else $error("[IF SVA ERROR] Illegal write attempted while FIFO is FULL at %0t", $time);

    property p_no_underflow;
        @(posedge clk) disable iff (!rst_n)
        (empty && rd_en) |-> 1'b0;
    endproperty
    assert_if_underflow: assert property (p_no_underflow)
        else $error("[IF SVA ERROR] Illegal read attempted while FIFO is EMPTY at %0t", $time);

endinterface

// ============================================================
// 2. Transaction Item
// ============================================================
class fifo_item #(parameter DATA_WIDTH = 8);
    rand bit                  wr_en;
    rand bit                  rd_en;
    rand bit [DATA_WIDTH-1:0] wr_data;
    bit      [DATA_WIDTH-1:0] rd_data;
    bit                       full;
    bit                       empty;

    constraint wr_rd_dist {
        wr_en dist {1 := 50, 0 := 50};
        rd_en dist {1 := 50, 0 := 50};
    }
endclass

// ============================================================
// 3. Generator
// ============================================================
class generator #(parameter DATA_WIDTH = 8);
    mailbox #(fifo_item#(DATA_WIDTH)) gen2drv;
    int num_transactions;

    function new(mailbox #(fifo_item#(DATA_WIDTH)) gen2drv, int count);
        this.gen2drv = gen2drv;
        this.num_transactions = count;
    endfunction

    task run();
        fifo_item#(DATA_WIDTH) item;
        for (int i = 0; i < num_transactions; i++) begin
            item = new();
            if (!item.randomize()) begin
                $error("[GEN] Randomization failed!");
            end
            gen2drv.put(item);
        end
    endtask
endclass

// ============================================================
// 4. Driver (Using Virtual Interface with DRV Modport)
// ============================================================
class driver #(parameter DATA_WIDTH = 8);
    mailbox #(fifo_item#(DATA_WIDTH)) gen2drv;
    virtual fifo_if#(DATA_WIDTH).DRV vif;

    function new(mailbox #(fifo_item#(DATA_WIDTH)) gen2drv, virtual fifo_if#(DATA_WIDTH).DRV vif);
        this.gen2drv = gen2drv;
        this.vif     = vif;
    endfunction

    task run();
        fifo_item#(DATA_WIDTH) item;
        forever begin
            gen2drv.get(item);
            @(vif.driver_cb);
            vif.driver_cb.wr_en   <= item.wr_en;
            vif.driver_cb.rd_en   <= item.rd_en;
            vif.driver_cb.wr_data <= item.wr_data;
        end
    endtask
endclass

// ============================================================
// 5. Monitor & Functional Coverage (Using MON Modport)
// ============================================================
class monitor #(parameter DATA_WIDTH = 8);
    virtual fifo_if#(DATA_WIDTH).MON vif;
    mailbox #(fifo_item#(DATA_WIDTH)) mon2scb;

    covergroup fifo_cg;
        option.per_instance = 1;

        cp_wr_en: coverpoint vif.monitor_cb.wr_en {
            bins active = {1};
            bins idle   = {0};
        }
        cp_rd_en: coverpoint vif.monitor_cb.rd_en {
            bins active = {1};
            bins idle   = {0};
        }
        cp_full: coverpoint vif.monitor_cb.full {
            bins is_full  = {1};
            bins not_full = {0};
        }
        cp_empty: coverpoint vif.monitor_cb.empty {
            bins is_empty  = {1};
            bins not_empty = {0};
        }
        cross_wr_full:  cross cp_wr_en, cp_full;
        cross_rd_empty: cross cp_rd_en, cp_empty;
        cross_wr_rd:    cross cp_wr_en, cp_rd_en;
    endgroup

    function new(virtual fifo_if#(DATA_WIDTH).MON vif, mailbox #(fifo_item#(DATA_WIDTH)) mon2scb);
        this.vif     = vif;
        this.mon2scb = mon2scb;
        this.fifo_cg = new();
    endfunction

    task run();
        fifo_item#(DATA_WIDTH) item;
        bit rd_pending = 0;

        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.rst_n) begin
                item = new();
                item.wr_en   = vif.monitor_cb.wr_en;
                item.rd_en   = vif.monitor_cb.rd_en;
                item.wr_data = vif.monitor_cb.wr_data;
                item.full    = vif.monitor_cb.full;
                item.empty   = vif.monitor_cb.empty;

                // Pick up read data when valid on the cycle following rd_en
                if (rd_pending) begin
                    item.rd_data = vif.monitor_cb.rd_data;
                end

                rd_pending = (vif.monitor_cb.rd_en && !vif.monitor_cb.empty);
                fifo_cg.sample();
                mon2scb.put(item);
            end else begin
                rd_pending = 0;
            end
        end
    endtask
endclass

// ============================================================
// 6. Scoreboard (Golden Model with Read Latency Sync)
// ============================================================
class scoreboard #(parameter DATA_WIDTH = 8);
    mailbox #(fifo_item#(DATA_WIDTH)) mon2scb;
    logic [DATA_WIDTH-1:0] expected_queue[$];
    int pass_count = 0;
    int fail_count = 0;
    bit check_rd_next = 0;

    function new(mailbox #(fifo_item#(DATA_WIDTH)) mon2scb);
        this.mon2scb = mon2scb;
    endfunction

    task run();
        fifo_item#(DATA_WIDTH) item;
        logic [DATA_WIDTH-1:0] exp_data;

        forever begin
            mon2scb.get(item);

            // 1. Verify read data from preceding cycle
            if (check_rd_next) begin
                if (expected_queue.size() > 0) begin
                    exp_data = expected_queue.pop_front();
                    if (item.rd_data === exp_data) begin
                        pass_count++;
                    end else begin
                        $error("[SCB FAIL] Mismatch! Exp: 0x%02X, Got: 0x%02X at time %0t", exp_data, item.rd_data, $time);
                        fail_count++;
                    end
                end
                check_rd_next = 0;
            end

            // 2. Queue write data on valid write
            if (item.wr_en && !item.full) begin
                expected_queue.push_back(item.wr_data);
            end

            // 3. Mark read data check due on next cycle
            if (item.rd_en && !item.empty) begin
                check_rd_next = 1;
            end
        end
    endtask
endclass

// ============================================================
// 7. Top-Level Testbench Module
// ============================================================
module tb_fifo;
    localparam DATA_WIDTH = 8;
    localparam FIFO_DEPTH = 16;

    logic clk;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Interface instance
    fifo_if #(DATA_WIDTH) intf(clk);

    // DUT instance (directly connected to interface signals)
    synchronous_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk    (intf.clk),
        .rst_n  (intf.rst_n),
        .wr_en  (intf.wr_en),
        .rd_en  (intf.rd_en),
        .wr_data(intf.wr_data),
        .rd_data(intf.rd_data),
        .full   (intf.full),
        .empty  (intf.empty)
    );

    // Mailboxes
    mailbox #(fifo_item#(DATA_WIDTH)) gen2drv = new();
    mailbox #(fifo_item#(DATA_WIDTH)) mon2scb = new();

    // Verification Components
    generator  #(DATA_WIDTH) gen;
    driver     #(DATA_WIDTH) drv;
    monitor    #(DATA_WIDTH) mon;
    scoreboard #(DATA_WIDTH) scb;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_fifo);

        // 500 randomized transactions to cover boundary conditions
        gen = new(gen2drv, 500);
        drv = new(gen2drv, intf.DRV);
        mon = new(intf.MON, mon2scb);
        scb = new(mon2scb);

        // Reset DUT
        intf.rst_n   <= 0;
        intf.wr_en   <= 0;
        intf.rd_en   <= 0;
        intf.wr_data <= 0;
        #25;
        @(negedge clk);
        intf.rst_n   <= 1;

        // Run environment
        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join_any

        #3000; // Allow remaining transactions in flight to resolve

        $display("==============================================");
        $display("SIMULATION COMPLETED");
        $display("Scoreboard Results: %0d PASSED, %0d FAILED", scb.pass_count, scb.fail_count);
        $display("Functional Coverage: %0.2f%%", mon.fifo_cg.get_inst_coverage());
        $display("==============================================");
        $finish;
    end
endmodule