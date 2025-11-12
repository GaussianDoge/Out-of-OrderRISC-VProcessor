import types_pkg::*;

module rob (
    input  logic clk,
    input  logic reset,
    
    // from rename stage
    input  logic write_en,
    input  logic [7:0] pd_new_in,
    input  logic [7:0] pd_old_in,
    input logic [31:0] pc_in,
    
    // from FU stage 
    input logic complete_in,
    input logic [4:0] rob_fu,
    input logic mispredict,
    input logic branch,
    input logic [4:0] mispredict_tag,
    
    // Update RS
    output logic [4:0] rob_tag_out,
    output logic valid_retired,
    // Update FU availability
    output logic complete_out,

    output logic full,
    output logic empty
);
    rob_data rob_table[0:15];
    
    logic [4:0]  w_ptr, r_ptr;      
    logic [4:0]  ctr;            
    
    assign full = (ctr == 16); 
    assign empty = (ctr == 0);
    
    logic do_write;           
    logic do_retire;
    
    assign do_retire = rob_table[r_ptr].complete && rob_table[r_ptr].valid;
    assign do_write = write_en && !full;
    assign complete_out = rob_table[r_ptr].complete;

    always_ff @(posedge clk) begin
        if (reset) begin
            w_ptr    <= '0;
            r_ptr    <= '0;
            ctr      <= '0;
            for (int i = 0; i < 16; i++) begin
                rob_table[i] = '0;
            end
        end else begin
            valid_retired <= 1'b0;
            // Update the complete column for a specific instruction
            if (complete_in && rob_table[rob_fu].valid) begin
                rob_table[rob_fu].complete <= 1'b1;
            end
            // Mispredict operation
            if (mispredict) begin
                automatic logic [4:0] old_w = w_ptr;            
                automatic logic [4:0] re_ptr = (mispredict_tag==15)?0:mispredict_tag+1;  
                automatic logic [4:0] newcnt = (re_ptr >= r_ptr) ? (re_ptr - r_ptr) : (5'd16 - r_ptr + re_ptr);
        
                for (logic [4:0] i=re_ptr; i!=old_w; i=(i==15)?0:i+1) begin
                    rob_table[i] <= '0;
                end
                
                w_ptr <= re_ptr;
                ctr <= newcnt;
            end
            else begin
                // inform reservation station an instruction is retired, 
                // also reset that row in the table, advance r_ptr by 1
                if (do_retire) begin
                    rob_tag_out <= r_ptr;
                    valid_retired <= 1'b1;
                    rob_table[r_ptr] <= '0;
                    r_ptr <= (r_ptr == 5'd15) ? 5'b0 : r_ptr + 1;
                end
                
                // Dispatch instruction to ROB
                if (do_write) begin
                    rob_table[w_ptr].pd_new <= pd_new_in;
                    rob_table[w_ptr].pd_old <= pd_old_in;
                    rob_table[w_ptr].pc <= pc_in;
                    rob_table[w_ptr].complete <= 1'b0;
                    rob_table[w_ptr].valid <= 1'b1;
                    rob_table[w_ptr].rob_index <= w_ptr;
                    w_ptr <= (w_ptr == 5'd15) ? 5'b0 : w_ptr + 1;
                end
                unique case ({do_retire, do_write})
                  2'b10: ctr <= ctr - 5'd1;
                  2'b01: ctr <= ctr + 5'd1; 
                  default: ctr <= ctr;     
                endcase
            end
        end
    end
endmodule
