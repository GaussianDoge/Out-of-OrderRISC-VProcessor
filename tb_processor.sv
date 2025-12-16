`timescale 1ns / 1ps

module tb_processor;

    // Clock and reset
    logic clk;
    logic reset;

    // DUT
    processor dut (
        .clk   (clk),
        .reset (reset)
    );

    // Clock generation: 100 MHz (10 ns period)
    initial begin
        clk = 1'b0;
        forever #2 clk = ~clk;
    end

    // -----------------------------------------------------------------------
    // DEBUG: Runtime Monitor
    // -----------------------------------------------------------------------
    // This block prints the PC and ROB status every cycle.
    // If the simulation is stuck in a loop, you will see the last printed PC.
    int count = 1;
    always @(posedge clk) begin
        if (!reset) begin
//            $display("Time: %0t | PC: %h | ROB Head: %0d | ROB Tail: %0d | LSQ Count: %0d", 
//                     $time, 
//                     dut.pc, 
//                     dut.u_rob.head, 
//                     dut.u_rob.ptr,  // Tail/Alloc pointer
//                     dut.dispatch_unit.lsq_dispatch_rob_tag // Or LSQ counter if available
//                    );
            logic [6:0] pr_x7;
            logic [31:0] val_x7;
            logic [6:0] pr_x28;
            logic [31:0] val_x28;
            
            pr_x7 = dut.rename_unit.map[5'd7];
            val_x7 = dut.PRF.phy_reg[pr_x7];
            
            
            pr_x28 = dut.rename_unit.map[5'd28];
            val_x28 = dut.PRF.phy_reg[pr_x28];

            if (dut.mispredict) begin
                $display("============= Mispredict #%0d =============", count);
                $display("X7: phys %0d = 0x%08h (%0d)", pr_x7, val_x7, $signed(val_x7));
                $display("X28: phys %0d = 0x%08h (%0d)", pr_x28, val_x28, $signed(val_x28));
            end
        end
    end

    // -----------------------------------------------------------------------
    // DEBUG: Combinational Loop Catcher (Glitch Detector)
    // -----------------------------------------------------------------------
    // If signals oscillate infinitely without time advancing, this might trigger.
    // (Note: Most simulators just freeze, but this helps if there is 'delta' movement)
    
    // Monitors the LSQ 'full' signal which was causing issues earlier
    always @(dut.dispatch_unit.lsq_alloc_valid_out) begin
        if ($time > 230 && $time < 240) begin // Only check around the crash time
             $display("[GLITCH] LSQ Alloc Valid changed to %b at time %0t (Delta cycle?)", 
                      dut.dispatch_unit.lsq_alloc_valid_out, $time);
        end
    end

    // -----------------------------------------------------------------------
    // Main Sequence
    // -----------------------------------------------------------------------
    initial begin
        // Assert reset
        reset = 1'b1;
        repeat (2) @(posedge clk);
        reset = 1'b0;
        $display("Reset de-asserted. Starting execution...");

        // Run for a safe limit
        // Use a loop instead of 'repeat' so we can see progress
        for (int i = 0; i < 2000; i++) begin
            @(posedge clk);
            
            // OPTIONAL: Stop if PC hits a weird value (like 0 after start) or specific address
            // if (dut.pc == 32'h0000_0034) $display("--- Reached the Crash PC ---");
        end

        // Dump a0 and a1 at the end
        dump_a0_a1();
        $finish;
    end
    
    // Safety Timeout: Force stop if simulation runs too long (prevents infinite waits)
//    initial begin
//        #10000; // 10,000 ns limit
//        $display("\n[ERROR] Simulation Timed Out! Force finishing.");
//        dump_a0_a1();
//        $finish;
//    end

    // Task to dump the architectural a0/a1
    task dump_a0_a1;
        logic [6:0] pr_a0, pr_a1, pr_a2, pr_a3, pr_a4;
        logic [31:0] val_a0, val_a1, val_a2, val_a3, val_a4;
    begin
        pr_a0 = dut.rename_unit.map[5'd1];
        pr_a1 = dut.rename_unit.map[5'd9];
        pr_a2 = dut.rename_unit.map[5'd10];
        pr_a3 = dut.rename_unit.map[5'd11];
        pr_a4 = dut.rename_unit.map[5'd29];

        val_a0 = dut.PRF.phy_reg[pr_a0];
        val_a1 = dut.PRF.phy_reg[pr_a1];
        val_a2 = dut.PRF.phy_reg[pr_a2];
        val_a3 = dut.PRF.phy_reg[pr_a3];
        val_a4 = dut.PRF.phy_reg[pr_a4];

        $display("=================================================");
        $display("Register dump at time %0t:", $time);
        $display("  phys %0d = 0x%08h (%0d)", pr_a0, val_a0, $signed(val_a0));
        $display("  phys %0d = 0x%08h (%0d)", pr_a1, val_a1, $signed(val_a1));
        $display("  phys %0d = 0x%08h (%0d)", pr_a2, val_a2, $signed(val_a2));
        $display("  phys %0d = 0x%08h (%0d)", pr_a3, val_a3, $signed(val_a3));
        $display("  phys %0d = 0x%08h (%0d)", pr_a4, val_a4, $signed(val_a4));
        $display("=================================================");
    end
    endtask

    // Waveform dump
    initial begin
        $dumpfile("tb_processor.vcd");
        $dumpvars(0, tb_processor);
    end

endmodule