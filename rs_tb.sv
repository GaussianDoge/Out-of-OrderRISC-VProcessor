`timescale 1ns/1ps
import types_pkg::*;

module rs_tb;

    // Clock / reset
    logic clk;
    logic reset;

    // DUT interface
    logic fu_rdy;

    // Upstream dispatch
    logic                 valid_in;
    logic                 ready_in;
    dispatch_pipeline_data instr;

    // Downstream issue
    logic                 valid_out;
    rs_data [1:0]         data_out;

    // New dest physical reg marked not ready
    logic [6:0]           nr_reg;
    logic                 nr_valid;

    // Reg ready updates (from retire / PRF)
    logic [6:0]           reg1_rdy, reg2_rdy, reg3_rdy;
    logic                 reg1_rdy_valid, reg2_rdy_valid, reg3_rdy_valid;

    // Flush
    logic                 flush;

    // ------------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------------
    rs dut (
        .clk             (clk),
        .reset           (reset),
        .fu_rdy          (fu_rdy),

        .valid_in        (valid_in),
        .ready_in        (ready_in),
        .instr           (instr),

        .valid_out       (valid_out),
        .data_out        (data_out),

        .nr_reg          (nr_reg),
        .nr_valid        (nr_valid),

        .reg1_rdy        (reg1_rdy),
        .reg2_rdy        (reg2_rdy),
        .reg3_rdy        (reg3_rdy),
        .reg1_rdy_valid  (reg1_rdy_valid),
        .reg2_rdy_valid  (reg2_rdy_valid),
        .reg3_rdy_valid  (reg3_rdy_valid),

        .flush           (flush)
    );

    // ------------------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;  // 10ns period

    // ------------------------------------------------------------------------
    // Helper tasks
    // ------------------------------------------------------------------------

    task automatic do_reset;
        begin
            reset           = 1'b1;
            fu_rdy          = 1'b0;
            valid_in        = 1'b0;
            flush           = 1'b0;

            reg1_rdy        = '0;
            reg2_rdy        = '0;
            reg3_rdy        = '0;
            reg1_rdy_valid  = 1'b0;
            reg2_rdy_valid  = 1'b0;
            reg3_rdy_valid  = 1'b0;

            instr = '{default: '0};

            repeat (3) @(posedge clk);
            reset = 1'b0;
            @(posedge clk);
            $display("[%0t] Reset deasserted", $time);
        end
    endtask

    // Dispatch instruction into RS (1-cycle valid pulse)
    task automatic dispatch_instr(
        input [6:0] prd,
        input [6:0] pr1,
        input       pr1_ready,
        input [6:0] pr2,
        input       pr2_ready,
        input [3:0] rob_index,
        input [6:0] opcode
    );
        begin
            // Wait until RS says it has space
            @(posedge clk);
            while (!ready_in) @(posedge clk);

            valid_in         <= 1'b1;
            instr.Opcode     <= opcode;
            instr.prd        <= prd;
            instr.pr1        <= pr1;
            instr.pr1_ready  <= pr1_ready;
            instr.pr2        <= pr2;
            instr.pr2_ready  <= pr2_ready;
            instr.imm        <= 32'hDEAD_BEEF;
            instr.rob_index  <= rob_index;

            $display("[%0t] DISPATCH: prd=%0d pr1=%0d(%0b) pr2=%0d(%0b) rob=%0d",
                     $time, prd, pr1, pr1_ready, pr2, pr2_ready, rob_index);

            @(posedge clk);
            valid_in         <= 1'b0;
            instr            <= '{default: '0};
        end
    endtask

    // *** Key change: update PR readiness BEFORE the issue edge ***
    // We drive reg*_rdy / reg*_rdy_valid on the NEGEDGE, then
    // leave them stable through the following POSEDGE where RS issues.
    task automatic mark_reg_ready_before_issue(
        input [6:0] r1,
        input       v1,
        input [6:0] r2,
        input       v2,
        input [6:0] r3,
        input       v3
    );
        begin
            @(negedge clk);  // "CDB" / retire happens in second half of cycle
            reg1_rdy       <= r1;
            reg2_rdy       <= r2;
            reg3_rdy       <= r3;
            reg1_rdy_valid <= v1;
            reg2_rdy_valid <= v2;
            reg3_rdy_valid <= v3;

            $display("[%0t] UPDATE PR READY: r1=%0d(v=%0b) r2=%0d(v=%0b) r3=%0d(v=%0b)",
                     $time, r1, v1, r2, v2, r3, v3);

            // Keep valid for one full posedge so always_comb can update rs_table
            @(posedge clk);
            reg1_rdy_valid <= 1'b0;
            reg2_rdy_valid <= 1'b0;
            reg3_rdy_valid <= 1'b0;
        end
    endtask

    // Wait for one issue and dump data_out[1]
    task automatic wait_for_issue(input string tag);
        int cycles;
        begin
            cycles = 0;
            while (!valid_out && cycles < 20) begin
                @(posedge clk);
                cycles++;
            end
            if (!valid_out) begin
                $error("[%0t] TIMEOUT waiting for issue: %s", $time, tag);
            end else begin
                $display("[%0t] ISSUE (%s): prd=%0d pr1=%0d rdy1=%0b pr2=%0d rdy2=%0b fu=%0b rob=%0d age=%0d",
                    $time, tag,
                    data_out[1].prd,
                    data_out[1].pr1, data_out[1].pr1_ready,
                    data_out[1].pr2, data_out[1].pr2_ready,
                    data_out[1].fu,
                    data_out[1].rob_index,
                    data_out[1].age);
                @(posedge clk);
            end
        end
    endtask

    task automatic do_flush;
        begin
            @(posedge clk);
            flush <= 1'b1;
            $display("[%0t] FLUSH asserted", $time);
            @(posedge clk);
            flush <= 1'b0;
            $display("[%0t] FLUSH deasserted", $time);
        end
    endtask

    // ------------------------------------------------------------------------
    // Simple monitor
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        $display("[%0t] rst=%0b flush=%0b valid_in=%0b ready_in=%0b fu_rdy=%0b valid_out=%0b nr_valid=%0b nr_reg=%0d",
                 $time, reset, flush, valid_in, ready_in, fu_rdy, valid_out, nr_valid, nr_reg);
    end

    // ------------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------------
    initial begin
        // Init
        reset           = 1'b0;
        fu_rdy          = 1'b0;
        valid_in        = 1'b0;
        flush           = 1'b0;

        reg1_rdy        = '0;
        reg2_rdy        = '0;
        reg3_rdy        = '0;
        reg1_rdy_valid  = 1'b0;
        reg2_rdy_valid  = 1'b0;
        reg3_rdy_valid  = 1'b0;

        instr           = '{default: '0};

        // 1) Reset
        do_reset();

        // 2) Insert one instr with both operands NOT ready -> no issue
        dispatch_instr(7'd10, 7'd1, 1'b0, 7'd2, 1'b0, 4'd1, 7'h33);
        fu_rdy = 1'b1;   // FU ready but operands not ready yet
        repeat (3) @(posedge clk);
        if (valid_out)
            $error("[%0t] ERROR: Issued with operands not ready", $time);
        else
            $display("[%0t] OK: No issue when PRs not ready", $time);

        // 3) Mark pr1 ready in a cycle BEFORE issue
        mark_reg_ready_before_issue(7'd1, 1'b1, 7'd0, 1'b0, 7'd0, 1'b0);
        // FU still ready; only pr1 ready -> still no issue
        repeat (2) @(posedge clk);
        if (valid_out)
            $error("[%0t] ERROR: Issued when only pr1 ready", $time);
        else
            $display("[%0t] OK: No issue when only one operand ready", $time);

        // 4) Mark pr2 ready BEFORE issue
        mark_reg_ready_before_issue(7'd0, 1'b0, 7'd2, 1'b1, 7'd0, 1'b0);
        // Now on the next posedge, BOTH operands are ready and fu_rdy=1 -> issue
        wait_for_issue("single_instr");

        // 5) Check nr_reg / nr_valid on new dispatch
        dispatch_instr(7'd20, 7'd5, 1'b0, 7'd6, 1'b0, 4'd2, 7'h33);
        @(posedge clk);
        if (!nr_valid || nr_reg != 7'd20)
            $error("[%0t] ERROR: nr_reg/nr_valid mismatch", $time);
        else
            $display("[%0t] OK: nr_reg=%0d nr_valid=%0b", $time, nr_reg, nr_valid);

        // 6) Flush behavior
        dispatch_instr(7'd21, 7'd7, 1'b0, 7'd8, 1'b0, 4'd3, 7'h33);
        dispatch_instr(7'd22, 7'd9, 1'b0, 7'd10, 1'b0, 4'd4, 7'h33);
        do_flush();

        // After flush, even if we mark regs ready, nothing should issue
        mark_reg_ready_before_issue(7'd7, 1'b1, 7'd8, 1'b1, 7'd9, 1'b1);
        repeat (4) @(posedge clk);
        if (valid_out)
            $error("[%0t] ERROR: Issued after flush", $time);
        else
            $display("[%0t] OK: No issue after flush", $time);

        // 7) Two instructions A and B; make B's operands ready first
        //    A: prd 30, src 30/31
        //    B: prd 40, src 40/41
        dispatch_instr(7'd30, 7'd30, 1'b0, 7'd31, 1'b0, 4'd5, 7'h33);  // A
        dispatch_instr(7'd40, 7'd40, 1'b0, 7'd41, 1'b0, 4'd6, 7'h33);  // B

        // Mark B ready first (both PRs), BEFORE issue
        mark_reg_ready_before_issue(7'd40, 1'b1, 7'd41, 1'b1, 7'd0, 1'b0);
        fu_rdy = 1'b1;
        wait_for_issue("B_should_issue_first");

        // Now mark A ready
        mark_reg_ready_before_issue(7'd30, 1'b1, 7'd31, 1'b1, 7'd0, 1'b0);
        wait_for_issue("A_should_issue_second");

        $display("[%0t] All tests done", $time);
        #20;
        $finish;
    end

endmodule
