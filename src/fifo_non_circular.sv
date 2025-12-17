`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/19/2025 09:59:56 AM
// Design Name: 
// Module Name: fifo
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module fifo #(
    parameter type T = logic [31:0],
    parameter DEPTH = 8
)(
    input logic clk,
    input logic reset,
    
    input logic write_en,
    input T write_data,
    input logic read_en,
    output T read_data,
    output logic full,
    output logic empty
);
    T mem[DEPTH-1:0];
    logic [$clog2(DEPTH):0] wr_cnt;
    T r_data;
    
    always_comb begin
        full = (wr_cnt == DEPTH);
        empty = (wr_cnt == '0);
        read_data = r_data;
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            for (integer i = 0; i < DEPTH; i++) begin
                mem[i] <= '0;
            end
            wr_cnt <= '0;
            r_data <= '0;
        end
        else begin 
            if (write_en && !full) begin
                for (int i = wr_cnt; i > 0; i--) begin
                        mem[i] <= mem[i-1];
                end
                mem[0] <= write_data;
                if (wr_cnt < DEPTH) begin
                    wr_cnt <= wr_cnt + 1;
                end
            end
            if (read_en && !empty) begin
                if (wr_cnt > 0) begin
                    r_data <= mem[wr_cnt-1];
                    wr_cnt <= wr_cnt - 1;
                end
                else begin
                    $display("The memory is empty");
                end
            end
        end
    end
endmodule
