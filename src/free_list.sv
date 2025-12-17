module free_list#(
parameter int DEPTH = 128
)(
    input logic clk,
    input logic reset,
    
    // Commit/Deallocate
    input logic write_en,
    input logic [6:0] data_in,

    // Allocate
    input logic read_en,
    output logic [6:0] pd_new_out, // Output: The actual register ID
    output logic empty,

    input logic mispredict,
    input logic [6:0] re_r_ptr,
    input logic [6:0] re_w_ptr,
    input logic [0:DEPTH-1] [6:0] re_list,

    output logic [6:0] r_ptr_out,
    output logic [6:0] w_ptr_out,
    output logic [0:DEPTH-1] [6:0] list_out 
);

    logic [0:DEPTH-1] [6:0] list;
    logic [6:0] w_ptr, r_ptr;
    logic [6:0] ctr;
    
    // Snapshot Outputs
    assign r_ptr_out = r_ptr;
    assign w_ptr_out = w_ptr;
    assign list_out  = list;

    assign pd_new_out = list[r_ptr];  
    assign empty = (ctr == 0);
    
    logic do_write;
    logic do_read;
    
    assign do_write = write_en && (ctr!=7'd127);
    assign do_read = read_en && (ctr!=0);
    
    logic [6:0] distance;
    always_comb begin 
        if (r_ptr >= re_r_ptr) begin
            distance = r_ptr - re_r_ptr;
        end else begin
            distance = DEPTH - re_r_ptr + r_ptr;
        end
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            w_ptr    <= 0;
            r_ptr    <= 0;
            ctr      <= 127;
            // Start allocation at p32 as p0-p31 are reserved for x0-x31
            for (int i = 0; i < DEPTH; i++) begin
                list[i] <= i + 32;
            end
        end else begin
            // Mispredict case
            if (mispredict) begin
                ctr <= ctr + distance;
                r_ptr <= re_r_ptr;
                w_ptr <= re_w_ptr;
                list  <= re_list;
            end else begin
                // Normal Read (Allocation)
                if (do_read) begin
                    r_ptr <= (r_ptr == 127) ? 1 : r_ptr + 1;
                end
                
                // Normal Write (Freeing/Commit)
                if (do_write) begin
                    list[w_ptr] <= data_in; // CRITICAL: Actually save the ID
                    w_ptr       <= (w_ptr == 127) ? 1 : w_ptr + 1;
                end
            
                // Counter Update
                unique case ({do_write, do_read})
                    2'b10: ctr <= ctr + 1'b1;
                    2'b01: ctr <= ctr - 1'b1;    
                    default: ctr <= ctr;          
                endcase
            end
        end
    end
endmodule
