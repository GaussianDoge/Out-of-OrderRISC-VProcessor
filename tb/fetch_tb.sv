`timescale 1ns / 1ps

//******************************************************************
// 1. The Testbench
//******************************************************************
module fetch_tb;

    // --- Clock ---
    parameter CLK_PERIOD = 10; // 10ns = 100MHz

    // --- DUT Signals ---
    logic clk;
    logic reset;
    
    // Inputs to fetch
    logic [31:0] PC_in;
    logic        ready_out; // From Decode
    
    // Outputs from fetch
    logic [31:0] instr_out;
    logic [31:0] PC_out;
    logic [31:0] PC_4;
    logic        valid_out;

    // --- Instantiate the Device Under Test (DUT) ---
    fetch dut (
        .clk(clk),
        .reset(reset),
        .pc_in(PC_in),
        .ready_out(ready_out),
        .instr_out(instr_out),
        .pc_out(PC_out),
        .pc_4(PC_4),
        .valid_out(valid_out)
    );

    // --- Clock Generator ---
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // --- Waveform Dump ---
    initial begin
        $dumpfile("fetch_waves.vcd");
        $dumpvars(0, fetch_tb);
    end

    // --- Test Stimulus ---
    initial begin
        $display("--- Simulation Start (Original Fetch) ---");
        
        // --- 1. Reset ---
        reset = 1;
        PC_in = 'x;
        ready_out = 0;
        @(posedge clk);
        @(posedge clk);
        reset = 0;
        $display("Time: %0t - Reset released.", $time);
        
        @(posedge clk);
        #1; // Allow combinational logic to settle
        assert (!valid_out) else $fatal(1, "FAIL: valid_out is high after reset.");

        // --- 2. Test Pass-through (Full Speed) ---
        $display("Time: %0t - Test 1: Pass-through (PC=0, 4)", $time);
        ready_out = 1; // Decode stage is ready
        PC_in = 32'd0;
        
        @(posedge clk);
        #1;
        $display("Time: %0t - PC_out=%h, instr_out=%h, valid_out=%b", $time, PC_out, instr_out, valid_out);
        assert (valid_out) else $fatal(1, "FAIL: valid_out did not go high.");
        assert (PC_out == 32'd0) else $fatal(1, "FAIL: PC_out is not 0.");
        // ICache is combinational, so instr_out should be valid
        assert (instr_out !== 32'hxxxxxxxx) else $fatal(1, "FAIL: instr_out is X.");

        // Send next PC
        PC_in = 32'd4;
        @(posedge clk);
        #1;
        $display("Time: %0t - PC_out=%h, instr_out=%h, valid_out=%b", $time, PC_out, instr_out, valid_out);
        assert (PC_out == 32'd4) else $fatal(1, "FAIL: PC_out is not 4.");
        $display("--- Pass-through OK ---");
        
        // --- 3. Test Stall ---
        $display("Time: %0t - Test 2: Consumer Stall (PC_in=8)", $time);
        ready_out = 0; // Stall the Decode stage
        PC_in = 32'd8; // Try to send PC=8
        
        @(posedge clk);
        #1;
        // The buffer should STALL. It should hold its OLD value (PC=4)
        $display("Time: %0t - Stalled. PC_out=%h, instr_out=%h, valid_out=%b", $time, PC_out, instr_out, valid_out);
        assert (PC_out == 32'd4) else $fatal(1, "FAIL: PC_out did not stall at 4.");
        $display("--- Stall OK ---");
        
        repeat(2) @(posedge clk);
        $display("--- All Tests Passed ---");
        $finish;
    end
endmodule