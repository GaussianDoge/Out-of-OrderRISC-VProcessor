`timescale 1ns / 1ps

import types_pkg::*;

module checkpoint(
    input logic clk,
    input logic reset,

    // From Rename
    input logic branch_detect,
    input logic [31:0] branch_pc,
    input logic [4:0] branch_rob_tag,

    // From ROB
    input logic mispredict,
    input logic [4:0] mispredict_tag,

    // From PRF
    input logic [127:0] reg_rdy_snap_shot,

    // Output
    output logic checkpoint_valid,
    output checkpoint snapshot
    );


    checkpoint [3:0] checkpoint;
    

    always_ff @(posedge clk) begin
        if (reset) begin
            checkpoint <= '0;
        end else begin
            checkpoint_valid <= 1'b0;
            if (branch_detect) begin
                for (int i = 0; i < 4; i++) begin
                    if (!checkpont[i].valid) begin
                        checkpoint.pc <= branch_pc;
                        checkpoint.rob_ta <= branch_rob_tag;
                        checkpoint.reg_rdy_table <= reg_rdy_snap_shot;
                    end
                end
            end
        end
    end

    always_comb begin
        if (mispredict) begin
            for (int i = 0; i < 4; i++) begin
                if (checkpont[i].valid && checkpoint.rob_tag == mispredict_tag) begin
                    snapshot = checkpoint[i];
                    checkpoint_valid = 1'b1;
                    break;
                end
            end
        end
    end


endmodule
