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
    logic [31:0] addr;
    logic [31:0] data_mem;
    logic [6:0] pd_mem;
    logic [4:0] rob_mem;
    
    always_comb begin
        // Only support L-type instructions
        if (data_in.Opcode == 7'b0000011) begin
            addr = ps1_data + data_in.imm;
        end else begin
            addr = '0;
        end
    end    
    
    always_comb begin   
        data_out.fu_mem_ready = 1'b1;
        data_out.fu_mem_done  = 1'b0;
        if (mispredict) begin
            automatic logic [4:0] ptr = (mispredict_tag == 15) ? 0 : mispredict_tag + 1;
            for (logic [4:0] i = ptr; i != curr_rob_tag; i=(i==15)?0:i+1) begin
                if (i == data_in.rob_index) begin
                    data_out.p_mem = '0;
                    data_out.rob_fu_mem = '0;
                    data_out.data = '0;
                    data_out.fu_mem_ready = 1'b1;
                    data_out.fu_mem_done = 1'b0;
                end
            end
        end else begin
            if (issued) begin
                data_out.fu_mem_ready = 1'b0;
                data_out.fu_mem_done = 1'b0;
                data_out.data = '0;
                data_out.p_mem = data_in.pd;
                data_out.rob_fu_mem = data_in.rob_index;
            end
            else if (valid) begin
                data_out.fu_mem_ready = 1'b1;
                data_out.fu_mem_done = 1'b1;
                data_out.data = data_mem;
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
