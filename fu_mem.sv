`timescale 1ns / 1ps

import types_pkg::*;

module fu_mem(
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
    output mem_data data_out
);
    // For Data Memory operation
    wire [6:0] curr_Opcode = data_in.Opcode;
    wire [2:0] curr_func3 = data_in.func3;
    logic valid;
    logic read_en;
    logic [31:0] addr;
    logic [31:0] data_mem;
    
    always_comb begin
        // Only support L-type instructions
        if (issued) begin
            if (data_in.Opcode == 7'b0000011) begin
                addr = ps1_data + data_in.imm;
            end
        end
    end
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            data_out.p_mem <= '0;
            data_out.rob_fu_mem <= '0;
            data_out.data <= '0; 
            data_out.fu_mem_ready <= 1'b1;
            data_out.fu_mem_done <= 1'b0;
            read_en <= 1'b0;
            addr <= '0;
        end else begin
            if (mispredict) begin
                automatic logic [4:0] ptr = (mispredict_tag == 15) ? 0 : mispredict_tag + 1;
                for (logic [4:0] i = ptr; i != curr_rob_tag; i=(i==15)?0:i+1) begin
                    if (i == data_in.rob_index) begin
                        data_out.p_mem <= '0;
                        data_out.rob_fu_mem <= '0;
                        data_out.data <= '0;
                        data_out.fu_mem_ready <= 1'b1;
                        data_out.fu_mem_done <= 1'b0;
                        read_en <= 1'b0;
                        addr <= '0;
                    end
                end
            end else begin
                if (issued) begin
                    data_out.fu_mem_ready <= 1'b0;
                    data_out.fu_mem_done <= 1'b0;
                end else if (valid) begin
                    read_en <= 1'b0;
                    data_out.fu_mem_ready <= 1'b1;
                    data_out.fu_mem_done <= 1'b1;
                    addr <= '0;
                    data_out.data <= data_mem;
                end else if (!read_en) begin
                    data_out.fu_mem_ready <= 1'b1;
                    data_out.fu_mem_done <= 1'b0;
                end 
            end
        end
    end
    
    data_memory u_dmem (
        .clk(clk),
        .reset(reset),
        
        .addr(addr),
        .issued(issued),
        .Opcode(curr_Opcode),
        .func3(curr_func3),
        
        .data_out(data_mem),
        .valid(valid)
    );
    
endmodule
