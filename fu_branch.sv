`timescale 1ns / 1ps

module fu_branch(
    input clk,
    input reset,
    
    // From ROB
    input logic [4:0] curr_rob_tag,
    input logic [4:0] mispredict_tag,
    
    // From RS
    input rs_data data_in,
    input logic issued,
    
    // From PRF
    input logic [31:0] ps1_data,
    input logic [31:0] ps2_data,
    
    // Output 
    output b_data data_out
);
    logic [4:0] ptr;
    always_comb begin
        data_out.fu_b_ready = 1'b1;
        data_out.fu_b_done = 1'b0;
        data_out.jalr_bne_signal = 1'b0;
        data_out.mispredict = 1'b0;
        data_out.mispredict_tag = '0;
        data_out.pc = '0;
        data_out.fu_b_ready = 1'b1;
        data_out.p_b = '0;
        data_out.data = '0;
        data_out.rob_fu_b = '0;

        if (issued) begin
            if (data_in.Opcode == 7'b1100111) begin
                if (data_in.func3 == 3'b000) begin // Jalr
                    // Mispredict, since for JALR it is automatically assumed to be not taken unless we have a BTB
                    data_out.pc = data_in.imm + ps1_data;
                    data_out.data = data_in.pc + 4;
                    data_out.jalr_bne_signal = 1'b1;
                    data_out.p_b = data_in.pd;
                    data_out.mispredict = 1'b1;
                    data_out.mispredict_tag = data_in.rob_index;
                    data_out.rob_fu_b = data_in.rob_index;
                end
            end else if (data_in.Opcode == 7'b1100011) begin
                if (data_in.func3 == 3'b001) begin // Bne
                    // Mispredict, we assume not taken
                    if ((ps1_data - ps2_data) != 0) begin
                        data_out.pc = (data_in.pc + data_in.imm) & {{31{1'b1}}, 1'b0};
                        data_out.rob_fu_b = data_in.rob_index;
                        data_out.jalr_bne_signal = 1'b1;
                        data_out.mispredict = 1'b1;
                        data_out.mispredict_tag = data_in.rob_index;
                    end else begin 
                        data_out.rob_fu_b = data_in.rob_index;
                        data_out.mispredict = 1'b0;
                        data_out.jalr_bne_signal = 1'b0;
                    end
                end 
            end
            data_out.fu_b_done = 1'b1;
        end
    end

endmodule
