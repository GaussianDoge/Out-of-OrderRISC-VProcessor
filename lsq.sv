`timescale 1ns / 1ps
import types_pkg::*;

module lsq(
    input logic clk,
    input logic reset,

    // From RS_mem dispatch buffer (insert S-type in orders)
    input logic [4:0] dispatch_rob_tag,
    input logic dispatch_valid,
    
    // From FU_mem
    input logic [31:0] ps1_data,
    input logic [31:0] imm_in,
    
    // From PRF 
    input logic [31:0] ps2_data,
    
    // From RS
    input logic issued,
    input rs_data data_in, 
    
    // From ROB
    input logic retired,
    input logic [4:0] rob_head,
    output logic store_wb,

    output lsq data_out,

    // To do: data forwarding for load instructions
    output logic [31:0] load_forward_data,
    output logic load_forward_valid,
    output logic load_mem,
    output logic [4:0] store_rob_tag,
    output logic full
);
    lsq lsq_arr[0:7];
    logic [2:0] w_ptr; // write pointer points to the next free entry
    logic [2:0] r_ptr; // read/retire pointer points to the oldest valid entry
    logic [3:0] ctr; // counter for number of entries in LSQ

    logic [31:0] addr;
    assign addr = ps1_data + imm_in;
    
    assign full = (ctr == 8);

    // rs_data stall_load_data;
    // logic no_stall_load;
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            ctr <= '0;
            w_ptr <= '0;
            r_ptr <= '0;
            store_wb <= 1'b0;
            data_out <= '0;
            // load_forward_data <= '0;
            for (int i = 0; i <= 7; i++) begin
                lsq_arr[i] <= '0;
            end
        end else begin
            store_wb <= 1'b0;
            data_out <= '0;

            // Reserve position for load and store in LSQ in order (from dispatch buffer)
            if (dispatch_valid && !full) begin
                lsq_arr[w_ptr].valid <= 1'b1;
                lsq_arr[w_ptr].addr <= '0;
                lsq_arr[w_ptr].pc <= '0;
                lsq_arr[w_ptr].rob_tag <= dispatch_rob_tag;
                lsq_arr[w_ptr].ps2_data <= '0;
                lsq_arr[w_ptr].pd <= '0;
                lsq_arr[w_ptr].sw_sh_signal <= '0;
                lsq_arr[w_ptr].valid_data <= 1'b0;

                // update circular buffer pointers and counter
                ctr <= ctr + 1;
                w_ptr <= (w_ptr == 7) ? 0 : w_ptr + 1;
            end

            if (issued) begin
                // Update store data in LSQ
                for (int i = 0; i <= 7; i++) begin
                    if (lsq_arr[i].valid 
                    && !lsq_arr[i].valid_data 
                    && lsq_arr[i].rob_tag == data_in.rob_index) begin
                        lsq_arr[i].addr <= ps1_data + imm_in;
                        lsq_arr[i].pc <= data_in.pc;
                        lsq_arr[i].ps2_data <= ps2_data;
                        lsq_arr[i].valid_data <= 1'b1;
                        lsq_arr[i].pd <= data_in.pd;

                        if (data_in.Opcode == 7'b0100011) begin // store
                            lsq_arr[i].store <= 1'b1;
                            if (data_in.func3 == 3'b010) begin // sw
                                lsq_arr[i].sw_sh_signal <= 1'b0;
                            end else if (data_in.func3 == 3'b001) begin // sh
                                lsq_arr[i].sw_sh_signal <= 1'b1;
                            end
                        end else begin // load
                            lsq_arr[i].store <= 1'b0;
                        end
                        store_rob_tag = data_in.rob_index;
                    end
                end

                

                // if (data_in.Opcode == 7'b0100011) begin
                //     lsq_arr[w_ptr].valid <= 1'b1;
                //     lsq_arr[w_ptr].addr <= ps1_data + imm_in;
                //     lsq_arr[w_ptr].rob_tag <= data_in.rob_index;
                //     lsq_arr[w_ptr].ps2_data <= ps2_data;
                //     lsq_arr[w_ptr].pd <= data_in.pd;
                //     if (data_in.func3 == 3'b010) begin // sw
                //         lsq_arr[w_ptr].sw_sh_signal <= 1'b0;
                //     end else if (data_in.func3 == 3'b001) begin // sh
                //         lsq_arr[w_ptr].sw_sh_signal <= 1'b1;
                //     end
                //     ctr <= ctr + 1;
                //     w_ptr <= (w_ptr == 7) ? 0 : w_ptr + 1;
                    
                //     store_done = 1'b1;
                //     store_ready = 1'b1;
                //     store_rob_tag = data_in.rob_index;
                // end
            end 
            if (retired) begin
                if (lsq_arr[r_ptr].valid_data && rob_head == lsq_arr[r_ptr].rob_tag && lsq_arr[r_ptr].store) begin
                    store_wb <= 1'b1;
                    data_out <= lsq_arr[r_ptr];
                    lsq_arr[r_ptr] <= '0;
                    r_ptr <= (r_ptr == 7) ? 0 : r_ptr + 1;
                    ctr <= ctr - 1;
                end else if (lsq_arr[r_ptr].valid_data && rob_head == lsq_arr[r_ptr].rob_tag && !lsq_arr[r_ptr].store) begin
                    store_wb <= 1'b0;
                    data_out <= '0;
                    lsq_arr[r_ptr] <= '0;
                    r_ptr <= (r_ptr == 7) ? 0 : r_ptr + 1;
                    ctr <= ctr - 1;
                end
            end 
        end 
    end

    always_comb begin
        // Default
        load_forward_data = '0;
        load_forward_valid = 0;
        load_mem = 1'b0;
        // Issuing Load
        if (issued && data_in.Opcode == 7'b0000011) begin
            logic [2:0] temp_ptr;
            temp_ptr = r_ptr;

            // Loop through LSQ
            for (int i = 0; i <= 7; i++) begin
                if (lsq_arr[temp_ptr].valid && lsq_arr[temp_ptr].store) begin

                    // If store is older
                    if (lsq_arr[temp_ptr].pc < data_in.pc) begin
                        // Data isn't valid yet
                        if(!lsq_arr[temp_ptr].valid_data) begin
                            load_mem = 1'b0;
                            load_forward_valid = 1'b0;
                        end else begin
                            // Logic for checking if a load is in the right range (LBU)
                            logic [31:0] store_addr = lsq_arr[temp_ptr].addr;
                            logic is_word = !lsq_arr[temp_ptr].sw_sh_signal;
                            logic [31:0] limit = is_word ? 3 : 1;
                            logic [31:0] offset;
                            if (data_in.func3 == 3'b100) begin // lbu
                                offset = 0;
                            end else if (data_in.func3 == 3'b010) begin // lw
                                offset = 3;
                            end

                            // Check if Load Address falls inside Store Range
                            if (addr >= store_addr && addr + offset <= (store_addr + limit)) begin
                                // If address overlaps
                                // SW to LW (Word to Word) - Forward
                                $display("LSQ: Load Forwarding from Store rob=%0d addr=0x%08h data=0x%08h",
                                    lsq_arr[temp_ptr].rob_tag, lsq_arr[temp_ptr].addr, lsq_arr[temp_ptr].ps2_data);
                                if (addr == store_addr && data_in.func3 == 3'b010 && is_word) begin
                                    load_forward_valid = 1'b1;
                                    load_forward_data = lsq_arr[temp_ptr].ps2_data;
                                    load_mem = 1'b0;
                                end
                                // SW/SH to LBU (Byte Extraction) - Forward as the byte is inside the store data
                                else if (data_in.func3 == 3'b100) begin 
                                    load_forward_valid = 1'b1;
                                    load_mem = 1'b0;
                                    
                                    // Calculate byte offset (0, 1, 2, or 3) and extract byte & zero extend (LBU)
                                    case (addr[1:0] - store_addr[1:0])
                                        2'b00: load_forward_data = {24'b0, lsq_arr[temp_ptr].ps2_data[7:0]};
                                        2'b01: load_forward_data = {24'b0, lsq_arr[temp_ptr].ps2_data[15:8]};
                                        2'b10: load_forward_data = {24'b0, lsq_arr[temp_ptr].ps2_data[23:16]};
                                        2'b11: load_forward_data = {24'b0, lsq_arr[temp_ptr].ps2_data[31:24]};
                                    endcase
                                end
                                else begin
                                    // Complex/Partial overlap not covered above (e.g. SH -> LW)
                                    // Must Stall
                                    load_mem = 1'b0; 
                                end
                            end else if (addr >= store_addr && addr <= (store_addr + limit)) begin // check for two incompleted overlap store
                                // Previous perfect match not found
                                // then fall into incompleted overlap case
                                load_mem = 1'b1;
                                load_forward_valid = 1'b0;
                                $display("LSQ: Load Stalled due to incompleted overlap store");
                            end
                        end
                    end
                end
                // Move to next entry in circular buffer
                temp_ptr = (temp_ptr == 7) ? 0 : temp_ptr + 1;
            end
        end
    end


// Delete it if you don't need it
//     rs_data check_load;
//     assign check_load = (no_stall_load) ? data_in : stall_load_data;

//     always_comb begin
//         if (issued || retired) begin
//             // load instructions search LSQ for matching store
//             if (check_load.Opcode == 7'b0000011) begin
//                 logic [2:0] temp_ptr;
//                 temp_ptr = r_ptr;
//                 logic [31:0] offset;
//                 if (check_load.func3 == 3'b100) begin // lbu
//                     offset = 0;
//                 end else if (check_load.func3 == 3'b010) begin // lw
//                     offset = 3;
//                 end
//                 for (logic [2:0] i = 0; i <= 7; i++) begin
//                     if (lsq_arr[i].valid) begin // take the latest value to forward
//                         // check if addr is in range of store instruction
//                         if (lsq_arr[i].pc < check_load.pc
//                         && lsq_arr[i].valid_data
//                         && !lsq_arr[i].sw_sh_signal // SW type check
//                         && lsq_arr[i].addr <= addr // addr range check
//                         && lsq_arr[i].addr+3 >= addr+offset) begin

//                             load_forward_data = lsq_arr[i].ps2_data;
//                             load_forward_valid = 1'b1;
//                             load_mem = 1'b0;

//                         end else if (lsq_arr[i].pc < check_load.pc
//                         && lsq_arr[i].valid_data
//                         && lsq_arr[i].sw_sh_signal // SH type check
//                         && lsq_arr[i].addr <= addr  // addr range check
//                         && lsq_arr[i].addr+1 >= addr+offset) begin

//                             load_forward_data = {16'b0, lsq_arr[i].ps2_data[15:0]};
//                             load_forward_valid = 1'b1;
//                             load_mem = 1'b0;
                            
//                         end else if (lsq_arr[i].pc < check_load.pc // we stall until all stores before are retired
//                         && !lsq_arr[i].valid_data) begin 
//                             load_forward_data = 32'b0;
//                             load_forward_valid = 1'b0;
//                         end
//                     end else if (lsq_arr[i].valid) begin
//                         load_forward_data = 32'b0;
//                         load_forward_valid = 1'b0;
//                     end
//                     temp_ptr = (temp_ptr == 7) ? 0 : temp_ptr + 1;
//                 end

//                 if (load_forward_valid) begin
//                     no_stall_load = 1'b1;
//                 end else begin
//                     no_stall_load = 1'b0;
//                 end
//             end
//         end
//     end
    
 endmodule
