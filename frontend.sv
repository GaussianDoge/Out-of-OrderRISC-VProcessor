`timescale 1ns / 1ps
// This module is for testing purpose

module frontend(
    input logic clk,
    input logic reset,
    input logic [31:0] pc_in,
    output decode_data data_out
    );
    
    logic pc_out;
    logic pc_4;
    logic fetch_instr_out;
    logic fetch_valid_out;
    
    logic decode_ready_in;
    logic decode_valid_out;
    logic decode_data_out;
    logic decode_buffer_ready_in;
    
    fetch fetch_unit (
        .clk(clk),
        .reset(reset),
        .pc_in(pc_in),
        .ready_out(decode_ready_in),
        .instr_out(fetch_instr_out),
        .pc_out(pc_out),
        .pc_4(pc_4),
        .valid_out(fetch_valid_out)
    );
    
    decode decode_unit (
        .clk      (clk),
        .reset    (reset),
        .instr    (fetch_instr_out),
        .pc_in    (pc_out),
        .valid_in (fetch_valid_out),
        .ready_in (decode_ready_in),
        .ready_out(ready_out),
        .valid_out(decode_valid_out),
        .data_out (decode_data_out)
    );
    
    skid_buffer_struct #(
        .T ( decode_data )
    ) decode_buffer (
        .clk        (clk),
        .reset      (reset),
        
        .valid_in   (decode_valid_out),
        .ready_in   (decode_buffer_ready_in),
        .data_in    (decode_data_out),
        
        .valid_out  (),
        .ready_out  (),
        .data_out   (data_out)
    );
    
endmodule
