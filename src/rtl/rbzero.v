`default_nettype none
`timescale 1ns / 1ps

module rbzero(
  input clk,
  input reset,
  output wire hsync_n, vsync_n,
  output wire [1:0] r, g, b,
  output wire [9:0] hpos,
  output wire [9:0] vpos
);

  // VGA sync driver:
  wire hsync, vsync;
  wire visible;
  assign hsync_n = ~hsync;
  assign vsync_n = ~vsync;
  // wire [9:0] hpos;
  // wire [9:0] vpos;
  vga_sync vga_sync(
    .clk    (clk),
    .reset  (reset),
    .hsync  (hsync),
    .vsync  (vsync),
    .hpos   (hpos),
    .vpos   (vpos),
    .visible(visible)
  );

  wire [5:0] rgb;

  wire hit;

  row_render row_render(
    .side(vpos[3]),
    .size({1'b0,vpos}),
    .hpos(hpos),
    .r(rgb[1:0]),
    .g(rgb[3:2]),
    .b(rgb[5:4]),
    .hit(hit)
  );

  assign {b,g,r} = (visible & hit) ? rgb : 6'b000000;

endmodule
