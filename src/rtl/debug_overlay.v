`default_nettype none
// `timescale 1ns / 1ps

// `include "fixed_point_params.v"

module debug_overlay #(
  parameter H_VIEW = 640,
  parameter DEBUG_SCALE = 3 // Power of 2 scaling for debug overlay.
) (
  input [9:0] hpos, vpos,
  input `F playerX, playerY, facingX, facingY, vplaneX, vplaneY,
  output in_debug_overlay,
  output [5:0] debug_rgb
);
  // 'h' is hpos offset to coordinates relative to the top-left corner of the debug overlay:
  localparam DOHS = (H_VIEW - (1<<DEBUG_SCALE)*(`Qm+`Qn) - 1);
  localparam [10:0] DEBUG_OVERLAY_HPOS_START = DOHS[10:0];
  wire signed [10:0] h = {1'b0,hpos} - DEBUG_OVERLAY_HPOS_START;
  wire [9:0] v = vpos; // Just for convenience.

  // Are we in the region where the debug overlay displays?
  assign in_debug_overlay = (h >= 0) && (v <= (8<<DEBUG_SCALE));

  // Are we in one of the gridlines between cells?
  wire in_debug_gridline = h[DEBUG_SCALE-1:0]==0||v[DEBUG_SCALE-1:0]==0;

  // Mask to extract current bit (per h) from each of the vectors:
  //SMELL: Just use bit index instead?
  wire `F debug_bit_mask = (1 << (`Qmn-h[10:DEBUG_SCALE]-1));

  wire [1:0] c =
    in_debug_gridline               ? ( h==(`Qm<<DEBUG_SCALE)       ? 2'b10 : 2'b00) : // h==(`Qm<<DEBUG_SCALE) is integer/fraction dividing line.
    v[DEBUG_SCALE+2:DEBUG_SCALE]==0 ? ( (playerX&debug_bit_mask)!=0 ? 2'b11 : 2'b01) :
    v[DEBUG_SCALE+2:DEBUG_SCALE]==1 ? ( (playerY&debug_bit_mask)!=0 ? 2'b11 : 2'b01) :
    v[DEBUG_SCALE+2:DEBUG_SCALE]==3 ? ( (facingX&debug_bit_mask)!=0 ? 2'b11 : 2'b01) :
    v[DEBUG_SCALE+2:DEBUG_SCALE]==4 ? ( (facingY&debug_bit_mask)!=0 ? 2'b11 : 2'b01) :
    v[DEBUG_SCALE+2:DEBUG_SCALE]==6 ? ( (vplaneX&debug_bit_mask)!=0 ? 2'b11 : 2'b01) :
    v[DEBUG_SCALE+2:DEBUG_SCALE]==7 ? ( (vplaneY&debug_bit_mask)!=0 ? 2'b11 : 2'b01) :
                                      2'b00;

  assign debug_rgb = {c,c,c};

endmodule
