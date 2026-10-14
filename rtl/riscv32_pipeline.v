// -----------------------------------------------------------------------------
// riscv32_pipeline.v : 5-stage pipelined RV32I processor (top level)
//
//   IF  -> ID  -> EX  -> MEM -> WB
//
//  Hazard handling
//   * Data hazards  : EX-stage forwarding (EX/MEM, MEM/WB) + 1-cycle load-use
//                     stall.  FORWARDING=0 removes the bypass network and stalls
//                     in ID until the producer reaches WB (for CPI comparison).
//   * Control hazards
//       - JAL                : always taken, target computed in ID    (1 bubble)
//       - Conditional branch : predicted in ID by a 2-bit BHT         (1 bubble
//                              if predicted taken), resolved in EX; a
//                              misprediction flushes IF+ID           (2 bubbles)
//       - JALR               : resolved in EX (target = rs1+imm)      (2 bubbles)
//     BRANCH_PRED=0 -> static predict-not-taken.
//
//  Memories (instruction + data) are Harvard-style, asynchronous read,
//  synchronous write; data memory supports LB/LH/LW/LBU/LHU/SB/SH/SW (aligned).
//  Performance counters and the data-memory model live here for simulation and
//  are excluded from synthesis (`SYNTHESIS).
// -----------------------------------------------------------------------------
module riscv32_pipeline #(
    parameter FORWARDING  = 1,     // 1: forwarding unit enabled
    parameter BRANCH_PRED = 1,     // 1: 2-bit BHT, 0: predict-not-taken
    parameter IMEM_WORDS  = 256,
    parameter DMEM_WORDS  = 256,
    parameter BHT_ENTRIES = 64
)(
    input  wire clk,
    input  wire rst,
    output wire halt            // ECALL/EBREAK has retired
);
    // =========================================================================
    // Signal declarations
    // =========================================================================
    // ---- IF
    wire [31:0] if_pc, if_instr, if_pc_plus4, pc_next;
    wire        pc_en;
    // ---- ID
    wire [31:0] id_pc, id_instr, id_imm, id_rd1, id_rd2, id_target;
    wire        id_valid;
    wire [4:0]  id_rs1 = id_instr[19:15];
    wire [4:0]  id_rs2 = id_instr[24:20];
    wire [4:0]  id_rd  = id_instr[11:7];
    wire [2:0]  id_funct3 = id_instr[14:12];
    wire        id_reg_write, id_mem_read, id_mem_write, id_mem_to_reg;
    wire [1:0]  id_alu_src_a;
    wire        id_alu_src_b;
    wire [3:0]  id_alu_op;
    wire        id_is_branch, id_is_jal, id_is_jalr, id_uses_rs1, id_uses_rs2;
    wire        id_halt, id_illegal;
    wire        bp_taken, id_pred_taken, id_redirect;
    // ---- EX
    wire [31:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm;
    wire [4:0]  ex_rs1, ex_rs2, ex_rd;
    wire [2:0]  ex_funct3;
    wire        ex_reg_write, ex_mem_read, ex_mem_write, ex_mem_to_reg;
    wire [1:0]  ex_alu_src_a;
    wire        ex_alu_src_b;
    wire [3:0]  ex_alu_op;
    wire        ex_is_branch, ex_is_jal, ex_is_jalr, ex_halt, ex_pred_taken, ex_valid;
    wire [1:0]  forward_a, forward_b;
    wire [31:0] ex_fwd_a, ex_fwd_b, ex_alu_a, ex_alu_b, ex_alu_result, ex_result;
    wire        alu_eq, alu_lt, alu_ltu;
    reg         ex_cond;
    wire        ex_branch_taken, ex_redirect;
    wire [31:0] ex_redirect_pc;
    // ---- MEM
    wire [31:0] mem_pc, mem_result, mem_store_data, mem_load_data;
    wire [4:0]  mem_rd;
    wire [2:0]  mem_funct3;
    wire        mem_reg_write, mem_mem_read, mem_mem_write, mem_mem_to_reg, mem_halt, mem_valid;
    // ---- WB
    wire [31:0] wb_pc, wb_result, wb_load_data, wb_data;
    wire [4:0]  wb_rd;
    wire        wb_reg_write, wb_mem_to_reg, wb_halt, wb_valid;
    // ---- hazard
    wire        stall;

    assign halt = wb_valid & wb_halt;

    // =========================================================================
    // IF : instruction fetch
    // =========================================================================
    assign if_pc_plus4 = if_pc + 32'd4;
    // priority: EX redirect (mispredict / JALR) > ID redirect (JAL / predicted taken) > PC+4
    assign pc_next = ex_redirect ? ex_redirect_pc :
                     id_redirect ? id_target      : if_pc_plus4;
    assign pc_en   = ~stall | ex_redirect;

    program_counter u_pc (
        .clk(clk), .rst(rst), .en(pc_en), .pc_next(pc_next), .pc(if_pc)
    );

    instruction_memory #(.WORDS(IMEM_WORDS)) u_imem (
        .addr(if_pc), .instr(if_instr)
    );

    if_id_reg u_if_id (
        .clk(clk), .rst(rst),
        .en(~stall),
        .flush(ex_redirect | id_redirect),
        .pc_in(if_pc), .instr_in(if_instr),
        .pc_out(id_pc), .instr_out(id_instr), .valid_out(id_valid)
    );

    // =========================================================================
    // ID : decode, register read, early branch prediction
    // =========================================================================
    control_unit u_ctrl (
        .instr(id_instr),
        .reg_write(id_reg_write), .mem_read(id_mem_read), .mem_write(id_mem_write),
        .mem_to_reg(id_mem_to_reg), .alu_src_a(id_alu_src_a), .alu_src_b(id_alu_src_b),
        .alu_op(id_alu_op), .is_branch(id_is_branch), .is_jal(id_is_jal),
        .is_jalr(id_is_jalr), .uses_rs1(id_uses_rs1), .uses_rs2(id_uses_rs2),
        .halt(id_halt), .illegal(id_illegal), .imm(id_imm)
    );

    register_file u_rf (
        .clk(clk), .we(wb_reg_write),
        .ra1(id_rs1), .ra2(id_rs2), .wa(wb_rd), .wd(wb_data),
        .rd1(id_rd1), .rd2(id_rd2)
    );

    branch_predictor #(.ENABLE(BRANCH_PRED), .ENTRIES(BHT_ENTRIES)) u_bp (
        .clk(clk), .rst(rst),
        .lookup_pc(id_pc), .predict_taken(bp_taken),
        .update_en(ex_is_branch), .update_pc(ex_pc), .update_taken(ex_branch_taken)
    );

    assign id_target     = id_pc + id_imm;                       // branch / JAL target
    assign id_pred_taken = id_is_jal | (id_is_branch & bp_taken);
    // do not redirect while stalled (instruction will be re-presented) or when
    // this instruction is itself on a wrong path (EX redirect has priority)
    assign id_redirect   = id_pred_taken & ~stall & ~ex_redirect;

    hazard_unit #(.FORWARDING(FORWARDING)) u_hazard (
        .id_rs1(id_rs1), .id_rs2(id_rs2),
        .id_uses_rs1(id_uses_rs1), .id_uses_rs2(id_uses_rs2),
        .ex_rs1(ex_rs1), .ex_rs2(ex_rs2), .ex_rd(ex_rd),
        .ex_reg_write(ex_reg_write), .ex_mem_read(ex_mem_read),
        .mem_rd(mem_rd), .mem_reg_write(mem_reg_write),
        .wb_rd(wb_rd), .wb_reg_write(wb_reg_write),
        .forward_a(forward_a), .forward_b(forward_b), .stall(stall)
    );

    id_ex_reg u_id_ex (
        .clk(clk), .rst(rst),
        .bubble(stall | ex_redirect),
        .pc_in(id_pc), .rs1_data_in(id_rd1), .rs2_data_in(id_rd2), .imm_in(id_imm),
        .rs1_in(id_rs1), .rs2_in(id_rs2), .rd_in(id_rd), .funct3_in(id_funct3),
        .reg_write_in(id_reg_write), .mem_read_in(id_mem_read),
        .mem_write_in(id_mem_write), .mem_to_reg_in(id_mem_to_reg),
        .alu_src_a_in(id_alu_src_a), .alu_src_b_in(id_alu_src_b), .alu_op_in(id_alu_op),
        .is_branch_in(id_is_branch), .is_jal_in(id_is_jal), .is_jalr_in(id_is_jalr),
        .halt_in(id_halt), .pred_taken_in(id_pred_taken), .valid_in(id_valid),
        .pc_out(ex_pc), .rs1_data_out(ex_rs1_data), .rs2_data_out(ex_rs2_data),
        .imm_out(ex_imm), .rs1_out(ex_rs1), .rs2_out(ex_rs2), .rd_out(ex_rd),
        .funct3_out(ex_funct3),
        .reg_write_out(ex_reg_write), .mem_read_out(ex_mem_read),
        .mem_write_out(ex_mem_write), .mem_to_reg_out(ex_mem_to_reg),
        .alu_src_a_out(ex_alu_src_a), .alu_src_b_out(ex_alu_src_b), .alu_op_out(ex_alu_op),
        .is_branch_out(ex_is_branch), .is_jal_out(ex_is_jal), .is_jalr_out(ex_is_jalr),
        .halt_out(ex_halt), .pred_taken_out(ex_pred_taken), .valid_out(ex_valid)
    );

    // =========================================================================
    // EX : forwarding muxes, ALU, branch resolution
    // =========================================================================
    assign ex_fwd_a = (forward_a == 2'b10) ? mem_result :
                      (forward_a == 2'b01) ? wb_data    : ex_rs1_data;
    assign ex_fwd_b = (forward_b == 2'b10) ? mem_result :
                      (forward_b == 2'b01) ? wb_data    : ex_rs2_data;

    assign ex_alu_a = (ex_alu_src_a == 2'd0) ? ex_fwd_a :
                      (ex_alu_src_a == 2'd1) ? ex_pc    : 32'h0;
    assign ex_alu_b = ex_alu_src_b ? ex_imm : ex_fwd_b;

    alu u_alu (
        .a(ex_alu_a), .b(ex_alu_b), .op(ex_alu_op),
        .result(ex_alu_result), .eq(alu_eq), .lt(alu_lt), .ltu(alu_ltu)
    );

    // branch condition (branches use alu_src_a=rs1, alu_src_b=rs2 -> flags valid)
    always @(*) begin
        case (ex_funct3)
            3'b000:  ex_cond =  alu_eq;     // BEQ
            3'b001:  ex_cond = ~alu_eq;     // BNE
            3'b100:  ex_cond =  alu_lt;     // BLT
            3'b101:  ex_cond = ~alu_lt;     // BGE
            3'b110:  ex_cond =  alu_ltu;    // BLTU
            3'b111:  ex_cond = ~alu_ltu;    // BGEU
            default: ex_cond = 1'b0;
        endcase
    end
    assign ex_branch_taken = ex_is_branch & ex_cond;

    // misprediction of a conditional branch, or any JALR, redirects the PC
    assign ex_redirect    = (ex_is_branch & (ex_branch_taken != ex_pred_taken)) | ex_is_jalr;
    assign ex_redirect_pc = ex_is_jalr       ? {ex_alu_result[31:1], 1'b0} :
                            ex_branch_taken  ? (ex_pc + ex_imm)            :
                                               (ex_pc + 32'd4);

    assign ex_result = (ex_is_jal | ex_is_jalr) ? (ex_pc + 32'd4) : ex_alu_result;

    ex_mem_reg u_ex_mem (
        .clk(clk), .rst(rst),
        .pc_in(ex_pc), .result_in(ex_result), .store_data_in(ex_fwd_b),
        .rd_in(ex_rd), .funct3_in(ex_funct3),
        .reg_write_in(ex_reg_write), .mem_read_in(ex_mem_read),
        .mem_write_in(ex_mem_write), .mem_to_reg_in(ex_mem_to_reg),
        .halt_in(ex_halt), .valid_in(ex_valid),
        .pc_out(mem_pc), .result_out(mem_result), .store_data_out(mem_store_data),
        .rd_out(mem_rd), .funct3_out(mem_funct3),
        .reg_write_out(mem_reg_write), .mem_read_out(mem_mem_read),
        .mem_write_out(mem_mem_write), .mem_to_reg_out(mem_mem_to_reg),
        .halt_out(mem_halt), .valid_out(mem_valid)
    );

    // =========================================================================
    // MEM : data memory access
    // =========================================================================
    data_memory #(.WORDS(DMEM_WORDS)) u_dmem (
        .clk(clk), .we(mem_mem_write), .funct3(mem_funct3),
        .addr(mem_result), .wdata(mem_store_data), .rdata(mem_load_data)
    );

    mem_wb_reg u_mem_wb (
        .clk(clk), .rst(rst),
        .pc_in(mem_pc), .result_in(mem_result), .load_data_in(mem_load_data),
        .rd_in(mem_rd), .reg_write_in(mem_reg_write), .mem_to_reg_in(mem_mem_to_reg),
        .halt_in(mem_halt), .valid_in(mem_valid),
        .pc_out(wb_pc), .result_out(wb_result), .load_data_out(wb_load_data),
        .rd_out(wb_rd), .reg_write_out(wb_reg_write), .mem_to_reg_out(wb_mem_to_reg),
        .halt_out(wb_halt), .valid_out(wb_valid)
    );

    // =========================================================================
    // WB : write-back mux (feeds register file and forwarding network)
    // =========================================================================
    assign wb_data = wb_mem_to_reg ? wb_load_data : wb_result;

    // =========================================================================
    // Performance counters (simulation only)
    //   cycles = retired + 4 (pipeline fill) + stalls + 2*ex_flushes + id_flushes
    //            - mispred_pt   (a mispredicted *predicted-taken* branch already left
    //                            one bubble in ID, so its EX flush costs only 1 more)
    // =========================================================================
`ifndef SYNTHESIS
    // events caused by instructions younger than a halting ECALL never matter
    wire shadow = ex_halt | mem_halt | wb_halt;
    integer cycle_count, instr_count, stall_count, ex_flush_count, id_flush_count;
    integer branch_count, taken_count, mispredict_count, jalr_count, jal_count;
    integer load_count, store_count, mispred_pt_count;
    always @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0; instr_count <= 0; stall_count <= 0;
            ex_flush_count <= 0; id_flush_count <= 0; branch_count <= 0;
            taken_count <= 0; mispredict_count <= 0; jalr_count <= 0; jal_count <= 0;
            load_count <= 0; store_count <= 0; mispred_pt_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (wb_valid)                 instr_count    <= instr_count + 1;
            if (stall & ~ex_redirect & ~shadow) stall_count    <= stall_count + 1;
            if (ex_redirect)              ex_flush_count <= ex_flush_count + 1;
            if (id_redirect & ~shadow)    id_flush_count <= id_flush_count + 1;
            if (ex_is_branch)             branch_count   <= branch_count + 1;
            if (ex_branch_taken)          taken_count    <= taken_count + 1;
            if (ex_is_branch & (ex_branch_taken != ex_pred_taken))
                                          mispredict_count <= mispredict_count + 1;
            if (ex_is_branch & ex_pred_taken & ~ex_branch_taken)
                                          mispred_pt_count <= mispred_pt_count + 1;
            if (ex_is_jalr)               jalr_count     <= jalr_count + 1;
            if (ex_is_jal & ex_valid)     jal_count      <= jal_count + 1;
            if (ex_mem_read  & ex_valid)  load_count    <= load_count + 1;
            if (ex_mem_write & ex_valid)  store_count   <= store_count + 1;
        end
    end
`endif
endmodule


// -----------------------------------------------------------------------------
// data_memory : word array with byte/half/word access, sign/zero-extended loads
//   (aligned accesses only; behavioural model, treated as a black box in the
//   synthesis flow)
// -----------------------------------------------------------------------------
module data_memory #(
    parameter WORDS = 256
)(
    input  wire        clk,
    input  wire        we,
    input  wire [2:0]  funct3,     // 000 B, 001 H, 010 W, 100 BU, 101 HU
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata
);
    localparam AW = $clog2(WORDS);

    reg [31:0] mem [0:WORDS-1];

    wire [AW-1:0] widx = addr[AW+1:2];
    wire [1:0]    boff = addr[1:0];
    wire [31:0]   word = mem[widx];

    // ---- load path
    wire [31:0] shifted = word >> {boff, 3'b000};
    always @(*) begin
        case (funct3)
            3'b000:  rdata = {{24{shifted[7]}},  shifted[7:0]};     // LB
            3'b001:  rdata = {{16{shifted[15]}}, shifted[15:0]};    // LH
            3'b100:  rdata = {24'b0, shifted[7:0]};                 // LBU
            3'b101:  rdata = {16'b0, shifted[15:0]};                // LHU
            default: rdata = word;                                  // LW
        endcase
    end

    // ---- store path (read-modify-write with byte mask)
    reg [31:0] wmask, wdat;
    always @(*) begin
        case (funct3[1:0])
            2'b00:   begin wmask = 32'h0000_00FF << {boff, 3'b000};       wdat = {4{wdata[7:0]}};  end
            2'b01:   begin wmask = 32'h0000_FFFF << {boff[1], 4'b0000};   wdat = {2{wdata[15:0]}}; end
            default: begin wmask = 32'hFFFF_FFFF;                         wdat = wdata;            end
        endcase
    end

    always @(posedge clk)
        if (we) mem[widx] <= (word & ~wmask) | (wdat & wmask);

`ifndef SYNTHESIS
    integer i;
    initial for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h0;
`endif
endmodule
