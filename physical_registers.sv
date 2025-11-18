`timescale 1ns / 1ps

module physical_registers(
    input logic clk,
    input logic reset,

    // Write and read
    input logic read,
    input logic write,
    input logic [31:0] write_data,
    input logic [6:0] target_reg,
    output logic [31:0] read_data,
    output logic [6:0] rdy_reg1,
    output logic reg1_rdy_valid,
    
    // check if reg is ready
    input logic alu_rs_check_rdy1,
    input logic alu_rs_check_rdy2,
    input logic [6:0] alu_pr1,
    input logic [6:0] alu_pr2,
    
    input logic lsu_rs_check_rdy1,
    input logic lsu_rs_check_rdy2,
    input logic [6:0] lsu_pr1,
    input logic [6:0] lsu_pr2,
    
    input logic branch_rs_check_rdy1,
    input logic branch_rs_check_rdy2,
    input logic [6:0] branch_pr1,
    input logic [6:0] branch_pr2,
    
    output logic alu_rs_rdy1,
    output logic alu_rs_rdy2,
    output logic lsu_rs_rdy1,
    output logic lsu_rs_rdy2,
    output logic branch_rs_rdy1,
    output logic branch_rs_rdy2,
    
    // set reg to not ready
    input logic alu_set_not_rdy,
    input logic lsu_set_not_rdy,
    input logic branch_set_not_rdy,
    input logic [6:0] alu_rd,
    input logic [6:0] lsu_rd,
    input logic [6:0] branch_rd
    );
    
    reg [127:0][31:0] phy_reg;
    reg [127:0] reg_rdy_table;
    
    // Check if reg is ready & Set target rd to not rdy
    always_comb begin
        if (!reset) begin
            if (alu_rs_check_rdy1) begin
                alu_rs_rdy1 = reg_rdy_table[alu_pr1];
            end
            
            if (alu_rs_check_rdy2) begin
                alu_rs_rdy1 = reg_rdy_table[alu_pr2];
            end
            
            if (lsu_rs_check_rdy1) begin
                lsu_rs_rdy1 = reg_rdy_table[lsu_pr1];
            end
            
            if (lsu_rs_check_rdy2) begin
                lsu_rs_rdy2 = reg_rdy_table[lsu_pr2];
            end
            
            if (branch_rs_check_rdy1) begin
                branch_rs_rdy1 = reg_rdy_table[branch_pr1];
            end
            
            if (branch_rs_check_rdy2) begin
                branch_rs_rdy2 = reg_rdy_table[branch_pr2];
            end
            
            if (alu_set_not_rdy) begin
                reg_rdy_table[alu_rd] = 1'b0;
            end
            
            if (lsu_set_not_rdy) begin
                reg_rdy_table[lsu_rd] = 1'b0;
            end
            
            if (branch_set_not_rdy) begin
                reg_rdy_table[branch_rd] = 1'b0;
            end
        end
    end
    
    
    // Read and Write
    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < 128; i++) begin
                phy_reg[i] <= 32'b0;
                reg_rdy_table[i] <= 1'b1;
            end
        end else begin
            reg1_rdy_valid <= 1'b0;
            case ({read, write})
                2'b10: begin // read only
                    read_data <= phy_reg[target_reg];
                end
                2'b01: begin // write only => automatically set reg to ready
                    phy_reg[target_reg] <= write_data;
                    reg_rdy_table[target_reg] <= 1'b1;
                    rdy_reg1 <= target_reg;
                    reg1_rdy_valid <= 1'b1;
                end
            endcase
        end
    end
    
endmodule
