`timescale 1ns/1ps
import types_pkg::*;

// Simple integration test: fu_alu + phys_reg_file
module fu_alu_prf_tb;

  // Clock / reset
  logic clk;
  logic reset;

  // FU → PRF connections
  logic        issued;
  rs_data      data_in;
  logic [31:0] ps1_data;
  logic [31:0] ps2_data;
  alu_data     alu_out;

  // PRF ports
  logic        write_alu_en;
  logic [31:0] data_alu_in;
  logic [6:0]  pd_alu_in;

  logic        write_b_en;
  logic [31:0] data_b_in;
  logic [6:0]  pd_b_in;

  logic        write_mem_en;
  logic [31:0] data_mem_in;
  logic [6:0]  pd_mem_in;

  logic        read_en_alu;
  logic        read_en_b;
  logic        read_en_mem;

  logic [6:0]  ps1_in_alu;
  logic [6:0]  ps2_in_alu;
  logic [6:0]  ps1_in_b;
  logic [6:0]  ps2_in_b;
  logic [6:0]  ps1_in_mem;
  logic [6:0]  ps2_in_mem;

  logic [31:0] ps1_out_alu;
  logic [31:0] ps2_out_alu;
  logic [31:0] ps1_out_b;
  logic [31:0] ps2_out_b;
  logic [31:0] ps1_out_mem;
  logic [31:0] ps2_out_mem;

  // ROB / branch signals (not really used here)
  logic [4:0]  curr_rob_tag;
  logic        mispredict;
  logic [4:0]  mispredict_tag;

  // Some handy params
  localparam logic [6:0] OPCODE_OPIMM = 7'b0010011; // ADDI
  localparam logic [6:0] TEST_PD      = 7'd5;
  localparam logic [4:0] TEST_ROB     = 5'd3;

  // DUTs ----------------------------------------------------------------

  fu_alu u_alu (
    .clk            (clk),
    .reset          (reset),
    .curr_rob_tag   (curr_rob_tag),
    .mispredict     (mispredict),
    .mispredict_tag (mispredict_tag),
    .issued         (issued),
    .data_in        (data_in),
    .ps1_data       (ps1_data),
    .ps2_data       (ps2_data),
    .data_out       (alu_out)
  );

  // Connect FU → PRF write port
  assign write_alu_en = alu_out.fu_alu_done;
  assign data_alu_in  = alu_out.data;
  assign pd_alu_in    = alu_out.p_alu;

  // No branch / mem writes for this test
  assign write_b_en   = 1'b0;
  assign data_b_in    = '0;
  assign pd_b_in      = '0;

  assign write_mem_en = 1'b0;
  assign data_mem_in  = '0;
  assign pd_mem_in    = '0;

  phys_reg_file u_prf (
    .clk          (clk),
    .reset        (reset),

    .write_alu_en (write_alu_en),
    .data_alu_in  (data_alu_in),
    .pd_alu_in    (pd_alu_in),

    .write_b_en   (write_b_en),
    .data_b_in    (data_b_in),
    .pd_b_in      (pd_b_in),

    .write_mem_en (write_mem_en),
    .data_mem_in  (data_mem_in),
    .pd_mem_in    (pd_mem_in),

    .read_en_alu  (read_en_alu),
    .read_en_b    (read_en_b),
    .read_en_mem  (read_en_mem),

    .ps1_in_alu   (ps1_in_alu),
    .ps2_in_alu   (ps2_in_alu),
    .ps1_in_b     (ps1_in_b),
    .ps2_in_b     (ps2_in_b),
    .ps1_in_mem   (ps1_in_mem),
    .ps2_in_mem   (ps2_in_mem),

    .ps1_out_alu  (ps1_out_alu),
    .ps2_out_alu  (ps2_out_alu),
    .ps1_out_b    (ps1_out_b),
    .ps2_out_b    (ps2_out_b),
    .ps1_out_mem  (ps1_out_mem),
    .ps2_out_mem  (ps2_out_mem)
  );

  // Clock -----------------------------------------------------------------
  initial clk = 0;
  always #5 clk = ~clk;  // 100 MHz

  // Test sequence ---------------------------------------------------------
  initial begin
    $dumpfile("fu_alu_prf.vcd");
    $dumpvars(0, fu_alu_prf_tb);

    // Default values
    issued         = 0;
    data_in        = '0;
    ps1_data       = '0;
    ps2_data       = '0;
    curr_rob_tag   = '0;
    mispredict     = 0;
    mispredict_tag = '0;

    read_en_alu    = 1'b0;
    read_en_b      = 1'b0;
    read_en_mem    = 1'b0;
    ps1_in_alu     = '0;
    ps2_in_alu     = '0;
    ps1_in_b       = '0;
    ps2_in_b       = '0;
    ps1_in_mem     = '0;
    ps2_in_mem     = '0;

    // Reset
    reset = 1'b1;
    repeat (3) @(posedge clk);
    reset = 1'b0;
    @(posedge clk);

    // We will always be "reading" TEST_PD from the PRF
    read_en_alu = 1'b1;
    ps1_in_alu  = TEST_PD;

    // --- ISSUE 1 ADDI OP ----------------------------------------
    // ps1 = 10, imm = 5 → expected = 15
    @(negedge clk);
    curr_rob_tag        = TEST_ROB + 1;
    mispredict          = 1'b0;
    mispredict_tag      = '0;

    data_in             = '0;
    data_in.valid       = 1'b1;
    data_in.Opcode      = OPCODE_OPIMM;
    data_in.func3       = 3'b000;       // ADDI
    data_in.func7       = 7'b0000000;
    data_in.imm         = 32'd5;
    data_in.pd          = TEST_PD;
    data_in.rob_index   = TEST_ROB;
    data_in.fu          = 2'd1;        // ALU

    ps1_data            = 32'd10;
    ps2_data            = 32'd0;

    issued = 1'b1;

    // First posedge: ALU computes result and asserts done,
    // BUT PRF hasn't seen write_alu_en yet (still old value)
    @(posedge clk);
    #1;
    $display("[%0t] After ISSUE edge:", $time);
    $display("  ALU done=%0b, result=0x%08h", alu_out.fu_alu_done, alu_out.data);
    $display("  PRF read(ps1_out_alu) BEFORE write = 0x%08h", ps1_out_alu);

    if (alu_out.fu_alu_done !== 1'b1 || alu_out.data !== 32'd15)
      $error("ALU did not produce expected 1-cycle result (expected 15).");

    // Drop issue so we don't start a new op
    @(negedge clk);
    issued   = 1'b0;
    data_in  = '0;
    ps1_data = '0;
    ps2_data = '0;

    // Second posedge: PRF sees write_alu_en=1 and updates prf[TEST_PD]
    @(posedge clk);
    #1;
    $display("[%0t] One cycle later:", $time);
    $display("  ALU done=%0b (may have dropped to 0; PRF already wrote this edge)", alu_out.fu_alu_done);
    $display("  PRF read(ps1_out_alu) AFTER write = 0x%08h", ps1_out_alu);

    if (ps1_out_alu !== 32'd15)
      $error("PRF did not get updated value one cycle after ALU.");
    else
      $display("[%0t] PASS: PRF sees updated value exactly one cycle after ALU executes.", $time);

    // Third posedge: done drops back to 0 (depending on your FU logic)
    @(posedge clk);
    #1;
    $display("[%0t] Later cycle: done=%0b, PRF value still = 0x%08h",
             $time, alu_out.fu_alu_done, ps1_out_alu);

    $display("[%0t] Test completed.", $time);
    $finish;
  end

  // Optional monitor
  initial begin
    $monitor("[%0t] issued=%0b done=%0b write_alu_en=%0b ps1_out_alu=0x%08h",
             $time, issued, alu_out.fu_alu_done, write_alu_en, ps1_out_alu);
  end

endmodule
