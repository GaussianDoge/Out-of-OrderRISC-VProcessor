`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/31/2025 02:28:21 PM
// Design Name: 
// Module Name: ICache
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ICache (
    input logic clk,
    input logic reset,
    input logic [31:0] address, 
    output logic [31:0] instruction
);
    //shift address right by 2
    logic [31:0] instr_mem[0:551];
    
    // initialize instruction memory
    // initial begin
    //      $readmemh("program.hex", mem);
    // end
    always_ff @(posedge clk) begin
        if (reset) instruction <= 32'b0;
        else instruction <= instr_mem[address>>2];
    end
endmodule
