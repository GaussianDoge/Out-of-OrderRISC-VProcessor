`timescale 1ns / 1ps
import types_pkg::*; // Ensure your decode_data struct is visible

module tb_frontend_mispredict;

    // Inputs
    logic clk;
    logic reset;
    logic [31:0] pc_in;
    logic mispredict;
    logic frontend_ready_out; // Backpressure from Rename/Dispatch

    // Outputs
    decode_data data_out;
    logic frontend_valid_out;

    // Instantiate the Full Frontend
    frontend u_frontend (
        .clk(clk),
        .reset(reset),
        .pc_in(pc_in),
        .mispredict(mispredict),
        .frontend_ready_out(frontend_ready_out),
        .data_out(data_out),
        .frontend_valid_out(frontend_valid_out)
    );

    // Clock Gen
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Simulation Logic
    initial begin
        $display("=== STARTING FULL FRONTEND MISPREDICT TEST ===");

        // 1. Initialize
        reset = 1;
        mispredict = 0;
        pc_in = 0;
        frontend_ready_out = 1; // Backend is always ready to accept
        #10;
        
        reset = 0;
        $display("[Time %0t] Reset released", $time);

        // ------------------------------------------------------------
        // 2. Normal Execution (PC: 0 -> 4 -> 8 -> C)
        // ------------------------------------------------------------
        // We will feed PCs. Note: In real HW, the output comes out later due to buffering.
        
        pc_in = 32'h0000_0000; #10;
        pc_in = 32'h0000_0004; #10;
        pc_in = 32'h0000_0008; #10;
        pc_in = 32'h0000_000C; #10; // This instruction is "speculative" and will be flushed!

        // ------------------------------------------------------------
        // 3. TRIGGER MISPREDICT (Target = 0x40)
        // ------------------------------------------------------------
        $display("[Time %0t] !!! MISPREDICT FIRED !!! Jump to 0x40", $time);
        
        mispredict = 1;
        pc_in = 32'h0000_0040; // The Jump Target
        
        #10; // Cycle 1 of flush (PC register captures 0x40)
        
        mispredict = 0;
        // IMPORTANT: We HOLD 0x40 for one cycle here because the PC register
        // hasn't incremented yet in the real processor. The Fetch unit needs
        // this cycle to lock onto the new stream.
        #10; 

        // ------------------------------------------------------------
        // 4. RECOVERY (Target: 0x44 -> 0x48)
        // ------------------------------------------------------------
        pc_in = 32'h0000_0044; #10;
        pc_in = 32'h0000_0048; #10;
        pc_in = 32'h0000_004C; #10;
        
        // Let the pipeline drain
        #50;
        
        $display("=== TEST FINISHED ===");
        $finish;
    end

    // Monitor Output
    always @(posedge clk) begin
        if (!reset) begin
            if (frontend_valid_out) begin
                $display("[Time %0t] VALID OUT: PC=0x%h | Opcode=0x%h | RS1=%d | RD=%d", 
                    $time, 
                    data_out.pc, 
                    data_out.Opcode, 
                    data_out.rs1, 
                    data_out.rd
                );
            end else begin
                // Check if we are seeing a bubble
                $display("[Time %0t] (Bubble/Flush)", $time);
            end
        end
    end

endmodule