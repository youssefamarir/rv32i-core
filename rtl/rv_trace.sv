`timescale 1ns/1ps
module rv_trace #(
  parameter int DEPTH = 16,
  parameter int W     = 128,
  parameter int AW    = $clog2(DEPTH)
) (
  input  logic          clk,
  input  logic          rst,
  input  logic          en,
  input  logic [W-1:0]  sample,
  input  logic          ev_stall,
  input  logic          ev_redirect,
  input  logic [1:0]    cfg_mask,
  input  logic [7:0]    cfg_post,
  input  logic          rearm,
  input  logic [AW-1:0] rd_addr,
  output logic [W-1:0]  rd_data,
  output logic [AW-1:0] wptr,
  output logic          wrapped,
  output logic          triggered,
  output logic          frozen,
  output logic [AW-1:0] trig_idx
);
  logic [W-1:0]  mem [0:DEPTH-1];
  logic [AW-1:0] wptr_q, trig_q;
  logic          wrapped_q, trig_f, frozen_q;
  logic [7:0]    post_left;
  logic          hit, write;

  assign hit   = |(cfg_mask & {ev_redirect, ev_stall});
  assign write = en && !frozen_q;

  always @(posedge clk) begin
    if (rst) begin
      wptr_q    <= '0;
      trig_q    <= '0;
      wrapped_q <= 1'b0;
      trig_f    <= 1'b0;
      frozen_q  <= 1'b0;
      post_left <= 8'd0;
    end else if (rearm) begin
      trig_f    <= 1'b0;
      frozen_q  <= 1'b0;
      post_left <= 8'd0;
    end else if (write) begin
      mem[wptr_q] <= sample;
      wptr_q      <= wptr_q + 1'b1;
      if (wptr_q == AW'(DEPTH - 1)) wrapped_q <= 1'b1;
      if (!trig_f && hit) begin
        trig_f    <= 1'b1;
        trig_q    <= wptr_q;
        post_left <= cfg_post;
        if (cfg_post == 8'd0) frozen_q <= 1'b1;
      end else if (trig_f) begin
        post_left <= post_left - 8'd1;
        if (post_left == 8'd1) frozen_q <= 1'b1;
      end
    end
  end

  assign rd_data   = mem[rd_addr];
  assign wptr      = wptr_q;
  assign wrapped   = wrapped_q;
  assign triggered = trig_f;
  assign frozen    = frozen_q;
  assign trig_idx  = trig_q;
endmodule
