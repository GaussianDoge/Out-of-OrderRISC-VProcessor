`timescale 1ns / 1ps
import types_pkg::*;

module lsq(
    input logic clk,
    input logic reset,

    // From RS_mem dispatch buffer (insert S-type in orders)
    input logic [4:0] dispatch_rob_tag,
    input logic dispatch_valid,
    input logic [31:0] dispatch_pc,
    
    // From FU_mem
    input logic [31:0] ps1_data,
    input logic [31:0] imm_in,
    input logic mispredict,
    input logic [4:0] mispredict_tag,
    input logic [4:0] curr_rob_tag,
    input logic [31:0] mispredict_pc,
    
    // From PRF 
    input logic [31:0] ps2_data,
    
    // From RS
    input logic issued,
    input rs_data data_in, 
    
    // From ROB
    input logic retired,
    input logic [4:0] rob_head,
    output logic store_wb,

    // Writebacked data
    output lsq data_out,
    

    // forwarding
    output logic [31:0] load_forward_data,
    output logic [6:0] forward_load_pd,
    output logic [4:0] forward_rob_index,

    // loading from memory
    output lsq data_load,
    output logic load_forward_valid,
    output logic load_mem,

    // Retirement
    output logic [4:0] store_rob_tag, // for lsq writeback
    output logic store_lsq_done,
    output logic tag_full
);
    lsq lsq_arr[0:7];
    logic [2:0] w_ptr; // write pointer points to the next free entry
    logic [2:0] r_ptr; // read/retire pointer points to the oldest valid entry
    logic [3:0] ctr; // counter for number of entries in LSQ
    logic [2:0] new_w_ptr;

    logic [31:0] addr;
    assign addr = ps1_data + imm_in;
    
    // assign full = (ctr == 7);
    assign tag_full = (lsq_arr[0].valid)
                    && (lsq_arr[1].valid)
                    && (lsq_arr[2].valid)
                    && (lsq_arr[3].valid)
                    && (lsq_arr[4].valid)
                    && (lsq_arr[5].valid)
                    && (lsq_arr[6].valid)
                    && (lsq_arr[7].valid);

    logic incompleted_load;
    logic unissued_store;
    logic lsq_issued;

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
            if (mispredict) begin
                // automatic logic [4:0] ptr = (mispredict_tag == 15) ? 0 : mispredict_tag + 1;
                // automatic logic [3:0] new_ctr = '0;

                // for (logic [4:0] i = ptr; i != curr_rob_tag; i=(i==15)?0:i+1) begin
                //     for (logic [4:0] j = 0; j <= 7; j++) begin
                //         if (lsq_arr[j].valid && i == lsq_arr[j].rob_tag) begin
                //             lsq_arr[j] <= '0;
                //         end
                //     end
                // end
                
                // for (logic [4:0] i = 0; i <= 7; i++) begin
                //     if (lsq_arr[i].valid) begin
                //         new_ctr++;
                //     end
                // end
                
                // if (new_ctr == 0) begin
                //     ctr   <= 0;
                //     r_ptr <= w_ptr;
                // end else begin
                //     ctr <= new_ctr;
                // end
                logic [2:0] tmp_wptr;
                logic       stop;

                tmp_wptr = w_ptr;
                stop     = 1'b0;


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

                if (issued && data_in.pc < mispredict_pc) begin
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
                            lsq_arr[i].func3 <= data_in.func3;

                            if (data_in.Opcode == 7'b0100011) begin // store
                                lsq_arr[i].store <= 1'b1;
                                if (data_in.func3 == 3'b010) begin // sw
                                    lsq_arr[i].sw_sh_signal <= 1'b0;
                                end else if (data_in.func3 == 3'b001) begin // sh
                                    lsq_arr[i].sw_sh_signal <= 1'b1;
                                end
                                store_rob_tag <= data_in.rob_index;
                                store_lsq_done <= 1'b1;
                            end else begin // load
                                lsq_arr[i].store <= 1'b0;
                            end
                            
                        end
                    end
                end 

                
                // for (int i = 1; i < 8; i++) begin
                //     if (lsq_arr[w_ptr-i].pc >= mispredict_pc) begin
                //         lsq_arr[i] <= '0;
                //         $display("Flush out PC: %8h Larger than PC: %8h", lsq_arr[w_ptr-i].pc, mispredict_pc);
                //         w_ptr <= w_ptr-i;
                //     end
                // end
                

                for (int k = 0; k < 8; k++) begin
                    logic [2:0] last;
                    last = tmp_wptr - 3'd1;   // wraps correctly when tmp_wptr==0 -> last==7

                    if (!stop) begin
                        if (lsq_arr[last].valid && (lsq_arr[last].pc >= mispredict_pc)) begin
                            // $display("Flush out PC: %8h Larger than PC: %8h",
                            //         lsq_arr[last].pc, mispredict_pc);
                            lsq_arr[last] <= '0;   // clear the entry you checked
                            tmp_wptr = last;       // move next-free back by 1
                        end else begin
                            stop = 1'b1;           // stop after first non-flushable tail entry
                        end
                    end
                end

                w_ptr <= tmp_wptr;                 // update once

                

                


            end else begin
                store_lsq_done <= 1'b0;

                // Reserve position for load and store in LSQ in order (from dispatch buffer)
                if (dispatch_valid && !tag_full) begin
                    lsq_arr[w_ptr].valid <= 1'b1;
                    lsq_arr[w_ptr].addr <= '0;
                    lsq_arr[w_ptr].pc <= dispatch_pc;
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
                            lsq_arr[i].func3 <= data_in.func3;

                            if (data_in.Opcode == 7'b0100011) begin // store
                                lsq_arr[i].store <= 1'b1;
                                if (data_in.func3 == 3'b010) begin // sw
                                    lsq_arr[i].sw_sh_signal <= 1'b0;
                                end else if (data_in.func3 == 3'b001) begin // sh
                                    lsq_arr[i].sw_sh_signal <= 1'b1;
                                end
                                store_rob_tag <= data_in.rob_index;
                                store_lsq_done <= 1'b1;
                            end else begin // load
                                lsq_arr[i].store <= 1'b0;
                            end
                            
                        end
                    end
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
    end

    assign incompleted_load = (lsq_arr[0].valid_data && !lsq_arr[0].store)
                              || (lsq_arr[1].valid_data && !lsq_arr[1].store)
                              || (lsq_arr[2].valid_data && !lsq_arr[2].store)
                              || (lsq_arr[3].valid_data && !lsq_arr[3].store)
                              || (lsq_arr[4].valid_data && !lsq_arr[4].store)
                              || (lsq_arr[5].valid_data && !lsq_arr[5].store)
                              || (lsq_arr[6].valid_data && !lsq_arr[6].store)
                              || (lsq_arr[7].valid_data && !lsq_arr[7].store);

    always_comb begin
        // Default
        if (reset) begin
            load_forward_data = '0;
            load_forward_valid = 0;
            load_mem = 1'b0;
            data_load = '0;
        end

        load_forward_data = '0;
        load_forward_valid = 0;
        load_mem = 1'b0;
        data_load = '0;
        
        unissued_store = 1'b0;
        lsq_issued = 1'b0;
        if (incompleted_load) begin
            logic [2:0] temp_ptr;
            temp_ptr = r_ptr;
            
            for (int i = 0; i <= 7; i++) begin
                if (!lsq_arr[temp_ptr].valid_data) begin
                    // any prev invalid data found, we wait
                    unissued_store = 1'b1;
                end else if (lsq_arr[temp_ptr].valid_data && !lsq_arr[temp_ptr].store) begin
                    // found incompleted load
                    unissued_store = 1'b0;
                    break;
                end
                temp_ptr = (temp_ptr == 7) ? 0 : temp_ptr + 1;
            end

            if (!unissued_store) begin // no more unissued store before
                automatic logic [31:0] pc = lsq_arr[temp_ptr].pc;
                automatic logic [31:0] addr = lsq_arr[temp_ptr].addr;
                automatic logic [4:0] rob_index = lsq_arr[temp_ptr].rob_tag;
                automatic logic [2:0] func3 = lsq_arr[temp_ptr].func3;
                forward_load_data(
                    pc,
                    addr,
                    rob_index,
                    func3,
                    load_forward_data,
                    load_forward_valid,
                    load_mem
                );

                forward_load_pd = lsq_arr[temp_ptr].pd;
                forward_rob_index = lsq_arr[temp_ptr].rob_tag;

                if (load_forward_valid || load_mem) begin
                    lsq_issued = 1'b1;
                end else begin
                    lsq_issued = 1'b0;
                end

                if (load_mem && !load_forward_valid) begin
                    data_load <= lsq_arr[temp_ptr];
                end
                
            end
        end
        // Issuing Load
        if (!lsq_issued && issued && data_in.Opcode == 7'b0000011) begin
            automatic logic [31:0] pc = data_in.pc;
            automatic logic [31:0] addr = ps1_data + imm_in;
            automatic logic [4:0] rob_index = data_in.rob_index;
            automatic logic [2:0] func3 = data_in.func3;
            forward_load_data(
                pc,
                addr,
                rob_index,
                func3,
                load_forward_data,
                load_forward_valid,
                load_mem
            );

            forward_load_pd = data_in.pd;;
            forward_rob_index = data_in.rob_index;

            if (load_mem && !load_forward_valid) begin
                data_load.valid = 1'b1;
                data_load.pc = pc;
                data_load.addr = addr;
                data_load.rob_tag = rob_index;
                data_load.pd = data_in.pd;
                data_load.func3 = func3;
                data_load.store = 1'b0;
                data_load.sw_sh_signal = 1'b0;
                data_load.valid_data = 1'b1;
            end
        end
    end
    
    logic [2:0] task_temp_ptr;
    logic [2:0] age;
    logic [2:0] target_age;
    task automatic forward_load_data(
        input logic [31:0] pc,
        input logic [31:0] addr,
        input logic [4:0] rob_index,
        input logic [2:0] func3,
        output logic [31:0] load_data,
        output logic forward_valid,
        output logic load_from_mem
    );
        begin
            logic task_unissued_store;
            logic dependent;
            logic [2:0] index;
            
            for (int i = 0; i < 8; i++) begin
                if (lsq_arr[i].rob_tag == rob_index) begin
                    if (i >= r_ptr) begin
                        age = 7 - (i - r_ptr);
                    end else begin
                        age =  7 - (8 - r_ptr + i);
                    end
                end
            end

            load_data = '0;
            dependent = 1'b0;
            forward_valid = 1'b0;
            load_from_mem = 1'b0;

            task_temp_ptr = r_ptr;
            task_unissued_store = 1'b0;
            // Loop through LSQ
            // $display("******************Load PC = %8h ROB = %0d", pc, rob_index);
            for (int i = 0; i <= 7; i++) begin
                // $display("Checking PC = %8h Rob = %0d", lsq_arr[task_temp_ptr].pc, lsq_arr[task_temp_ptr].rob_tag);
                
                if (task_temp_ptr >= r_ptr) begin
                    target_age = 7 - (task_temp_ptr - r_ptr);
                end else begin
                    target_age =  7 - (8 - r_ptr + task_temp_ptr);
                end

                if (target_age > age
                    && lsq_arr[task_temp_ptr].valid_data 
                    && lsq_arr[task_temp_ptr].store) begin
                        // Logic for checking if a load is in the right range (LBU)
                        logic [31:0] store_addr = lsq_arr[task_temp_ptr].addr;
                        logic is_word = !lsq_arr[task_temp_ptr].sw_sh_signal;
                        logic [31:0] limit = is_word ? 3 : 1;
                        logic [31:0] offset;
                        if (func3 == 3'b100) begin // lbu
                            offset = 0;
                        end else if (func3 == 3'b010) begin // lw
                            offset = 3;
                        end

                        // Check if Load Address falls inside Store Range
                        if (addr >= store_addr && addr + offset <= (store_addr + limit)) begin
                            // If address overlaps
                            // SW to LW (Word to Word) - Forward
                                // $display("LSQ: Load Forwarding from Store rob=%0d addr=0x%0d data=0x%08h To Load rob=%0d addr=0x%0d",
                                // lsq_arr[task_temp_ptr].rob_tag, lsq_arr[task_temp_ptr].addr, lsq_arr[task_temp_ptr].ps2_data, rob_index, addr);
                            if (addr == store_addr && func3 == 3'b010 && is_word) begin
                                forward_valid = 1'b1;
                                load_data = lsq_arr[task_temp_ptr].ps2_data;
                                load_from_mem = 1'b0;
                                // $display("Word to Word");
                                break;
                            end
                            // SW/SH to LBU (Byte Extraction) - Forward as the byte is inside the store data
                            else if (func3 == 3'b100) begin 
                                forward_valid = 1'b1;
                                load_from_mem = 1'b0;
                                
                                // Calculate byte offset (0, 1, 2, or 3) and extract byte & zero extend (LBU)
                                case (addr[1:0] - store_addr[1:0])
                                    2'b00: load_data = {24'b0, lsq_arr[task_temp_ptr].ps2_data[7:0]};
                                    2'b01: load_data = {24'b0, lsq_arr[task_temp_ptr].ps2_data[15:8]};
                                    2'b10: load_data = {24'b0, lsq_arr[task_temp_ptr].ps2_data[23:16]};
                                    2'b11: load_data = {24'b0, lsq_arr[task_temp_ptr].ps2_data[31:24]};
                                endcase
                                // $display("Byte Extraction");
                                break;
                            end
                        end else if ((addr >= store_addr && addr <= (store_addr + limit)) 
                                    ||(addr <= store_addr && addr + offset <= (store_addr + limit))) begin
                            load_from_mem = 1'b0;
                            forward_valid = 1'b0;
                            load_data = '0;
                            dependent = 1'b1;
                            // $display("Dependency detected!");
                            break;
                        end else begin
                            // $display("***********************************");
                            // $display("Addr: %0d  Store: %d, Limit: %0d", addr, store_addr, limit);
                        end
                end else if (target_age > age && !lsq_arr[task_temp_ptr].valid_data ) begin // unissued pre instructions
                    load_from_mem = 1'b0;
                    forward_valid = 1'b0;
                    task_unissued_store = 1'b1;
                    // $display("LSQ: Load Stalled load Rob=%0d due to Rob=%0d", rob_index, lsq_arr[task_temp_ptr].rob_tag);
                    break;
                end else if (target_age <= age) begin
                    load_from_mem = 1'b0;
                    forward_valid = 1'b0;
                    dependent = 1'b0;
                    // $display("No dependency");
                    break;
                end

                // Move to next entry in circular buffer
                task_temp_ptr = (task_temp_ptr == 7) ? 0 : task_temp_ptr + 1;
            end

            if (task_unissued_store) begin
                load_from_mem = 1'b0;
                forward_valid = 1'b0;
                load_data = '0;
            end else if (!forward_valid && !task_unissued_store && !dependent) begin // need to load from memory
                load_from_mem = 1'b1;
                load_data = '0;
                // $display("Loading from memory Rob=%0d", rob_index);
            end
        end
    endtask
 endmodule
