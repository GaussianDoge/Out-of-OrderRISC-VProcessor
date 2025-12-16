`timescale 1ns / 1ps

import types_pkg::*;

module checkpoint(
    input logic clk,
    input logic reset,

    // From Rename
    input logic branch_detect,
    input logic [31:0] branch_pc,
    input logic [4:0] branch_rob_tag,
    input logic [6:0] not_rdy_pr,
    input logic not_rdy_pr_valid,

    // From ROB
    input logic mispredict,
    input logic [4:0] mispredict_tag,
    input logic hit,

    // Output
    output logic checkpoint_valid,
    output checkpoint snapshot
);
    // 4 Checkpoints
    checkpoint [7:0] chkpt;

    always_ff @(posedge clk) begin
        if (reset) begin
            chkpt <= '0;
        end else begin
//            checkpoint_valid <= 1'b0;
            // When a new branch is renamed/dispatched
            if (mispredict || hit) begin
                for (int i = 0; i < 8; i++) begin
                    if (chkpt[i].valid && chkpt[i].rob_tag == mispredict_tag) begin
                        chkpt[i] <= '0;
                        break;
                    end
                end
            end else begin
                if (branch_detect) begin
                    for (int i = 0; i < 4; i++) begin
                        if (!chkpt[i].valid) begin
                            chkpt[i].valid <= 1'b1;
                            chkpt[i].pc <= branch_pc;
                            chkpt[i].rob_tag <= branch_rob_tag;
                            chkpt[i].reset_reg_rdy_table <= '0;
                            break; // Stop after filling one slot
                        end
                    end
                end

                for (int i = 0; i < 4; i++) begin
                    if (chkpt[i].valid && not_rdy_pr_valid) begin
                        chkpt[i].reset_reg_rdy_table[not_rdy_pr] <= 1'b1;
                    end
                end
            end

            
        end
    end

    always_comb begin
        // Default outputs to prevent latches
        snapshot = '0;
        checkpoint_valid = 1'b0;
        if (mispredict) begin
            // Search for the snapshot belonging to the mispredicted branch
            for (int i = 0; i < 8; i++) begin
                if (chkpt[i].valid && chkpt[i].rob_tag == mispredict_tag) begin
                    snapshot = chkpt[i];
                    checkpoint_valid = 1'b1;
                    break;
                end
            end
        end
    end
    
endmodule
