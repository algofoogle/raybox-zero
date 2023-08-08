// This file is included for using this design with 8bitworkshop.com,
// specifically as a "Verilog (VGA @ 25 Mhz)" project:
// https://8bitworkshop.com/v3.10.1/?platform=verilog-vga

`default_nettype none
`timescale 1ns / 1ps

`include "vga_sync.v"
`include "rbzero.v"
`include "row_render.v"

module rbzero_top(
  input clk,
  input reset,
  output hsync,
  output vsync,
  output [2:0] rgb
);
  
  wire hsync_n, vsync_n;
  assign {hsync,vsync} = {~hsync_n,~vsync_n};
  wire [1:0] rr,gg,bb;
  assign rgb = {bb[1],gg[1],rr[1]};
  wire [9:0] hpos;
  wire [9:0] vpos;
  
  rbzero dut(
    .clk(clk),
    .reset(reset),
    .hsync_n(hsync_n), .vsync_n(vsync_n),
    .hpos(hpos), .vpos(vpos),
    .r(rr), .g(gg), .b(bb)
  );
  
  dither dither(
    .field(0),
    .xo(hpos[0]), .yo(vpos[0]),
    .r(rr), .g(gg), .b(bb),
    .dR(rgb[0]), .dG(rgb[1]), .dB(rgb[2])
  );
  
endmodule


module dither(
  input field,
  input xo, yo, // Odd of X and Y positions respectively.
  input [1:0] r,g,b,
  output dR,dG,dB
);
  wire dither_hi = (xo^yo)^field;
  wire dither_lo = (xo^field)&(yo^field);
  assign dR = (r==2'b11) ? 1'b1 : (r==2'b10) ? dither_hi : (r==2'b01) ? dither_lo : 1'b0;
  assign dG = (g==2'b11) ? 1'b1 : (g==2'b10) ? dither_hi : (g==2'b01) ? dither_lo : 1'b0;
  assign dB = (b==2'b11) ? 1'b1 : (b==2'b10) ? dither_hi : (b==2'b01) ? dither_lo : 1'b0;

endmodule
