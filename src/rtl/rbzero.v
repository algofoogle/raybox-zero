`default_nettype none
`timescale 1ns / 1ps

`include "fixed_point_params.v"

//SMELL: These should probably be defined by the target (e.g. TT04 or FPGA) rather than inline here:
// `define USE_MAP_OVERLAY
// `define USE_DEBUG_OVERLAY
// `define TRACE_STATE_DEBUG  // Trace state is represented visually per each line on-screen.

module rbzero(
  input               clk,
  input               reset,
  // SPI interface for updating vectors:
  input               i_sclk,
  input               i_mosi,
  input               i_ss_n,
  // VGA outputs:
  output wire         hsync_n, vsync_n,
  output wire [5:0]   rgb,
  // hpos and vpos are currently supplied so a top module can do dithering,
  // but otherwise they're not really required, or even just bit-0 of each would do:
  output wire [9:0]   hpos,
  output wire [9:0]   vpos
);

  localparam H_VIEW = 640;
  localparam HALF_SIZE = H_VIEW/2;
  localparam MAP_WIDTH_BITS = 4;
  localparam MAP_HEIGHT_BITS = 4;
  localparam MAP_SCALE = 3;

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
  wire `F playerX /* verilator public */;
  wire `F playerY /* verilator public */;
  wire `F facingX /* verilator public */;
  wire `F facingY /* verilator public */;
  wire `F vplaneX /* verilator public */;
  wire `F vplaneY /* verilator public */;
  wire visible_frame_end = (hpos==799 && vpos==479); // The moment when SPI-loaded vector data could be used.
  pov pov(
    .clk      (clk),
    .reset    (reset),
    .i_sclk   (i_sclk),
    .i_mosi   (i_mosi),
    .i_ss_n   (i_ss_n),
    .load_if_ready(visible_frame_end),
    .playerX(playerX), .playerY(playerY),
    .facingX(facingX), .facingY(facingY),
    .vplaneX(vplaneX), .vplaneY(vplaneY)
  );

  // --- Map ROM: ---
  wire [MAP_WIDTH_BITS-1:0] tracer_map_col;
  wire [MAP_HEIGHT_BITS-1:0] tracer_map_row;
  wire tracer_map_val;
  map_rom #(
    .MAP_WIDTH_BITS(MAP_WIDTH_BITS),
    .MAP_HEIGHT_BITS(MAP_HEIGHT_BITS)
  ) map_rom (
    .i_col(tracer_map_col),
    .i_row(tracer_map_row),
    .o_val(tracer_map_val)
  );


`ifdef USE_MAP_OVERLAY
  // --- Map ROM for overlay: ---
  //SMELL: We only want one map ROM instance, but for now this is just a hack to avoid
  // contention when both the tracer and map overlay need to read from the map ROM.
  //@@@ This must be eliminated because it's blatant waste.
  wire [MAP_WIDTH_BITS-1:0] overlay_map_col;
  wire [MAP_HEIGHT_BITS-1:0] overlay_map_row;
  wire overlay_map_val;
  map_rom #(
    .MAP_WIDTH_BITS(MAP_WIDTH_BITS),
    .MAP_HEIGHT_BITS(MAP_HEIGHT_BITS)
  ) map_rom_overlay(
    .i_col(overlay_map_col),
    .i_row(overlay_map_row),
    .o_val(overlay_map_val)
  );
  // --- Map overlay: ---
  wire map_en;
  wire [5:0] map_rgb;
  map_overlay #(
    .MAP_SCALE(MAP_SCALE),
    .MAP_WIDTH_BITS(MAP_WIDTH_BITS),
    .MAP_HEIGHT_BITS(MAP_HEIGHT_BITS)
  ) map_overlay(
    .hpos(hpos), .vpos(vpos),
    .playerX(playerX), .playerY(playerY),
    .o_map_col(overlay_map_col),
    .o_map_row(overlay_map_row),
    .i_map_val(overlay_map_val),
    .in_map_overlay(map_en),
    .map_rgb(map_rgb)
  );
`endif//USE_MAP_OVERLAY


`ifdef USE_DEBUG_OVERLAY
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
`endif//USE_DEBUG_OVERLAY


  // --- Row-level ray caster/tracer: ---
  wire        traced_side;
  wire [10:0] traced_size;  // Calculated from traced_vdist, in this module.
  wall_tracer #(
    .MAP_WIDTH_BITS(MAP_WIDTH_BITS),
    .MAP_HEIGHT_BITS(MAP_HEIGHT_BITS)
  ) wall_tracer(
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
    // Map ROM access:
    .o_map_col(tracer_map_col),
    .o_map_row(tracer_map_row),
    .i_map_val(tracer_map_val),
    // Outputs:
`ifdef TRACE_STATE_DEBUG
    .o_state  (trace_state), //DEBUG.
`endif//TRACE_STATE_DEBUG
    .o_side   (traced_side),
    .o_size   (traced_size)
  );

`ifdef TRACE_STATE_DEBUG
  wire [2:0] trace_state;
`endif//TRACE_STATE_DEBUG

  // --- Combined pixel colour driver/mux: ---
  wire [5:0] bg = hpos < HALF_SIZE
    ? 6'b10_10_10   // Light grey for left (or bottom) side.
    : 6'b01_01_01;  // Dark grey.
  vga_mux vga_mux(
    .visible  (visible),

`ifdef USE_DEBUG_OVERLAY
    .debug_en (debug_en), .debug_rgb(debug_rgb),
`else//!USE_DEBUG_OVERLAY
    .debug_en (1'b0), .debug_rgb(6'd0),
`endif//USE_DEBUG_OVERLAY

`ifdef USE_MAP_OVERLAY
    .map_en   (map_en), .map_rgb(map_rgb),
`else//!USE_MAP_OVERLAY
    .map_en   (1'b0), .map_rgb(6'd0),
`endif//USE_MAP_OVERLAY

`ifdef TRACE_STATE_DEBUG
    .trace_state_debug(trace_state), //DEBUG.
`endif//TRACE_STATE_DEBUG

    .wall_en  (wall_en),
    .wall_rgb (wall_rgb),
    .bg_rgb   (bg),
    .out      (rgb)
  );

endmodule
