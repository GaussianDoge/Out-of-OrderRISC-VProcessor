`timescale 1ns / 1ps
import types_pkg::*;

module rs_bu(
    input logic clk,
    input logic reset,
    
    // Execution Stage Interface
    input logic fu_rdy,
    
    // Dispatch Interface (Upstream)
    input logic valid_in,
    input dispatch_pipeline_data instr,
    output logic ready_in,
    
    // Issue Interface (Downstream)
    output logic valid_out,
    output rs_data data_out, // The instruction at HEAD
    
    // Result Bus (CDB) / Forwarding / Wakeup
    input logic [6:0] reg1_rdy,
    input logic [6:0] reg2_rdy,
    input logic [6:0] reg3_rdy,
    input logic reg1_rdy_valid,
    input logic reg2_rdy_valid,
    input logic reg3_rdy_valid,
    
    // Recovery
    input logic flush // Clears the entire buffer
);

    // FIFO Parameters
    localparam SIZE = 8;
    localparam PTR_WIDTH = $clog2(SIZE);

    // Storage
    rs_data fifo [SIZE-1:0];
    
    // Pointers
    logic [PTR_WIDTH-1:0] head;
    logic [PTR_WIDTH-1:0] tail;
    logic [PTR_WIDTH:0] count;

    // Full/Empty Logic
    assign ready_in = (count < SIZE);
    wire empty = (count == 0);

    assign data_out  = fifo[head];

    always_comb begin
        // Update ready status of reg; Assuming at most retire 3 instr
        for (int i = 0; i < 8; i++) begin
            if (fifo[i].ps1 == reg1_rdy && reg1_rdy_valid) begin
                fifo[i].ps1_ready = 1'b1;
            end else if (fifo[i].ps2 == reg1_rdy && reg1_rdy_valid) begin
                fifo[i].ps2_ready = 1'b1;
            end else begin
            end
            
            if (fifo[i].ps1 == reg2_rdy && reg2_rdy_valid) begin
                fifo[i].ps1_ready = 1'b1;
            end else if (fifo[i].ps2 == reg2_rdy && reg2_rdy_valid) begin
                fifo[i].ps2_ready = 1'b1;
            end else begin
            end
            
            if (fifo[i].ps1 == reg3_rdy && reg3_rdy_valid) begin
                fifo[i].ps1_ready = 1'b1;
            end else if (fifo[i].ps2 == reg3_rdy && reg3_rdy_valid) begin
                fifo[i].ps2_ready = 1'b1;
            end else begin
            end
        end
        valid_out = !empty && fifo[head].ps1_ready && fifo[head].ps2_ready;
    end


    always_ff @(posedge clk) begin
        if (reset || flush) begin
            head  <= 0;
            tail  <= 0;
            count <= 0;
            
            // Clear valid bits for safety
            for (int i = 0; i < SIZE; i++) begin
                fifo[i].valid <= 1'b1;
                fifo[i].Opcode <= '0;
                fifo[i].pd <= '0;
                fifo[i].ps1 <= '0;
                fifo[i].ps1_ready <= '0;
                fifo[i].ps2 <= instr.pr2;
                fifo[i].ps2_ready <= '0;
                fifo[i].imm <= '0;
                fifo[i].rob_index <= '0;
                fifo[i].age <= 3'b0;
                fifo[i].fu <= '0;
                fifo[i].func3 <= '0;
                fifo[i].func7 <= '0;
                fifo[i].pc <= '0;
            end
            
        end else begin

            // Write to tail
            if (valid_in && ready_in) begin
                fifo[tail].valid <= 1'b0;
                fifo[tail].Opcode <= instr.Opcode;
                fifo[tail].pd <= instr.prd;
                fifo[tail].ps1 <= instr.pr1;
                fifo[tail].ps1_ready <= instr.pr1_ready;
                fifo[tail].ps2 <= instr.pr2;
                fifo[tail].ps2_ready <= instr.pr2_ready;
                fifo[tail].imm <= instr.imm;
                fifo[tail].rob_index <= instr.rob_index;
                fifo[tail].age <= 3'b0;
                fifo[tail].fu <= fu_rdy;
                fifo[tail].func3 <= instr.func3;
                fifo[tail].func7 <= instr.func7;
                fifo[tail].pc <= instr.pc;
                tail <= (tail == SIZE-1) ? 0 : tail + 1;
            end

            // Issue if output is valid and FU is ready
            if (valid_out && fu_rdy) begin
                fifo[head].valid <= 1'b1;
                head <= (head == SIZE-1) ? 0 : head + 1;
            end

            // Update count
            // Handle simultaneous push and pop
            if ((valid_in && ready_in) && !(valid_out && fu_rdy)) begin
                count <= count + 1;
            end else if (!(valid_in && ready_in) && (valid_out && fu_rdy)) begin
                count <= count - 1;
            end
        end
    end

endmodule