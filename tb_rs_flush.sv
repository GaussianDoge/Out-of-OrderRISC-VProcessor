`timescale 1ns / 1ps
import types_pkg::*;

module tb_rs_flush;

    // Signals
    logic clk, reset;
    logic fu_rdy;
    
    // Upstream (Dispatch)
    logic valid_in;
    logic ready_in;
    dispatch_pipeline_data instr;
    
    // Downstream (Issue)
    logic valid_out;
    rs_data data_out;
    
    // CDB (Just tied to 0 for this test)
    logic [6:0] reg1_rdy, reg2_rdy, reg3_rdy;
    logic reg1_rdy_valid, reg2_rdy_valid, reg3_rdy_valid;
    
    // Recover
    logic flush;
    logic [4:0] flush_tag;

    // Instantiate MUT
    rs dut (
        .clk(clk),
        .reset(reset),
        .fu_rdy(fu_rdy),
        .valid_in(valid_in),
        .ready_in(ready_in),
        .instr(instr),
        .valid_out(valid_out),
        .data_out(data_out),
        .reg1_rdy(reg1_rdy), .reg2_rdy(reg2_rdy), .reg3_rdy(reg3_rdy),
        .reg1_rdy_valid(reg1_rdy_valid), .reg2_rdy_valid(reg2_rdy_valid), .reg3_rdy_valid(reg3_rdy_valid),
        .flush(flush),
        .flush_tag(flush_tag)
    );

    // Clock Gen
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Helper Task: Dispatch an Instruction
    // -------------------------------------------------------------------------
    task dispatch_instr(input [4:0] rob_tag);
        // Wait until RS is ready
        wait(ready_in);
        @(negedge clk);
        
        valid_in = 1'b1;
        instr.rob_index = rob_tag;
        // Dummy values for other fields
        instr.Opcode = 7'h13; 
        instr.prd = 5'd1;
        instr.pr1_ready = 1'b0; // Not ready (so it stays in RS)
        instr.pr2_ready = 1'b0;
        
        @(posedge clk);
        #1; // Hold time
        valid_in = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Test Sequence
    // -------------------------------------------------------------------------
    
    // Variables for verification must be declared at the top of the block
    // or inside a named scope to satisfy Vivado.
    logic found_tag_2, found_tag_5, found_tag_7;
    logic found_tag_13, found_tag_14, found_tag_1;

    initial begin
        // 1. Initialization
        clk = 0;
        reset = 1;
        valid_in = 0;
        fu_rdy = 1; // ALUs are ready
        flush = 0;
        flush_tag = 0;
        
        // Tie off CDB
        reg1_rdy = 0; reg2_rdy = 0; reg3_rdy = 0;
        reg1_rdy_valid = 0; reg2_rdy_valid = 0; reg3_rdy_valid = 0;

        // Reset Pulse
        @(posedge clk);
        #1 reset = 0;
        
        $display("\n--- TEST START: RS Misprediction Logic ---");

        // ------------------------------------------------------------
        // CASE 1: Normal Flush (No Wrap)
        // ------------------------------------------------------------
        $display("\n[Case 1] Setup: Dispatching Tags 2, 5, 7");
        dispatch_instr(5'd2);
        dispatch_instr(5'd5);
        dispatch_instr(5'd7);
        
        // Wait a cycle to settle
        @(posedge clk); 

        $display("[Case 1] Action: Flush at Tag 5 (Kill > 5)");
        @(negedge clk);
        flush = 1;
        flush_tag = 5'd5;
        @(posedge clk);
        #1 flush = 0;

        // --- VERIFY CASE 1 ---
        // Search the table for the tags
        found_tag_2 = 0; found_tag_5 = 0; found_tag_7 = 0;

        for (int i = 0; i < 8; i++) begin
            if (dut.rs_table[i].valid == 1'b0) begin // 0 means OCCUPIED
                if (dut.rs_table[i].rob_index == 5'd2) found_tag_2 = 1;
                if (dut.rs_table[i].rob_index == 5'd5) found_tag_5 = 1;
                if (dut.rs_table[i].rob_index == 5'd7) found_tag_7 = 1;
            end
        end

        if (found_tag_2) $display("PASS: Tag 2 (Older) Survived.");
        else $error("FAIL: Tag 2 was killed or lost.");

        if (found_tag_5) $display("PASS: Tag 5 (The Branch) Survived.");
        else $error("FAIL: Tag 5 was killed.");

        if (found_tag_7) $error("FAIL: Tag 7 Survived (Should be flushed).");
        else $display("PASS: Tag 7 (Younger) was correctly Killed.");

        
        // ------------------------------------------------------------
        // RESET FOR NEXT CASE
        // ------------------------------------------------------------
        reset = 1; @(posedge clk); #1 reset = 0;


        // ------------------------------------------------------------
        // CASE 2: Wrap-Around Flush
        // ------------------------------------------------------------
        $display("\n[Case 2] Setup: Dispatching Tags 13, 14, 1 (Wrap)");
        dispatch_instr(5'd13);
        dispatch_instr(5'd14);
        dispatch_instr(5'd1);

        $display("[Case 2] Action: Flush at Tag 14");
        @(negedge clk);
        flush = 1;
        flush_tag = 5'd14;
        @(posedge clk);
        #1 flush = 0;

        // --- VERIFY CASE 2 ---
        found_tag_13 = 0; found_tag_14 = 0; found_tag_1 = 0;

        for (int i = 0; i < 8; i++) begin
            if (dut.rs_table[i].valid == 1'b0) begin // 0 means OCCUPIED
                if (dut.rs_table[i].rob_index == 5'd13) found_tag_13 = 1;
                if (dut.rs_table[i].rob_index == 5'd14) found_tag_14 = 1;
                if (dut.rs_table[i].rob_index == 5'd1)  found_tag_1 = 1;
            end
        end

        if (found_tag_13) $display("PASS: Tag 13 (Older) Survived.");
        else $error("FAIL: Tag 13 killed.");

        if (found_tag_14) $display("PASS: Tag 14 (Branch) Survived.");
        else $error("FAIL: Tag 14 killed.");

        if (found_tag_1) $error("FAIL: Tag 1 Survived (Should be flushed).");
        else $display("PASS: Tag 1 (Wrapped Younger) was correctly Killed.");


        // ------------------------------------------------------------
        // CASE 3: Flush an Instruction that is currently Issuing
        // ------------------------------------------------------------
        reset = 1; @(posedge clk); #1 reset = 0;
        
        $display("\n[Case 3] Setup: Instruction Ready to Issue but needs Flush");
        
        wait(ready_in);
        @(negedge clk);
        valid_in = 1;
        instr.rob_index = 5'd8;
        instr.pr1_ready = 1'b1; 
        instr.pr2_ready = 1'b1; 
        @(posedge clk);
        valid_in = 0;
        
        $display("[Case 3] Action: Flush Tag 5 while Tag 8 issues");
        @(negedge clk);
        flush = 1;
        flush_tag = 5'd5;
        @(posedge clk); 
        #1 flush = 0;
        
        if (valid_out == 1'b0)
            $display("PASS: valid_out was squashed during flush.");
        else
            $error("FAIL: valid_out went high! Bad instruction leaked to ALU.");

        $display("\n--- TEST COMPLETE ---");
        $finish;
    end

endmodule