`timescale 1ns / 1ps
import types_pkg::*;

module load_reg(
    // From Reservation Stations
    input  logic   alu_issued,
    input  rs_data alu_rs_data,
    input  logic   b_issued,
    input  rs_data b_rs_data,
    input  logic   mem_issued,
    input  rs_data mem_rs_data,

    // Control into PRF (physical_registers)
    output logic       read_alu_r1,
    output logic       read_alu_r2,
    output logic       read_b_r1,
    output logic       read_b_r2,
    output logic       read_lru_r1,
    output logic       read_lru_r2,

    output logic [6:0] target_alu_r1,
    output logic [6:0] target_alu_r2,
    output logic [6:0] target_b_r1,
    output logic [6:0] target_b_r2,
    output logic [6:0] target_lru_r1,
    output logic [6:0] target_lru_r2,

    // Data coming *from* PRF read ports
    input  logic [31:0] alu_r1,
    input  logic [31:0] alu_r2,
    input  logic [31:0] b_r1,
    input  logic [31:0] b_r2,
    input  logic [31:0] lru_r1,
    input  logic [31:0] lru_r2,

    // Data to FUs (to be wired into fus.sv)
    output logic [31:0] ps1_alu_data,
    output logic [31:0] ps2_alu_data,
    output logic [31:0] ps1_b_data,
    output logic [31:0] ps2_b_data,
    output logic [31:0] ps1_mem_data,
    output logic [31:0] ps2_mem_data
);
    assign ps1_alu_data   = alu_r1;
    assign ps2_alu_data   = alu_r2;
    assign ps1_b_data     = b_r1;
    assign ps2_b_data     = b_r2;
    assign ps1_mem_data   = lru_r1;
    assign ps2_mem_data   = lru_r2;
    
    always_comb begin
        // ALU
        if (alu_issued && alu_rs_data.valid) begin
            // Always read both sources; RS should only issue when ready
            read_alu_r1    = 1'b1;
            read_alu_r2    = 1'b1;

            target_alu_r1  = alu_rs_data.ps1;
            target_alu_r2  = alu_rs_data.ps2;
        end else begin
            read_alu_r1    = 1'b0;
            read_alu_r2    = 1'b0;
            target_alu_r1  = '0;
            target_alu_r2  = '0;
        end

        // Branch
        if (b_issued && b_rs_data.valid) begin
            read_b_r1      = 1'b1;
            read_b_r2      = 1'b1;

            target_b_r1    = b_rs_data.ps1;
            target_b_r2    = b_rs_data.ps2;
        end else begin
            read_b_r1      = 1'b0;
            read_b_r2      = 1'b0;
            target_b_r1    = '0;
            target_b_r2    = '0;
        end

        // LSU
        if (mem_issued && mem_rs_data.valid) begin
            read_lru_r1    = 1'b1;
            read_lru_r2    = 1'b1;

            target_lru_r1  = mem_rs_data.ps1;
            target_lru_r2  = mem_rs_data.ps2;
        end else begin
            read_lru_r1    = 1'b0;
            read_lru_r2    = 1'b0;
    
            target_lru_r1  = '0;
            target_lru_r2  = '0;
        end
    end

endmodule
