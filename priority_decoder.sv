module priority_decoder
#(
    parameter WIDTH = 4
) (
    input wire [WIDTH-1: 0] in,
    output logic [$clog2(WIDTH)-1: 0] out,
    output logic valid
);

    // 32-bit internal "helper" signal for the output (To prevent Icarus Verilog and Verilator from contradicting each other)
    logic [31:0] out_internal;
    assign out = out_internal[$clog2(WIDTH)-1: 0];

    always_comb begin // Same as always @(*) for verilog
        // If found is set, there is no need to search through the other indices
        logic found;
        // Default outputs
        valid = 1'b0;
        out_internal = '0; // Sets all bits to 0
        found = 1'b0;
        // For loop for finding the correct output (Lowest index has highest priority; Can change to the opposite just by reversing the loop)
        for (int i = 0; i < WIDTH; i = i + 1) begin
            if(in[i] == 1 && !found) begin
                valid = 1'b1;
                out_internal = i;
                found = 1'b1;
            end
        end
    end
endmodule