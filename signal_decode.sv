`timescale 1ns / 1ps

module signal_decode(
    input logic [31:0] instr,
    output logic [4:0] rs1,
    output logic [4:0] rs2,
    output logic [4:0] rd,
    output logic [2:0] ALUOp,
    output logic [6:0] opcode
    );
    
    logic [4:0] rs1_next;
    logic [4:0] rs2_next;
    logic [4:0] rd_next;
    logic [31:0] imm_next;
    logic [2:0] ALUOp_next;
    logic [6:0] opcode_next;
    
    always_comb begin
        opcode_next = instr[6:0];
        case (opcode_next)
            // imm_next is already calculated by immgen_dut
            // I-type instructions
            7'b0010011: begin
                rs1_next = instr[19:15];
                rs2_next = 5'b0;
                rd_next = instr[11:7];
                ALUOp_next = 3'b011;
            end
            // LUI
            7'b0110111: begin
                rs1_next = 5'b0;
                rs2_next = 5'b0;
                rd_next = instr[11:7];
                ALUOp_next = 3'b100;
            end
            // R-type instructions
            7'b0110011: begin
                rs1_next = instr[19:15];
                rs2_next = instr[24:20];
                rd_next = instr[11:7];
                ALUOp_next = 3'b010;
            end
            // Load instructions excluding LUI 
            7'b0000011: begin
                rs1_next = instr[19:15];
                rs2_next = 5'b0;
                rd_next = instr[11:7];
                ALUOp_next = 3'b000;
            end
            // S-type instructions
            7'b0100011: begin
                rs1_next = instr[19:15];
                rs2_next = instr[24:20];
                rd_next = 5'b0;
                ALUOp_next = 3'b000;
            end
            // BNE
            7'b1100011: begin
                rs1_next = instr[19:15];
                rs2_next = instr[24:20];
                rd_next = 5'b0;
                ALUOp_next = 3'b001;
            end
            // JALR
            7'b1100111: begin
                rs1_next = instr[19:15];
                rs2_next = 5'b0;
                rd_next = instr[11:7];
                ALUOp_next = 3'b110;
            end
            // For other unknown OPcodes
            default: begin
                rs1_next = 5'b0;
                rs2_next = 5'b0;
                rd_next = 5'b0;
                ALUOp_next = 3'b0;
            end
        endcase
    end
endmodule
