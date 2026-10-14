// -----------------------------------------------------------------------------
// register_file.v : 32 x 32-bit general purpose registers (x0 hard-wired to 0)
//   * 2 asynchronous read ports, 1 synchronous write port
//   * Write-through bypass: a read of the register being written in the same
//     cycle returns the new value.  This resolves the WB->ID hazard (3rd
//     instruction distance) without any extra stall or forwarding path.
// -----------------------------------------------------------------------------
module register_file (
    input  wire        clk,
    input  wire        we,
    input  wire [4:0]  ra1,
    input  wire [4:0]  ra2,
    input  wire [4:0]  wa,
    input  wire [31:0] wd,
    output wire [31:0] rd1,
    output wire [31:0] rd2
);
    reg [31:0] regs [0:31];

`ifndef SYNTHESIS
    integer i;
    initial for (i = 0; i < 32; i = i + 1) regs[i] = 32'h0;
`endif

    always @(posedge clk)
        if (we && (wa != 5'd0)) regs[wa] <= wd;

    assign rd1 = (ra1 == 5'd0)            ? 32'h0 :
                 (we && (wa == ra1))      ? wd    : regs[ra1];
    assign rd2 = (ra2 == 5'd0)            ? 32'h0 :
                 (we && (wa == ra2))      ? wd    : regs[ra2];
endmodule
