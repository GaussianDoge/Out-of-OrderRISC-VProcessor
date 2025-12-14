`timescale 1ns / 1ps
import types_pkg::*;

module lsq_mispredict_tb;

    // Clock / reset
    logic clk;
    logic reset;

    // LSQ inputs
    logic [4:0] dispatch_rob_tag;
    logic       dispatch_valid;

    logic [31:0] ps1_data;
    logic [31:0] imm_in;
    logic        mispredict;
    logic [4:0]  mispredict_tag;
    logic [4:0]  curr_rob_tag;

    logic [31:0] ps2_data;
    logic        issued;
    rs_data      data_in;

    logic        retired;
    logic [4:0]  rob_head;

    // LSQ outputs
    logic        store_wb;
    lsq          data_out;
    logic [31:0] load_forward_data;
    logic        load_forward_valid;
    logic        load_mem;
    logic [4:0]  store_rob_tag;
    logic        full;

    // DUT
    lsq dut (
        .clk(clk),
        .reset(reset),

        .dispatch_rob_tag(dispatch_rob_tag),
        .dispatch_valid(dispatch_valid),

        .ps1_data(ps1_data),
        .imm_in(imm_in),
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        .curr_rob_tag(curr_rob_tag),

        .ps2_data(ps2_data),

        .issued(issued),
        .data_in(data_in),

        .retired(retired),
        .rob_head(rob_head),
        .store_wb(store_wb),

        .data_out(data_out),

        .load_forward_data(load_forward_data),
        .load_forward_valid(load_forward_valid),
        .load_mem(load_mem),
        .store_rob_tag(store_rob_tag),
        .full(full)
    );

    // Clock gen
    initial begin
        clk = 0;
        forever #5 clk = ~clk;   // 100 MHz
    end

    // ------------- Helpers -------------

    task automatic tb_reset;
        begin
            reset            = 1;
            dispatch_valid   = 0;
            dispatch_rob_tag = '0;
            ps1_data         = '0;
            imm_in           = '0;
            mispredict       = 0;
            mispredict_tag   = '0;
            curr_rob_tag     = '0;
            ps2_data         = '0;
            issued           = 0;
            data_in          = '0;
            retired          = 0;
            rob_head         = '0;
            @(posedge clk);
            @(posedge clk);
            reset = 0;
            @(posedge clk);
        end
    endtask

    // Reserve LSQ entry (from dispatch buffer)
    task automatic reserve_entry(input [4:0] rob_tag);
        begin
            dispatch_rob_tag = rob_tag;
            dispatch_valid   = 1'b1;
            @(posedge clk);
            dispatch_valid   = 1'b0;
            @(posedge clk);
        end
    endtask

    // Fill LSQ entry as a STORE (SW)
    task automatic issue_store(
        input [4:0]  rob_tag,
        input [31:0] pc,
        input [31:0] base,
        input [31:0] imm,
        input [31:0] data
    );
        rs_data d;
        begin
            d              = '0;
            d.rob_index    = rob_tag;
            d.Opcode       = 7'b0100011; // store
            d.func3        = 3'b010;     // sw
            d.pc           = pc;
            d.pd           = 7'd5;

            data_in        = d;
            issued         = 1'b1;
            ps1_data       = base;
            imm_in         = imm;
            ps2_data       = data;

            @(posedge clk);
            issued         = 1'b0;
            data_in        = '0;
            ps1_data       = '0;
            imm_in         = '0;
            ps2_data       = '0;
            @(posedge clk);
        end
    endtask

    // Fill LSQ entry as a LOAD (LW)
    task automatic issue_load(
        input [4:0]  rob_tag,
        input [31:0] pc,
        input [31:0] base,
        input [31:0] imm
    );
        rs_data d;
        begin
            d              = '0;
            d.rob_index    = rob_tag;
            d.Opcode       = 7'b0000011; // load
            d.func3        = 3'b010;     // lw
            d.pc           = pc;
            d.pd           = 7'd6;

            data_in        = d;
            issued         = 1'b1;
            ps1_data       = base;
            imm_in         = imm;
            ps2_data       = 32'hDEAD_BEEF; // not used for loads

            @(posedge clk);
            issued         = 1'b0;
            data_in        = '0;
            ps1_data       = '0;
            imm_in         = '0;
            ps2_data       = '0;
            @(posedge clk);
        end
    endtask

    // Dump LSQ internal state
    task automatic dump_lsq(input string tag);
        begin
            $display("====================================================");
            $display("LSQ STATE: %s  @ time %0t", tag, $time);
            $display("ctr = %0d, w_ptr = %0d, r_ptr = %0d",
                dut.ctr, dut.w_ptr, dut.r_ptr);
            for (int i = 0; i < 8; i++) begin
                lsq e = dut.lsq_arr[i];
                $display("entry[%0d]: valid=%0d store=%0d rob_tag=%0d pc=0x%08h addr=0x%08h data=0x%08h valid_data=%0d",
                    i, e.valid, e.store, e.rob_tag, e.pc, e.addr, e.ps2_data, e.valid_data);
            end
            $display("====================================================");
        end
    endtask

    // Trigger mispredict with given range
    task automatic trigger_mispredict(
        input [4:0] mp_tag,
        input [4:0] curr_tag,
        input string label
    );
        begin
            $display("=== Triggering mispredict (%s) ===", label);
            mispredict     = 1'b1;
            mispredict_tag = mp_tag;
            curr_rob_tag   = curr_tag;
            @(posedge clk);
            @(posedge clk);
            mispredict     = 1'b0;
            mispredict_tag = '0;
            curr_rob_tag   = '0;
            @(posedge clk);
        end
    endtask

    // ------------- SCENARIOS -------------

    // Case A: All entries flushed (oldest included)
    task automatic case_all_flushed;
        begin
            $display("\n\n==== CASE A: Flush all LSQ entries (oldest included) ====");
            tb_reset();

            // Create three entries: rob 2, 3, 4
            reserve_entry(5'd2);
            reserve_entry(5'd3);
            reserve_entry(5'd4);

            // Give them some PCs/addrs as loads or stores (doesn't matter much for flush)
            issue_load (5'd2, 32'h0000_1000, 32'h0000_2000, 32'd0);
            issue_store(5'd3, 32'h0000_1004, 32'h0000_2004, 32'd4, 32'hAAAA_BBBB);
            issue_store(5'd4, 32'h0000_1008, 32'h0000_2008, 32'd8, 32'hCCCC_DDDD);

            dump_lsq("Before mispredict (CASE A)");

            // Branch at rob_tag=1 mispredicts, recover to curr_rob_tag=5
            // Range i = 2,3,4 → all LSQ entries should be killed
            trigger_mispredict(5'd1, 5'd5, "CASE A");

            dump_lsq("After mispredict (CASE A)");

            // Optionally insert a new store after recovery to see reuse
            reserve_entry(5'd6);
            issue_store(5'd6, 32'h0000_2000, 32'h0000_3000, 32'd0, 32'h1234_5678);

            dump_lsq("After recovery + new store (CASE A)");
        end
    endtask

    // Case B: Wrap-around in ROB tag space (mispredict 14 → curr 3)
    task automatic case_wraparound;
        begin
            $display("\n\n==== CASE B: Wrap-around in ROB tag space ====");
            tb_reset();

            // Layout: older rob 10, then 15, 0, 1, 2
            reserve_entry(5'd10); // oldest, should survive
            reserve_entry(5'd15);
            reserve_entry(5'd0);
            reserve_entry(5'd1);
            reserve_entry(5'd2);

            issue_store(5'd10, 32'h0000_2000, 32'h0000_3000, 32'd0, 32'h1111_1111);
            issue_store(5'd15, 32'h0000_2004, 32'h0000_3004, 32'd4, 32'h2222_2222);
            issue_store(5'd0,  32'h0000_2008, 32'h0000_3008, 32'd8, 32'h3333_3333);
            issue_store(5'd1,  32'h0000_200C, 32'h0000_300C, 32'd12,32'h4444_4444);
            issue_store(5'd2,  32'h0000_2010, 32'h0000_3010, 32'd16,32'h5555_5555);

            dump_lsq("Before mispredict (CASE B)");

            // Branch at rob_tag=14 mispredicts, resume from curr=3
            // ROB range: i = 15,0,1,2 → we expect those tags to be flushed
            trigger_mispredict(5'd14, 5'd3, "CASE B");

            dump_lsq("After mispredict (CASE B)");

            // Insert a new store to see that LSQ still behaves with remaining older entry
            reserve_entry(5'd6);
            issue_store(5'd6, 32'h0000_3000, 32'h0000_4000, 32'd0, 32'h7777_7777);

            dump_lsq("After recovery + new store (CASE B)");
        end
    endtask

    // Case C: Mixed load + store, then mispredict that kills younger ones
    task automatic case_mixed_load_store;
        begin
            $display("\n\n==== CASE C: Mixed load/store + mispredict ====");
            tb_reset();

            // Older store (rob=1), younger load (rob=3), and another younger store (rob=4)
            reserve_entry(5'd1);
            reserve_entry(5'd3);
            reserve_entry(5'd4);

            // Store at addr 0x4000
            issue_store(5'd1, 32'h0000_0100, 32'h0000_4000, 32'd0, 32'hDEAD_BEEF);

            // Load from same addr (younger)
            issue_load(5'd3, 32'h0000_0104, 32'h0000_4000, 32'd0);

            // Another younger store at a different addr
            issue_store(5'd4, 32'h0000_0108, 32'h0000_5000, 32'd0, 32'hABCD_1234);

            dump_lsq("Before mispredict (CASE C)");

            // If you want, you can also check forwarding signals here by
            // issuing a fresh load with same addr and observing
            // load_forward_valid / load_forward_data.

            // Branch at rob_tag=1 mispredicts, resume from curr=5
            // Range: i = 2,3,4 → should flush entries with rob 3 and 4, keep rob 1
            trigger_mispredict(5'd1, 5'd5, "CASE C");

            dump_lsq("After mispredict (CASE C)");

            // Insert a new load that should still see only the old store (rob=1)
            reserve_entry(5'd6);
            issue_load(5'd6, 32'h0000_0200, 32'h0000_4000, 32'd0);

            dump_lsq("After recovery + new load (CASE C)");
        end
    endtask


    // ------------- MAIN -------------
    initial begin
        $display("=== Starting LSQ advanced mispredict tests ===");
        case_all_flushed();
        case_wraparound();
        case_mixed_load_store();
        $display("=== LSQ advanced mispredict tests COMPLETE ===");
        $finish;
    end

endmodule
