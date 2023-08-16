`default_nettype none
`timescale 1ns / 1ps

module vga_mux(
  input         visible,

  input         debug_en,
  input [5:0]   debug_rgb,

  input         map_en,
  input [5:0]   map_rgb,

  input         wall_en,
  input [5:0]   wall_rgb,

  input [5:0]   bg_rgb, // Default background colour.
  output reg [5:0]  out
);

  always @(*) begin
    if (!visible)       out = 6'b0;
    else if (debug_en)  out = debug_rgb;
    else if (map_en)    out = map_rgb;
    else if (wall_en)   out = wall_rgb;
    else                out = bg_rgb;
  end
  
endmodule
