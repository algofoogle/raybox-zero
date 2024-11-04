`default_nettype none
// `timescale 1ns / 1ps

`ifndef RBZ_OPTIONS
  // These are Verilator/VSCode hints, only. RBZ_OPTIONS should otherwise always be defined for deploying raybox-zero.
  `include "helpers.v"
  `include "fixed_point_params.v"
`endif

// Well this is a funky SPI module! I'm sure there's a better way to do this...
// Should it really be storing registers itself?

module spi_registers(
  input               clk,
  input               reset,
  input               i_sclk, i_ss_n, i_mosi, // SPI input.

  output reg  `RGB    sky, floor,     // Sky and floor colours.
  output reg  [5:0]   leak,           // Floor 'leak'.
  output reg  [5:0]   otherx, othery, // 'Other' map cell position.
  output reg  [5:0]   vshift,         // Texture V axis shift (texv addend).
  output reg          vinf,           // Infinite V/height setting.
  output              o_leakfixed,    // Is LEAK fixed to the ground (1), or floating (0)?
  output reg  [5:0]   mapdx, mapdy,   // Map 'dividing walls' on X and Y. 0=none
  output reg  [1:0]   mapdxw, mapdyw, // Map dividing wall, wall IDs (texture) for X and Y respectively
`ifndef NO_EXTERNAL_TEXTURES
  output reg  [23:0]  texadd0,        // Texture address addend 0
  output reg  [23:0]  texadd1,        // Texture address addend 1
  output reg  [23:0]  texadd2,        // Texture address addend 2
  output reg  [23:0]  texadd3,        // Texture address addend 3
`endif // NO_EXTERNAL_TEXTURES

  input               i_inc_px, i_inc_py, // Demo overrides for playerX/Y inc. If either is asserted, SPI POV loads are masked out and 'ready' is cleared.
  output `F           playerX, playerY,
  output `F           facingX, facingY,
  output `F           vplaneX, vplaneY,

  input               load_new        // Will go high at the moment that buffered data can go live.
);

  wire manual_pov_inc_needed  = i_inc_px | i_inc_py;        // Manual playerX/Y increment in effect (i.e. demo mode)?

// ===== COMMAND/REGISTER PARAMETERS AND SIZING =====

  localparam CMD_SKY    = 0;  localparam LEN_SKY    =  6; // Set sky colour (6b data)
  localparam CMD_FLOOR  = 1;  localparam LEN_FLOOR  =  6; // Set floor colour (6b data)
  localparam CMD_LEAK   = 2;  localparam LEN_LEAK   =  6; // Set floor 'leak' (in texels; 6b data)
  localparam CMD_OTHER  = 3;  localparam LEN_OTHER  = 12; // Set 'other wall cell' position: X and Y, both 6b each, for a total of 12b.
  localparam CMD_VSHIFT = 4;  localparam LEN_VSHIFT =  6; // Set texture V axis shift (texv addend). //SMELL: Make this more bits for finer grain.
`ifdef USE_LEAK_FIXED
  localparam CMD_VOPTS  = 5;  localparam LEN_VOPTS  =  2; // Bits [1:0] = {VINF,LEAK_FIXED}
`else // USE_LEAK_FIXED
  localparam CMD_VINF   = 5;  localparam LEN_VINF   =  1; // Set infinite V mode (infinite height/size).
`endif // USE_LEAK_FIXED
  localparam CMD_MAPD   = 6;  localparam LEN_MAPD   = 16; // Set mapdx,mapdy, mapdxw,mapdyw.
`ifndef NO_EXTERNAL_TEXTURES
  localparam CMD_TEXADD0= 7;  localparam LEN_TEXADD0= 24;
  localparam CMD_TEXADD1= 8;  localparam LEN_TEXADD1= 24;
  localparam CMD_TEXADD2= 9;  localparam LEN_TEXADD2= 24;
  localparam CMD_TEXADD3=10;  localparam LEN_TEXADD3= 24;
