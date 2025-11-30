`timescale 1ns / 1ps

module processor(
    input logic clk,
    input logic reset
    );
    
    // General data for all stages
    logic [31:0] pc;
    logic mispredict;
    
    // For frontend(Fetch and Decode) and Rename
    logic rename_ready_in;
    decode_data frontend_data_out;
    logic frontend_valid_out;
    
    frontend frontend_unit(.clk(clk), 
                           .reset(reset), 
                           .pc_in(pc),
                           .mispredict(mispredict),
                           .frontend_ready_out(rename_ready_in),
                           .data_out(frontend_data_out),
                           .frontend_valid_out(frontend_valid_out));
    
    rename_data rename_data_out;
    logic rename_valid_out;
    logic dispatch_ready_in;
    
    rename rename_unit(.clk(clk), 
                       .reset(reset), 
                       .pc_in(pc), 
                       .frontend_ready_out(frontend_valid_out), 
                       .data_in(frontend_data_out),
                       .ready_in(rename_ready_in),
                       .mispredict(mispredict),
                       .data_out(rename_data_out),
                       .valid_out(rename_valid_out),
                       .ready_out(dispatch_ready_in));
    
    dispatch dispatch_unit();
    
    
endmodule
