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
    // Problematic:
    // We need to set readiness for src regs in order before send to Pipeline Buffer and RS

    logic alu_issued;
    rs_data alu_rs_data_out;
    logic alu_rdy;
    logic [6:0] alu_nr_reg;
    logic alu_nr_valid;

    logic b_issued;
    rs_data br_rs_data_out;
    logic br_rdy;
    logic [6:0] branch_nr_reg;
    logic branch_nr_valid;

    logic mem_issued;
    rs_data lsu_rs_data_out;
    logic lsu_rdy;
    logic [6:0] lsu_nr_reg;
    logic lsu_nr_valid;
    dispatch dispatch_unit(.clk(clk),
                           .reset(reset),
                           
                           // upstream from rename
                           .valid_in(rename_valid_out),
                           .data_in(rename_data_out),
                           .ready_in(dispatch_ready_in),
                           
                           // Downstream (Interface with FUs)
                           // ALU
                           .alu_rs_valid_out(alu_issued),
                           .alu_rs_data_out(alu_rs_data_out),
                           .alu_rs_ready_in(alu_rdy),
                           
                           // Branch Unit
                           .br_rs_valid_out(b_issued),
                           .br_rs_data_out(br_rs_data_out),
                           .br_rs_ready_in(br_rdy),
                           
                           // LSU
                           .lsu_rs_valid_out(mem_issued),
                           .lsu_rs_data_out(lsu_rs_data_out),
                           .lsu_rs_ready_in(lsu_rdy)
                           
                           // Interface with PRF
                           .alu_nr_reg(alu_nr_reg),
                           .alu_nr_valid(alu_nr_valid),
                           .br_nr_reg(branch_nr_reg),
                           .br_nr_valid(branch_nr_valid),
                           .lsu_nr_reg(lsu_nr_reg),
                           .lsu_nr_valid(lsu_nr_valid),

                           .preg1_rdy(rdy_reg1),
                           .preg2_rdy(rdy_reg2),
                           .preg3_rdy(rdy_reg3),
                           .preg1_valid(reg1_rdy_valid),
                           .preg2_valid(reg2_rdy_valid),
                           .preg3_valid(reg3_rdy_valid),

                           // Interface with ROB

                           );
    // Load From Reg
    // Wires between PRF and load_reg
    logic read_alu_r1, read_alu_r2;
    logic read_b_r1,   read_b_r2;
    logic read_lru_r1, read_lru_r2;
    logic [6:0] target_alu_r1, target_alu_r2;
    logic [6:0] target_b_r1,   target_b_r2;
    logic [6:0] target_lru_r1, target_lru_r2;
    
    logic [31:0] alu_r1, alu_r2;
    logic [31:0] b_r1,   b_r2;
    logic [31:0] lru_r1, lru_r2;
    
    // Wires from load_reg into fus
    logic [31:0] ps1_alu_data, ps2_alu_data;
    logic [31:0] ps1_b_data,   ps2_b_data;
    logic [31:0] ps1_mem_data, ps2_mem_data;
    
    load_reg u_load_reg(.alu_issued(alu_issued),
                        .alu_rs_data(alu_rs_data_out),
                        .b_issued(b_issued),
                        .b_rs_data(br_rs_data_out),
                        .mem_issued(mem_issued),
                        .mem_rs_data(lsu_rs_data_out),
                    
                        // PRF control + data
                        .read_alu_r1(read_alu_r1),
                        .read_alu_r2(read_alu_r2),
                        .read_b_r1(read_b_r1),
                        .read_b_r2(read_b_r2),
                        .read_lru_r1(read_lru_r1),
                        .read_lru_r2(read_lru_r2),
                        .target_alu_r1(target_alu_r1),
                        .target_alu_r2(target_alu_r2),
                        .target_b_r1(target_b_r1),
                        .target_b_r2(target_b_r2),
                        .target_lru_r1(target_lru_r1),
                        .target_lru_r2(target_lru_r2),
                    
                        .alu_r1(alu_r1),
                        .alu_r2(alu_r2),
                        .b_r1(b_r1),
                        .b_r2(b_r2),
                        .lru_r1(lru_r1),
                        .lru_r2(lru_r2),
                    
                        // To FUs
                        .ps1_alu_data(ps1_alu_data),
                        .ps2_alu_data(ps2_alu_data),
                        .ps1_b_data(ps1_b_data),
                        .ps2_b_data(ps2_b_data),
                        .ps1_mem_data(ps1_mem_data),
                        .ps2_mem_data(ps2_mem_data));
    
    
    // PRF (Physical Register Files)
    // From FUs (Write Back)
    logic write_alu_rd;
    logic [31:0] write_alu_data;
    logic [6:0] target_alu_reg;

    logic write_b_rd;
    logic [31:0] write_b_data;
    logic [6:0] target_b_reg;

    logic write_lru_rd;
    logic [31:0] write_lru_data;
    logic [6:0] target_lru_reg;

    // From PRF to RS (Set readiness)
    logic [6:0] rdy_reg1;
    logic reg1_rdy_valid;
    logic [6:0] rdy_reg2;
    logic reg2_rdy_valid;
    logic [6:0] rdy_reg3;
    logic reg3_rdy_valid;
    
    physical_registers PRF(.clk(clk),
                           .reset(reset),
                           
                           // Read and Write for ALU
                           .read_alu_r1(read_alu_r1),
                           .read_alu_r2(read_alu_r2),
                           .write_alu_rd(write_alu_rd),
                           .write_alu_data(write_alu_data),
                           .target_alu_reg(target_alu_reg),
                           .target_alu_r1(target_alu_r1),
                           .target_alu_r2(target_alu_r2),

                           .alu_r1(alu_r1),
                           .alu_r2(alu_r2),
                           .rdy_reg1(rdy_reg1),
                           .reg1_rdy_valid(reg1_rdy_valid),
                           
                           // Read and Write for Branch
                           .read_b_r1(read_b_r1),
                           .read_b_r2(read_b_r2),
                           .write_b_rd(write_b_rd),
                           .write_b_data(write_b_data),
                           .target_b_reg(target_b_reg),
                           .target_b_r1(target_b_r1),
                           .target_b_r2(target_b_r2),

                           .b_r1(b_r1),
                           .b_r2(b_r2),
                           .rdy_reg2(rdy_reg2),
                           .reg2_rdy_valid(reg2_rdy_valid),
                           
                           // Read and Write for LRU
                           .read_lru_r1(read_lru_r1),
                           .read_lru_r2(read_lru_r2),
                           .write_lru_rd(write_lru_rd),
                           .write_lru_data(write_lru_data),
                           .target_lru_reg(target_lru_reg),
                           .target_lru_r1(target_lru_r1),
                           .target_lru_r2(target_lru_r2),

                           .lru_r1(lru_r1),
                           .lru_r2(lru_r2),
                           .rdy_reg3(rdy_reg3),
                           .reg3_rdy_valid(reg3_rdy_valid),

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
                           .alu_set_not_rdy(alu_nr_valid),
                           .lsu_set_not_rdy(lsu_nr_valid),
                           .branch_set_not_rdy(branch_nr_valid),
                           .alu_rd(alu_nr_reg),
                           .lsu_rd(lsu_nr_reg),
                           .branch_rd(branch_nr_reg)
                           );
    
    // FUs
    alu_data alu_data_out;
    b_data b_data_out;
    mem_data mem_data_out;
    
    assign write_alu_rd = alu_data_out.fu_alu_done;
    assign write_alu_data = alu_data_out.data;
    assign target_alu_reg = alu_data_out.p_alu;
    assign write_b_rd = b_data_out.fu_b_done;
    assign write_b_data = b_data_out.data;
    assign target_b_reg = b_data_out.p_b;
    assign write_lru_rd = mem_data_out.fu_mem_done;
    assign write_lru_data = mem_data_out.data;
    assign target_lru_reg = mem_data_out.p_mem;
    assign alu_rdy = alu_data_out.fu_alu_ready;
    assign br_rdy = b_data_out.fu_b_ready;
    assign lsu_rdy = mem_data_out.fu_mem_ready;
    
    fus fu(.clk(clk),
           .reset(reset),

           // From Reservation Stations
           .alu_issued(alu_issued),
           .alu_rs_data(alu_rs_data_out),
           .b_issued(b_issued),
           .b_rs_data(br_rs_data_out),
           .mem_issued(mem_issued),
           .mem_rs_data(lsu_rs_data_out),

           // From ROB
           .curr_rob_tag(),
           .mispredict(mispredict),
           .mispredict_tag(),

           // PRF
           .ps1_alu_data(ps1_alu_data),
           .ps2_alu_data(ps2_alu_data),
           .ps1_b_data(ps1_b_data),
           .ps2_b_data(ps2_b_data),
           .ps1_mem_data(ps1_mem_data),
           .ps2_mem_data(ps2_mem_data),

           // From FU branch
           .br_mispredict(mispredict),
           .br_mispredict_tag(),

           // Output data
           .alu_out(alu_data_out),
           .b_out(b_data_out),
           .mem_out(mem_data_out)
           );
    
endmodule
