`default_nettype none
`timescale 1ns / 1ps

// Other modules required:
// - tracer logic and FSM
// - row renderer?
// - map
// - vga/rgb mux
// - view vectors (and SPI slave controller?)
// - reciprocal(s)
// - shared multiplier?
// - OPTIONAL texture SPI RAM master and local memory
// - OPTIONAL external control pins
// - OPTIONAL debugging IO
// - OPTIONAL debug overlay
// - OPTIONAL temporal ordered dither

module rbzero (
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

  // rgb_test_pattern test(
  //   .hpos(hpos),
  //   .vpos(vpos),
  //   .visible(visible),
  //   .r(r),
  //   .g(g),
  //   .b(b)
  // );

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

  assign {b,g,r} = hit ? rgb : 6'b000000;

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



// module vga_mux(
//   input [1:0] wallR,wallG,wallB,
//   input wall_en
//   input [1:0] backR,backG,backB
// );

// endmodule



module row_render #(
  localparam H_VIEW = 640
) (
  input wire side,
  input wire [10:0] size, // Supports 0..2047; remember this is mirrored, too.
  input wire [9:0] hpos,  // Current horizontal trace position.
  output wire [1:0] r, g, b,
  output wire hit         // Are we in this row or not?    
);
  localparam HALF_SIZE = H_VIEW/2;
  //SMELL: Instead of combo logic, could use a register and check for enter/leave:
  assign hit =
    (size > HALF_SIZE) ||
    ((HALF_SIZE-size <= {1'b0,hpos}) && ({1'b0,hpos} <= HALF_SIZE+size));
  //SMELL: For now, just arbitrarily assign a colour based on side. Later, do textures.
  assign {r,g,b} = side ?
    6'b00_00_11 :
    6'b00_00_10;

endmodule


module rgb_test_pattern(
  input [9:0] hpos,
  input [9:0] vpos,
  input visible,
  output [1:0] r, g, b
);
  
  assign r = visible ? {2{hpos[3]}} : 0;
  assign g = visible ? {2{vpos[3]}} : 0;
  assign b = visible ? {2{hpos[5]^vpos[5]}} : 0;
  
endmodule
