`default_nettype none
`timescale 1ns / 1ps

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

  // VGA sync driver:
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

  wire traced_side;
  wire [10:0] traced_size;

  wall_tracer wall_tracer(
    // Inputs:
    .clk      (clk),
    .reset    (reset),
    .i_row    (vpos),
    // Tracer is allowed to run for the whole line duration,
    // but gets the signal to stop and present its result at the end of the line,
    // i.e. when 'hmax' goes high, and hence on the 'run' falling edge:
    .i_run    (~hmax),
    // Outputs:
    .o_side   (traced_side),
    .o_size   (traced_size)
  );



  wire [5:0] bg = hpos < HALF_SIZE
    ? 6'b10_10_10   // Light grey for left (or bottom) side.
    : 6'b01_01_01;  // Dark grey.
  
  vga_mux vga_mux(
    .out      (rgb),
    .visible  (visible),
    .bg_rgb   (bg),
    .wall_rgb (wall_rgb),
    .wall_en  (wall_en)
  );

endmodule
