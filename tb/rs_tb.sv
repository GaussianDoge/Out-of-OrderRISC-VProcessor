`timescale 1ns / 1ps
import types_pkg::*;

module rs_tb;

    // ------------------------
    // DUT interface signals
    // ------------------------
    logic clk;
    logic reset;
    logic fu_rdy;

    // Upstream (from dispatch / buffer)
    logic                 valid_in;
    logic                 ready_in;
    dispatch_pipeline_data instr;

    // Downstream (to FU)
    logic   valid_out;
    rs_data data_out;

    // New dest physical reg not-ready
    logic [6:0] nr_reg;
    logic       nr_valid;

    // Ready-reg broadcast from PRF / CDB
    logic [6:0] reg1_rdy, reg2_rdy, reg3_rdy;
    logic       reg1_rdy_valid, reg2_rdy_valid, reg3_rdy_valid;

    // Flush / recover
    logic flush;

    // ------------------------
    // DUT instance
    // ------------------------
    rs dut (
        .clk            (clk),
        .reset          (reset),
        .fu_rdy         (fu_rdy),

        .valid_in       (valid_in),
        .ready_in       (ready_in),
        .instr          (instr),

        .valid_out      (valid_out),
        .data_out       (data_out),

        .nr_reg         (nr_reg),
        .nr_valid       (nr_valid),

        .reg1_rdy       (reg1_rdy),
        .reg2_rdy       (reg2_rdy),
        .reg3_rdy       (reg3_rdy),
        .reg1_rdy_valid (reg1_rdy_valid),
        .reg2_rdy_valid (reg2_rdy_valid),
        .reg3_rdy_valid (reg3_rdy_valid),

        .flush          (flush)
    );

    // ------------------------
    // Clock
    // ------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100 MHz
    end

    // ------------------------
    // Main stimulus
    // ------------------------
    initial begin
        // Default init
        reset          = 1;
        fu_rdy         = 1'b1;   // FU always ready for now
        valid_in       = 1'b0;
        flush          = 1'b0;

        reg1_rdy       = '0;
        reg2_rdy       = '0;
        reg3_rdy       = '0;
        reg1_rdy_valid = 1'b0;
        reg2_rdy_valid = 1'b0;
        reg3_rdy_valid = 1'b0;

        instr          = '{default: '0};

        // Reset for a few cycles
        repeat (3) @(posedge clk);
        reset = 0;

        // --------------------
        // Enqueue a few instr
        // --------------------
        send_instr(7'd10, 7'd1, 7'd2, 32'h0000_0001); // prd=10, src1=1, src2=2
        send_instr(7'd11, 7'd3, 7'd4, 32'h0000_0002); // prd=11, src1=3, src2=4
        send_instr(7'd12, 7'd1, 7'd3, 32'h0000_0003); // prd=12, src1=1, src2=3

        // Let them sit one or two cycles
        repeat (5) @(posedge clk);

        // --------------------
        // Mark some regs ready
        // --------------------
        // Make src1=1 ready
        mark_reg_ready(7'd1);
        // Make src2=2 ready
        mark_reg_ready(7'd2);
        // Make src3=3 ready
        mark_reg_ready(7'd3);

        // Wait to see issues
        repeat (20) @(posedge clk);

        // --------------------
        // Test flush
        // --------------------
        $display("[%0t] Asserting flush", $time);
        flush = 1'b1;
        @(posedge clk);
        flush = 1'b0;

        repeat (10) @(posedge clk);

        $display("[%0t] TB done.", $time);
        $finish;
    end

    // ------------------------
    // Task: enqueue instruction
    // ------------------------
    task send_instr(
        input logic [6:0] prd,
        input logic [6:0] pr1,
        input logic [6:0] pr2,
        input logic [31:0] imm
    );
    begin
        // Wait until RS is ready to accept
        @(posedge clk);
        while (!ready_in) @(posedge clk);

        instr = '{default: '0};
        // Basic fields we know from rs.sv
        instr.prd        = prd;
        instr.pr1        = pr1;
        instr.pr2        = pr2;
        instr.pr1_ready  = 1'b0;
        instr.pr2_ready  = 1'b0;
        instr.imm        = imm;
        instr.rob_index  = 4'd1;      // arbitrary
        instr.Opcode     = 7'h33;     // pretend R-type
        instr.func3      = 3'b000;
        instr.func7      = 7'b0000000;

        valid_in = 1'b1;
        @(posedge clk);
        valid_in = 1'b0;

        // Clear instr to avoid X-propagation
        instr = '{default: '0};
    end
    endtask

    // ------------------------
    // Task: broadcast ready reg
    // (uses reg1_* channel; you can also use reg2/3)
    // ------------------------
    task mark_reg_ready(input logic [6:0] reg_id);
    begin
        @(posedge clk);
        reg1_rdy       = reg_id;
        reg1_rdy_valid = 1'b1;
        @(posedge clk);
        reg1_rdy_valid = 1'b0;
        reg1_rdy       = '0;
    end
    endtask

    // ------------------------
    // Simple monitors
    // ------------------------
    always @(posedge clk) begin
        if (nr_valid) begin
            $display("[%0t] nr_valid: mark PR %0d as not-ready", $time, nr_reg);
        end

        if (valid_out) begin
            $display("[%0t] ISSUE: Opcode=%h pd=%0d ps1=%0d ready1=%0b ps2=%0d ready2=%0b rob=%0d imm=%h fu=%0d",
                     $time,
                     data_out.Opcode,
                     data_out.pd,
                     data_out.ps1, data_out.ps1_ready,
                     data_out.ps2, data_out.ps2_ready,
                     data_out.rob_index,
                     data_out.imm,
                     data_out.fu);
        end
    end

    // ------------------------
    // Waveform dump
    // ------------------------
    initial begin
        $dumpfile("rs_tb.vcd");
        $dumpvars(0, rs_tb);
    end

endmodule
