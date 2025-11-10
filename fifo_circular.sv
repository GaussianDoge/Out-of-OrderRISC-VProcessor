module circular_buffer #(
  parameter type T = logic [31:0],
  parameter int  DEPTH = 8
)(
  input  logic clk,
  input  logic reset,

  input  logic write_en,
  input  T     write_data,
  input  logic read_en,
  output T     read_data,
  output logic full,
  output logic empty
);

  T mem [DEPTH];       
  logic [3:0]  w_ptr, r_ptr;      
  logic [3:0]  ctr;            
  T r_data_q;

  assign read_data = r_data_q;
  assign full  = (ctr == DEPTH);
  assign empty = (ctr == 0);

  always_ff @(posedge clk) begin
    if (reset) begin
      w_ptr    <= '0;
      r_ptr    <= '0;
      ctr      <= '0;
      r_data_q <= '0;
    end else begin
      automatic logic do_write = write_en;           
      automatic logic do_read  = read_en && (ctr!=0); 
      if (do_write && (ctr == DEPTH) && !do_read) begin
        r_ptr <= (r_ptr + 1) % DEPTH;
      end
      if (do_read) begin
        r_data_q <= mem[r_ptr];
        r_ptr    <= (r_ptr + 1) % DEPTH;
      end
      if (do_write) begin
        mem[w_ptr] <= write_data;
        w_ptr      <= (w_ptr + 1) % DEPTH;
      end

      unique case ({do_write, do_read})
        2'b10: if (ctr < DEPTH) ctr <= ctr + 1'b1;
        2'b01: ctr <= ctr - 1'b1;    
        default: ctr <= ctr;          
      endcase
    end
  end
endmodule
