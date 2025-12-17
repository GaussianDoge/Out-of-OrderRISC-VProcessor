`timescale 1ns / 1ps
import types_pkg::*;

module tb_rs_bu;

    // -------------------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------------------
    logic clk;
    logic reset;
    
    // Dispatch Interface
    logic valid_in;
    dispatch_pipeline_data instr;
    logic ready_in; // output from DUT
    
    // Execution Interface
    logic fu_rdy;
    logic valid_out; // output from DUT
    rs_data data_out; // output from DUT
    
    // CDB Interface
    logic [6:0] reg1_rdy, reg2_rdy, reg3_rdy;
    logic reg1_rdy_valid, reg2_rdy_valid, reg3_rdy_valid;
    
    // Recovery
    logic flush;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    rs_bu DUT (
        .clk(clk),
        .reset(reset),
        .fu_rdy(fu_rdy),
        .valid_in(valid_in),
        .instr(instr),
        .ready_in(ready_in),
        .valid_out(valid_out),
        .data_out(data_out),
        .reg1_rdy(reg1_rdy),
        .reg2_rdy(reg2_rdy),
        .reg3_rdy(reg3_rdy),
        .reg1_rdy_valid(reg1_rdy_valid),
        .reg2_rdy_valid(reg2_rdy_valid),
        .reg3_rdy_valid(reg3_rdy_valid),
        .flush(flush)
    );

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------
    
    // Task to dispatch a branch instruction
    task dispatch_branch(
        input [31:0] pc,
        input [6:0] pd,
        input [6:0] ps1, input logic ps1_ready,
        input [6:0] ps2, input logic ps2_ready,
        input [3:0] rob_idx
    );
        begin
            wait(clk == 0); // Synchronize
            valid_in = 1;
            instr.pc = pc;
            instr.Opcode = 7'b1100011; // BEQ
            instr.prd = pd;
            instr.pr1 = ps1;
            instr.pr1_ready = ps1_ready;
            instr.pr2 = ps2;
            instr.pr2_ready = ps2_ready;
            instr.rob_index = rob_idx;
            // Defaults for others
            instr.imm = 32'd4;
            instr.func3 = 3'b0;
            instr.func7 = 7'b0;
            
            @(posedge clk);
            #1; // Hold time
            valid_in = 0;
        end
    endtask

    // Task to broadcast a result on CDB (Wakeup)
    task cdb_broadcast(input [6:0] tag);
        begin
            wait(clk == 0);
            reg1_rdy_valid = 1;
            reg1_rdy = tag;
            @(posedge clk);
            #1;
            reg1_rdy_valid = 0;
            reg1_rdy = 0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        // Initialize Inputs
        reset = 1;
        valid_in = 0;
        instr = '0;
        fu_rdy = 0;
        reg1_rdy = 0; reg2_rdy = 0; reg3_rdy = 0;
        reg1_rdy_valid = 0; reg2_rdy_valid = 0; reg3_rdy_valid = 0;
        flush = 0;

        // Reset Pulse
        #20 reset = 0;
        #10;

        $display("=== TEST 1: Basic Dispatch & Issue (No Stalls) ===");
        // Dispatch Instr 1: Ready immediately (ps1=10, ps2=11 both ready)
        dispatch_branch(32'h100, 7'd5, 7'd10, 1'b1, 7'd11, 1'b1, 4'd1);
        
        #1;
        if (valid_out && data_out.pc == 32'h100) $display("PASS: Head is valid immediately");
        else $error("FAIL: Head should be valid");

        // Execute it
        fu_rdy = 1;
        @(posedge clk); 
        #1;
        fu_rdy = 0;
        
        if (!valid_out) $display("PASS: FIFO Empty after issue");
        else $error("FAIL: FIFO should be empty");

        
        $display("\n=== TEST 2: Dependency Stall & Snooping ===");
        // Dispatch Instr 2: Depends on P20 (Not ready)
        dispatch_branch(32'h200, 7'd6, 7'd20, 1'b0, 7'd21, 1'b1, 4'd2);
        
        #1;
        if (!valid_out) $display("PASS: Stalled waiting for P20");
        else $error("FAIL: Should not be valid yet");

        // Broadcast P20 on CDB
        $display("Broadcasting P20...");
        cdb_broadcast(7'd20);
        
        #1;
        if (valid_out && data_out.pc == 32'h200) $display("PASS: Woke up and valid after CDB broadcast");
        else $error("FAIL: Did not wake up");
        
        // Clear from FIFO
        fu_rdy = 1;
        @(posedge clk);
        #1;
        fu_rdy = 0;


        $display("\n=== TEST 3: FIFO Ordering (In-Order Issue) ===");
        // Dispatch Instr A (Ready)
        dispatch_branch(32'hAAA, 7'd1, 7'd0, 1'b1, 7'd0, 1'b1, 4'd3);
        // Dispatch Instr B (Ready)
        dispatch_branch(32'hBBB, 7'd2, 7'd0, 1'b1, 7'd0, 1'b1, 4'd4);

        #1;
        if (data_out.pc == 32'hAAA) $display("PASS: Instr A is at Head");
        else $error("FAIL: Wrong Head");

        // Issue A
        fu_rdy = 1;
        @(posedge clk);
        #1;
        // Issue B
        if (data_out.pc == 32'hBBB) $display("PASS: Instr B is at Head now");
        else $error("FAIL: Wrong Head after A issued");
        
        @(posedge clk);
        fu_rdy = 0;
        #1;


        $display("\n=== TEST 4: Forwarding (Dispatch + CDB same cycle) ===");
        // Setup: Dispatch Instr that needs P30 (not ready), but P30 arrives NOW on CDB
        wait(clk == 0);
        valid_in = 1;
        instr.pc = 32'h400;
        instr.pr1 = 7'd30;
        instr.pr1_ready = 0; // "Not ready" in rename
        instr.pr2_ready = 1;
        
        reg1_rdy_valid = 1;  // But CDB says "Here is P30!"
        reg1_rdy = 7'd30;
        
        @(posedge clk);
        valid_in = 0;
        reg1_rdy_valid = 0;
        #1;
        
        if (valid_out && data_out.ps1_ready == 1) $display("PASS: Forwarding caught the dependency");
        else $error("FAIL: Failed to catch simultaneous wakeup");
        
        // Clear FIFO
        fu_rdy = 1; @(posedge clk); fu_rdy = 0; 


        $display("\n=== TEST 5: Full Flag & Flush ===");
        // Fill FIFO (Depth 8)
        for (int i=0; i<8; i++) begin
            dispatch_branch(32'h500+i, 7'd0, 7'd0, 1'b1, 7'd0, 1'b1, i[3:0]);
        end
        
        #1;
        // Verify it is full before flushing
        if (ready_in == 0) $display("PASS: Ready_in Low (Full)");
        else $error("FAIL: Should be full. Count is %d", DUT.count);

        // --- FLUSH SEQUENCE (FIXED) ---
        $display("Asserting Flush...");
        
        wait(clk == 0); 
        flush = 1;      // Set flush high
        
        @(posedge clk); // Wait for the active edge
        #1;             // <--- CRITICAL DELAY: Hold flush past the edge
        
        flush = 0;      // Now it's safe to drop it
        
        #1; // Wait for combinational logic (ready_in) to settle
        
        // Debug output to help you see what happened
        $display("Status after flush -> Ready_in: %b, Count: %d, Valid_out: %b", 
                 ready_in, DUT.count, valid_out);

        if (ready_in == 1 && valid_out == 0) 
            $display("PASS: Empty after flush");
        else 
            $error("FAIL: Flush failed.");

        $display("\n=== ALL TESTS COMPLETE ===");
        $finish;
    end

endmodule