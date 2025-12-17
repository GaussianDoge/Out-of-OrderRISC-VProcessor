`timescale 1ns/1ps

module fifo_tb_circular;
  // ---------- DUT params / types ----------
  typedef logic [31:0] T_t;
  localparam int DEPTH = 8;

  // ---------- DUT I/O ----------
  logic clk, reset;
  logic write_en, read_en;
  T_t  write_data, read_data;
  logic full, empty;

  // ---------- DUT ----------
  fifo #(.T(T_t), .DEPTH(DEPTH)) dut (
    .clk, .reset,
    .write_en, .write_data,
    .read_en,  .read_data,
    .full, .empty
  );

  // ---------- Clock & Reset ----------
  initial clk = 0;
  always #5 clk = ~clk; // 100 MHz

  task automatic do_reset();
    begin
      reset = 1;
      write_en = 0; read_en = 0; write_data = '0;
      repeat (3) @(posedge clk);
      reset = 0;
      @(posedge clk);
    end
  endtask

  // ---------- Scoreboard (models drop-oldest on full) ----------
  T_t model_q[$];

  task automatic push(input T_t d);
    begin : t_push
      assert(!full) else $fatal(1, "TB push() called while FULL");
      write_data = d; write_en = 1; read_en = 0;
      @(posedge clk);
      write_en = 0;
      model_q.push_back(d);
    end
  endtask

  // Intentionally push while FULL (no read) -> DUT drops oldest then writes new
  task automatic push_overwrite(input T_t d);
    begin : t_push_ov
      assert(full && !read_en) else $fatal(1, "push_overwrite requires FULL and no read");
      write_data = d; write_en = 1; read_en = 0;
      // Model: drop oldest, then append
      if (model_q.size() > 0) void'(model_q.pop_front());
      model_q.push_back(d);
      @(posedge clk);
      write_en = 0;
    end
  endtask

  task automatic pop();
    T_t got; T_t exp;
    begin : t_pop
      assert(!empty) else $fatal(1, "TB pop() called while EMPTY");
      write_en = 0; read_en = 1;
      @(posedge clk);
      read_en = 0;
      got = read_data;
      if (model_q.size() == 0) $fatal(1, "Model underflow");
      exp = model_q.pop_front();
      if (got !== exp) begin
        $error("POP MISMATCH: exp=0x%08x got=0x%08x @%0t", exp, got, $time);
        $fatal(2);
      end
    end
  endtask

  task automatic push_pop(input T_t d);
    T_t got; T_t exp;
    begin : t_push_pop
      if (!full && !empty) begin
        write_data = d; write_en = 1; read_en = 1;
        @(posedge clk);
        write_en = 0; read_en = 0;

        // Model: enqueue then dequeue
        model_q.push_back(d);
        got = read_data;
        exp = model_q.pop_front();
        if (got !== exp) begin
          $error("RW MISMATCH: exp=0x%08x got=0x%08x @%0t", exp, got, $time);
          $fatal(2);
        end
      end
      else if (!full)  push(d);
      else if (!empty) pop();
    end
  endtask

  // ---------- Assertions (use $past to look at flags BEFORE the edge) ----------
  bit allow_overwrite = 0;

  // No read when it was empty in the previous cycle (unless also writing)
  property no_tb_underflow_attempt;
    @(posedge clk) disable iff (reset)
      !( read_en && $past(empty) && !$past(write_en) );
  endproperty
  assert property(no_tb_underflow_attempt)
    else $fatal(3, "TB underflow attempt");

  // No write when it was full in the previous cycle (unless also reading).
  // Gate with $past(allow_overwrite) so our intentional overwrites don't trip.
  property no_tb_overflow_attempt;
    @(posedge clk) disable iff (reset)
      !( write_en && $past(full) && !$past(read_en) && !$past(allow_overwrite) );
  endproperty
  assert property(no_tb_overflow_attempt)
    else $fatal(3, "TB overflow attempt");

  // ---------- Simple coverage ----------
  covergroup cg @(posedge clk);
    coverpoint full;
    coverpoint empty;
  endgroup
  cg cov = new;

  // ---------- Test Sequence ----------
    int n = 0;
  initial begin
    $display("[%0t] Start", $time);
    do_reset();

    // 1) Fill to FULL
    while (!full) begin
      push(T_t'(32'h1111_0000 + n));
      n++;
    end
    $display("[%0t] Reached FULL with %0d items", $time, n);

    // 2) Intentional overwrite-on-full a few times (drop-oldest semantics)
    allow_overwrite = 1;
    @(posedge clk); // make allow_overwrite visible to $past(...)
    for (int k = 0; k < 3; k++) begin
      assert(full) else $fatal(1, "Expected FULL before overwrite");
      push_overwrite(T_t'(32'hAAAA_0000 + k));
      assert(full) else $fatal(1, "Should remain FULL after overwrite");
    end
    allow_overwrite = 0;

    // 3) Drain all and check order
    while (!empty) pop();
    $display("[%0t] Drained EMPTY", $time);

    // 4) Wrap-around with mixed push/pop
    for (int i = 0; i < DEPTH/2; i++) push(T_t'($urandom()));
    for (int j = 0; j < DEPTH*3; j++) push_pop(T_t'($urandom()));
    while (!empty) pop();

    // 5) Randomized legal ops
    repeat (200) begin
      @(negedge clk);
      unique case ($urandom_range(0,2))
        0: if (!full)  push(T_t'($urandom()));
        1: if (!empty) pop();
        2: if (!full && !empty) push_pop(T_t'($urandom()));
      endcase
    end
    while (!empty) pop();

    if (model_q.size() != 0) begin
      $error("Model queue not empty at end: size=%0d", model_q.size());
      $fatal(4);
    end

    $display("[%0t] TEST PASSED ✅", $time);
    $finish;
  end

endmodule
