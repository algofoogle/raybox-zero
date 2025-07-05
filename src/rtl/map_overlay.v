`default_nettype none
// `timescale 1ns / 1ps


module map_overlay #(
  // parameter H_VIEW = 640,
  parameter USE_GRIDLINES = 0,
  parameter MAP_WALLBITS = 3,
  parameter MAP_WBITS = 4,
  parameter MAP_HBITS = 4,
  parameter MAP_SCALE = 3 // Power of 2 scaling for overlay.
) (
  input [9:0]             hpos, vpos,
  input `F playerX, playerY, //facingX, facingY, vplaneX, vplaneY,

  // Interface to map ROM:
  output [MAP_WBITS-1:0]  o_map_col,
  output [MAP_HBITS-1:0]  o_map_row,
  input [MAP_WALLBITS-1:0] i_map_val, // Value of the map cell (i.e. from map memory)
  // Other map cell X,Y:
  input [5:0]             i_otherx, i_othery,
`ifndef NO_DIV_WALLS
  // Map X/Y dividers:
  input [5:0]             i_mapdx, i_mapdy,
`endif // NO_DIV_WALLS
`ifdef USE_DOORS
  // Yosys doesn't support arrayed ports?
  // input [23:0]            i_doors [0:3],
  input wire [23:0]       i_doors0,
  input wire [23:0]       i_doors1,
  input wire [23:0]       i_doors2,
  input wire [23:0]       i_doors3,
`endif // USE_DOORS

  output in_map_overlay,
  output [5:0] map_rgb
);

  localparam MAP_WIDTH          = 1<<MAP_WBITS;
  localparam MAP_HEIGHT         = 1<<MAP_HBITS;
  localparam MAP_OVERLAY_WIDTH  = (MAP_WIDTH   << MAP_SCALE)+USE_GRIDLINES;
  localparam MAP_OVERLAY_HEIGHT = (MAP_HEIGHT  << MAP_SCALE)+USE_GRIDLINES;

  wire [MAP_WBITS-1:0] hpos_mapx = hpos[MAP_SCALE+MAP_WBITS-1:MAP_SCALE];
  wire [MAP_HBITS-1:0] vpos_mapy = vpos[MAP_SCALE+MAP_HBITS-1:MAP_SCALE];

`ifdef USE_DOORS
  wire        hit_door;
  wire [7:0]  hit_door_pos;
`else // !USE_DOORS
  wire        hit_door = 0;
`endif // USE_DOORS
  wire `WALL  hit_wall_id;
  wire        valid_hit;

  wall_id_resolver #(
    .MAP_WALLBITS (MAP_WALLBITS),
    .MAP_WBITS    (MAP_WBITS),
    .MAP_HBITS    (MAP_HBITS)
  ) wall_id_resolver(
    // --- Inputs ---
    // Map cell to resolve:
    .mapx           (o_map_col), //mapX),
    .mapy           (o_map_row), //mapY),
    // Base map cell:
    .map_cell       (i_map_val),
`ifndef NO_DIV_WALLS
    // Parameters from map "dividing walls" registers:
    .mapdivx        (i_mapdx[4:0]),  .mapdivx_wall(0), // wall ID is 0 because it's unknown (and irrelevant) in here.
    .mapdivy        (i_mapdy[4:0]),  .mapdivy_wall(0), // wall ID is 0 because it's unknown (and irrelevant) in here.
`endif // NO_DIV_WALLS
    // Parameters from "OTHER" cell:
    .otherx         (i_otherx[4:0]),
    .othery         (i_othery[4:0]),
`ifdef USE_DOORS
    // Door registers:
    .doors0         (i_doors0),
    .doors1         (i_doors1),
    .doors2         (i_doors2),
    .doors3         (i_doors3),
`endif // USE_DOORS

    // --- Outputs ---
`ifdef USE_DOORS
    .o_hit_door     (hit_door),
    .o_hit_door_pos (hit_door_pos),
`endif // USE_DOORS
    .o_hit_wall_id  (hit_wall_id),
    .o_valid_hit    (valid_hit)
  );

  assign in_map_overlay = hpos < MAP_OVERLAY_WIDTH  && vpos < MAP_OVERLAY_HEIGHT;
  wire in_map_gridline  = USE_GRIDLINES && (hpos[MAP_SCALE-1:0]==0 || vpos[MAP_SCALE-1:0]==0);
  wire in_player_cell   = hpos_mapx==playerX[MAP_WBITS-1:0] &&
                          vpos_mapy==playerY[MAP_HBITS-1:0];

  // wall_id_resolver already handles 'other' and 'div' cells,
  // but we override them to apply a special appearance in the map...
  wire in_other_cell    = hpos_mapx==i_otherx[MAP_WBITS-1:0] &&
                          vpos_mapy==i_othery[MAP_HBITS-1:0];
`ifndef NO_DIV_WALLS
  wire in_mapdx_cell    = hpos_mapx==i_mapdx[MAP_WBITS-1:0] && i_mapdx!=0;
  wire in_mapdy_cell    = vpos_mapy==i_mapdy[MAP_HBITS-1:0] && i_mapdy!=0;
`endif // NO_DIV_WALLS
  wire in_player_pixel  = in_player_cell
                                  && (playerX[-1:-MAP_SCALE]==hpos[MAP_SCALE-1:0])
                                  && (playerY[-1:-MAP_SCALE]==vpos[MAP_SCALE-1:0]);

  assign o_map_col = hpos[MAP_SCALE+MAP_WBITS-1:MAP_SCALE];
  assign o_map_row = vpos[MAP_SCALE+MAP_HBITS-1:MAP_SCALE];

  wire [MAP_WALLBITS-1:0] map_cell_wall_id =
`ifdef USE_DOORS
    hit_door ? hit_wall_id[3:1] :
`endif // USE_DOORS
    hit_wall_id[2:0];

  wire [5:0] map_cell_base_color =
`ifdef USE_DOORS
    map_cell_wall_id==0     ? (hit_door ? 6'b00_00_11 : 6'b00_00_00):  // Door wall ID 0 is red. Otherwise: unoccupied map cells are black.
`else
    map_cell_wall_id==0     ? 6'b00_00_00:  // Unoccupied map cells are black.
`endif // USE_DOORS
    map_cell_wall_id==1     ? 6'b11_10_00:  // Wall ID 1: Map cell is Light blue
    map_cell_wall_id==2     ? 6'b11_00_00:  // Wall ID 2: Map cell is Blue
    map_cell_wall_id==3     ? 6'b11_00_10:  // Wall ID 3: Map cell is Purple
    map_cell_wall_id==4     ? 6'b00_01_10:  // 4: Brown
    map_cell_wall_id==5     ? 6'b00_10_11:  // 5: Orange
    map_cell_wall_id==6     ? 6'b10_00_11:  // 6: Purple-red
    /*map_cell_wall_id==7*/   6'b00_10_01;  // 7: Yellow-green

  assign map_rgb =
    in_player_pixel ? 6'b00_11_11:  // Player pixel in map is yellow.
    in_player_cell  ? 6'b00_01_00:  // Player cell is dark green.
    in_map_gridline ? 6'b01_00_00:  // Map gridlines are dark blue.
`ifdef USE_DOORS
    hit_door        ? (map_cell_base_color & {6{~(hpos[0] | vpos[0])}}): // Doors have a 'grid' pattern.
`endif // USE_DOORS
    in_other_cell   ? 6'b00_00_11:  // 'Other' cell is red.
`ifndef NO_DIV_WALLS
    in_mapdx_cell   ? 6'b00_00_10:  // mapdx bar is dark red.
    in_mapdy_cell   ? 6'b00_00_01:  // mapdy bar is very dark red.
`endif // NO_DIV_WALLS
                      map_cell_base_color;

endmodule
