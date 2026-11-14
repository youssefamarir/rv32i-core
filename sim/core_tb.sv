`timescale 1ns/1ps
module core_tb;
  parameter int PIPELINE = 0;
  parameter int FORWARD  = 1;
  localparam int TDEPTH  = 16;
  localparam int TAW     = $clog2(TDEPTH);

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic           ret_valid, ret_rd_we, ret_st_valid, stop_valid, halted;
  logic [31:0]    ret_seq, ret_pc, ret_inst, ret_rd_wdata, ret_st_addr, ret_st_data, stop_pc;
  logic [4:0]     ret_rd;
  logic [3:0]     ret_st_be, stop_cause;
  logic [31:0]    sig_value, sig_writes;
  logic           sig_written;
  logic [31:0]    fetch_pc, fetch_inst, d_addr, perf_stalls, perf_flushes;
  logic           rf_we, st_commit;
  logic [1:0]     tr_mask;
  logic [7:0]     tr_post;
  logic           tr_rearm;
  logic [TAW-1:0] tr_rd_addr, tr_wptr, tr_trig_idx;
  logic [127:0]   tr_rd_data;
  logic           tr_wrapped, tr_triggered, tr_frozen;

  rv_top #(.PIPELINE(PIPELINE), .FORWARD(FORWARD), .TRACE_DEPTH(TDEPTH)) dut (
    .clk(clk), .rst(rst),
    .ret_valid(ret_valid), .ret_seq(ret_seq), .ret_pc(ret_pc), .ret_inst(ret_inst),
    .ret_rd_we(ret_rd_we), .ret_rd(ret_rd), .ret_rd_wdata(ret_rd_wdata),
    .ret_st_valid(ret_st_valid), .ret_st_addr(ret_st_addr), .ret_st_be(ret_st_be),
    .ret_st_data(ret_st_data),
    .stop_valid(stop_valid), .stop_cause(stop_cause), .stop_pc(stop_pc), .halted(halted),
    .sig_value(sig_value), .sig_written(sig_written), .sig_writes(sig_writes),
    .dbg_fetch_pc(fetch_pc), .dbg_fetch_inst(fetch_inst), .dbg_rf_we(rf_we),
    .dbg_commit(st_commit), .dbg_d_addr(d_addr),
    .perf_stalls(perf_stalls), .perf_flushes(perf_flushes),
    .tr_mask(tr_mask), .tr_post(tr_post), .tr_rearm(tr_rearm),
    .tr_rd_addr(tr_rd_addr), .tr_rd_data(tr_rd_data), .tr_wptr(tr_wptr),
    .tr_wrapped(tr_wrapped), .tr_triggered(tr_triggered), .tr_frozen(tr_frozen),
    .tr_trig_idx(tr_trig_idx)
  );

  string       hexfile, vcdfile, tracefile, tdumpfile;
  int          timeout, exp_cause, fd, cycles, retired, i, tmp;
  logic [31:0] exp_sig, exp_pc;
  bit          chk_sig, chk_pc, no_sig_write, use_vcd, quiet, done;

  initial begin
    if (!$value$plusargs("hex=%s", hexfile)) hexfile = "build/smoke.hex";
    if (!$value$plusargs("vcd=%s", vcdfile)) vcdfile = "build/smoke.vcd";
    use_vcd = !$test$plusargs("novcd");
    if (!$value$plusargs("trace=%s", tracefile)) tracefile = "";
    if (!$value$plusargs("tdump=%s", tdumpfile)) tdumpfile = "";
    if (!$value$plusargs("timeout=%d", timeout)) timeout = 100;
    if (!$value$plusargs("cause=%d", exp_cause)) exp_cause = 1;
    chk_sig = 1'b1;
    if (!$value$plusargs("sig=%h", exp_sig)) exp_sig = 32'h0000000c;
    if ($test$plusargs("nosig")) chk_sig = 1'b0;
    no_sig_write = $test$plusargs("nosigwrite");
    chk_pc = $value$plusargs("stoppc=%h", exp_pc);
    if (!$value$plusargs("tmask=%d", tmp)) tmp = 0;
    tr_mask = tmp[1:0];
    if (!$value$plusargs("tpost=%d", tmp)) tmp = 4;
    tr_post  = tmp[7:0];
    tr_rearm = 1'b0;
    tr_rd_addr = '0;
    quiet = tracefile != "";
    done = 1'b0;
    cycles = 0;
    retired = 0;

    fd = 0;
    if (tracefile != "") begin
      fd = $fopen(tracefile, "w");
      if (fd == 0) $fatal(1, "FAIL cannot open trace file %s", tracefile);
    end

    for (i = 0; i < 1024; i = i + 1) begin
      dut.u_mem.ram[i] = 32'h0;
      dut.u_mem.rom[i] = 32'h0;
    end
    $readmemh(hexfile, dut.u_mem.rom);

    if (use_vcd) begin
      $dumpfile(vcdfile);
      $dumpvars(0, core_tb);
    end

    rst = 1'b1;
    repeat (2) @(posedge clk);
    @(negedge clk) rst = 1'b0;
  end

  task automatic emit_line(input string line);
    if (fd != 0) $fdisplay(fd, "%s", line);
    if (!quiet) $display("%s", line);
  endtask

  task automatic emit_retire();
    string s, r, w;
    if (ret_rd_we) r = $sformatf("%0d %h", ret_rd, ret_rd_wdata);
    else           r = "-- --------";
    if (ret_st_valid) w = $sformatf("%h %h %h", ret_st_addr, ret_st_be, ret_st_data);
    else              w = "-------- - --------";
    s = $sformatf("R %0d %h %h %s %s", ret_seq, ret_pc, ret_inst, r, w);
    emit_line(s);
  endtask

  task automatic dump_trace();
    int tf, k;
    tf = $fopen(tdumpfile, "w");
    if (tf == 0) $fatal(1, "FAIL cannot open trace dump %s", tdumpfile);
    $fdisplay(tf, "TSTATUS depth=%0d wptr=%0d wrapped=%0d triggered=%0d frozen=%0d trig_idx=%0d mask=%0d post=%0d",
              TDEPTH, tr_wptr, tr_wrapped, tr_triggered, tr_frozen, tr_trig_idx, tr_mask, tr_post);
    for (k = 0; k < TDEPTH; k = k + 1) begin
      tr_rd_addr = k[TAW-1:0];
      #0.1;
      $fdisplay(tf, "T %0d %h", k, tr_rd_data);
    end
    $fclose(tf);
  endtask

  task automatic finish_run();
    $display("STOP cause=%0d pc=%h", stop_cause, stop_pc);
    $display("SIG written=%0d value=%h writes=%0d", sig_written, sig_value, sig_writes);
    $display("PERF cycles=%0d retired=%0d stalls=%0d flushes=%0d", cycles, retired, perf_stalls, perf_flushes);
    if (fd != 0) $fclose(fd);
    if (PIPELINE != 0 && tdumpfile != "") dump_trace();
    if (stop_cause !== exp_cause[3:0])
      $fatal(1, "FAIL stop cause %0d, expected %0d at pc %h", stop_cause, exp_cause, stop_pc);
    if (chk_pc && stop_pc !== exp_pc)
      $fatal(1, "FAIL stop pc %h, expected %h", stop_pc, exp_pc);
    if (chk_sig && sig_written !== 1'b1)
      $fatal(1, "FAIL signature was never written");
    if (chk_sig && sig_value !== exp_sig)
      $fatal(1, "FAIL signature %h, expected %h", sig_value, exp_sig);
    if (no_sig_write && sig_written !== 1'b0)
      $fatal(1, "FAIL signature written but no write was expected");
    $display("PASS");
    $finish;
  endtask

  always @(posedge clk) begin
    if (rst) begin
      if (ret_valid === 1'b1 || stop_valid === 1'b1 || rf_we === 1'b1 || st_commit === 1'b1)
        $fatal(1, "FAIL architectural activity during reset");
    end else if (!done) begin
      cycles = cycles + 1;
      if (cycles == 1 && fetch_pc !== 32'h0)
        $fatal(1, "FAIL first fetch after reset at %h", fetch_pc);
      if (ret_valid === 1'b1 && stop_valid === 1'b1)
        $fatal(1, "FAIL retire and stop in the same cycle at pc %h", ret_pc);
      if (ret_valid === 1'b1) begin
        emit_retire();
        retired = retired + 1;
      end
      if (stop_valid === 1'b1) begin
        if (rf_we === 1'b1 || st_commit === 1'b1)
          $fatal(1, "FAIL stopping instruction at %h has an architectural write", stop_pc);
        emit_line($sformatf("S %0d %h", stop_cause, stop_pc));
        done = 1'b1;
        finish_run();
      end else if (cycles >= timeout) begin
        $display("STOP cause=timeout pc=%h", fetch_pc);
        $display("PERF cycles=%0d retired=%0d stalls=%0d flushes=%0d", cycles, retired, perf_stalls, perf_flushes);
        if (fd != 0) $fclose(fd);
        $fatal(1, "FAIL timeout after %0d cycles", cycles);
      end
    end
  end
endmodule
