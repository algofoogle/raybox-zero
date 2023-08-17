`default_nettype none
`timescale 1ns / 1ps

`include "fixed_point_params.v"

module rbzero(
  input clk,
  input reset,
  output wire hsync_n, vsync_n,
  output wire [5:0] rgb,
  // hpos and vpos are currently supplied so a top module can do dithering,
  // but otherwise they're not really required, or even just bit-0 of each would do:
  output wire [9:0] hpos,
  output wire [9:0] vpos
);

  localparam H_VIEW = 640;
  localparam HALF_SIZE = H_VIEW/2;

  // --- VGA sync driver: ---
  wire hsync, vsync;
  wire visible;
  assign {hsync_n,vsync_n} = ~{hsync,vsync};
  // wire [9:0] hpos;
  // wire [9:0] vpos;
  wire hmax, vmax;
  vga_sync vga_sync(
    .clk      (clk),
    .reset    (reset),
    .hsync    (hsync),
    .vsync    (vsync),
    .hpos     (hpos),
    .vpos     (vpos),
    .hmax     (hmax),
    .vmax     (vmax),
    .visible  (visible)
  );

  // --- Row-level renderer: ---
  wire wall_en;
  wire [5:0] wall_rgb;
  row_render row_render(
    // Inputs:
    .side     (traced_side),
    .size     (traced_size),
    .hpos     (hpos),
    // Outputs:
    .rgb      (wall_rgb),
    .hit      (wall_en)
  );

  // --- Point-Of-View data, i.e. view vectors: ---
  wire `F playerX, playerY, facingX, facingY, vplaneX, vplaneY;
  pov pov(
    .playerX(playerX), .playerY(playerY),
    .facingX(facingX), .facingY(facingY),
    .vplaneX(vplaneX), .vplaneY(vplaneY)
  );

  // --- Debug overlay: ---
  wire debug_en;
  wire [5:0] debug_rgb;
  debug_overlay debug_overlay(
    .hpos(hpos), .vpos(vpos),
    // View vectors:
    .playerX(playerX), .playerY(playerY),
    .facingX(facingX), .facingY(facingY),
    .vplaneX(vplaneX), .vplaneY(vplaneY),
    .in_debug_overlay(debug_en),
    .debug_rgb(debug_rgb)
  );

  // --- Map overlay: ---
  wire map_en;
  wire [5:0] map_rgb;
  map_overlay map_overlay(
    .hpos(hpos), .vpos(vpos),
    .playerX(playerX), .playerY(playerY),
    .in_map_overlay(map_en),
    .map_rgb(map_rgb)
  );

  // --- Row-level ray caster/tracer: ---
  wire        traced_side;
  wire [10:0] traced_size;
  wall_tracer wall_tracer(
    // Inputs:
    .clk      (clk),
    .reset    (reset),
    // vsync is used to reset the FSM and prepare for all traces that will take place
    // in the next frame:
    .vsync    (vsync),
    // Tracer is allowed to run for the whole line duration,
    // but gets the signal to stop and present its result at the end of the line,
    // i.e. when 'hmax' goes high:
    .hmax     (hmax),
    // View vectors:
    .playerX(playerX), .playerY(playerY),
    .facingX(facingX), .facingY(facingY),
    .vplaneX(vplaneX), .vplaneY(vplaneY),
    // Outputs:
    .o_side   (traced_side),
    .o_size   (traced_size)
  );

  // --- Combined pixel colour driver/mux: ---
  wire [5:0] bg = hpos < HALF_SIZE
    ? 6'b10_10_10   // Light grey for left (or bottom) side.
    : 6'b01_01_01;  // Dark grey.
  vga_mux vga_mux(
    .visible  (visible),
    .debug_en (debug_en),
    .debug_rgb(debug_rgb),
    .map_en   (map_en),
    .map_rgb  (map_rgb),
    .wall_en  (wall_en),
    .wall_rgb (wall_rgb),
    .bg_rgb   (bg),
    .out      (rgb)
  );

endmodule
