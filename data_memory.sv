`timescale 1ns / 1ps
import types_pkg::*;

module data_memory(
    input clk,
    input reset,
    
    // From FU Mem
    input logic [31:0] addr,
    input logic issued,
    input logic [6:0] Opcode,
    input logic [2:0] func3,
    input logic [4:0] rob_index,
    
    // From LSQ for S-type
    input logic store_wb,
    input lsq lsq_in,
    
    // Output
    output logic [31:0] data_out,
    output logic valid
);
    logic [7:0] data_mem [0:102400]; // 100 KB memory
    logic valid_2cycles;
    logic [31:0] addr_reg;
    logic [2:0]  func3_reg;
    logic [4:0] pre_rob_index = 4'b1111;
    
    logic load_issue;
    assign load_issue = issued && (Opcode == 7'b0000011) && (pre_rob_index != rob_index);
        
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            data_out <= '0;
            valid <= 1'b0;
            valid_2cycles <= 1'b0;
            pre_rob_index <= 4'b1111;
            for (int i = 0; i <= 102400; i++) begin
                data_mem[i] <= '0;
            end
        end else begin
            valid <= 1'b0;
            if (store_wb) begin
                if (lsq_in.sw_sh_signal == 1'b0) begin // sw
                    data_mem[lsq_in.addr] <= lsq_in.ps2_data[31:24];
                    data_mem[lsq_in.addr+1] <= lsq_in.ps2_data[23:16];
                    data_mem[lsq_in.addr+2] <= lsq_in.ps2_data[15:8];
                    data_mem[lsq_in.addr+3] <= lsq_in.ps2_data[7:0];
                end else if (lsq_in.sw_sh_signal == 1'b1) begin // sh
                    data_mem[lsq_in.addr] <= lsq_in.ps2_data[15:8];
                    data_mem[lsq_in.addr+1] <= lsq_in.ps2_data[7:0];
                end
                $display("STORE_COMMIT rob=%0d addr=0x%08h data=0x%08h sw_sh=%0d",
                    lsq_in.rob_tag[4:0], lsq_in.addr, lsq_in.ps2_data, lsq_in.sw_sh_signal);
                $display("M[65568]=%32h", {data_mem[65568], data_mem[65568+1],data_mem[65568+2], data_mem[65568+3]});
                $display("M[65572]=%32h", {data_mem[65568+4], data_mem[65568+5],data_mem[65568+6], data_mem[65568+7]});
            end 
            if (load_issue) begin
                addr_reg  <= addr;
                func3_reg <= func3;
            end
            
            valid_2cycles <= load_issue;

            // When v2==1, 2 cycles after load_issue, return data
            if (valid_2cycles) begin
                valid <= 1'b1;
                pre_rob_index <= rob_index;
                if (func3_reg == 3'b100) begin // lbu
                    data_out <= {{24{1'b0}}, data_mem[addr_reg]};
                end else if (func3_reg == 3'b010) begin // lw
                    data_out <= {data_mem[addr_reg], data_mem[addr_reg+1],
                                  data_mem[addr_reg+2], data_mem[addr_reg+3]};
                    $display("Load Word");
                    $display("M[%5d]=%32h", addr_reg, {data_mem[addr_reg], data_mem[addr_reg+1],
                                  data_mem[addr_reg+2], data_mem[addr_reg+3]});
                end
            end
        end
    end
endmodule