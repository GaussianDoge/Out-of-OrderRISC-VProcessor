`timescale 1ns / 1ps

module free_list_tb;

    // Parameters
    parameter int DEPTH = 96;

    // Inputs
    logic clk;
    logic reset;
    logic write_en;
    logic [6:0] data_in;
    logic read_en;
    logic mispredict;
    logic [6:0] re_r_ptr;
    logic [6:0] re_w_ptr;
    logic [6:0] re_list [0:95];

    // Outputs
    logic [6:0] pd_new_out;
    logic empty;
    logic [6:0] r_ptr_out;
    logic [6:0] w_ptr_out;
    logic [6:0] list_out [0:95];

    // Instantiate the Unit Under Test (UUT)
    free_list #(
        .DEPTH(DEPTH)
    ) uut (
        .clk(clk),
        .reset(reset),
        .write_en(write_en),
        .data_in(data_in),
        .read_en(read_en),
        .pd_new_out(pd_new_out),
        .empty(empty),
        .mispredict(mispredict),
        .re_r_ptr(re_r_ptr),
        .re_w_ptr(re_w_ptr),
        .re_list(re_list),
        .r_ptr_out(r_ptr_out),
        .w_ptr_out(w_ptr_out),
        .list_out(list_out)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test Variables
    int i;
    logic [6:0] snapshot_r_ptr;
    logic [6:0] snapshot_w_ptr;
    logic [6:0] snapshot_list [0:95];

    initial begin
        // Initialize Inputs
        reset = 1;
        write_en = 0;
        data_in = 0;
        read_en = 0;
        mispredict = 0;
        re_r_ptr = 0;
        re_w_ptr = 0;

        // Wait for global reset
        #20;
        reset = 0;
        #10;

        $display("=== Test 1: Initialization ===");
        // Expecting R_PTR = 0, W_PTR = 0, EMPTY = 0 (Full of regs)
        if (r_ptr_out == 0 && w_ptr_out == 0 && empty == 0) 
            $display("PASS: Init correct. r_ptr=%d, w_ptr=%d, empty=%b", r_ptr_out, w_ptr_out, empty);
        else 
            $display("FAIL: Init incorrect. r_ptr=%d, w_ptr=%d", r_ptr_out, w_ptr_out);
        
        // Check first few values
        if (pd_new_out == 1) $display("PASS: First reg is 1");
        else $display("FAIL: First reg is %d (expected 1)", pd_new_out);


        $display("\n=== Test 2: Allocation (Reading) ===");
        // Allocate 5 registers
        read_en = 1;
        for (i = 0; i < 5; i++) begin
            $display("Allocating: Got Reg %d at r_ptr %d", pd_new_out, r_ptr_out);
            #10; // Wait one clock cycle
        end
        read_en = 0;
        
        // r_ptr should now be 5
        if (r_ptr_out == 5) $display("PASS: r_ptr moved to 5");
        else $display("FAIL: r_ptr is %d (expected 5)", r_ptr_out);


        $display("\n=== Test 3: Freeing (Writing) ===");
        // Free register 100, 101, 102 (just arbitrary IDs to test storage)
        write_en = 1;
        data_in = 7'd100; #10;
        data_in = 7'd101; #10;
        data_in = 7'd102; #10;
        write_en = 0;

        // w_ptr should now be 3
        if (w_ptr_out == 3) $display("PASS: w_ptr moved to 3");
        else $display("FAIL: w_ptr is %d (expected 3)", w_ptr_out);

        // Verify the list contains 100 at index 0
        if (list_out[0] == 100) $display("PASS: List[0] updated to 100");
        else $display("FAIL: List[0] is %d", list_out[0]);


        $display("\n=== Test 4: Snapshot & Mispredict ===");
        
        // 1. Take a Snapshot (Save current state)
        // Current State: r_ptr=5, w_ptr=3.
        snapshot_r_ptr = r_ptr_out;
        snapshot_w_ptr = w_ptr_out;
        snapshot_list  = list_out;
        $display("Taking Snapshot at r_ptr=%d, w_ptr=%d", r_ptr_out, w_ptr_out);

        // 2. Do more operations (Alloc 2 more)
        read_en = 1;
        #20; 
        read_en = 0;
        $display("Advanced state: r_ptr=%d", r_ptr_out); // Should be 7

        // 3. Trigger Mispredict (Restore)
        // Rename module would typically drive these inputs from its saved registers
        mispredict = 1;
        re_r_ptr = snapshot_r_ptr;
        re_w_ptr = snapshot_w_ptr;
        re_list  = snapshot_list;
        #10; // Apply for one cycle
        mispredict = 0;

        // 4. Check Restore
        #1; // Wait for logic to settle
        if (r_ptr_out == snapshot_r_ptr && w_ptr_out == snapshot_w_ptr) begin
            $display("PASS: Restored correctly to r_ptr=%d, w_ptr=%d", r_ptr_out, w_ptr_out);
        end else begin
            $display("FAIL: Restore failed. Got r_ptr=%d, w_ptr=%d", r_ptr_out, w_ptr_out);
        end

        // 5. Verify Content Check (did we revert the list?)
        if (list_out[0] == 100) $display("PASS: List content preserved/restored.");
        else $display("FAIL: List content lost.");


        $display("\n=== Test 5: Wrapping Behavior ===");
        // Reset to simplify wrapping test
        reset = 1; #10; reset = 0; #10;
        
        // Move r_ptr to 95 (last index) manually for testing or just loop
        // Let's loop 95 times
        read_en = 1;
        repeat(95) #10;
        read_en = 0;
        
        if (r_ptr_out == 95) $display("PASS: Reached end of buffer (95)");
        
        // Read one more time
        read_en = 1; #10; read_en = 0;
        
        if (r_ptr_out == 0) $display("PASS: Wrapped around to 0");
        else $display("FAIL: Did not wrap. r_ptr=%d", r_ptr_out);

        $stop;
    end

endmodule