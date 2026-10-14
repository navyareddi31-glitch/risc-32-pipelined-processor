// -----------------------------------------------------------------------------
// hazard_unit.v : Data-hazard detection / forwarding and control-hazard
//                 prediction support
//
//  hazard_unit      Detects RAW hazards and generates the EX-stage forwarding
//                   selects and the pipeline stall.
//                     FORWARDING = 1 : forward EX/MEM and MEM/WB results into
//                                      the EX stage; only a load-use hazard
//                                      costs a (1-cycle) stall.
//                     FORWARDING = 0 : no bypass paths; an instruction in ID
//                                      stalls until its producer has reached
//                                      WB (the register file write-through
//                                      covers the WB->ID case).
//
//  branch_predictor 2-bit saturating-counter branch history table (BHT),
//                   indexed by PC[log2(ENTRIES)+1:2], initialised weakly
//                   not-taken.  ENABLE = 0 degrades it to static predict-not-
//                   taken, which is the "no branch prediction" baseline.
// -----------------------------------------------------------------------------
module hazard_unit #(
    parameter FORWARDING = 1
)(
    // ID stage (instruction being decoded)
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    input  wire       id_uses_rs1,
    input  wire       id_uses_rs2,
    // EX stage (instruction being executed)
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,
    input  wire [4:0] ex_rd,
    input  wire       ex_reg_write,
    input  wire       ex_mem_read,
    // MEM stage
    input  wire [4:0] mem_rd,
    input  wire       mem_reg_write,
    // WB stage
    input  wire [4:0] wb_rd,
    input  wire       wb_reg_write,
    // outputs
    output wire [1:0] forward_a,   // 2'b00 register file, 2'b10 EX/MEM, 2'b01 MEM/WB
    output wire [1:0] forward_b,
    output wire       stall        // freeze PC and IF/ID, insert bubble into ID/EX
);
    // ---- stall detection ----------------------------------------------------
    wire hit_ex  = ex_reg_write  && (ex_rd  != 5'd0) &&
                   ((id_uses_rs1 && (id_rs1 == ex_rd )) ||
                    (id_uses_rs2 && (id_rs2 == ex_rd )));
    wire hit_mem = mem_reg_write && (mem_rd != 5'd0) &&
                   ((id_uses_rs1 && (id_rs1 == mem_rd)) ||
                    (id_uses_rs2 && (id_rs2 == mem_rd)));

    // ---- forwarding ---------------------------------------------------------
    wire a_from_mem = mem_reg_write && (mem_rd != 5'd0) && (mem_rd == ex_rs1);
    wire a_from_wb  = wb_reg_write  && (wb_rd  != 5'd0) && (wb_rd  == ex_rs1);
    wire b_from_mem = mem_reg_write && (mem_rd != 5'd0) && (mem_rd == ex_rs2);
    wire b_from_wb  = wb_reg_write  && (wb_rd  != 5'd0) && (wb_rd  == ex_rs2);

    generate
        if (FORWARDING != 0) begin : g_fwd
            // load-use is the only hazard forwarding cannot hide
            assign stall     = ex_mem_read && hit_ex;
            assign forward_a = a_from_mem ? 2'b10 : (a_from_wb ? 2'b01 : 2'b00);
            assign forward_b = b_from_mem ? 2'b10 : (b_from_wb ? 2'b01 : 2'b00);
        end else begin : g_nofwd
            assign stall     = hit_ex || hit_mem;
            assign forward_a = 2'b00;
            assign forward_b = 2'b00;
        end
    endgenerate
endmodule


module branch_predictor #(
    parameter ENABLE  = 1,
    parameter ENTRIES = 64
)(
    input  wire        clk,
    input  wire        rst,
    // lookup (ID stage)
    input  wire [31:0] lookup_pc,
    output wire        predict_taken,
    // update (EX stage, when a branch resolves)
    input  wire        update_en,
    input  wire [31:0] update_pc,
    input  wire        update_taken
);
    localparam IW = $clog2(ENTRIES);

    // flat vector of 2-bit counters (maps to plain flip-flops in synthesis)
    reg [2*ENTRIES-1:0] bht;

    wire [IW-1:0] lidx = lookup_pc[IW+1:2];
    wire [IW-1:0] uidx = update_pc[IW+1:2];
    wire [1:0]    lcnt = bht[2*lidx +: 2];
    wire [1:0]    ucnt = bht[2*uidx +: 2];

    assign predict_taken = (ENABLE != 0) ? lcnt[1] : 1'b0;

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < ENTRIES; i = i + 1) bht[2*i +: 2] <= 2'b01;  // weakly not-taken
        end else if (update_en && (ENABLE != 0)) begin
            if (update_taken) begin
                if (ucnt != 2'b11) bht[2*uidx +: 2] <= ucnt + 2'b01;
            end else begin
                if (ucnt != 2'b00) bht[2*uidx +: 2] <= ucnt - 2'b01;
            end
        end
    end
endmodule
