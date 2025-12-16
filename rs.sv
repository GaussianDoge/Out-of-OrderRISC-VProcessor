`timescale 1ns / 1ps
import types_pkg::*;

module rs(
    input logic clk,
    input logic reset,
    input logic fu_rdy,
    
    // Upstream from Pipeline Buffer/FIFO
    input logic valid_in,
    output logic ready_in,
    input dispatch_pipeline_data instr,
    
    // Downstream
    output logic valid_out,
    output rs_data data_out,
    
    // combinational update readyness of src reg
    // when physical reg writes something, it will send reg_rdy_valid signal
    input logic [6:0] reg1_rdy,
    input logic [6:0] reg2_rdy,
    input logic [6:0] reg3_rdy,
    input logic reg1_rdy_valid,
    input logic reg2_rdy_valid,
    input logic reg3_rdy_valid,
    
    // Recover
    input logic flush,
    input logic [4:0] flush_tag,
    input logic [31:0] flush_pc
    );
    
    rs_data [7:0] rs_table;
    
    logic [2:0] index;
    logic [3:0] free_space;
    
    assign ready_in = free_space > 4'b0;
    
    always_comb begin
        if (reset) begin
        end else begin
            // Find empty slot
            free_space = 0;
            for (int i = 0; i < 8; i++) begin
                if (rs_table[i].valid) begin
                    free_space = free_space + 1;
                    index = i[$clog2(8)-1:0];
                end
            end
        
            // Update ready status of reg; Assuming at most retire 3 instr
            for (int i = 0; i < 8; i++) begin
                if (rs_table[i].ps1 == reg1_rdy && reg1_rdy_valid) begin
                    rs_table[i].ps1_ready = 1'b1;
                end else if (rs_table[i].ps2 == reg1_rdy && reg1_rdy_valid) begin
                    rs_table[i].ps2_ready = 1'b1;
                end else begin
                end
                
                if (rs_table[i].ps1 == reg2_rdy && reg2_rdy_valid) begin
                    rs_table[i].ps1_ready = 1'b1;
                end else if (rs_table[i].ps2 == reg2_rdy && reg2_rdy_valid) begin
                    rs_table[i].ps2_ready = 1'b1;
                end else begin
                end
                
                if (rs_table[i].ps1 == reg3_rdy && reg3_rdy_valid) begin
                    rs_table[i].ps1_ready = 1'b1;
                end else if (rs_table[i].ps2 == reg3_rdy && reg3_rdy_valid) begin
                    rs_table[i].ps2_ready = 1'b1;
                end else begin
                end
            end
        end
        // ready_in = free_space > 4'b0;
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            ready_in <= 1'b1;
            valid_out <= 1'b0;
            for (int i = 0; i < 8; i++) begin
                rs_table[i].valid <= 1'b1;
                rs_table[i].Opcode <= 7'b0;
                rs_table[i].pd <= 7'b0;
                rs_table[i].ps1 <= 7'b0;
                rs_table[i].ps1_ready <= 1'b0;
                rs_table[i].ps2 <= 7'b0;
                rs_table[i].ps2_ready <= 1'b0;
                rs_table[i].imm <= 32'b0;
                rs_table[i].fu <= 2'b0;
                rs_table[i].rob_index <= 4'b0;
                rs_table[i].age <= 3'b0;
                rs_table[i].func3 <= 3'b0;
                rs_table[i].func7 <= 7'b0;
                rs_table[i].pc <= 32'b0;
            end
        end else if (flush) begin
            ready_in <= 1'b1;
            valid_out <= 1'b0;
            for (int i = 0; i < 8; i++) begin
                if (is_younger(rs_table[i].rob_index, flush_tag)) begin
                    rs_table[i].valid <= 1'b1;
                    rs_table[i].Opcode <= 7'b0;
                    rs_table[i].pd <= 7'b0;
                    rs_table[i].ps1 <= 7'b0;
                    rs_table[i].ps1_ready <= 1'b0;
                    rs_table[i].ps2 <= 7'b0;
                    rs_table[i].ps2_ready <= 1'b0;
                    rs_table[i].imm <= 32'b0;
                    rs_table[i].fu <= 2'b0;
                    rs_table[i].rob_index <= 4'b0;
                    rs_table[i].age <= 3'b0;
                    rs_table[i].func3 <= 3'b0;
                    rs_table[i].func7 <= 7'b0;
                    rs_table[i].pc <= 32'b0;
                end
            end
        end else begin           
            // if slot is free, insert instruction
            // first instr
            //$display("Inside");
            if (ready_in && valid_in) begin
                // increment age
//                for (int i = 0; i < 8; i++) begin
//                    if (rs_table[i].valid && rs_table[i].age < 3'b111) begin
//                        rs_table[i].age <= rs_table[i].age + 1;
//                        break;
//                    end
//                end

                rs_table[index].valid <= 1'b0;
                rs_table[index].Opcode <= instr.Opcode;
                rs_table[index].pd <= instr.prd;
                rs_table[index].ps1 <= instr.pr1;
                rs_table[index].ps1_ready <= instr.pr1_ready;
                rs_table[index].ps2 <= instr.pr2;
                rs_table[index].ps2_ready <= instr.pr2_ready;
                rs_table[index].imm <= instr.imm;
                rs_table[index].rob_index <= instr.rob_index;
                rs_table[index].age <= 3'b0;
                rs_table[index].fu <= fu_rdy;
                rs_table[index].func3 <= instr.func3;
                rs_table[index].func7 <= instr.func7;
                rs_table[index].pc <= instr.pc;

            end else begin
                
            end
            
            // issue
            for (int i = 0; i < 8; i++) begin
                if (rs_table[i].ps1_ready && rs_table[i].ps2_ready 
                    && fu_rdy) begin
                    valid_out <= 1'b1;
                    data_out <= rs_table[i];
                    rs_table[i].valid <= 1'b1;
                    rs_table[i].Opcode <= 7'b0;
                    rs_table[i].pd <= 7'b0;
                    rs_table[i].ps1 <= 7'b0;
                    rs_table[i].ps1_ready <= 1'b0;
                    rs_table[i].ps2 <= 7'b0;
                    rs_table[i].ps2_ready <= 1'b0;
                    rs_table[i].imm <= 32'b0;
                    rs_table[i].fu <= 2'b0;
                    rs_table[i].rob_index <= 5'b0;
                    rs_table[i].age <= 3'b0;
                    rs_table[i].func3 <= 3'b0;
                    rs_table[i].func7 <= 7'b0;
                    break;
                end else begin
                    valid_out <= 1'b0;
                end
            end
        end
    end

    function automatic logic is_younger(
        input [4:0] check_tag,    // 5-bit input (MSB is always 0)
        input [4:0] flush_tag    // 5-bit input (MSB is always 0)
    );
        logic [3:0] distance;
        distance = check_tag[3:0] - flush_tag[3:0];
        // Use 8 as the limit (Half of ROB size 16)
        return (distance > 0 && distance < 8);
    endfunction
    
    
endmodule
