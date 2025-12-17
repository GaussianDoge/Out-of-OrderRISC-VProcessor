`timescale 1ns / 1ps
import types_pkg::*;

module tb_rob_misprediction;

    // -------------------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------------------
    logic clk, reset;

    // Dispatch Inputs
    logic write_en;
    logic [6:0] pd_new_in;
    logic [6:0] pd_old_in;
    logic [31:0] pc_in;

    // FU Inputs
    logic fu_alu_done, fu_b_done, fu_mem_done;
    logic [4:0] rob_fu_alu, rob_fu_b, rob_fu_mem;
    logic [4:0] store_rob_tag;
    logic store_lsq_done;
    
    // Mispredict Inputs
    logic br_mispredict;
    logic [4:0] br_mispredict_tag;

    // Outputs
    logic [6:0] preg_old;
    logic valid_retired;
    logic [4:0] head;
    logic mispredict;
    logic [4:0] mispredict_tag_out;
    logic [4:0] ptr; // w_ptr
    logic full;

    // -------------------------------------------------------------------------
    // Instantiate DUT
    // -------------------------------------------------------------------------
    rob dut (
        .clk(clk),
        .reset(reset),
        .write_en(write_en),
        .pd_new_in(pd_new_in),
        .pd_old_in(pd_old_in),
        .pc_in(pc_in),
        .fu_alu_done(fu_alu_done),
        .fu_b_done(fu_b_done),
        .fu_mem_done(fu_mem_done),
        .rob_fu_alu(rob_fu_alu),
        .rob_fu_b(rob_fu_b),
        .rob_fu_mem(rob_fu_mem),
        .store_rob_tag(store_rob_tag),
        .store_lsq_done(store_lsq_done),
        .br_mispredict(br_mispredict),
        .br_mispredict_tag(br_mispredict_tag),
        .preg_old(preg_old),
        .valid_retired(valid_retired),
        .head(head),
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag_out),
        .ptr(ptr),
        .full(full)
    );

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------
    
    // 1. Dispatch (Add instruction to ROB)
    task dispatch(input [6:0] pd_new, input [6:0] pd_old, input [31:0] pc);
        wait(!full); // Wait if ROB is full
        @(negedge clk);
        write_en = 1;
        pd_new_in = pd_new;
        pd_old_in = pd_old;
        pc_in = pc;
        @(posedge clk);
        #1;
        write_en = 0;
    endtask

    // 2. Complete (Mark instruction as done)
    task complete_alu(input [4:0] tag);
        @(negedge clk);
        fu_alu_done = 1;
        rob_fu_alu = tag;
        @(posedge clk);
        #1;
        fu_alu_done = 0;
    endtask

    // 3. Trigger Mispredict
    task trigger_mispredict(input [4:0] tag);
        @(negedge clk);
        br_mispredict = 1;
        br_mispredict_tag = tag;
        @(posedge clk);
        #1;
        br_mispredict = 0;
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        // Init
        clk = 0;
        reset = 1;
        write_en = 0;
        fu_alu_done = 0; fu_b_done = 0; fu_mem_done = 0;
        store_lsq_done = 0;
        br_mispredict = 0;
        
        @(posedge clk);
        #1 reset = 0;
        
        $display("\n--- TEST START: ROB ---");

        // ------------------------------------------------------------
        // CASE 1: Basic Dispatch & In-Order Retirement
        // ------------------------------------------------------------
        $display("\n[Case 1] Dispatching Tags 0, 1, 2");
        dispatch(7'd10, 7'd1, 32'h100); // Tag 0
        dispatch(7'd11, 7'd2, 32'h104); // Tag 1
        dispatch(7'd12, 7'd3, 32'h108); // Tag 2
        
        // Check internal pointers (Peek inside DUT)
        if (dut.w_ptr !== 3) $error("FAIL: w_ptr should be 3, got %d", dut.w_ptr);

        $display("[Case 1] Completing Out-of-Order (Tag 2 finishes first)");
        complete_alu(5'd2);
        
        // Wait a cycle. Should NOT retire yet because Tag 0 is head.
        @(posedge clk);
        if (valid_retired) $error("FAIL: Tag 2 retired early! Head is Tag 0.");
        
        $display("[Case 1] Completing Tag 0");
        complete_alu(5'd0);
        
        // Next cycle, Tag 0 should retire automatically
        @(posedge clk); 
        #1; // Wait for logic updates
        if (valid_retired && head == 5'd0) 
            $display("PASS: Tag 0 Retired.");
        else 
            $error("FAIL: Tag 0 did not retire.");

        $display("[Case 1] Completing Tag 1");
        complete_alu(5'd1);
        
        // Next cycle, Tag 1 retires.
        // FOLLOWING cycle, Tag 2 (which was already done) should retire immediately.
        @(posedge clk); #1; // Tag 1 retires
        if (valid_retired && head == 5'd1) $display("PASS: Tag 1 Retired.");
        
        @(posedge clk); #1; // Tag 2 retires automatically
        if (valid_retired && head == 5'd2) $display("PASS: Tag 2 Retired (Auto).");


        // ------------------------------------------------------------
        // CASE 2: Misprediction & Flush
        // ------------------------------------------------------------
        $display("\n[Case 2] Setup: Dispatch Tags 3, 4, 5, 6");
        // Reset pointers logic check
        dispatch(7'd13, 7'd4, 32'h200); // Tag 3
        dispatch(7'd14, 7'd5, 32'h204); // Tag 4 (The Branch)
        dispatch(7'd15, 7'd6, 32'h208); // Tag 5 (Garbage)
        dispatch(7'd16, 7'd7, 32'h20C); // Tag 6 (Garbage)
        
        $display("[Case 2] Current w_ptr: %d (Expect 7)", dut.w_ptr);

        $display("[Case 2] Action: Mispredict at Tag 4");
        trigger_mispredict(5'd4);
        
        // Expected Result:
        // - w_ptr should move to Tag 4 + 1 = 5.
        // - Tags 5 and 6 should be invalidated.
        // - Tag 4 should remain valid (it is the branch itself).
        
        if (dut.w_ptr == 5'd5) 
            $display("PASS: w_ptr corrected to 5.");
        else 
            $error("FAIL: w_ptr is %d (Expected 5).", dut.w_ptr);

        if (dut.rob_table[5].valid == 0 && dut.rob_table[6].valid == 0)
            $display("PASS: Younger instructions flushed.");
        else
            $error("FAIL: Garbage instructions still valid.");
            

        // ------------------------------------------------------------
        // CASE 3: Wrap-Around Logic
        // ------------------------------------------------------------
        $display("\n[Case 3] Filling buffer to Wrap Around");
        
        // Current w_ptr is 5. Let's fill until it wraps past 15 to 0, 1...
        // We dispatch 12 instructions (5 + 12 = 17 -> wraps to index 1)
        for (int i=0; i<12; i++) begin
            dispatch(7'd20+i, 7'd0, 32'h300);
        end
        
        if (dut.w_ptr == 5'd1) 
            $display("PASS: w_ptr wrapped around correctly to 1.");
        else 
            $error("FAIL: w_ptr wrap failed, got %d", dut.w_ptr);
            
        if (full) 
            $display("PASS: Full signal asserted.");

        $display("\n--- TEST COMPLETE ---");
        $finish;
    end

endmodule