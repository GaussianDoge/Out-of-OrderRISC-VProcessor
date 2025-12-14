`timescale 1ns / 1ps

module checkpoint(
    input logic clk,
    input logic reset,

    input logic branch_detect,
    input logic [31:0] branch_pc,
    input logic [4:0] branch_rob_tag,
    input logic mispredict,
    output logic checkpoint_valid
    );


endmodule
