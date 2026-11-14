`timescale 1ns/1ps
module rv_top #(
  parameter int PIPELINE    = 0,
  parameter int FORWARD     = 1,
  parameter int TRACE_DEPTH = 16,
  parameter int TAW         = $clog2(TRACE_DEPTH)
) (
  input  logic           clk,
  input  logic           rst,
  output logic           ret_valid,
  output logic [31:0]    ret_seq,
  output logic [31:0]    ret_pc,
  output logic [31:0]    ret_inst,
  output logic           ret_rd_we,
  output logic [4:0]     ret_rd,
  output logic [31:0]    ret_rd_wdata,
  output logic           ret_st_valid,
  output logic [31:0]    ret_st_addr,
  output logic [3:0]     ret_st_be,
  output logic [31:0]    ret_st_data,
  output logic           stop_valid,
  output logic [3:0]     stop_cause,
  output logic [31:0]    stop_pc,
  output logic           halted,
  output logic [31:0]    sig_value,
  output logic           sig_written,
  output logic [31:0]    sig_writes,
  output logic [31:0]    dbg_fetch_pc,
  output logic [31:0]    dbg_fetch_inst,
  output logic           dbg_rf_we,
  output logic           dbg_commit,
  output logic [31:0]    dbg_d_addr,
  output logic [31:0]    perf_stalls,
  output logic [31:0]    perf_flushes,
  input  logic [1:0]     tr_mask,
  input  logic [7:0]     tr_post,
  input  logic           tr_rearm,
  input  logic [TAW-1:0] tr_rd_addr,
  output logic [127:0]   tr_rd_data,
  output logic [TAW-1:0] tr_wptr,
  output logic           tr_wrapped,
  output logic           tr_triggered,
  output logic           tr_frozen,
  output logic [TAW-1:0] tr_trig_idx
);
  logic [31:0] i_addr, i_rdata, d_addr, d_wdata, d_rdata, d_lane_addr, d_lane_data;
  logic        i_fault, d_load, d_store, d_unsigned, d_commit, d_misaligned, d_access_fault;
  logic [1:0]  d_size;
  logic [3:0]  d_be;

  rv_mem u_mem (
    .clk(clk), .rst(rst),
    .i_addr(i_addr), .i_rdata(i_rdata), .i_fault(i_fault),
    .d_addr(d_addr), .d_load(d_load), .d_store(d_store), .d_size(d_size),
    .d_unsigned(d_unsigned), .d_wdata(d_wdata), .d_commit(d_commit),
    .d_rdata(d_rdata), .d_misaligned(d_misaligned), .d_access_fault(d_access_fault),
    .d_lane_addr(d_lane_addr), .d_be(d_be), .d_lane_data(d_lane_data),
    .sig_value(sig_value), .sig_written(sig_written), .sig_writes(sig_writes)
  );

  assign dbg_fetch_pc   = i_addr;
  assign dbg_fetch_inst = i_rdata;
  assign dbg_commit     = d_commit;
  assign dbg_d_addr     = d_addr;

  generate
    if (PIPELINE != 0) begin : g_pipe
      logic         tr_en, tr_ev_stall, tr_ev_redirect;
      logic [127:0] tr_sample;

      rv_core_pipe #(.FORWARD(FORWARD)) u_core (
        .clk(clk), .rst(rst),
        .i_addr(i_addr), .i_rdata(i_rdata), .i_fault(i_fault),
        .d_addr(d_addr), .d_load(d_load), .d_store(d_store), .d_size(d_size),
        .d_unsigned(d_unsigned), .d_wdata(d_wdata), .d_commit(d_commit),
        .d_rdata(d_rdata), .d_misaligned(d_misaligned), .d_access_fault(d_access_fault),
        .d_lane_addr(d_lane_addr), .d_be(d_be), .d_lane_data(d_lane_data),
        .ret_valid(ret_valid), .ret_seq(ret_seq), .ret_pc(ret_pc), .ret_inst(ret_inst),
        .ret_rd_we(ret_rd_we), .ret_rd(ret_rd), .ret_rd_wdata(ret_rd_wdata),
        .ret_st_valid(ret_st_valid), .ret_st_addr(ret_st_addr), .ret_st_be(ret_st_be),
        .ret_st_data(ret_st_data),
        .stop_valid(stop_valid), .stop_cause(stop_cause), .stop_pc(stop_pc),
        .halted(halted), .rf_wen(dbg_rf_we),
        .perf_stalls(perf_stalls), .perf_flushes(perf_flushes),
        .tr_en(tr_en), .tr_ev_stall(tr_ev_stall), .tr_ev_redirect(tr_ev_redirect),
        .tr_sample(tr_sample)
      );

      rv_trace #(.DEPTH(TRACE_DEPTH), .W(128)) u_trace (
        .clk(clk), .rst(rst), .en(tr_en), .sample(tr_sample),
        .ev_stall(tr_ev_stall), .ev_redirect(tr_ev_redirect),
        .cfg_mask(tr_mask), .cfg_post(tr_post), .rearm(tr_rearm),
        .rd_addr(tr_rd_addr), .rd_data(tr_rd_data),
        .wptr(tr_wptr), .wrapped(tr_wrapped), .triggered(tr_triggered),
        .frozen(tr_frozen), .trig_idx(tr_trig_idx)
      );
    end else begin : g_sc
      rv_core_sc u_core (
        .clk(clk), .rst(rst),
        .i_addr(i_addr), .i_rdata(i_rdata), .i_fault(i_fault),
        .d_addr(d_addr), .d_load(d_load), .d_store(d_store), .d_size(d_size),
        .d_unsigned(d_unsigned), .d_wdata(d_wdata), .d_commit(d_commit),
        .d_rdata(d_rdata), .d_misaligned(d_misaligned), .d_access_fault(d_access_fault),
        .d_lane_addr(d_lane_addr), .d_be(d_be), .d_lane_data(d_lane_data),
        .ret_valid(ret_valid), .ret_seq(ret_seq), .ret_pc(ret_pc), .ret_inst(ret_inst),
        .ret_rd_we(ret_rd_we), .ret_rd(ret_rd), .ret_rd_wdata(ret_rd_wdata),
        .ret_st_valid(ret_st_valid), .ret_st_addr(ret_st_addr), .ret_st_be(ret_st_be),
        .ret_st_data(ret_st_data),
        .stop_valid(stop_valid), .stop_cause(stop_cause), .stop_pc(stop_pc),
        .halted(halted), .rf_wen(dbg_rf_we)
      );

      assign perf_stalls  = 32'h0;
      assign perf_flushes = 32'h0;
      assign tr_rd_data   = 128'h0;
      assign tr_wptr      = '0;
      assign tr_wrapped   = 1'b0;
      assign tr_triggered = 1'b0;
      assign tr_frozen    = 1'b0;
      assign tr_trig_idx  = '0;
    end
  endgenerate
endmodule
