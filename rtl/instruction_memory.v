// -----------------------------------------------------------------------------
// instruction_memory.v : Word-addressed ROM (asynchronous read)
//   * Program is loaded with $readmemh, either from the +PROGRAM=<file> plusarg
//     or from the INIT_FILE parameter.  Unused locations hold NOP (addi x0,x0,0)
//   * Addresses wrap around at WORDS (so wrong-path fetches are harmless)
//   * Loading is simulation-only (`SYNTHESIS is defined by the Yosys script; the
//     memory is treated as a black box there)
// -----------------------------------------------------------------------------
module instruction_memory #(
    parameter WORDS     = 256,
    parameter INIT_FILE = ""
)(
    input  wire [31:0] addr,
    output wire [31:0] instr
);
    localparam AW = $clog2(WORDS);

    reg [31:0] mem [0:WORDS-1];

    assign instr = mem[addr[AW+1:2]];

`ifndef SYNTHESIS
    integer i;
    reg [8*256-1:0] fname;
    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h0000_0013;   // NOP
        if ($value$plusargs("PROGRAM=%s", fname))
            $readmemh(fname, mem);
        else if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end
`endif
endmodule
