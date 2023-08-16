`default_nettype none
`timescale 1ns / 1ps

module map_overlay #(
  parameter H_VIEW = 640,
  parameter MAP_WIDTH_BITS = 4,
  parameter MAP_HEIGHT_BITS = 4,
  parameter MAP_SCALE = 3 // Power of 2 scaling for overlay.
) (
  input [9:0] hpos, vpos,
  input `F playerX, playerY, //facingX, facingY, vplaneX, vplaneY,
  output in_map_overlay,
  output [5:0] map_rgb
);

  localparam MAP_WIDTH          = 1<<MAP_WIDTH_BITS;
  localparam MAP_HEIGHT         = 1<<MAP_HEIGHT_BITS;
  localparam MAP_OVERLAY_WIDTH  = (MAP_WIDTH   << MAP_SCALE)+1;
  localparam MAP_OVERLAY_HEIGHT = (MAP_HEIGHT  << MAP_SCALE)+1;

  assign in_map_overlay = hpos < MAP_OVERLAY_WIDTH  && vpos < MAP_OVERLAY_HEIGHT;
  wire in_map_gridline  = hpos[MAP_SCALE-1:0]==0    || vpos[MAP_SCALE-1:0]==0;
  wire in_player_cell   = playerX[MAP_WIDTH_BITS-1:0]==hpos[MAP_SCALE+MAP_WIDTH_BITS-1:MAP_SCALE] &&
                          playerY[MAP_HEIGHT_BITS-1:0]==vpos[MAP_SCALE+MAP_HEIGHT_BITS-1:MAP_SCALE];
  wire in_player_pixel  = in_player_cell
                                  && (playerX[-1:-MAP_SCALE]==hpos[MAP_SCALE-1:0])
                                  && (playerY[-1:-MAP_SCALE]==vpos[MAP_SCALE-1:0]);

  assign map_rgb =
    in_player_pixel ? 6'b00_11_11 :   // Player pixel in map is yellow.
    in_player_cell  ? 6'b00_01_00 :   // Player cell is dark green.
    in_map_gridline ? 6'b01_00_00 :   // Map gridlines are dark blue.
                      6'b00_00_00;    // Until we can read the actual map, map cells are black.

endmodule
