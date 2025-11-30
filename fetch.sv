`timescale 1ns / 1ps

module fetch(
    input logic clk,
    input logic reset,
    input logic mispredict,
    
    // Upstream 
    input logic [31:0] pc_in,

    // Downstream
    input logic ready_out,
    output logic [31:0] instr_out,
    output logic [31:0] pc_out,
    output logic [31:0] pc_4,
    output logic valid_out
);

    logic [31:0] instr_icache;


    // This will be used to pass in and out of the skid buffer
    logic [63:0] data_next;
    
    ICache ICache_dut (
        .clk(clk),
        .reset(reset),
        .address(pc_in),
        .instruction(instr_icache)
    );
    
    assign data_next = {pc_in, instr_icache};

    // Buffered signal
    logic [63:0] data_buf;

    // Create a 1-cycle delayed "always valid" signal
    logic valid_in_delayed;
    
    always_ff @(posedge clk) begin
        if (reset) begin
            valid_in_delayed <= 1'b0;
        end else begin
            valid_in_delayed <= 1'b1;
        end
    end

    skid_buffer_struct #(
        .T ( logic [63:0] )
    ) fetch_decode_buffer (
        .clk        (clk),
        .reset      (reset),
        .mispredict (mispredict),
        
        .valid_in   (valid_in_delayed),
        .ready_in   (),
        .data_in    (data_next),
        
        .valid_out  (valid_out),
        .ready_out  (ready_out),
        .data_out   (data_buf)
    );

    // Unpacking the buffered data
    assign pc_out    = data_buf[63:32];
    assign instr_out = data_buf[31:0];

    // Incrementing PC
    assign pc_4 = pc_out + 32'd4;

endmodule