`timescale 1ns / 1ps
import types_pkg::*;

module rs_bu(
    input logic clk,
    input logic reset,
    input logic fu_rdy,
    
    // Upstream
    input logic valid_in,
    output logic ready_in,
    input dispatch_pipeline_data instr,
    
    // Downstream
    output logic valid_out,
    output rs_data data_out,
    
    // Combinational update readyness (CDB)
    input logic [6:0] reg1_rdy,
    input logic [6:0] reg2_rdy,
    input logic [6:0] reg3_rdy,
    input logic reg1_rdy_valid,
    input logic reg2_rdy_valid,
    input logic reg3_rdy_valid,
    
    // Recover
    input logic flush,
    input logic [4:0] flush_tag,   // Unused in Total Flush
    input logic [31:0] flush_pc    // Unused in Total Flush
    );

    rs_data [7:0] rs_table;
    
    logic [2:0] head_ptr;
    logic [2:0] tail_ptr;
    logic [3:0] count;

    assign ready_in = (count < 4'd8);

    // Update rs_table
    always_comb begin

        // Update ready status of reg; Assuming at most retire 3 instr
        for (int i = 0; i < 8; i++) begin
            if (rs_table[i].ps1 == reg1_rdy && reg1_rdy_valid) begin
                rs_table[i].ps1_ready = 1'b1;
            end else if (rs_table[i].ps2 == reg1_rdy && reg1_rdy_valid) begin
                rs_table[i].ps2_ready = 1'b1;
            end else begin
            end
            
            if (rs_table[i].ps1 == reg2_rdy && reg2_rdy_valid) begin
                rs_table[i].ps1_ready = 1'b1;
            end else if (rs_table[i].ps2 == reg2_rdy && reg2_rdy_valid) begin
                rs_table[i].ps2_ready = 1'b1;
            end else begin
            end
            
            if (rs_table[i].ps1 == reg3_rdy && reg3_rdy_valid) begin
                rs_table[i].ps1_ready = 1'b1;
            end else if (rs_table[i].ps2 == reg3_rdy && reg3_rdy_valid) begin
                rs_table[i].ps2_ready = 1'b1;
            end else begin
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset || flush) begin
            // Since In-Order Issue, anything left in the RS is younger than the branch and must be flushed.
            head_ptr   <= 3'b0;
            tail_ptr   <= 3'b0;
            count      <= 4'b0;
            valid_out  <= 1'b0;
            data_out   <= '0;
            ready_in <= 1'b1;
            
            // Optional: Zero out table for cleanliness (not strictly required for logic)
            for(int i=0; i<8; i++) rs_table[i] <= '0;

        end else begin
            // Default valid_out
            valid_out <= 1'b0;

            // Dispatch
            if (valid_in && ready_in) begin
                // 1. Write Data
                rs_table[tail_ptr].valid <= 1'b0;
                rs_table[tail_ptr].Opcode <= instr.Opcode;
                rs_table[tail_ptr].pd <= instr.prd;
                rs_table[tail_ptr].ps1 <= instr.pr1;
                rs_table[tail_ptr].ps1_ready <= instr.pr1_ready;
                rs_table[tail_ptr].ps2 <= instr.pr2;
                rs_table[tail_ptr].ps2_ready <= instr.pr2_ready;
                rs_table[tail_ptr].imm <= instr.imm;
                rs_table[tail_ptr].rob_index <= instr.rob_index;
                rs_table[tail_ptr].age <= 3'b0;
                rs_table[tail_ptr].fu <= fu_rdy;
                rs_table[tail_ptr].func3 <= instr.func3;
                rs_table[tail_ptr].func7 <= instr.func7;
                rs_table[tail_ptr].pc <= instr.pc;

                // 3. Update Pointers
                tail_ptr <= tail_ptr + 1;
                count <= count + 1;
            end 

            // issue
            if (count > 0) begin
                // Check if Head is ready (using current state OR forwarding)         
                if (rs_table[head_ptr].ps1_ready && rs_table[head_ptr].ps2_ready && fu_rdy) begin
                    valid_out <= 1'b1;
                    data_out  <= rs_table[head_ptr];
                    
                    // Capture final ready state for output
                    rs_table[head_ptr].valid <= 1'b1;
                    rs_table[head_ptr].pc <= '0;
                    rs_table[head_ptr].Opcode <= 7'b0;
                    rs_table[head_ptr].pd <= 7'b0;
                    rs_table[head_ptr].ps1 <= 7'b0;
                    rs_table[head_ptr].ps1_ready <= 1'b0;
                    rs_table[head_ptr].ps2 <= 7'b0;
                    rs_table[head_ptr].ps2_ready <= 1'b0;
                    rs_table[head_ptr].imm <= 32'b0;
                    rs_table[head_ptr].fu <= 2'b0;
                    rs_table[head_ptr].rob_index <= 5'b0;
                    rs_table[head_ptr].age <= 3'b0;
                    rs_table[head_ptr].func3 <= 3'b0;
                    rs_table[head_ptr].func7 <= 7'b0;
                    
                    head_ptr <= head_ptr + 1;
                    count <= count - 1;
                end else begin
                    valid_out <= 1'b0;
                end
            end
        end
    end

endmodule