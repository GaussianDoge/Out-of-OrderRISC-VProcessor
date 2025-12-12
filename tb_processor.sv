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
        forever #5 clk = ~clk;
    end

    // Main TB sequence: reset, (optional) program load, run, dump a0/a1
    initial begin
        // Assert reset
        reset = 1'b1;

        // OPTIONAL: load program.mem into your instruction memory
        // Adjust the hierarchical path and array name to match your fetch unit.
        // For example, if your fetch module has:
        //   reg [31:0] imem [0:255];
        // inside instance fetch_unit inside frontend,
        // you can uncomment and adjust this line:
        //
        // $readmemh("program.mem", dut.frontend_unit.fetch_unit.imem);
        //
        // If your fetch already calls $readmemh("program.mem", ...) internally,
        // you don't need to do anything here.

        // Hold reset for a few cycles
        repeat (2) @(posedge clk);
        reset = 1'b0;

        // Let the program run for some cycles (adjust as needed)
        repeat (500) @(posedge clk);

        // Dump a0 and a1 at the end
        dump_a0_a1();

        $finish;
    end

    // Task to dump the architectural a0/a1 using rename map + PRF
    task dump_a0_a1;
        // Physical register indices for x10 (a0) and x11 (a1)
        logic [6:0] pr_a0;
        logic [6:0] pr_a1;

        // Values in those physical registers
        logic [31:0] val_a0;
        logic [31:0] val_a1;
    begin
        // RISC-V ABI: a0 = x10, a1 = x11
        // rename_unit.map[arch_reg] -> physical reg ID (7 bits)
        pr_a0 = dut.rename_unit.map[5'd23];
        pr_a1 = dut.rename_unit.map[5'd31];

        // Read the physical register file in PRF
        val_a0 = dut.PRF.phy_reg[pr_a0];
        val_a1 = dut.PRF.phy_reg[pr_a1];

        $display("=================================================");
        $display("End of simulation register dump:");
        $display("  a0 (x10): phys %0d = 0x%08h (%0d)", pr_a0, val_a0, val_a0);
        $display("  a1 (x11): phys %0d = 0x%08h (%0d)", pr_a1, val_a1, val_a1);
        $display("=================================================");
    end
    endtask

    // Waveform dump (for GTKWave, etc.)
    initial begin
        $dumpfile("tb_processor.vcd");
        $dumpvars(0, tb_processor);
    end

endmodule
