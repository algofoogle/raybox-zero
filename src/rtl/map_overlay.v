`default_nettype none
`timescale 1ns / 1ps


//@@@ map_overlay can't work properly yet, because *for now* we need to assume the tracer wants
// access to the map ROM at the same time as map_overlay. Hopefully we'll find that there's HEAPS
// of free tracing time, in which case we'll just make sure the FSM runs when we're out of
// the 'in_map_overlay' screen region.

module map_overlay #(
  parameter H_VIEW = 640,
  parameter MAP_WBITS = 4,
  parameter MAP_HBITS = 4,
  parameter MAP_SCALE = 3 // Power of 2 scaling for overlay.
) (
  input [9:0]             hpos, vpos,
  input `F playerX, playerY, //facingX, facingY, vplaneX, vplaneY,

  // Interface to map ROM:
  output [MAP_WBITS-1:0]  o_map_col,
  output [MAP_HBITS-1:0]  o_map_row,
  input [1:0]             i_map_val,

  output in_map_overlay,
  output [5:0] map_rgb
);

  localparam MAP_WIDTH          = 1<<MAP_WBITS;
  localparam MAP_HEIGHT         = 1<<MAP_HBITS;
  localparam MAP_OVERLAY_WIDTH  = (MAP_WIDTH   << MAP_SCALE)+1;
  localparam MAP_OVERLAY_HEIGHT = (MAP_HEIGHT  << MAP_SCALE)+1;

  assign in_map_overlay = hpos < MAP_OVERLAY_WIDTH  && vpos < MAP_OVERLAY_HEIGHT;
  wire in_map_gridline  = hpos[MAP_SCALE-1:0]==0    || vpos[MAP_SCALE-1:0]==0;
  wire in_player_cell   = playerX[MAP_WBITS-1:0]==hpos[MAP_SCALE+MAP_WBITS-1:MAP_SCALE] &&
                          playerY[MAP_HBITS-1:0]==vpos[MAP_SCALE+MAP_HBITS-1:MAP_SCALE];
  wire in_player_pixel  = in_player_cell
                                  && (playerX[-1:-MAP_SCALE]==hpos[MAP_SCALE-1:0])
                                  && (playerY[-1:-MAP_SCALE]==vpos[MAP_SCALE-1:0]);

  assign o_map_col = hpos[MAP_SCALE+MAP_WBITS-1:MAP_SCALE];
  assign o_map_row = vpos[MAP_SCALE+MAP_HBITS-1:MAP_SCALE];

  assign map_rgb =
    in_player_pixel ? 6'b00_11_11:  // Player pixel in map is yellow.
    in_player_cell  ? 6'b00_01_00:  // Player cell is dark green.
    in_map_gridline ? 6'b01_00_00:  // Map gridlines are dark blue.
    i_map_val==0    ? 6'b00_00_00:  // Unoccupied map cells are black.
    i_map_val==1    ? 6'b11_00_00:  // Blue map cell (on the map at least).
    i_map_val==2    ? 6'b00_11_11:  // Yellow map cell
    /*i_map_val==3?*/ 6'b00_00_11;  // Red map cell

endmodule
