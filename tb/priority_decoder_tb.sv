`timescale 1ns / 1ps

// Note: This testbench is specifically for the WIDTH=4
// version of your decoder, as shown in your screenshot.

module priority_decoder_tb;

  // --- Parameters ---
  parameter TB_WIDTH = 4;
  // Output width is clog2(TB_WIDTH). For 4, clog2(4) = 2.
  parameter TB_OUT_WIDTH = 2; 

  // --- Testbench Signals ---
  // Inputs to the DUT are 'reg'
  reg  [TB_WIDTH-1:0]     tb_in;
  
  // Outputs from the DUT are 'wire'
  wire [TB_OUT_WIDTH-1:0] tb_out;
  wire                    tb_valid;

  // --- Instantiate the Device Under Test (DUT) ---
  // The module name 'piority_decoder' matches your screenshot's typo
  priority_decoder #(
    .WIDTH(TB_WIDTH)
  ) DUT (
    .in(tb_in),
    .out(tb_out),
    .valid(tb_valid)
  );

  // --- Test Vector Logic ---
  initial begin
    // Initialize inputs
    tb_in = 4'b0000;
    #10; // Wait 10ns for signals to settle

    // Test 1: All zeros
    // Expect: valid=0
    $display("Test 1: Input 0000");
    tb_in = 4'b0000;
    #10;

    // Test 2: Lowest bit (highest priority)
    // Expect: valid=1, out=0
    $display("Test 2: Input 0001");
    tb_in = 4'b0001;
    #10;

    // Test 3: Highest bit (lowest priority)
    // Expect: valid=1, out=3
    $display("Test 3: Input 1000");
    tb_in = 4'b1000;
    #10;

    // Test 4: Multiple bits (check priority)
    // in[2] has priority over in[3]
    // Expect: valid=1, out=2
    $display("Test 4: Input 1100");
    tb_in = 4'b1100;
    #10;

    // Test 5: Another multiple bit test
    // in[0] has priority over in[2]
    // Expect: valid=1, out=0
    $display("Test 5: Input 0101");
    tb_in = 4'b0101;
    #10;
    
    // 3. End simulation
    $display("Test complete.");
    $finish;
  end

  // Optional: This will print all signal changes to the console
  always @(*) begin
    $monitor("Time = %0t | In = %b | Valid = %b | Out = %d",
             $time, tb_in, tb_valid, tb_out);
  end

endmodule