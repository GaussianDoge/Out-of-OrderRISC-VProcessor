`timescale 1ns/1ps
import types_pkg::*;

module phase1_tb;
  localparam CLK_PERIOD = 10;
  logic clk = 0, reset = 1;

  logic [31:0] pc_in;
  decode_data  data_out;

  frontend dut (
    .clk     (clk),
    .reset   (reset),
    .pc_in   (pc_in),
    .data_out(data_out)
  );

  // clock
  always #(CLK_PERIOD/2) clk = ~clk;

  // ---- PC increments EVERY cycle ----
  always_ff @(posedge clk) begin
    if (reset)  pc_in <= 32'h0000_0000;
    else        pc_in <= pc_in + 32'd4;
  end

  // Monitor Decode outputs (before final skid)
  initial begin
    $timeformat(-9,1," ns",6);
    forever begin
      @(posedge clk);
      if (!reset && dut.decode_valid_out) begin
        $display("[%t] Decode valid", $realtime);
        $display("   pc=%h rs1=%0d rs2=%0d rd=%0d imm=%h ALUOp=%0h opcode=%07b mem=%0b alu=%0b",
          dut.decode_data_out.pc,
          dut.decode_data_out.rs1,
          dut.decode_data_out.rs2,
          dut.decode_data_out.rd,
          dut.decode_data_out.imm,
          dut.decode_data_out.ALUOp,
          dut.decode_data_out.Opcode,
          dut.decode_data_out.fu_mem,
          dut.decode_data_out.fu_alu);
      end
    end
  end

  // Brief downstream backpressure to exercise skids (optional)
  task automatic stall_downstream(int cycles_low = 3, int delay = 12);
    force dut.decode_buffer.ready_out = 1'b1;
    repeat (delay) @(posedge clk);
    force dut.decode_buffer.ready_out = 1'b0;
    repeat (cycles_low) @(posedge clk);
    force dut.decode_buffer.ready_out = 1'b1;
  endtask

  initial begin
    $dumpfile("phase1_tb.vcd");
    $dumpvars(0, phase1_tb);

    // Hold reset, then run. ICache loads program.mem automatically.
    repeat (5) @(posedge clk);
    reset = 1'b0;

    fork
      stall_downstream(3, 12); // optional; remove if not needed
    join_none

    // Run long enough to traverse several instructions
    repeat (60) @(posedge clk);
    $finish;
  end
endmodule
