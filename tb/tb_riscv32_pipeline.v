// -----------------------------------------------------------------------------
// tb_riscv32_pipeline.v : self-checking testbench / performance monitor
//
//   Run-time plusargs:
//     +PROGRAM=<hexfile>   program to load into instruction memory
//     +VCD=<file>          dump waveform
//     +TRACE               print every retired instruction (cycle, pc)
//     +DUMPREGS            dump final x0..x31 and dmem[0..63] (for ISS diffing)
//   Compile-time parameters (use iverilog -P):
//     FORWARDING (1/0), BRANCH_PRED (1/0), MAX_CYCLES
//
//   Test convention: program finishes with ECALL; x31 = 0x600D means PASS,
//   0x0BAD means FAIL (x30 holds the failing check number).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_riscv32_pipeline;
    parameter FORWARDING  = 1;
    parameter BRANCH_PRED = 1;
    parameter MAX_CYCLES  = 200000;

    reg  clk = 1'b0;
    reg  rst = 1'b1;
    wire halt;

    riscv32_pipeline #(.FORWARDING(FORWARDING), .BRANCH_PRED(BRANCH_PRED)) dut (
        .clk(clk), .rst(rst), .halt(halt)
    );

    always #5 clk = ~clk;                      // 100 MHz

    reg [8*256-1:0] vcdfile;
    integer i, timeout;
    real cpi, ipc;
    reg [31:0] result;
    integer expected_cycles;

    initial begin
        if ($value$plusargs("VCD=%s", vcdfile)) begin
            $dumpfile(vcdfile);
            $dumpvars(0, tb_riscv32_pipeline);
        end
        repeat (3) @(posedge clk);
        #1 rst = 1'b0;

        timeout = 0;
        while (timeout < MAX_CYCLES) begin
            @(posedge clk);  #1;
            if (halt) timeout = MAX_CYCLES + 1;      // leave loop, keep 'halt' asserted
            else      timeout = timeout + 1;
        end
        // halt is a one-cycle pulse; the counters register it on the next edge
        if (!halt) begin
            $display("RESULT: TIMEOUT after %0d cycles", MAX_CYCLES);
            $finish;
        end

        @(posedge clk);  #1;                   // let the counters see the final retire
        result = dut.u_rf.regs[31];
        cpi = (dut.instr_count > 0) ? (dut.cycle_count * 1.0) / dut.instr_count : 0.0;
        ipc = (dut.cycle_count > 0) ? (dut.instr_count * 1.0) / dut.cycle_count : 0.0;
        expected_cycles = dut.instr_count + 4 + dut.stall_count
                        + 2*dut.ex_flush_count - dut.mispred_pt_count + dut.id_flush_count;

        if ($test$plusargs("DUMPREGS")) begin
            for (i = 0; i < 32; i = i + 1) $display("REG x%0d=%08x", i, dut.u_rf.regs[i]);
            for (i = 0; i < 64; i = i + 1) $display("MEM %0d=%08x", i, dut.u_dmem.mem[i]);
        end

        if      (result == 32'h0000_600D) $display("RESULT: PASS");
        else if (result == 32'h0000_0BAD) $display("RESULT: FAIL (check #%0d)", dut.u_rf.regs[30]);
        else                              $display("RESULT: DONE (x31=%08x, no pass/fail flag)", result);

        $display("STATS fwd=%0d bp=%0d cycles=%0d instrs=%0d cpi=%0.3f ipc=%0.3f stalls=%0d ex_flush=%0d id_flush=%0d branches=%0d taken=%0d mispred=%0d jal=%0d jalr=%0d loads=%0d stores=%0d ctrl_bubbles=%0d",
                 FORWARDING, BRANCH_PRED, dut.cycle_count, dut.instr_count, cpi, ipc,
                 dut.stall_count, dut.ex_flush_count, dut.id_flush_count,
                 dut.branch_count, dut.taken_count, dut.mispredict_count,
                 dut.jal_count, dut.jalr_count, dut.load_count, dut.store_count,
                 2*dut.ex_flush_count - dut.mispred_pt_count + dut.id_flush_count);

        if (expected_cycles == dut.cycle_count) $display("CYCLE-ACCOUNTING: OK");
        else $display("CYCLE-ACCOUNTING: MISMATCH (cycles=%0d, accounted=%0d)",
                      dut.cycle_count, expected_cycles);
        $finish;
    end

    // retire trace
    always @(posedge clk)
        if (!rst && dut.wb_valid && $test$plusargs("TRACE"))
            $display("[cycle %0d] retire pc=%08x rd=x%0d wdata=%08x%s", dut.cycle_count,
                     dut.wb_pc, dut.wb_rd, dut.wb_data, dut.wb_reg_write ? "" : " (no wb)");
endmodule
