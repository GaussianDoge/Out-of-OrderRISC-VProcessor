`timescale 1ns / 1ps

module skid_buffer_tb;

    // --- Parameters ---
    parameter CLK_PERIOD = 10; // 10ns = 100MHz clock
    localparam DATA_WIDTH = 8; // Test with 8-bit data

    // --- Signals (wires) to connect to DUT ---
    logic clk;
    logic reset;
    
    // Upstream
    logic valid_in;
    logic ready_in; // Output from DUT
    logic [DATA_WIDTH-1:0] data_in;
    
    // Downstream
    logic valid_out; // Output from DUT
    logic ready_out;
    logic [DATA_WIDTH-1:0] data_out; // Output from DUT

    // --- Instantiate the Device Under Test (DUT) ---
    // We override the 'T' parameter to be an 8-bit vector
    skid_buffer_struct #(
        .T ( logic [DATA_WIDTH-1:0] )
    ) u_dut (
        .clk(clk),
        .reset(reset),
        
        .valid_in(valid_in),
        .ready_in(ready_in),
        .data_in(data_in),
        
        .valid_out(valid_out),
        .ready_out(ready_out),
        .data_out(data_out)
    );

    // --- Clock Generator ---
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // --- Waveform Dump (for GTKWave) ---
    initial begin
        $dumpfile("waves.vcd");
        $dumpvars(0, skid_buffer_tb); // Dump all signals in this testbench
    end

    // --- Test Stimulus ---
    initial begin
        $display("--- Simulation Start ---");
        
        // --- 1. Reset ---
        reset = 1;
        valid_in = 0;
        ready_out = 0;
        data_in = 'x;
        repeat(2) @(posedge clk);
        reset = 0;
        $display("Time: %0t - Reset released. Buffer empty.", $time);
        @(posedge clk);
        
        // At this point, buffer should be empty and ready
        // valid_out should be 0
        // ready_in should be 1 (combinational)
        assert (ready_in) else $fatal(1, "FAIL: ready_in is not 1 after reset.");
        assert (!valid_out) else $fatal(1, "FAIL: valid_out is not 0 after reset.");

        // --- 2. Test Pass-through (Full Speed) ---
        // Consumer is ready, producer sends data
        $display("Time: %0t - Test 1: Pass-through (AA, BB)", $time);
        ready_out = 1;
        valid_in = 1;
        data_in = 8'hAA;
        @(posedge clk); 
        #1;
        // At this edge, AA is latched into data_reg
        // data_out should now be AA
        // ready_in should still be 1 (because !valid_reg || ready_out)
        $display("Time: %0t - AA latched. data_out=%h, valid_out=%b", $time, data_out, valid_out);
        assert (data_out == 8'hAA) else $fatal(1, "FAIL: data_out not AA.");
        assert (valid_out) else $fatal(1, "FAIL: valid_out not 1.");
        assert (ready_in) else $fatal(1, "FAIL: ready_in did not stay 1.");
        
        // Send next data immediately
        data_in = 8'hBB;
        @(posedge clk);
        #1;
        // At this edge, BB is latched, replacing AA
        $display("Time: %0t - BB latched. data_out=%h, valid_out=%b", $time, data_out, valid_out);
        assert (data_out == 8'hBB) else $fatal(1, "FAIL: data_out not BB.");
        $display("--- Pass-through OK ---");

        // --- 3. Test Consumer Stall (Fill Buffer) ---
        $display("Time: %0t - Test 3: Consumer Stall (Attempt to send C1)", $time);
        ready_out = 0; // Stall the consumer
        valid_in  = 1; // Try to send C1
        data_in   = 8'hC1;
        
        @(posedge clk);
        #1; // Wait for non-blocking updates

        // At this edge, the buffer is FULL and STALLED.
        // It should *reject* C1 and *hold* the old value, BB.
        $display("Time: %0t - Buffer stalled. data_out=%h, valid_out=%b, ready_in=%b", $time, data_out, valid_out, ready_in);
        
        assert (data_out == 8'hBB) else $fatal(1, "FAIL: data_out should be BB (stalled).");
        assert (valid_out) else $fatal(1, "FAIL: valid_out should be 1 (stalled).");
        assert (!ready_in) else $fatal(1, "FAIL: ready_in did not go 0 on stall.");
        $display("--- Consumer Stall OK ---");

        // --- 4. Test Stall Release (Pass-through C1) ---
        // Now we un-stall the consumer, while still trying to send C1.
        // This should cause a 1-cycle "pass-through" where
        // BB is read out and C1 is read in simultaneously.
        $display("Time: %0t - Test 4: Stall Release (Drain BB, Latch C1)", $time);
        ready_out = 1; // Un-stall the consumer
        valid_in  = 1; // Keep trying to send C1
        data_in   = 8'hC1;
        
        // ready_in should *immediately* become 1 (combinational)
        #1;
        assert (ready_in) else $fatal(1, "FAIL: ready_in did not go 1 (combinational) on release.");

        @(posedge clk);
        #1; // Wait for non-blocking updates

        // At this edge, the consumer took BB, and the buffer latched C1.
        $display("Time: %0t - BB drained, C1 latched. data_out=%h", $time, data_out);
        assert (data_out == 8'hC1) else $fatal(1, "FAIL: data_out not C1 after stall release.");
        assert (valid_out) else $fatal(1, "FAIL: valid_out not 1.");
        $display("--- Stall Release + Latch OK ---");

        // --- 5. Test Drain Buffer ---
        $display("Time: %0t - Test 5: Drain Buffer (Send nothing)", $time);
        ready_out = 1; // Consumer is ready
        valid_in  = 0; // Producer sends nothing
        
        @(posedge clk);
        #1; // Wait for non-blocking updates
        
        // At this edge, the consumer took C1, and nothing new arrived.
        $display("Time: %0t - Buffer drained. valid_out=%b", $time, valid_out);
        assert (!valid_out) else $fatal(1, "FAIL: valid_out did not go 0 on drain.");
        assert (ready_in) else $fatal(1, "FAIL: ready_in is not 1 (empty).");
        $display("--- Buffer Drain OK ---");

        repeat(2) @(posedge clk);
        $display("--- All Tests Passed ---");
        $finish; // End simulation
    end
endmodule