`timescale 1ns / 1ps
import types_pkg::*;

module dispatch(
    input logic clk,
    input logic reset,

    // Upstream (Interface with Rename)
    input logic       valid_in,
    input rename_data data_in,    
    output logic      ready_in,   

    // Downstream (Interface with FUs)
    
    // ALU
    output logic alu_rs_valid_out,
    output rs_data alu_rs_data_out,
    input  logic alu_rs_ready_in,

    // Branch Unit
    output logic b_rs_valid_out,
    output rs_data b_rs_data_out,
    input  logic b_rs_ready_in,

    // LSU
    output logic lsu_rs_valid_out,
    output rs_data lsu_rs_data_out,
    input  logic lsu_rs_ready_in,

    // LSQ
    output logic lsq_alloc_valid_out,
    output logic [4:0] lsq_dispatch_rob_tag,
    output logic [31:0] lsq_dispatch_pc,

    // Interface with PRF (Set Busy / Allocation)
    output logic [6:0] alu_nr_reg_out,
    output logic alu_nr_valid_out,
    output logic [6:0] b_nr_reg_out,
    output logic b_nr_valid_out,
    output logic [6:0] lsu_nr_reg_out,
    output logic lsu_nr_valid_out,

    // For checkpoint
    output logic [6:0] not_rdy_reg,

    // Interface with PRF (Readiness Query)
    output logic [6:0] query_ps1,
    output logic [6:0] query_ps2,
    input  logic pr1_is_ready,
    input  logic pr2_is_ready,

    // Common Data Bus (Lost Wakeup Check)
    input logic [6:0] preg1_rdy,
    input logic [6:0] preg2_rdy,
    input logic [6:0] preg3_rdy,
    input logic preg1_valid,
    input logic preg2_valid,
    input logic preg3_valid,

    // Interface with ROB (Allocation)
    output logic rob_we_out,
    output logic [6:0] rob_pd_new_out,
    output logic [6:0] rob_pd_old_out,
    output logic [31:0] rob_pc_out,

    // Interface with ROB (Status)
    input logic [4:0] rob_tag_in,
    input logic rob_full_in,
    input logic [4:0] curr_rob_tag,

    // Global
    input logic mispredict,
    input logic [4:0] mispredict_tag,
    input logic [31:0] mispredict_pc
);

    // Routing Logic
    logic is_alu, is_mem, is_b;
    always_comb begin
        is_alu = data_in.fu_alu;
        is_mem = data_in.fu_mem;
        is_b  = data_in.fu_br;
    end
    
    // ALU RS Buffer
    logic alu_buf_ready_in;
    logic alu_buf_valid_out;
    logic alu_buf_ready_out;
    rename_data alu_buf_data;

    skid_buffer_struct #(.T(rename_data)) u_buf_alu (
        .clk(clk), .reset(reset),
        .mispredict(mispredict),
        .valid_in(valid_in && is_alu && ready_in), 
        .ready_in(alu_buf_ready_in),
        .data_in(data_in),
        .valid_out(alu_buf_valid_out),
        .ready_out(alu_buf_ready_out),
        .data_out(alu_buf_data)
    );

    // Branch RS Buffer
    logic b_buf_ready_in;
    logic b_buf_valid_out;
    logic b_buf_ready_out;
    rename_data b_buf_data;

    skid_buffer_struct #(.T(rename_data)) u_buf_b (
        .clk(clk), .reset(reset),
        .mispredict(mispredict),
        .valid_in(valid_in && is_b && ready_in), 
        .ready_in(b_buf_ready_in), 
        .data_in(data_in),
        .valid_out(b_buf_valid_out),
        .ready_out(b_buf_ready_out),
        .data_out(b_buf_data)
    );

    // LSU RS Buffer
    logic lsu_buf_ready_in;
    logic lsu_buf_valid_out;
    logic lsu_buf_ready_out;
    rename_data lsu_buf_data;

    skid_buffer_struct #(.T(rename_data)) u_buf_lsu (
        .clk(clk), .reset(reset),
        .mispredict(mispredict),
        .valid_in(valid_in && is_mem && ready_in), 
        .ready_in(lsu_buf_ready_in), 
        .data_in(data_in),
        .valid_out(lsu_buf_valid_out),
        .ready_out(lsu_buf_ready_out),
        .data_out(lsu_buf_data)
    );

    // Rename Stall Logic
    assign ready_in = alu_buf_ready_in && b_buf_ready_in && lsu_buf_ready_in && (lsu_rs_ready_in || !data_in.fu_mem);
    
    // Pre-buffer set destination to not ready
    wire dispatch_handshake = valid_in && ready_in;

    assign alu_nr_reg_out = data_in.pd_new;
    assign alu_nr_valid_out = dispatch_handshake && is_alu && (data_in.pd_new != 7'd0) && !mispredict;

    assign b_nr_reg_out = data_in.pd_new;
    assign b_nr_valid_out = dispatch_handshake && is_b && (data_in.pd_new != 7'd0) && !mispredict;

    assign lsu_nr_reg_out = data_in.pd_new;
    assign lsu_nr_valid_out = dispatch_handshake && is_mem && (data_in.pd_new != 7'd0) && !mispredict;

    assign lsq_alloc_valid_out = (data_in.Opcode == 7'b0000011 || data_in.Opcode == 7'b0100011) && dispatch_handshake;

    // Priority Logic
    rename_data active_packet;
    
    always_comb begin
        if (alu_buf_valid_out) begin
            active_packet = alu_buf_data;
        end else if (b_buf_valid_out) begin
            active_packet = b_buf_data;
        end else if (lsu_buf_valid_out) begin
            active_packet = lsu_buf_data;
        end else begin
            active_packet = '0;
        end

        // LSQ dispatch rob tag
        if (lsq_alloc_valid_out) begin
            lsq_dispatch_rob_tag = data_in.rob_tag;
            lsq_dispatch_pc = data_in.pc;
        end else begin
            lsq_dispatch_rob_tag = '0;
            lsq_dispatch_pc = '0;
        end

        if (alu_nr_valid_out) begin
            not_rdy_reg = alu_nr_reg_out;
        end else if (lsu_nr_valid_out) begin
            not_rdy_reg = lsu_nr_reg_out;
        end else if (b_nr_valid_out) begin
            not_rdy_reg = b_nr_reg_out;
        end
    end

    // Buffer Ready Outs
    logic rob_is_full;
    assign rob_is_full = rob_full_in;
    logic alu_rs_has_space, b_rs_has_space, lsu_rs_has_space;

    assign alu_buf_ready_out = !rob_is_full && alu_rs_has_space;
    assign b_buf_ready_out  = !rob_is_full && b_rs_has_space;
    assign lsu_buf_ready_out = !rob_is_full && lsu_rs_has_space;

    // Write Enables for RSs
    logic alu_rs_write_en, b_rs_write_en, lsu_rs_write_en;
    assign alu_rs_write_en = alu_buf_valid_out && alu_buf_ready_out;
    assign b_rs_write_en  = b_buf_valid_out  && b_buf_ready_out;
    assign lsu_rs_write_en = lsu_buf_valid_out && lsu_buf_ready_out;

    // ROB Output
    assign rob_we_out     = alu_rs_write_en || b_rs_write_en || lsu_rs_write_en;
    assign rob_pd_new_out = active_packet.pd_new;
    assign rob_pd_old_out = active_packet.pd_old;
    assign rob_pc_out     = active_packet.pc;

    // Readiness Logic
    assign query_ps1 = active_packet.ps1;
    assign query_ps2 = active_packet.ps2;
    
    dispatch_pipeline_data dispatch_packet;
    logic match_cdb_1, match_cdb_2;

    always_comb begin
        dispatch_packet.Opcode    = active_packet.Opcode;
        dispatch_packet.pc        = active_packet.pc;
        dispatch_packet.prd       = active_packet.pd_new;
        dispatch_packet.pr1       = active_packet.ps1;
        dispatch_packet.pr2       = active_packet.ps2;
        dispatch_packet.imm       = active_packet.imm[31:0];
        dispatch_packet.rob_index = active_packet.rob_tag;

        dispatch_packet.func3     = active_packet.func3;
        dispatch_packet.func7     = active_packet.func7;
        
        dispatch_packet.pr1_ready = 1'b0; 
        dispatch_packet.pr2_ready = 1'b0;

        // Check if the source matches any tag currently on the CDB (forwarding)
        match_cdb_1 = (preg1_valid && preg1_rdy == active_packet.ps1) || 
                      (preg2_valid && preg2_rdy == active_packet.ps1) || 
                      (preg3_valid && preg3_rdy == active_packet.ps1);

        match_cdb_2 = (preg1_valid && preg1_rdy == active_packet.ps2) || 
                      (preg2_valid && preg2_rdy == active_packet.ps2) || 
                      (preg3_valid && preg3_rdy == active_packet.ps2);

        // Determine Final Readiness
        dispatch_packet.pr1_ready = (active_packet.ps1 == 0) || pr1_is_ready || match_cdb_1; 
        dispatch_packet.pr2_ready = (active_packet.ps2 == 0) || pr2_is_ready || match_cdb_2;
    end

    // ALU RS
    rs u_alu_rs (
        .clk(clk),
        .reset(reset),
        .fu_rdy(alu_rs_ready_in),
        .valid_out(alu_rs_valid_out),
        .data_out(alu_rs_data_out),
        .valid_in(alu_rs_write_en),
        .ready_in(alu_rs_has_space),
        .instr(dispatch_packet),
        .reg1_rdy(preg1_rdy), .reg2_rdy(preg2_rdy), .reg3_rdy(preg3_rdy),
        .reg1_rdy_valid(preg1_valid), .reg2_rdy_valid(preg2_valid), .reg3_rdy_valid(preg3_valid),
        .flush(mispredict),
        .flush_tag(mispredict_tag),
        .flush_pc(mispredict_pc)
    );

    // Branch RS
    rs_bu u_branch_rs (
        .clk(clk),
        .reset(reset),
        .fu_rdy(b_rs_ready_in),
        .valid_out(b_rs_valid_out),
        .data_out(b_rs_data_out),
        .valid_in(b_rs_write_en),
        .ready_in(b_rs_has_space),
        .instr(dispatch_packet),
        .reg1_rdy(preg1_rdy), .reg2_rdy(preg2_rdy), .reg3_rdy(preg3_rdy),
        .reg1_rdy_valid(preg1_valid), .reg2_rdy_valid(preg2_valid), .reg3_rdy_valid(preg3_valid),
        .flush(mispredict),
        .flush_tag(mispredict_tag),
        .flush_pc(mispredict_pc)
    );

    // LSU RS
    rs u_lsu_rs (
        .clk(clk),
        .reset(reset),
        .fu_rdy(1'b1),
        .valid_out(lsu_rs_valid_out),
        .data_out(lsu_rs_data_out),
        .valid_in(lsu_rs_write_en),
        .ready_in(lsu_rs_has_space),
        .instr(dispatch_packet),
        .reg1_rdy(preg1_rdy), .reg2_rdy(preg2_rdy), .reg3_rdy(preg3_rdy),
        .reg1_rdy_valid(preg1_valid), .reg2_rdy_valid(preg2_valid), .reg3_rdy_valid(preg3_valid),
        .flush(mispredict),
        .flush_tag(mispredict_tag),
        .flush_pc(mispredict_pc)
    );
endmodule