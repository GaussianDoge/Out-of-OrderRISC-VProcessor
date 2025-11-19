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
    output logic br_rs_valid_out,
    output rs_data br_rs_data_out,
    input  logic br_rs_ready_in,

    // LSU
    output logic lsu_rs_valid_out,
    output rs_data lsu_rs_data_out,
    input  logic lsu_rs_ready_in,

    // Interface with PRF
    output logic [6:0] dispatch_nr_reg,
    output logic dispatch_nr_valid,

    input logic [6:0] preg1_rdy,
    input logic [6:0] preg2_rdy,
    input logic [6:0] preg3_rdy,
    input logic preg1_valid,
    input logic preg2_valid,
    input logic preg3_valid,

    // Interface with ROB
    input logic complete_in,
    input logic [4:0] rob_fu_tag, // why 5 bits
    input logic mispredict,
    input logic [4:0] mispredict_tag, // why 5 bits
    
    output logic [4:0] rob_retire_tag, // why 5 bits
    output logic rob_retire_valid
);

    // Routing Logic
    logic is_alu, is_mem, is_br;
    always_comb begin
        is_alu = data_in.fu_alu;
        is_mem = data_in.fu_mem;
        is_br  = data_in.fu_br;
    end
    
    // ALU RS Buffer
    logic alu_buf_valid_out;
    logic alu_buf_ready_out;
    rename_data alu_buf_data;

    skid_buffer_struct #(.T(rename_data)) u_buf_alu (
        .clk(clk), .reset(reset),
        .valid_in(valid_in && is_alu), 
        .ready_in(),
        .data_in(data_in),
        .valid_out(alu_buf_valid_out),
        .ready_out(alu_buf_ready_out),
        .data_out(alu_buf_data)
    );

    // Branch RS Buffer
    logic br_buf_valid_out;
    logic br_buf_ready_out;
    rename_data br_buf_data;

    skid_buffer_struct #(.T(rename_data)) u_buf_br (
        .clk(clk), .reset(reset),
        .valid_in(valid_in && is_br), 
        .ready_in(), 
        .data_in(data_in),
        .valid_out(br_buf_valid_out),
        .ready_out(br_buf_ready_out),
        .data_out(br_buf_data)
    );

    // LSU RS Buffer
    logic lsu_buf_valid_out;
    logic lsu_buf_ready_out;
    rename_data lsu_buf_data;

    skid_buffer_struct #(.T(rename_data)) u_buf_lsu (
        .clk(clk), .reset(reset),
        .valid_in(valid_in && is_mem), 
        .ready_in(), 
        .data_in(data_in),
        .valid_out(lsu_buf_valid_out),
        .ready_out(lsu_buf_ready_out),
        .data_out(lsu_buf_data)
    );

    // Rename Stall Logic
    assign ready_in = !(alu_buf_valid_out || br_buf_valid_out || lsu_buf_valid_out);

    // Dispatch Logic
    logic rob_is_full;
    logic alu_rs_has_space, br_rs_has_space, lsu_rs_has_space;

    rename_data active_packet;
    
    always_comb begin
        if (alu_buf_valid_out) begin
            active_packet = alu_buf_data;
        end else if (br_buf_valid_out) begin
            active_packet = br_buf_data;
        end else if (lsu_buf_valid_out) begin
            active_packet = lsu_buf_data;
        end else begin
            active_packet = '0;
        end
    end

    // Buffer Ready Outs
    assign alu_buf_ready_out = !rob_is_full && alu_rs_has_space;
    assign br_buf_ready_out  = !rob_is_full && br_rs_has_space;
    assign lsu_buf_ready_out = !rob_is_full && lsu_rs_has_space;

    // Write Enables for RSs
    logic alu_rs_write_en;
    logic br_rs_write_en;
    logic lsu_rs_write_en;
    assign alu_rs_write_en = alu_buf_valid_out && alu_buf_ready_out;
    assign br_rs_write_en  = br_buf_valid_out  && br_buf_ready_out;
    assign lsu_rs_write_en = lsu_buf_valid_out && lsu_buf_ready_out;

    // Write Enable for ROB
    logic rob_we;
    assign rob_we = alu_rs_write_en || br_rs_write_en || lsu_rs_write_en;

    // ROB
    rob u_rob (
        .clk            (clk),
        .reset          (reset),
        .write_en       (rob_we),
        .pd_new_in      (active_packet.pd_new), 
        .pd_old_in      (active_packet.pd_old),
        .pc_in          (active_packet.pc),
        .complete_in    (complete_in),
        .rob_fu         (rob_fu_tag), // 5 bits?
        .mispredict     (mispredict),
        .branch         (1'b0), 
        .mispredict_tag (mispredict_tag), // 5 bits?
        .rob_tag_out    (rob_retire_tag), // 5 bits?
        .valid_retired  (rob_retire_valid),
        .complete_out   (), 
        .full           (rob_is_full),
        .empty          ()
    );

    dispatch_pipeline_data dispatch_packet;
    always_comb begin
        dispatch_packet.Opcode    = active_packet.Opcode;
        dispatch_packet.pc        = active_packet.pc;
        dispatch_packet.prd       = active_packet.pd_new;
        dispatch_packet.pr1       = active_packet.ps1;
        dispatch_packet.pr2       = active_packet.ps2;
        dispatch_packet.imm       = active_packet.imm[31:0];
        dispatch_packet.rob_index = active_packet.rob_tag[3:0];

        dispatch_packet.func3     = active_packet.func3;
        dispatch_packet.func7     = active_packet.func7;
        
        dispatch_packet.pr1_ready = 1'b0; 
        dispatch_packet.pr2_ready = 1'b0;
    end
    
    logic [6:0] alu_nr_reg;
    logic alu_nr_valid;

    logic [6:0] br_nr_reg;
    logic br_nr_valid;

    logic [6:0] lsu_nr_reg;
    logic lsu_nr_valid;

    // ALU RS
    rs u_alu_rs (
        .clk(clk), .reset(reset),
        .fu_rdy(alu_rs_ready_in),
        .valid_out(alu_rs_valid_out), 
        .data_out(alu_rs_data_out),
        
        .valid_in(alu_rs_write_en),
        .ready_in(alu_rs_has_space), 
        .instr(dispatch_packet),
        
        .nr_reg(alu_nr_reg),
        .nr_valid(alu_nr_valid),
        
        .reg1_rdy(preg1_rdy),
        .reg2_rdy(preg2_rdy),
        .reg3_rdy(preg3_rdy),

        .reg1_rdy_valid(preg1_valid),
        .reg2_rdy_valid(preg2_valid),
        .reg3_rdy_valid(preg3_valid),
        
        .flush(mispredict)
    );

    // Branch RS
    rs u_branch_rs (
        .clk(clk), .reset(reset),
        .fu_rdy(br_rs_ready_in),
        .valid_out(br_rs_valid_out), 
        .data_out(br_rs_data_out),
        
        .valid_in(br_rs_write_en),
        .ready_in(br_rs_has_space), 
        .instr(dispatch_packet),
        
        .nr_reg(br_nr_reg),
        .nr_valid(br_nr_valid),
        
        .reg1_rdy(preg1_rdy),
        .reg2_rdy(preg2_rdy),
        .reg3_rdy(preg3_rdy),
        
        .reg1_rdy_valid(preg1_valid),
        .reg2_rdy_valid(preg2_valid),
        .reg3_rdy_valid(preg3_valid),
        
        .flush(mispredict)
    );

    // LSU RS
    rs u_lsu_rs (
        .clk(clk), .reset(reset),
        .fu_rdy(lsu_rs_ready_in),
        .valid_out(lsu_rs_valid_out), 
        .data_out(lsu_rs_data_out),
        
        .valid_in(lsu_rs_write_en),
        .ready_in(lsu_rs_has_space), 
        .instr(dispatch_packet),
        
        .nr_reg(lsu_nr_reg),
        .nr_valid(lsu_nr_valid),
        
        .reg1_rdy(preg1_rdy),
        .reg2_rdy(preg2_rdy),
        .reg3_rdy(preg3_rdy),

        .reg1_rdy_valid(preg1_valid),
        .reg2_rdy_valid(preg2_valid),
        .reg3_rdy_valid(preg3_valid),
        
        .flush(mispredict)
    );

    // PRF Update Logic
    assign dispatch_nr_valid = alu_nr_valid | br_nr_valid | lsu_nr_valid;
    
    always_comb begin
        if (alu_nr_valid) begin
            dispatch_nr_reg = alu_nr_reg;
        end else if (br_nr_valid) begin
            dispatch_nr_reg = br_nr_reg;
        end else if (lsu_nr_valid) begin 
            dispatch_nr_reg = lsu_nr_reg;
        end else begin
            dispatch_nr_reg = '0;
        end
    end

endmodule