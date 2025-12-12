`timescale 1ns / 1ps
import types_pkg::*;

module lsq(
    input logic clk,
    input logic reset,
    
    // From FU_mem
    input logic [31:0] ps1_data,
    input logic [31:0] imm_in,
    
    // From PRF 
    input logic [31:0] ps2_data,
    
    // From RS
    input logic issued,
    input rs_data data_in, 
    
    // From ROB
    input logic retired,
    input logic [4:0] rob_head,
    output logic store_wb,
    output lsq data_out,
    output logic store_done,
    output logic store_ready,
    output logic [4:0] store_rob_tag,
    output full
);
    lsq lsq_arr[0:7];
    logic [2:0] w_ptr;
    logic [2:0] r_ptr;
    logic [3:0] ctr;
    
    assign full = (ctr == 8);
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            ctr <= '0;
            w_ptr <= '0;
            r_ptr <= '0;
            store_wb <= 1'b0;
            data_out <= '0;
            for (logic [2:0] i = 0; i <= 7; i++) begin
                lsq_arr[i] <= '0;
            end
        end else begin
            store_wb <= 1'b0;
            data_out <= '0;
            if (issued && !full) begin
                if (data_in.Opcode == 7'b0100011) begin
                    lsq_arr[w_ptr].valid <= 1'b1;
                    lsq_arr[w_ptr].addr <= ps1_data + imm_in;
                    lsq_arr[w_ptr].rob_tag <= data_in.rob_index;
                    lsq_arr[w_ptr].ps2_data <= ps2_data;
                    lsq_arr[w_ptr].pd <= data_in.pd;
                    if (data_in.func3 == 3'b010) begin // sw
                        lsq_arr[w_ptr].sw_sh_signal <= 1'b0;
                    end else if (data_in.func3 == 3'b001) begin // sh
                        lsq_arr[w_ptr].sw_sh_signal <= 1'b1;
                    end
                    ctr <= ctr + 1;
                    w_ptr <= (w_ptr == 7) ? 0 : w_ptr + 1;
                    
                    store_done = 1'b1;
                    store_ready = 1'b1;
                    store_rob_tag = data_in.rob_index;
                end
            end 
            if (retired) begin
                if (lsq_arr[r_ptr].valid && rob_head == lsq_arr[r_ptr].rob_tag) begin
                    store_wb <= 1'b1;
                    data_out <= lsq_arr[r_ptr];
                    lsq_arr[r_ptr] <= '0;
                    r_ptr <= (r_ptr == 7) ? 0 : r_ptr + 1;
                    ctr <= ctr - 1;
                end
            end 
        end 
    end
    
endmodule
