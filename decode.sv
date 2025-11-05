`timescale 1ns / 1ps

module decode(
    input logic clk,
    input logic reset,

    // Upstream
    input logic [31:0] instr,
    input logic [31:0] pc_in,
    input logic valid_in,
    output logic ready_in,

    // Downstream
    input logic ready_out,
    output logic [31:0] pc_out,
    output logic valid_out,

    // Decoded signal
    output logic [4:0] rs1,
    output logic[4:0] rs2,
    output logic [4:0] rd,
    output logic [31:0] imm,
    output logic [2:0] ALUOp,
    output logic [6:0] opcode
    // Harzard detect signal?
    );
    
    // Buffered signals
    logic [31:0] pc_buf;
    logic valid_out_buf;
    
    logic [4:0] rs1_buf;
    logic[4:0] rs2_buf;
    logic [4:0] rd_buf;
    logic [31:0] imm_buf;
    logic [2:0] ALUOp_buf;
    logic [6:0] opcode_buf;

    //  Future signals
    logic [4:0] rs1_next;
    logic [4:0] rs2_next;
    logic [4:0] rd_next;
    logic [31:0] imm_next;
    logic [2:0] ALUOp_next;
    logic [6:0] opcode_next;
    
    // Combinational Section
    assign pc_out = pc_buf;
    assign ready_in = ready_out || !valid_out_buf;
    assign valid_out = valid_out_buf;
    assign rs1 = rs1_buf;
    assign rs2 = rs2_buf;
    assign rd = rd_buf;
    assign imm = imm_buf;
    assign ALUOp = ALUOp_buf;
    assign opcode = opcode_buf;

    ImmGen immgen_dut (
        .instr(instr),
        .imm(imm_next)
    );

    signal_decode decoder(
        .instr(instr),
        .rs1(rs1_next),
        .rs2(rs2_next),
        .rd(rd_next),
        .ALUOp(ALUOp_next),
        .opcode(opcode_next)
    );

    always_comb begin
        if (reset) begin
            pc_buf <= 32'b0;
            valid_out_buf <= 1'b0;
            
            rs1_buf <= 5'b0;
            rs2_buf <= 5'b0;
            rd_buf <= 5'b0;
            imm_buf<= 32'b0;
            ALUOp_buf <= 3'b0;
            opcode_buf <= 7'b0;
        end else begin
            // Handle upstream
            if (valid_in && ready_in) begin
                pc_buf <= pc_in;
                valid_out_buf <= 1'b1;
                
                // all signals handled by decoder and immGen
                rs1_buf <= rs1_next;
                rs2_buf <= rs2_next;
                rd_buf <= rd_next;
                opcode_buf <= opcode_next;
                imm_buf <= imm_next;
                ALUOp_buf <= ALUOp_next;
            end else if (ready_out && valid_out) begin
            // Handle downstream
                valid_out_buf <= 1'b0;
            end
        end
    end
    
endmodule
