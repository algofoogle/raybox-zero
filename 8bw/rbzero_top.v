// This file is included for using this design with 8bitworkshop.com,
// specifically as a "Verilog (VGA @ 25 Mhz)" project:
// https://8bitworkshop.com/v3.10.1/?platform=verilog-vga

`default_nettype none
`timescale 1ns / 1ps

`include "debug_overlay.v"
`include "lzc.v"
`include "reciprocal.v"
`include "map_overlay.v"
`include "map_rom.v"
`include "pov.v"
`include "rbzero.v"
`include "row_render.v"
`include "vga_mux.v"
`include "vga_sync.v"
`include "wall_tracer.v"


module rbzero_top(
  input clk,
  input reset,
  output hsync,
  output vsync,
  output [2:0] rgb
);
  
  wire hsync_n, vsync_n;
  assign {hsync,vsync} = ~{hsync_n,vsync_n};
  wire [9:0] hpos;
  wire [9:0] vpos;
  wire [5:0] rgb6;  // 6-bit colour, BBGGRR bit order.
  rbzero dut(
    .clk    (clk),
    .reset  (reset),
    .hsync_n(hsync_n),
    .vsync_n(vsync_n),
    .hpos   (hpos),
    .vpos   (vpos),
    .rgb    (rgb6)
  );
  
  reg dither_field;
  always @(posedge vsync_n) dither_field <= ~dither_field;
  initial dither_field = 0;

  dither dither(
    .field  (dither_field),
    .xo     (hpos[0]), .yo(vpos[0]),
    .rgb6   (rgb6),
    .rgb3   (rgb)
  );
  
endmodule


//NOTE: This dither is as follows:
// Perhaps the better way is to use these patterns:
// - 11: 100%: Pixels fully on.
// - 10: 62.5% (5/8):
//      odd   even
//      xx    x.
//      x.    .x
// - 01: 37.5% (3/8):
//      Inverse of above
module dither(
  input field,
  input xo, yo, // Odd of X and Y positions respectively.
  input [5:0] rgb6,
  output [2:0] rgb3
);
  // // Dither using 100/50/25/0%:
  // wire dither_hi = (xo^yo)^field;
  // wire dither_lo = (xo^field)&(yo^field);
  // Dither using 100/63/38/0
  wire dither_hi = yo ? (field ? 1'b1 : ~xo) : field^xo;
  wire dither_lo = ~dither_hi;
  //SMELL: Do this with a 'for' or something?
  wire [1:0] r = rgb6[1:0];
  wire [1:0] g = rgb6[3:2];
  wire [1:0] b = rgb6[5:4];
  assign rgb3[0] = (r==2'b11) ? 1'b1 : (r==2'b10) ? dither_hi : (r==2'b01) ? dither_lo : 1'b0;
  assign rgb3[1] = (g==2'b11) ? 1'b1 : (g==2'b10) ? dither_hi : (g==2'b01) ? dither_lo : 1'b0;
  assign rgb3[2] = (b==2'b11) ? 1'b1 : (b==2'b10) ? dither_hi : (b==2'b01) ? dither_lo : 1'b0;

endmodule
