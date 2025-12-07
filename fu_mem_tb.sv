`timescale 1ns / 1ps
import types_pkg::*;

module fu_mem_tb;

    // =========================================================
    // DUT Interface Signals
    // =========================================================
    logic clk;
    logic reset;

    // From ROB
    logic       retired;
    logic [4:0] rob_head;
    logic [4:0] curr_rob_tag;
    logic       mispredict;
    logic [4:0] mispredict_tag;

    // From RS / PRF
    logic        issued;
    rs_data      data_in;
    logic [31:0] ps1_data;
    logic [31:0] ps2_data;

    // From FU MEM
    mem_data     data_out;

    // For checking results
    logic [31:0] expected_data;

    // =========================================================
    // DUT Instance
    // =========================================================
    fu_mem dut (
        .clk            (clk),
        .reset          (reset),

        // ROB
        .retired        (retired),
        .rob_head       (rob_head),
        .curr_rob_tag   (curr_rob_tag),
        .mispredict     (mispredict),
        .mispredict_tag (mispredict_tag),

        // RS / PRF
        .issued         (issued),
        .data_in        (data_in),
        .ps1_data       (ps1_data),
        .ps2_data       (ps2_data),

        // Output
        .data_out       (data_out)
    );

    // =========================================================
    // Clock Generation
    // =========================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 10ns period
    end

    // =========================================================
    // Tasks
    // =========================================================

    // Synchronous reset
    task automatic do_reset();
    begin
        reset          = 1'b1;
        retired        = 1'b0;
        rob_head       = '0;
        curr_rob_tag   = '0;
        mispredict     = 1'b0;
        mispredict_tag = '0;
        issued         = 1'b0;
        data_in        = '0;
        ps1_data       = '0;
        ps2_data       = '0;
        expected_data  = '0;

        repeat (3) @(posedge clk);
        reset = 1'b0;
        @(posedge clk);
    end
    endtask

    // Issue a single LOAD (LW or LBU)
    task automatic issue_load(
        input  logic [2:0]  func3_in,   // 010 = LW, 100 = LBU, etc.
        input  logic [31:0] base_addr,
        input  logic [31:0] offset,
        input  logic [4:0]  rob_idx
    );
    begin
        @(posedge clk);

        // Drive RS → FU for ONE cycle only
        data_in           = '0;
        data_in.Opcode    = 7'b0000011;   // LOAD
        data_in.func3     = func3_in;
        data_in.imm       = offset;
        data_in.rob_index = rob_idx;
        data_in.pd        = 7'd5;         // arbitrary dest preg

        ps1_data          = base_addr;
        ps2_data          = 32'd0;

        curr_rob_tag      = rob_idx;      // emulate ROB tail
        mispredict        = 1'b0;

        issued            = 1'b1;
        @(posedge clk);   // 1-cycle issue pulse
        issued            = 1'b0;

        // RS lets go of this entry after issue (more realistic)
        data_in    = '0;
        ps1_data   = '0;
        ps2_data   = '0;
    end
    endtask

    // Wait for fu_mem_done (load completion), with timeout
    task automatic wait_for_fu_mem_done(
        output logic [31:0] value,
        output int          cycles
    );
        int timeout;
    begin
        timeout = 50;
        cycles  = 0;
        while (!data_out.fu_mem_done && timeout > 0) begin
            @(posedge clk);
            timeout--;
            cycles++;
        end

        if (!data_out.fu_mem_done) begin
            $error("[%0t] TIMEOUT: fu_mem_done never asserted!", $time);
        end else begin
            $display("[%0t] fu_mem_done asserted after %0d cycles", $time, cycles);
        end

        value = data_out.data;
    end
    endtask

    // Issue a single STORE WORD (SW) via S-type
    task automatic issue_store_word(
        input  logic [31:0] base_addr,
        input  logic [31:0] offset,
        input  logic [31:0] value,
        input  logic [4:0]  rob_idx
    );
    begin
        @(posedge clk);
        data_in           = '0;
        data_in.Opcode    = 7'b0100011;   // S-type (store)
        data_in.func3     = 3'b010;       // SW
        data_in.imm       = offset;
        data_in.rob_index = rob_idx;
        data_in.pd        = 7'd0;         // stores don't write dest preg

        ps1_data          = base_addr;    // base
        ps2_data          = value;        // store data

        curr_rob_tag      = rob_idx;
        mispredict        = 1'b0;

        issued            = 1'b1;
        @(posedge clk);   // issue pulse
        issued            = 1'b0;

        // RS lets go after issue
        data_in    = '0;
        ps1_data   = '0;
        ps2_data   = '0;

        // Let LSQ capture store
        @(posedge clk);

        // Now "retire" this store from ROB: commit to memory
        @(posedge clk);
        retired  = 1'b1;
        rob_head = rob_idx;
        @(posedge clk);
        retired  = 1'b0;
        rob_head = '0;

        // Extra cycle for data_memory store to settle
        @(posedge clk);
    end
    endtask

    // Issue a single STORE HALFWORD (SH)
    task automatic issue_store_half(
        input  logic [31:0] base_addr,
        input  logic [31:0] offset,
        input  logic [31:0] value,
        input  logic [4:0]  rob_idx
    );
    begin
        @(posedge clk);
        data_in           = '0;
        data_in.Opcode    = 7'b0100011;   // S-type
        data_in.func3     = 3'b001;       // SH
        data_in.imm       = offset;
        data_in.rob_index = rob_idx;
        data_in.pd        = 7'd0;

        ps1_data          = base_addr;    // base
        ps2_data          = value;        // low 16 bits used

        curr_rob_tag      = rob_idx;
        mispredict        = 1'b0;

        issued            = 1'b1;
        @(posedge clk);   // issue pulse
        issued            = 1'b0;

        // RS lets go after issue
        data_in    = '0;
        ps1_data   = '0;
        ps2_data   = '0;

        // Let LSQ capture store
        @(posedge clk);

        // Retire SH from ROB -> commit to memory
        @(posedge clk);
        retired  = 1'b1;
        rob_head = rob_idx;
        @(posedge clk);
        retired  = 1'b0;
        rob_head = '0;

        // Extra cycle for data_memory store to settle
        @(posedge clk);
    end
    endtask

    // =========================================================
    // Main Stimulus
    // =========================================================
    initial begin
        logic [31:0] load_val;
        int          cycles;

        $dumpfile("fu_mem_sw_sh_lw.vcd");
        $dumpvars(0, fu_mem_tb);

        $display("=== FU MEM + LSQ + DATA_MEMORY TESTBENCH START ===");

        // 1. Reset
        do_reset();

        // -----------------------------------------------------
        // TEST 1: SW followed by LW from same address
        // -----------------------------------------------------
        $display("\n[Test 1] SW then LW @ addr 16...");
        issue_store_word(
            32'd16,        // base addr
            32'd0,         // imm
            32'hDEAD_BEEF, // value
            5'd1           // rob index
        );

        // Now load back with LW
        issue_load(
            3'b010,        // LW
            32'd16,
            32'd0,
            5'd2
        );
        wait_for_fu_mem_done(load_val, cycles);

        expected_data = 32'hDEAD_BEEF;
        if (load_val !== expected_data) begin
            $error("FAIL: SW/LW mismatch: got 0x%08h, expected 0x%08h",
                   load_val, expected_data);
        end else begin
            $display("PASS: SW/LW: got 0x%08h as expected", load_val);
        end

        // -----------------------------------------------------
        // TEST 2: SH followed by LW from same address
        // -----------------------------------------------------
        $display("\n[Test 2] SH then LW @ addr 32...");
        issue_store_half(
            32'd32,        // base addr
            32'd0,         // imm
            32'h0000_BEEF, // low 16 bits written
            5'd3
        );

        issue_load(
            3'b010,        // LW
            32'd32,
            32'd0,
            5'd4
        );
        wait_for_fu_mem_done(load_val, cycles);

        expected_data = 32'h0000_BEEF;  // upper 16 bits should remain 0
        if (load_val !== expected_data) begin
            $error("FAIL: SH/LW mismatch: got 0x%08h, expected 0x%08h",
                   load_val, expected_data);
        end else begin
            $display("PASS: SH/LW: got 0x%08h as expected", load_val);
        end

        // -----------------------------------------------------
        // TEST 3: LBU after SW (byte load)
        // -----------------------------------------------------
        $display("\n[Test 3] SW then LBU @ addr 40 (check lowest byte)...");
        issue_store_word(
            32'd40,
            32'd0,
            32'h1122_33AA,  // LSByte = 0xAA at addr 40
            5'd5
        );

        issue_load(
            3'b100,        // LBU
            32'd40,
            32'd0,
            5'd6
        );
        wait_for_fu_mem_done(load_val, cycles);

        expected_data = 32'h0000_00AA;
        if (load_val !== expected_data) begin
            $error("FAIL: SW/LBU mismatch: got 0x%08h, expected 0x%08h",
                   load_val, expected_data);
        end else begin
            $display("PASS: SW/LBU: got 0x%08h as expected", load_val);
        end

        $display("\n=== FU MEM TESTS COMPLETE ===");
        #50;
        $finish;
    end

    // =========================================================
    // Monitor (for debug)
    // =========================================================
    initial begin
        $monitor("[%0t] issued=%0b retired=%0b rob_head=%0d Opcode=0x%02h func3=0x%0h fu_mem_ready=%0b fu_mem_done=%0b addr_from_ps1+imm=0x%08h data_out=0x%08h",
                 $time,
                 issued,
                 retired,
                 rob_head,
                 data_in.Opcode,
                 data_in.func3,
                 data_out.fu_mem_ready,
                 data_out.fu_mem_done,
                 ps1_data + data_in.imm,
                 data_out.data);
    end

endmodule
