`timescale 1ns / 1ps
import types_pkg::*;

module tb_alu_reservation_station;

    // Parameters
    localparam int RS_DEPTH   = 8;
    localparam int CLK_PERIOD = 10;

    // DUT signals
    logic clk;
    logic reset;

    // ALU ready signals
    logic alu1_rdy;
    logic alu2_rdy;

    // Upstream interface (two pipelines)
    logic                  valid_in_1;
    logic                  valid_in_2;
    logic                  ready_in;
    logic                  ready_in2;
    dispatch_pipeline_data instr1;
    dispatch_pipeline_data instr2;

    // Downstream / issue side
    logic          ready_out;
    logic          valid_out;
    alu_rs_data  [1:0]  data_out;
    logic [1:0]    valid_issue;

    // DUT instance
    alu_reservation_station dut (
        .clk        (clk),
        .reset      (reset),
        .alu1_rdy   (alu1_rdy),
        .alu2_rdy   (alu2_rdy),
        .valid_in_1 (valid_in_1),
        .valid_in_2 (valid_in_2),
        .ready_in   (ready_in),
        .ready_in2  (ready_in2),
        .instr1     (instr1),
        .instr2     (instr2),
        .ready_out  (ready_out),
        .valid_out  (valid_out),
        .data_out   (data_out),
        .valid_issue(valid_issue)
    );

    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;

    // Simple helper: wait n cycles
    task automatic wait_cycles(input int n);
        begin
            repeat (n) @(posedge clk);
        end
    endtask

    // Helper: mark the entry with a given PRD as ready (pr1_ready/pr2_ready = 1)
    task automatic mark_pr_ready_by_prd(input logic [7:0] prd_value);
        int idx;
        begin
            idx = -1;
            for (int i = 0; i < RS_DEPTH; i++) begin
                if (!dut.rs_table[i].valid && dut.rs_table[i].prd == prd_value) begin
                    idx = i;
                    break;
                end
            end
            if (idx == -1) begin
                $error("[%0t] mark_pr_ready_by_prd: could not find entry with prd=%0d", $time, prd_value);
            end else begin
                dut.rs_table[idx].pr1_ready = 1'b1;
                dut.rs_table[idx].pr2_ready = 1'b1;
                $display("[%0t] mark_pr_ready_by_prd: entry %0d (prd=%0d) marked ready", $time, idx, prd_value);
            end
        end
    endtask

    // Helper: wait until the entry with a given PRD has issued (its valid bit goes back to 1)
    task automatic wait_issue_by_prd(input logic [7:0] prd_value, input string tag);
        int idx;
        int cycles;
        begin
            // Find the entry first
            idx = -1;
            for (int i = 0; i < RS_DEPTH; i++) begin
                if (!dut.rs_table[i].valid && dut.rs_table[i].prd == prd_value) begin
                    idx = i;
                    break;
                end
            end
            if (idx == -1) begin
                $error("[%0t] %s: wait_issue_by_prd: entry with prd=%0d not found (maybe already issued?)",
                       $time, tag, prd_value);
                return;
            end

            cycles = 0;
            while (!dut.rs_table[idx].valid && cycles < 20) begin
                @(posedge clk);
                cycles++;
            end

            if (dut.rs_table[idx].valid) begin
                $display("[%0t] %s: entry with prd=%0d issued after %0d cycles (slot %0d freed)",
                         $time, tag, prd_value, cycles, idx);
            end else begin
                $error("[%0t] %s: entry with prd=%0d did NOT issue within timeout", $time, tag, prd_value);
            end
        end
    endtask

    // Helper: drain the RS by marking all current entries ready and enabling both ALUs
    // (no extra reset, but we end up with free_space == 8)
    task automatic drain_rs(input string tag);
        int safety;
        begin
            $display("\n[%0t] %s: draining RS ...", $time, tag);
            // Make both ALUs ready
            alu1_rdy = 1'b1;
            alu2_rdy = 1'b1;

            safety = 0;
            // Repeat: mark all occupied entries ready and wait until all slots are free
            while (dut.free_space != RS_DEPTH && safety < 30) begin
                // Mark all occupied entries ready
                for (int i = 0; i < RS_DEPTH; i++) begin
                    if (!dut.rs_table[i].valid) begin
                        dut.rs_table[i].pr1_ready = 1'b1;
                        dut.rs_table[i].pr2_ready = 1'b1;
                    end
                end
                @(posedge clk);
                safety++;
            end

            if (dut.free_space == RS_DEPTH) begin
                $display("[%0t] %s: RS drained (free_space=%0d)", $time, tag, dut.free_space);
            end else begin
                $error("[%0t] %s: failed to drain RS (free_space=%0d)", $time, tag, dut.free_space);
            end
        end
    endtask

    // Test 0: One instruction, PR ready, ALUs ready -> issues
    task automatic test_single_issue();
        begin
            $display("\n[%0t] --- Test 0: single instruction issues ---", $time);
            drain_rs("Test0");

            // ALUs ready
            alu1_rdy = 1'b1;
            alu2_rdy = 1'b1;

            // Prepare one instruction (unique PRD)
            instr1.Opcode    = 7'h33;
            instr1.prd       = 8'd10;
            instr1.pr1       = 8'd1;
            instr1.pr2       = 8'd2;
            instr1.pr1_ready = 1'b0;  // will be set in rs_table directly
            instr1.pr2_ready = 1'b0;
            instr1.imm       = 32'hAAAA_0000;
            instr1.rob_index = 4'd0;

            // Dispatch it on pipeline 1
            valid_in_1 = 1'b1;
            valid_in_2 = 1'b0;
            @(posedge clk);
            valid_in_1 = 1'b0;

            // After it is stored, mark PR ready in the RS
            #1;
            mark_pr_ready_by_prd(8'd10);

            // Wait for it to issue
            wait_issue_by_prd(8'd10, "Test0");

            $display("[%0t] Test 0 DONE\n", $time);
        end
    endtask

    // Test 1: Two ready instructions, two ready ALUs -> both issue
    task automatic test_two_issue_when_all_ready();
        begin
            $display("\n[%0t] --- Test 1: two ready instr + two ready ALUs ---", $time);
            drain_rs("Test1");

            alu1_rdy = 1'b1;
            alu2_rdy = 1'b1;

            // Two instructions with different PRDs
            instr1.Opcode    = 7'h33;
            instr1.prd       = 8'd21;
            instr1.pr1       = 8'd2;
            instr1.pr2       = 8'd3;
            instr1.pr1_ready = 1'b0;
            instr1.pr2_ready = 1'b0;
            instr1.imm       = 32'h1111_1111;
            instr1.rob_index = 4'd1;

            instr2.Opcode    = 7'h13;
            instr2.prd       = 8'd22;
            instr2.pr1       = 8'd4;
            instr2.pr2       = 8'd5;
            instr2.pr1_ready = 1'b0;
            instr2.pr2_ready = 1'b0;
            instr2.imm       = 32'h2222_2222;
            instr2.rob_index = 4'd2;

            // Dispatch both in same cycle
            valid_in_1 = 1'b1;
            valid_in_2 = 1'b1;
            @(posedge clk);
            valid_in_1 = 1'b0;
            valid_in_2 = 1'b0;

            // Mark both entries ready inside RS
            #1;
            mark_pr_ready_by_prd(8'd21);
            mark_pr_ready_by_prd(8'd22);

            // Wait for both to issue
            wait_issue_by_prd(8'd21, "Test1");
            wait_issue_by_prd(8'd22, "Test1");

            $display("[%0t] Test 1 DONE\n", $time);
        end
    endtask

    // Test 2: PRs not ready -> stall even though ALUs are ready
    task automatic test_pr_not_ready_stalls();
        int idx;
        begin
            $display("\n[%0t] --- Test 2: PRs not ready -> stall ---", $time);
            drain_rs("Test2");

            alu1_rdy = 1'b1;
            alu2_rdy = 1'b1;

            // One instruction with PR not ready (we will NOT set pr*_ready in rs_table)
            instr1.Opcode    = 7'h33;
            instr1.prd       = 8'd30;
            instr1.pr1       = 8'd6;
            instr1.pr2       = 8'd7;
            instr1.pr1_ready = 1'b0;
            instr1.pr2_ready = 1'b0;
            instr1.imm       = 32'h3333_0000;
            instr1.rob_index = 4'd3;

            valid_in_1 = 1'b1;
            valid_in_2 = 1'b0;
            @(posedge clk);
            valid_in_1 = 1'b0;

            // Locate the entry
            #1;
            idx = -1;
            for (int i = 0; i < RS_DEPTH; i++) begin
                if (!dut.rs_table[i].valid && dut.rs_table[i].prd == 8'd30) begin
                    idx = i;
                    break;
                end
            end
            if (idx == -1) begin
                $error("[%0t] Test2: could not find entry with prd=30", $time);
            end

            // Check that over several cycles, it does NOT issue (valid stays 0)
            for (int c = 0; c < 5; c++) begin
                @(posedge clk);
                if (idx != -1 && dut.rs_table[idx].valid) begin
                    $error("[%0t] Test2 FAIL: entry (prd=30) issued even though PRs were not ready", $time);
                end
            end

            $display("[%0t] Test2: no issue while PRs not ready, now marking PR ready ...", $time);

            // Now mark PR ready and expect it to issue
            mark_pr_ready_by_prd(8'd30);
            wait_issue_by_prd(8'd30, "Test2");

            $display("[%0t] Test 2 DONE\n", $time);
        end
    endtask

    // Test 3: ALUs not ready -> stall even though PRs are ready
    task automatic test_alu_not_ready_stalls();
        int idx;
        begin
            $display("\n[%0t] --- Test 3: ALUs not ready -> stall ---", $time);
            drain_rs("Test3");

            // ALUs NOT ready at first
            alu1_rdy = 1'b0;
            alu2_rdy = 1'b0;

            instr1.Opcode    = 7'h33;
            instr1.prd       = 8'd40;
            instr1.pr1       = 8'd8;
            instr1.pr2       = 8'd9;
            instr1.pr1_ready = 1'b0;
            instr1.pr2_ready = 1'b0;
            instr1.imm       = 32'h4444_0000;
            instr1.rob_index = 4'd4;

            valid_in_1 = 1'b1;
            valid_in_2 = 1'b0;
            @(posedge clk);
            valid_in_1 = 1'b0;

            // Mark PR ready immediately in RS
            #1;
            mark_pr_ready_by_prd(8'd40);

            // Locate index
            idx = -1;
            for (int i = 0; i < RS_DEPTH; i++) begin
                if (!dut.rs_table[i].valid && dut.rs_table[i].prd == 8'd40) begin
                    idx = i;
                    break;
                end
            end
            if (idx == -1) begin
                $error("[%0t] Test3: could not find entry with prd=40", $time);
            end

            // While ALUs are not ready, it must not issue
            for (int c = 0; c < 5; c++) begin
                @(posedge clk);
                if (idx != -1 && dut.rs_table[idx].valid) begin
                    $error("[%0t] Test3 FAIL: entry (prd=40) issued while ALUs not ready", $time);
                end
            end

            // Now enable ALUs and expect issue
            alu1_rdy = 1'b1;
            alu2_rdy = 1'b1;
            wait_issue_by_prd(8'd40, "Test3");

            $display("[%0t] Test 3 DONE\n", $time);
        end
    endtask

    // Test 4: Fill RS almost full, then try to send 2 instr with only 1 slot left
    // Expect only ONE of them to be accepted.
    task automatic test_one_slot_left_two_instr();
        int accepted;
        begin
            $display("\n[%0t] --- Test 4: 1 free slot, try 2 instr ---", $time);
            drain_rs("Test4");

            // Keep ALUs not ready so entries stay in RS
            alu1_rdy = 1'b0;
            alu2_rdy = 1'b0;

            // Fill RS with RS_DEPTH-1 instructions
            for (int k = 0; k < RS_DEPTH-1; k++) begin
                instr1.Opcode    = 7'h33;
                instr1.prd       = 8'(50 + k);  // unique
                instr1.pr1       = 8'd10;
                instr1.pr2       = 8'd11;
                instr1.pr1_ready = 1'b0;
                instr1.pr2_ready = 1'b0;
                instr1.imm       = 32'h5555_0000;
                instr1.rob_index = k[3:0];

                valid_in_1 = 1'b1;
                valid_in_2 = 1'b0;
                @(posedge clk);
                valid_in_1 = 1'b0;
            end

            @(posedge clk);
            $display("[%0t] Test4: after filling %0d entries, free_space=%0d ready_in=%b ready_in2=%b",
                     $time, RS_DEPTH-1, dut.free_space, ready_in, ready_in2);

            // Now try to send 2 instr when there is only 1 free slot
            instr1.Opcode    = 7'h33;
            instr1.prd       = 8'd100;
            instr1.pr1       = 8'd20;
            instr1.pr2       = 8'd21;
            instr1.pr1_ready = 1'b0;
            instr1.pr2_ready = 1'b0;
            instr1.imm       = 32'h6666_0000;
            instr1.rob_index = 4'd10;

            instr2.Opcode    = 7'h33;
            instr2.prd       = 8'd101;
            instr2.pr1       = 8'd22;
            instr2.pr2       = 8'd23;
            instr2.pr1_ready = 1'b0;
            instr2.pr2_ready = 1'b0;
            instr2.imm       = 32'h7777_0000;
            instr2.rob_index = 4'd11;

            valid_in_1 = 1'b1;
            valid_in_2 = 1'b1;
            @(posedge clk);
            valid_in_1 = 1'b0;
            valid_in_2 = 1'b0;

            @(posedge clk);

            accepted = 0;
            for (int i = 0; i < RS_DEPTH; i++) begin
                if (!dut.rs_table[i].valid &&
                   (dut.rs_table[i].prd == 8'd100 || dut.rs_table[i].prd == 8'd101)) begin
                    accepted++;
                end
            end

            $display("[%0t] Test4: among prd=100/101, accepted=%0d", $time, accepted);

            if (accepted != 1) begin
                $error("[%0t] Test4 FAIL: expected exactly 1 instr accepted with 1 free slot, got %0d",
                       $time, accepted);
            end else begin
                $display("[%0t] Test4 PASS: only 1 of 2 instr accepted when 1 slot left.", $time);
            end

            $display("[%0t] Test 4 DONE\n", $time);
        end
    endtask

    int found;
    // Test 5: Fill RS completely, check that new instr are not accepted (stalls)
    task automatic test_full_rs_stalls_new_instr();
        int before_free;
        int after_free;
        begin
            $display("\n[%0t] --- Test 5: RS full -> no new instr accepted ---", $time);
            drain_rs("Test5");

            alu1_rdy = 1'b0;
            alu2_rdy = 1'b0;

            // Fill RS completely with 8 instructions
            for (int k = 0; k < RS_DEPTH; k++) begin
                instr1.Opcode    = 7'h33;
                instr1.prd       = 8'(70 + k);  // unique
                instr1.pr1       = 8'd30;
                instr1.pr2       = 8'd31;
                instr1.pr1_ready = 1'b0;
                instr1.pr2_ready = 1'b0;
                instr1.imm       = 32'h8888_0000;
                instr1.rob_index = k[3:0];

                valid_in_1 = 1'b1;
                valid_in_2 = 1'b0;
                @(posedge clk);
                valid_in_1 = 1'b0;
            end

            @(posedge clk);
            $display("[%0t] Test5: after filling, free_space=%0d ready_in=%b ready_in2=%b",
                     $time, dut.free_space, ready_in, ready_in2);

            // Now RS should be full
            if (dut.free_space != 0) begin
                $error("[%0t] Test5: expected free_space=0 (full), got %0d", $time, dut.free_space);
            end

            before_free = dut.free_space;

            // Try to send one more instruction
            instr1.Opcode    = 7'h33;
            instr1.prd       = 8'd120;
            instr1.pr1       = 8'd40;
            instr1.pr2       = 8'd41;
            instr1.pr1_ready = 1'b0;
            instr1.pr2_ready = 1'b0;
            instr1.imm       = 32'h9999_0000;
            instr1.rob_index = 4'd15;

            valid_in_1 = 1'b1;
            valid_in_2 = 1'b0;
            @(posedge clk);
            valid_in_1 = 1'b0;

            @(posedge clk);
            after_free = dut.free_space;

            // Scan for prd=120
            found = 0;
            for (int i = 0; i < RS_DEPTH; i++) begin
                if (!dut.rs_table[i].valid && dut.rs_table[i].prd == 8'd120) begin
                    found = 1;
                end
            end

            if (found) begin
                $error("[%0t] Test5 FAIL: new instruction (prd=120) was stored even though RS full", $time);
            end else if (before_free != 0 || after_free != 0) begin
                $error("[%0t] Test5 FAIL: free_space changed unexpectedly before=%0d after=%0d",
                       $time, before_free, after_free);
            end else begin
                $display("[%0t] Test5 PASS: RS full, no new instr accepted.", $time);
            end

            $display("[%0t] Test 5 DONE\n", $time);
        end
    endtask

    // Main test sequence
    initial begin
        // Init
        clk        = 1'b0;
        reset      = 1'b1;
        alu1_rdy   = 1'b0;
        alu2_rdy   = 1'b0;
        valid_in_1 = 1'b0;
        valid_in_2 = 1'b0;
        ready_out  = 1'b1;   // downstream always ready

        instr1 = '0;
        instr2 = '0;

        // Reset once at start
        wait_cycles(3);
        reset = 1'b0;
        wait_cycles(1);
        $display("[%0t] Reset de-asserted, starting tests ...", $time);

        test_single_issue();
        test_two_issue_when_all_ready();
        test_pr_not_ready_stalls();
        test_alu_not_ready_stalls();
        test_one_slot_left_two_instr();
        test_full_rs_stalls_new_instr();

        $display("\n[%0t] === ALL TESTS COMPLETED ===", $time);
        $finish;
    end

endmodule
