`timescale 1ns / 1ps

import types_pkg::*;

module fus_tb;

    // DUT I/O
    logic clk;
    logic reset;

    // From Reservation Stations
    logic   alu_issued;
    rs_data alu_rs_data;
    logic   b_issued;
    rs_data b_rs_data;
    logic   mem_issued;
    rs_data mem_rs_data;

    // From ROB
    logic [4:0] curr_rob_tag;
    logic       mispredict_in;      // ROB → FUs
    logic [4:0] mispredict_tag_in;  // ROB → FUs

    // PRF data
    logic [31:0] ps1_alu_data;
    logic [31:0] ps2_alu_data;
    logic [31:0] ps1_b_data;
    logic [31:0] ps2_b_data;
    logic [31:0] ps1_mem_data;
    logic [31:0] ps2_mem_data;

    // From Branch FU back to ROB
    logic       br_mispredict;
    logic [4:0] br_mispredict_tag;

    // FU outputs
    alu_data alu_out;
    b_data   b_out;
    mem_data mem_out;

    // DUT Instantiation
    fus dut (
        .clk            (clk),
        .reset          (reset),

        // RS
        .alu_issued     (alu_issued),
        .alu_rs_data    (alu_rs_data),
        .b_issued       (b_issued),
        .b_rs_data      (b_rs_data),
        .mem_issued     (mem_issued),
        .mem_rs_data    (mem_rs_data),

        // ROB
        .curr_rob_tag   (curr_rob_tag),
        .mispredict     (mispredict_in),
        .mispredict_tag (mispredict_tag_in),

        // PRF data
        .ps1_alu_data   (ps1_alu_data),
        .ps2_alu_data   (ps2_alu_data),
        .ps1_b_data     (ps1_b_data),
        .ps2_b_data     (ps2_b_data),
        .ps1_mem_data   (ps1_mem_data),
        .ps2_mem_data   (ps2_mem_data),

        // From FU branch back to ROB
        .br_mispredict     (br_mispredict),
        .br_mispredict_tag (br_mispredict_tag),

        // FU outputs
        .alu_out        (alu_out),
        .b_out          (b_out),
        .mem_out        (mem_out)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 10 ns period
    end

    // Safety Watchdog
    initial begin
        #50000;
        $display("\n[TB] ERROR: Simulation timed out.");
        $stop;
    end

    // Helper Tasks

    task automatic sys_reset();
        $display("\n[TB] --- System Reset ---");
        reset           = 1'b1;

        alu_issued      = 1'b0;
        b_issued        = 1'b0;
        mem_issued      = 1'b0;

        alu_rs_data     = '0;
        b_rs_data       = '0;
        mem_rs_data     = '0;

        ps1_alu_data    = '0;
        ps2_alu_data    = '0;
        ps1_b_data      = '0;
        ps2_b_data      = '0;
        ps1_mem_data    = '0;
        ps2_mem_data    = '0;

        curr_rob_tag    = 5'd0;

        mispredict_in      = 1'b0;
        mispredict_tag_in  = '0;

        @(posedge clk); @(posedge clk); @(posedge clk);
        #1;
        reset = 1'b0;
        @(posedge clk); #1;
    endtask

    // Generic ALU issue task (covers ADDI/ORI/SLTIU/LUI/AND/SUB/SRA)
    task automatic issue_alu(
        input  [6:0]  opcode,
        input  [2:0]  func3,
        input  [6:0]  func7,
        input  [4:0]  rd,
        input  [31:0] rs1_val,
        input  [31:0] rs2_val,
        input  [31:0] imm,
        input  [4:0]  rob_idx
    );
        alu_rs_data           = '0;
        alu_rs_data.Opcode    = opcode;
        alu_rs_data.func3     = func3;
        alu_rs_data.func7     = func7;
        alu_rs_data.pc        = 32'h1000;
        alu_rs_data.imm       = imm;
        alu_rs_data.pd        = {2'b00, rd};
        alu_rs_data.rob_index = rob_idx;

        ps1_alu_data          = rs1_val;
        ps2_alu_data          = rs2_val;

        @(negedge clk);
        alu_issued            = 1'b1;
        @(posedge clk);       // FU computes here
        #1;
        alu_issued            = 1'b0;
    endtask

    // Convenience wrapper for ADDI test
    task automatic issue_addi(
        input  [4:0]  rd,
        input  [31:0] rs1_val,
        input  [31:0] imm
    );
        issue_alu(7'b0010011, 3'b000, 7'b0,
                  rd, rs1_val, 32'd0, imm, 5'd2);
    endtask

    // Issue a JALR through branch FU
    task automatic issue_jalr(
        input [4:0]  rd,
        input [31:0] pc,
        input [31:0] rs1_val,
        input [31:0] imm
    );
        b_rs_data            = '0;
        b_rs_data.Opcode     = 7'b1100111;
        b_rs_data.func3      = 3'b000;      // JALR
        b_rs_data.pc         = pc;
        b_rs_data.imm        = imm;
        b_rs_data.pd         = {2'b00, rd};
        b_rs_data.rob_index  = 5'd5;

        ps1_b_data           = rs1_val;
        ps2_b_data           = 32'd0;

        @(negedge clk);
        b_issued             = 1'b1;
        @(posedge clk);      // FU computes here
        #1;
        b_issued             = 1'b0;
    endtask

    // Issue a BNE through branch FU; ps1, ps2 decide taken/not-taken
    task automatic issue_bne(
        input [31:0] pc,
        input [31:0] imm,
        input [31:0] val1,
        input [31:0] val2,
        input [4:0]  rob_idx
    );
        b_rs_data            = '0;
        b_rs_data.Opcode     = 7'b1100011;
        b_rs_data.func3      = 3'b001;      // BNE
        b_rs_data.pc         = pc;
        b_rs_data.imm        = imm;
        b_rs_data.rob_index  = rob_idx;

        ps1_b_data           = val1;
        ps2_b_data           = val2;

        @(negedge clk);
        b_issued             = 1'b1;
        @(posedge clk);      // FU computes here
        #1;
        b_issued             = 1'b0;
    endtask

    // Issue a LOAD (LW or LBU) through MEM FU (Opcode 0000011)
    // func3 = 3'b010 : LW
    // func3 = 3'b100 : LBU
    task automatic issue_load(
        input [2:0]  func3,
        input [31:0] base_addr,
        input [31:0] offset,
        input [4:0]  rob_idx
    );
        mem_rs_data           = '0;
        mem_rs_data.Opcode    = 7'b0000011; // LOAD
        mem_rs_data.func3     = func3;
        mem_rs_data.imm       = offset;
        mem_rs_data.rob_index = rob_idx;
        mem_rs_data.pd        = 7'd10;     // arbitrary dest

        ps1_mem_data          = base_addr;
        ps2_mem_data          = 32'd0;

        @(negedge clk);
        mem_issued            = 1'b1;
        @(posedge clk);
        #1;
        mem_issued            = 1'b0;
    endtask

    // Test Sequence
    initial begin
        sys_reset();

        // TEST 1: Basic ALU ADDI
        $display("\n[TB] === Test 1: ALU ADDI ===");
        curr_rob_tag      = 5'd0;
        mispredict_in     = 1'b0;
        mispredict_tag_in = '0;

        issue_addi(5'd3, 32'd10, 32'd20); // x3 = 10 + 20

        if (alu_out.fu_alu_done &&
            alu_out.data == 32'd30) begin
            $display("[TB] Test 1 PASSED: ALU ADDI result = %0d", alu_out.data);
        end else begin
            $error("[TB] Test 1 FAILED: expected 30, got %0d, done=%b",
                   alu_out.data, alu_out.fu_alu_done);
        end

        @(posedge clk); #1;

        // TEST 2: Branch JALR basic behavior via fus
        $display("\n[TB] === Test 2: Branch JALR via fus ===");

        issue_jalr(5'd5, 32'd1000, 32'd500, 32'd20);

        if (b_out.fu_b_done &&
            b_out.jalr_bne_signal &&
            b_out.pc   == 32'd520 &&
            b_out.data == 32'd1004 &&
            b_out.p_b  == 7'd5) begin
            $display("[TB] Test 2 PASSED: JALR target=520, retAddr=1004");
        end else begin
            $error("[TB] Test 2 FAILED: pc=%0d data=%0d done=%b signal=%b p_b=%0d",
                   b_out.pc, b_out.data, b_out.fu_b_done,
                   b_out.jalr_bne_signal, b_out.p_b);
        end

        @(posedge clk); #1;

        // TEST 3: BNE Taken → branch mispredict out of fus
        $display("\n[TB] === Test 3: BNE Taken (mispredict) via fus ===");

        issue_bne(32'd2000, 32'd100, 32'd10, 32'd20, 5'd12); // ps1!=ps2 → taken

        if (b_out.mispredict &&
            b_out.mispredict_tag == 5'd12 &&
            b_out.pc == 32'd2100 &&
            br_mispredict == 1'b1 &&
            br_mispredict_tag == 5'd12) begin
            $display("[TB] Test 3 PASSED: BNE mispredict propagated through fus.");
        end else begin
            $error("[TB] Test 3 FAILED: b_out.mispredict=%b, b_out.tag=%0d, pc=%0d, br_mispredict=%b, br_tag=%0d",
                   b_out.mispredict, b_out.mispredict_tag, b_out.pc,
                   br_mispredict, br_mispredict_tag);
        end

        @(posedge clk); #1;

        // TEST 4: BNE Not Taken → no mispredict
        $display("\n[TB] === Test 4: BNE Not Taken (no mispredict) ===");

        issue_bne(32'd3000, 32'd40, 32'd50, 32'd50, 5'd7); // ps1==ps2 → not taken

        if (!b_out.mispredict &&
            br_mispredict == 1'b0) begin
            $display("[TB] Test 4 PASSED: No mispredict for not-taken BNE.");
        end else begin
            $error("[TB] Test 4 FAILED: mispredict flagged unexpectedly. b_out.mispredict=%b, br_mispredict=%b",
                   b_out.mispredict, br_mispredict);
        end

        @(posedge clk); #1;

        // TEST 5: ALU ORI (0010011 / func3=110)
        $display("\n[TB] === Test 5: ALU ORI ===");
        mispredict_in     = 1'b0;
        mispredict_tag_in = '0;

        // rs1 = 0x0F0F_0000, imm = 0x0000_00FF → result = 0x0F0F_00FF
        issue_alu(7'b0010011, 3'b110, 7'b0,
                  5'd4, 32'h0F0F_0000, 32'd0, 32'h0000_00FF, 5'd3);

        if (alu_out.fu_alu_done &&
            alu_out.data == 32'h0F0F_00FF) begin
            $display("[TB] Test 5 PASSED: ORI result = 0x%08h", alu_out.data);
        end else begin
            $error("[TB] Test 5 FAILED: expected 0x0F0F00FF, got 0x%08h, done=%b",
                   alu_out.data, alu_out.fu_alu_done);
        end

        @(posedge clk); #1;

        // TEST 6: ALU SLTIU (0010011 / func3=011) - both < and >= cases
        $display("\n[TB] === Test 6: ALU SLTIU ===");

        // Case 6a: ps1 < imm → result = 1
        issue_alu(7'b0010011, 3'b011, 7'b0,
                  5'd6, 32'd5, 32'd0, 32'd10, 5'd4);

        if (alu_out.fu_alu_done &&
            alu_out.data == 32'd1) begin
            $display("[TB] Test 6a PASSED: SLTIU (5 < 10) result = %0d", alu_out.data);
        end else begin
            $error("[TB] Test 6a FAILED: expected 1, got %0d, done=%b",
                   alu_out.data, alu_out.fu_alu_done);
        end

        @(posedge clk); #1;

        // Case 6b: ps1 >= imm → result = 0
        issue_alu(7'b0010011, 3'b011, 7'b0,
                  5'd6, 32'd20, 32'd0, 32'd10, 5'd5);

        if (alu_out.fu_alu_done &&
            alu_out.data == 32'd0) begin
            $display("[TB] Test 6b PASSED: SLTIU (20 >= 10) result = %0d", alu_out.data);
        end else begin
            $error("[TB] Test 6b FAILED: expected 0, got %0d, done=%b",
                   alu_out.data, alu_out.fu_alu_done);
        end

        @(posedge clk); #1;

        // TEST 7: ALU LUI (0110111)
        $display("\n[TB] === Test 7: ALU LUI ===");

        issue_alu(7'b0110111, 3'b000, 7'b0,
                  5'd7, 32'd0, 32'd0, 32'hDEAD_BEEF, 5'd6);

        if (alu_out.fu_alu_done &&
            alu_out.data == 32'hDEAD_BEEF) begin
            $display("[TB] Test 7 PASSED: LUI result = 0x%08h", alu_out.data);
        end else begin
            $error("[TB] Test 7 FAILED: expected 0xDEADBEEF, got 0x%08h, done=%b",
                   alu_out.data, alu_out.fu_alu_done);
        end

        @(posedge clk); #1;

        // TEST 8: ALU SUB, AND, SRA (R-type)
        $display("\n[TB] === Test 8: ALU SUB / AND / SRA ===");

        // 8a: SUB (0110011 / func3=000 / func7[5]=1)
        issue_alu(7'b0110011, 3'b000, 7'b0100000,
                  5'd8, 32'd50, 32'd8, 32'd0, 5'd7); // 50 - 8 = 42

        if (alu_out.fu_alu_done &&
            alu_out.data == 32'd42) begin
            $display("[TB] Test 8a PASSED: SUB result = %0d", alu_out.data);
        end else begin
            $error("[TB] Test 8a FAILED: expected 42, got %0d, done=%b",
                   alu_out.data, alu_out.fu_alu_done);
        end

        @(posedge clk); #1;

        // 8b: AND (0110011 / func3=111 / func7[5]=0)
        issue_alu(7'b0110011, 3'b111, 7'b0000000,
                  5'd9, 32'hFF00_F0F0, 32'h0F0F_0F0F, 32'd0, 5'd8);

        if (alu_out.fu_alu_done &&
            alu_out.data == (32'hFF00_F0F0 & 32'h0F0F_0F0F)) begin
            $display("[TB] Test 8b PASSED: AND result = 0x%08h", alu_out.data);
        end else begin
            $error("[TB] Test 8b FAILED: expected 0x%08h, got 0x%08h, done=%b",
                   (32'hFF00_F0F0 & 32'h0F0F_0F0F), alu_out.data, alu_out.fu_alu_done);
        end

        @(posedge clk); #1;

        // 8c: SRA (0110011 / func3=101 / func7[5]=1)
        issue_alu(7'b0110011, 3'b101, 7'b0100000,
                  5'd10, 32'hFFFF_FF80, 32'd2, 32'd0, 5'd9);

        if (alu_out.fu_alu_done &&
            alu_out.data == 32'hFFFF_FFE0) begin
            $display("[TB] Test 8c PASSED: SRA result = 0x%08h", alu_out.data);
        end else begin
            $error("[TB] Test 8c FAILED: expected 0xFFFF_FFE0, got 0x%08h, done=%b",
                   alu_out.data, alu_out.fu_alu_done);
        end

        @(posedge clk); #1;

        // TEST 9: ALU flush-on-mispredict (ROB → FUs path)
        $display("\n[TB] === Test 9: ALU Flush-on-Mispredict ===");

        curr_rob_tag      = 5'd8;
        mispredict_tag_in = 5'd3;

        alu_rs_data           = '0;
        alu_rs_data.Opcode    = 7'b0010011;  // ADDI
        alu_rs_data.func3     = 3'b000;
        alu_rs_data.func7     = 7'b0;
        alu_rs_data.pc        = 32'h2000_0000;
        alu_rs_data.imm       = 32'd1;
        alu_rs_data.pd        = 7'd12;
        alu_rs_data.rob_index = 5'd5;       // younger than mispredict_tag

        ps1_alu_data          = 32'd123;
        ps2_alu_data          = 32'd0;

        @(negedge clk);
        alu_issued        = 1'b1;
        mispredict_in     = 1'b1; // ROB broadcasts mispredict
        @(posedge clk); #1;
        alu_issued        = 1'b0;
        mispredict_in     = 1'b0;

        if (alu_out.fu_alu_done == 1'b0 &&
            alu_out.data == 32'd0) begin
            $display("[TB] Test 9 PASSED: ALU outputs cleared on mispredict flush.");
        end else begin
            $error("[TB] Test 9 FAILED: flush did not clear ALU output. done=%b data=%0d",
                   alu_out.fu_alu_done, alu_out.data);
        end

        @(posedge clk); #1;

        // TEST 10: Branch flush-on-mispredict (ROB kills younger branch)
        $display("\n[TB] === Test 10: Branch Flush-on-Mispredict ===");

        curr_rob_tag      = 5'd10;
        mispredict_tag_in = 5'd3;

        // Branch at rob_index=6 (between 3 and 10) that *would* mispredict
        b_rs_data            = '0;
        b_rs_data.Opcode     = 7'b1100011;  // BNE
        b_rs_data.func3      = 3'b001;
        b_rs_data.pc         = 32'd4000;
        b_rs_data.imm        = 32'd100;
        b_rs_data.rob_index  = 5'd6;

        ps1_b_data           = 32'd1;
        ps2_b_data           = 32'd2;       // taken -> would mispredict

        @(negedge clk);
        b_issued         = 1'b1;
        mispredict_in    = 1'b1;  // older branch mispredict coming from ROB
        @(posedge clk); #1;
        b_issued         = 1'b0;
        mispredict_in    = 1'b0;

        // Because global mispredict came in, this branch's own output should be flushed
        if (b_out.fu_b_done == 1'b0 &&
            b_out.jalr_bne_signal == 1'b0 &&
            b_out.mispredict == 1'b0) begin
            $display("[TB] Test 10 PASSED: Branch outputs cleared on external mispredict.");
        end else begin
            $error("[TB] Test 10 FAILED: branch flush did not clear outputs. done=%b signal=%b mispredict=%b",
                   b_out.fu_b_done, b_out.jalr_bne_signal, b_out.mispredict);
        end

        @(posedge clk); #1;

        // TEST 11: MEM LW via fus (addr=0)
        $display("\n[TB] === Test 11: MEM LW via fus ===");
        // Assumes data_memory is initialized such that:
        //   [0..3] bytes form word 0x4433_2211 (same as fu_mem_tb)

        curr_rob_tag      = 5'd0;
        mispredict_in     = 1'b0;
        mispredict_tag_in = '0;

        issue_load(3'b010, 32'h0000_0000, 32'h0, 5'd1); // LW @0

        // Wait for 2-cycle BRAM + FU logic
        begin : WAIT_LW
            int timeout = 0;
            while (!mem_out.fu_mem_done && timeout < 50) begin
                @(posedge clk);
                timeout++;
            end
            if (!mem_out.fu_mem_done) begin
                $error("[TB] Test 11 TIMEOUT: fu_mem_done never asserted for LW.");
            end
        end

        if (mem_out.data == 32'h4433_2211) begin
            $display("[TB] Test 11 PASSED: LW result = 0x%08h", mem_out.data);
        end else begin
            $error("[TB] Test 11 FAILED: expected 0x4433_2211, got 0x%08h",
                   mem_out.data);
        end

        @(posedge clk); #1;

        // TEST 12: MEM LBU via fus (addr=1)
        $display("\n[TB] === Test 12: MEM LBU via fus ===");
        // Assumes data_memory[1] = 0x22 -> LBU = 0x0000_0022

        issue_load(3'b100, 32'h0000_0000, 32'h1, 5'd2); // LBU @1

        begin : WAIT_LBU
            int timeout = 0;
            while (!mem_out.fu_mem_done && timeout < 50) begin
                @(posedge clk);
                timeout++;
            end
            if (!mem_out.fu_mem_done) begin
                $error("[TB] Test 12 TIMEOUT: fu_mem_done never asserted for LBU.");
            end
        end

        if (mem_out.data == 32'h0000_0022) begin
            $display("[TB] Test 12 PASSED: LBU result = 0x%08h", mem_out.data);
        end else begin
            $error("[TB] Test 12 FAILED: expected 0x0000_0022, got 0x%08h",
                   mem_out.data);
        end

        @(posedge clk); #1;

        // TEST 13: MEM flush-on-mispredict (ROB kills younger load)
        $display("\n[TB] === Test 13: MEM Flush-on-Mispredict ===");

        curr_rob_tag      = 5'd8;
        mispredict_tag_in = 5'd3;

        // Issue a load at rob_index=5 (younger than branch=3)
        mem_rs_data           = '0;
        mem_rs_data.Opcode    = 7'b0000011; // LOAD
        mem_rs_data.func3     = 3'b010;     // LW
        mem_rs_data.imm       = 32'h0;
        mem_rs_data.rob_index = 5'd5;
        mem_rs_data.pd        = 7'd10;

        ps1_mem_data          = 32'h0000_0000;
        ps2_mem_data          = 32'd0;

        @(negedge clk);
        mem_issued        = 1'b1;
        mispredict_in     = 1'b1;  // global mispredict from older branch
        @(posedge clk); #1;
        mem_issued        = 1'b0;
        mispredict_in     = 1'b0;

        // After flush, fu_mem_done should be 0 and data cleared to 0
        @(posedge clk); #1;
        if (mem_out.fu_mem_done == 1'b0 &&
            mem_out.data == 32'd0) begin
            $display("[TB] Test 13 PASSED: MEM outputs cleared on mispredict flush.");
        end else begin
            $error("[TB] Test 13 FAILED: flush did not clear MEM output. done=%b data=0x%08h",
                   mem_out.fu_mem_done, mem_out.data);
        end

        #50;
        $display("\n[TB] --- All Tests Complete ---");
        $stop;
    end

endmodule
