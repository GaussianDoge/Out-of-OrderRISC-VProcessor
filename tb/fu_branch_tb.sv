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
        .clk            (clk),
        .reset          (reset),

        .curr_rob_tag   (curr_rob_tag),
        .mispredict     (mispredict_in),
        .mispredict_tag (mispredict_tag_in),

        .data_in        (data_in),
        .issued         (issued),

        .ps1_data       (ps1_data),
        .ps2_data       (ps2_data),

        .data_out       (data_out)
    );

    // Simple reset task (clears TB-side regs; FU is combinational)
    task automatic do_reset();
        begin
            reset             = 1'b1;
            issued            = 1'b0;
            data_in           = '0;
            ps1_data          = 32'd0;
            ps2_data          = 32'd0;
            curr_rob_tag      = 5'd0;
            mispredict_in     = 1'b0;
            mispredict_tag_in = 5'd0;

            repeat (2) @(posedge clk);
            reset = 1'b0;
            @(posedge clk);
        end
    endtask

    // -------------------- Main Stimulus --------------------
    initial begin
        // Waves
        $dumpfile("fu_branch_tb.vcd");
        $dumpvars(0, fu_branch_tb);

        $display("=== Starting fu_branch tests ===");

        do_reset();

        // ----------------------------------------------------
        // 1. JALR Test (Opcode 1100111, func3=000)
        // ----------------------------------------------------
        $display("\n--- JALR Test ---");
        // PC = 1000, rs1 = 500, imm = 20
        // target PC = 500 + 20 = 520
        // return (data) = PC + 4 = 1004

        @(negedge clk);
        issued             = 1'b1;
        data_in            = '0;
        data_in.Opcode     = 7'b1100111;
        data_in.func3      = 3'b000;
        data_in.pc         = 32'd1000;
        data_in.imm        = 32'd20;
        data_in.pd         = 7'd5;
        data_in.rob_index  = 5'd2;
        ps1_data           = 32'd500;
        ps2_data           = 32'd0;
        curr_rob_tag       = 5'd3;
        mispredict_in      = 1'b0;
        mispredict_tag_in  = 5'd0;

        #1; // combinational settle

        if (data_out.fu_b_done        == 1'b1   &&
            data_out.fu_b_ready       == 1'b1   &&
            data_out.jalr_bne_signal  == 1'b1   &&
            data_out.pc               == 32'd520 &&
            data_out.data             == 32'd1004 &&
            data_out.p_b              == 7'd5   &&
            data_out.rob_fu_b         == 5'd2   &&
            data_out.mispredict       == 1'b0   &&
            data_out.mispredict_tag   == 5'd0) begin
            $display("JALR Test PASSED");
        end else begin
            $error("JALR Test FAILED: pc=%0d data=%0d done=%b ready=%b jalr_bne=%b p_b=%0d rob=%0d mispred=%b tag=%0d",
                   data_out.pc, data_out.data, data_out.fu_b_done, data_out.fu_b_ready,
                   data_out.jalr_bne_signal, data_out.p_b, data_out.rob_fu_b,
                   data_out.mispredict, data_out.mispredict_tag);
        end

        @(negedge clk);
        issued = 1'b0;

        // ----------------------------------------------------
        // 2. BNE Taken (mispredict should be signaled)
        // ----------------------------------------------------
        $display("\n--- BNE Taken (mispredict) Test ---");
        // Opcode 1100011, func3=001 (BNE)
        // ps1 != ps2 → taken → we mispredicted (assuming not taken)

        @(negedge clk);
        issued             = 1'b1;
        data_in            = '0;
        data_in.Opcode     = 7'b1100011;
        data_in.func3      = 3'b001;
        data_in.pc         = 32'd2000;
        data_in.imm        = 32'd100;
        data_in.rob_index  = 5'd12;

        ps1_data           = 32'd10;
        ps2_data           = 32'd20;      // unequal → branch taken

        curr_rob_tag       = 5'd13;
        mispredict_in      = 1'b0;
        mispredict_tag_in  = 5'd0;

        #1;

        // Target PC = (2000+100) & ~1 = 2100
        if (data_out.mispredict      == 1'b1     &&
            data_out.mispredict_tag  == 5'd12    &&
            data_out.pc              == 32'd2100 &&
            data_out.rob_fu_b        == 5'd12    &&
            data_out.jalr_bne_signal == 1'b1     &&
            data_out.fu_b_done       == 1'b1     &&
            data_out.fu_b_ready      == 1'b1) begin
            $display("BNE Taken Test PASSED");
        end else begin
            $error("BNE Taken Test FAILED: mispred=%b tag=%0d pc=%0d rob=%0d jalr_bne=%b done=%b ready=%b",
                   data_out.mispredict, data_out.mispredict_tag,
                   data_out.pc, data_out.rob_fu_b,
                   data_out.jalr_bne_signal,
                   data_out.fu_b_done, data_out.fu_b_ready);
        end

        @(negedge clk);
        issued = 1'b0;

        // ----------------------------------------------------
        // 3. BNE Not Taken (correct prediction, no mispredict)
        // ----------------------------------------------------
        $display("\n--- BNE Not Taken (no mispredict) Test ---");

        @(negedge clk);
        issued             = 1'b1;
        data_in            = '0;
        data_in.Opcode     = 7'b1100011;
        data_in.func3      = 3'b001;
        data_in.pc         = 32'd2200;
        data_in.imm        = 32'd40;
        data_in.rob_index  = 5'd7;

        ps1_data           = 32'd50;
        ps2_data           = 32'd50;    // equal → not taken

        curr_rob_tag       = 5'd8;
        mispredict_in      = 1'b0;
        mispredict_tag_in  = 5'd0;

        #1;

        if (data_out.mispredict      == 1'b0  &&
            data_out.fu_b_done       == 1'b1  &&
            data_out.jalr_bne_signal == 1'b0  &&
            data_out.pc              == 32'd0 &&
            data_out.rob_fu_b        == 5'd7  &&
            data_out.fu_b_ready      == 1'b1) begin
            $display("BNE Not Taken Test PASSED");
        end else begin
            $error("BNE Not Taken Test FAILED: mispred=%b done=%b jalr_bne=%b pc=%0d rob=%0d ready=%b",
                   data_out.mispredict, data_out.fu_b_done,
                   data_out.jalr_bne_signal, data_out.pc,
                   data_out.rob_fu_b, data_out.fu_b_ready);
        end

        @(negedge clk);
        issued = 1'b0;

        // ----------------------------------------------------
        // 4. Flush-on-Mispredict Test
        // ----------------------------------------------------
        $display("\n--- Flush-on-Mispredict Test ---");

        // Setup: branch at rob_index=3 appears as in-flight in FU
        @(negedge clk);
        issued             = 1'b1;
        data_in            = '0;
        data_in.Opcode     = 7'b1100011; // BNE
        data_in.func3      = 3'b001;
        data_in.pc         = 32'd3000;
        data_in.imm        = 32'd40;
        data_in.rob_index  = 5'd3;
        ps1_data           = 32'd1;
        ps2_data           = 32'd0;
        curr_rob_tag       = 5'd5;

        mispredict_in      = 1'b0;
        mispredict_tag_in  = 5'd0;

        #1;
        // Sanity: with mispredict_in=0, FU produces some branch result
        if (!data_out.fu_b_done) begin
            $error("Flush Test setup: fu_b_done should be 1 when executing branch.");
        end

        // Now assert mispredict from older branch at tag=1
        @(negedge clk);
        issued             = 1'b0;  // RS can stop issuing this
        mispredict_in      = 1'b1;
        mispredict_tag_in  = 5'd1;
        curr_rob_tag       = 5'd5;  // so window is {2,3,4}

        #1;

        // Expected: FU outputs are cleared (flush)
        if (data_out.fu_b_done       == 1'b0 &&
            data_out.jalr_bne_signal == 1'b0 &&
            data_out.mispredict      == 1'b0 &&
            data_out.mispredict_tag  == 5'd0 &&
            data_out.pc              == 32'd0 &&
            data_out.p_b             == 7'd0  &&
            data_out.rob_fu_b        == 5'd0  &&
            data_out.fu_b_ready      == 1'b1) begin
            $display("Flush-on-Mispredict Test PASSED: outputs cleared.");
        end else begin
            $error("Flush-on-Mispredict Test FAILED: fu_b_done=%b ready=%b jalr_bne=%b mispred=%b tag=%0d pc=%0d p_b=%0d rob_fu_b=%0d",
                   data_out.fu_b_done,
                   data_out.fu_b_ready,
                   data_out.jalr_bne_signal,
                   data_out.mispredict,
                   data_out.mispredict_tag,
                   data_out.pc,
                   data_out.p_b,
                   data_out.rob_fu_b);
        end

        @(negedge clk);
        mispredict_in     = 1'b0;
        mispredict_tag_in = 5'd0;
        issued            = 1'b0;
        data_in           = '0;

        #20;
        $display("\n=== All fu_branch tests complete ===");
        $finish;
    end

    // Monitor
    initial begin
        $monitor("[%0t] issued=%0b mispred_in=%0b fu_b_done=%0b fu_b_ready=%0b jalr_bne=%0b pc=0x%08h rob=%0d mispred_tag=%0d",
                 $time,
                 issued,
                 mispredict_in,
                 data_out.fu_b_done,
                 data_out.fu_b_ready,
                 data_out.jalr_bne_signal,
                 data_out.pc,
                 data_out.rob_fu_b,
                 data_out.mispredict_tag);
    end

endmodule
