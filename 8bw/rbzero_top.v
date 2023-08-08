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
  
  dither dither(
    .field  (0),
    .xo     (hpos[0]), .yo(vpos[0]),
    .rgb6   (rgb6),
    .rgb3   (rgb)
  );
  
endmodule


module dither(
  input field,
  input xo, yo, // Odd of X and Y positions respectively.
  input [5:0] rgb6,
  output [2:0] rgb3
);
  wire dither_hi = (xo^yo)^field;
  wire dither_lo = (xo^field)&(yo^field);
  //SMELL: Do this with a 'for' or something?
  wire [1:0] r = rgb6[1:0];
  wire [1:0] g = rgb6[3:2];
  wire [1:0] b = rgb6[5:4];
  assign rgb3[0] = (r==2'b11) ? 1'b1 : (r==2'b10) ? dither_hi : (r==2'b01) ? dither_lo : 1'b0;
  assign rgb3[1] = (g==2'b11) ? 1'b1 : (g==2'b10) ? dither_hi : (g==2'b01) ? dither_lo : 1'b0;
  assign rgb3[2] = (b==2'b11) ? 1'b1 : (b==2'b10) ? dither_hi : (b==2'b01) ? dither_lo : 1'b0;

endmodule
