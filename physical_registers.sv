`timescale 1ns / 1ps

module physical_registers(
    input logic clk,
    input logic reset,

    // Write and read (three ports for 3 FUs)
    // For ALU read r1 and r2, and write rd
    input logic read_alu_r1,
    input logic read_alu_r2,
    input logic write_alu_rd,
    input logic [31:0] write_alu_data,
    input logic [6:0] target_alu_reg,
    input logic [6:0] target_alu_r1,
    input logic [6:0] target_alu_r2,
    
    output logic [31:0] alu_r1,
    output logic [31:0] alu_r2,
    output logic [6:0] rdy_reg1,
    output logic reg1_rdy_valid,
    
    // For Branch Unit (BNE & JALR), read r1 and r2
    input logic read_b_r1,
    input logic read_b_r2,
    input logic write_b_rd,
    input logic [31:0] write_b_data,
    input logic [6:0] target_b_reg,
    input logic [6:0] target_b_r1,
    input logic [6:0] target_b_r2,
    
    output logic [31:0] b_r1,
    output logic [31:0] b_r2,
    output logic [6:0] rdy_reg2,
    output logic reg2_rdy_valid,
    
    // For LRU (LBU & LW)
    input logic read_lru_r1,
    input logic read_lru_r2,
    input logic write_lru_rd,
    input logic [31:0] write_lru_data,
    input logic [6:0] target_lru_reg,
    input logic [6:0] target_lru_r1,
    input logic [6:0] target_lru_r2,
    
    output logic [31:0] lru_r1,
    output logic [31:0] lru_r2,
    output logic [6:0] rdy_reg3,
    output logic reg3_rdy_valid,
    
    
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
    
    
    always_comb begin
        if (!reset) begin
            // Combinational Read Reg File for FUs
            // ALU
            if (read_alu_r1) begin
                alu_r1 = phy_reg[target_alu_r1];
            end
            
            if (read_alu_r2) begin
                alu_r2 = phy_reg[target_alu_r2];
            end
            
            // Branch Unit
            if (read_b_r1) begin
                b_r1 = phy_reg[target_b_r1];
            end
            
            if (read_alu_r2) begin
                b_r2 = phy_reg[target_b_r2];
            end
            
            // LRU
            if (read_lru_r1) begin
                lru_r1 = phy_reg[target_lru_r1];
            end
            
            if (read_lru_r2) begin
                lru_r2 = phy_reg[target_lru_r2];
            end
        
            // Check if reg is ready & Set target rd to not rdy
            if (alu_rs_check_rdy1) begin
                alu_rs_rdy1 = reg_rdy_table[alu_pr1];
            end
            
            if (alu_rs_check_rdy2) begin
                alu_rs_rdy2 = reg_rdy_table[alu_pr2];
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
            // Write for ALU
            if (write_alu_rd && target_alu_reg != 0) begin
                // write only => automatically set reg to ready
                phy_reg[target_alu_reg] <= write_alu_data;
                reg_rdy_table[target_alu_reg] <= 1'b1;
                rdy_reg1 <= target_alu_reg;
                reg1_rdy_valid <= 1'b1;
            end else begin
                reg1_rdy_valid <= 1'b0;
            end
            
            // Write for Branch Unit
            if (write_b_rd && target_b_reg != 0) begin
                // write only => automatically set reg to ready
                phy_reg[target_b_reg] <= write_b_data;
                reg_rdy_table[target_b_reg] <= 1'b1;
                rdy_reg2 <= target_b_reg;
                reg2_rdy_valid <= 1'b1;
            end else begin
                reg2_rdy_valid <= 1'b0;
            end
            
            // Write for LRU
            if (write_lru_rd && target_lru_reg != 0) begin
                // write only => automatically set reg to ready
                phy_reg[target_lru_reg] <= write_lru_data;
                reg_rdy_table[target_lru_reg] <= 1'b1;
                rdy_reg3 <= target_lru_reg;
                reg3_rdy_valid <= 1'b1;
            end else begin
                reg3_rdy_valid <= 1'b0;
            end
            
        end
    end
    
endmodule
