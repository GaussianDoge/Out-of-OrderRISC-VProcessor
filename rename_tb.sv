import types_pkg::*;

// 2. TESTBENCH
module rename_tb;

    // Signals
    logic clk;
    logic reset;

    // Upstream (Decode -> Rename)
    logic valid_in;
    decode_data data_in;
    logic ready_in;

    // From ROB (Commit/Retire)
    logic write_en;
    logic [6:0] rob_data_in;

    // Mispredict
    logic mispredict;

    // Downstream (Rename -> Dispatch/Issue)
    rename_data data_out;
    logic valid_out;
    logic ready_out;

    // DUT Instantiation
    rename dut (
        .clk        (clk),
        .reset      (reset),
        .valid_in   (valid_in),
        .data_in    (data_in),
        .ready_in   (ready_in),
        .write_en   (write_en),
        .rob_data_in(rob_data_in),
        .mispredict (mispredict),
        .data_out   (data_out),
        .valid_out  (valid_out),
        .ready_out  (ready_out)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Safety Watchdog
    initial begin
        #30000; // Increased timeout for longer tests
        $display("\n[TB] ERROR: Simulation Timed Out! Potential deadlock or infinite loop.");
        $stop;
    end

    // Constants
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_ALU    = 7'b0110011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;

    // Tasks
    
    task sys_reset();
        $display("\n[TB] --- System Reset ---");
        reset      = 1;
        valid_in   = 0;
        data_in    = '0;
        write_en   = 0;
        rob_data_in= '0;
        mispredict = 0;
        ready_out  = 0;
        repeat (5) @(posedge clk);
        #1; // Align away from edge
        reset = 0;
        @(posedge clk);
        ready_out = 1;   // default "consumer ready"
    endtask

    task send_inst(
        input  logic [6:0] opcode,
        input  logic [4:0] rd,
        input  logic [4:0] rs1,
        input  logic [4:0] rs2,
        output logic [6:0] allocated_pd
    );
        int timeout_ctr;
        timeout_ctr = 0;

        // Wait for DUT to be ready (Handle Empty Free List case)
        while (!ready_in) begin
            @(posedge clk);
            timeout_ctr++;
            if (timeout_ctr > 20) begin
                $error("[TB] ERROR: Time out waiting for ready_in. Free List likely Empty/Deadlocked!");
                $stop;
            end
        end
        
        // Drive Inputs slightly after clock edge to avoid races
        #1;
        valid_in      = 1;
        data_in.pc    = 32'h1000;
        data_in.rs1   = rs1;
        data_in.rs2   = rs2;
        data_in.rd    = rd;
        data_in.imm   = 32'h0;
        data_in.ALUOp = 3'b0;
        data_in.Opcode= opcode;
        data_in.fu    = 2'b0;
        data_in.func3 = 3'b0;
        data_in.func7 = 7'b0;
        ready_out     = 1; 

        // Handshake
        @(posedge clk);
        #1;
        valid_in = 0;
        
        // Wait for output valid
        while(!valid_out) @(posedge clk);
        
        allocated_pd = data_out.pd_new;
        $display("[TB] Issued Inst: Op=%b Rd=%0d -> Alloc P%0d", opcode, rd, data_out.pd_new);
    endtask

    task retire_reg(input logic [6:0] preg);
        int   ctr_before, ctr_after;
        logic internal_we;
        
        $display("[TB] RETIRING Physical Register: %0d", preg);
        
        // Peek internal state before
        ctr_before = dut.u_free_list.ctr; 
        
        @(posedge clk);
        #1;
        write_en    = 1;
        rob_data_in = preg;
        
        @(posedge clk);
        #1;
        write_en    = 0;
        rob_data_in = '0;
        
        // Wait one cycle for logic to settle
        @(posedge clk); 
        #1; 
        
        // Peek internal state after
        ctr_after   = dut.u_free_list.ctr;
        internal_we = dut.fl_write_en;
        
        $display("[TB] DEBUG: Free List CTR before=%0d, after=%0d", ctr_before, ctr_after);
        
        if (ctr_after == ctr_before) begin
            $error("[TB] FAILURE: Retire did not increment free list counter! Logic ignored the write.");
            $display("[TB] DEBUG HINT: fl_write_en inside DUT was seen as: %b", internal_we);
        end else begin
            $display("[TB] SUCCESS: Retire accepted. Counter incremented.");
        end
    endtask

    // Local variables for tests
    logic   [6:0] captured_pd;
    logic   [6:0] pd_first, pd_second;
    logic   [6:0] p1_allocation;
    logic   [6:0] last_speculative_pd;
    integer i;
    logic   found_recycled;

    // Main Test Sequence
    initial begin
        // TEST 1: First writer (x5 depends on x1,x2)
        sys_reset();
        $display("\n[TB] Test 1: First writer (ALU x5,x1,x2)");

        send_inst(OP_ALU, 5'd5, 5'd1, 5'd2, pd_first);
        // Assuming reset map: x0->P0, x1->P1, ..., x31->P31
        assert(data_out.ps1   == 6'd1)  else $error("Test1: ps1 != map[x1]==1 (got %0d)", data_out.ps1);
        assert(data_out.ps2   == 6'd2)  else $error("Test1: ps2 != map[x2]==2 (got %0d)", data_out.ps2);
        assert(data_out.pd_old== 6'd5)  else $error("Test1: pd_old != map[x5]==5 (got %0d)", data_out.pd_old);
        assert(pd_first != 0 && pd_first != 5)
            else $error("Test1: pd_new should be non-zero and != old mapping (got %0d)", pd_first);
        $display("[TB] Test 1 PASSED.");

        // TEST 2: Dependent writer (x6 reads new x5 mapping)
        $display("\n[TB] Test 2: Dependent writer (ALU x6,x5,0)");

        send_inst(OP_ALU, 5'd6, 5'd5, 5'd0, pd_second);

        assert(data_out.ps1 == pd_first)
            else $error("Test2: ps1 (x5) != new mapping pd_first=%0d (got %0d)", pd_first, data_out.ps1);
        assert(data_out.pd_old == 6'd6)
            else $error("Test2: pd_old != map[x6]==6 (got %0d)", data_out.pd_old);
        assert(pd_second != 0 && pd_second != pd_first)
            else $error("Test2: pd_new_2 must be non-zero and != pd_new_1 (got %0d)", pd_second);
        $display("[TB] Test 2 PASSED.");

        // TEST 3: Backpressure on ready_out
        $display("\n[TB] Test 3: Backpressure on ready_out");
        begin
            logic [6:0] ps1_hold, ps2_hold, pd_hold;
            int k;

            // Make sure upstream is allowed to fire
            wait(ready_in);
            @(posedge clk); #1;

            // Stall downstream
            ready_out = 0;

            // Issue a writer (e.g., ALU x7,x1,x6)
            valid_in      = 1;
            data_in.pc    = 32'h2000;
            data_in.rs1   = 5'd1;
            data_in.rs2   = 5'd6;
            data_in.rd    = 5'd7;
            data_in.imm   = 32'h0;
            data_in.ALUOp = 3'b0;
            data_in.Opcode= OP_ALU;
            data_in.fu    = 2'b0;
            data_in.func3 = 3'b0;
            data_in.func7 = 7'b0;

            @(posedge clk); #1;
            valid_in = 0;

            // Wait until rename produces output
            while (!valid_out) @(posedge clk);

            // Capture outputs
            ps1_hold = data_out.ps1;
            ps2_hold = data_out.ps2;
            pd_hold  = data_out.pd_new;

            // Check that valid_out and payload stay stable while ready_out=0
            for (k = 0; k < 5; k++) begin
                @(posedge clk); #1;
                assert(valid_out)
                    else $error("Test3: valid_out deasserted while backpressured.");
                assert(data_out.ps1 == ps1_hold)
                    else $error("Test3: ps1 changed under backpressure (exp %0d, got %0d)",
                                ps1_hold, data_out.ps1);
                assert(data_out.ps2 == ps2_hold)
                    else $error("Test3: ps2 changed under backpressure (exp %0d, got %0d)",
                                ps2_hold, data_out.ps2);
                assert(data_out.pd_new == pd_hold)
                    else $error("Test3: pd_new changed under backpressure (exp %0d, got %0d)",
                                pd_hold, data_out.pd_new);
            end

            // Release backpressure
            ready_out = 1;
            @(posedge clk); #1;
            @(posedge clk); #1;

            assert(!valid_out)
                else $error("Test3: valid_out did not deassert after ready_out=1.");
            $display("[TB] Test 3 PASSED.");
        end

        // TEST 4: STORE x2 -> 0(x1) (no pd allocation)
        $display("\n[TB] Test 4: STORE x2 -> 0(x1) (no pd allocation)");
        begin
            logic [6:0] pd_store;
            send_inst(OP_STORE, 5'd0, 5'd1, 5'd2, pd_store); // rd is don't-care for store

            // With initial map and we never wrote x1/x2 as rd, they should be 1 and 2.
            assert(data_out.ps1 == 6'd1)
                else $error("Test4: STORE ps1 != map[x1]==1 (got %0d)", data_out.ps1);
            assert(data_out.ps2 == 6'd2)
                else $error("Test4: STORE ps2 != map[x2]==2 (got %0d)", data_out.ps2);
            assert(pd_store == 0)
                else $error("Test4: STORE pd_new should be 0 (no alloc), got %0d", pd_store);
            assert(data_out.pd_old == 0)
                else $error("Test4: STORE pd_old should be map[x0]==0, got %0d", data_out.pd_old);
            $display("[TB] Test 4 PASSED.");
        end

        // TEST 5: rd == x0 (no pd allocation)
        $display("\n[TB] Test 5: rd == x0 (no pd allocation)");
        begin
            logic [6:0] pd_x0;
            send_inst(OP_ALU, 5'd0, 5'd1, 5'd2, pd_x0);

            assert(pd_x0 == 0)
                else $error("Test5: x0 write: pd_new should be 0 (no alloc), got %0d", pd_x0);
            assert(data_out.pd_old == 0)
                else $error("Test5: x0 write: pd_old should be map[x0]==0, got %0d", data_out.pd_old);
            $display("[TB] Test 5 PASSED.");
        end

        // TEST 6: Retire PD=50 and check reuse via rename (wrap-around)
        $display("\n[TB] === Test 6: Retire P50 and check reuse via rename ===");
        begin
            // Flush until we hit P50
            $display("[TB] Flushing Free List up to P50...");
            do begin
                send_inst(OP_ALU, 5'd5, 5'd0, 5'd0, captured_pd);
            end while (captured_pd != 7'd50);
            
            $display("[TB] P50 allocated. Now let's retire P50 back to the free list.");
            retire_reg(7'd50);

            // Consume free list to force wrap-around and see P50 again
            $display("[TB] Consuming free list to force wrap-around...");
            found_recycled = 0;
            for (i = 0; i < 110; i++) begin
                send_inst(OP_ALU, 5'd6, 5'd0, 5'd0, captured_pd);
                if (captured_pd == 7'd50) begin
                    found_recycled = 1;
                    $display("[TB] SUCCESS: P50 was successfully recycled and re-allocated at iteration %0d!", i);
                    break;
                end
            end

            if (!found_recycled)
                $error("[TB] FAILURE: P50 never reappeared after retiring!");
        end

        // TEST 7: Branch Misprediction Recovery (map + free_list)
        sys_reset(); // fresh state for a clean mispredict experiment
        $display("\n[TB] Test 7: Branch Misprediction Recovery");

        // Setup R1 -> known mapping
        send_inst(OP_ALU, 5'd1, 5'd0, 5'd0, p1_allocation); 
        $display("[TB] Setup: R1 is mapped to P%0d", p1_allocation);
        
        // Branch (Checkpoint)
        send_inst(OP_BRANCH, 5'd0, 5'd1, 5'd2, captured_pd); 
        
        // Speculative pollution: remap R1
        send_inst(OP_ALU, 5'd1, 5'd0, 5'd0, captured_pd); 
        last_speculative_pd = captured_pd;
        $display("[TB] Speculative: R1 re-mapped to P%0d", captured_pd);
        
        // Trigger Mispredict
        $display("[TB] *** TRIGGERING MISPREDICT ***");
        @(posedge clk); #1;
        mispredict = 1;
        @(posedge clk); #1;
        mispredict = 0;
        @(posedge clk);

        // Verify free_list pointer behavior by another allocation
        $display("[TB] Checking Post-Recovery Allocation...");
        send_inst(OP_ALU, 5'd11, 5'd0, 5'd0, captured_pd);
        if (captured_pd > last_speculative_pd && captured_pd < last_speculative_pd + 5)
            $warning("[TB] Warning: Allocation continued forward (heuristic).");
        else
            $display("[TB] Free List Pointer seems to have jumped back (Good).");

        // Check map table restoration for R1
        $display("[TB] Checking Map Table Restoration for R1...");
        wait(ready_in);
        @(posedge clk); #1;
        valid_in      = 1;
        data_in.pc    = 32'h1000;
        data_in.rs1   = 5'd1;
        data_in.rs2   = 5'd0;
        data_in.rd    = 5'd0; 
        data_in.imm   = 32'h0;
        data_in.ALUOp = 3'b0;
        data_in.Opcode= OP_ALU;
        data_in.fu    = 2'b0;
        data_in.func3 = 3'b0;
        data_in.func7 = 7'b0;
        ready_out     = 1;

        @(posedge clk); #1;
        valid_in = 0;
        
        while (!valid_out) @(posedge clk);
        
        if (data_out.ps1 == p1_allocation) 
            $display("[TB] SUCCESS: R1 map restored to P%0d", p1_allocation);
        else 
            $error("[TB] FAILURE: R1 map is P%0d, expected P%0d", data_out.ps1, p1_allocation);

        #100;
        $display("\n[TB] All Tests Complete");
        $stop;
    end

endmodule
