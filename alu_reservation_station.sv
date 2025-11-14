`timescale 1ns / 1ps
import types_pkg::*;

module alu_reservation_station(
    input logic clk,
    input logic reset,
    // Upstream from Pipeline Buffer/FIFO
    input logic valid_in,
    output logic ready_in,
    input dispatch_pipeline_data data_in,
    
    // Downstream
    input logic ready_out,
    output logic valid_out,
    output alu_rs_data data_out
    );
    
    alu_rs_data [7:0] rs_table;
    
    integer valid_index;
    
    always_ff @(posedge clk) begin
        if (reset) begin
            valid_index <= 0;
            for (int i = 0; i < 8; i++) begin
                rs_table[i].valid <= 1'b1;
                rs_table[i].Opcode <= 7'b0;
                rs_table[i].prd <= 8'b0;
                rs_table[i].pr1 <= 8'b0;
                rs_table[i].pr1_ready <= 1'b0;
                rs_table[i].pr2 <= 8'b0;
                rs_table[i].pr2_ready <= 1'b0;
                rs_table[i].imm <= 32'b0;
                rs_table[i].fu <= 2'b0;
                rs_table[i].rob_index <= 4'b0;
                rs_table[i].age <= 3'b0;
            end
        end else begin
            // get index of free slot
            for (int j = 0; j < 8; j++) begin
                if (rs_table[j].valid) begin
                    valid_index = j; // immediately update
                    break;
                end
            end
            
            // if slot is free, insert instruction
            if (rs_table[valid_index].valid) begin
                // increment age
                for (int i = 0; i < 8; i++) begin
                    if (rs_table[i].valid && rs_table[i].age < 3'b111) begin
                        rs_table[i].age <= rs_table[i].age + 1;
                        break;
                    end
                end
            
                rs_table[valid_index].valid <= 1'b0;
                rs_table[valid_index].Opcode <= data_in.Opcode;
                rs_table[valid_index].prd <= data_in.prd;
                rs_table[valid_index].pr1 <= data_in.pr1;
                //rs_table[valid_index].pr1_ready = 1'b0;
                rs_table[valid_index].pr2 <= data_in.pr2;
                //rs_table[valid_index].pr2_ready = 1'b0;
                rs_table[valid_index].imm <= data_in.imm;
                //rs_table[valid_index].fu = 2'b0;
                rs_table[valid_index].rob_index <= data_in.rob_index;
                rs_table[valid_index].age <= 3'b0;
            end
            
        end
    end
    
    
endmodule
