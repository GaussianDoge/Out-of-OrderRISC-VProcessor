`timescale 1ns / 1ps
import types_pkg::*;

module fu_mem_tb;

    // ---------------- Signals ----------------
    logic clk;
    logic reset;

    // Inputs to DUT
    logic        issued;
    logic [4:0]  curr_rob_tag;
    logic        mispredict;
    logic [4:0]  mispredict_tag;
    rs_data      data_in;
    logic [31:0] ps1_data;
    logic [31:0] ps2_data;   // unused but kept for interface

    // Outputs from DUT
    mem_data     data_out;

    // For checking results
    logic [31:0] expected_data;

    // ---------------- DUT ----------------
    fu_mem dut (
        .clk            (clk),
        .reset          (reset),

        .curr_rob_tag   (curr_rob_tag),
        .mispredict     (mispredict),
        .mispredict_tag (mispredict_tag),

        .issued         (issued),
        .data_in        (data_in),
        .ps1_data       (ps1_data),
        .ps2_data       (ps2_data),

        .data_out       (data_out)
    );

    // ---------------- Clock ----------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 10 ns period
    end

    // Safety Assertion: only LOAD opcodes should ever be issued
    always @(posedge clk) begin
        if (!reset) begin
            assert (!(issued && data_in.Opcode != 7'b0000011))
                else $error("Issued non-LOAD opcode to fu_mem at time %0t!", $time);
        end
    end

    // ---------------- Tasks ----------------

    // Synchronous reset
    task automatic do_reset();
        begin
            reset          = 1'b1;
            issued         = 1'b0;
            curr_rob_tag   = '0;
            mispredict     = 1'b0;
            mispredict_tag = '0;
            data_in        = '0;
            ps1_data       = '0;
            ps2_data       = '0;
            expected_data  = '0;

            repeat (3) @(posedge clk);
            reset = 1'b0;
            @(posedge clk);
        end
    endtask

    // Issue a single LOAD (LW/LBU) pulse
    task automatic issue_load(
        input  logic [2:0]  func3_in,   // 010 for LW, 100 for LBU
        input  logic [31:0] base_addr,
        input  logic [31:0] offset,
        input  logic [4:0]  rob_idx
    );
        begin
            @(posedge clk);
            // Fill rs_data
            data_in           = '0;
            data_in.Opcode    = 7'b0000011; // LOAD
            data_in.func3     = func3_in;
            data_in.imm       = offset;
            data_in.rob_index = rob_idx;

            ps1_data          = base_addr;
            ps2_data          = 32'd0;

            issued = 1'b1;
            @(posedge clk);      // 1-cycle issue pulse
            issued = 1'b0;
        end
    endtask

    // ---------------- Main Stimulus ----------------
    initial begin
        $dumpfile("fu_mem_waves.vcd");
        $dumpvars(0, fu_mem_tb);

        $display("=== Starting FU MEM Simulation ===");

        // 1. Reset
        do_reset();

        // ------------------------------------------------
        // TEST 1: LW at addr 0
        // ------------------------------------------------
        $display("\n[Test 1] LW at addr 0...");
        // data.mem assumed: [0..3] = 11 22 33 44  => 0x44332211
        curr_rob_tag = 5'd0;  // not used (no mispredict), but set anyway
        issue_load(3'b010, 32'h0000_0000, 32'h0, 5'd1);

        // Wait for fu_mem_done from FU (valid from BRAM)
        wait (data_out.fu_mem_done === 1'b1);
        #1;  // settle

        expected_data = 32'h4433_2211;
        if (data_out.data !== expected_data) begin
            $error("FAIL: LW got %h, expected %h", data_out.data, expected_data);
        end else begin
            $display("PASS: LW result = %h", data_out.data);
        end

        data_in  = '0;
        ps1_data = '0;
        @(posedge clk);

        // ------------------------------------------------
        // TEST 2: LBU at addr 1
        // ------------------------------------------------
        $display("\n[Test 2] LBU at addr 1...");
        // data_mem[1] = 0x22 -> 0x00000022
        curr_rob_tag = 5'd0;
        issue_load(3'b100, 32'h0000_0000, 32'h1, 5'd2);

        wait (data_out.fu_mem_done === 1'b1);
        #1;

        expected_data = 32'h0000_0022;
        if (data_out.data !== expected_data) begin
            $error("FAIL: LBU got %h, expected %h", data_out.data, expected_data);
        end else begin
            $display("PASS: LBU result = %h", data_out.data);
        end

        data_in  = '0;
        ps1_data = '0;
        @(posedge clk);

        // ------------------------------------------------
        // TEST 3: Misprediction flush while load in-flight
        // ------------------------------------------------
        $display("\n[Test 3] Mispredict flush (in-flight)...");

        // Issue a load with ROB index = 5
        @(posedge clk);
        data_in           = '0;
        data_in.Opcode    = 7'b0000011;
        data_in.func3     = 3'b010;
        data_in.imm       = 32'h0;
        data_in.rob_index = 5'd5;
        ps1_data          = 32'h0000_0000;

        issued = 1'b1;
        @(posedge clk);
        issued = 1'b0;

        // Configure ROB window: mispredict at 3, tail at 8 => younger 4,5,6,7.
        mispredict_tag = 5'd3;
        curr_rob_tag   = 5'd8;
        mispredict     = 1'b1;

        // Hold mispredict across likely memory-latency window
        repeat (4) @(posedge clk);
        mispredict = 1'b0;

        // Give one cycle for combinational fu_mem to settle after mispredict goes low
        @(posedge clk);

        if (data_out.fu_mem_done === 1'b0 && data_out.data === 32'd0) begin
            $display("PASS: Mispredict flush cleared FU MEM outputs.");
        end else begin
            $error("FAIL: Mispredict flush: fu_mem_done=%b, data=%h",
                   data_out.fu_mem_done, data_out.data);
        end

        data_in  = '0;
        ps1_data = '0;
        @(posedge clk);

        // ------------------------------------------------
        // TEST 4: Back-to-back loads (LW then LBU)
        // ------------------------------------------------
        $display("\n[Test 4] Back-to-back loads...");

        // First LW @0
        curr_rob_tag = 5'd3;
        issue_load(3'b010, 32'h0000_0000, 32'h0, 5'd3);
        wait (data_out.fu_mem_done === 1'b1);
        #1;

        expected_data = 32'h4433_2211;
        if (data_out.data !== expected_data) begin
            $error("FAIL: Back-to-back LW got %h, expected %h",
                   data_out.data, expected_data);
        end else begin
            $display("PASS: Back-to-back LW result = %h", data_out.data);
        end

        // Immediately a second load: LBU @1
        issue_load(3'b100, 32'h0000_0000, 32'h1, 5'd4);
        wait (data_out.fu_mem_done === 1'b1);
        #1;

        expected_data = 32'h0000_0022;
        if (data_out.data !== expected_data) begin
            $error("FAIL: Back-to-back LBU got %h, expected %h",
                   data_out.data, expected_data);
        end else begin
            $display("PASS: Back-to-back LBU result = %h", data_out.data);
        end

        // End Simulation
        $display("\n=== Simulation Complete ===");
        #50;
        $finish;
    end

    // Monitor 
    initial begin
        $monitor("[%0t] issued=%0b mispredict=%0b fu_mem_ready=%0b fu_mem_done=%0b addr=0x%08h data=0x%08h",
                 $time,
                 issued,
                 mispredict,
                 data_out.fu_mem_ready,
                 data_out.fu_mem_done,
                 dut.addr,           // internal addr inside fu_mem
                 data_out.data);
    end

endmodule