`endif
  localparam CMD_POV    =11;  localparam LEN_POV    = (15*2)+(11*2)+(11*2); // player(X,Y), facing(X,Y), vplane(X,Y): 74 bits
  //NOTE: Reserve CMD 12 and above for 'extended' commands, i.e. upper 2 bits high means:
  // 11ccccXX:  cccc = command, XX is 2 more bits for payload (helps POV fit in 9 bytes).
  // i.e. cccc==1011 (POV) can be the better packing.
  // This also enables additional commands:
  // - 1100
  // - 1101
  // - 1110
  // - 1111: Maybe can mean All commands 0..6 (53 bits)?
  // ALSO: Support different LEAK modes (fixed vs. floating).
  // Also, a sequence of 1111YYYY could mean YYYY defines additional extended commands.

// `ifdef NO_EXTERNAL_TEXTURES
//   localparam SPI_BUFFER_SIZE = 16; //NOTE: Should be set to whatever the largest LEN_* value is above.
// `else // NO_EXTERNAL_TEXTURES
//   localparam SPI_BUFFER_SIZE = 24; //NOTE: Should be set to whatever the largest LEN_* value is above.
// `endif
  localparam SPI_BUFFER_SIZE = LEN_POV; //NOTE: Should be set to whatever the largest LEN_* value is above.
  localparam SPI_BUFFER_LIMIT = SPI_BUFFER_SIZE-1;

  localparam SPI_CMD_BITS = 4;

// ===== GOOD STARTING PARAMETERS FOR RESET =====

`ifdef QUARTUS
  localparam SCALER = 1<<9; // The vectors below use 9 fractional bits.
  localparam real FSCALER = SCALER;
  // An interesting starting position for demo purposes:
  localparam `UQ6_9 playerInitX  = 11.500000 * FSCALER;
  localparam `UQ6_9 playerInitY  = 10.500000 * FSCALER;
  localparam `SQ2_9 facingInitX  =  0.720137 * FSCALER;
  localparam `SQ2_9 facingInitY  = -0.693832 * FSCALER;
  localparam `SQ2_9 vplaneInitX  =  0.346916 * FSCALER;
  localparam `SQ2_9 vplaneInitY  =  0.360069 * FSCALER;
`else
  // An interesting starting position for demo purposes:
  //NOTE: The right-shift below is because realF() assumes `Qn (say, 10 or 12) fractional bits, but we're only using 9:
  localparam SHIFT_Qn9 = `Qn-9;
  localparam `UQ6_9 playerInitX  = 15'($rtoi(`realF(11.500000))>>SHIFT_Qn9);
  localparam `UQ6_9 playerInitY  = 15'($rtoi(`realF(10.500000))>>SHIFT_Qn9);
  localparam `SQ2_9 facingInitX  = 11'($rtoi(`realF( 0.720137))>>SHIFT_Qn9);
  localparam `SQ2_9 facingInitY  = 11'($rtoi(`realF(-0.693832))>>SHIFT_Qn9);
  localparam `SQ2_9 vplaneInitX  = 11'($rtoi(`realF( 0.346916))>>SHIFT_Qn9);
  localparam `SQ2_9 vplaneInitY  = 11'($rtoi(`realF( 0.360069))>>SHIFT_Qn9);
