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
    output logic [6:0] OpCode
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
    logic [6:0] OpCode_buf;

    //  Future signals
    logic [4:0] rs1_next;
    logic [4:0] rs2_next;
    logic [4:0] rd_next;
    logic [31:0] imm_next;
    logic [2:0] ALUOp_next;
    logic [6:0] OpCode_next;
    
    // Combinational Section
    assign pc_out = pc_buf;
    assign ready_in = ready_out || !valid_out_buf;
    assign valid_out = valid_out_buf;
    assign rs1 = rs1_buf;
    assign rs2 = rs2_buf;
    assign rd = rd_buf;
    assign imm = imm_buf;
    assign ALUOp = ALUOp_buf;
    assign OpCode = OpCode_buf;

    ImmGen immgen_dut (
        .instruction(instr),
        .imm(imm_next)
    );

    always_comb begin
        OpCode_next = instr[6:0];
        case (OpCode_next)
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

    // Skid Buffer
    always_ff @ (posedge clk) begin
        if (reset) begin
            pc_buf <= 32'b0;
            valid_out_buf <= 1'b0;
            
            rs1_buf <= 5'b0;
            rs2_buf <= 5'b0;
            rd_buf <= 5'b0;
            imm_buf<= 32'b0;
            ALUOp_buf <= 3'b0;
            OpCode_buf <= 7'b0;
        end else begin
            // Handle upstream
            if (valid_in && ready_in) begin
                pc_buf <= pc_in;
                valid_out_buf <= 1'b1;
                
                rs1_buf <= rs1_next;
                rs2_buf <= rs2_next;
                rd_buf <= rd_next;
                OpCode_buf <= OpCode_next;
                imm_buf <= imm_next;
                ALUOp_buf <= ALUOp_next;
            end else if (ready_out && valid_out) begin
            // Handle downstream
                valid_out_buf <= 1'b0;
            end
        end
    end
    
endmodule
