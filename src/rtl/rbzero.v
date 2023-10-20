`default_nettype none
`timescale 1ns / 1ps

`include "fixed_point_params.v"
`include "helpers.v"

//SMELL: These should probably be defined by the target (e.g. TT04 or FPGA) rather than inline here:
// `define USE_MAP_OVERLAY
`define USE_DEBUG_OVERLAY
// `define TRACE_STATE_DEBUG  // Trace state is represented visually per each line on-screen.

module rbzero(
  input               clk,
  input               reset,
  // SPI slave for updating vectors:
  input               i_sclk,
  input               i_mosi,
  input               i_ss_n,
  // SPI slave for everything else:
  input               i_reg_ss_n, // aka /CS, aka csb.
  input               i_reg_sclk,
  input               i_reg_mosi,
  // SPI master for reading external flash ROM (e.g. texture data):
  output              o_tex_csb, // aka /CS
  output              o_tex_sclk,
  output              o_tex_mosi,
  input               i_tex_miso,
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

  localparam [9:0]  H_VIEW    = 640;
  localparam        HALF_SIZE = H_VIEW/2;
  localparam        MAP_WBITS = 5;
  localparam        MAP_HBITS = 5;
`ifdef USE_MAP_OVERLAY
  localparam        MAP_SCALE = 3;
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
  wire `F     texVshift = {{(`Qm-9){1'b0}},texv_shift,{(`Qn+3){1'b0}}};
  wire `F     texVV = texV + traced_texVinit + texVshift; //NOTE: Instead of having this adder, could just use traced_texVinit as the texV hmax reset (though it does make it 'gritty').
  wire [5:0]  texv =
    (texVV >= 0 || vinf)
      ? texVV[8:3]
      : 6'd0;                       // Clamp to 0 to fix texture underflow.

  // At vdist of 1.0, a 64p texture is stretched to 512p, hence texv is 64/512 (>>3) of int(texV).
  //NOTE: Would it be possible to do primitive texture 'filtering' using 50/50 checker dither for texxture sub-pixels?
  row_render row_render(
    // Inputs:
    .wall     (traced_wall),
    .side     (traced_side),
    .size     (traced_size),
    .texu     (traced_texu),        //SMELL: Need to clamp texu/v so they don't wrap due to fixed-point precision loss.
    .texv     (texv),
    .vinf     (vinf),
    .leak     (floor_leak),
    .hpos     (hpos),
    // Outputs:
    // .rgb      (wall_rgb),
    .hit      (wall_en)
  );

  // Texture pixel colour comes from looking up within the 'g1' buffer we loaded
  // during the Texture SPI read sequence...
  assign wall_rgb = {2'b00, {g1[texv],~traced_side}, 2'b00};

  //SMELL: Put the following into another module, or move it into row_render?
  // Load the next line's wall slice texture via SPI.
  // This assumes that by the time the SPI sequence starts, the wall slice address
  // is already known, i.e. wall_tracer has determined traced_wall/side/texu,
  // and they're all stable for the remainder of the line...
  wire [1:0] shifted_wall_id = traced_wall-1;
  wire [8:0] wall_slice_address = {shifted_wall_id, traced_side, traced_texu};
  //NOTE: Wall slice address, when used to form the SPI address, is actually
  // shifted left 3 bits, i.e. 8-byte-aligned, i.e. 64 pixels.
  localparam [9:0] TSPI_CMD_LEN         = 8;  // Num bits to send for SPI command.
  localparam [9:0] TSPI_ADDR_LEN        = 24; // Num bits to send for SPI address.
  localparam [9:0] TSPI_PREAMBLE_LEN    = TSPI_CMD_LEN + TSPI_ADDR_LEN; // Combined CMD+ADDR bit length.
  localparam [9:0] TSPI_READ_LEN        = 64; // For now: 64 bits, for 64 1-bit pixels.
  localparam [9:0] TSPI_STREAM_LEN      = TSPI_PREAMBLE_LEN + TSPI_READ_LEN; // Total SCLK cycles for full stream.
  localparam [9:0] TSPI_HPOS_READ_START = H_VIEW - TSPI_PREAMBLE_LEN; // hpos value when we can start SPI stream.
  localparam [9:0] TSPI_HPOS_READ_STOP  = TSPI_HPOS_READ_START + TSPI_STREAM_LEN; // hpos value when SPI stream ends.
  reg [TSPI_READ_LEN-1:0] g1;
  // Inverted clk directly drives texture SPI SCLK at full speed, continuously:
  assign o_tex_sclk = ~clk;
  // Why inverted? Because this allows us to set up MOSI on rising clk edge,
  // then it's stable when spi_sclk would subsequently rise to clock that MOSI
  // bit into the SPI chip.
  //
  // Texture SPI states follow hpos, with an offset based on line end:
  wire [9:0] tspi_state = hpos - TSPI_HPOS_READ_START;
  // Texture SPI chip is ON for the whole duration of our SPI read stream:
  assign o_tex_csb = ~(tspi_state < TSPI_STREAM_LEN); // Active LOW.
  // This screen-time range is when MISO is presenting data, and we store it:
  wire tspi_data_present = (tspi_state >= TSPI_PREAMBLE_LEN && tspi_state < TSPI_STREAM_LEN); //(hpos >= TSPI_HPOS_READ_START && hpos < TSPI_HPOS_READ_STOP);
  //NOTE: Could/should we instead use 'tspi_state' instead of hpos comparison, above?
  //NOTE: BEWARE: Below, posedge of SPI_SCLK (not clk) is used, because this is where MISO output is stable...
  always @(posedge o_tex_sclk) begin
    if (tspi_data_present) begin
      // Bits are streaming out via MISO, so shift them into our buffer:
      g1 <= {i_tex_miso, g1[TSPI_READ_LEN-1:1]};
    end
  end
  // This is a simple way to work out what data to present at MOSI during the
  // SPI preamble:
  assign o_tex_mosi =
    (tspi_state== 6 || tspi_state== 7)      // CMD[1:0] is 'b11.
      ? 1'b1:
    (tspi_state>=20 && tspi_state<=28)      // ADDR[11:3] is wsa[8:0].
      ? wall_slice_address[28-tspi_state]:
    1'b0;                                   // 0 for all other preamble bits
                                            // and beyond.
  // The above combo logic for o_tex_csb and o_tex_mosi gives us the following output
  // for each 'state':
  //
  // | state    | o_tex_csb| o_tex_mosi| note                             |
  // |---------:|---------:|---------:|:----------------------------------|
  // | (n)      | 1        | 0        | (any state not otherwise covered) |
  // |  0       | 0        | 0        | CMD[7]; chip ON                   |
  // |  1       | 0        | 0        | CMD[6]                            |
  // |  2       | 0        | 0        | CMD[5]                            |
  // |  3       | 0        | 0        | CMD[4]                            |
  // |  4       | 0        | 0        | CMD[3]                            |
  // |  5       | 0        | 0        | CMD[2]                            |
  // |  6       | 0        | 1        | CMD[1]                            |
  // |  7       | 0        | 1        | CMD[0] => CMD 03h (READ) loaded.  |
  // |  8       | 0        | 0        | ADDR[23]                          |
  // |  9       | 0        | 0        | ADDR[22]                          |
  // | 10       | 0        | 0        | ADDR[21]                          |
  // | 11       | 0        | 0        | ADDR[20]                          |
  // | 12       | 0        | 0        | ADDR[19]                          |
  // | 13       | 0        | 0        | ADDR[18]                          |
  // | 14       | 0        | 0        | ADDR[17]                          |
  // | 15       | 0        | 0        | ADDR[16]                          |
  // | 16       | 0        | 0        | ADDR[15]                          |
  // | 17       | 0        | 0        | ADDR[14]                          |
  // | 18       | 0        | 0        | ADDR[13]                          |
  // | 19       | 0        | 0        | ADDR[12]                          |
  // | 20       | 0        | wsa[8]   | ADDR[11]                          |
  // | 21       | 0        | wsa[7]   | ADDR[10]                          |
  // | 22       | 0        | wsa[6]   | ADDR[9]                           |
  // | 23       | 0        | wsa[5]   | ADDR[8]                           |
  // | 24       | 0        | wsa[4]   | ADDR[7]                           |
  // | 25       | 0        | wsa[3]   | ADDR[6]                           |
  // | 26       | 0        | wsa[2]   | ADDR[5]                           |
  // | 27       | 0        | wsa[1]   | ADDR[4]                           |
  // | 28       | 0        | wsa[0]   | ADDR[3]                           |
  // | 29       | 0        | 0        | ADDR[2]                           |
  // | 30       | 0        | 0        | ADDR[1]                           |
  // | 31       | 0        | 0        | ADDR[0]                           |
  // | 32..95   | 0        | 0        | (64 states) MOSI=dummy, MISO=read bit |
  // | 96       | 1        | 0        | Chip OFF                          |


  // texV scans the texture 'v' coordinate range with a step size of 'traced_texa'.
  //NOTE: Because of 'texVV = texV + traced_texVinit' above, texV might be relative to
  // a positive, 0, or negative starting point as calculated by wall_tracer.
  //SMELL: Move this into some other module, e.g. row_render?
  always @(posedge clk) texV <= (hmax ? 20'd0 : texV + traced_texa);

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

  spi_registers spi_registers(
    .clk      (clk),
    .reset    (reset),

    .i_sclk   (i_reg_sclk),
    .i_mosi   (i_reg_mosi),
    .i_ss_n   (i_reg_ss_n),

    .sky      (color_sky),
    .floor    (color_floor),
    .leak     (floor_leak),
    .otherx   (otherx),
    .othery   (othery),
    .vshift   (texv_shift),
    .vinf     (vinf),

    .load_new (visible_frame_end)
  );
  wire `RGB   color_sky     /* verilator public */;
  wire `RGB   color_floor   /* verilator public */;
  wire [5:0]  floor_leak    /* verilator public */;
  wire [5:0]  otherx        /* verilator public */;
  wire [5:0]  othery        /* verilator public */;
  wire [5:0]  texv_shift    /* verilator public */;
  wire        vinf          /* verilator public */;

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
    .otherx   (otherx),
    .othery   (othery),
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
    ? color_floor   // Default is light grey for left (or bottom) side.
    : color_sky;    // Default is dark grey for right (or top) side.
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
