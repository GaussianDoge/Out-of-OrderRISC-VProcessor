`timescale 1ns / 1ps

module ImmGen(
    input logic [31:0] instr,
    output logic [31:0] imm
);

    // Different lengths of immediates
    logic [11:0] imm_12bits;
    logic [19:0] imm_20bits;

    always_comb begin
        automatic logic [6:0] opcode = instr[6:0];
        case (opcode) 
            // I-type, J-type, L-type
            7'b0010011, 7'b1100111, 7'b0000011: begin
                imm_12bits = instr[31:20];
                imm_20bits = 20'b0;
                imm = {{20{imm_12bits[11]}}, imm_12bits};
            end
            // LUI
            7'b0110111: begin
                imm_12bits = 12'b0;
                imm_20bits = instr[31:12];
                imm = {imm_20bits, {12{1'b0}}};
            end
            // BNE
            7'b1100011: begin
                imm_12bits = {instr[31], instr[7], instr[30:25], instr[11:8]};
                imm = {{19{imm_12bits[11]}}, imm_12bits<<1'b1};
            end
            // S-type
            7'b0100011: begin
                imm_12bits = {instr[31:25], instr[11:7]};
                imm_20bits = 20'b0;
                imm = {{20{imm_12bits[11]}}, imm_12bits};
            end
            // Default case for other opcodes
            default: begin
                imm_12bits = 12'b0;
                imm_20bits = 20'b0;
                imm = 32'b0;
            end
        endcase
    end
endmodule
