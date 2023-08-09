`default_nettype none
`timescale 1ns / 1ps

module vga_mux(
  output [5:0]  out,

  input         visible,

  input [5:0]   bg_rgb, // Default background colour.

  input         wall_en,
  input [5:0]   wall_rgb

);

  always @(*) begin
    if (!visible)
      out = 6'b0;
    else if (wall_en)
      out = wall_rgb;
    else
      out = bg_rgb;
  end
  
endmodule
