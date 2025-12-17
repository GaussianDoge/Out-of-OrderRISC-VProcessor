`timescale 1ns / 1ps
import types_pkg::*;

module tb_checkpoint;

    // Signals
    logic clk;
    logic reset;

    // Save Interface
    logic branch_detect;
    logic [31:0] branch_pc;
    logic [4:0] branch_rob_tag;
    logic [127:0] reg_rdy_snap_shot;

    // Restore Interface
    logic mispredict;
    logic [4:0] mispredict_tag;

    // Outputs
    logic checkpoint_valid;
    checkpoint snapshot;

    // Instantiate DUT
    checkpoint dut (
        .clk(clk),
        .reset(reset),
        .branch_detect(branch_detect),
        .branch_pc(branch_pc),
        .branch_rob_tag(branch_rob_tag),
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        .reg_rdy_snap_shot(reg_rdy_snap_shot),
        .checkpoint_valid(checkpoint_valid),
        .snapshot(snapshot)
    );

    // Clock Gen
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------
    
    // Save a Snapshot
    task save_branch(input [4:0] tag, input [127:0] state);
        @(negedge clk);
        branch_detect = 1;
        branch_rob_tag = tag;
        reg_rdy_snap_shot = state;
        branch_pc = 32'h1000 + {27'b0, tag}; // Dummy PC
        @(posedge clk);
        #1;
        branch_detect = 0;
    endtask

    // Trigger Mispredict
    task trigger_mispredict(input [4:0] tag);
        @(negedge clk);
        mispredict = 1;
        mispredict_tag = tag;
        @(posedge clk);
        #1; // Wait for combinational output to settle
    endtask

    // Stop Mispredict signal
    task clear_mispredict;
        mispredict = 0;
        mispredict_tag = 0;
        @(negedge clk);
    endtask

    // -------------------------------------------------------------------------
    // Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        // Init
        clk = 0;
        reset = 1;
        branch_detect = 0;
        branch_pc = 0;
        branch_rob_tag = 0;
        mispredict = 0;
        mispredict_tag = 0;
        reg_rdy_snap_shot = 0;

        @(posedge clk);
        #1 reset = 0;

        $display("\n--- TEST START: Checkpoint Unit ---");

        // ------------------------------------------------------------
        // CASE 1: Save 3 distinct branches
        // ------------------------------------------------------------
        $display("\n[Case 1] Saving 3 Snapshots");
        
        // Branch A (Tag 10): State = All 1s
        save_branch(5'd10, {128{1'b1}}); 
        
        // Branch B (Tag 11): State = Alternating 1010...
        save_branch(5'd11, {64{2'b10}}); 
        
        // Branch C (Tag 12): State = All 0s
        save_branch(5'd12, {128{1'b0}});

        // Verify internal state (Peek inside DUT buffer)
        // Note: Assuming logic fills 0 -> 1 -> 2
        if (dut.chkpt[0].valid && dut.chkpt[0].rob_tag == 5'd10) $display("PASS: Branch A saved in slot 0");
        else $error("FAIL: Branch A not found.");
        
        if (dut.chkpt[1].valid && dut.chkpt[1].rob_tag == 5'd11) $display("PASS: Branch B saved in slot 1");
        else $error("FAIL: Branch B not found.");


        // ------------------------------------------------------------
        // CASE 2: Restore Branch B (Middle of buffer)
        // ------------------------------------------------------------
        $display("\n[Case 2] Trigger Mispredict for Tag 11 (Branch B)");
        
        trigger_mispredict(5'd11);
        
        if (checkpoint_valid == 1'b1) 
            $display("PASS: checkpoint_valid asserted.");
        else 
            $error("FAIL: checkpoint_valid is LOW.");

        if (snapshot.reg_rdy_table === {64{2'b10}}) 
            $display("PASS: Restored correct state (1010...).");
        else 
            $error("FAIL: Data mismatch. Expected 1010..., Got %h", snapshot.reg_rdy_table);

        clear_mispredict();


        // ------------------------------------------------------------
        // CASE 3: Restore Branch A (Oldest)
        // ------------------------------------------------------------
        $display("\n[Case 3] Trigger Mispredict for Tag 10 (Branch A)");
        
        trigger_mispredict(5'd10);
        
        if (snapshot.reg_rdy_table === {128{1'b1}}) 
            $display("PASS: Restored correct state (All 1s).");
        else 
            $error("FAIL: Data mismatch for Tag 10.");

        clear_mispredict();


        // ------------------------------------------------------------
        // CASE 4: Trigger Mispredict for unknown tag
        // ------------------------------------------------------------
        $display("\n[Case 4] Trigger Mispredict for Tag 99 (Non-existent)");
        
        trigger_mispredict(5'd20);
        
        if (checkpoint_valid == 1'b0) 
            $display("PASS: checkpoint_valid is 0 (Correctly ignored).");
        else 
            $error("FAIL: checkpoint_valid asserted for unknown tag!");

        clear_mispredict();

        $display("\n--- TEST COMPLETE ---");
        $finish;
    end

endmodule