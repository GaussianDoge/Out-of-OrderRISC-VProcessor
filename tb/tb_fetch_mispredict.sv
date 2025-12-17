`timescale 1ns / 1ps

module tb_fetch_mispredict;

    // Inputs
    logic clk;
    logic reset;
    logic mispredict;
    logic [31:0] pc_in;
    logic ready_out_from_backend;

    // Outputs
    logic [31:0] instr_out;
    logic [31:0] pc_out;
    logic [31:0] pc_4;
    logic valid_out;

    // Instantiate the User's Fetch Unit (which contains your ICache)
    fetch u_fetch (
        .clk(clk),
        .reset(reset),
        .mispredict(mispredict),
        .pc_in(pc_in),
        .ready_out(ready_out_from_backend), // We keep this High to simulate "Backend Ready"
        .instr_out(instr_out),
        .pc_out(pc_out),
        .pc_4(pc_4),
        .valid_out(valid_out)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Simulation Sequence
    initial begin
        $display("=== STARTING FETCH MISPREDICTION TEST ===");

        // 1. Initialize
        reset = 1;
        mispredict = 0;
        pc_in = 0;
        ready_out_from_backend = 1; 
        #10;
        
        reset = 0;
        $display("[Time %0t] Reset released", $time);

        // ------------------------------------------------------------
        // 2. Normal Fetching (Linear Execution)
        // ------------------------------------------------------------
        // We simulate the PC incrementing normally
        
        // Fetch Address 0 (Instruction 0)
        pc_in = 32'h0000_0000;
        #10; 
        
        // Fetch Address 4 (Instruction 1)
        pc_in = 32'h0000_0004;
        #10;

        // Fetch Address 8 (Instruction 2)
        pc_in = 32'h0000_0008;
        #10;

        // ------------------------------------------------------------
        // 3. TRIGGER MISPREDICT
        // ------------------------------------------------------------
        // Scenario: Branch Logic decides we must jump to 0x40 (Line 16 in mem)
        $display("[Time %0t] !!! TRIGGERING MISPREDICT !!! Jump to 0x40", $time);
        
        mispredict = 1;       // Flush the pipeline buffers
        pc_in = 32'h0000_0040; // Force PC to the Jump Target
        
        #10; // Hold for 1 cycle
        
        // ------------------------------------------------------------
        // 4. RECOVERY
        // ------------------------------------------------------------
        mispredict = 0;       // Release Flush
        // pc_in = 32'h0000_0044; // <--- DON'T INCREMENT YET!
        
        // KEEP pc_in at 0x40 so the Fetch Unit can capture it now that flush is done.
        #10; 
        
        // NOW increment
        pc_in = 32'h0000_0044; // Target + 4
        #10;
        
        pc_in = 32'h0000_0048; // Target + 8
        #10;

        // ------------------------------------------------------------
        // 5. FINISH
        // ------------------------------------------------------------
        #20;
        $display("=== TEST FINISHED ===");
        $finish;
    end

    // Monitor Output
    always @(posedge clk) begin
        if (!reset) begin
            if (valid_out) 
                $display("[Time %0t] OUT: PC=0x%h Instr=0x%h", $time, pc_out, instr_out);
            else 
                $display("[Time %0t] OUT: Pipeline Bubble (Valid=0)", $time);
        end
    end

endmodule