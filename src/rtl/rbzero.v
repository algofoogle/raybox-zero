`default_nettype none
// `timescale 1ns / 1ps

// `include "fixed_point_params.v"
// `include "helpers.v"

// These can be defined by the target (e.g. TT04 or FPGA) rather than inline here:
//`define USE_MAP_OVERLAY
//`define USE_DEBUG_OVERLAY
//`define TRACE_STATE_DEBUG  // Trace state is represented visually per each line on-screen.
//`define STANDBY_RESET // If defined use extra logic to avoid clocking regs during reset (for power saving/stability).
//`define RESET_TEXTURE_MEMORY // Should there be an explicit reset for local texture memory?
//`define RESET_TEXTURE_MEMORY_PATTERNED // If defined with RESET_TEXTURE_MEMORY, texture memory reset is a pattern instead of black.
//`define DEBUG_NO_TEXTURE_LOAD // If defined, prevent texture loading

module rbzero(
  input               clk,
  input               reset,
  // SPI slave for updating vectors:
  input               i_ss_n,
  input               i_sclk,
  input               i_mosi,
  // SPI slave for everything else:
  input               i_reg_ss_n, // aka /CS, aka csb.
  input               i_reg_sclk,
  input               i_reg_mosi,
  // SPI master for reading external flash ROM (e.g. texture data):
  output              o_tex_csb, // aka /CS
  output              o_tex_sclk,
  output              o_tex_out0,
  output              o_tex_oeb0, // For QSPI io[0], oeb0==0 is OUTPUT, 1 is INPUT.
  input   [3:0]       i_tex_in,
  // Debug/demo signals:
  input               i_debug_v,  // Show debug overlay for inspecting view vectors?
  input               i_debug_m,  // Show debug overlay for map
  input               i_debug_t,  // Show debug overlay for the tracer FSM
  input               i_inc_px,   // DEMO: Increment playerX
  input               i_inc_py,   // DEMO: Increment playerY
  input               i_gen_tex,  // 1=Use bitwise-generated textures instead of SPI texture memory.
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

  localparam [9:0]  H_VIEW    = 640;
  localparam        HALF_SIZE = H_VIEW/2;
  localparam        MAP_WBITS = 5; // 32x...
  localparam        MAP_HBITS = 5; // ...32 map
`ifdef USE_MAP_OVERLAY
  localparam        MAP_SCALE = 3;
`endif//USE_MAP_OVERLAY

  assign o_vinf = vinf;

`ifdef STANDBY_RESET
  wire no_standby = !reset;  // Regs standby mode driven by reset.
`else
  wire no_standby = 1'b1; // CONSTANT: Regs standby disabled completely. Should get optimised out.
`endif

  // --- VGA sync driver: ---
  wire hsync, vsync;
  wire visible;
  assign {hsync_n,vsync_n} = ~{hsync,vsync};
  // wire [9:0] hpos;
  // wire [9:0] vpos;
  wire hmax, vmax;
  assign {o_hmax,o_vmax} = {hmax,vmax};
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
  //NOTE: Would it be possible to do primitive texture 'filtering' using 50/50 checker dither for texture sub-pixels?
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
    .hit      (wall_en),
    .gen_tex_rgb(gen_tex_rgb)
  );

  wire `RGB gen_tex_rgb; // i_gen_tex selects between this or external texture SPI memory.
  //SMELL: i_gen_tex==1 doesn't disable SPI texture memory access.

  // Texture pixel colour comes from looking up within the texel colour buffers
  // we loaded during the Texture SPI read sequence below...
  assign wall_rgb =
    i_gen_tex ? gen_tex_rgb:  // If i_gen_tex==1, use generated texture.
    // Otherwise, use texture from SPI texture memory...
    {
      {tex_b1[texv], tex_b0[texv]},
      {tex_g1[texv], tex_g0[texv]},
      {tex_r1[texv], tex_r0[texv]}
    };

  //SMELL: Put the following into another module, or move it into row_render?
  // Load the next line's wall slice texture via QSPI.
  // This assumes that by the time the SPI sequence starts, the wall slice address
  // is already known, i.e. wall_tracer has determined traced_wall/side/texu,
  // and they're all stable for the remainder of the line...
  wire [1:0] shifted_wall_id = wall_hot-1'd1;
  // Address we'd start reading from if it wasn't for adding the texture addends:
  wire [23:0] wall_slice_base_address = {9'd0, shifted_wall_id, side_hot, texu_hot, 6'd0};
  // Actual start address we'll send to the SPI memory to start reading from (i.e. base address offset by texture addend):
  wire [23:0] wall_slice_start_address = wall_slice_base_address + texadd[shifted_wall_id];
  // Wall slice BASE address pattern (i.e. without addend):
  // ------------------000000 (Covers 0..63 texels in the slice)
  // ------------UUUUUU------ texu (wall slice 0..63)
  // -----------S------------ side 0 or 1
  // ---------WW------------- Wall ID 0..3
  // 000000000--------------- Unused (extra address range)
  //NOTE: Each texel is currently 8 bits in the ROM, i.e. 64 bytes per slice,
  // representing 64 pixels. In each byte, the packing is XBGRXBGR, i.e.
  // X---X--- Unused -- io3 input might not always be available as an IO pad.
  // -B---B-- B[0:1] //NOTE: These are all LSB first.
  // --G---G- G[0:1]
  // ---R---R R[0:1]
  localparam [9:0] TSPI_CMD_LEN         = 8;  // Num bits to send for SPI command.
  localparam [9:0] TSPI_ADDR_LEN        = 24; // Num bits to send for SPI address.
  localparam [9:0] TSPI_DUMMY_LEN       = 8;  // Num clocks in dummy wait after sending ADDR.
  localparam [9:0] TSPI_PREAMBLE_LEN    = TSPI_CMD_LEN + TSPI_ADDR_LEN + TSPI_DUMMY_LEN; // Combined CMD+ADDR+DUMMY bit length.
  localparam [9:0] TSPI_TEXEL_COUNT     = 64;
  localparam [9:0] TSPI_READ_LEN        = TSPI_TEXEL_COUNT<<1; // For now: 128 QSPI nibbles, i.e. 64 bytes, 1 byte per texel.
  localparam [9:0] TSPI_STREAM_LEN      = TSPI_PREAMBLE_LEN + TSPI_READ_LEN; // Total SCLK cycles for full stream.
  localparam [9:0] TSPI_HPOS_READ_START = H_VIEW - TSPI_PREAMBLE_LEN; // hpos value when we can start SPI stream.
  // localparam [9:0] TSPI_HPOS_READ_STOP  = TSPI_HPOS_READ_START + TSPI_STREAM_LEN; // hpos value when SPI stream ends.
  reg [TSPI_TEXEL_COUNT-1:0] tex_r1, tex_r0;
  reg [TSPI_TEXEL_COUNT-1:0] tex_g1, tex_g0;
  reg [TSPI_TEXEL_COUNT-1:0] tex_b1, tex_b0;
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
  wire tspi_data_present = (tspi_state >= TSPI_PREAMBLE_LEN && tspi_state < TSPI_STREAM_LEN);
  //NOTE: BEWARE: Below, posedge of SPI_SCLK (not clk) is used, because this is where MISO output is stable...
  always @(posedge o_tex_sclk) begin
`ifdef RESET_TEXTURE_MEMORY
    // This is reset logic for the texture memory DFFs; not normally needed, and included for debugging.
    if (reset) begin
      `ifdef RESET_TEXTURE_MEMORY_PATTERNED
        tex_r0 <= 64'b1111_1111__1111_1111___1111_1111__1111_1111____0000_0000__0000_0000___0000_0000__0000_0000;
        tex_r1 <= 64'b1111_1111__1111_1111___0000_0000__0000_0000____1111_1111__1111_1111___0000_0000__0000_0000;
        tex_g0 <= 64'b1111_1111__0000_0000___1111_1111__0000_0000____1111_1111__0000_0000___1111_1111__0000_0000;
        tex_g1 <= 64'b1111_0000__1111_0000___1111_0000__1111_0000____1111_0000__1111_0000___1111_0000__1111_0000;
        tex_b0 <= 64'b1100_1100__1100_1100___1100_1100__1100_1100____1100_1100__1100_1100___1100_1100__1100_1100;
        tex_b1 <= 64'b1010_1010__1010_1010___1010_1010__1010_1010____1010_1010__1010_1010___1010_1010__1010_1010;
      `else
        tex_r0 <= 64'b0;
        tex_r1 <= 64'b0;
        tex_g0 <= 64'b0;
        tex_g1 <= 64'b0;
        tex_b0 <= 64'b0;
        tex_b1 <= 64'b0;
      `endif
    end else
`endif // RESET_TEXTURE_MEMORY
    if (tspi_data_present && no_standby) begin
`ifndef DEBUG_NO_TEXTURE_LOAD
      // Nibbles are streaming out via io[3:0], so shift them into our buffers...
      //NOTE: i_tex_in[0] is discarded for now.
      if (0==tspi_state[0]) begin
        // Even nibble (colour LSB):
        tex_r0 <= {i_tex_in[0], tex_r0[TSPI_TEXEL_COUNT-1:1]};
        tex_g0 <= {i_tex_in[1], tex_g0[TSPI_TEXEL_COUNT-1:1]};
        tex_b0 <= {i_tex_in[2], tex_b0[TSPI_TEXEL_COUNT-1:1]};
      end else begin
        // Odd nibble (colour MSB):
        tex_r1 <= {i_tex_in[0], tex_r1[TSPI_TEXEL_COUNT-1:1]};
        tex_g1 <= {i_tex_in[1], tex_g1[TSPI_TEXEL_COUNT-1:1]};
        tex_b1 <= {i_tex_in[2], tex_b1[TSPI_TEXEL_COUNT-1:1]};
      end
`endif // DEBUG_NO_TEXTURE_LOAD
    end
  end
  // Set dir of io[0] to INPUT once we hit the DUMMY part of the preamble
  // (and beyond). Otherwise, oeb0==0, meaning io[0] is OUTPUT.
  assign o_tex_oeb0 = (tspi_state >= 32);
  // This is a simple way to work out what data to present at MOSI (io[0])
  // during the SPI preamble:
  wire [7:0] tspi_cmd = 8'h6B; // Quad Output Fast Read Array (6Bh).
  assign o_tex_out0 =
    (tspi_state<8)
      ? tspi_cmd[7-tspi_state]:                   // CMD[7:0]
    (tspi_state<32)
      ? wall_slice_start_address[31-tspi_state]:  // ADDR[23:0]
    1'b0;                                         // 0 for all other preamble bits and beyond.
/////SMELL: UPDATE THE TABLE BELOW!!!!!!!!!
  // The above combo logic for o_tex_csb and o_tex_mosi gives us the following output
  // for each 'state':
  //
  // | state    | o_tex_csb| o_tex_out0| note                                   |
  // |---------:|---------:|----------:|:---------------------------------------|
  // | (n)      | 1        | 0         | (any state not otherwise covered)      |
  // |  0       | 0        | 0         | CMD[7]; chip ON                        |
  // |  1       | 0        | 0         | CMD[6]                                 |
  // |  2       | 0        | 0         | CMD[5]                                 |
  // |  3       | 0        | 0         | CMD[4]                                 |
  // |  4       | 0        | 0         | CMD[3]                                 |
  // |  5       | 0        | 0         | CMD[2]                                 |
  // |  6       | 0        | 1         | CMD[1]                                 |
  // |  7       | 0        | 1         | CMD[0] => CMD 03h (READ) loaded.       |
  // |  8       | 0        | 0         | ADDR[23]                               |
  // |  9       | 0        | 0         | ADDR[22]                               |
  // | 10       | 0        | 0         | ADDR[21]                               |
  // | 11       | 0        | 0         | ADDR[20]                               |
  // | 12       | 0        | 0         | ADDR[19]                               |
  // | 13       | 0        | 0         | ADDR[18]                               |
  // | 14       | 0        | 0         | ADDR[17]                               |
  // | 15       | 0        | 0         | ADDR[16]                               |
  // | 16       | 0        | 0         | ADDR[15]                               |
  // | 17       | 0        | 0         | ADDR[14]                               |
  // | 18       | 0        | 0         | ADDR[13]                               |
  // | 19       | 0        | 0         | ADDR[12]                               |
  // | 20       | 0        | wsa[8]    | ADDR[11]                               |
  // | 21       | 0        | wsa[7]    | ADDR[10]                               |
  // | 22       | 0        | wsa[6]    | ADDR[9]                                |
  // | 23       | 0        | wsa[5]    | ADDR[8]                                |
  // | 24       | 0        | wsa[4]    | ADDR[7]                                |
  // | 25       | 0        | wsa[3]    | ADDR[6]                                |
  // | 26       | 0        | wsa[2]    | ADDR[5]                                |
  // | 27       | 0        | wsa[1]    | ADDR[4]                                |
  // | 28       | 0        | wsa[0]    | ADDR[3]                                |
  // | 29       | 0        | 0         | ADDR[2]                                |
  // | 30       | 0        | 0         | ADDR[1]                                |
  // | 31       | 0        | 0         | ADDR[0]                                |
  // | 32..95   | 0        | 0         | (64 states) MOSI=dummy, MISO=read bit  |
  // | 96       | 1        | 0         | Chip OFF                               |


  // texV scans the texture 'v' coordinate range with a step size of 'traced_texa'.
  //NOTE: Because of 'texVV = texV + traced_texVinit' above, texV might be relative to
  // a positive, 0, or negative starting point as calculated by wall_tracer.
  //SMELL: Move this into some other module, e.g. row_render?
  always @(posedge clk) if (no_standby) texV <= (hmax ? `Qmnc'd0 : texV + traced_texa);

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
    .mapdx    (mapdx),
    .mapdy    (mapdy),
    .mapdxw   (mapdxw),
    .mapdyw   (mapdyw),
    .texadd0  (texadd[0]),
    .texadd1  (texadd[1]),
    .texadd2  (texadd[2]),
    .texadd3  (texadd[3]),

    .load_new (visible_frame_end)
  );
  wire `RGB   color_sky     /* verilator public */;
  wire `RGB   color_floor   /* verilator public */;
  wire [5:0]  floor_leak    /* verilator public */;
  wire [5:0]  otherx        /* verilator public */;
  wire [5:0]  othery        /* verilator public */;
  wire [5:0]  texv_shift    /* verilator public */;
  wire        vinf          /* verilator public */;
  wire [5:0]  mapdx         /* verilator public */;
  wire [5:0]  mapdy         /* verilator public */;
  wire [1:0]  mapdxw        /* verilator public */;
  wire [1:0]  mapdyw        /* verilator public */;
  wire [23:0] texadd [0:3]  /* verilator public */;

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
    .i_otherx(otherx), .i_othery(othery),
    .i_mapdx(mapdx), .i_mapdy(mapdy),
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
  wire [1:0]  wall_hot;
  wire        side_hot;
  wire [5:0]  texu_hot;

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
    .playerX(playerX),  .playerY(playerY),
    .facingX(facingX),  .facingY(facingY),
    .vplaneX(vplaneX),  .vplaneY(vplaneY),
    // Special map overrides:
    .otherx (otherx),   .othery (othery),
    .mapdx  (mapdx),    .mapdy  (mapdy),
    .mapdxw (mapdxw),   .mapdyw (mapdyw),
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
    .o_texVinit(traced_texVinit),
    .o_wall_hot(wall_hot),
    .o_side_hot(side_hot),
    .o_texu_hot(texu_hot)
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
    .debug_en (debug_en & i_debug_v), .debug_rgb(debug_rgb),
`else//!USE_DEBUG_OVERLAY
    .debug_en (1'b0), .debug_rgb(6'd0),
`endif//USE_DEBUG_OVERLAY

`ifdef USE_MAP_OVERLAY
    .map_en   (map_en & i_debug_m), .map_rgb(map_rgb),
`else//!USE_MAP_OVERLAY
    .map_en   (1'b0), .map_rgb(6'd0),
`endif//USE_MAP_OVERLAY

`ifdef TRACE_STATE_DEBUG
    .show_trace_debug(i_debug_t),
    .trace_state_debug(trace_state), //DEBUG.
`endif//TRACE_STATE_DEBUG

    .wall_en  (wall_en),
    .wall_rgb (wall_rgb),
    .bg_rgb   (bg),
    .out      (rgb)
  );

endmodule
