`timescale 1ns/1ps
module rv_mem (
  input  logic        clk,
  input  logic        rst,
  input  logic [31:0] i_addr,
  output logic [31:0] i_rdata,
  output logic        i_fault,
  input  logic [31:0] d_addr,
  input  logic        d_load,
  input  logic        d_store,
  input  logic [1:0]  d_size,
  input  logic        d_unsigned,
  input  logic [31:0] d_wdata,
  input  logic        d_commit,
  output logic [31:0] d_rdata,
  output logic        d_misaligned,
  output logic        d_access_fault,
  output logic [31:0] d_lane_addr,
  output logic [3:0]  d_be,
  output logic [31:0] d_lane_data,
  output logic [31:0] sig_value,
  output logic        sig_written,
  output logic [31:0] sig_writes
);
  logic [31:0] rom [0:1023];
  logic [31:0] ram [0:1023];
  logic [31:0] sig_q;
  logic        sig_w_q;
  logic [31:0] sig_n_q;

  logic        i_in_rom;
  logic        in_rom, in_ram, in_sig, req, mis, mapped;
  logic [31:0] rom_word, ram_word, rword, rsh;

  assign i_in_rom = i_addr[31:12] == 20'h00000;
  assign i_fault  = !i_in_rom;
  assign i_rdata  = i_in_rom ? rom[i_addr[11:2]] : 32'h0;

  assign in_rom = d_addr[31:12] == 20'h00000;
  assign in_ram = d_addr[31:12] == 20'h00010;
  assign in_sig = d_addr[31:2]  == 30'h20000000;
  assign req    = d_load | d_store;

  always @(*) begin
    case (d_size)
      2'd0:    mis = 1'b0;
      2'd1:    mis = d_addr[0];
      default: mis = |d_addr[1:0];
    endcase
  end

  assign mapped         = d_store ? (in_ram | (in_sig & d_size == 2'd2))
                                  : (in_rom | in_ram | (in_sig & d_size == 2'd2));
  assign d_misaligned   = req & mis;
  assign d_access_fault = req & !mis & !mapped;

  assign rom_word = rom[d_addr[11:2]];
  assign ram_word = ram[d_addr[11:2]];
  assign rword    = in_rom ? rom_word : in_ram ? ram_word : in_sig ? sig_q : 32'h0;
  assign rsh      = rword >> {d_addr[1:0], 3'b000};

  always @(*) begin
    case (d_size)
      2'd0:    d_rdata = d_unsigned ? {24'b0, rsh[7:0]}  : {{24{rsh[7]}}, rsh[7:0]};
      2'd1:    d_rdata = d_unsigned ? {16'b0, rsh[15:0]} : {{16{rsh[15]}}, rsh[15:0]};
      default: d_rdata = rword;
    endcase
  end

  always @(*) begin
    case (d_size)
      2'd0: begin
        d_be        = 4'b0001 << d_addr[1:0];
        d_lane_data = {24'b0, d_wdata[7:0]} << {d_addr[1:0], 3'b000};
      end
      2'd1: begin
        d_be        = 4'b0011 << {d_addr[1], 1'b0};
        d_lane_data = {16'b0, d_wdata[15:0]} << {d_addr[1], 4'b0000};
      end
      default: begin
        d_be        = 4'b1111;
        d_lane_data = d_wdata;
      end
    endcase
  end

  assign d_lane_addr = {d_addr[31:2], 2'b00};

  always @(posedge clk) begin
    if (d_commit && in_ram) begin
      if (d_be[0]) ram[d_addr[11:2]][7:0]   <= d_lane_data[7:0];
      if (d_be[1]) ram[d_addr[11:2]][15:8]  <= d_lane_data[15:8];
      if (d_be[2]) ram[d_addr[11:2]][23:16] <= d_lane_data[23:16];
      if (d_be[3]) ram[d_addr[11:2]][31:24] <= d_lane_data[31:24];
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      sig_q   <= 32'h0;
      sig_w_q <= 1'b0;
      sig_n_q <= 32'h0;
    end else if (d_commit && in_sig) begin
      sig_q   <= d_wdata;
      sig_w_q <= 1'b1;
      sig_n_q <= sig_n_q + 32'd1;
    end
  end

  assign sig_value   = sig_q;
  assign sig_written = sig_w_q;
  assign sig_writes  = sig_n_q;
endmodule
