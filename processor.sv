`timescale 1ns / 1ps

module processor(
    input logic clk,
    input logic reset
    );
    
    // General data for all stages
    logic [31:0] pc;
    logic mispredict;
    
    // Fetch and Decode Stages (Frontend)
    logic rename_ready_in;
    decode_data frontend_data_out;
    logic frontend_valid_out;
    
    frontend frontend_unit(.clk(clk), 
                           .reset(reset), 
                           .pc_in(pc),
                           .mispredict(mispredict),
                           .frontend_ready_out(rename_ready_in),
                           .data_out(frontend_data_out),
                           .frontend_valid_out(frontend_valid_out));
    
    // Rename Stage
    rename_data rename_data_out;
    logic rename_valid_out;
    logic dispatch_ready_in;
    
    rename rename_unit(.clk(clk), 
                       .reset(reset), 
                       .pc_in(pc), 
                       .frontend_ready_out(frontend_valid_out), 
                       .data_in(frontend_data_out),
                       .ready_in(rename_ready_in),
                       .mispredict(mispredict),
                       .data_out(rename_data_out),
                       .valid_out(rename_valid_out),
                       .ready_out(dispatch_ready_in));
    
    // Dispatch Stage
    dispatch dispatch_unit(.clk(clk),
                           .reset(reset),
                           
                           // upstream from rename
                           .valid_in(rename_valid_out),
                           .data_in(rename_data_out),
                           .ready_in(dispatch_ready_in),
                           
                           // Downstream (Interface with FUs)
                           
                           
                           // ALU
                           .alu_rs_valid_out(),
                           .alu_rs_data_out(),
                           .alu_rs_ready_in(),
                           
                           // Branch Unit
                           .br_rs_valid_out(),
                           .br_rs_data_out(),
                           .br_rs_ready_in(),
                           
                           // LSU
                           .lsu_rs_valid_out(),
                           .lsu_rs_data_out(),
                           .lsu_rs_ready_in()
                           
                           // Interface with PRF
                           
                           );
    
    // PRF (Physical Register Files)
    physical_registers PRF(.clk(clk),
                           .reset(reset),
                           
                           // Read and Write for ALU
                           .read_alu_r1(),
                           .read_alu_r2(),
                           .write_alu_rd(),
                           .write_alu_data(),
                           .target_alu_reg(),
                           .target_alu_r1(),
                           .target_alu_r2(),

                           .alu_r1(),
                           .alu_r2(),
                           .rdy_reg1(),
                           .reg1_rdy_valid(),
                           
                           // Read and Write for Branch
                           .read_b_r1(),
                           .read_b_r2(),
                           .write_b_rd(),
                           .write_b_data(),
                           .target_b_reg(),
                           .target_b_r1(),
                           .target_b_r2(),

                           .b_r1(),
                           .b_r2(),
                           .rdy_reg2(),
                           .reg2_rdy_valid(),
                           
                           // Read and Write for LRU
                           .read_lru_r1(),
                           .read_lru_r2(),
                           .write_lru_rd(),
                           .write_lru_data(),
                           .target_lru_reg(),
                           .target_lru_r1(),
                           .target_lru_r2(),

                           .lru_r1(),
                           .lru_r2(),
                           .rdy_reg3(),
                           .reg3_rdy_valid(),

                           // Check if reg is ready
                           .alu_rs_check_rdy1(),
                           .alu_rs_check_rdy2(),
                           .alu_pr1(),
                           .alu_pr2(),

                           .lsu_rs_check_rdy1(),
                           .lsu_rs_check_rdy2(),
                           .lsu_pr1(),
                           .lsu_pr2(),

                           .branch_rs_check_rdy1(),
                           .branch_rs_check_rdy2(),
                           .branch_pr1(),
                           .branch_pr2(),
                           
                           // Set rd to not ready after dispatch
                           .alu_set_not_rdy(),
                           .lsu_set_not_rdy(),
                           .branch_set_not_rdy(),
                           .alu_rd(),
                           .lsu_rd(),
                           .branch_rd()
                           );
    
    // 
    
endmodule
