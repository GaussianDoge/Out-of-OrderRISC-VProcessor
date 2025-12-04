`timescale 1ns/1ps
import types_pkg::*;

module fu_alu_tb;

    // Signals
    logic        clk;
    logic        reset;
    logic        issued;

    // ROB / branch signals
    logic [4:0]  curr_rob_tag;
    logic        mispredict;
    logic [4:0]  mispredict_tag;

    rs_data      data_in;
    logic [31:0] ps1_data;
    logic [31:0] ps2_data;

    alu_data     data_out;

    // Localparams for opcodes / tags 
    localparam logic [6:0] OPCODE_OPIMM   = 7'b0010011;
    localparam logic [6:0] OPCODE_LUI     = 7'b0110111;
    localparam logic [6:0] OPCODE_OP      = 7'b0110011;

    localparam logic [6:0] EXPECTED_PD    = 7'd5;
    localparam logic [4:0] EXPECTED_ROB   = 5'd3;

    // DUT 
    fu_alu dut (
        .clk            (clk),
        .reset          (reset),
        .curr_rob_tag   (curr_rob_tag),
        .mispredict     (mispredict),
        .mispredict_tag (mispredict_tag),
        .issued         (issued),      // not used in fu_alu (combinational)
        .data_in        (data_in),
        .ps1_data       (ps1_data),
        .ps2_data       (ps2_data),
        .data_out       (data_out)
    );

    // Clock (not strictly needed for combinational FU, but fine)
    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz, 10 ns period

    // ---------------- Tasks ----------------

    task automatic apply_reset;
        begin
            reset          = 1'b1;
            issued         = 1'b0;
            curr_rob_tag   = '0;
            mispredict     = 1'b0;
            mispredict_tag = '0;

            data_in        = '0;
            ps1_data       = '0;
            ps2_data       = '0;

            repeat (5) @(posedge clk);
            reset = 1'b0;
            @(posedge clk);
        end
    endtask

    // For combinational FU: drive inputs, wait #1, then check outputs
    task automatic do_alu_op(
        input string       name,
        input logic [6:0]  opcode,
        input logic [2:0]  func3,
        input logic [6:0]  func7,
        input logic [31:0] imm,
        input logic [31:0] src1,
        input logic [31:0] src2,
        input logic [31:0] expected
    );
        begin
            @(negedge clk);
            mispredict          = 1'b0;
            mispredict_tag      = '0;
            curr_rob_tag        = EXPECTED_ROB + 1;  // arbitrary

            data_in             = '0;
            data_in.valid       = 1'b1;
            data_in.Opcode      = opcode;
            data_in.func3       = func3;
            data_in.func7       = func7;
            data_in.imm         = imm;
            data_in.pd          = EXPECTED_PD;
            data_in.rob_index   = EXPECTED_ROB;
            data_in.fu          = 2'd1;    // ALU

            ps1_data            = src1;
            ps2_data            = src2;

            issued              = 1'b1;    // purely cosmetic here

            #1; // let combinational logic settle

            if (data_out.fu_alu_ready !== 1'b1) begin
                $error("[%0t] %s: fu_alu_ready should be 1, got %0b",
                       $time, name, data_out.fu_alu_ready);
            end

            if (data_out.fu_alu_done !== 1'b1) begin
                $error("[%0t] %s: fu_alu_done not asserted when expected", $time, name);
            end

            if (data_out.p_alu !== EXPECTED_PD) begin
                $error("[%0t] %s: p_alu mismatch: got %0d, expected %0d",
                       $time, name, data_out.p_alu, EXPECTED_PD);
            end
            if (data_out.rob_fu_alu !== EXPECTED_ROB) begin
                $error("[%0t] %s: rob_fu_alu mismatch: got %0d, expected %0d",
                       $time, name, data_out.rob_fu_alu, EXPECTED_ROB);
            end

            if (data_out.data !== expected) begin
                $error("[%0t] %s FAILED: got 0x%08h, expected 0x%08h",
                       $time, name, data_out.data, expected);
            end else begin
                $display("[%0t] %s PASSED: result = 0x%08h",
                         $time, name, data_out.data);
            end

            issued = 1'b0;
            @(posedge clk); // small gap before next op
        end
    endtask

    // Test mispredict flush while ALU result is "live"
    task automatic test_mispredict_flush;
        begin
            $display("\n[Test] Mispredict flush...");

            // Issue a simple ADDI with ROB index = 5
            @(negedge clk);
            mispredict          = 1'b0;
            mispredict_tag      = '0;
            curr_rob_tag        = 5'd0;

            data_in             = '0;
            data_in.valid       = 1'b1;
            data_in.Opcode      = OPCODE_OPIMM;
            data_in.func3       = 3'b000;       // ADDI
            data_in.func7       = 7'b0000000;
            data_in.imm         = 32'd5;
            data_in.pd          = 7'd10;
            data_in.rob_index   = 5'd5;        // <-- in mispredict window
            data_in.fu          = 2'd1;

            ps1_data            = 32'd10;
            ps2_data            = 32'd0;

            issued              = 1'b1;

            // Check "normal" result first
            #1;
            if (data_out.fu_alu_done !== 1'b1 ||
                data_out.data        !== 32'd15) begin
                $error("[%0t] Mispredict test: initial ADDI result wrong: done=%0b data=0x%08h",
                       $time, data_out.fu_alu_done, data_out.data);
            end else begin
                $display("[%0t] Mispredict test: initial ADDI result OK: 0x%08h",
                         $time, data_out.data);
            end

            // Now assert mispredict for window including rob_index==5
            // mispredict_tag=3, curr_rob_tag=8 -> loop visits 4,5,6,7
            @(negedge clk);
            mispredict     = 1'b1;
            mispredict_tag = 5'd3;
            curr_rob_tag   = 5'd8;

            #1;
            // After mispredict, outputs should be cleared
            if (data_out.fu_alu_done !== 1'b0 ||
                data_out.p_alu       !== '0    ||
                data_out.rob_fu_alu  !== '0    ||
                data_out.data        !== '0) begin
                $error("[%0t] Mispredict flush FAILED: done=%0b p_alu=%0d rob=%0d data=0x%08h",
                       $time,
                       data_out.fu_alu_done,
                       data_out.p_alu,
                       data_out.rob_fu_alu,
                       data_out.data);
            end else begin
                $display("[%0t] Mispredict flush PASSED: outputs cleared.", $time);
            end

            @(negedge clk);
            mispredict     = 1'b0;
            mispredict_tag = '0;
            issued         = 1'b0;
            data_in        = '0;
            ps1_data       = '0;
            ps2_data       = '0;
            @(posedge clk);
        end
    endtask

    // Back-to-back ops: drive two ALU ops in sequence
    task automatic test_back_to_back;
        logic [31:0] expected1;
        logic [31:0] expected2;
        begin
            $display("\n[Test] Back-to-back ops...");

            // First op: ADDI: 10 + 5 = 15
            @(negedge clk);
            mispredict          = 1'b0;
            mispredict_tag      = '0;
            curr_rob_tag        = 5'd4;

            data_in             = '0;
            data_in.valid       = 1'b1;
            data_in.Opcode      = OPCODE_OPIMM;
            data_in.func3       = 3'b000;
            data_in.func7       = 7'b0000000;
            data_in.imm         = 32'd5;
            data_in.pd          = 7'd11;
            data_in.rob_index   = 5'd4;
            data_in.fu          = 2'd1;

            ps1_data            = 32'd10;
            ps2_data            = 32'd0;

            issued = 1'b1;
            #1;

            expected1 = 32'd15;
            if (data_out.fu_alu_done !== 1'b1 || data_out.data !== expected1) begin
                $error("[%0t] Back-to-back op1 FAILED: done=%0b data=0x%08h expected=0x%08h",
                       $time, data_out.fu_alu_done, data_out.data, expected1);
            end else begin
                $display("[%0t] Back-to-back op1 PASSED: result=0x%08h", $time, data_out.data);
            end

            // Second op: SUB 30 - 12 = 18
            @(negedge clk);
            data_in             = '0;
            data_in.valid       = 1'b1;
            data_in.Opcode      = OPCODE_OP;
            data_in.func3       = 3'b000;
            data_in.func7       = 7'b0100000; // SUB
            data_in.imm         = 32'd0;
            data_in.pd          = 7'd12;
            data_in.rob_index   = 5'd5;
            data_in.fu          = 2'd1;

            ps1_data            = 32'd30;
            ps2_data            = 32'd12;

            issued = 1'b1;
            #1;

            expected2 = 32'd18;
            if (data_out.fu_alu_done !== 1'b1 || data_out.data !== expected2) begin
                $error("[%0t] Back-to-back op2 FAILED: done=%0b data=0x%08h expected=0x%08h",
                       $time, data_out.fu_alu_done, data_out.data, expected2);
            end else begin
                $display("[%0t] Back-to-back op2 PASSED: result=0x%08h", $time, data_out.data);
            end

            @(negedge clk);
            issued = 1'b0;
            @(posedge clk);
        end
    endtask

    // ---------------- Test sequence ----------------
    initial begin
        $dumpfile("fu_alu_waves.vcd");
        $dumpvars(0, fu_alu_tb);

        apply_reset();

        // 1) ADDI
        do_alu_op("ADDI",
            OPCODE_OPIMM, 3'b000, 7'b0000000,
            32'd5,
            32'd10,
            32'd0,
            32'd15
        );

        // 2) ORI
        do_alu_op("ORI",
            OPCODE_OPIMM, 3'b110, 7'b0000000,
            32'h0000_FFFF,
            32'h0F0F_0000,
            32'd0,
            32'h0F0F_FFFF
        );

        // 3) SLTIU
        do_alu_op("SLTIU",
            OPCODE_OPIMM, 3'b011, 7'b0000000,
            32'd20,
            32'd10,
            32'd0,
            32'd1
        );

        // 4) LUI
        do_alu_op("LUI",
            OPCODE_LUI, 3'b000, 7'b0000000,
            32'h1234_5000,
            32'd0,
            32'd0,
            32'h1234_5000
        );

        // 5) SRA
        do_alu_op("SRA",
            OPCODE_OP, 3'b101, 7'b0100000,
            32'd0,
            32'hF000_0000,
            32'd4,
            32'hFF00_0000
        );

        // 6) SUB
        do_alu_op("SUB",
            OPCODE_OP, 3'b000, 7'b0100000,
            32'd0,
            32'd30,
            32'd12,
            32'd18
        );

        // 7) AND
        do_alu_op("AND",
            OPCODE_OP, 3'b111, 7'b0000000,
            32'd0,
            32'hFF00_FF00,
            32'h0F0F_0F0F,
            32'h0F00_0F00
        );

        test_mispredict_flush();
        test_back_to_back();

        $display("[%0t] All tests completed.", $time);
        $finish;
    end

    // Monitor
    initial begin
        $monitor("[%0t] issued=%0b mispred=%0b done=%0b p_alu=%0d rob=%0d data=0x%08h",
                 $time,
                 issued,
                 mispredict,
                 data_out.fu_alu_done,
                 data_out.p_alu,
                 data_out.rob_fu_alu,
                 data_out.data);
    end

endmodule