`endif
  localparam skyColorInit       = 6'b01_01_01;
  localparam floorColorInit     = 6'b10_10_10;

// ===== TRUNCATED-TO-FULL-RANGE VECTOR EXTENSION =====

  // Registered versions of the truncated vectors, before they get padded up to `F (SQ10.10) format on output ports.
  reg `UQ6_9 playerRX, playerRY;
  reg `SQ2_9 facingRX, facingRY;
  reg `SQ2_9 vplaneRX, vplaneRY;
  //NOTE: These are final registers (not buffered). The other final registers are declared as 'output reg' ports in this module.

  // The below extends our more-truncated vectors (at various Qm.n precisions) to conventional `F ports...

  // playerX/Y are received initially as truncated to UQ6.9...
  // This is enough for the player moving within a 64x64 map to a granularity of 1/512 units.
  // This granularity is ~0.002 of a block. Given a block 'feels' like about 1.8m wide this granularity is about ~3.5mm.
  //NOTE: Sign bit not needed (hence 0) because player position should never be negative anyway? i.e. it's in the range [0,64)
  localparam PadUQ6_9Hi = `Qm-6;
  localparam PadUQ6_9Lo = `Qn-9;
  assign playerX = { {PadUQ6_9Hi{1'b0}}, playerRX, {PadUQ6_9Lo{1'b0}} };
  assign playerY = { {PadUQ6_9Hi{1'b0}}, playerRY, {PadUQ6_9Lo{1'b0}} };

  // facing/vplaneX/Y are received as truncated to SQ2.9 before being sign-extended to conventional `F ports...
  // These have much smaller magnitude because normally each vector won't exceed 1.0...
  // we allow a range of [-2.0,+2.0) because that's more than enough for some effects, FOV control (?) etc.
  localparam PadSQ2_9Hi = `Qm-1; // Because of sign bit repetition, this is NOT '-2'
  localparam PadSQ2_9Lo = `Qn-9;
  assign facingX = { {PadSQ2_9Hi{facingRX[1]}}, facingRX[0:-9], {PadSQ2_9Lo{1'b0}} };
  assign facingY = { {PadSQ2_9Hi{facingRY[1]}}, facingRY[0:-9], {PadSQ2_9Lo{1'b0}} };
  assign vplaneX = { {PadSQ2_9Hi{vplaneRX[1]}}, vplaneRX[0:-9], {PadSQ2_9Lo{1'b0}} };
  assign vplaneY = { {PadSQ2_9Hi{vplaneRY[1]}}, vplaneRY[0:-9], {PadSQ2_9Lo{1'b0}} };

`ifdef USE_LEAK_FIXED
  reg leakfixed;
  assign o_leakfixed = leakfixed;
`else // USE_LEAK_FIXED
  assign o_leakfixed = 1'b0;
`endif

  // Values in waiting:
  reg `RGB    buf_sky;
  reg `RGB    buf_floor;
  reg [5:0]   buf_leak;
  reg [5:0]   buf_otherx;
  reg [5:0]   buf_othery;
  reg [5:0]   buf_vshift;
  reg         buf_vinf;
`ifdef USE_LEAK_FIXED
  reg         buf_leakfixed;
`endif // USE_LEAK_FIXED
  reg [5:0]   buf_mapdx;
  reg [5:0]   buf_mapdy;
  reg [1:0]   buf_mapdxw;
  reg [1:0]   buf_mapdyw;
`ifndef NO_EXTERNAL_TEXTURES
  reg [23:0]  buf_texadd0;
  reg [23:0]  buf_texadd1;
  reg [23:0]  buf_texadd2;
  reg [23:0]  buf_texadd3;
`endif // NO_EXTERNAL_TEXTURES
  // POV registers:
  // SMELL: Make bit ranges parametric here, and for other POV data above!
  reg [14:0]  buf_playerRX, buf_playerRY;
  reg [10:0]  buf_facingRX, buf_facingRY;
  reg [10:0]  buf_vplaneRX, buf_vplaneRY;
  //SMELL: If we don't want to waste space with all these extra registers,
  // could we just transfer one 'waiting' value into a SINGLE selected register?
  // Only problem with doing so is that we can then only update 1 per frame
  // ...unless we implement the 'immediate' option and the host waits for VBLANK
  // in order for each to be live-loaded (safely).


// ===== SPI INPUT SYNCHRONISATION =====

  // The following synchronises the 3 SPI inputs using the typical DFF pair approach
  // for metastability avoidance at the 2nd stage, but note that for SCLK this
  // rolls into a 3rd stage so that stages 2 and 3 can detect a rising edge...

  // Sync SCLK using 3-bit shift reg (to catch rising/falling edges):
  reg [2:0] sclk_buffer;
  always @(posedge clk) sclk_buffer <= (reset ? 3'd0 : {sclk_buffer[1:0], i_sclk});
  wire sclk_rise = (sclk_buffer[2:1]==2'b01);

  // Sync /SS; only needs 2 bits because we don't care about edges:
  reg [1:0] ss_buffer;
  always @(posedge clk) ss_buffer <= (reset ? 2'd0 : {ss_buffer[0], i_ss_n});
  wire ss_active = ~ss_buffer[1];

  // Sync MOSI:
  reg [1:0] mosi_buffer;
  always @(posedge clk) mosi_buffer <= (reset ? 2'd0 : {mosi_buffer[0], i_mosi});
  wire mosi = mosi_buffer[1];
  //SMELL: Do we actually need to sync MOSI? It should be stable when we check it at the SCLK rising edge.

  wire spi_frame_end =
    spi_counter == (
      SPI_CMD_BITS + (
        (spi_cmd == CMD_SKY     ) ?   LEN_SKY:
        (spi_cmd == CMD_FLOOR   ) ?   LEN_FLOOR:
        (spi_cmd == CMD_LEAK    ) ?   LEN_LEAK:
        (spi_cmd == CMD_OTHER   ) ?   LEN_OTHER:
        (spi_cmd == CMD_VSHIFT  ) ?   LEN_VSHIFT:
        (spi_cmd == CMD_MAPD    ) ?   LEN_MAPD:
`ifndef NO_EXTERNAL_TEXTURES
        (spi_cmd == CMD_TEXADD0 ) ?   LEN_TEXADD0:
        (spi_cmd == CMD_TEXADD1 ) ?   LEN_TEXADD1:
        (spi_cmd == CMD_TEXADD2 ) ?   LEN_TEXADD2:
        (spi_cmd == CMD_TEXADD3 ) ?   LEN_TEXADD3:
`endif // NO_EXTERNAL_TEXTURES
        (spi_cmd == CMD_POV     ) ?   LEN_POV:
`ifdef USE_LEAK_FIXED
      /*(spi_cmd == CMD_VOPTS   ) ?*/ LEN_VOPTS
`else // USE_LEAK_FIXED
      /*(spi_cmd == CMD_VINF    ) ?*/ LEN_VINF
`endif // USE_LEAK_FIXED
      ) - 1
    );


// ===== MAIN SPI CONTROL/PAYLOAD REGISTERS =====

  reg [6:0]                 spi_counter; // To count largest supported frame (74 for vectors, 0..73).
  reg [SPI_CMD_BITS-1:0]    spi_cmd;
  reg [SPI_BUFFER_LIMIT:0]  spi_buffer; // Receives the SPI data (after the command).
  reg                       spi_done;
  

// ===== MAIN SPI CLOCKED LOGIC =====

  always @(posedge clk) begin

    // spi_counter:
    if (reset)
      spi_counter <= 0;
    else if (!ss_active)
      spi_counter <= 0;
    else if (sclk_rise && spi_counter < SPI_CMD_BITS)
      spi_counter <= spi_counter + 1'd1;
    else if (sclk_rise && !spi_frame_end)
      spi_counter <= spi_counter + 1'd1;
    // Stall SPI counter at expected end of frame.

    // Load spi_cmd data:
    if (reset)
      spi_cmd <= 0;
    else if (!ss_active)
      spi_cmd <= 0;
    else if (sclk_rise && spi_counter < SPI_CMD_BITS)
      spi_cmd <= {spi_cmd[SPI_CMD_BITS-2:0], mosi};

    // Load spi_buffer data:
    if (reset)
      spi_buffer <= 0;
    else if (ss_active && sclk_rise && spi_counter >= SPI_CMD_BITS)
      spi_buffer <= {spi_buffer[SPI_BUFFER_LIMIT-1:0], mosi};

    // spi_done:
    if (reset)
      spi_done <= 0;
    else if (!ss_active)
      spi_done <= 0;
    else if (spi_done)
      spi_done <= 0;
    else if (sclk_rise && spi_counter < SPI_CMD_BITS)
      spi_done <= 0;
    else if (sclk_rise && spi_frame_end)
      spi_done <= 1;

    // Handle live values:
    if (reset) begin

      // Load default values into our live regs
      //SMELL: Could avoid having to do this by just using buf_* values, with forced load_new, and a 2-cycle reset:
      sky       <= skyColorInit;
      floor     <= floorColorInit;
      leak      <= 6'd0;
      otherx    <= 6'd0;
      othery    <= 6'd0;
      vshift    <= 6'd0;
      vinf      <= 1'b0;
`ifdef USE_LEAK_FIXED
      leakfixed <= 1'b0;
`endif // USE_LEAK_FIXED
      mapdx     <= 6'd0;
      mapdy     <= 6'd0;
      mapdxw    <= 2'd0;
      mapdyw    <= 2'd0;
`ifndef NO_EXTERNAL_TEXTURES
      texadd0   <= 24'd0;
      texadd1   <= 24'd0;
      texadd2   <= 24'd0;
      texadd3   <= 24'd0;
`endif // NO_EXTERNAL_TEXTURES
      playerRX  <= playerInitX;      playerRY  <= playerInitY;
      facingRX  <= facingInitX;      facingRY  <= facingInitY;
      vplaneRX  <= vplaneInitX;      vplaneRY  <= vplaneInitY;

    end else if (load_new) begin

      // Load from in-waiting buffers:
      sky       <= buf_sky;
      floor     <= buf_floor;
      leak      <= buf_leak;
      otherx    <= buf_otherx;
      othery    <= buf_othery;
      vshift    <= buf_vshift;
      vinf      <= buf_vinf;
`ifdef USE_LEAK_FIXED
      leakfixed <= buf_leakfixed;
`endif // USE_LEAK_FIXED
      mapdx     <= buf_mapdx;
      mapdy     <= buf_mapdy;
      mapdxw    <= buf_mapdxw;
      mapdyw    <= buf_mapdyw;
`ifndef NO_EXTERNAL_TEXTURES
      texadd0   <= buf_texadd0;
      texadd1   <= buf_texadd1;
      texadd2   <= buf_texadd2;
      texadd3   <= buf_texadd3;
`endif // NO_EXTERNAL_TEXTURES
      // POV registers:
      playerRX  <= buf_playerRX;  playerRY  <= buf_playerRY;
      facingRX  <= buf_facingRX;  facingRY  <= buf_facingRY;
      vplaneRX  <= buf_vplaneRX;  vplaneRY  <= buf_vplaneRY;
      if (manual_pov_inc_needed) begin
        // Override increment is in effect:
        if (i_inc_px) buf_playerRX <= buf_playerRX - 15'b1;
        if (i_inc_py) buf_playerRY <= buf_playerRY - 15'b1;
      end

    end

    // Handle loading in-waiting buffer regs from spi_buffer:
    if (reset) begin

      buf_sky       <= skyColorInit;
      buf_floor     <= floorColorInit;
      buf_leak      <= 6'd0;
      buf_otherx    <= 6'd0;
      buf_othery    <= 6'd0;
      buf_vshift    <= 6'd0;
      buf_vinf      <= 1'b0;
`ifdef USE_LEAK_FIXED
      buf_leakfixed <= 1'b0;
`endif // USE_LEAK_FIXED
      buf_mapdx     <= 6'd0;
      buf_mapdy     <= 6'd0;
      buf_mapdxw    <= 2'd0;
      buf_mapdyw    <= 2'd0;
`ifndef NO_EXTERNAL_TEXTURES
      buf_texadd0   <= 24'd0;
      buf_texadd1   <= 24'd0;
      buf_texadd2   <= 24'd0;
      buf_texadd3   <= 24'd0;
`endif // NO_EXTERNAL_TEXTURES
      buf_playerRX  <= playerInitX;   buf_playerRY  <= playerInitY;
      buf_facingRX  <= facingInitX;   buf_facingRY  <= facingInitY;
      buf_vplaneRX  <= vplaneInitX;   buf_vplaneRY  <= vplaneInitY;

    end else if (spi_done) begin

      if (spi_cmd == CMD_SKY    ) buf_sky       <= spi_buffer`RGB;
      if (spi_cmd == CMD_FLOOR  ) buf_floor     <= spi_buffer`RGB;
      if (spi_cmd == CMD_LEAK   ) buf_leak      <= spi_buffer[5:0];
      if (spi_cmd == CMD_OTHER  ){buf_otherx,
                                  buf_othery}   <= spi_buffer[11:0];
      if (spi_cmd == CMD_VSHIFT ) buf_vshift    <= spi_buffer[5:0];
`ifdef USE_LEAK_FIXED
      if (spi_cmd == CMD_VOPTS  ){buf_vinf,
                                  buf_leakfixed}<= spi_buffer[1:0];
`else // USE_LEAK_FIXED      
      if (spi_cmd == CMD_VINF   ) buf_vinf      <= spi_buffer[0];
`endif // USE_LEAK_FIXED
      if (spi_cmd == CMD_MAPD   ){buf_mapdx,
                                  buf_mapdy,
                                  buf_mapdxw,
                                  buf_mapdyw}   <= spi_buffer[15:0];
`ifndef NO_EXTERNAL_TEXTURES
      if (spi_cmd == CMD_TEXADD0) buf_texadd0   <= spi_buffer[23:0];
      if (spi_cmd == CMD_TEXADD1) buf_texadd1   <= spi_buffer[23:0];
      if (spi_cmd == CMD_TEXADD2) buf_texadd2   <= spi_buffer[23:0];
      if (spi_cmd == CMD_TEXADD3) buf_texadd3   <= spi_buffer[23:0];
`endif // NO_EXTERNAL_TEXTURES

      if (!manual_pov_inc_needed)
        // No override increment, so CMD_POV load is allowed.
        if (spi_cmd == CMD_POV  ){buf_playerRX, buf_playerRY,
                                  buf_facingRX, buf_facingRY,
                                  buf_vplaneRX, buf_vplaneRY}
                                                <= spi_buffer[LEN_POV-1:0];
    end

  end

endmodule
