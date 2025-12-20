`timescale 1ns / 1ps

import types_pkg::*;

module rename(
    input logic clk,
    input logic reset,

    // Data from skid buffer
    // Upstream
    input logic valid_in,  
    input decode_data data_in,
    output logic ready_in,
    
    // From ROB
    input logic write_en,
    input logic [6:0] rob_data_in,
    
    // Mispredict signal from ROB
    input logic mispredict,
    input logic [4:0] mispredict_tag,
    input logic hit,
    
    // Downstream
    output rename_data data_out,
    output logic valid_out,
    input logic ready_out
);
    logic [31:0] pre_pc;
    wire write_pd = data_in.Opcode != 7'b0100011 
                    && data_in.Opcode != 7'b1100011 
                    && data_in.rd != 5'd0;
    wire rename_en = ready_in && valid_in && pre_pc != data_in.pc;
    wire fl_write_en = write_en && (rob_data_in != 7'b0);
   
    logic read_en;
    logic update_en;     
    logic [6:0] preg;
    logic empty;
    logic [3:0] re_ctr;
    
    // ROB Tag
    logic [3:0] ctr = 4'b0;
    
    // Recovery
    rename_checkpoint [7:0] checkpoint;
    logic [0:31] [6:0] re_map;
    logic [6:0] re_r_ptr;
    logic [6:0] re_w_ptr;
    
    logic [6:0] r_ptr_list;
    logic [6:0] w_ptr_list;
    logic [0:31] [6:0] map;

    logic capture;
    logic [3:0] index;
    logic [3:0] oldest;
    

    // Speculation is 1 when we encounter a branch instruction
    logic branch;
    assign branch = (data_in.Opcode == 7'b1100011);

    logic jalr;
    assign jalr = (data_in.Opcode == 7'b1100111);
        
    assign ready_in = (ready_out || !valid_out) && (!empty || !write_pd);
    assign read_en = write_pd && rename_en;
    assign update_en = write_pd && rename_en;

    
    always_comb begin
        if (mispredict) begin
            pre_pc = data_in.pc;
            for (int i = 0; i < 8; i++) begin
                if (checkpoint[i].valid && checkpoint[i].rob_tag == mispredict_tag) begin
                    re_map = checkpoint[i].re_map;
                    re_ctr = checkpoint[i].re_ctr;
                    re_r_ptr = checkpoint[i].re_r_ptr;
                    re_w_ptr = checkpoint[i].re_w_ptr;
                    break;
                end
            end 
            
        end
    end
        
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            ctr <= 4'b0;
            data_out <= '0;
            valid_out <= 1'b0;
            pre_pc <= 32'b1;
            checkpoint <= '0;
            capture <= 1'b0;
            index <= '0;
            oldest <= '0;
        end else begin
            if (valid_out && ready_out) begin
                valid_out <= 1'b0;
            end
            if (rename_en && (branch || jalr) && !mispredict) begin
                capture <= jalr;

                for (int i = 0; i < 8; i++) begin
                    if (!checkpoint[i].valid) begin
                        checkpoint[i].valid <= 1'b1;
                        checkpoint[i].pc <= data_in.pc;
                        checkpoint[i].rob_tag <= ctr;

                        checkpoint[i].re_map <= map;
                        checkpoint[i].re_ctr <= ctr;
                        checkpoint[i].re_r_ptr <= (r_ptr_list == 127) ? 1 : r_ptr_list + 1;
                        checkpoint[i].re_w_ptr <= w_ptr_list;

                        index <= i;
                        break; // Stop after filling one slot
                    end 
                end
            end

            if (capture) begin
                checkpoint[index].re_map <= map;
                capture <= 1'b0;
            end

            if (mispredict) begin
                for (int i = 0; i < 8; i++) begin
                    if (checkpoint[i].valid && checkpoint[i].rob_tag == mispredict_tag) begin
                        if (i == oldest) begin
                            checkpoint <= '0;
                            oldest <= '0;
                        end else begin
                            checkpoint[i] <= '0;
                        end
                        break;
                    end
                end 

                if (mispredict) begin
                    ctr <= (re_ctr == 15) ? 0 : re_ctr + 1;
                end
                
            end else if (hit) begin
                for (int i = 0; i < 8; i++) begin
                    if (checkpoint[i].valid && checkpoint[i].rob_tag == mispredict_tag) begin
                        checkpoint[i] <= '0;
                        oldest <= oldest+1;
                        break;
                    end
                end 
            end else if (rename_en) begin
                ctr <= (ctr == 15) ? 0 : ctr + 1;
                data_out.pc <= data_in.pc;
                data_out.ps1 <= map[data_in.rs1];
                data_out.ps2 <= map[data_in.rs2];
                data_out.pd_old <= map[data_in.rd];
                data_out.imm <= data_in.imm;
                data_out.rob_tag <= ctr;
                data_out.fu_alu <= data_in.fu_alu;
                data_out.fu_br <= data_in.fu_br;
                data_out.fu_mem <= data_in.fu_mem;
                data_out.ALUOp <= data_in.ALUOp;
                data_out.Opcode <= data_in.Opcode;
                data_out.func3 <= data_in.func3;
                data_out.func7 <= data_in.func7;
                valid_out <= 1'b1;

                pre_pc <= data_in.pc;
                if (write_pd) begin
                    data_out.pd_new <= preg;
                end else begin
                    data_out.pd_new <= '0;
                end 
                valid_out <= 1'b1;
            end
        end
    end
    
    map_table u_map_table(
        .clk(clk),
        .reset(reset), 
        .branch(branch),
        .mispredict(mispredict), 
        .update_en(update_en),
        .rd(data_in.rd),
        .pd_new(preg),
        .re_map(re_map),
        .map(map)
    );
    
    free_list u_free_list(
        .clk(clk),
        .reset(reset),
        .mispredict(mispredict),
        .write_en(fl_write_en),    
        .data_in(rob_data_in),
        .read_en(read_en),
        .empty(empty),
        .re_r_ptr(re_r_ptr),
        .re_w_ptr(re_w_ptr),
        .pd_new_out(preg),
        .r_ptr_out(r_ptr_list),
        .w_ptr_out(w_ptr_list)
    );
endmodule
