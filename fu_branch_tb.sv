`timescale 1ns / 1ps

// Ensure types_pkg is compiled before this file
import types_pkg::*;

module fu_branch_tb;

    // Signal Declarations
    logic clk;
    logic reset;

    // Inputs from ROB
    logic [4:0] curr_rob_tag;
    logic       mispredict_in;
    logic [4:0] mispredict_tag_in;

    // Inputs from RS
    rs_data data_in;
    logic   issued;

    // Inputs from PRF
    logic [31:0] ps1_data;
    logic [31:0] ps2_data;

    // Outputs
    b_data data_out;

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end

    // DUT Instantiation
    fu_branch dut (
        .clk           (clk),
        .reset         (reset),

        .curr_rob_tag  (curr_rob_tag),

        .data_in       (data_in),
        .issued        (issued),

        .mispredict    (mispredict_in),
        .mispredict_tag(mispredict_tag_in),

        .ps1_data      (ps1_data),
        .ps2_data      (ps2_data),

        .data_out      (data_out)
    );

    // Test Procedure
    initial begin
        // Initialize Inputs
        issued           = 0;
        data_in          = '0;
        ps1_data         = 0;
        ps2_data         = 0;
        curr_rob_tag     = 5'd0;
        mispredict_in    = 1'b0;
        mispredict_tag_in= 5'd0;

        // 1. Reset Test
        $display("--- Starting Reset Test ---");
        reset = 1;
        @(posedge clk);
        #1; // Post-hold
        reset = 0;
        @(posedge clk);
        #1;

        assert(data_out.fu_b_ready == 1'b1) else $error("Reset failed: fu_b_ready should be 1");
        assert(data_out.fu_b_done  == 1'b0) else $error("Reset failed: fu_b_done should be 0");
        $display("Reset Test Passed");

        // 2. JALR Test (Opcode 7'b1100111, func3 000)
        $display("\n--- Starting JALR Test ---");

        // Setup JALR: Target = rs1 + imm
        // PC = 1000, RS1 = 500, Imm = 20 -> Target should be 520
        // Return Address (data) should be PC + 4 = 1004

        @(negedge clk);
        issued          = 1;
        data_in.Opcode  = 7'b1100111;
        data_in.func3   = 3'b000;
        data_in.pc      = 32'd1000;
        data_in.imm     = 32'd20;
        data_in.pd      = 7'd5;     // Dest physical reg
        data_in.rob_index = 5'd2;   // arbitrary tag
        ps1_data        = 32'd500;  // Base address
        ps2_data        = 32'd0;    // Unused for JALR
        curr_rob_tag    = 5'd3;     // head/tail somewhere after this

        @(posedge clk);
        #1; // Check after clock edge

        if (data_out.fu_b_done &&
            data_out.jalr_bne_signal &&
            data_out.pc   == 32'd520 &&
            data_out.data == 32'd1004 &&
            data_out.p_b  == 7'd5) begin
            $display("JALR Test Passed: Target=520, RetAddr=1004");
        end else begin
            $error("JALR Test Failed! Got: PC=%0d, Data=%0d, Done=%b, p_b=%0d",
                   data_out.pc, data_out.data, data_out.fu_b_done, data_out.p_b);
        end

        // Deassert issue
        @(negedge clk);
        issued = 0;
        @(posedge clk);

        // 3. BNE Test - Mispredict (Taken)
        $display("\n--- Starting BNE (Mispredict/Taken) Test ---");
        // Logic assumes Not Taken. If taken (rs1 != rs2), it is a mispredict.
        // Opcode 7'b1100011, func3 001

        @(negedge clk);
        issued            = 1;
        data_in.Opcode    = 7'b1100011;
        data_in.func3     = 3'b001;
        data_in.pc        = 32'd2000;
        data_in.imm       = 32'd100;
        data_in.rob_index = 5'd12; // Tag 12

        ps1_data = 32'd10;
        ps2_data = 32'd20; // 10 != 20, so Branch IS Taken

        curr_rob_tag = 5'd13;

        @(posedge clk);
        #1;

        // Expected: Mispredict = 1, PC = (2000+100)&~1 = 2100, Tag = 12
        if (data_out.mispredict == 1'b1 &&
            data_out.mispredict_tag == 5'd12 &&
            data_out.pc == 32'd2100) begin
            $display("BNE (Taken) Test Passed: Correctly flagged mispredict to PC 2100");
        end else begin
            $error("BNE (Taken) Test Failed! Mispredict=%b, Tag=%0d, PC=%0d",
                   data_out.mispredict, data_out.mispredict_tag, data_out.pc);
        end

        // 4. BNE Test - Correct Predict (Not Taken)
        $display("\n--- Starting BNE (Correct/Not Taken) Test ---");

        @(negedge clk);
        issued         = 1;
        // Keep opcode BNE
        // Make inputs Equal so branch is NOT taken
        data_in.pc     = 32'd2200;
        data_in.imm    = 32'd40;
        data_in.rob_index = 5'd7;
        ps1_data       = 32'd50;
        ps2_data       = 32'd50;

        curr_rob_tag   = 5'd8;

        @(posedge clk);
        #1;

        // Expected: Mispredict = 0, fu_b_done = 1 (branch executed but prediction was correct)
        if (data_out.mispredict == 1'b0 && data_out.fu_b_done == 1'b1) begin
             $display("BNE (Not Taken) Test Passed: No mispredict flagged.");
        end else begin
             $error("BNE (Not Taken) Test Failed! Mispredict should be 0. Got %b",
                    data_out.mispredict);
        end

        @(negedge clk);
        issued = 0;
        @(posedge clk);

        // 5. Flush-on-Mispredict Test (kill younger in-flight branch)
        $display("\n--- Starting Flush-on-Mispredict Test ---");

        // Step 1: Produce a branch result for ROB index 3
        @(negedge clk);
        issued            = 1;
        data_in.Opcode    = 7'b1100011; // B-type
        data_in.func3     = 3'b001;     // BNE
        data_in.pc        = 32'd3000;
        data_in.imm       = 32'd40;
        data_in.rob_index = 5'd3;
        ps1_data          = 32'd1;
        ps2_data          = 32'd0;     // taken
        curr_rob_tag      = 5'd5;      // ROB tail at 5; entries 0..4 in window

        @(posedge clk);
        #1;

        // Sanity: we should have a valid branch result
        if (data_out.fu_b_done != 1'b1) begin
            $error("Flush Test setup failed: fu_b_done should be 1 after executing branch.");
        end

        // Step 2: Simulate mispredict from an OLDER branch at tag 1
        // Range of younger tags between mispredict_tag+1..curr_rob_tag-1 = {2,3,4}
        // Since this branch is at tag 3, it should be killed.
        @(negedge clk);
        issued             = 0;       // no new instruction
        mispredict_in      = 1'b1;
        mispredict_tag_in  = 5'd1;
        curr_rob_tag       = 5'd5;

        @(posedge clk);
        #1;

        // Expect: this FU's outputs are cleared
        if (data_out.fu_b_done      == 1'b0 &&
            data_out.jalr_bne_signal== 1'b0 &&
            data_out.mispredict     == 1'b0 &&
            data_out.mispredict_tag == 5'd0 &&
            data_out.pc             == 32'd0 &&
            data_out.p_b            == 7'd0) begin
            $display("Flush-on-Mispredict Test Passed: branch output cleared by flush.");
        end else begin
            $error("Flush-on-Mispredict Test FAILED: outputs not cleared as expected.\n",
                   "  fu_b_done=%b jalr_bne_signal=%b mispredict=%b tag=%0d pc=%0d p_b=%0d",
                   data_out.fu_b_done,
                   data_out.jalr_bne_signal,
                   data_out.mispredict,
                   data_out.mispredict_tag,
                   data_out.pc,
                   data_out.p_b);
        end

        // Deassert mispredict
        @(negedge clk);
        mispredict_in     = 1'b0;
        mispredict_tag_in = 5'd0;

        // End Simulation
        #20;
        $display("\n All Tests Complete");
        $finish;
    end

endmodule
