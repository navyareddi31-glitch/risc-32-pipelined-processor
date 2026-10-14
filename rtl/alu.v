// -----------------------------------------------------------------------------
// alu.v : RV32I arithmetic / logic unit (EX stage)
//   Also produces the three comparison flags used by the branch unit, so a
//   single set of operands feeds both the ALU result and the branch decision.
// -----------------------------------------------------------------------------
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  op,
    output reg  [31:0] result,
    output wire        eq,      // a == b
    output wire        lt,      // a <  b (signed)
    output wire        ltu      // a <  b (unsigned)
);
    localparam ALU_ADD  = 4'd0,  ALU_SUB = 4'd1, ALU_SLL = 4'd2, ALU_SLT = 4'd3,
               ALU_SLTU = 4'd4,  ALU_XOR = 4'd5, ALU_SRL = 4'd6, ALU_SRA = 4'd7,
               ALU_OR   = 4'd8,  ALU_AND = 4'd9;

    wire [4:0] shamt = b[4:0];

    assign eq  = (a == b);
    assign lt  = ($signed(a) <  $signed(b));
    assign ltu = (a < b);

    always @(*) begin
        case (op)
            ALU_ADD : result = a + b;
            ALU_SUB : result = a - b;
            ALU_SLL : result = a << shamt;
            ALU_SLT : result = {31'b0, lt};
            ALU_SLTU: result = {31'b0, ltu};
            ALU_XOR : result = a ^ b;
            ALU_SRL : result = a >> shamt;
            ALU_SRA : result = $signed(a) >>> shamt;
            ALU_OR  : result = a | b;
            ALU_AND : result = a & b;
            default : result = 32'h0;
        endcase
    end
endmodule
