package types_pkg;
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instr;
        logic [31:0] pc_4;
    } fetch_data;
    
    typedef struct packed {
        logic [31:0] pc;
        logic [4:0] rs1, rs2, rd;
        logic [31:0] imm;
        logic [2:0] ALUOp;
        logic [6:0] Opcode;
        logic [1:0] fu;
        logic [2:0] func3;
        logic [6:0] func7;
    } decode_data;
    
    typedef struct packed {
        // ALUOp will be sent directly to dispatch stage
        logic [31:0] pc;
        logic [6:0] ps1;
        logic [6:0] ps2;
        logic [6:0] pd_new;
        logic [6:0] pd_old;
        logic [32:0] imm;
        logic [4:0] rob_tag;
        logic [2:0] ALUOp;
        logic [6:0] Opcode;
        logic [1:0] fu;
        logic [2:0] func3;
        logic [6:0] func7;
    } rename_data;
    
    typedef struct packed {
        logic [6:0] pd_new;
        logic [6:0] pd_old;
        logic [31:0] pc;
        logic complete;
        logic [4:0] rob_index;
        logic valid;
    } rob_data;
    
    typedef struct packed {
        logic valid;
        logic [6:0] Opcode;
        logic [2:0] func3;
        logic [6:0] func7;
        logic [6:0] pd;
        logic [6:0] ps1;
        logic ps1_ready;
        logic [6:0] ps2;
        logic ps2_ready;
        logic [31:0] imm;
        logic [4:0] rob_index;
        logic [1:0] fu;
        logic ready;
        logic [31:0] pc;
    } rs_data;
    
    typedef struct packed {
        logic [6:0] p_alu;
        logic fu_alu_done;
        logic fu_alu_ready;
        logic [4:0] rob_fu_alu;
        logic [31:0] data;
    } alu_data;
    
    typedef struct packed {
        logic [6:0] p_mem;
        logic fu_mem_done;
        logic fu_mem_ready;
        logic [4:0] rob_fu_mem;
        logic [31:0] data;
    } mem_data;
    
    typedef struct packed {
        logic [6:0] p_b;
        logic fu_b_done;
        logic fu_b_ready;
        logic mispredict;
        logic [4:0] mispredict_tag;
        logic jalr_bne_signal;
        logic [31:0] pc;
        logic [31:0] data;
        logic [4:0] rob_fu_b;
    } b_data;
    
    typedef struct packed {
        logic valid;
        logic [31:0] addr;
        logic [6:0] rob_tag;
        logic [31:0] ps2_data;
        logic [6:0] pd;
        logic sw_sh_signal;
    } lsq;
endpackage 
