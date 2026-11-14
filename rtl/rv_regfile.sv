`timescale 1ns/1ps
module rv_regfile (
  input  logic        clk,
  input  logic [4:0]  ra1,
  input  logic [4:0]  ra2,
  output logic [31:0] rd1,
  output logic [31:0] rd2,
  input  logic        we,
  input  logic [4:0]  wa,
  input  logic [31:0] wd
);
  logic [31:0] regs [0:31];

  assign rd1 = (ra1 == 5'd0) ? 32'h0 : regs[ra1];
  assign rd2 = (ra2 == 5'd0) ? 32'h0 : regs[ra2];

  always @(posedge clk) begin
    if (we && wa != 5'd0) regs[wa] <= wd;
  end
endmodule
