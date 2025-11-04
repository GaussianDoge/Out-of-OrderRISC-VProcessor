`timescale 1ns / 1ps

module ICache (
    input logic clk,
    input logic reset,
    input logic [31:0] address, 
    output logic [31:0] instruction
);
    // Stored in littleEndian
    logic [31:0] instr_mem[0:551];

    always_ff @(posedge clk) begin
        if (reset) instruction <= 32'b0;
        // Shift address right by 2
        else instruction <= instr_mem[address>>2];
    end
endmodule
