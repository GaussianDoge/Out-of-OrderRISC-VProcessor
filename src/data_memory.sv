`timescale 1ns/1ps
import types_pkg::*;

module data_memory #(
    parameter int BYTE_DEPTH = 102400
)(
    input  logic   clk,
    input  logic   reset,

    // store commit
    input  logic   store_wb,
    input  lsq     lsq_in,

    // load request
    input  logic   load_mem,
    input  lsq     lsq_load,

    // output
    output mem_data data_out,
    output logic    load_ready,
    output logic    valid
);

    // -------- Word-addressed memory --------
    localparam int WORD_DEPTH = (BYTE_DEPTH + 3) / 4;
    localparam int WADDR_BITS = $clog2(WORD_DEPTH);

    (* ram_style = "block" *)
    logic [31:0] mem [0:WORD_DEPTH-1];

    // -----------------------------
    // Write port (stores)
    // -----------------------------
    logic [WADDR_BITS-1:0] waddr;
    logic [1:0]            woff;

    always_comb begin
        waddr = lsq_in.addr[WADDR_BITS+1:2];  // word address
        woff  = lsq_in.addr[1:0];             // byte offset
    end

    always_ff @(posedge clk) begin
        if (store_wb) begin
            // NOTE: This assumes naturally-aligned stores for sw/sh (typical RISC-V).
            // If you allow unaligned, you must split across two words.

            if (lsq_in.sw_sh_signal == 1'b0) begin
                // sw: write all bytes
                mem[waddr][7:0]   <= lsq_in.ps2_data[7:0];
                mem[waddr][15:8]  <= lsq_in.ps2_data[15:8];
                mem[waddr][23:16] <= lsq_in.ps2_data[23:16];
                mem[waddr][31:24] <= lsq_in.ps2_data[31:24];
            end else begin
                // sh: write 2 bytes based on addr[1]
                if (woff[1] == 1'b0) begin
                    mem[waddr][7:0]   <= lsq_in.ps2_data[7:0];
                    mem[waddr][15:8]  <= lsq_in.ps2_data[15:8];
                end else begin
                    mem[waddr][23:16] <= lsq_in.ps2_data[7:0];
                    mem[waddr][31:24] <= lsq_in.ps2_data[15:8];
                end
            end
        end
    end

    // -----------------------------
    // Read port (loads) - 1 cycle latency (BRAM-style)
    // -----------------------------
    logic                  rd_pending;   // becomes the "valid next cycle" flag
    logic [WADDR_BITS-1:0] raddr_q;
    logic [1:0]            roff_q;
    logic [2:0]            func3_q;
    logic [4:0]            rob_q;
    logic [6:0]            pd_q;         // use correct width for your design
    logic [31:0]           rdata_q;      // REGISTERED memory output (key for BRAM)
    
    logic [4:0] pre_rob_index;
    
    always_ff @(posedge clk or posedge reset) begin
      if (reset) begin
        valid         <= 1'b0;
        load_ready    <= 1'b1;
        rd_pending    <= 1'b0;
        pre_rob_index <= 5'b11111;
        data_out      <= '0;
    
        raddr_q <= '0;
        roff_q  <= '0;
        func3_q <= '0;
        rob_q   <= '0;
        pd_q    <= '0;
        rdata_q <= '0;
    
      end else begin
        valid      <= 1'b0;
        load_ready <= 1'b1;
    
        // default: no response next cycle unless we accept a request now
        rd_pending <= 1'b0;
    
        // REQUEST STAGE (cycle N): capture meta AND do sync read into rdata_q
        if (load_mem && !store_wb && !lsq_load.store && (pre_rob_index != lsq_load.rob_tag)) begin
          rd_pending    <= 1'b1;  // this will trigger response in cycle N+1
    
          raddr_q       <= lsq_load.addr[WADDR_BITS+1:2];
          roff_q        <= lsq_load.addr[1:0];
          func3_q       <= lsq_load.func3;
          rob_q         <= lsq_load.rob_tag;
          pd_q          <= lsq_load.pd;
          pre_rob_index <= lsq_load.rob_tag;
    
          // THIS is the BRAM-inferable read:
          // use the request address directly (not mem[raddr_q]) so it's 1-cycle total
          rdata_q       <= mem[lsq_load.addr[WADDR_BITS+1:2]];
    
          load_ready <= 1'b0;
        end
    
        // RESPONSE STAGE (cycle N+1): use registered rdata_q (no mem[] access here!)
        if (rd_pending) begin
          valid                <= 1'b1;
          data_out.fu_mem_ready <= 1'b1;
          data_out.fu_mem_done  <= 1'b1;
          data_out.rob_fu_mem   <= rob_q;
          data_out.p_mem        <= pd_q;
    
          unique case (func3_q)
            3'b010: begin // lw
              data_out.data <= rdata_q;
            end
            3'b100: begin // lbu
              unique case (roff_q)
                2'd0: data_out.data <= {24'b0, rdata_q[7:0]};
                2'd1: data_out.data <= {24'b0, rdata_q[15:8]};
                2'd2: data_out.data <= {24'b0, rdata_q[23:16]};
                2'd3: data_out.data <= {24'b0, rdata_q[31:24]};
              endcase
            end
            default: data_out.data <= 32'b0;
          endcase
        end
      end
    end

endmodule
