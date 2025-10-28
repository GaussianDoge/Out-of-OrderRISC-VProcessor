`timescale 1ns/1ps
module tb_skid_buffer_struct;

  // === Payload type for this test ===
  typedef logic [15:0] T_t;

  // === Clock & reset ===
  logic clk = 0;
  logic reset;
  always #5 clk = ~clk; // 100 MHz

  // === Upstream (source driving first skid) ===
  logic     valid_src;
  logic     ready_src;   // from skid0.ready_in
  T_t       data_src;

  // === Between skid0 -> skid1 ===
  logic     v01;  T_t d01;  logic r01;  // r01 = skid1.ready_in

  // === Between skid1 -> skid2 ===
  logic     v12;  T_t d12;  logic r12;  // r12 = skid2.ready_in

  // === Downstream (sink at end of chain) ===
  logic     vout; T_t dout; logic ready_sink;

  // === Device(s) under test: 3 skids in series ===
  skid_buffer_struct #(.T(T_t)) skid0 (
    .clk, .reset,
    .valid_in (valid_src),
    .ready_in (ready_src),
    .data_in  (data_src),

    .valid_out(v01),
    .ready_out(r01),     // ready from downstream = skid1.ready_in
    .data_out (d01)
  );

  skid_buffer_struct #(.T(T_t)) skid1 (
    .clk, .reset,
    .valid_in (v01),
    .ready_in (r01),
    .data_in  (d01),

    .valid_out(v12),
    .ready_out(r12),     // ready from downstream = skid2.ready_in
    .data_out (d12)
  );

  skid_buffer_struct #(.T(T_t)) skid2 (
    .clk, .reset,
    .valid_in (v12),
    .ready_in (r12),
    .data_in  (d12),

    .valid_out(vout),
    .ready_out(ready_sink), // final consumer's ready
    .data_out (dout)
  );


  // === Simple scoreboard: expect queue ===
  T_t expect_q[$];
  int errors = 0;
  longint produced = 0, consumed = 0;

  // Capture producer handshakes (push expected)
  always_ff @(posedge clk) if (!reset) begin
    if (valid_src && ready_src) begin
      expect_q.push_back(data_src);
      produced++;
    end
  end

  // Check consumer handshakes (pop and compare)
  always_ff @(posedge clk) if (!reset) begin
    if (vout && ready_sink) begin
      consumed++;
      if (expect_q.size() == 0) begin
        $error("Pop with empty expect_q @%0t", $time);
        errors++;
      end else begin
        T_t exp = expect_q.pop_front();
        if (dout !== exp) begin
          $error("Data mismatch @%0t: got=%h exp=%h", $time, dout, exp);
          errors++;
        end
      end
    end
  end

  // === Reset and init ===
  initial begin
    reset      = 1;
    valid_src  = 0;
    data_src   = '0;
    ready_sink = 1;
    repeat (3) @(posedge clk);
    reset = 0;
  end

  int sent;
  // === Producer: send N items with stable-on-stall behavior ===
  task automatic send_stream(input T_t start, input int N);
    T_t next = start;
    valid_src <= 1'b1;
    data_src  <= next;
    sent = 0;
    while (sent < N) begin
      @(posedge clk);
      if (ready_src) begin
        sent++;
        next++;
        data_src <= next; // advance to next value only after accept
      end else begin
        data_src <= data_src; // hold stable while stalled
      end
    end
    valid_src <= 1'b0;
  endtask


  // === Test sequences ===
  int cycles;
  int left;
  int c;
  T_t gen;
  initial begin : run
    @(negedge reset); @(posedge clk);

    // 1) Pure pass-through (no backpressure)
    $display("\n[TEST1] pass-through burst, ready_sink=1");
    ready_sink = 1;
    send_stream(16'h0000, 8);
    
    // 2) Single-cycle stall at the end
    $display("\n[TEST2] single-cycle stall at sink");
    fork
      begin
        send_stream(16'h0100, 10);
      end
      begin
        @(posedge clk);
        ready_sink = 0;  // stall one beat
        @(posedge clk);
        ready_sink = 1;
      end
    join
    
    // 3) Multi-cycle stall (fills up to 3 entries across chain)
    $display("\n[TEST3] multi-cycle stall (expect up to 3 items buffered)");
    fork
      begin
        send_stream(16'h0200, 16);
      end
      begin
        repeat (2) @(posedge clk);
        repeat (5) begin ready_sink = 0; @(posedge clk); end
        ready_sink = 1;
      end
    join

    // 4) Randomized stress (200 cycles)
    $display("\n[TEST4] random stress");
    cycles = 200;
    left   = 60; // total items to send during stress
    fork
      // Producer side: probabilistic valid
      begin
        valid_src = 0;
        gen = 16'h1000;
        for (c = 0; c < cycles; c++) begin
          // 70% chance to drive valid if items remain
          if (left > 0 && ($urandom_range(0,9) < 7)) begin
            valid_src <= 1;
            data_src  <= gen;
          end else begin
            valid_src <= 0;
          end

          @(posedge clk);
          if (valid_src && ready_src) begin
            gen++; left--;
            if (left == 0) valid_src <= 0;
          end
        end
        valid_src <= 0;
      end
      // Consumer side: random backpressure
      begin
        for (int c = 0; c < cycles; c++) begin
          ready_sink = $urandom_range(0,1);
          @(posedge clk);
        end
        ready_sink = 1;
      end
    join

    // Drain a few cycles
    repeat (10) @(posedge clk);

    // Final checks
    if (expect_q.size() != 0) begin
      $error("Items remaining in expect_q: %0d", expect_q.size());
      errors++;
    end

    $display("\nProduced=%0d, Consumed=%0d", produced, consumed);
    if (errors == 0) $display("SKID-CHAIN(3) TB: PASS ✅");
    else             $display("SKID-CHAIN(3) TB: FAIL ❌  (errors=%0d)", errors);
    $finish;
  end

endmodule
