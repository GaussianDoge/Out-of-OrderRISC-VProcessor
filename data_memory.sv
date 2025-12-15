`timescale 1ns / 1ps
import types_pkg::*;

module data_memory(
    input clk,
    input reset,
    
    // From FU Mem
    //input logic [31:0] addr,
    input logic issued,
    input rs_data data_in,
    
    // From LSQ for S-type
    input logic store_wb,
    input lsq lsq_in,

    // From LSQ for L-type
    input logic load_mem,
    input lsq lsq_load,
    
    // Output
    output mem_data data_out,
    output logic load_ready,
    output logic valid
);
    logic [6:0] Opcode;
    logic [2:0] func3;
    logic [4:0] rob_index;
    assign Opcode = data_in.Opcode;
    assign func3 = data_in.func3;
    assign rob_index = data_in.rob_index;

    logic [0:204800] [7:0]data_mem= '0; // 100 KB memory
    // logic valid_2cycles;
    logic [31:0] addr_reg;
    // logic [2:0]  func3_reg;
    logic [4:0] pre_rob_index;
    
    
    // logic load_issue;
    // assign load_issue = issued && (Opcode == 7'b0000011) && (pre_rob_index != rob_index);
        
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            data_out <= '0;
            valid <= 1'b0;
            // valid_2cycles <= 1'b0;
            pre_rob_index <= 5'b11111;
            for (int i = 0; i <= 204800; i++) begin
                data_mem[i] <= '0;
            end
        end else begin
            valid <= 1'b0;
            load_ready <= 1'b1;
            if (store_wb) begin
                if (lsq_in.sw_sh_signal == 1'b0) begin // sw
                    data_mem[lsq_in.addr] <= lsq_in.ps2_data[7:0];
                    data_mem[lsq_in.addr+1] <= lsq_in.ps2_data[15:8];
                    data_mem[lsq_in.addr+2] <= lsq_in.ps2_data[23:16];
                    data_mem[lsq_in.addr+3] <= lsq_in.ps2_data[31:24];
                end else if (lsq_in.sw_sh_signal == 1'b1) begin // sh
                    data_mem[lsq_in.addr] <= lsq_in.ps2_data[7:0];
                    data_mem[lsq_in.addr+1] <= lsq_in.ps2_data[15:8];
                end
                data_out.fu_mem_ready <= 1'b1;      // free again
                // no need retire we already done in LSQ
                $display("=====================================");
                $display("STORE_COMMIT pc=%8h rob=%0d addr=0x%0d data=0x%08h sw_sh=%0d",
                    lsq_in.pc, lsq_in.rob_tag[4:0], lsq_in.addr, lsq_in.ps2_data, lsq_in.sw_sh_signal);
                $display("M[%0d]=%8h", lsq_in.addr, lsq_in.ps2_data);
            end 
            // if (load_issue) begin
            //     addr_reg  <= addr;
            //     func3_reg <= func3;
            // end
            
            //valid_2cycles <= load_issue && load_mem;

            // When v2==1, 2 cycles after load_issue, return data
            if (!store_wb && load_mem && !lsq_load.store && pre_rob_index != lsq_load.rob_tag) begin
                valid <= 1'b1;
                load_ready = 1'b0;
                pre_rob_index <= lsq_load.rob_tag;
                if (lsq_load.func3 == 3'b100) begin // lbu
                    data_out.data <= {{24{1'b0}}, data_mem[lsq_load.addr]};
                    data_out.p_mem <= lsq_load.pd;
                    data_out.fu_mem_ready <= 1'b1;      // free again
                    data_out.fu_mem_done  <= 1'b1;      // retire
                    data_out.rob_fu_mem <= lsq_load.rob_tag;
                    $display("=====================================");
                    $display("Load Byte Unsigned PC=%8h", lsq_load.pc);
                    $display("M[%0d]=%32h", lsq_load.addr, {{24{1'b0}}, data_mem[lsq_load.addr]});
                end else if (lsq_load.func3 == 3'b010) begin // lw
                    data_out.data <= {data_mem[lsq_load.addr+3], data_mem[lsq_load.addr+2],
                                  data_mem[lsq_load.addr+1], data_mem[lsq_load.addr]};
                    data_out.p_mem <= lsq_load.pd;
                    data_out.fu_mem_ready <= 1'b1;      // free again
                    data_out.fu_mem_done  <= 1'b1;      // retire
                    data_out.rob_fu_mem <= lsq_load.rob_tag;
                    $display("=====================================");
                    $display("Load Word PC=%8h", lsq_load.pc);
                    $display("M[%0d]=%32h", lsq_load.addr, {data_mem[lsq_load.addr+3], data_mem[lsq_load.addr+2],
                                  data_mem[lsq_load.addr+1], data_mem[lsq_load.addr]});
                end
            end
        end
    end

endmodule