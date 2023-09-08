`default_nettype none
`timescale 1ns / 1ps

`include "fixed_point_params.v"

//SMELL: These should probably be defined by the target (e.g. TT04 or FPGA) rather than inline here:
// `define USE_MAP_OVERLAY
`define USE_DEBUG_OVERLAY
// `define TRACE_STATE_DEBUG  // Trace state is represented visually per each line on-screen.

module rbzero(
  input               clk,
  input               reset,
  // SPI interface for updating vectors:
  input               i_sclk,
  input               i_mosi,
  input               i_ss_n,
  // Debug/demo signals:
  input               i_debug,
  input               i_inc_px,
  input               i_inc_py,
  // VGA outputs:
  output wire         hsync_n, vsync_n,
  output wire [5:0]   rgb,

  // Other outputs:
  output wire         o_hblank, // Asserted for the duration of the horizontal blanking interval.
  output wire         o_vblank, // Asserted for the duration of the vertical blanking interval.

  // hpos and vpos are currently supplied so a top module can do dithering,
  // but otherwise they're not really required, or even just bit-0 of each would do:
  output wire [9:0]   hpos,
  output wire [9:0]   vpos
);

  localparam H_VIEW = 640;
  localparam HALF_SIZE = H_VIEW/2;
  localparam MAP_WBITS = 4;
  localparam MAP_HBITS = 4;
`ifdef USE_MAP_OVERLAY
  localparam MAP_SCALE = 3;
`endif//USE_MAP_OVERLAY

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
  wire        wall_en;              // Asserted for the duration of the textured wall being visible on screen.
  wire [5:0]  wall_rgb;             // Colour of the current wall pixel being scanned.
  reg `F      texV;                 // Note big 'V': Fixed-point accumulator for working out texv per pixel. //SMELL: Wasted excess precision.
  wire `F     texVV = texV + traced_texVinit;
  wire [5:0]  texv = (texVV < 0) ? 6'd0 : texVV[8:3]; // Clamp to 0.
  // At vdist of 1.0, a 64p texture is stretched to 512p, hence texv is 64/512 (>>3) of int(texV).
  //NOTE: Would it be possible to do primitive texture 'filtering' using 50/50 checker dither for texxture sub-pixels?
  row_render row_render(
    // Inputs:
    .wall     (traced_wall),
    .side     (traced_side),
    .size     (traced_size),
    .texu     (traced_texu),        //SMELL: Need to clamp texu/v so they don't wrap due to fixed-point precision loss.
    .texv     (texv),
    .leak     (6'd0), // Unused as yet. For positive values up to 32, it could be used to make it look like everything is submerged in the floor (e.g. water).
    // .over     (texVV[9]), //DEBUG: texture overflow.
    .hpos     (hpos),
    // Outputs:
    .rgb      (wall_rgb),
    .hit      (wall_en)
  );
  // texV scans the texture 'v' coordinate range with a step size of 'traced_texa'.
  //NOTE: Because of 'texVV = texV + traced_texVinit' above, texV might be relative to
  // a positive, 0, or negative starting point as calculated by wall_tracer.
  //SMELL: Move this into some other module, e.g. row_render?
  always @(posedge clk) texV <= (hmax ? 0 : texV + traced_texa);

  // --- Point-Of-View data, i.e. view vectors: ---
  wire `F playerX /* verilator public */;
  wire `F playerY /* verilator public */;
  wire `F facingX /* verilator public */;
  wire `F facingY /* verilator public */;
  wire `F vplaneX /* verilator public */;
  wire `F vplaneY /* verilator public */;
  wire visible_frame_end = (hpos==799 && vpos==479); // The moment when SPI-loaded vector data could be used.
  assign o_hblank = hpos >= 640;
  assign o_vblank = vpos >= 480;
  pov pov(
    .clk      (clk),
    .reset    (reset),
    .i_sclk   (i_sclk),
    .i_mosi   (i_mosi),
    .i_ss_n   (i_ss_n),
    .i_inc_px (i_inc_px),
    .i_inc_py (i_inc_py),
    .load_if_ready(visible_frame_end),
    .playerX(playerX), .playerY(playerY),
    .facingX(facingX), .facingY(facingY),
    .vplaneX(vplaneX), .vplaneY(vplaneY)
  );

  // --- Map ROM: ---
  wire [MAP_WBITS-1:0] tracer_map_col;
  wire [MAP_HBITS-1:0] tracer_map_row;
  wire [1:0] tracer_map_val;
  map_rom #(
    .MAP_WBITS(MAP_WBITS),
    .MAP_HBITS(MAP_HBITS)
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
  wire [MAP_WBITS-1:0] overlay_map_col;
  wire [MAP_HBITS-1:0] overlay_map_row;
  wire [1:0] overlay_map_val;
  map_rom #(
    .MAP_WBITS(MAP_WBITS),
    .MAP_HBITS(MAP_HBITS)
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
    .MAP_WBITS(MAP_WBITS),
    .MAP_HBITS(MAP_HBITS)
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
  wire [1:0]  traced_wall;
  wire        traced_side;
  wire [10:0] traced_size;  // Calculated from traced_vdist, in this module.
  wire [5:0]  traced_texu;  // Texture 'u' coordinate value.
  wire `F     traced_texa;
  wire `F     traced_texVinit;
  wall_tracer #(
    .MAP_WBITS(MAP_WBITS),
    .MAP_HBITS(MAP_HBITS),
    .HALF_SIZE(HALF_SIZE)
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
    .o_wall   (traced_wall),
    .o_side   (traced_side),
    .o_size   (traced_size),
    .o_texu   (traced_texu),
    .o_texa   (traced_texa),
    .o_texVinit(traced_texVinit)
  );

`ifdef TRACE_STATE_DEBUG
  wire [3:0] trace_state;
`endif//TRACE_STATE_DEBUG

  // --- Combined pixel colour driver/mux: ---
  wire [5:0] bg = hpos < HALF_SIZE
    // ? 6'b11_00_00   // Blue... water?
    ? 6'b10_10_10   // Light grey for left (or bottom) side.
    : 6'b01_01_01;  // Dark grey.
  vga_mux vga_mux(
    .visible  (visible),

`ifdef USE_DEBUG_OVERLAY
    .debug_en (debug_en & i_debug), .debug_rgb(debug_rgb),
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
