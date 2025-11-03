`timescale 1ns / 1ps

module skid_buffer_struct #(
    parameter type T = logic 
    )(
    input logic     clk,
    input logic     reset,
    
    // upstream (producer -> skid)
    input logic     valid_in,
    output logic    ready_in,
    input T         data_in,
    
    // downstream (skid -> consumer)
    output logic    valid_out,
    input logic     ready_out,
    output T        data_out
    );
    
    // Flip-Flops for storage
    T       data_reg;
    logic   valid_reg;

    // --- Combinational Logic ---

    // We are ready to accept new data IF:
    assign ready_in = !valid_reg || ready_out;
    
    // The output is valid if our register is valid
    assign valid_out = valid_reg;
    
    // The output data is just our registered data
    assign data_out = data_reg;
    
    
    // --- Sequential Logic ---
    
    always_ff @(posedge clk) begin
        if (reset) begin
            valid_reg <= 1'b0;
            data_reg  <= '0; // Use '0 to assign all bits to 0
        end 
        else if (ready_in && valid_in) begin
            // **Load/Replace:** A new valid item is arriving AND we can accept it.
            // This single case handles:
            // 1. Empty -> Full (loading)
            // 2. Full -> Full (replacing)
            valid_reg <= 1'b1;
            data_reg  <= data_in;
        end 
        else if (ready_out) begin
            // **Clear:** No new item is arriving (because ready_in&&valid_in was false),
            // but the consumer is clearing us.
            valid_reg <= 1'b0;
        end
        // **Stall:** If none of the above is true, it means:
        // We are full and the consumer is not ready.
        // We simply hold our values (valid_reg and data_reg).
    end
    
endmodule