`timescale 1ns / 1ps

module fifo_tb_non_circular;

  // -------------------------------------------------------------
  // Parameters
  // -------------------------------------------------------------
  parameter type T = logic [31:0];
  parameter int  DEPTH = 8;

  // -------------------------------------------------------------
  // DUT signals
  // -------------------------------------------------------------
  logic clk;
  logic reset;
  logic write_en;
  logic read_en;
  T     write_data;
  T     read_data;
  logic full;
  logic empty;

  // -------------------------------------------------------------
  // Instantiate DUT
  // -------------------------------------------------------------
  fifo #(
    .T(T),
    .DEPTH(DEPTH)
  ) dut (
    .clk(clk),
    .reset(reset),
    .write_en(write_en),
    .write_data(write_data),
    .read_en(read_en),
    .read_data(read_data),
    .full(full),
    .empty(empty)
  );

  // -------------------------------------------------------------
  // Clock generation (10 ns period)
  // -------------------------------------------------------------
  initial clk = 0;
  always #5 clk = ~clk;

  // -------------------------------------------------------------
  // Test stimulus
  // -------------------------------------------------------------
  initial begin
    // --- Initialize ---
    write_en   = 0;
    read_en    = 0;
    write_data = '0;
    reset      = 1;

    // --- Apply reset for a few cycles ---
    repeat (3) @(posedge clk);
    reset = 0;
    $display("[%0t] Release reset", $time);

    // =============================================================
    // MODULE 1: Pipe data into FIFO until full
    // =============================================================
    $display("\n=== MODULE 1: Writing until FIFO is full ===");

    for (integer i = 0; i < DEPTH + 3; i++) begin
      @(posedge clk);
      if (!full) begin
        write_en   = 1;
        write_data = i;
        $display("[%0t] WRITE  data = %0d (wr_en=1)", $time, write_data);
      end else begin
        write_en = 0;
        $display("[%0t] FIFO FULL (cannot write %0d)", $time, i);
      end
    end

    // Stop writing
    @(posedge clk);
    write_en = 0;

    // =============================================================
    // MODULE 2: Read data from FIFO when full
    // =============================================================
    $display("\n=== MODULE 2: Reading data from FIFO ===");

    // Wait one cycle to settle
    @(posedge clk);
    read_en = 1;

    while (!empty) begin
      @(posedge clk);
      $display("[%0t] READ   data = %0d (rd_en=1)", $time, read_data);
    end

    // Stop reading
    @(posedge clk);
    read_en = 0;

    $display("\n[%0t] FIFO now empty. Test complete.", $time);
    $stop;
  end

endmodule
