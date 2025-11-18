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
    
    // Mispredict signal from ROB
    input logic mispredict,
    
    // Downstream
    output rename_data data_out,
    output logic valid_out,
    input logic ready_out
);
    wire write_pd = data_in.Opcode != 7'b0100011 && data_in.rd != 5'd0;
    wire rename_en = ready_in && ready_out && valid_in;
    
    // We update write_en when implement mispredict
    logic write_en;
    logic read_en;
    logic update_en;     
    logic [6:0] preg;
    logic empty;
    
    // ROB Tag
    logic [3:0] ctr = 4'b0;
    
    // Support mispeculation 
    logic [6:0] re_map [0:31];
    logic [6:0] re_preg;

    logic [6:0] map [0:31];
    
    // Speculation is 1 when we encounter a branch instruction
    wire branch = (data_in.Opcode == 7'b1100011);
        
    assign ready_in = ready_out && (!empty || !write_pd);
    assign read_en = write_pd && rename_en;
    assign update_en = write_pd && rename_en;
    
    logic valid_out_delayed;
    
    always_ff @(posedge clk) begin
        if (reset) begin
            ctr <= 4'b0;
            data_out.imm <= '0;
            data_out.pd_old <= '0;
            data_out.pd_new <= '0;
            data_out.ps1 <= '0;
            data_out.ps2 <= '0;
            write_en <= 1'b0;
            valid_out <= 1'b0;
            valid_out_delayed <= 1'b0;
        end else begin
            if (valid_out && ready_out) begin
                valid_out_delayed <= 1'b0;
            end else if (rename_en) begin
                valid_out_delayed <= 1'b1;
            end
            valid_out <= valid_out_delayed;
            if (valid_in && ready_in && branch) begin
                re_preg <= preg;
                re_map <= map;
            end
            if (rename_en) begin
                ctr <= (ctr == 15) ? 0 : ctr + 1;
                data_out.ps1 <= map[data_in.rs1];
                data_out.ps2 <= map[data_in.rs2];
                data_out.pd_old <= map[data_in.rd];
                data_out.imm <= data_in.imm;
                data_out.rob_tag <= ctr;
                valid_out <= 1'b1;
                if (write_pd) begin
                    data_out.pd_new <= preg;
                end else begin
                    data_out.pd_new <= '0;
                end 
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
        .write_en(write_en),    
        .read_en(read_en),
        .empty(empty),
        .re_ptr(re_preg),
        .ptr(preg)
    );
endmodule
