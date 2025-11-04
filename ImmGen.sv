`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/01/2025 06:20:16 PM
// Design Name: 
// Module Name: ImmGen
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


module ImmGen(
    input logic [31:0] instruction,
    output logic [31:0] imm    
);
    logic [11:0] imm_12bits;
    logic [19:0] imm_20bits;
    always_comb begin
        automatic logic [6:0] opcode = instruction[6:0];
        imm_12bits = 12'b0;
        imm_20bits = 20'b0;
        imm = 32'b0;
        case (opcode) 
            // I-type, J-type, L-type
            7'b0010011, 7'b1100111, 7'b0000011: begin
                imm_12bits = instruction[31:20];
                imm = {{20{imm_12bits[11]}}, imm_12bits};
            end
            // LUI
            7'b0110111: begin
                imm_20bits = instruction[31:12];
                imm = {imm_20bits, {12{1'b0}}};
            end
            // BNE
            7'b1100011: begin
                imm_12bits = {instruction[31], instruction[7], instruction[29:24], instruction[11:8]};
                imm = {{20{imm_12bits[11]}}, imm_12bits};
            end
            // S-type
            7'b0100011: begin
                imm_12bits = {instruction[31:25], instruction[11:7]};
                imm = {{20{imm_12bits[11]}}, imm_12bits};
            end
        endcase
    end
endmodule
