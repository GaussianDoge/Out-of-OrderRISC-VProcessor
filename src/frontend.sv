`timescale 1ns / 1ps

module frontend(
    input logic clk,
    input logic reset,
    input logic [31:0] pc_in,
    
    // Handle Mispredict
    input logic mispredict,
    
    // Downstream of pipeline
    input logic frontend_ready_out,
    output decode_data data_out,
    output logic frontend_valid_out
    );
    
    logic [31:0] pc_out;
    logic [31:0] pc_4;
    logic [31:0] fetch_instr_out;
    logic fetch_valid_out;
    
    logic decode_ready_in;
    logic decode_valid_out;
    decode_data decode_data_out;
    logic decode_buffer_ready_in;
    
    

    
    fetch fetch_unit (
        .clk(clk),
        .reset(reset),
        .mispredict(mispredict),
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
        .mispredict(mispredict),
        .instr    (fetch_instr_out),
        .pc_in    (pc_out),
        .valid_in (fetch_valid_out),
        .ready_in (decode_ready_in),
        .ready_out(decode_buffer_ready_in),
        .valid_out(decode_valid_out),
        .data_out (decode_data_out)
    );
    
    skid_buffer_struct #(
        .T ( decode_data )
    ) decode_buffer (
        .clk        (clk),
        .reset      (reset),
        .mispredict (mispredict),
        
        .valid_in   (decode_valid_out),
        .ready_in   (decode_buffer_ready_in),
        .data_in    (decode_data_out),
        
        .valid_out  (frontend_valid_out),
        .ready_out  (frontend_ready_out),
        .data_out   (data_out)
    );
    
endmodule
