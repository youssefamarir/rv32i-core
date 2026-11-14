`timescale 1ns/1ps
module trace_tb;
  localparam int DEPTH = 8;
  localparam int AW    = 3;

  logic          clk = 1'b0;
  logic          rst = 1'b1;
  logic          en = 1'b0;
  logic [15:0]   sample = 16'h0;
  logic          ev_stall = 1'b0;
  logic          ev_redirect = 1'b0;
  logic [1:0]    cfg_mask = 2'b00;
  logic [7:0]    cfg_post = 8'd0;
  logic          rearm = 1'b0;
  logic [AW-1:0] rd_addr = '0;
  logic [15:0]   rd_data;
  logic [AW-1:0] wptr, trig_idx;
  logic          wrapped, triggered, frozen;
  int            errors = 0;

  always #5 clk = ~clk;

  rv_trace #(.DEPTH(DEPTH), .W(16)) dut (
    .clk(clk), .rst(rst), .en(en), .sample(sample),
    .ev_stall(ev_stall), .ev_redirect(ev_redirect),
    .cfg_mask(cfg_mask), .cfg_post(cfg_post), .rearm(rearm),
    .rd_addr(rd_addr), .rd_data(rd_data),
    .wptr(wptr), .wrapped(wrapped), .triggered(triggered), .frozen(frozen), .trig_idx(trig_idx)
  );

  task automatic tick(input logic [15:0] value, input logic st, input logic rd);
    sample      = value;
    ev_stall    = st;
    ev_redirect = rd;
    @(posedge clk);
    #1;
    ev_stall    = 1'b0;
    ev_redirect = 1'b0;
  endtask

  task automatic expect_eq(input string what, input int got, input int want);
    if (got !== want) begin
      $display("FAIL %s: got %0d expected %0d", what, got, want);
      errors = errors + 1;
    end
  endtask

  task automatic expect_slot(input int slot, input int want);
    rd_addr = slot[AW-1:0];
    #1;
    expect_eq($sformatf("slot %0d", slot), rd_data, want);
  endtask

  initial begin
    int k;
    @(posedge clk);
    @(posedge clk);
    #1 rst = 1'b0;
    expect_eq("reset wptr", wptr, 0);
    expect_eq("reset wrapped", wrapped, 0);
    expect_eq("reset triggered", triggered, 0);
    expect_eq("reset frozen", frozen, 0);

    en = 1'b1;
    for (k = 0; k < 5; k = k + 1) tick(16'd100 + k[15:0], 1'b0, 1'b0);
    expect_eq("capture wptr", wptr, 5);
    expect_eq("capture wrapped", wrapped, 0);
    for (k = 0; k < 5; k = k + 1) expect_slot(k, 100 + k);

    for (k = 5; k < 11; k = k + 1) tick(16'd100 + k[15:0], 1'b0, 1'b0);
    expect_eq("wrap wptr", wptr, 3);
    expect_eq("wrap flag", wrapped, 1);
    for (k = 0; k < 3; k = k + 1) expect_slot(k, 108 + k);
    for (k = 3; k < 8; k = k + 1) expect_slot(k, 100 + k);

    en = 1'b0;
    tick(16'd999, 1'b0, 1'b0);
    expect_eq("disabled wptr", wptr, 3);
    en = 1'b1;

    cfg_mask = 2'b01;
    cfg_post = 8'd3;
    tick(16'd200, 1'b0, 1'b1);
    expect_eq("masked event ignored", triggered, 0);
    tick(16'd201, 1'b1, 1'b0);
    expect_eq("trigger fired", triggered, 1);
    expect_eq("trigger index", trig_idx, 4);
    expect_eq("not frozen at trigger", frozen, 0);
    tick(16'd202, 1'b1, 1'b0);
    tick(16'd203, 1'b0, 1'b0);
    expect_eq("not frozen before window ends", frozen, 0);
    tick(16'd204, 1'b0, 1'b0);
    expect_eq("frozen after post window", frozen, 1);
    expect_eq("wptr after freeze", wptr, 0);
    tick(16'd205, 1'b1, 1'b0);
    tick(16'd206, 1'b0, 1'b0);
    expect_eq("wptr held while frozen", wptr, 0);
    expect_slot(3, 200);
    expect_slot(4, 201);
    expect_slot(5, 202);
    expect_slot(6, 203);
    expect_slot(7, 204);
    expect_slot(0, 108);

    rearm = 1'b1;
    tick(16'd300, 1'b0, 1'b0);
    rearm = 1'b0;
    expect_eq("rearm clears triggered", triggered, 0);
    expect_eq("rearm clears frozen", frozen, 0);
    expect_eq("rearm keeps wptr", wptr, 0);
    cfg_mask = 2'b10;
    cfg_post = 8'd0;
    tick(16'd301, 1'b0, 1'b0);
    tick(16'd302, 1'b1, 1'b0);
    expect_eq("stall ignored with redirect mask", triggered, 0);
    tick(16'd303, 1'b0, 1'b1);
    expect_eq("second trigger", triggered, 1);
    expect_eq("second trigger index", trig_idx, 2);
    expect_eq("post 0 freezes on trigger", frozen, 1);
    tick(16'd304, 1'b0, 1'b0);
    expect_eq("no capture after post 0 freeze", wptr, 3);
    expect_slot(2, 303);

    rst = 1'b1;
    tick(16'd400, 1'b0, 1'b0);
    rst = 1'b0;
    expect_eq("reset clears wptr", wptr, 0);
    expect_eq("reset clears wrapped", wrapped, 0);
    expect_eq("reset clears triggered", triggered, 0);
    expect_eq("reset clears frozen", frozen, 0);
    tick(16'd500, 1'b0, 1'b0);
    expect_slot(0, 500);

    if (errors != 0) $fatal(1, "FAIL trace_tb with %0d errors", errors);
    $display("PASS trace_tb");
    $finish;
  end
endmodule
