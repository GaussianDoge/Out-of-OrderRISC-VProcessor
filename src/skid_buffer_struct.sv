`timescale 1ns / 1ps

module skid_buffer_struct #(
    parameter type T = logic 
    )(
    input logic     clk,
    input logic     reset,
    input logic     mispredict,
    
    // upstream (producer -> skid)
    input logic     valid_in,
    output logic    ready_in,
    input T         data_in,
    
    // downstream (skid -> consumer)
    output logic    valid_out,
    input logic     ready_out,
    output T        data_out
    );
    
    // downstream
    logic   valid_out_sig;
    T       buffer;

    //assign ready_in = ready_out && !valid_out_sig;
    assign valid_out = valid_out_sig;
    assign data_out = buffer;
    assign ready_in = ready_out;
    
    always_ff @ (posedge clk) begin
        if (reset || mispredict) begin
            ready_in <= 1'b1;
            valid_out_sig <= 1'b0;
            buffer <= 0;
        end else begin
            // handle upstream
            if (valid_in && ready_in) begin
                buffer <= data_in;
                valid_out_sig <= 1'b1;
            end else if (ready_out && valid_out) begin
                valid_out_sig <= 1'b0;
            end
        end
    end
endmodule
