`timescale 1ns/1ps
package rv_pkg;
  localparam logic [6:0] OP_LUI    = 7'b0110111;
  localparam logic [6:0] OP_AUIPC  = 7'b0010111;
  localparam logic [6:0] OP_JAL    = 7'b1101111;
  localparam logic [6:0] OP_JALR   = 7'b1100111;
  localparam logic [6:0] OP_BRANCH = 7'b1100011;
  localparam logic [6:0] OP_LOAD   = 7'b0000011;
  localparam logic [6:0] OP_STORE  = 7'b0100011;
  localparam logic [6:0] OP_IMM    = 7'b0010011;
  localparam logic [6:0] OP_REG    = 7'b0110011;
  localparam logic [6:0] OP_FENCE  = 7'b0001111;
  localparam logic [6:0] OP_SYSTEM = 7'b1110011;

  localparam logic [3:0] ALU_ADD  = 4'd0;
  localparam logic [3:0] ALU_SUB  = 4'd1;
  localparam logic [3:0] ALU_SLL  = 4'd2;
  localparam logic [3:0] ALU_SLT  = 4'd3;
  localparam logic [3:0] ALU_SLTU = 4'd4;
  localparam logic [3:0] ALU_XOR  = 4'd5;
  localparam logic [3:0] ALU_SRL  = 4'd6;
  localparam logic [3:0] ALU_SRA  = 4'd7;
  localparam logic [3:0] ALU_OR   = 4'd8;
  localparam logic [3:0] ALU_AND  = 4'd9;

  localparam logic [1:0] A_RS1  = 2'd0;
  localparam logic [1:0] A_PC   = 2'd1;
  localparam logic [1:0] A_ZERO = 2'd2;

  localparam logic [1:0] WB_ALU = 2'd0;
  localparam logic [1:0] WB_MEM = 2'd1;
  localparam logic [1:0] WB_PC4 = 2'd2;

  localparam logic [3:0] C_NONE             = 4'd0;
  localparam logic [3:0] C_EBREAK           = 4'd1;
  localparam logic [3:0] C_ECALL            = 4'd2;
  localparam logic [3:0] C_ILLEGAL          = 4'd3;
  localparam logic [3:0] C_INST_MISALIGNED  = 4'd4;
  localparam logic [3:0] C_FETCH_ACCESS     = 4'd5;
  localparam logic [3:0] C_LOAD_MISALIGNED  = 4'd6;
  localparam logic [3:0] C_LOAD_ACCESS      = 4'd7;
  localparam logic [3:0] C_STORE_MISALIGNED = 4'd8;
  localparam logic [3:0] C_STORE_ACCESS     = 4'd9;

  localparam logic [1:0] ST_NONE     = 2'd0;
  localparam logic [1:0] ST_LOAD_USE = 2'd1;
  localparam logic [1:0] ST_RAW      = 2'd2;

  localparam logic [1:0] FW_REG = 2'd0;
  localparam logic [1:0] FW_MEM = 2'd1;
  localparam logic [1:0] FW_WB  = 2'd2;
endpackage
