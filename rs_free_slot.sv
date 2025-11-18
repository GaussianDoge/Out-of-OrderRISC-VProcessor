`timescale 1ns / 1ps
import types_pkg::*;

module rs_free_slot(
    input rs_data [7:0] rs_table,
    output logic [2:0] index1,
    output logic [2:0] index2,
    output logic [3:0] free_space,
    output logic have_free1,
    output logic have_free2
    );

    always_comb begin
        have_free1 = 1'b0;
        have_free2 = 1'b0;
        free_space = 4'b0;
        have_free1 = 1'b0;
        have_free2 = 1'b0;
        
        for (int i = 0; i < 8; i++) begin
            if (rs_table[i].valid) begin
                free_space = free_space + 1;
                if (!have_free1) begin
                    index1 = i[$clog2(8)-1:0];
                    have_free1 = 1'b1;
                end else if (!have_free2) begin
                    index2 = i[$clog2(8)-1:0];
                    have_free2 = 1'b1;
                end
            end
        end
    end
endmodule
