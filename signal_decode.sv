`timescale 1ns / 1ps

module signal_decode(
    input logic [31:0] instr,
    output logic [4:0] rs1,
    output logic [4:0] rs2,
    output logic [4:0] rd,
    output logic [2:0] ALUOp,
    output logic [6:0] Opcode,
    output logic fu_mem,
    output logic fu_alu,
    output logic fu_br,
    output logic [2:0] func3,
    output logic [6:0] func7
    );
    
    always_comb begin
        Opcode = instr[6:0];
        case (Opcode)
            // imm_next is already calculated by immgen_dut
            // I-type instructions
            7'b0010011: begin
                rs1 = instr[19:15];
                rs2 = 5'b0;
                rd = instr[11:7];
                ALUOp = 3'b011;
                fu_alu = 1'b1;
                fu_mem = 1'b0;
                fu_br = 1'b0;
                func3 = instr[14:12];
                func7 = instr[31:25];
            end
            // LUI
            7'b0110111: begin
                rs1 = 5'b0;
                rs2 = 5'b0;
                rd = instr[11:7];
                ALUOp = 3'b100;
                fu_alu = 1'b1;
                fu_mem = 1'b0;
                fu_br = 1'b0;
                func3 = '0;
                func7 = '0; 
            end
            // R-type instructions
            7'b0110011: begin
                rs1 = instr[19:15];
                rs2 = instr[24:20];
                rd = instr[11:7];
                ALUOp = 3'b010;
                fu_alu = 1'b1;
                fu_mem = 1'b0;
                fu_br = 1'b0;
                func3 = instr[14:12];
                func7 = instr[31:25];
            end
            // Load instructions excluding LUI 
            7'b0000011: begin
                rs1 = instr[19:15];
                rs2 = 5'b0;
                rd = instr[11:7];
                ALUOp = 3'b000;
                fu_alu = 1'b1;
                fu_mem = 1'b1;
                fu_br = 1'b0;
                func3 = instr[14:12];
                func7 = '0;
            end
            // S-type instructions
            7'b0100011: begin
                rs1 = instr[19:15];
                rs2 = instr[24:20];
                rd = 5'b0;
                ALUOp = 3'b000;
                fu_alu = 1'b1;
                fu_mem = 1'b1;
                fu_br = 1'b0;
                func3 = instr[14:12];
                func7 = '0;
            end
            // BNE
            7'b1100011: begin
                rs1 = instr[19:15];
                rs2 = instr[24:20];
                rd = 5'b0;
                ALUOp = 3'b001;
                fu_alu = 1'b1;
                fu_mem = 1'b0;
                fu_br = 1'b1;
                func3 = instr[14:12];
                func7 = '0;
            end
            // JALR
            7'b1100111: begin
                rs1 = instr[19:15];
                rs2 = 5'b0;
                rd = instr[11:7];
                ALUOp = 3'b110;
                fu_alu = 1'b1;
                fu_mem = 1'b0;
                fu_br = 1'b0;
                func3 = instr[14:12];
                func7 = '0;
            end
            // For other unknown OPcodes
            default: begin
                rs1 = 5'b0;
                rs2 = 5'b0;
                rd = 5'b0;
                ALUOp = 3'b0;
                fu_alu = 1'b0;
                fu_mem = 1'b0;
                fu_br = 1'b0;
                func3 = '0;
                func7 = '0;
            end
        endcase
    end
endmodule
