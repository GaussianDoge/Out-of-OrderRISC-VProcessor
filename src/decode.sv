`timescale 1ns / 1ps

import types_pkg::*;
module decode(
    input logic clk,
    input logic reset,
    input logic mispredict,

    // Upstream
    input logic [31:0] instr,
    input logic [31:0] pc_in,
    input logic valid_in,
    output logic ready_in,

    // Downstream
    input logic ready_out,
    output logic valid_out,
    output decode_data data_out
    // Decoded signal
    
    // Harzard detect signal?
    );
    
    // track status
    //logic sent;

    //  Future signals
    logic [4:0] rs1_next;
    logic [4:0] rs2_next;
    logic [4:0] rd_next;
    logic [31:0] imm_next;
    logic [2:0] ALUOp_next;
    logic [6:0] opcode_next;
    logic fu_mem_next;
    logic fu_alu_next;
    logic fu_br_next;
    logic ready_in_reset;
    logic [2:0] func3_next;
    logic [6:0] func7_next;
    
    // Combinational Section
    //assign ready_in = sent||ready_in_reset;
    assign ready_in = ready_out;

    ImmGen immgen (
        .instr(instr),
        .imm(imm_next)
    );

    signal_decode decoder(
        .instr(instr),
        .rs1(rs1_next),
        .rs2(rs2_next),
        .rd(rd_next),
        .ALUOp(ALUOp_next),
        .Opcode(opcode_next),
        .fu_mem(fu_mem_next),
        .fu_alu(fu_alu_next),
        .fu_br(fu_br_next),
        .func3(func3_next),
        .func7(func7_next)
    );

    always_comb begin
        if (reset || mispredict) begin
            data_out.pc = 32'b0;
            valid_out = 1'b0;
            ready_in_reset = 1'b1;
            
            data_out.rs1 = 5'b0;
            data_out.rs2 = 5'b0;
            data_out.rd = 5'b0;
            data_out.imm = 32'b0;
            data_out.ALUOp = 3'b0;
            data_out.Opcode = 7'b0;
            data_out.fu_mem = 1'b0;
            data_out.fu_alu = 1'b0;
            data_out.fu_br = 1'b0;
            data_out.func3 = 3'b0;
            data_out.func7 = 7'b0;
            
            //sent = 1'b0;
        end else begin
            // Handle upstream
            if (valid_in && ready_in) begin
                ready_in_reset = 1'b0;
                data_out.pc = pc_in;
                valid_out = 1'b1;
                
                // all signals handled by decoder and immGen
                data_out.rs1 = rs1_next;
                data_out.rs2 = rs2_next;
                data_out.rd = rd_next;
                data_out.Opcode = opcode_next;
                data_out.imm = imm_next;
                data_out.ALUOp = ALUOp_next;
                data_out.fu_mem = fu_mem_next;
                data_out.fu_alu = fu_alu_next;
                data_out.fu_br = fu_br_next;
                data_out.func3 = func3_next;
                data_out.func7 = func7_next;
            end else begin
                valid_out = 1'b0;
            end
            
//            // Handle downstream
//            if (ready_out && valid_out) begin
//                sent = 1'b1;
//            end else if (sent && !ready_out) begin // triggered when downstream updated
//                sent = 1'b0;
//            end else begin
//                // do nothing (keep to avoid bug)
//            end
        end
    end
    
endmodule
