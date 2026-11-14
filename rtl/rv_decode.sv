`timescale 1ns/1ps
module rv_decode (
  input  logic [31:0] inst,
  output logic [4:0]  rs1,
  output logic [4:0]  rs2,
  output logic [4:0]  rd,
  output logic [2:0]  funct3,
  output logic [31:0] imm,
  output logic [3:0]  alu_op,
  output logic [1:0]  a_sel,
  output logic        b_imm,
  output logic        rf_we,
  output logic [1:0]  wb_sel,
  output logic        is_load,
  output logic        is_store,
  output logic [1:0]  mem_size,
  output logic        mem_unsigned,
  output logic        is_branch,
  output logic        is_jal,
  output logic        is_jalr,
  output logic        uses_rs1,
  output logic        uses_rs2,
  output logic        illegal,
  output logic        is_ecall,
  output logic        is_ebreak
);
  import rv_pkg::*;

  logic [6:0]  opcode;
  logic [6:0]  funct7;
  logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  logic        bad;

  assign opcode = inst[6:0];
  assign funct3 = inst[14:12];
  assign funct7 = inst[31:25];
  assign rd     = inst[11:7];
  assign rs1    = inst[19:15];
  assign rs2    = inst[24:20];

  assign imm_i = {{20{inst[31]}}, inst[31:20]};
  assign imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
  assign imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
  assign imm_u = {inst[31:12], 12'b0};
  assign imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

  always @(*) begin
    imm          = 32'h0;
    alu_op       = ALU_ADD;
    a_sel        = A_RS1;
    b_imm        = 1'b0;
    rf_we        = 1'b0;
    wb_sel       = WB_ALU;
    is_load      = 1'b0;
    is_store     = 1'b0;
    mem_size     = 2'd0;
    mem_unsigned = 1'b0;
    is_branch    = 1'b0;
    is_jal       = 1'b0;
    is_jalr      = 1'b0;
    uses_rs1     = 1'b0;
    uses_rs2     = 1'b0;
    is_ecall     = 1'b0;
    is_ebreak    = 1'b0;
    bad          = 1'b0;

    if (inst[1:0] != 2'b11) begin
      bad = 1'b1;
    end else begin
      case (opcode)
        OP_LUI: begin
          imm   = imm_u;
          a_sel = A_ZERO;
          b_imm = 1'b1;
          rf_we = 1'b1;
        end
        OP_AUIPC: begin
          imm   = imm_u;
          a_sel = A_PC;
          b_imm = 1'b1;
          rf_we = 1'b1;
        end
        OP_JAL: begin
          imm    = imm_j;
          is_jal = 1'b1;
          rf_we  = 1'b1;
          wb_sel = WB_PC4;
        end
        OP_JALR: begin
          imm      = imm_i;
          is_jalr  = 1'b1;
          rf_we    = 1'b1;
          wb_sel   = WB_PC4;
          uses_rs1 = 1'b1;
          bad      = funct3 != 3'b000;
        end
        OP_BRANCH: begin
          imm       = imm_b;
          is_branch = 1'b1;
          uses_rs1  = 1'b1;
          uses_rs2  = 1'b1;
          bad       = funct3 == 3'b010 || funct3 == 3'b011;
        end
        OP_LOAD: begin
          imm          = imm_i;
          b_imm        = 1'b1;
          is_load      = 1'b1;
          rf_we        = 1'b1;
          wb_sel       = WB_MEM;
          uses_rs1     = 1'b1;
          mem_size     = funct3[1:0];
          mem_unsigned = funct3[2];
          bad          = funct3 == 3'b011 || funct3 == 3'b110 || funct3 == 3'b111;
        end
        OP_STORE: begin
          imm      = imm_s;
          b_imm    = 1'b1;
          is_store = 1'b1;
          uses_rs1 = 1'b1;
          uses_rs2 = 1'b1;
          mem_size = funct3[1:0];
          bad      = funct3[2] || funct3[1:0] == 2'b11;
        end
        OP_IMM: begin
          imm      = imm_i;
          b_imm    = 1'b1;
          rf_we    = 1'b1;
          uses_rs1 = 1'b1;
          case (funct3)
            3'b000: alu_op = ALU_ADD;
            3'b010: alu_op = ALU_SLT;
            3'b011: alu_op = ALU_SLTU;
            3'b100: alu_op = ALU_XOR;
            3'b110: alu_op = ALU_OR;
            3'b111: alu_op = ALU_AND;
            3'b001: begin
              alu_op = ALU_SLL;
              bad    = funct7 != 7'b0000000;
            end
            default: begin
              alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
              bad    = funct7 != 7'b0000000 && funct7 != 7'b0100000;
            end
          endcase
        end
        OP_REG: begin
          rf_we    = 1'b1;
          uses_rs1 = 1'b1;
          uses_rs2 = 1'b1;
          if (funct7 == 7'b0000000) begin
            case (funct3)
              3'b000:  alu_op = ALU_ADD;
              3'b001:  alu_op = ALU_SLL;
              3'b010:  alu_op = ALU_SLT;
              3'b011:  alu_op = ALU_SLTU;
              3'b100:  alu_op = ALU_XOR;
              3'b101:  alu_op = ALU_SRL;
              3'b110:  alu_op = ALU_OR;
              default: alu_op = ALU_AND;
            endcase
          end else if (funct7 == 7'b0100000 && funct3 == 3'b000) begin
            alu_op = ALU_SUB;
          end else if (funct7 == 7'b0100000 && funct3 == 3'b101) begin
            alu_op = ALU_SRA;
          end else begin
            bad = 1'b1;
          end
        end
        OP_FENCE: begin
          bad = funct3 != 3'b000;
        end
        OP_SYSTEM: begin
          if (inst == 32'h00000073)      is_ecall  = 1'b1;
          else if (inst == 32'h00100073) is_ebreak = 1'b1;
          else                           bad       = 1'b1;
        end
        default: bad = 1'b1;
      endcase
    end

    if (bad) begin
      rf_we     = 1'b0;
      is_load   = 1'b0;
      is_store  = 1'b0;
      is_branch = 1'b0;
      is_jal    = 1'b0;
      is_jalr   = 1'b0;
      uses_rs1  = 1'b0;
      uses_rs2  = 1'b0;
    end
  end

  assign illegal = bad;
endmodule
