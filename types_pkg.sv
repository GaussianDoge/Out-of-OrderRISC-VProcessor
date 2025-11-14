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
    } decode_data;
    
    typedef struct packed {
        // ALUOp will be sent directly to dispatch stage
        logic [7:0] ps1;
        logic [7:0] ps2;
        logic [7:0] pd_new;
        logic [7:0] pd_old;
        logic [32:0] imm;
        logic [4:0] rob_tag;
    } rename_data;
    
    typedef struct packed {
        logic [7:0] pd_new;
        logic [7:0] pd_old;
        logic [31:0] pc;
        logic complete;
        logic [4:0] rob_index;
        logic valid;
    } rob_data;
    
    typedef struct packed {
        logic [6:0] Opcode;
        logic [7:0] prd;
        logic [7:0] pr1;
        logic pr1_ready;
        logic [7:0] pr2;
        logic pr2_ready;
        logic [31:0] imm;
        logic [1:0] fu;
        logic [3:0] rob_index;
    }dispatch_pipeline_data;
    
    typedef struct packed {
        logic valid;
        logic [6:0] Opcode;
        logic [7:0] prd;
        logic [7:0] pr1;
        logic pr1_ready;
        logic [7:0] pr2;
        logic pr2_ready;
        logic [31:0] imm;
        logic [1:0] fu;
        logic [3:0] rob_index;
        logic [2:0] age;
    } alu_rs_data;
endpackage 
