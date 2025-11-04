`timescale 1ns / 1ps

module fetch(
    input logic clk,
    input logic reset,
    
    // Upstream 
    input logic [31:0] PC_in,

    // Downstream
    input logic ready_in,
    output logic [31:0] instr_out,
    output logic [31:0] PC_out,
    output logic [31:0] PC_4,
    output logic valid_out
);

    // Buffered signals
    logic [31:0] PC_buf;
    logic [31:0] instr_buf;
    logic valid_out_buf;
    
    logic [31:0] instr_icache;
    
    ICache ICache_dut (
        .clk(clk),
        .reset(reset),
        .address(PC_in),
        .instruction(instr_icache)
    );
    
    // Combinational section
    assign PC_out = PC_buf;
    assign PC_4 = PC_buf + 32'd4;
    assign valid_out = valid_out_buf;
    assign instr_out = instr_buf;
    
    always_ff @(posedge clk) begin
        if (reset) begin
            valid_out_buf <= 1'b0;  
            instr_buf <= 32'b0;
            PC_buf <= 32'b0;
        end else begin
            // Handle Upstream
            if (!valid_out_buf || ready_in) begin
                valid_out_buf <= 1'b1;
                PC_buf <= PC_in;
                instr_buf <= instr_icache;
            end
        end
    end
endmodule