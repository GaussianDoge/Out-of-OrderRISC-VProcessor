`timescale 1ns / 1ps
import types_pkg::*;

module dispatch_tb;

    // =================================================================
    // Signals & Constants
    // =================================================================
    parameter CLK_PERIOD = 10;

    logic clk;
    logic reset;

    // Upstream (Rename)
    logic       valid_in;
    rename_data data_in;
    logic       ready_in; // Output from DUT

    // Downstream (ALU)
    logic       alu_rs_valid_out;
    rs_data     alu_rs_data_out;
    logic       alu_rs_ready_in;

    // Downstream (Branch)
    logic       br_rs_valid_out;
    rs_data     br_rs_data_out;
    logic       br_rs_ready_in;

    // Downstream (LSU)
    logic       lsu_rs_valid_out;
    rs_data     lsu_rs_data_out;
    logic       lsu_rs_ready_in;

    // PRF Interface
    logic [6:0] dispatch_nr_reg;
    logic       dispatch_nr_valid;

    // CDB Broadcast (Inputs)
    logic [6:0] preg1_rdy;
    logic [6:0] preg2_rdy;
    logic [6:0] preg3_rdy;
    logic       preg1_valid;
    logic       preg2_valid;
    logic       preg3_valid;

    // ROB Interface
    logic       complete_in;
    logic [4:0] rob_fu_tag;
    logic       mispredict;
    logic [4:0] mispredict_tag;
    
    logic [4:0] rob_retire_tag;
    logic       rob_retire_valid;

    // =================================================================
    // DUT Instantiation
    // =================================================================
    dispatch dut (
        .clk(clk),
        .reset(reset),

        // Upstream
        .valid_in(valid_in),
        .data_in(data_in),
        .ready_in(ready_in),

        // Downstream
        .alu_rs_valid_out(alu_rs_valid_out),
        .alu_rs_data_out(alu_rs_data_out),
        .alu_rs_ready_in(alu_rs_ready_in),

        .br_rs_valid_out(br_rs_valid_out),
        .br_rs_data_out(br_rs_data_out),
        .br_rs_ready_in(br_rs_ready_in),

        .lsu_rs_valid_out(lsu_rs_valid_out),
        .lsu_rs_data_out(lsu_rs_data_out),
        .lsu_rs_ready_in(lsu_rs_ready_in),

        // PRF
        .dispatch_nr_reg(dispatch_nr_reg),
        .dispatch_nr_valid(dispatch_nr_valid),

        // CDB
        .preg1_rdy(preg1_rdy), .preg2_rdy(preg2_rdy), .preg3_rdy(preg3_rdy),
        .preg1_valid(preg1_valid), .preg2_valid(preg2_valid), .preg3_valid(preg3_valid),

        // ROB
        .complete_in(complete_in),
        .rob_fu_tag(rob_fu_tag),
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        .rob_retire_tag(rob_retire_tag),
        .rob_retire_valid(rob_retire_valid)
    );

    // =================================================================
    // Clock Generation
    // =================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // =================================================================
    // Helper Tasks
    // =================================================================
    
    task reset_system;
        begin
            reset = 1;
            valid_in = 0;
            data_in = '0;
            
            // Execution Units are ready by default
            alu_rs_ready_in = 1;
            br_rs_ready_in = 1;
            lsu_rs_ready_in = 1;
            
            // No CDB broadcasts
            preg1_valid = 0; preg2_valid = 0; preg3_valid = 0;
            preg1_rdy = 0;   preg2_rdy = 0;   preg3_rdy = 0;
            
            // No ROB completion
            complete_in = 0;
            rob_fu_tag = 0;
            mispredict = 0;
            
            @(posedge clk);
            @(posedge clk);
            reset = 0;
            @(posedge clk); // Wait for reset to clear
        end
    endtask

    task send_alu_instr(input [4:0] tag, input [6:0] pd, input [6:0] p1, input [6:0] p2);
        begin
            // Wait for ready_in
            while (!ready_in) @(posedge clk);
            
            valid_in = 1;
            data_in.fu_alu = 1;
            data_in.fu_mem = 0;
            data_in.fu_br  = 0;
            data_in.Opcode = 7'b0110011; // R-Type ADD
            data_in.rob_tag = tag;
            data_in.pd_new = pd;
            data_in.ps1 = p1;
            data_in.ps2 = p2;
            data_in.imm = '0;
            
            @(posedge clk);
            valid_in = 0; // Pulse valid for 1 cycle
            // Clear data to avoid confusion in waves
            // data_in = '0; 
        end
    endtask

    task send_lsu_instr(input [4:0] tag, input [6:0] pd, input [6:0] p1);
        begin
            while (!ready_in) @(posedge clk);
            valid_in = 1;
            data_in.fu_alu = 0;
            data_in.fu_mem = 1; // LSU
            data_in.fu_br  = 0;
            data_in.Opcode = 7'b0000011; // Load
            data_in.rob_tag = tag;
            data_in.pd_new = pd;
            data_in.ps1 = p1;
            data_in.ps2 = 0;
            @(posedge clk);
            valid_in = 0;
        end
    endtask

    task broadcast_cdb(input [6:0] tag);
        begin
            // Pulse CDB for 1 cycle to simulate writeback
            preg1_valid = 1;
            preg1_rdy = tag;
            @(posedge clk);
            preg1_valid = 0;
            preg1_rdy = 0;
        end
    endtask

    // =================================================================
    // Main Test Process
    // =================================================================
    initial begin
        $dumpfile("dispatch_waves.vcd");
        $dumpvars(0, dispatch_tb);
        
        $display("=== Simulation Start ===");
        reset_system();

        // -----------------------------------------------------------
        // Test Case 1: Dispatch ALU Instruction (Stuck in RS)
        // -----------------------------------------------------------
        // Send: ADD p10, p1, p2 (Tag #1)
        // Expect: 
        // 1. Rename -> Skid Buffer (Cycle 1)
        // 2. Skid Buffer -> ALU RS (Cycle 2)
        // 3. RS waits because p1/p2 are not ready (default 0)
        $display("[T=%0t] Test 1: Dispatch ALU Instr (Wait for operands)", $time);
        
        send_alu_instr(5'd1, 7'd10, 7'd1, 7'd2);
        
        // Wait a few cycles to ensure it landed in RS but didn't issue
        repeat(2) @(posedge clk);
        
        if (dispatch_nr_valid && dispatch_nr_reg == 7'd10) 
            $display("PASS: Dispatch marked p10 as busy.");
        else 
            $error("FAIL: Dispatch did not mark destination busy.");

        if (alu_rs_valid_out == 0) 
            $display("PASS: ALU RS did not issue (operands not ready).");
        else 
            $error("FAIL: ALU RS issued prematurely!");


        // -----------------------------------------------------------
        // Test Case 2: Wakeup & Issue
        // -----------------------------------------------------------
        // Broadcast p1 and p2 on CDB.
        // Expect: ALU RS issues the instruction.
        $display("[T=%0t] Test 2: Broadcast Wakeup", $time);
        
        // Broadcast p1
        preg1_valid = 1; preg1_rdy = 7'd1;
        // Broadcast p2 on second port
        preg2_valid = 1; preg2_rdy = 7'd2;
        
        @(posedge clk);
        preg1_valid = 0; preg2_valid = 0;

        // Wait for RS to react (combinational + sequential)
        @(posedge clk); 
        
        if (alu_rs_valid_out == 1 && alu_rs_data_out.rob_index == 4'd1)
            $display("PASS: ALU RS Issued instruction #1.");
        else
            $error("FAIL: ALU RS did not issue after wakeup.");


        // -----------------------------------------------------------
        // Test Case 3: Dispatch LSU Instruction
        // -----------------------------------------------------------
        $display("[T=%0t] Test 3: Dispatch LSU Instr", $time);
        send_lsu_instr(5'd2, 7'd11, 7'd3);
        
        repeat(2) @(posedge clk);
        
        // Wake it up immediately
        broadcast_cdb(7'd3);
        
        @(posedge clk);
        if (lsu_rs_valid_out == 1)
            $display("PASS: LSU RS Issued instruction #2.");
        else
            $error("FAIL: LSU RS did not issue.");

        // -----------------------------------------------------------
        // Test Case 4: Fill RS & Verify Rename Stall
        // -----------------------------------------------------------
        // ALU RS size is 8. We send 9 ALU instructions.
        // The 9th should stall 'ready_in'.
        $display("[T=%0t] Test 4: Stall Logic (Fill ALU RS)", $time);
        
        // Note: Instruction #1 is gone (issued). So RS has 0 ALU instrs.
        // We need to send instructions that WON'T issue (dependencies not met).
        // Send instructions dependent on p99 (which we won't broadcast)
        
        for (int i = 0; i < 8; i++) begin
            // Tag i+10, Dest i+20, Src p99, p99
            send_alu_instr(5'(i+10), 7'(i+20), 7'd99, 7'd99);
        end
        
        // Wait for buffer to drain into RS
        @(posedge clk);
        
        // Now RS should be full (8 entries).
        // Try to send 9th
        valid_in = 1;
        data_in.fu_alu = 1; // Targeting FULL RS
        data_in.rob_tag = 5'd30;
        
        #1; // Wait for combinational logic
        if (ready_in == 0)
            $display("PASS: Dispatch correctly stalled Rename (ALU RS Full).");
        else
            $error("FAIL: ready_in is 1, but RS should be full.");
            
        valid_in = 0; // Stop trying

        $display("=== Simulation End ===");
        $finish;
    end

endmodule