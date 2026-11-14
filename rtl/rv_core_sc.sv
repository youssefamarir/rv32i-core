`timescale 1ns/1ps
module rv_core_sc (
  input  logic        clk,
  input  logic        rst,
  output logic [31:0] i_addr,
  input  logic [31:0] i_rdata,
  input  logic        i_fault,
  output logic [31:0] d_addr,
  output logic        d_load,
  output logic        d_store,
  output logic [1:0]  d_size,
  output logic        d_unsigned,
  output logic [31:0] d_wdata,
  output logic        d_commit,
  input  logic [31:0] d_rdata,
  input  logic        d_misaligned,
  input  logic        d_access_fault,
  input  logic [31:0] d_lane_addr,
  input  logic [3:0]  d_be,
  input  logic [31:0] d_lane_data,
  output logic        ret_valid,
  output logic [31:0] ret_seq,
  output logic [31:0] ret_pc,
  output logic [31:0] ret_inst,
  output logic        ret_rd_we,
  output logic [4:0]  ret_rd,
  output logic [31:0] ret_rd_wdata,
  output logic        ret_st_valid,
  output logic [31:0] ret_st_addr,
  output logic [3:0]  ret_st_be,
  output logic [31:0] ret_st_data,
  output logic        stop_valid,
  output logic [3:0]  stop_cause,
  output logic [31:0] stop_pc,
  output logic        halted,
  output logic        rf_wen
);
  import rv_pkg::*;

  logic [31:0] pc_q, seq_q;
  logic        halted_q;
  logic        active;

  logic [4:0]  rs1, rs2, rd;
  logic [2:0]  funct3;
  logic [31:0] imm;
  logic [3:0]  alu_op;
  logic [1:0]  a_sel, wb_sel, mem_size;
  logic        b_imm, rf_we, is_load, is_store, mem_unsigned;
  logic        is_branch, is_jal, is_jalr, uses_rs1, uses_rs2;
  logic        illegal, is_ecall, is_ebreak;

  logic [31:0] rs1v, rs2v, alu_a, alu_b, alu_y, pc4, target, wb_data;
  logic        br_taken, take, target_mis;
  logic [3:0]  cause;

  assign active = !rst && !halted_q;
  assign i_addr = pc_q;

  rv_decode u_dec (
    .inst(i_rdata), .rs1(rs1), .rs2(rs2), .rd(rd), .funct3(funct3), .imm(imm),
    .alu_op(alu_op), .a_sel(a_sel), .b_imm(b_imm), .rf_we(rf_we), .wb_sel(wb_sel),
    .is_load(is_load), .is_store(is_store), .mem_size(mem_size), .mem_unsigned(mem_unsigned),
    .is_branch(is_branch), .is_jal(is_jal), .is_jalr(is_jalr),
    .uses_rs1(uses_rs1), .uses_rs2(uses_rs2),
    .illegal(illegal), .is_ecall(is_ecall), .is_ebreak(is_ebreak)
  );

  rv_regfile u_rf (
    .clk(clk), .ra1(rs1), .ra2(rs2), .rd1(rs1v), .rd2(rs2v),
    .we(rf_wen), .wa(rd), .wd(wb_data)
  );

  assign alu_a = (a_sel == A_PC) ? pc_q : (a_sel == A_ZERO) ? 32'h0 : rs1v;
  assign alu_b = b_imm ? imm : rs2v;

  rv_alu u_alu (.op(alu_op), .a(alu_a), .b(alu_b), .y(alu_y));
  rv_branch u_br (.funct3(funct3), .a(rs1v), .b(rs2v), .taken(br_taken));

  assign pc4        = pc_q + 32'd4;
  assign target     = is_jalr ? ((rs1v + imm) & ~32'h1) : (pc_q + imm);
  assign take       = is_jal | is_jalr | (is_branch & br_taken);
  assign target_mis = take & target[1];

  assign d_addr     = alu_y;
  assign d_load     = active & !i_fault & is_load;
  assign d_store    = active & !i_fault & is_store;
  assign d_size     = mem_size;
  assign d_unsigned = mem_unsigned;
  assign d_wdata    = rs2v;

  always @(*) begin
    cause = C_NONE;
    if (i_fault)                         cause = C_FETCH_ACCESS;
    else if (illegal)                    cause = C_ILLEGAL;
    else if (is_ecall)                   cause = C_ECALL;
    else if (is_ebreak)                  cause = C_EBREAK;
    else if (target_mis)                 cause = C_INST_MISALIGNED;
    else if (is_load && d_misaligned)    cause = C_LOAD_MISALIGNED;
    else if (is_load && d_access_fault)  cause = C_LOAD_ACCESS;
    else if (is_store && d_misaligned)   cause = C_STORE_MISALIGNED;
    else if (is_store && d_access_fault) cause = C_STORE_ACCESS;
  end

  assign ret_valid  = active && cause == C_NONE;
  assign stop_valid = active && cause != C_NONE;
  assign rf_wen     = ret_valid && rf_we && rd != 5'd0;
  assign d_commit   = ret_valid && is_store;
  assign wb_data    = (wb_sel == WB_MEM) ? d_rdata : (wb_sel == WB_PC4) ? pc4 : alu_y;

  assign ret_seq      = seq_q;
  assign ret_pc       = pc_q;
  assign ret_inst     = i_rdata;
  assign ret_rd_we    = rf_wen;
  assign ret_rd       = rd;
  assign ret_rd_wdata = wb_data;
  assign ret_st_valid = d_commit;
  assign ret_st_addr  = d_lane_addr;
  assign ret_st_be    = d_be;
  assign ret_st_data  = d_lane_data;
  assign stop_cause   = cause;
  assign stop_pc      = pc_q;
  assign halted       = halted_q;

  always_ff @(posedge clk) begin
    if (rst) begin
      pc_q     <= 32'h0;
      seq_q    <= 32'h0;
      halted_q <= 1'b0;
    end else if (active) begin
      if (stop_valid) begin
        halted_q <= 1'b1;
      end else begin
        pc_q  <= take ? target : pc4;
        seq_q <= seq_q + 32'd1;
      end
    end
  end
endmodule
