`timescale 1ns / 1ps
import types_pkg::*;

module alu_reservation_station(
    input logic clk,
    input logic reset,
    input logic alu1_rdy,
    input logic alu2_rdy,
    
    // Upstream from Pipeline Buffer/FIFO
    input logic valid_in_1,
    input logic valid_in_2,
    output logic ready_in,
    output logic ready_in2,
    input dispatch_pipeline_data instr1, // two entries
    input dispatch_pipeline_data instr2,
    
    // Downstream
    input logic ready_out,
    output logic valid_out,
    output logic valid_out2,
    output alu_rs_data [1:0] data_out,
    
    // Set destination physical reg to not ready
    output logic [6:0] nr_reg1,
    output logic [6:0] nr_reg2,
    output logic [1:0] nr_valid, // 01: set reg1 not ready; 10: set reg2 not ready; 11: both; 00: none
    
    // combinational update readyness of src reg
    // alu will send reg_rdy_valid after finish excution
    // when it receive set_reg_rdy = 1, it set reg_rdy_valid to 0
    input logic [6:0] reg1_rdy,
    input logic [6:0] reg2_rdy,
    input logic reg1_rdy_valid,
    input logic reg2_rdy_valid,
    
    output logic set_reg1_rdy,
    output logic set_reg2_rdy
    );
    
    alu_rs_data [7:0] rs_table;
    logic alu_assign;
    
    logic [2:0] index1;
    logic [2:0] index2;
    logic [3:0] free_space;
    logic index1_valid;
    logic index2_valid;
    
    
    
    assign ready_in = free_space > 4'b0;
    assign ready_in2 = free_space > 4'b0001;
    
    
    // find free slots for two entries
    rs_free_slot find_slot(
        .rs_table(rs_table),
        .index1(index1),
        .index2(index2),
        .free_space(free_space),
        .have_free1(index1_valid),
        .have_free2(index2_valid)
    );
    
    // get free alu
    always_comb begin
        if (reset) begin
        end else begin
            unique case ({alu1_rdy, alu2_rdy})
                2'b00: alu_assign = 1'b0;
                2'b01: alu_assign = 1'b1;
                2'b10: alu_assign = 1'b0;
                2'b11: alu_assign = 1'b0;
            endcase
            
            for (int i = 0; i < 8; i++) begin
                if (rs_table[i].pr1 == reg1_rdy && reg1_rdy_valid) begin
                    rs_table[i].pr1_ready = 1'b1;
                    set_reg1_rdy = 1'b1;
                end else if (rs_table[i].pr2 == reg1_rdy && reg1_rdy_valid) begin
                    rs_table[i].pr2_ready <= 1'b1;
                    set_reg1_rdy = 1'b1;
                end else begin
                end
                
                if (rs_table[i].pr1 == reg2_rdy && reg2_rdy_valid) begin
                    rs_table[i].pr1_ready = 1'b1;
                    set_reg2_rdy = 1'b1;
                end else if (rs_table[i].pr2 == reg2_rdy && reg2_rdy_valid) begin
                    rs_table[i].pr2_ready = 1'b1;
                    set_reg2_rdy = 1'b1;
                end else begin
                end
            end
            
            if (!reg1_rdy_valid && set_reg1_rdy) begin
                set_reg1_rdy = 1'b0;
            end else begin
            end
            
            if (!reg2_rdy_valid && set_reg2_rdy) begin
                set_reg2_rdy = 1'b0;
            end else begin
            end
        end
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            alu_assign <= 1'b0;
            
            ready_in <= 1'b1;
            valid_out <= 1'b0;
            for (int i = 0; i < 8; i++) begin
                rs_table[i].valid <= 1'b1;
                rs_table[i].Opcode <= 7'b0;
                rs_table[i].prd <= 7'b0;
                rs_table[i].pr1 <= 7'b0;
                rs_table[i].pr1_ready <= 1'b0;
                rs_table[i].pr2 <= 7'b0;
                rs_table[i].pr2_ready <= 1'b0;
                rs_table[i].imm <= 32'b0;
                rs_table[i].fu <= 2'b0;
                rs_table[i].rob_index <= 4'b0;
                rs_table[i].age <= 3'b0;
            end
        end else begin           
            // if slot is free, insert instruction
            // first instr
            if (ready_in && valid_in_1 && index1_valid) begin
                // increment age
//                for (int i = 0; i < 8; i++) begin
//                    if (rs_table[i].valid && rs_table[i].age < 3'b111) begin
//                        rs_table[i].age <= rs_table[i].age + 1;
//                        break;
//                    end
//                end

                rs_table[index1].valid <= 1'b0;
                rs_table[index1].Opcode <= instr1.Opcode;
                rs_table[index1].prd <= instr1.prd;
                nr_reg1 <= instr1.prd;
                rs_table[index1].pr1 <= instr1.pr1;
                rs_table[index1].pr1_ready = instr1.pr1_ready;
                rs_table[index1].pr2 <= instr1.pr2;
                rs_table[index1].pr2_ready = instr1.pr2_ready;
                rs_table[index1].imm <= instr1.imm;
                rs_table[index1].rob_index <= instr1.rob_index;
                rs_table[index1].age <= 3'b0;
                rs_table[index1].fu <= alu_assign;
                
                nr_valid[0] <= 1'b1;
            end else begin
                nr_valid[0] <= 1'b0;
            end
            
            // second instr
            if (ready_in2 && valid_in_2 && index2_valid) begin
                rs_table[index2].valid <= 1'b0;
                rs_table[index2].Opcode <= instr2.Opcode;
                rs_table[index2].prd <= instr2.prd;
                nr_reg2 <= instr2.prd;
                rs_table[index2].pr1 <= instr2.pr1;
                rs_table[index2].pr1_ready = instr2.pr1_ready;
                rs_table[index2].pr2 <= instr2.pr2;
                rs_table[index2].pr2_ready = instr2.pr2_ready;
                rs_table[index2].imm <= instr2.imm;
                rs_table[index2].rob_index <= instr2.rob_index;
                rs_table[index2].age <= 3'b0;
                rs_table[index2].fu <= ~alu_assign; // assign different alu from instr1
                
                nr_valid[1] <= 1'b1;
            end else begin
                nr_valid[1] <= 1'b0;
            end
            
            // issue
            for (int i = 0; i < 8; i++) begin
                if (rs_table[i].pr1_ready && rs_table[i].pr2_ready 
                    && rs_table[i].fu && alu2_rdy) begin
                    valid_out <= 1'b1;
                    data_out[1] <= rs_table[i];
                    rs_table[i].valid <= 1'b1;
                    rs_table[i].Opcode <= 7'b0;
                    rs_table[i].prd <= 7'b0;
                    rs_table[i].pr1 <= 7'b0;
                    rs_table[i].pr1_ready <= 1'b0;
                    rs_table[i].pr2 <= 7'b0;
                    rs_table[i].pr2_ready <= 1'b0;
                    rs_table[i].imm <= 32'b0;
                    rs_table[i].fu <= 2'b0;
                    rs_table[i].rob_index <= 4'b0;
                    rs_table[i].age <= 3'b0;
                    break;
                end
            end
            
            for (int i = 0; i < 8; i++) begin
                if (rs_table[i].pr1_ready && rs_table[i].pr2_ready 
                    && ~rs_table[i].fu && alu1_rdy) begin
                    valid_out2 <= 1'b1;
                    data_out[0] <= rs_table[i];
                    rs_table[i].valid <= 1'b1;
                    rs_table[i].Opcode <= 7'b0;
                    rs_table[i].prd <= 7'b0;
                    rs_table[i].pr1 <= 7'b0;
                    rs_table[i].pr1_ready <= 1'b0;
                    rs_table[i].pr2 <= 7'b0;
                    rs_table[i].pr2_ready <= 1'b0;
                    rs_table[i].imm <= 32'b0;
                    rs_table[i].fu <= 2'b0;
                    rs_table[i].rob_index <= 4'b0;
                    rs_table[i].age <= 3'b0;
                    break;
                end
            end
        end
    end
    
    
endmodule
