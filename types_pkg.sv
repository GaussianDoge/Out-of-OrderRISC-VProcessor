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
        logic fu_mem;
        logic fu_alu;
        logic fu_br;
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
        logic fu_alu;
        logic fu_br;
        logic fu_mem;
        logic [2:0] func3;
        logic [6:0] func7;
    } rename_data;
    
     typedef struct packed {
        logic [6:0] Opcode;
        logic [31:0] pc;
        logic [6:0] prd;
        logic [6:0] pr1;
        logic [6:0] pr2;
        logic [31:0] imm;
        logic [4:0] rob_index;
        logic [2:0] func3;
        logic [6:0] func7;
        logic pr1_ready;
        logic pr2_ready;
    } dispatch_pipeline_data;

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
        logic [31:0] pc;
        logic [4:0] rob_index;
        logic [6:0] Opcode;
        logic [2:0] func3;
        logic [6:0] func7;
        logic [6:0] pd;
        logic [6:0] ps1;
        logic ps1_ready;
        logic [6:0] ps2;
        logic ps2_ready;
        logic [31:0] imm;
        logic [1:0] fu;
        logic [2:0] age;
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
        logic hit;
        logic [4:0] mispredict_tag;
        logic jalr_bne_signal;
        logic [31:0] pc;
        logic [31:0] data;
        logic [4:0] rob_fu_b;
    } b_data;

    typedef struct packed {
        logic valid;
        logic [31:0] pc;
        logic [4:0] rob_tag;
        logic [31:0] addr;
        logic [31:0] ps2_data;
        logic [6:0] pd;
        logic [2:0] func3;
        logic sw_sh_signal;
        logic store;
        logic valid_data;
    } lsq;

    typedef struct packed {
        logic valid;
        logic [31:0] pc;
        logic [4:0] rob_tag;
        logic [127:0] reset_reg_rdy_table;

    } checkpoint;
endpackage 
