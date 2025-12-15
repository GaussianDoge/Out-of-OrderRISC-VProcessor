`timescale 1ns / 1ps
import types_pkg::*;

module processor(
    input logic clk,
    input logic reset
    );
    
    // General Signals
    logic [31:0] pc;
    logic mispredict;
    logic [4:0] mispredict_tag;
    
    always_ff @(posedge clk) begin
        if (reset) begin
            pc <= 32'd0;
        end else if (b_data_out.fu_b_done && b_data_out.jalr_bne_signal) begin
            pc <= b_data_out.pc;
        end else if (pc <= 12 || frontend_valid_out && rename_ready_in && !mispredict) begin
            pc <= pc + 4;
        end
    end
    
    // Frontend (Fetch & Decode)
    logic rename_ready_in;
    decode_data frontend_data_out;
    logic frontend_valid_out;
    
    frontend frontend_unit(
        .clk(clk), 
        .reset(reset), 
        .pc_in(pc),
        .mispredict(mispredict),
        .frontend_ready_out(rename_ready_in),
        .data_out(frontend_data_out),
        .frontend_valid_out(frontend_valid_out)
    );
    
    // Commit Signals
    logic rob_retire_valid;
    logic [6:0] retire_pd_old;

    // Rename Stage
    rename_data rename_data_out;
    logic rename_valid_out;
    logic dispatch_ready_in;
    
    rename rename_unit(
        .clk(clk), 
        .reset(reset), 
        .valid_in(frontend_valid_out), 
        .data_in(frontend_data_out),
        .ready_in(rename_ready_in),
        .mispredict(mispredict),
        .data_out(rename_data_out),
        .valid_out(rename_valid_out),
        .ready_out(dispatch_ready_in),
        .write_en(rob_retire_valid),
        .rob_data_in(retire_pd_old)
    );


   // Check point for recovery
   logic branch_detect;
   logic checkpoint_valid;
   assign branch_detect = rename_data_out.fu_br && rename_valid_out;

   logic not_rdy_pr_valid;
   assign not_rdy_pr_valid =  alu_nr_valid || b_nr_valid || lsu_nr_valid;
   logic [6:0] not_rdy_pr;

   checkpoint snapshot_out;


    
   checkpoint check_point(
       .clk(clk),
       .reset(reset),

       // From Rename
       .branch_detect(branch_detect),
       .branch_pc(rename_data_out.pc),
       .branch_rob_tag(rename_data_out.rob_tag),
       .not_rdy_pr(not_rdy_pr),
       .not_rdy_pr_valid(not_rdy_pr_valid),

       // From ROB
       .mispredict(mispredict),
       .mispredict_tag(mispredict_tag),

       // Output
       .checkpoint_valid(checkpoint_valid),
       .snapshot(snapshot_out)
   );


    
    // Dispatch Stage
    logic alu_issued, b_issued, mem_issued;
    rs_data alu_rs_data_out, b_rs_data_out, lsu_rs_data_out;
    logic alu_rdy, b_rdy, lsu_rdy;

    // Wires for Readiness Check (Query)
    logic [6:0] dispatch_query_ps1, dispatch_query_ps2;
    logic prf_response_rdy1, prf_response_rdy2;

    // Wires for Setting Registers to "Busy" (Allocation)
    logic [6:0] alu_nr_reg, b_nr_reg, lsu_nr_reg;
    logic alu_nr_valid, b_nr_valid, lsu_nr_valid;

    // Signals connecting Dispatch to ROB
    logic dispatch_rob_we;
    logic [6:0] dispatch_rob_pd_new;
    logic [6:0] dispatch_rob_pd_old;
    logic [31:0] dispatch_rob_pc;

    // Signals connecting ROB to Dispatch
    logic [4:0] rob_alloc_ptr;
    logic rob_full;
    logic [4:0] rob_head;

    // Writeback Signals (CDB)
    alu_data alu_data_out;
    b_data b_data_out;
    mem_data mem_data_out;

    // Dispatch to LSQ
    logic dispatch_valid;
    logic [4:0] dispatch_rob_tag;

    // // PRF to RS (Set Readiness)
    // logic [6:0] rdy_reg1, rdy_reg2, rdy_reg3;
    // logic reg1_rdy_valid, reg2_rdy_valid, reg3_rdy_valid;    
    
    dispatch dispatch_unit(
        .clk(clk),
        .reset(reset),
        
        // Upstream from rename
        .valid_in(rename_valid_out),
        .data_in(rename_data_out),
        .ready_in(dispatch_ready_in),
        
        // Downstream (Interface with FUs)
        .alu_rs_valid_out(alu_issued), .alu_rs_data_out(alu_rs_data_out), .alu_rs_ready_in(alu_rdy),
        .b_rs_valid_out(b_issued), .b_rs_data_out(b_rs_data_out), .b_rs_ready_in(b_rdy),
        .lsu_rs_valid_out(mem_issued), .lsu_rs_data_out(lsu_rs_data_out), .lsu_rs_ready_in(lsu_rdy),

        // Interface with LSQ
        .lsq_alloc_valid_out(dispatch_valid),
        .lsq_dispatch_rob_tag(dispatch_rob_tag),
        
        // Interface with PRF
        .query_ps1(dispatch_query_ps1), .query_ps2(dispatch_query_ps2),
        .pr1_is_ready(prf_response_rdy1), .pr2_is_ready(prf_response_rdy2),
        .alu_nr_reg_out(alu_nr_reg), .alu_nr_valid_out(alu_nr_valid),
        .b_nr_reg_out(b_nr_reg), .b_nr_valid_out(b_nr_valid),
        .lsu_nr_reg_out(lsu_nr_reg), .lsu_nr_valid_out(lsu_nr_valid),

        // For checkpoint
        .not_rdy_reg(not_rdy_pr),

        // CDB Inputs (For "Lost Wakeup" Check)
        .preg1_rdy(alu_data_out.p_alu), .preg1_valid(alu_data_out.fu_alu_done),
        .preg2_rdy(b_data_out.p_b), .preg2_valid(b_data_out.fu_b_done),
        .preg3_rdy(mem_data_out.p_mem), .preg3_valid(mem_data_out.fu_mem_done),

        // Interface with ROB
        .rob_we_out(dispatch_rob_we),
        .rob_pd_new_out(dispatch_rob_pd_new),
        .rob_pd_old_out(dispatch_rob_pd_old),
        .rob_pc_out(dispatch_rob_pc),
        .rob_tag_in(rob_alloc_ptr),
        .rob_full_in(rob_full),
        
        // Global
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag)
    );

    


    logic [4:0] store_rob_tag;
    logic store_lsq_done;

    // ROB (Reorder Buffer)
    rob u_rob(
        .clk(clk),
        .reset(reset),
        
        // Interface with Dispatch
        .write_en(dispatch_rob_we),
        .pd_new_in(dispatch_rob_pd_new),
        .pd_old_in(dispatch_rob_pd_old),
        .pc_in(dispatch_rob_pc),
        
        // Interface with FUs
        .fu_alu_done(alu_data_out.fu_alu_done),
        .rob_fu_alu(alu_data_out.rob_fu_alu),
        .fu_b_done(b_data_out.fu_b_done),
        .rob_fu_b(b_data_out.rob_fu_b),
        .fu_mem_done(mem_data_out.fu_mem_done),
        .rob_fu_mem(mem_data_out.rob_fu_mem),
        .store_rob_tag(store_rob_tag),
        .store_lsq_done(store_lsq_done),
        
        // Branch Mispredict (From FU Branch)
        .br_mispredict(b_data_out.mispredict),
        .br_mispredict_tag(b_data_out.mispredict_tag),
        
        .head(rob_head),

        // Outputs (Global Control & Commit)
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),

        .valid_retired(rob_retire_valid),
        .preg_old(retire_pd_old), // Connect to Rename

        .ptr(rob_alloc_ptr), // Connect to Dispatch
        .full(rob_full) // Connect to Dispatch
    );

    // Load From Reg
    // Wires between PRF and load_reg
    logic read_alu_r1, read_alu_r2;
    logic read_b_r1, read_b_r2;
    logic read_lsu_r1, read_lsu_r2;

    logic [6:0] target_alu_r1, target_alu_r2;
    logic [6:0] target_b_r1, target_b_r2;
    logic [6:0] target_lsu_r1, target_lsu_r2;
    
    logic [31:0] alu_r1, alu_r2;
    logic [31:0] b_r1, b_r2;
    logic [31:0] lru_r1, lru_r2;
    
    // Wires from load_reg into fus
    logic [31:0] ps1_alu_data, ps2_alu_data;
    logic [31:0] ps1_b_data, ps2_b_data;
    logic [31:0] ps1_mem_data, ps2_mem_data;
    
    load_reg u_load_reg(
        .alu_issued(alu_issued), .alu_rs_data(alu_rs_data_out),
        .b_issued(b_issued), .b_rs_data(b_rs_data_out),
        .mem_issued(mem_issued), .mem_rs_data(lsu_rs_data_out),
    
        // PRF control + data
        .read_alu_r1(read_alu_r1), .read_alu_r2(read_alu_r2),
        .read_b_r1(read_b_r1), .read_b_r2(read_b_r2),
        .read_lru_r1(read_lsu_r1), .read_lru_r2(read_lsu_r2),

        .target_alu_r1(target_alu_r1), .target_alu_r2(target_alu_r2),
        .target_b_r1(target_b_r1), .target_b_r2(target_b_r2),
        .target_lru_r1(target_lsu_r1), .target_lru_r2(target_lsu_r2),
    
        .alu_r1(alu_r1), .alu_r2(alu_r2),
        .b_r1(b_r1), .b_r2(b_r2),
        .lru_r1(lru_r1), .lru_r2(lru_r2),
    
        // To FUs
        .ps1_alu_data(ps1_alu_data), .ps2_alu_data(ps2_alu_data),
        .ps1_b_data(ps1_b_data), .ps2_b_data(ps2_b_data),
        .ps1_mem_data(ps1_mem_data), .ps2_mem_data(ps2_mem_data)
    );
    
    // PRF Bridge
    logic write_alu_rd, write_b_rd, write_lsu_rd;
    logic [31:0] write_alu_data, write_b_data, write_lsu_data;
    logic [6:0] target_alu_reg, target_b_reg, target_lsu_reg;
    
    assign write_alu_rd = alu_data_out.fu_alu_done;
    assign write_alu_data = alu_data_out.data;
    assign target_alu_reg = alu_data_out.p_alu;

    assign write_b_rd = b_data_out.fu_b_done;
    assign write_b_data = b_data_out.data;
    assign target_b_reg = b_data_out.p_b;

    assign write_lsu_rd = mem_data_out.fu_mem_done;
    assign write_lsu_data = mem_data_out.data;
    assign target_lsu_reg = mem_data_out.p_mem;

    assign alu_rdy = alu_data_out.fu_alu_ready;
    assign b_rdy = b_data_out.fu_b_ready;
    assign lsu_rdy = mem_data_out.fu_mem_ready;
    
    physical_registers PRF(
        .clk(clk),
        .reset(reset),

        // Mispredict
        .mispredict(mispredict),
        .checkpoint_valid(checkpoint_valid),
        .checkpoint(snapshot_out),
        
        // Read Ports
        .read_alu_r1(read_alu_r1), .read_alu_r2(read_alu_r2),
        .write_alu_rd(write_alu_rd),
        .write_alu_data(write_alu_data),
        .target_alu_reg(target_alu_reg),
        .target_alu_r1(target_alu_r1), .target_alu_r2(target_alu_r2),
        .alu_r1(alu_r1), .alu_r2(alu_r2),
        .rdy_reg1(), .reg1_rdy_valid(), // Outputs from PRF (Unused)
        
        .read_b_r1(read_b_r1), .read_b_r2(read_b_r2),
        .write_b_rd(write_b_rd),
        .write_b_data(write_b_data),
        .target_b_reg(target_b_reg),
        .target_b_r1(target_b_r1), .target_b_r2(target_b_r2),
        .b_r1(b_r1), .b_r2(b_r2),
        .rdy_reg2(), .reg2_rdy_valid(), // Outputs from PRF (Unused)
        
        .read_lru_r1(read_lsu_r1), .read_lru_r2(read_lsu_r2),
        .write_lru_rd(write_lsu_rd),
        .write_lru_data(write_lsu_data),
        .target_lru_reg(target_lsu_reg),
        .target_lru_r1(target_lsu_r1), .target_lru_r2(target_lsu_r2),
        .lru_r1(lru_r1), .lru_r2(lru_r2),
        .rdy_reg3(), .reg3_rdy_valid(), // Outputs from PRF (Unused)

        // Readiness Check (Queries from Dispatch)
        // Wire Dispatch Query signals to the ALU ports since it's a unified table
        .alu_rs_check_rdy1(1'b1), // Always enable check if query has data
        .alu_rs_check_rdy2(1'b1),
        .alu_pr1(dispatch_query_ps1), .alu_pr2(dispatch_query_ps2),
        .alu_rs_rdy1(prf_response_rdy1), .alu_rs_rdy2(prf_response_rdy2),

        // Tie off other check ports to 0
        .lsu_rs_check_rdy1(1'b0), .lsu_rs_check_rdy2(1'b0),
        .lsu_pr1(7'b0), .lsu_pr2(7'b0),
        .lsu_rs_rdy1(), .lsu_rs_rdy2(),

        .branch_rs_check_rdy1(1'b0), .branch_rs_check_rdy2(1'b0),
        .branch_pr1(7'b0), .branch_pr2(7'b0),
        .branch_rs_rdy1(), .branch_rs_rdy2(),
        
        // Set Busy (From Dispatch Allocation)
        .alu_set_not_rdy(alu_nr_valid), .alu_rd(alu_nr_reg),
        .lsu_set_not_rdy(lsu_nr_valid), .lsu_rd(lsu_nr_reg),
        .branch_set_not_rdy(b_nr_valid), .branch_rd(b_nr_reg)
    );

    // assign rdy_reg1 = target_alu_reg;
    // assign reg1_rdy_valid = write_alu_rd;
    // assign rdy_reg2 = target_b_reg;
    // assign reg2_rdy_valid = write_b_rd;
    // assign rdy_reg3 = target_lsu_reg;
    // assign reg3_rdy_valid = write_lsu_rd;
    
    // FUs
    fus fu(
        .clk(clk),
        .reset(reset),

        // From Dispatch
        .dispatch_valid(dispatch_valid),
        .dispatch_rob_tag(dispatch_rob_tag),

        // From Reservation Stations
        .alu_issued(alu_issued), .alu_rs_data(alu_rs_data_out),
        .b_issued(b_issued), .b_rs_data(b_rs_data_out),
        .mem_issued(mem_issued), .mem_rs_data(lsu_rs_data_out),

        // From ROB
        .retired(rob_retire_valid),
        .rob_head(rob_head),
        .curr_rob_tag(rob_alloc_ptr),
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),

        // From PRF
        .ps1_alu_data(ps1_alu_data), .ps2_alu_data(ps2_alu_data),
        .ps1_b_data(ps1_b_data), .ps2_b_data(ps2_b_data),
        .ps1_mem_data(ps1_mem_data), .ps2_mem_data(ps2_mem_data),

        // From FU branch
        .br_mispredict(), // OUTPUT OPEN: Signal captured via b_out struct below
        .br_mispredict_tag(), // OUTPUT OPEN: Signal captured via b_out struct below

        // Output data
        .alu_out(alu_data_out),
        .b_out(b_data_out),
        .mem_out(mem_data_out),
        .store_rob_tag(store_rob_tag),
        .store_lsq_done(store_lsq_done)
    );
endmodule