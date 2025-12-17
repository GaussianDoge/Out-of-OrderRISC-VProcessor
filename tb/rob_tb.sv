`timescale 1ns/1ps
import types_pkg::*;

module rob_tb;

    // DUT I/O
    logic        clk, reset;
    logic        write_en;
    logic [6:0]  pd_new_in, pd_old_in;
    logic [31:0] pc_in;

    // FU completion signals
    logic        fu_alu_done;
    logic        fu_b_done;
    logic        fu_mem_done;
    logic [4:0]  rob_fu_alu;
    logic [4:0]  rob_fu_b;
    logic [4:0]  rob_fu_mem;

    // Branch FU → ROB (inputs)
    logic        br_mispredict;
    logic [4:0]  br_mispredict_tag;

    // ROB → global (outputs)
    logic        mispredict;
    logic [4:0]  mispredict_tag;

    // DUT outputs
    logic [6:0]  preg_old;
    logic        valid_retired;
    logic        full;
    logic [4:0]  ptr;          // write pointer from DUT (tail index)

    localparam int CLK_PERIOD = 10;

    // Clock
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Helper: increment mod 16
    function automatic [4:0] inc16(input [4:0] x);
        return (x == 5'd15) ? 5'd0 : (x + 5'd1);
    endfunction

    // TB mirrors of head/tail so we don't rely on DUT internals for protocol
    logic [4:0] tb_wptr;  // next tag to allocate (tail mirror)
    logic [4:0] tb_rptr;  // next tag expected to retire (head mirror)

    // Occupancy calculation
    function automatic int occ(input [4:0] r, input [4:0] w);
        return (w >= r) ? (w - r) : (5'd16 - r + w);
    endfunction

    // Reset
    task automatic apply_reset;
        begin
            reset          = 1;
            write_en       = 0;
            pd_new_in      = '0;
            pd_old_in      = '0;
            pc_in          = '0;

            fu_alu_done    = 0;
            fu_b_done      = 0;
            fu_mem_done    = 0;
            rob_fu_alu     = '0;
            rob_fu_b       = '0;
            rob_fu_mem     = '0;

            br_mispredict      = 0;
            br_mispredict_tag  = '0;

            tb_wptr        = '0;
            tb_rptr        = '0;

            repeat (3) @(posedge clk);
            reset = 0;
            @(posedge clk);

            if (occ(tb_rptr, tb_wptr) != 0 || full)
                $fatal(1, "[RESET] expected empty ROB, got occ=%0d full=%0b",
                       occ(tb_rptr, tb_wptr), full);

            $display("[%0t] Reset done.", $time);
        end
    endtask

    // Allocate: write into ROB tail
    task automatic alloc(output [4:0] tag_o,
                         input  [6:0] pd_new,
                         input  [6:0] pd_old,
                         input  [31:0] pc);
        begin
            if (full)
                $fatal(1, "[ALLOC] ROB full unexpectedly (occ=%0d)",
                       occ(tb_rptr, tb_wptr));

            tag_o     = tb_wptr;
            pd_new_in = pd_new;
            pd_old_in = pd_old;
            pc_in     = pc;
            write_en  = 1;

            @(posedge clk);           // allocate on this edge
            write_en  = 0;
            tb_wptr   = inc16(tb_wptr);

            $display("[%0t] ALLOC tag=%0d pc=0x%08h (TB occ-> %0d)",
                     $time, tag_o, pc, occ(tb_rptr, tb_wptr));

            @(posedge clk);           // cadence
        end
    endtask

    // Mark ROB entry complete via ALU FU
    task automatic complete_tag(input [4:0] tag);
        begin
            rob_fu_alu   = tag;
            fu_alu_done  = 1;
            @(posedge clk);
            fu_alu_done  = 0;
            rob_fu_alu   = '0;
            $display("[%0t] COMPLETE tag=%0d", $time, tag);
        end
    endtask

    // Expect no retire next cycle
    task automatic expect_no_retire_next;
        begin
            @(posedge clk);
            if (valid_retired)
                $fatal(1, "[NO_RET] Retired unexpectedly (head incomplete)");
        end
    endtask

    // Expect a specific retire (head only)
    task automatic expect_retire(input [4:0] exp_tag);
        int waitcycles = 0;
        begin
            // Sanity: TB model's head should match expected tag
            if (tb_rptr !== exp_tag) begin
                $fatal(1,
                    "[RETIRE] TB head (%0d) != exp_tag (%0d) before retire",
                    tb_rptr, exp_tag);
            end

            while (!valid_retired) begin
                @(posedge clk);
                if (waitcycles++ > 20) begin
                    $fatal(1,
                      "[RETIRE] Timeout waiting for tag %0d (TB head=%0d, TB tail=%0d, occ=%0d)",
                      exp_tag, tb_rptr, tb_wptr, occ(tb_rptr, tb_wptr));
                end
            end

            $display("[%0t] RETIRE tag=%0d", $time, tb_rptr);

            // TB head mirror advances on a retire
            tb_rptr = inc16(tb_rptr);
            @(posedge clk); // consume pulse
        end
    endtask

    // Mispredict (flush younger-than-branch) - **strengthened**
    task automatic do_mispredict(input [4:0] tag);
        begin
            $display("[%0t] ---- MISPREDICT at tag=%0d ----", $time, tag);

            // Drive mispredict inputs from branch FU
            br_mispredict_tag = tag;
            br_mispredict     = 1;

            // On this cycle, ROB must pulse mispredict with correct tag
            @(posedge clk);
            assert (mispredict == 1'b1 && mispredict_tag == tag)
                else $fatal(1,
                    "[MISPREDICT] expected mispredict=1 tag=%0d, got mispredict=%0b tag=%0d",
                    tag, mispredict, mispredict_tag);

            // Drop inputs, ROB should recover and deassert mispredict
            br_mispredict     = 0;
            br_mispredict_tag = '0;

            @(posedge clk);

            assert(mispredict == 1'b0)
                else $fatal(1,
                    "[MISPREDICT] mispredict output should be deasserted after recovery");

            // TB tail mirror becomes branch+1
            tb_wptr = inc16(tag);
        end
    endtask

    // DUT
    rob dut (
        .clk,
        .reset,

        // from rename
        .write_en,
        .pd_new_in,
        .pd_old_in,
        .pc_in,

        // from FUs
        .fu_alu_done,
        .fu_b_done,
        .fu_mem_done,
        .rob_fu_alu,
        .rob_fu_b,
        .rob_fu_mem,
        .br_mispredict      (br_mispredict),
        .br_mispredict_tag  (br_mispredict_tag),

        // outputs
        .preg_old,
        .valid_retired,
        .mispredict,
        .mispredict_tag,
        .full,
        .ptr
    );

    // Sanity checks on internal ctr
    always @(posedge clk) if (!reset) begin
        assert (dut.ctr <= 16) else $fatal(1, "ctr overflow: %0d", dut.ctr);
        assert (full == (dut.ctr == 16))
            else $fatal(1, "full mismatch: full=%0b ctr=%0d",
                        full, dut.ctr);
    end

    logic [6:0] exp_pd_old [0:2];
    logic [6:0] seen_pd_old[0:2];

    // Tests 
    initial begin
        logic [4:0] t0, t1, t2, t3, t4, t5, newtag;
        int  need_to_full;
        int  push_to_nearfull;

        apply_reset();

        // TEST 1: OoO completion, in-order retirement
        $display("TEST 1: OoO completion, in-order retirement");

        alloc(t0, 7'h20, 7'h10, 32'h0000_1000); // tag 0
        alloc(t1, 7'h21, 7'h11, 32'h0000_1004); // tag 1
        alloc(t2, 7'h22, 7'h12, 32'h0000_1008); // tag 2

        // Complete out-of-order: t1 then t0
        complete_tag(t1);
        expect_no_retire_next;

        complete_tag(t0);
        expect_retire(t0);
        expect_retire(t1);

        // Finally complete and retire t2
        complete_tag(t2);
        expect_retire(t2);

        if (occ(tb_rptr, tb_wptr) != 0)
            $fatal(1, "[TEST1] ROB not empty at end (occ=%0d)",
                   occ(tb_rptr, tb_wptr));


        // TEST 2: Mispredict flush (younger-than-branch squashed)
        $display("TEST 2: Mispredict flush");

        alloc(t3, 7'h33, 7'h23, 32'h0000_2000); // branch
        alloc(t4, 7'h34, 7'h24, 32'h0000_2004); // younger
        alloc(t5, 7'h35, 7'h25, 32'h0000_2008); // younger

        // Complete a younger entry that will be flushed
        complete_tag(t5);
        expect_no_retire_next;

        // Flush younger than branch
        do_mispredict(t3);

        // Only the branch remains live at head; complete & retire it
        complete_tag(t3);
        expect_retire(t3);

        // First new alloc should reuse tag = t3+1
        alloc(newtag, 7'h44, 7'h34, 32'h0000_200C);
        assert (newtag == inc16(t3))
            else $fatal(1,
                "[TEST2] expected new alloc at tag=%0d, got=%0d",
                inc16(t3), newtag);


        // TEST 3: Wrap-around / full behavior
        $display("TEST 3: Wrap-around / full behavior");

        // Fill up to near full based on remaining occupancy
        need_to_full     = 16 - occ(tb_rptr, tb_wptr);
        push_to_nearfull = need_to_full - 1;

        for (int i = 0; i < push_to_nearfull; i++) begin
            alloc(newtag, 7'h50 + i, 7'h60, 32'h0000_3000 + i);
        end

        // One more to go full
        alloc(newtag, 7'h5F, 7'h6F, 32'h0000_3FFF);
        assert (full)
            else $fatal(1,
                "[TEST3] ROB should be full (occ=%0d)",
                occ(tb_rptr, tb_wptr));

        // Retire two heads
        complete_tag(tb_rptr);
        expect_retire(tb_rptr);

        complete_tag(tb_rptr);
        expect_retire(tb_rptr);

        assert (!full)
            else $fatal(1,
                "[TEST3] still full after two retires (occ=%0d)",
                occ(tb_rptr, tb_wptr));

        // Allocate again - should succeed now
        alloc(newtag, 7'h70, 7'h60, 32'h0000_4000);
        
        // TEST 4: Mispredict with branch not at head (middle of ROB)
        $display("TEST 4: Mispredict with branch not at head");

        apply_reset();  // fresh ROB & TB state

        // Layout: t0 (oldest), t1, t2 (branch), t3 (younger)
        alloc(t0, 7'h10, 7'h01, 32'h0000_4000); // tag 0
        alloc(t1, 7'h11, 7'h02, 32'h0000_4004); // tag 1
        alloc(t2, 7'h12, 7'h03, 32'h0000_4008); // tag 2 (branch)
        alloc(t3, 7'h13, 7'h04, 32'h0000_400C); // tag 3 (younger)

        // Complete a younger entry (t3) - should NOT retire yet
        complete_tag(t3);
        expect_no_retire_next;

        // Now mispredict at t2 (branch in the middle)
        do_mispredict(t2);

        // After mispredict:
        // - ROB should logically contain t0, t1, t2
        // - TB model: head = 0, tail = inc16(2) = 3, so occ = 3
        if (occ(tb_rptr, tb_wptr) != 3)
            $fatal(1,
              "[TEST4] expected occ=3 after mispredict at mid-ROB (t2), got occ=%0d",
              occ(tb_rptr, tb_wptr));

        // Now complete and retire t0, t1, t2 in order.
        // Note: tb_rptr always equals the next expected retire tag by construction.
        complete_tag(t0);
        expect_retire(t0);

        complete_tag(t1);
        expect_retire(t1);

        complete_tag(t2);
        expect_retire(t2);

        if (occ(tb_rptr, tb_wptr) != 0)
            $fatal(1, "[TEST4] ROB not empty at end (occ=%0d)",
                   occ(tb_rptr, tb_wptr));

        // Next allocation should reuse tag = inc16(t2) = 3
        alloc(newtag, 7'h20, 7'h05, 32'h0000_4010);
        if (newtag != inc16(t2))
            $fatal(1,
              "[TEST4] expected next alloc tag=%0d after flush+retire, got=%0d",
              inc16(t2), newtag);
        else
            $display("TEST 4 PASS: mid-ROB mispredict flushed younger, preserved older + branch, tags reused correctly.");

        // TEST 5: Free-list interface (preg_old / valid_retired)
        $display("TEST 5: preg_old / valid_retired sequence");

        apply_reset();

        // Allocate 3 entries with distinct pd_old_in values
        exp_pd_old[0] = 7'h31;
        exp_pd_old[1] = 7'h32;
        exp_pd_old[2] = 7'h33;

        alloc(t0, 7'h40, exp_pd_old[0], 32'h0000_5000);
        alloc(t1, 7'h41, exp_pd_old[1], 32'h0000_5004);
        alloc(t2, 7'h42, exp_pd_old[2], 32'h0000_5008);

        // RETIRE t0
        complete_tag(t0);
        @(posedge clk);
        if (!valid_retired)
            $fatal(1, "[TEST5] expected valid_retired on first retire (t0)");
        seen_pd_old[0] = preg_old;
        if (seen_pd_old[0] != exp_pd_old[0])
            $fatal(1,
              "[TEST5] preg_old mismatch on first retire: expected %0d got %0d",
              exp_pd_old[0], seen_pd_old[0]);
        tb_rptr = inc16(tb_rptr);     // <-- advance TB head
        @(posedge clk);               // consume pulse

        // RETIRE t1
        complete_tag(t1);
        @(posedge clk);
        if (!valid_retired)
            $fatal(1, "[TEST5] expected valid_retired on second retire (t1)");
        seen_pd_old[1] = preg_old;
        if (seen_pd_old[1] != exp_pd_old[1])
            $fatal(1,
              "[TEST5] preg_old mismatch on second retire: expected %0d got %0d",
              exp_pd_old[1], seen_pd_old[1]);
        tb_rptr = inc16(tb_rptr);     // <-- advance TB head
        @(posedge clk);

        // RETIRE t2
        complete_tag(t2);
        @(posedge clk);
        if (!valid_retired)
            $fatal(1, "[TEST5] expected valid_retired on third retire (t2)");
        seen_pd_old[2] = preg_old;
        if (seen_pd_old[2] != exp_pd_old[2])
            $fatal(1,
              "[TEST5] preg_old mismatch on third retire: expected %0d got %0d",
              exp_pd_old[2], seen_pd_old[2]);
        tb_rptr = inc16(tb_rptr);     // <-- advance TB head
        @(posedge clk);

        if (occ(tb_rptr, tb_wptr) != 0)
            $fatal(1, "[TEST5] ROB not empty at end (occ=%0d)",
                   occ(tb_rptr, tb_wptr));
        else
            $display("TEST 5 PASS: preg_old and valid_retired pulse in correct order.");

        $display("[PASS] All ROB tests completed.");
        $finish;
    end

endmodule
