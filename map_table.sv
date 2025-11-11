`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/09/2025 08:38:55 PM
// Design Name: 
// Module Name: map_table
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


module map_table(
    input logic clk,
    input logic reset,
    // Data from rename
    input logic spec,
    input logic mispredict,
    input logic update_en,
    input logic [4:0] rd,
    input logic [7:0] pd_new,
    
    input logic [7:0] re_map [0:31],
    output logic [7:0] map [0:31]
);
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < 32; i ++) begin
                map[i] <= i;
            end
        end else begin
            if (mispredict) begin
                map <= re_map;
            end else if (!spec && update_en && rd != 5'd0) begin
                map[rd] <= pd_new;
            end 
        end
    end
endmodule
