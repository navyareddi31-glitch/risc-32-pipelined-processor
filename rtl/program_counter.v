// -----------------------------------------------------------------------------
// program_counter.v : Program counter register (IF stage)
//   * synchronous active-high reset to address 0
//   * 'en' low freezes the PC (used for load-use / data-hazard stalls)
// -----------------------------------------------------------------------------
module program_counter (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    input  wire [31:0] pc_next,
    output reg  [31:0] pc
);
    always @(posedge clk) begin
        if (rst)     pc <= 32'h0000_0000;
        else if (en) pc <= pc_next;
    end
endmodule
