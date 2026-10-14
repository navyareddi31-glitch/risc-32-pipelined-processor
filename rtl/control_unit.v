// -----------------------------------------------------------------------------
// control_unit.v : RV32I instruction decoder (ID stage)
//   Pure combinational: instruction word -> control signals + sign-extended
//   immediate.  Unknown / unsupported opcodes decode to a NOP (and raise
//   'illegal' for debug).  ECALL/EBREAK raise 'halt', which stops the testbench
//   when the instruction retires.  FENCE is treated as a NOP.
// -----------------------------------------------------------------------------
module control_unit (
    input  wire [31:0] instr,

    output reg         reg_write,
    output reg         mem_read,
    output reg         mem_write,
    output reg         mem_to_reg,   // 1: write-back data comes from data memory
    output reg  [1:0]  alu_src_a,    // 0: rs1   1: PC   2: zero
    output reg         alu_src_b,    // 0: rs2   1: immediate
    output reg  [3:0]  alu_op,
    output reg         is_branch,
    output reg         is_jal,
    output reg         is_jalr,
    output reg         uses_rs1,     // used by the hazard unit (avoid false stalls)
    output reg         uses_rs2,
    output reg         halt,
    output reg         illegal,
    output reg  [31:0] imm
);
    // opcodes
    localparam OP_LUI    = 7'b0110111, OP_AUIPC  = 7'b0010111,
               OP_JAL    = 7'b1101111, OP_JALR   = 7'b1100111,
               OP_BRANCH = 7'b1100011, OP_LOAD   = 7'b0000011,
               OP_STORE  = 7'b0100011, OP_IMM    = 7'b0010011,
               OP_REG    = 7'b0110011, OP_FENCE  = 7'b0001111,
               OP_SYSTEM = 7'b1110011;

    // ALU operation codes (must match alu.v)
    localparam ALU_ADD  = 4'd0, ALU_SUB = 4'd1, ALU_SLL = 4'd2, ALU_SLT = 4'd3,
               ALU_SLTU = 4'd4, ALU_XOR = 4'd5, ALU_SRL = 4'd6, ALU_SRA = 4'd7,
               ALU_OR   = 4'd8, ALU_AND = 4'd9;

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire       f7_5   = instr[30];

    // immediates
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    // ALU op for register-register / register-immediate instructions
    reg [3:0] alu_fn;
    always @(*) begin
        case (funct3)
            3'b000:  alu_fn = (opcode == OP_REG && f7_5) ? ALU_SUB : ALU_ADD;
            3'b001:  alu_fn = ALU_SLL;
            3'b010:  alu_fn = ALU_SLT;
            3'b011:  alu_fn = ALU_SLTU;
            3'b100:  alu_fn = ALU_XOR;
            3'b101:  alu_fn = f7_5 ? ALU_SRA : ALU_SRL;
            3'b110:  alu_fn = ALU_OR;
            default: alu_fn = ALU_AND;
        endcase
    end

    always @(*) begin
        // defaults = NOP
        reg_write = 1'b0;  mem_read  = 1'b0;  mem_write = 1'b0;  mem_to_reg = 1'b0;
        alu_src_a = 2'd0;  alu_src_b = 1'b0;  alu_op    = ALU_ADD;
        is_branch = 1'b0;  is_jal    = 1'b0;  is_jalr   = 1'b0;
        uses_rs1  = 1'b0;  uses_rs2  = 1'b0;  halt      = 1'b0;  illegal = 1'b0;
        imm       = imm_i;

        case (opcode)
            OP_LUI: begin
                reg_write = 1'b1; alu_src_a = 2'd2; alu_src_b = 1'b1; imm = imm_u;
            end
            OP_AUIPC: begin
                reg_write = 1'b1; alu_src_a = 2'd1; alu_src_b = 1'b1; imm = imm_u;
            end
            OP_JAL: begin
                reg_write = 1'b1; is_jal = 1'b1; imm = imm_j;
            end
            OP_JALR: begin
                reg_write = 1'b1; is_jalr = 1'b1; alu_src_b = 1'b1; uses_rs1 = 1'b1;
                imm = imm_i;
            end
            OP_BRANCH: begin
                is_branch = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1; alu_op = ALU_SUB;
                imm = imm_b;
            end
            OP_LOAD: begin
                reg_write = 1'b1; mem_read = 1'b1; mem_to_reg = 1'b1;
                alu_src_b = 1'b1; uses_rs1 = 1'b1; imm = imm_i;
            end
            OP_STORE: begin
                mem_write = 1'b1; alu_src_b = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1;
                imm = imm_s;
            end
            OP_IMM: begin
                reg_write = 1'b1; alu_src_b = 1'b1; uses_rs1 = 1'b1;
                alu_op = alu_fn; imm = imm_i;
            end
            OP_REG: begin
                reg_write = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1; alu_op = alu_fn;
            end
            OP_FENCE: begin
                // treated as NOP
            end
            OP_SYSTEM: begin
                if (funct3 == 3'b000) halt = 1'b1;   // ECALL / EBREAK
                else                  illegal = 1'b1; // CSR instructions unsupported
            end
            default: illegal = 1'b1;
        endcase
    end
endmodule
