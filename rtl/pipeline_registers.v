// -----------------------------------------------------------------------------
// pipeline_registers.v : IF/ID, ID/EX, EX/MEM and MEM/WB stage registers
//
//  * 'valid' travels with every instruction (0 = bubble) and is used only for
//    performance counters / tracing; bubbles are also made harmless by clearing
//    every control signal, so correctness never depends on 'valid'.
//  * 'pc' is carried down the pipe for tracing only; it is unused in hardware
//    after EX and is removed by synthesis.
// -----------------------------------------------------------------------------

// ---------------------------------------------------------------- IF / ID ----
module if_id_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,        // 0 = hold (stall)
    input  wire        flush,     // 1 = replace with bubble (has priority over en)
    input  wire [31:0] pc_in,
    input  wire [31:0] instr_in,
    output reg  [31:0] pc_out,
    output reg  [31:0] instr_out,
    output reg         valid_out
);
    localparam NOP = 32'h0000_0013;   // addi x0, x0, 0
    always @(posedge clk) begin
        if (rst || flush) begin
            pc_out    <= 32'h0;
            instr_out <= NOP;
            valid_out <= 1'b0;
        end else if (en) begin
            pc_out    <= pc_in;
            instr_out <= instr_in;
            valid_out <= 1'b1;
        end
    end
endmodule

// ---------------------------------------------------------------- ID / EX ----
module id_ex_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        bubble,    // 1 = insert bubble (stall or flush)
    // data
    input  wire [31:0] pc_in,
    input  wire [31:0] rs1_data_in,
    input  wire [31:0] rs2_data_in,
    input  wire [31:0] imm_in,
    input  wire [4:0]  rs1_in,
    input  wire [4:0]  rs2_in,
    input  wire [4:0]  rd_in,
    input  wire [2:0]  funct3_in,
    // control
    input  wire        reg_write_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        mem_to_reg_in,
    input  wire [1:0]  alu_src_a_in,
    input  wire        alu_src_b_in,
    input  wire [3:0]  alu_op_in,
    input  wire        is_branch_in,
    input  wire        is_jal_in,
    input  wire        is_jalr_in,
    input  wire        halt_in,
    input  wire        pred_taken_in,
    input  wire        valid_in,
    // outputs
    output reg  [31:0] pc_out,
    output reg  [31:0] rs1_data_out,
    output reg  [31:0] rs2_data_out,
    output reg  [31:0] imm_out,
    output reg  [4:0]  rs1_out,
    output reg  [4:0]  rs2_out,
    output reg  [4:0]  rd_out,
    output reg  [2:0]  funct3_out,
    output reg         reg_write_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg         mem_to_reg_out,
    output reg  [1:0]  alu_src_a_out,
    output reg         alu_src_b_out,
    output reg  [3:0]  alu_op_out,
    output reg         is_branch_out,
    output reg         is_jal_out,
    output reg         is_jalr_out,
    output reg         halt_out,
    output reg         pred_taken_out,
    output reg         valid_out
);
    always @(posedge clk) begin
        if (rst || bubble) begin
            pc_out         <= 32'h0;
            rs1_data_out   <= 32'h0;
            rs2_data_out   <= 32'h0;
            imm_out        <= 32'h0;
            rs1_out        <= 5'd0;
            rs2_out        <= 5'd0;
            rd_out         <= 5'd0;
            funct3_out     <= 3'd0;
            reg_write_out  <= 1'b0;
            mem_read_out   <= 1'b0;
            mem_write_out  <= 1'b0;
            mem_to_reg_out <= 1'b0;
            alu_src_a_out  <= 2'd0;
            alu_src_b_out  <= 1'b0;
            alu_op_out     <= 4'd0;
            is_branch_out  <= 1'b0;
            is_jal_out     <= 1'b0;
            is_jalr_out    <= 1'b0;
            halt_out       <= 1'b0;
            pred_taken_out <= 1'b0;
            valid_out      <= 1'b0;
        end else begin
            pc_out         <= pc_in;
            rs1_data_out   <= rs1_data_in;
            rs2_data_out   <= rs2_data_in;
            imm_out        <= imm_in;
            rs1_out        <= rs1_in;
            rs2_out        <= rs2_in;
            rd_out         <= rd_in;
            funct3_out     <= funct3_in;
            reg_write_out  <= reg_write_in;
            mem_read_out   <= mem_read_in;
            mem_write_out  <= mem_write_in;
            mem_to_reg_out <= mem_to_reg_in;
            alu_src_a_out  <= alu_src_a_in;
            alu_src_b_out  <= alu_src_b_in;
            alu_op_out     <= alu_op_in;
            is_branch_out  <= is_branch_in;
            is_jal_out     <= is_jal_in;
            is_jalr_out    <= is_jalr_in;
            halt_out       <= halt_in;
            pred_taken_out <= pred_taken_in;
            valid_out      <= valid_in;
        end
    end
