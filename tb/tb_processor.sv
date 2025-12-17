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

    // Clock generation: 4ns period
    initial begin
        clk = 1'b0;
        forever #2 clk = ~clk;
    end

    // ----------------------------
    // ABI name for x-reg
    // ----------------------------
    function automatic string abi_name(input int unsigned r);
        case (r)
            0:  abi_name = "zero";
            1:  abi_name = "ra";
            2:  abi_name = "sp";
            3:  abi_name = "gp";
            4:  abi_name = "tp";
            5:  abi_name = "t0";
            6:  abi_name = "t1";
            7:  abi_name = "t2";
            8:  abi_name = "s0/fp";
            9:  abi_name = "s1";
            10: abi_name = "a0";
            11: abi_name = "a1";
            12: abi_name = "a2";
            13: abi_name = "a3";
            14: abi_name = "a4";
            15: abi_name = "a5";
            16: abi_name = "a6";
            17: abi_name = "a7";
            18: abi_name = "s2";
            19: abi_name = "s3";
            20: abi_name = "s4";
            21: abi_name = "s5";
            22: abi_name = "s6";
            23: abi_name = "s7";
            24: abi_name = "s8";
            25: abi_name = "s9";
            26: abi_name = "s10";
            27: abi_name = "s11";
            28: abi_name = "t3";
            29: abi_name = "t4";
            30: abi_name = "t5";
            31: abi_name = "t6";
            default: abi_name = "???";
        endcase
    endfunction

    // -----------------------------------------
    // Read current architectural register value
    // x0 forced to 0
    // -----------------------------------------
    function automatic logic [31:0] read_arch_val(input int unsigned r);
        logic [6:0] pr;
        begin
            if (r == 0) begin
                read_arch_val = 32'd0;
            end else begin
                pr = dut.rename_unit.map[r[4:0]];
                read_arch_val = dut.PRF.phy_reg[pr];
            end
        end
    endfunction

    // -----------------------------------------
    // Task: Dump ALL architectural registers
    // -----------------------------------------
    task automatic dump_arch_regs(input string tag = "");
        logic [6:0]  pr;
        logic [31:0] val;
        longint signed   sval;
        longint unsigned uval;
        string name;
    begin
        if (tag != "") $display("\n================== %s ==================", tag);

        $display("==============================================================================================");
        $display("Architectural Register File Dump @ time %0t", $time);
        $display("----------------------------------------------------------------------------------------------");
        $display("  Arch    ABI       Phys     Hex Value      Signed Value        Unsigned Value");
        $display("----------------------------------------------------------------------------------------------");

        for (int r = 0; r < 32; r++) begin
            name = abi_name(r);

            pr = dut.rename_unit.map[r[4:0]];
            if (r == 0) val = 32'd0;
            else        val = dut.PRF.phy_reg[pr];

            sval = $signed(val);
            uval = $unsigned(val);

            $display("  x%02d   %-7s  p%03d   0x%08h   %14d   %18u",
                     r, name, pr, val, sval, uval);
        end

        $display("==============================================================================================\n");
    end
    endtask

    // ----------------------------
    // Cycle / stability tracking
    // ----------------------------
    logic [31:0] prev_arch [0:31];
    logic [31:0] curr_arch [0:31];

    int unsigned cycle;
    int unsigned start_cycle;
    int unsigned last_change_cycle;
    int unsigned stable_count;          // consecutive cycles with no arch-reg changes
    bit          started;
    bit          changed;

    localparam int unsigned STABLE_WINDOW = 20;
    localparam int unsigned MAX_CYCLES    = 200000; // safety cap

    // ----------------------------
    // Main sequence
    // ----------------------------
    initial begin
        reset = 1'b1;
        cycle = 0;
        started = 0;
        stable_count = 0;
        start_cycle = 0;
        last_change_cycle = 0;

        // init prev snapshot
        for (int r = 0; r < 32; r++) prev_arch[r] = '0;

        repeat (2) @(posedge clk);
        reset = 1'b0;

        // Start counting from first posedge after reset goes low
        @(posedge clk);
        started = 1;
        cycle = 1;
        start_cycle = cycle;
        last_change_cycle = cycle;

        // Take an initial snapshot
        for (int r = 0; r < 32; r++) prev_arch[r] = read_arch_val(r);

        $display("Reset de-asserted. Starting execution...");
        $display("Will stop when architectural regs are stable for %0d cycles.\n", STABLE_WINDOW);

        // Run until stable window is reached
        while (cycle < MAX_CYCLES) begin
            @(posedge clk);
            cycle++;

            // read current snapshot
            for (int r = 0; r < 32; r++) curr_arch[r] = read_arch_val(r);

            // detect changes
            changed = 0;
            for (int r = 0; r < 32; r++) begin
                if (curr_arch[r] !== prev_arch[r]) changed = 1;
            end

            if (changed) begin
                last_change_cycle = cycle;
                stable_count = 0;

                // update prev snapshot
                for (int r = 0; r < 32; r++) prev_arch[r] = curr_arch[r];
            end else begin
                stable_count++;
            end

            // If stable for 20 cycles -> done
            if (stable_count >= STABLE_WINDOW) begin
                int unsigned cycles_to_last_update;
                int unsigned cycles_to_stable;

                cycles_to_last_update = last_change_cycle - start_cycle;
                cycles_to_stable      = cycle - start_cycle;

                $display("\n================== COMPLETION DETECTED ==================");
                $display("Start cycle (after reset):            %0d", start_cycle);
                $display("Last architectural update cycle:      %0d (delta: %0d cycles)",
                         last_change_cycle, cycles_to_last_update);
                $display("Stability reached at cycle:           %0d (delta: %0d cycles)",
                         cycle, cycles_to_stable);
                $display("Condition: no arch-reg changes for    %0d consecutive cycles", STABLE_WINDOW);
                $display("=========================================================\n");

                dump_arch_regs("FINAL REGISTER STATE");
                $finish;
            end
        end

        $display("ERROR: Reached MAX_CYCLES=%0d without hitting stability window.", MAX_CYCLES);
        dump_arch_regs("REGISTER STATE AT TIMEOUT");
        $finish;
    end

    // Waveform
    initial begin
        $dumpfile("tb_processor.vcd");
        $dumpvars(0, tb_processor);
    end

endmodule
