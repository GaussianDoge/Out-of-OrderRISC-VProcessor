`timescale 1ns / 1ps
import types_pkg::*;

module fu_alu(
    input clk,
    input reset,
    
    // From ROB
    input logic [4:0] curr_rob_tag,
    input logic mispredict,
    input logic [4:0] mispredict_tag,
    
    // From RS and PRF
    input logic issued,
    input rs_data data_in,
    input logic [31:0] ps1_data,
    input logic [31:0] ps2_data,
    
    // Output data
    output alu_data data_out
);
    logic done;
    assign data_out.fu_alu_done = done;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            data_out.p_alu <= '0;
            data_out.rob_fu_alu <= '0;
            data_out.data <= '0; 
            data_out.fu_alu_ready <= 1'b1;
            done <= '0;
        end else begin
            data_out.fu_alu_ready <= 1'b1;
            if (mispredict) begin
                automatic logic [4:0] ptr = (mispredict_tag == 15) ? 0 : mispredict_tag + 1;
                for (logic [4:0] i = ptr; i != curr_rob_tag; i=(i==15)?0:i+1) begin
                    if (i == data_in.rob_index) begin
                        data_out.p_alu <= '0;
                        data_out.rob_fu_alu <= '0;
                        data_out.data <= '0;
                        data_out.fu_alu_ready <= 1'b1;
                        done <= '0;
                    end
                end
            end else begin
                if (issued) begin
                    data_out.p_alu <= data_in.pd;
                    data_out.rob_fu_alu <= data_in.rob_index;
                    if (data_in.Opcode == 7'b0010011) begin
                        if (data_in.func3 == 3'b000) begin // Addi
                            data_out.data <= ps1_data + data_in.imm;
                        end else if (data_in.func3 == 3'b110) begin // Ori
                            data_out.data <= ps1_data | data_in.imm;
                        end else if (data_in.func3 == 3'b011) begin // Sltiu
                            data_out.data <= (ps1_data < data_in.imm) ? 12'b1 : 12'b0;
                        end 
                    end else if (data_in.Opcode == 7'b0110111) begin // LUI
                        data_out.data <= data_in.imm;
                    end else if (data_in.Opcode == 7'b0110011) begin
                        if (data_in.func3 == 3'b101 && data_in.func7[5] == 1'b1) begin // Sra
                            data_out.data <= $signed(ps1_data) >>> ps2_data;
                        end else if (data_in.func3 == 3'b000 && data_in.func7[5] == 1'b1) begin // sub
                            data_out.data <= ps1_data - ps2_data;
                        end else if (data_in.func3 == 3'b111 && data_in.func7[5] == 1'b0) begin // And
                            data_out.data <= ps1_data & ps2_data;
                        end
                    end
                    done <= 1'b1;
                end else begin
                    done <= 1'b0;
                end
            end
        end 
    end
endmodule
