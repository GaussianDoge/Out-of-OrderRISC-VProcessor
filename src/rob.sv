import types_pkg::*;

module rob (
    input  logic clk,
    input  logic reset,
    
    // from Dispatch stage
    input  logic write_en,
    input  logic [6:0] pd_new_in,
    input  logic [6:0] pd_old_in,
    input logic [31:0] pc_in,
    
    // from FUs
    input logic fu_alu_done,
    input logic fu_b_done,
    input logic fu_mem_done,
    input logic [4:0] rob_fu_alu,
    input logic [4:0] rob_fu_b,
    input logic [4:0] rob_fu_mem,
    input logic [4:0] store_rob_tag,
    input logic store_lsq_done,
    input logic br_mispredict,
    input logic [4:0] br_mispredict_tag,
    
    // Update free_list
    output logic [6:0] preg_old,
    output logic valid_retired,
    
    // Signal LSQ to put data into memory
    output logic [4:0] head,

    // Global mispredict 
    output logic mispredict,
    output logic [4:0] mispredict_tag,
    output logic [31:0] mispredict_pc, 
    output logic [4:0] ptr,

    output logic full
//    output logic [4:0] retired_ptr
);
//    assign retired_ptr = r_ptr; 

    assign mispredict = br_mispredict;
    assign mispredict_tag = br_mispredict_tag;
    assign mispredict_pc = rob_table[br_mispredict_tag].pc;
    rob_data rob_table[0:15];
    
    logic [3:0]  w_ptr, r_ptr;      
    assign ptr = w_ptr;
    //assign head = r_ptr;
    
    logic [3:0]  ctr;            
    
    assign full = (ctr == 15); 
    
    logic do_write;           
    logic do_retire;
    
    assign do_retire = (ctr!=0) && rob_table[r_ptr].complete && rob_table[r_ptr].valid;
    assign do_write = write_en && !full;

    always_ff @(posedge clk) begin
        if (reset) begin
            w_ptr    <= '0;
            r_ptr    <= '0;
            ctr      <= '0;
            for (int i = 0; i < 16; i++) begin
                rob_table[i] <= '0;
            end
        end else begin
            valid_retired <= 1'b0;
            // Update the complete column for a specific instruction
            if (fu_alu_done && rob_table[rob_fu_alu].valid) begin
                rob_table[rob_fu_alu].complete <= 1'b1;
            end
            if (fu_b_done && rob_table[rob_fu_b].valid) begin
                rob_table[rob_fu_b].complete <= 1'b1;
            end
            if (fu_mem_done && rob_table[rob_fu_mem].valid) begin
                rob_table[rob_fu_mem].complete <= 1'b1;
            end
            if (store_lsq_done && rob_table[store_rob_tag].valid) begin
                rob_table[store_rob_tag].complete <= 1'b1;
            end
            // Mispredict operation
            if (br_mispredict) begin
                automatic logic [3:0] old_w = w_ptr;            
                automatic logic [3:0] re_ptr = (br_mispredict_tag==15)?0:br_mispredict_tag+1;  
                automatic logic [3:0] newcnt = (re_ptr >= r_ptr) ? (re_ptr - r_ptr) : (4'd15 - r_ptr + re_ptr);
        
                for (logic [3:0] i=re_ptr; i!=old_w; i=(i==15)?0:i+1) begin
                    rob_table[i] <= '0;
                end
                
                w_ptr <= re_ptr;
                ctr <= newcnt;
            end
            else begin
                // inform reservation station an instruction is retired, 
                // also reset that row in the table, advance r_ptr by 1
                if (do_retire) begin
                    preg_old <= rob_table[r_ptr].pd_old;
                    valid_retired <= 1'b1;
                    head <= r_ptr;
                    rob_table[r_ptr] <= '0;
                    r_ptr <= (r_ptr == 4'd15) ? 4'b0 : r_ptr + 1;
                end
                
                // Dispatch instruction to ROB
                if (do_write) begin
                    rob_table[w_ptr].pd_new <= pd_new_in;
                    rob_table[w_ptr].pd_old <= pd_old_in;
                    rob_table[w_ptr].pc <= pc_in;
                    rob_table[w_ptr].complete <= 1'b0;
                    rob_table[w_ptr].valid <= 1'b1;
                    rob_table[w_ptr].rob_index <= w_ptr;
                    w_ptr <= (w_ptr == 4'd15) ? 4'b0 : w_ptr + 1;
                end
                unique case ({do_retire, do_write})
                  2'b10: ctr <= ctr - 4'd1;
                  2'b01: ctr <= ctr + 4'd1; 
                  default: ctr <= ctr;     
                endcase
            end
        end
    end
endmodule