endmodule

// --------------------------------------------------------------- EX / MEM ----
module ex_mem_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] pc_in,
    input  wire [31:0] result_in,       // ALU result (or PC+4 for JAL/JALR)
    input  wire [31:0] store_data_in,
    input  wire [4:0]  rd_in,
    input  wire [2:0]  funct3_in,
    input  wire        reg_write_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        mem_to_reg_in,
    input  wire        halt_in,
    input  wire        valid_in,
    output reg  [31:0] pc_out,
    output reg  [31:0] result_out,
    output reg  [31:0] store_data_out,
    output reg  [4:0]  rd_out,
    output reg  [2:0]  funct3_out,
    output reg         reg_write_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg         mem_to_reg_out,
    output reg         halt_out,
    output reg         valid_out
);
    always @(posedge clk) begin
        if (rst) begin
            pc_out         <= 32'h0;
            result_out     <= 32'h0;
            store_data_out <= 32'h0;
            rd_out         <= 5'd0;
            funct3_out     <= 3'd0;
            reg_write_out  <= 1'b0;
            mem_read_out   <= 1'b0;
            mem_write_out  <= 1'b0;
            mem_to_reg_out <= 1'b0;
            halt_out       <= 1'b0;
            valid_out      <= 1'b0;
        end else begin
            pc_out         <= pc_in;
            result_out     <= result_in;
            store_data_out <= store_data_in;
            rd_out         <= rd_in;
            funct3_out     <= funct3_in;
            reg_write_out  <= reg_write_in;
            mem_read_out   <= mem_read_in;
            mem_write_out  <= mem_write_in;
            mem_to_reg_out <= mem_to_reg_in;
            halt_out       <= halt_in;
            valid_out      <= valid_in;
        end
    end
endmodule

// --------------------------------------------------------------- MEM / WB ----
module mem_wb_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] pc_in,
    input  wire [31:0] result_in,
    input  wire [31:0] load_data_in,
    input  wire [4:0]  rd_in,
    input  wire        reg_write_in,
    input  wire        mem_to_reg_in,
    input  wire        halt_in,
    input  wire        valid_in,
    output reg  [31:0] pc_out,
    output reg  [31:0] result_out,
    output reg  [31:0] load_data_out,
    output reg  [4:0]  rd_out,
    output reg         reg_write_out,
    output reg         mem_to_reg_out,
    output reg         halt_out,
    output reg         valid_out
);
    always @(posedge clk) begin
        if (rst) begin
            pc_out         <= 32'h0;
            result_out     <= 32'h0;
            load_data_out  <= 32'h0;
            rd_out         <= 5'd0;
            reg_write_out  <= 1'b0;
            mem_to_reg_out <= 1'b0;
            halt_out       <= 1'b0;
            valid_out      <= 1'b0;
        end else begin
            pc_out         <= pc_in;
            result_out     <= result_in;
            load_data_out  <= load_data_in;
            rd_out         <= rd_in;
            reg_write_out  <= reg_write_in;
            mem_to_reg_out <= mem_to_reg_in;
            halt_out       <= halt_in;
            valid_out      <= valid_in;
        end
    end
endmodule
