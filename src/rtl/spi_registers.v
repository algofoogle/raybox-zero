`default_nettype none
// `timescale 1ns / 1ps

`ifndef RBZ_OPTIONS
  // These are Verilator/VSCode hints, only. RBZ_OPTIONS should otherwise always be defined for deploying raybox-zero.
  `include "helpers.v"
  `include "fixed_point_params.v"
`endif

// Well this is a funky SPI module! I'm sure there's a better way to do this...
// Should it really be storing registers itself?

module spi_registers #(
  parameter MAP_WALLBITS = 3,
  // Door register initials:         X     Y  Wall  Frame Pos
  parameter [23:0] DOOR0_INIT = {6'd13, 6'd6, 3'd1, 1'b1, 8'd0},
  parameter [23:0] DOOR1_INIT = {6'd15, 6'd7, 3'd1, 1'b1, 8'd0},
  parameter [23:0] DOOR2_INIT = {6'd17, 6'd0, 3'd1, 1'b1, 8'd0},
  parameter [23:0] DOOR3_INIT = {6'd22, 6'd16, 3'd1, 1'b1, 8'd0}
) (
  input               clk,
  input               reset,
  input               i_sclk, i_ss_n, i_mosi, // SPI input.

  output reg  `RGB    sky, floor,     // Sky and floor colours.
  output reg  [5:0]   leak,           // Floor 'leak'.
  output reg  [5:0]   otherx, othery, // 'Other' map cell position.
  output reg  [5:0]   vshift,         // Texture V axis shift (texv addend).
  output reg          vinf,           // Infinite V/height setting.
  output              o_leakfixed,    // Is LEAK fixed to the ground (1), or floating (0)?
  output reg  [2:0]   map_mode,       // 0=Classic map; 1=Tweaked map; 2=Funky map; 3=Interesting map

`ifndef NO_DIV_WALLS
  output reg [5:0]              mapdx, mapdy,   // Map 'dividing walls' on X and Y. 0=none
  output reg [MAP_WALLBITS-1:0] mapdxw, mapdyw, // Map dividing wall, wall IDs (texture) for X and Y respectively
`endif // NO_DIV_WALLS

`ifndef NO_EXTERNAL_TEXTURES
  output reg  [23:0]  texadd0,        // Texture address addend 0
  output reg  [23:0]  texadd1,        // Texture address addend 1
  output reg  [23:0]  texadd2,        // Texture address addend 2
  output reg  [23:0]  texadd3,        // Texture address addend 3
  output reg  [23:0]  texadd4,        // Texture address addend 4
  output reg  [23:0]  texadd5,        // Texture address addend 5
  output reg  [23:0]  texadd6,        // Texture address addend 6
  output reg  [23:0]  texadd7,        // Texture address addend 7
  output reg  [7:0]   texadd_ena_walls, // Each bit enables applying the respective TEXADD for walls.
  `ifdef USE_DOORS
  output reg  [7:0]   texadd_ena_doors, // Each bit enables applying the respective TEXADD for doors.
  `endif // USE_DOORS
`endif // NO_EXTERNAL_TEXTURES

`ifdef USE_MAP_RECT
  output reg  [5:0]   mapr_ax,
  output reg  [5:0]   mapr_ay,
  output reg  [5:0]   mapr_bx,
  output reg  [5:0]   mapr_by,
  output reg          mapr_erase,
  output reg  [2:0]   mapr_wall,
`endif // USE_MAP_RECT

`ifdef USE_DOORS
  // Each door port is: {doorx[5:0], doory[5:0], wallid[2:0], reserved[0], pos[7:0]}
  //NOTE: If wallid==0, then derive from the underlying map cell's wall ID (which can also be 0).
  // Yosys doesn't support arrayed ports?
  // output      [23:0]  o_doors [0:3],
  output      [23:0]  o_doors0,
  output      [23:0]  o_doors1,
  output      [23:0]  o_doors2,
  output      [23:0]  o_doors3,
`endif

`ifdef USE_POV_VIA_SPI_REGS
  input               i_inc_px, i_inc_py, // Demo overrides for playerX/Y inc. If either is asserted, SPI POV loads are masked out and 'ready' is cleared.
  output `F           playerX, playerY,
  output `F           facingX, facingY,
  output `F           vplaneX, vplaneY,
`endif // USE_POV_VIA_SPI_REGS

  input               load_new        // Will go high at the moment that buffered data can go live.
);

  reg [23:0] doors [0:3];

  assign o_doors0 = doors[0];
  assign o_doors1 = doors[1];
  assign o_doors2 = doors[2];
  assign o_doors3 = doors[3];

  localparam SPI_CMD_BITS = 8; // SPI command is 1 byte wide.
  localparam DEFAULT_MAP_MODE = 3'd1; // Start off with 'Tweaked' map.

`ifdef USE_POV_VIA_SPI_REGS
  wire manual_pov_inc_needed  = i_inc_px | i_inc_py;        // Manual playerX/Y increment in effect (i.e. demo mode)?
`endif // USE_POV_VIA_SPI_REGS

// ===== COMMAND/REGISTER PARAMETERS AND SIZING =====

  localparam CMD_SKY    = 8'b00000000;  localparam LEN_SKY    =  6; // 0: Set sky colour (6b data)
  localparam CMD_FLOOR  = 8'b00000001;  localparam LEN_FLOOR  =  6; // 1: Set floor colour (6b data)
  localparam CMD_LEAK   = 8'b00000010;  localparam LEN_LEAK   =  6; // 2: Set floor 'leak' (in texels; 6b data)
  localparam CMD_OTHER  = 8'b00000011;  localparam LEN_OTHER  = 12; // 3: Set 'other wall cell' position: X and Y, both 6b each, for a total of 12b.
  localparam CMD_VSHIFT = 8'b00000100;  localparam LEN_VSHIFT =  6; // 4: Set texture V axis shift (texv addend). //SMELL: Make this more bits for finer grain.

`ifdef USE_LEAK_FIXED
  localparam CMD_VOPTS  = 8'b00000101;  localparam LEN_VOPTS  =  5; // 5: Bits [4:0] = {VINF,LEAK_FIXED,MAPMODE[2:0]}
`else // USE_LEAK_FIXED
  localparam CMD_VINF   = 8'b00000101;  localparam LEN_VINF   =  1; // 5: Set infinite V mode (infinite height/size).
`endif // USE_LEAK_FIXED

`ifndef NO_DIV_WALLS
  localparam CMD_MAPD   = 8'b00000110;  localparam LEN_MAPD   = 18; // 6: Set mapdx,mapdy (6b/ea), mapdxw,mapdyw (3b/ea)
`endif // NO_DIV_WALLS

`ifdef USE_MAP_RECT
  localparam CMD_MAPR   = 8'b00000111;  localparam LEN_MAPR   = 28; // 7: {ax[5:0],ay[5:0], bx[5:0],by[5:0], erase[0], wallID[2:0]}
`endif // USE_MAP_RECT

`ifdef USE_DOORS
  localparam CMD_DOOR0  = 8'b00001000;  localparam LEN_DOOR   = 24; // 8..11: {doorx[5:0], doory[5:0], wallid[2:0], frame[0], pos[7:0]}
  localparam CMD_DOOR1  = 8'b00001001;
  localparam CMD_DOOR2  = 8'b00001010;
  localparam CMD_DOOR3  = 8'b00001011;
`endif // USE_DOORS
  //NOTE: CMD 12..15 reserved for 4 more doors.

`ifndef NO_EXTERNAL_TEXTURES
  localparam CMD_TEXADD0= 8'b00100000;  localparam LEN_TEXADD0= 24; // 32
  localparam CMD_TEXADD1= 8'b00100001;  localparam LEN_TEXADD1= 24; // 33
  localparam CMD_TEXADD2= 8'b00100010;  localparam LEN_TEXADD2= 24; // 34
  localparam CMD_TEXADD3= 8'b00100011;  localparam LEN_TEXADD3= 24; // 35
  localparam CMD_TEXADD4= 8'b00100100;  localparam LEN_TEXADD4= 24; // 36
  localparam CMD_TEXADD5= 8'b00100101;  localparam LEN_TEXADD5= 24; // 37
  localparam CMD_TEXADD6= 8'b00100110;  localparam LEN_TEXADD6= 24; // 38
  localparam CMD_TEXADD7= 8'b00100111;  localparam LEN_TEXADD7= 24; // 39
`endif
  /////////////////////// 8'b001xxxxx (32..63) -- reserved for TEXADD and related registers.

`ifndef NO_EXTERNAL_TEXTURES
  localparam CMD_TEXADDENA = 8'b01000000; localparam LEN_TEXADDENA= 16; // 8 MSB for doors, 8 LSB for walls.
  //NOTE: For consistency, 8 bits are reserved for doors, even if USE_DOORS is not defined.
`endif // NO_EXTERNAL_TEXTURES

`ifdef USE_POV_VIA_SPI_REGS
  // player(X,Y), facing(X,Y), vplane(X,Y): 74 bits
  localparam CMD_POV    = 8'b01111111;  localparam LEN_POV = (15*2)+(11*2)+(11*2); // 127
`endif // USE_POV_VIA_SPI_REGS

  // Extra registers we want:
  // -  CMD_VOPTS can have 2 more control bits in it, if we want: [2]: TEXADDs are absolute, not added. [3]: ?
  // -  Double TEXADD regs if we want to set each side independently
  //    (though this might be avoidable if we rearrange memory so the 'side' bit controls a whole bank rather than just a texture).
  // -  MapRect: 24 bits for coords, 1 for erase-or-not, 1 for outline-or-not, 3 for wall ID.

`ifdef USE_POV_VIA_SPI_REGS
  localparam SPI_BUFFER_SIZE = LEN_POV; //NOTE: Should be set to whatever the largest LEN_* value is above.
`elsif USE_MAP_RECT
  localparam SPI_BUFFER_SIZE = 28; // (LEN_MAPR)
`else // USE_POV_VIA_SPI_REGS
  `ifdef NO_EXTERNAL_TEXTURES
    `ifdef USE_DOORS
      localparam SPI_BUFFER_SIZE = 24;
    `else
      localparam SPI_BUFFER_SIZE = 18; //NOTE: Should be set to whatever the largest LEN_* value is above.
    `endif
  `else // NO_EXTERNAL_TEXTURES
    localparam SPI_BUFFER_SIZE = 24; //NOTE: Should be set to whatever the largest LEN_* value is above.
  `endif
`endif // USE_POV_VIA_SPI_REGS
  localparam SPI_BUFFER_LIMIT = SPI_BUFFER_SIZE-1;

// ===== GOOD STARTING PARAMETERS FOR RESET =====

`ifdef USE_POV_VIA_SPI_REGS
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
`endif // USE_POV_VIA_SPI_REGS
  localparam skyColorInit       = 6'b01_01_01;
  localparam floorColorInit     = 6'b10_10_10;

`ifdef USE_POV_VIA_SPI_REGS
// ===== TRUNCATED-TO-FULL-RANGE VECTOR EXTENSION =====

  // Registered versions of the truncated vectors, before they get padded up to `F (e.g. SQ10.10) format on output ports.
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
`endif // USE_POV_VIA_SPI_REGS

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
  reg [2:0]   buf_mapmode;

`ifdef USE_LEAK_FIXED
  reg         buf_leakfixed;
`endif // USE_LEAK_FIXED

`ifndef NO_DIV_WALLS
  reg [5:0]   buf_mapdx;
  reg [5:0]   buf_mapdy;
  reg [MAP_WALLBITS-1:0]   buf_mapdxw;
  reg [MAP_WALLBITS-1:0]   buf_mapdyw;
`endif // NO_DIV_WALLS

`ifndef NO_EXTERNAL_TEXTURES
  reg [23:0]  buf_texadd0;
  reg [23:0]  buf_texadd1;
  reg [23:0]  buf_texadd2;
  reg [23:0]  buf_texadd3;
  reg [23:0]  buf_texadd4;
  reg [23:0]  buf_texadd5;
  reg [23:0]  buf_texadd6;
  reg [23:0]  buf_texadd7;
  reg [7:0]   buf_texadd_ena_walls;
  `ifdef USE_DOORS
  reg [7:0]   buf_texadd_ena_doors;
  `endif // USE_DOORS
`endif // NO_EXTERNAL_TEXTURES
`ifdef USE_POV_VIA_SPI_REGS
  // POV registers:
  // SMELL: Make bit ranges parametric here, and for other POV data above!
  reg [14:0]  buf_playerRX, buf_playerRY;
  reg [10:0]  buf_facingRX, buf_facingRY;
  reg [10:0]  buf_vplaneRX, buf_vplaneRY;
`endif // USE_POV_VIA_SPI_REGS

`ifdef USE_MAP_RECT
  reg [5:0]   buf_mapr_ax;
  reg [5:0]   buf_mapr_ay;
  reg [5:0]   buf_mapr_bx;
  reg [5:0]   buf_mapr_by;
  reg         buf_mapr_erase;
  reg [2:0]   buf_mapr_wall;
`endif // USE_MAP_RECT

`ifdef USE_DOORS
  reg [23:0]  buf_doors [0:3];
`endif // USE_DOORS

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

// ===== MAIN SPI CONTROL/PAYLOAD REGISTERS =====

  reg [6:0]                 spi_counter; // To count largest supported frame (74 for vectors, 0..73).
  reg [SPI_CMD_BITS-1:0]    spi_cmd;
  reg [SPI_BUFFER_LIMIT:0]  spi_buffer; // Receives the SPI data (after the command).
  reg                       spi_done;

  wire spi_frame_end =
    spi_counter == (
      SPI_CMD_BITS + (
        (spi_cmd == CMD_SKY     ) ?   LEN_SKY:
        (spi_cmd == CMD_FLOOR   ) ?   LEN_FLOOR:
        (spi_cmd == CMD_LEAK    ) ?   LEN_LEAK:
        (spi_cmd == CMD_OTHER   ) ?   LEN_OTHER:
        (spi_cmd == CMD_VSHIFT  ) ?   LEN_VSHIFT:

`ifndef NO_DIV_WALLS
        (spi_cmd == CMD_MAPD    ) ?   LEN_MAPD:
`endif // NO_DIV_WALLS

`ifndef NO_EXTERNAL_TEXTURES
        (spi_cmd == CMD_TEXADD0 ) ?   LEN_TEXADD0:
        (spi_cmd == CMD_TEXADD1 ) ?   LEN_TEXADD1:
        (spi_cmd == CMD_TEXADD2 ) ?   LEN_TEXADD2:
        (spi_cmd == CMD_TEXADD3 ) ?   LEN_TEXADD3:
        (spi_cmd == CMD_TEXADD4 ) ?   LEN_TEXADD4:
        (spi_cmd == CMD_TEXADD5 ) ?   LEN_TEXADD5:
        (spi_cmd == CMD_TEXADD6 ) ?   LEN_TEXADD6:
        (spi_cmd == CMD_TEXADD7 ) ?   LEN_TEXADD7:
        (spi_cmd == CMD_TEXADDENA)?   LEN_TEXADDENA:
`endif // NO_EXTERNAL_TEXTURES

`ifdef USE_POV_VIA_SPI_REGS
        (spi_cmd == CMD_POV     ) ?   LEN_POV:
`endif // USE_POV_VIA_SPI_REGS

`ifdef USE_MAP_RECT
        (spi_cmd == CMD_MAPR    ) ?   LEN_MAPR:
`endif // USE_MAP_RECT

`ifdef USE_DOORS
        (spi_cmd == CMD_DOOR0   ) ?   LEN_DOOR:
        (spi_cmd == CMD_DOOR1   ) ?   LEN_DOOR:
        (spi_cmd == CMD_DOOR2   ) ?   LEN_DOOR:
        (spi_cmd == CMD_DOOR3   ) ?   LEN_DOOR:
`endif // USE_DOORS


`ifdef USE_LEAK_FIXED
      /*(spi_cmd == CMD_VOPTS   ) ?*/ LEN_VOPTS
`else // USE_LEAK_FIXED
      /*(spi_cmd == CMD_VINF    ) ?*/ LEN_VINF
`endif // USE_LEAK_FIXED

      ) - 1
    );


// ===== MAIN SPI CLOCKED LOGIC =====

  always @(posedge clk) begin

    // spi_counter:
    if (reset)
      spi_counter <= 0;
    else if (!ss_active)
      spi_counter <= 0;
    else if (sclk_rise && spi_counter < SPI_CMD_BITS) // Protects against overflows??
      spi_counter <= spi_counter + 1'd1;
    else if (sclk_rise && !spi_frame_end)
      spi_counter <= spi_counter + 1'd1;
    // Stall SPI counter at expected end of frame.
    //NOTE: Whether intentional or not, though spi_counter stalls,
    // data continues to shift in during "Load spi_buffer data".

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
      map_mode  <= DEFAULT_MAP_MODE;
`ifdef USE_LEAK_FIXED
      leakfixed <= 1'b0;
`endif // USE_LEAK_FIXED
`ifndef NO_DIV_WALLS
      mapdx     <= 6'd0;
      mapdy     <= 6'd0;
      mapdxw    <= 3'd0;
      mapdyw    <= 3'd0;
`endif // NO_DIV_WALLS
`ifndef NO_EXTERNAL_TEXTURES
      texadd0   <= 24'd0;
      texadd1   <= 24'd0;
      texadd2   <= 24'd0;
      texadd3   <= 24'd0;
      texadd4   <= 24'd0;
      texadd5   <= 24'd0;
      texadd6   <= 24'd0;
      texadd7   <= 24'd0;
      texadd_ena_walls <= 8'b1111_1111; // By default, TEXADDs are enabled for all walls.
  `ifdef USE_DOORS
      texadd_ena_doors <= 8'b0;
  `endif // USE_DOORS
`endif // NO_EXTERNAL_TEXTURES
`ifdef USE_POV_VIA_SPI_REGS
      playerRX  <= playerInitX;      playerRY  <= playerInitY;
      facingRX  <= facingInitX;      facingRY  <= facingInitY;
      vplaneRX  <= vplaneInitX;      vplaneRY  <= vplaneInitY;
`endif
`ifdef USE_MAP_RECT
      mapr_ax   <= 6'd0;
      mapr_ay   <= 6'd0;
      mapr_bx   <= 6'd0;
      mapr_by   <= 6'd0;
      mapr_erase<= 1'b0;
      mapr_wall <= 3'd0;
`endif // USE_MAP_RECT
`ifdef USE_DOORS
      doors[0] <= DOOR0_INIT;
      doors[1] <= DOOR1_INIT;
      doors[2] <= DOOR2_INIT;
      doors[3] <= DOOR3_INIT;
`endif // USE_DOORS

    end else if (load_new) begin

      // Load from in-waiting buffers:
      sky       <= buf_sky;
      floor     <= buf_floor;
      leak      <= buf_leak;
      otherx    <= buf_otherx;
      othery    <= buf_othery;
      vshift    <= buf_vshift;
      vinf      <= buf_vinf;
      map_mode  <= buf_mapmode;
`ifdef USE_LEAK_FIXED
      leakfixed <= buf_leakfixed;
`endif // USE_LEAK_FIXED
`ifndef NO_DIV_WALLS
      mapdx     <= buf_mapdx;
      mapdy     <= buf_mapdy;
      mapdxw    <= buf_mapdxw;
      mapdyw    <= buf_mapdyw;
`endif // NO_DIV_WALLS
`ifndef NO_EXTERNAL_TEXTURES
      texadd0   <= buf_texadd0;
      texadd1   <= buf_texadd1;
      texadd2   <= buf_texadd2;
      texadd3   <= buf_texadd3;
      texadd4   <= buf_texadd4;
      texadd5   <= buf_texadd5;
      texadd6   <= buf_texadd6;
      texadd7   <= buf_texadd7;
      texadd_ena_walls <= buf_texadd_ena_walls;
  `ifdef USE_DOORS
      texadd_ena_doors <= buf_texadd_ena_doors;
  `endif // USE_DOORS
`endif // NO_EXTERNAL_TEXTURES
`ifdef USE_POV_VIA_SPI_REGS
      // POV registers:
      playerRX  <= buf_playerRX;  playerRY  <= buf_playerRY;
      facingRX  <= buf_facingRX;  facingRY  <= buf_facingRY;
      vplaneRX  <= buf_vplaneRX;  vplaneRY  <= buf_vplaneRY;
      if (manual_pov_inc_needed) begin
        // Override increment is in effect:
        if (i_inc_px) buf_playerRX <= buf_playerRX - 15'b1;
        if (i_inc_py) buf_playerRY <= buf_playerRY - 15'b1;
      end
`endif // USE_POV_VIA_SPI_REGS
`ifdef USE_MAP_RECT
      mapr_ax   <= buf_mapr_ax;
      mapr_ay   <= buf_mapr_ay;
      mapr_bx   <= buf_mapr_bx;
      mapr_by   <= buf_mapr_by;
      mapr_erase<= buf_mapr_erase;
      mapr_wall <= buf_mapr_wall;
`endif // USE_MAP_RECT
`ifdef USE_DOORS
      doors[0]  <= buf_doors[0];
      doors[1]  <= buf_doors[1];
      doors[2]  <= buf_doors[2];
      doors[3]  <= buf_doors[3];
`endif // USE_DOORS

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
      buf_mapmode   <= DEFAULT_MAP_MODE;
`ifdef USE_LEAK_FIXED
      buf_leakfixed <= 1'b0;
`endif // USE_LEAK_FIXED
`ifndef NO_DIV_WALLS
      buf_mapdx     <= 6'd0;
      buf_mapdy     <= 6'd0;
      buf_mapdxw    <= 3'd0;
      buf_mapdyw    <= 3'd0;
`endif // NO_DIV_WALLS
`ifndef NO_EXTERNAL_TEXTURES
      buf_texadd0   <= 24'd0;
      buf_texadd1   <= 24'd0;
      buf_texadd2   <= 24'd0;
      buf_texadd3   <= 24'd0;
      buf_texadd4   <= 24'd0;
      buf_texadd5   <= 24'd0;
      buf_texadd6   <= 24'd0;
      buf_texadd7   <= 24'd0;
      buf_texadd_ena_walls <= 8'b1111_1111;
  `ifdef USE_DOORS
      buf_texadd_ena_doors <= 8'b0;
  `endif // USE_DOORs
`endif // NO_EXTERNAL_TEXTURES
`ifdef USE_POV_VIA_SPI_REGS
      buf_playerRX  <= playerInitX;   buf_playerRY  <= playerInitY;
      buf_facingRX  <= facingInitX;   buf_facingRY  <= facingInitY;
      buf_vplaneRX  <= vplaneInitX;   buf_vplaneRY  <= vplaneInitY;
`endif // USE_POV_VIA_SPI_REGS
`ifdef USE_MAP_RECT
      buf_mapr_ax   <= 6'd0;
      buf_mapr_ay   <= 6'd0;
      buf_mapr_bx   <= 6'd0;
      buf_mapr_by   <= 6'd0;
      buf_mapr_erase<= 1'b0;
      buf_mapr_wall <= 3'd0;
`endif // USE_MAP_RECT
`ifdef USE_DOORS
      buf_doors[0]  <= DOOR0_INIT;
      buf_doors[1]  <= DOOR1_INIT;
      buf_doors[2]  <= DOOR2_INIT;
      buf_doors[3]  <= DOOR3_INIT;
`endif // USE_DOORS

    end else if (spi_done) begin

      if (spi_cmd == CMD_SKY    ) buf_sky       <= spi_buffer`RGB;
      if (spi_cmd == CMD_FLOOR  ) buf_floor     <= spi_buffer`RGB;
      if (spi_cmd == CMD_LEAK   ) buf_leak      <= spi_buffer[5:0];
      if (spi_cmd == CMD_OTHER  ){buf_otherx,
                                  buf_othery}   <= spi_buffer[11:0];
      if (spi_cmd == CMD_VSHIFT ) buf_vshift    <= spi_buffer[5:0];
`ifdef USE_LEAK_FIXED
      if (spi_cmd == CMD_VOPTS  ){buf_vinf,
                                  buf_leakfixed,
                                  buf_mapmode}  <= spi_buffer[4:0];
`else // USE_LEAK_FIXED      
      if (spi_cmd == CMD_VINF   ) buf_vinf      <= spi_buffer[0];
`endif // USE_LEAK_FIXED
`ifndef NO_DIV_WALLS
      if (spi_cmd == CMD_MAPD   ){buf_mapdx,
                                  buf_mapdy,
                                  buf_mapdxw,
                                  buf_mapdyw}   <= spi_buffer[17:0];
`endif // NO_DIV_WALLS
`ifndef NO_EXTERNAL_TEXTURES
      if (spi_cmd == CMD_TEXADD0) buf_texadd0   <= spi_buffer[23:0];
      if (spi_cmd == CMD_TEXADD1) buf_texadd1   <= spi_buffer[23:0];
      if (spi_cmd == CMD_TEXADD2) buf_texadd2   <= spi_buffer[23:0];
      if (spi_cmd == CMD_TEXADD3) buf_texadd3   <= spi_buffer[23:0];
      if (spi_cmd == CMD_TEXADD4) buf_texadd4   <= spi_buffer[23:0];
      if (spi_cmd == CMD_TEXADD5) buf_texadd5   <= spi_buffer[23:0];
      if (spi_cmd == CMD_TEXADD6) buf_texadd6   <= spi_buffer[23:0];
      if (spi_cmd == CMD_TEXADD7) buf_texadd7   <= spi_buffer[23:0];
      if (spi_cmd == CMD_TEXADDENA) begin
                                  buf_texadd_ena_walls <= spi_buffer[7:0];
  `ifdef USE_DOORS
                                  buf_texadd_ena_doors <= spi_buffer[15:8];
  `endif // USE_DOORS
      end
`endif // NO_EXTERNAL_TEXTURES

`ifdef USE_POV_VIA_SPI_REGS
      if (!manual_pov_inc_needed)
        // No override increment, so CMD_POV load is allowed.
        if (spi_cmd == CMD_POV  ){buf_playerRX, buf_playerRY,
                                  buf_facingRX, buf_facingRY,
                                  buf_vplaneRX, buf_vplaneRY}
                                                <= spi_buffer[LEN_POV-1:0];
`endif // USE_POV_VIA_SPI_REGS

`ifdef USE_MAP_RECT
      if (spi_cmd == CMD_MAPR   ){buf_mapr_ax,  buf_mapr_ay,
                                  buf_mapr_bx,  buf_mapr_by,
                                  buf_mapr_erase, buf_mapr_wall}
                                                <= spi_buffer[LEN_MAPR-1:0];
`endif // USE_MAP_RECT

`ifdef USE_DOORS
      if (spi_cmd == CMD_DOOR0  ) buf_doors[0]  <= spi_buffer[23:0];
      if (spi_cmd == CMD_DOOR1  ) buf_doors[1]  <= spi_buffer[23:0];
      if (spi_cmd == CMD_DOOR2  ) buf_doors[2]  <= spi_buffer[23:0];
      if (spi_cmd == CMD_DOOR3  ) buf_doors[3]  <= spi_buffer[23:0];
`endif // USE_DOORS

    end

  end

endmodule
