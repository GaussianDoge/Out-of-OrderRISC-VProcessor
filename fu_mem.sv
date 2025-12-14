`timescale 1ns / 1ps

import types_pkg::*;

module fu_mem(
    input clk,
    input reset,
        
    // From ROB
    input logic retired,
    input logic [4:0] rob_head,
    input logic [4:0] dispatch_rob_tag,
    input logic mispredict,
    input logic [4:0] mispredict_tag,
    
    // From Dispatch (LSQ Allocation)
    input logic dispatch_valid,
    
    // From RS and PRF
    input logic issued,
    input rs_data data_in,
    input logic [31:0] ps1_data,
    input logic [31:0] ps2_data,
    
    // Output data
    output mem_data data_out
);
    logic valid;
    logic [31:0] addr;
    logic [31:0] data_mem;
    logic [6:0] pd_reg;
    logic [4:0] rob_reg;
    logic load_en;
    
    // LSQ Signals
    logic store_wb;
    lsq lsq_out;
    logic lsq_full;
    logic [4:0] store_rob_tag;
    
    // Forwarding Wires
    logic [31:0] fwd_data;
    logic fwd_valid;
    logic safe_to_mem;
    
    always_comb begin
        // L-type and S-type instructions
        if (data_in.Opcode == 7'b0000011) begin
            addr = ps1_data + data_in.imm;
        end else begin
            addr = '0;
        end
    end    
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            load_en <= 1'b0;
            pd_reg     <= '0;
            rob_reg    <= '0;
        end else begin
            if (mispredict) begin
                load_en <= 1'b0;
            end else begin
                // Load is issued & there isn't a load currently occuring & no FWD & memory address is safe to access
                if (issued && data_in.Opcode == 7'b0000011 && !load_en && !fwd_valid && safe_to_mem) begin
                    load_en <= 1'b1;
                    pd_reg     <= data_in.pd;
                    rob_reg    <= data_in.rob_index;
                end

                // Clear when memory returns valid data
                if (valid && load_en) begin
                    load_en <= 1'b0;
                end
            end
        end
    end
    
    always_comb begin   
        data_out.fu_mem_ready = 1'b1;
        data_out.fu_mem_done  = 1'b0;
        data_out.p_mem = '0;
        data_out.rob_fu_mem = '0;
        data_out.data = '0;
        
        
        if (load_en) begin
            data_out.fu_mem_ready = 1'b0;
        end 
        
        // stall if we're full when store
        if (data_in.Opcode == 7'b0100011 && lsq_full) begin
            data_out.fu_mem_ready = 1'b0;
        end
        
        if (!mispredict) begin
            if (issued) begin
                if (data_in.Opcode == 7'b0100011 && !lsq_full) begin // SW
                    data_out.fu_mem_ready = 1'b1;
                    data_out.fu_mem_done = 1'b1;
                    data_out.rob_fu_mem = store_rob_tag; 
                end 
                else if (data_in.Opcode == 7'b0000011) begin // LW
                    // FWD hit
                    if (fwd_valid) begin
                        data_out.fu_mem_done = 1'b1;      
                        data_out.data = fwd_data;         
                        data_out.p_mem = data_in.pd;
                        data_out.rob_fu_mem = data_in.rob_index;
                    end
                    // Memory hazard
                    else if (!safe_to_mem) begin
                        // Hazard detected. We stall ready, but we don't latch internally.
                        // Ideally RS should retry.
                        data_out.fu_mem_ready = 1'b0;
                    end
                end
            end
            
            // Memory response
            if (valid && load_en) begin
                data_out.fu_mem_ready = 1'b1;   // free again     
                data_out.fu_mem_done  = 1'b1;
                data_out.p_mem        = pd_reg;
                data_out.rob_fu_mem   = rob_reg;
                data_out.data         = data_mem;
            end
        end
    end
    
    lsq u_lsq (
        .clk(clk),
        .reset(reset),
        
        .dispatch_rob_tag(dispatch_rob_tag),
        .dispatch_valid(dispatch_valid),

        .ps1_data(ps1_data),
        .imm_in(data_in.imm),
        
        // From PRF
        .ps2_data(ps2_data),
        .issued(issued),
        .data_in(data_in),
        
        // From ROB
        .retired(retired),
        .rob_head(rob_head),
        .store_wb(store_wb),

        .data_out(lsq_out),
        
        .load_forward_data(fwd_data),
        .load_forward_valid(fwd_valid),
        .load_mem(safe_to_mem),
        
        .store_rob_tag(store_rob_tag),
        .full(lsq_full) 
    );
    
    // Drive Memory only if safe and not FWD
    logic dmem_issued;
    assign dmem_issued = issued && (data_in.Opcode == 7'b0000011) && safe_to_mem && !fwd_valid;
    
    data_memory u_dmem (
        .clk(clk),
        .reset(reset),
        
        .addr(addr),
        .issued(issued),
        .data_in(data_in),
        
        // From LSQ for S-type
        .store_wb(store_wb),
        .lsq_in(lsq_out),
        
        .data_out(data_out),
        .valid(valid)
    );
    
endmodule
