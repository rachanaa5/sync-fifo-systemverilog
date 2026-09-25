// synchronous_fifo.sv
module synchronous_fifo #(
    parameter DATA_WIDTH = 8,
    parameter FIFO_DEPTH = 16
)(
    input  logic                  clk,
    input  logic                  rst_n,      // Active-low asynchronous reset
    input  logic                  wr_en,
    input  logic                  rd_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic                  full,
    output logic                  empty
);

    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH);

    logic [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];
    logic [ADDR_WIDTH:0]   wr_ptr;
    logic [ADDR_WIDTH:0]   rd_ptr;

    // Full & Empty Flag Logic
    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) && 
                   (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

    // Write Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else if (wr_en && !full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // Read Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr  <= '0;
            rd_data <= '0;
        end else if (rd_en && !empty) begin
            rd_data <= mem[rd_ptr[ADDR_WIDTH-1:0]];
            rd_ptr  <= rd_ptr + 1'b1;
        end
    end

    // ==========================================
    // SYSTEMVERILOG ASSERTIONS (SVA)
    // ==========================================

    // 1. No Overflow Property: Cannot write when FIFO is full
    property p_no_overflow;
        @(posedge clk) disable iff (!rst_n)
        (full && wr_en) |-> ##0 (!full); // Or directly trigger an error if (full && wr_en) occurs
    endproperty

    // A clearer, direct assertion for overflow:
    assert_no_overflow: assert property (
        @(posedge clk) disable iff (!rst_n)
        not (full && wr_en)
    ) else $error("[SVA ERROR] FIFO Overflow detected! wr_en asserted while full=1 at time %0t", $time);

    // 2. No Underflow Property: Cannot read when FIFO is empty
    assert_no_underflow: assert property (
        @(posedge clk) disable iff (!rst_n)
        not (empty && rd_en)
    ) else $error("[SVA ERROR] FIFO Underflow detected! rd_en asserted while empty=1 at time %0t", $time);

    // 3. Reset Check: When rst_n is low, empty must be 1 and full must be 0
    assert_reset_state: assert property (
        @(posedge clk) !rst_n |-> (empty == 1'b1 && full == 1'b0)
    ) else $error("[SVA ERROR] Reset condition failed: empty=%0b, full=%0b", empty, full);

endmodule