`timescale 1ns/1ps
module rv_core_pipe #(
  parameter int FORWARD = 1
) (
  input  logic         clk,
  input  logic         rst,
  output logic [31:0]  i_addr,
  input  logic [31:0]  i_rdata,
  input  logic         i_fault,
  output logic [31:0]  d_addr,
  output logic         d_load,
  output logic         d_store,
  output logic [1:0]   d_size,
  output logic         d_unsigned,
  output logic [31:0]  d_wdata,
  output logic         d_commit,
  input  logic [31:0]  d_rdata,
  input  logic         d_misaligned,
  input  logic         d_access_fault,
  input  logic [31:0]  d_lane_addr,
  input  logic [3:0]   d_be,
  input  logic [31:0]  d_lane_data,
  output logic         ret_valid,
  output logic [31:0]  ret_seq,
  output logic [31:0]  ret_pc,
  output logic [31:0]  ret_inst,
  output logic         ret_rd_we,
  output logic [4:0]   ret_rd,
  output logic [31:0]  ret_rd_wdata,
  output logic         ret_st_valid,
  output logic [31:0]  ret_st_addr,
  output logic [3:0]   ret_st_be,
  output logic [31:0]  ret_st_data,
  output logic         stop_valid,
  output logic [3:0]   stop_cause,
  output logic [31:0]  stop_pc,
  output logic         halted,
  output logic         rf_wen,
  output logic [31:0]  perf_stalls,
  output logic [31:0]  perf_flushes,
  output logic         tr_en,
  output logic         tr_ev_stall,
  output logic         tr_ev_redirect,
  output logic [127:0] tr_sample
);
  import rv_pkg::*;

  logic        halted_q;
  logic [31:0] pc_f, seq_q, cyc_q, stalls_q, flushes_q;

  logic        d_valid, d_ffault;
  logic [31:0] d_pc, d_inst;

  logic        e_valid, e_b_imm, e_rf_we, e_load, e_store, e_uns, e_branch, e_jal, e_jalr;
  logic        e_uses_rs1, e_uses_rs2;
  logic [31:0] e_pc, e_inst, e_imm, e_rs1v, e_rs2v;
  logic [4:0]  e_rs1, e_rs2, e_rd;
  logic [3:0]  e_alu_op, e_cause;
  logic [1:0]  e_a_sel, e_wb_sel, e_size;
  logic [2:0]  e_f3;

  logic        m_valid, m_rf_we, m_load, m_store, m_uns;
  logic [31:0] m_pc, m_inst, m_alu, m_sdata, m_pc4;
  logic [4:0]  m_rd;
  logic [1:0]  m_wb_sel, m_size;
  logic [3:0]  m_cause;

  logic        w_valid, w_rf_we, w_st_valid;
  logic [31:0] w_pc, w_inst, w_result, w_st_addr, w_st_data;
  logic [4:0]  w_rd;
  logic [3:0]  w_cause, w_st_be;

  logic [4:0]  id_rs1, id_rs2, id_rd;
  logic [2:0]  id_f3;
  logic [31:0] id_imm, id_rf1, id_rf2, id_rs1v, id_rs2v;
  logic [3:0]  id_alu_op, id_cause;
  logic [1:0]  id_a_sel, id_wb_sel, id_size;
  logic        id_b_imm, id_rf_we, id_load, id_store, id_uns, id_branch, id_jal, id_jalr;
  logic        id_uses_rs1, id_uses_rs2, id_illegal, id_ecall, id_ebreak;

  logic        hit1_e, hit2_e, hit1_m, hit2_m;
  logic [1:0]  stall_reason;
  logic        stall, stall_eff;

  logic [1:0]  fwd_a, fwd_b;
  logic [31:0] m_fwd, ex_rs1, ex_rs2, ex_a, ex_b, ex_alu, ex_target;
  logic        ex_br, ex_take, ex_redirect;
  logic [3:0]  ex_cause;

  logic [3:0]  mem_cause;
  logic [31:0] m_result;

  logic        kill_m, kill_e, kill_d;
  logic        wb_stop, wb_retire, wb_rf_wen;

  assign i_addr = pc_f;

  rv_decode u_dec (
    .inst(d_inst), .rs1(id_rs1), .rs2(id_rs2), .rd(id_rd), .funct3(id_f3), .imm(id_imm),
    .alu_op(id_alu_op), .a_sel(id_a_sel), .b_imm(id_b_imm), .rf_we(id_rf_we), .wb_sel(id_wb_sel),
    .is_load(id_load), .is_store(id_store), .mem_size(id_size), .mem_unsigned(id_uns),
    .is_branch(id_branch), .is_jal(id_jal), .is_jalr(id_jalr),
    .uses_rs1(id_uses_rs1), .uses_rs2(id_uses_rs2),
    .illegal(id_illegal), .is_ecall(id_ecall), .is_ebreak(id_ebreak)
  );

  rv_regfile u_rf (
    .clk(clk), .ra1(id_rs1), .ra2(id_rs2), .rd1(id_rf1), .rd2(id_rf2),
    .we(wb_rf_wen), .wa(w_rd), .wd(w_result)
  );

  assign id_rs1v = (wb_rf_wen && w_rd == id_rs1) ? w_result : id_rf1;
  assign id_rs2v = (wb_rf_wen && w_rd == id_rs2) ? w_result : id_rf2;

  always @(*) begin
    id_cause = C_NONE;
    if (d_ffault)        id_cause = C_FETCH_ACCESS;
    else if (id_illegal) id_cause = C_ILLEGAL;
    else if (id_ecall)   id_cause = C_ECALL;
    else if (id_ebreak)  id_cause = C_EBREAK;
  end

  assign hit1_e = id_uses_rs1 && id_rs1 != 5'd0 && e_valid && e_rf_we && e_rd == id_rs1;
  assign hit2_e = id_uses_rs2 && id_rs2 != 5'd0 && e_valid && e_rf_we && e_rd == id_rs2;
  assign hit1_m = id_uses_rs1 && id_rs1 != 5'd0 && m_valid && m_rf_we && m_rd == id_rs1;
  assign hit2_m = id_uses_rs2 && id_rs2 != 5'd0 && m_valid && m_rf_we && m_rd == id_rs2;

  always @(*) begin
    stall_reason = ST_NONE;
    if (d_valid) begin
      if (FORWARD != 0) begin
        if (e_load && (hit1_e || hit2_e)) stall_reason = ST_LOAD_USE;
      end else begin
        if (hit1_e || hit2_e || hit1_m || hit2_m) stall_reason = ST_RAW;
      end
    end
  end

  assign stall     = stall_reason != ST_NONE;
  assign stall_eff = stall && !kill_d;

  assign fwd_a = (FORWARD == 0 || !e_uses_rs1 || e_rs1 == 5'd0) ? FW_REG :
                 (m_valid && m_rf_we && m_rd == e_rs1) ? FW_MEM :
                 (w_valid && w_rf_we && w_rd == e_rs1) ? FW_WB : FW_REG;
  assign fwd_b = (FORWARD == 0 || !e_uses_rs2 || e_rs2 == 5'd0) ? FW_REG :
                 (m_valid && m_rf_we && m_rd == e_rs2) ? FW_MEM :
                 (w_valid && w_rf_we && w_rd == e_rs2) ? FW_WB : FW_REG;

  assign m_fwd  = (m_wb_sel == WB_PC4) ? m_pc4 : m_alu;
  assign ex_rs1 = (fwd_a == FW_MEM) ? m_fwd : (fwd_a == FW_WB) ? w_result : e_rs1v;
  assign ex_rs2 = (fwd_b == FW_MEM) ? m_fwd : (fwd_b == FW_WB) ? w_result : e_rs2v;
  assign ex_a   = (e_a_sel == A_PC) ? e_pc : (e_a_sel == A_ZERO) ? 32'h0 : ex_rs1;
  assign ex_b   = e_b_imm ? e_imm : ex_rs2;

  rv_alu u_alu (.op(e_alu_op), .a(ex_a), .b(ex_b), .y(ex_alu));
  rv_branch u_br (.funct3(e_f3), .a(ex_rs1), .b(ex_rs2), .taken(ex_br));

  assign ex_target = e_jalr ? ((ex_rs1 + e_imm) & ~32'h1) : (e_pc + e_imm);
  assign ex_take   = e_jal | e_jalr | (e_branch & ex_br);

  always @(*) begin
    ex_cause = e_cause;
    if (e_cause == C_NONE && ex_take && ex_target[1]) ex_cause = C_INST_MISALIGNED;
  end

  assign ex_redirect = e_valid && ex_take && ex_cause == C_NONE && !kill_e;

  assign d_addr     = m_alu;
  assign d_load     = m_valid && m_load && m_cause == C_NONE && !kill_m && !rst;
  assign d_store    = m_valid && m_store && m_cause == C_NONE && !kill_m && !rst;
  assign d_size     = m_size;
  assign d_unsigned = m_uns;
  assign d_wdata    = m_sdata;

  always @(*) begin
    mem_cause = m_cause;
    if (m_cause == C_NONE) begin
      if (m_load && d_misaligned)        mem_cause = C_LOAD_MISALIGNED;
      else if (m_load && d_access_fault) mem_cause = C_LOAD_ACCESS;
      else if (m_store && d_misaligned)  mem_cause = C_STORE_MISALIGNED;
      else if (m_store && d_access_fault) mem_cause = C_STORE_ACCESS;
    end
  end

  assign d_commit = d_store && mem_cause == C_NONE;
  assign m_result = (m_wb_sel == WB_MEM) ? d_rdata : (m_wb_sel == WB_PC4) ? m_pc4 : m_alu;

  assign kill_m = (w_valid && w_cause != C_NONE) || halted_q;
  assign kill_e = kill_m || (m_valid && mem_cause != C_NONE);
  assign kill_d = kill_e || ex_redirect;

  assign wb_stop   = w_valid && w_cause != C_NONE && !halted_q && !rst;
  assign wb_retire = w_valid && w_cause == C_NONE && !halted_q && !rst;
  assign wb_rf_wen = wb_retire && w_rf_we && w_rd != 5'd0;

  assign ret_valid    = wb_retire;
  assign ret_seq      = seq_q;
  assign ret_pc       = w_pc;
  assign ret_inst     = w_inst;
  assign ret_rd_we    = wb_rf_wen;
  assign ret_rd       = w_rd;
  assign ret_rd_wdata = w_result;
  assign ret_st_valid = wb_retire && w_st_valid;
  assign ret_st_addr  = w_st_addr;
  assign ret_st_be    = w_st_be;
  assign ret_st_data  = w_st_data;
  assign stop_valid   = wb_stop;
  assign stop_cause   = w_cause;
  assign stop_pc      = w_pc;
  assign halted       = halted_q;
  assign rf_wen       = wb_rf_wen;
  assign perf_stalls  = stalls_q;
  assign perf_flushes = flushes_q;

  assign tr_en          = !rst && !halted_q;
  assign tr_ev_stall    = stall_eff;
  assign tr_ev_redirect = ex_redirect;
  assign tr_sample = {
    cyc_q[15:0],
    !kill_e, d_valid, e_valid, m_valid, w_valid,
    pc_f[15:0],
    d_valid ? d_pc[15:0] : 16'h0,
    e_valid ? e_pc[15:0] : 16'h0,
    m_valid ? m_pc[15:0] : 16'h0,
    w_valid ? w_pc[15:0] : 16'h0,
    e_valid ? fwd_a : FW_REG,
    e_valid ? fwd_b : FW_REG,
    stall_eff ? stall_reason : ST_NONE,
    ex_redirect,
    ex_redirect ? ex_target[15:0] : 16'h0,
    wb_stop ? w_cause : C_NONE
  };

  always_ff @(posedge clk) begin
    if (rst) begin
      pc_f      <= 32'h0;
      seq_q     <= 32'h0;
      cyc_q     <= 32'h0;
      stalls_q  <= 32'h0;
      flushes_q <= 32'h0;
      halted_q  <= 1'b0;
      d_valid   <= 1'b0;
      e_valid   <= 1'b0;
      m_valid   <= 1'b0;
      w_valid   <= 1'b0;
    end else begin
      cyc_q <= cyc_q + 32'd1;
      if (wb_stop)     halted_q  <= 1'b1;
      if (wb_retire)   seq_q     <= seq_q + 32'd1;
      if (stall_eff)   stalls_q  <= stalls_q + 32'd1;
      if (ex_redirect) flushes_q <= flushes_q + 32'd1;

      if (ex_redirect)                pc_f <= ex_target;
      else if (!stall_eff && !kill_e) pc_f <= pc_f + 32'd4;

      if (kill_d) begin
        d_valid <= 1'b0;
      end else if (!stall_eff) begin
        d_valid  <= 1'b1;
        d_pc     <= pc_f;
        d_inst   <= i_rdata;
        d_ffault <= i_fault;
      end

      if (kill_d || stall_eff) begin
        e_valid <= 1'b0;
      end else begin
        e_valid    <= d_valid;
        e_pc       <= d_pc;
        e_inst     <= d_inst;
        e_imm      <= id_imm;
        e_rs1      <= id_rs1;
        e_rs2      <= id_rs2;
        e_rd       <= id_rd;
        e_rs1v     <= id_rs1v;
        e_rs2v     <= id_rs2v;
        e_alu_op   <= id_alu_op;
        e_a_sel    <= id_a_sel;
        e_b_imm    <= id_b_imm;
        e_rf_we    <= id_rf_we;
        e_wb_sel   <= id_wb_sel;
        e_load     <= id_load;
        e_store    <= id_store;
        e_size     <= id_size;
        e_uns      <= id_uns;
        e_branch   <= id_branch;
        e_jal      <= id_jal;
        e_jalr     <= id_jalr;
        e_f3       <= id_f3;
        e_uses_rs1 <= id_uses_rs1;
        e_uses_rs2 <= id_uses_rs2;
        e_cause    <= id_cause;
      end

      if (kill_e) begin
        m_valid <= 1'b0;
      end else begin
        m_valid  <= e_valid;
        m_pc     <= e_pc;
        m_inst   <= e_inst;
        m_rd     <= e_rd;
        m_rf_we  <= e_rf_we;
        m_wb_sel <= e_wb_sel;
        m_load   <= e_load;
        m_store  <= e_store;
        m_size   <= e_size;
        m_uns    <= e_uns;
        m_alu    <= ex_alu;
        m_sdata  <= ex_rs2;
        m_pc4    <= e_pc + 32'd4;
        m_cause  <= ex_cause;
      end

      if (kill_m) begin
        w_valid <= 1'b0;
      end else begin
        w_valid    <= m_valid;
        w_pc       <= m_pc;
        w_inst     <= m_inst;
        w_rd       <= m_rd;
        w_rf_we    <= m_rf_we;
        w_result   <= m_result;
        w_cause    <= mem_cause;
        w_st_valid <= d_commit;
        w_st_addr  <= d_lane_addr;
        w_st_be    <= d_be;
        w_st_data  <= d_lane_data;
      end
    end
  end
endmodule
