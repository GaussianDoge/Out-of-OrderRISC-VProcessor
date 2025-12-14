`timescale 1ns / 1ps
import types_pkg::*;

module data_memory(
    input clk,
    input reset,
    
    // From FU Mem
    input logic [31:0] addr,
    input logic issued,
    input rs_data data_in,
    
    // From LSQ for S-type
    input logic store_wb,
    input lsq lsq_in,
    input logic load_mem,
    
    // Output
    output mem_data data_out,
    output logic valid
);
    logic [6:0] Opcode;
    logic [2:0] func3;
    logic [4:0] rob_index;
    assign Opcode = data_in.Opcode;
    assign func3 = data_in.func3;
    assign rob_index = data_in.rob_index;
    
    logic [7:0] data_mem [0:102400]; // 100 KB memory
    logic valid_2cycles;
    logic [31:0] addr_reg;
    logic [2:0]  func3_reg;
    logic [4:0] pre_rob_index = 5'b11111;
    
    
    logic load_issue;
    assign load_issue = issued && (Opcode == 7'b0000011) && (pre_rob_index != rob_index);
        
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            data_out <= '0;
            valid <= 1'b0;
            valid_2cycles <= 1'b0;
            pre_rob_index <= 5'b11111;
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
                    data_out.data <= {{24{1'b0}}, data_mem[addr_reg]};
                    data_out.p_mem <= data_in.pd;
                    data_out.fu_mem_ready <= 1'b1;      // free again
                    data_out.fu_mem_done  <= 1'b1;
                    data_out.rob_fu_mem <= data_in.rob_index;
                    
                    $display("Load Byte Unsigned");
                    $display("M[%5d]=%32h", addr_reg, {{24{1'b0}}, data_mem[addr_reg]});
                end else if (func3_reg == 3'b010) begin // lw
                    data_out.data <= {data_mem[addr_reg], data_mem[addr_reg+1],
                                  data_mem[addr_reg+2], data_mem[addr_reg+3]};
                    data_out.p_mem <= data_in.pd;
                    data_out.fu_mem_ready <= 1'b1;      // free again
                    data_out.fu_mem_done  <= 1'b1;
                    data_out.rob_fu_mem <= data_in.rob_index;
                    $display("Load Word");
                    $display("M[%5d]=%32h", addr_reg, {data_mem[addr_reg], data_mem[addr_reg+1],
                                  data_mem[addr_reg+2], data_mem[addr_reg+3]});
                end
            end
        end
    end
endmodule