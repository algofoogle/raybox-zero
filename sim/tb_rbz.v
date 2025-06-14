`default_nettype none
// `timescale 1ns / 1ps

module tb_rbz (
  input               clk,
  input               reset,
`ifndef USE_POV_VIA_SPI_REGS
  // SPI slave for updating vectors:
  input               i_ss_n,
  input               i_sclk,
  input               i_mosi,
`else // USE_POV_VIA_SPI_REGS
  // POV regs are instead accessed via spi_registers (the inputs below)...
`endif // USE_POV_VIA_SPI_REGS
  // SPI slave for everything else:
  input               i_reg_ss_n, // aka /CS, aka csb.
  input               i_reg_sclk,
  input               i_reg_mosi,
  // Debug/demo signals:
`ifdef USE_DEBUG_OVERLAY
  input               i_debug_v,  // Show debug overlay for inspecting view vectors?
`endif // USE_DEBUG_OVERLAY
`ifdef USE_MAP_OVERLAY
  input               i_debug_m,  // Show debug overlay for map
`endif // USE_MAP_OVERLAY
`ifdef TRACE_STATE_DEBUG
  input               i_debug_t,  // Show debug overlay for the tracer FSM
`endif // TRACE_STATE_DEBUG
  input               i_inc_px,   // DEMO: Increment playerX
  input               i_inc_py,   // DEMO: Increment playerY
`ifndef NO_EXTERNAL_TEXTURES
  input               i_gen_tex,  // 1=Use bitwise-generated textures instead of SPI texture memory.
`endif // NO_EXTERNAL_TEXTURES
  // VGA outputs:
  output wire         hsync_n, vsync_n,
  output wire [5:0]   rgb,

  // Other outputs:
  output wire         o_hblank, // Asserted for the duration of the horizontal blanking interval.
  output wire         o_vblank, // Asserted for the duration of the vertical blanking interval.
  output wire         o_hmax,
  output wire         o_vmax,

  // Debug outputs:
  output wire         o_vinf, // Send out a copy of the VINF register, which can help with debugging 'reg' SPI.

  // hpos and vpos are currently supplied so a top module can do dithering,
  // but otherwise they're not really required, or even just bit-0 of each would do:
  output wire [9:0]   hpos,
  output wire [9:0]   vpos
);


  wire o_tex_csb;
  wire o_tex_sclk;
  wire o_tex_out0;
  wire o_tex_oeb0;
  wire [3:0] i_tex_in;
  wire [2:0] tex_io;

  wire `F playerX /* verilator public */;
  wire `F playerY /* verilator public */;
  wire `F facingX /* verilator public */;
  wire `F facingY /* verilator public */;
  wire `F vplaneX /* verilator public */;
  wire `F vplaneY /* verilator public */;

  assign tex_io[0] =
    (o_tex_oeb0 == 0) ? o_tex_out0  // raybox-zero is asserting an output.
                      : 1'bz;       // raybox-zero is reading (or not using).

  assign i_tex_in = {1'b0, tex_io}; // These are going into rbzero from the ROM.

  rbzero dut(
    .clk            (clk),
    .reset          (reset),
  `ifndef USE_POV_VIA_SPI_REGS
    // SPI slave for updating vectors:
    .i_ss_n         (i_ss_n),
    .i_sclk         (i_sclk),
    .i_mosi         (i_mosi),
  `else // USE_POV_VIA_SPI_REGS
    // POV regs are instead accessed via spi_registers (the inputs below)...
  `endif // USE_POV_VIA_SPI_REGS
    // SPI slave for everything else:
    .i_reg_ss_n     (i_reg_ss_n), // aka /CS, aka csb.
    .i_reg_sclk     (i_reg_sclk),
    .i_reg_mosi     (i_reg_mosi),

  `ifndef NO_EXTERNAL_TEXTURES
    // -------- NOTE: These are connected to the Flash ROM, in this testbench --------
    // SPI master for reading external flash ROM (e.g. texture data):
    .o_tex_csb      (o_tex_csb), // aka /CS
    .o_tex_sclk     (o_tex_sclk),
    .o_tex_out0     (o_tex_out0),
    .o_tex_oeb0     (o_tex_oeb0), // For QSPI io[0], oeb0==0 is OUTPUT, 1 is INPUT.
    .i_tex_in       (i_tex_in),
  `endif // NO_EXTERNAL_TEXTURES

    // Debug/demo signals:
  `ifdef USE_DEBUG_OVERLAY
    .i_debug_v      (i_debug_v),  // Show debug overlay for inspecting view vectors?
  `endif // USE_DEBUG_OVERLAY
  `ifdef USE_MAP_OVERLAY
    .i_debug_m      (i_debug_m),  // Show debug overlay for map
  `endif // USE_MAP_OVERLAY
  `ifdef TRACE_STATE_DEBUG
    .i_debug_t      (i_debug_t),  // Show debug overlay for the tracer FSM
  `endif // TRACE_STATE_DEBUG
    .i_inc_px       (i_inc_px),   // DEMO: Increment playerX
    .i_inc_py       (i_inc_py),   // DEMO: Increment playerY
  `ifndef NO_EXTERNAL_TEXTURES
    .i_gen_tex      (i_gen_tex),  // 1=Use bitwise-generated textures instead of SPI texture memory.
  `endif // NO_EXTERNAL_TEXTURES
    // VGA outputs:
    .hsync_n        (hsync_n),
    .vsync_n        (vsync_n),
    .rgb            (rgb),

    // Other outputs:
    .o_hblank       (o_hblank), // Asserted for the duration of the horizontal blanking interval.
    .o_vblank       (o_vblank), // Asserted for the duration of the vertical blanking interval.
    .o_hmax         (o_hmax),
    .o_vmax         (o_vmax),

    // Debug outputs:
    .o_vinf         (o_vinf), // Send out a copy of the VINF register, which can help with debugging 'reg' SPI.
    .o_playerX      (playerX),
    .o_playerY      (playerY),
    .o_facingX      (facingX),
    .o_facingY      (facingY),
    .o_vplaneX      (vplaneX),
    .o_vplaneY      (vplaneY),

    // hpos and vpos are currently supplied so a top module can do dithering,
    // but otherwise they're not really required, or even just bit-0 of each would do:
    .hpos           (hpos),
    .vpos           (vpos)
  );

  // W25Q128JVxIM texture_rom(
  //   .DIO    (tex_io[0]),  // SPI io0 (MOSI) - BIDIRECTIONAL
  //   .DO     (tex_io[1]),  // SPI io1 (MISO)
  //   .WPn    (tex_io[2]),  // SPI io2
  //   //.HOLDn  (1'b1),     // SPI io3. //NOTE: Not used in raybox-zero.
  //   .CSn    (o_tex_csb),  // SPI /CS
  //   .CLK    (o_tex_sclk)  // SPI SCLK
  // );


endmodule
