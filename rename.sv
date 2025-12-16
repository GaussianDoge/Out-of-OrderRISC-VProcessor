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
    
    // Downstream
    output rename_data data_out,
    output logic valid_out,
    input logic ready_out
);
    wire write_pd = data_in.Opcode != 7'b0100011 
                    && data_in.Opcode != 7'b1100011 
                    && data_in.rd != 5'd0;
    wire rename_en = ready_in && valid_in;
    wire fl_write_en = write_en && (rob_data_in != 7'b0);
   
    logic read_en;
    logic update_en;     
    logic [6:0] preg;
    logic empty;
    logic [3:0] re_ctr;
    
    // ROB Tag
    logic [3:0] ctr = 4'b0;
    
    // Support mispeculation 
    logic [6:0] re_map [0:31];
    logic [6:0] re_list [0:127];
    logic [6:0] re_r_ptr;
    logic [6:0] re_w_ptr;
    
    logic [6:0] r_ptr_list;
    logic [6:0] w_ptr_list;
    logic [6:0] list [0:127];
    logic [6:0] map [0:31];
    
    // Speculation is 1 when we encounter a branch instruction
    wire branch = (data_in.Opcode == 7'b1100011);
        
    assign ready_in = (ready_out || !valid_out) && (!empty || !write_pd);
    assign read_en = write_pd && rename_en;
    assign update_en = write_pd && rename_en;
        
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            ctr <= 4'b0;
            data_out <= '0;
            valid_out <= 1'b0;
        end else begin
            if (valid_out && ready_out) begin
                valid_out <= 1'b0;
            end
            if (rename_en && branch) begin
                re_list <= list;
                re_map <= map;
                re_ctr <= ctr;
                re_r_ptr <= r_ptr_list;
                re_w_ptr <= w_ptr_list;
            end
            if (mispredict) begin
                ctr <= (re_ctr == 15) ? 0 : re_ctr + 1;
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
        .re_list(re_list),
        .re_r_ptr(re_r_ptr),
        .re_w_ptr(re_w_ptr),
        .pd_new_out(preg),
        .list_out(list),
        .r_ptr_out(r_ptr_list),
        .w_ptr_out(w_ptr_list)
    );
endmodule
