`default_nettype none
// `timescale 1ns / 1ps

// `include "helpers.v"

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
  output reg  [5:0]   mapdx, mapdy,   // Map 'dividing walls' on X and Y. 0=none
  output reg  [1:0]   mapdxw, mapdyw, // Map dividing wall, wall IDs (texture) for X and Y respectively
  output reg  [23:0]  texadd0,        // Texture address addend 0
  output reg  [23:0]  texadd1,        // Texture address addend 1
  output reg  [23:0]  texadd2,        // Texture address addend 2
  output reg  [23:0]  texadd3,        // Texture address addend 3

  input               load_new        // Will go high at the moment that buffered data can go live.
);

  // Values in waiting:
  reg `RGB    buf_sky;
  reg `RGB    buf_floor;
  reg [5:0]   buf_leak;
  reg [5:0]   buf_otherx;
  reg [5:0]   buf_othery;
  reg [5:0]   buf_vshift;
  reg         buf_vinf;
  reg [5:0]   buf_mapdx;
  reg [5:0]   buf_mapdy;
  reg [1:0]   buf_mapdxw;
  reg [1:0]   buf_mapdyw;
  reg [23:0]  buf_texadd0;
  reg [23:0]  buf_texadd1;
  reg [23:0]  buf_texadd2;
  reg [23:0]  buf_texadd3;
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


// ===== COMMAND/REGISTER PARAMETERS AND SIZING =====

  localparam CMD_SKY    = 0;  localparam LEN_SKY    =  6; // Set sky colour (6b data)
  localparam CMD_FLOOR  = 1;  localparam LEN_FLOOR  =  6; // Set floor colour (6b data)
  localparam CMD_LEAK   = 2;  localparam LEN_LEAK   =  6; // Set floor 'leak' (in texels; 6b data)
  localparam CMD_OTHER  = 3;  localparam LEN_OTHER  = 12; // Set 'other wall cell' position: X and Y, both 6b each, for a total of 12b.
  localparam CMD_VSHIFT = 4;  localparam LEN_VSHIFT =  6; // Set texture V axis shift (texv addend). //SMELL: Make this more bits for finer grain.
  localparam CMD_VINF   = 5;  localparam LEN_VINF   =  1; // Set infinite V mode (infinite height/size).
  localparam CMD_MAPD   = 6;  localparam LEN_MAPD   = 16; // Set mapdx,mapdy, mapdxw,mapdyw.
  localparam CMD_TEXADD0= 7;  localparam LEN_TEXADD0= 24;
  localparam CMD_TEXADD1= 8;  localparam LEN_TEXADD1= 24;
  localparam CMD_TEXADD2= 9;  localparam LEN_TEXADD2= 24;
  localparam CMD_TEXADD3=10;  localparam LEN_TEXADD3= 24;

  localparam SPI_BUFFER_SIZE = 24; //NOTE: Should be set to whatever the largest LEN_* value is above.
  localparam SPI_BUFFER_LIMIT = SPI_BUFFER_SIZE-1;

  localparam SPI_CMD_BITS = 4;

  wire spi_frame_end =
    spi_counter == (
      SPI_CMD_BITS + (
        (spi_cmd == CMD_SKY     ) ?   LEN_SKY:
        (spi_cmd == CMD_FLOOR   ) ?   LEN_FLOOR:
        (spi_cmd == CMD_LEAK    ) ?   LEN_LEAK:
        (spi_cmd == CMD_OTHER   ) ?   LEN_OTHER:
        (spi_cmd == CMD_VSHIFT  ) ?   LEN_VSHIFT:
        (spi_cmd == CMD_MAPD    ) ?   LEN_MAPD:
        (spi_cmd == CMD_TEXADD0 ) ?   LEN_TEXADD0:
        (spi_cmd == CMD_TEXADD1 ) ?   LEN_TEXADD1:
        (spi_cmd == CMD_TEXADD2 ) ?   LEN_TEXADD2:
        (spi_cmd == CMD_TEXADD3 ) ?   LEN_TEXADD3:
      /*(spi_cmd == CMD_VINF    ) ?*/ LEN_VINF
      ) - 1
    );


// ===== MAIN SPI CONTROL/PAYLOAD REGISTERS =====

  reg [6:0]                 spi_counter; // Enough to count the largest frame we support (74 counts, 0..73, for vectors).
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
      sky       <= 6'b01_01_01;
      floor     <= 6'b10_10_10;
      leak      <= 6'd0;
      otherx    <= 6'd0;
      othery    <= 6'd0;
      vshift    <= 6'd0;
      vinf      <= 1'b0;
      mapdx     <= 6'd0;
      mapdy     <= 6'd0;
      mapdxw    <= 2'd0;
      mapdyw    <= 2'd0;
      texadd0   <= 24'd0;
      texadd1   <= 24'd0;
      texadd2   <= 24'd0;
      texadd3   <= 24'd0;
    end else if (load_new) begin
      // Load from in-waiting buffers:
      sky       <= buf_sky;
      floor     <= buf_floor;
      leak      <= buf_leak;
      otherx    <= buf_otherx;
      othery    <= buf_othery;
      vshift    <= buf_vshift;
      vinf      <= buf_vinf;
      mapdx     <= buf_mapdx;
      mapdy     <= buf_mapdy;
      mapdxw    <= buf_mapdxw;
      mapdyw    <= buf_mapdyw;
      texadd0   <= buf_texadd0;
      texadd1   <= buf_texadd1;
      texadd2   <= buf_texadd2;
      texadd3   <= buf_texadd3;
    end

    // Handle loading in-waiting buffer regs from spi_buffer:
    if (reset) begin
      buf_sky       <= 6'b01_01_01;
      buf_floor     <= 6'b10_10_10;
      buf_leak      <= 6'd0;
      buf_otherx    <= 6'd0;
      buf_othery    <= 6'd0;
      buf_vshift    <= 6'd0;
      buf_vinf      <= 1'b0;
      buf_mapdx     <= 6'd0;
      buf_mapdy     <= 6'd0;
      buf_mapdxw    <= 2'd0;
      buf_mapdyw    <= 2'd0;
      buf_texadd0   <= 24'd0;
      buf_texadd1   <= 24'd0;
      buf_texadd2   <= 24'd0;
      buf_texadd3   <= 24'd0;
    end else if (spi_done) begin
      if (spi_cmd == CMD_SKY    ) buf_sky       <= spi_buffer`RGB;
      if (spi_cmd == CMD_FLOOR  ) buf_floor     <= spi_buffer`RGB;
      if (spi_cmd == CMD_LEAK   ) buf_leak      <= spi_buffer[5:0];
      if (spi_cmd == CMD_OTHER  ){buf_otherx,
                                  buf_othery}   <= spi_buffer[11:0];
      if (spi_cmd == CMD_VSHIFT ) buf_vshift    <= spi_buffer[5:0];
      if (spi_cmd == CMD_VINF   ) buf_vinf      <= spi_buffer[0];
      if (spi_cmd == CMD_MAPD   ){buf_mapdx,
                                  buf_mapdy,
                                  buf_mapdxw,
                                  buf_mapdyw}   <= spi_buffer[15:0];
      if (spi_cmd == CMD_TEXADD0) buf_texadd0   <= spi_buffer[23:0];
      if (spi_cmd == CMD_TEXADD1) buf_texadd1   <= spi_buffer[23:0];
      if (spi_cmd == CMD_TEXADD2) buf_texadd2   <= spi_buffer[23:0];
      if (spi_cmd == CMD_TEXADD3) buf_texadd3   <= spi_buffer[23:0];
    end

  end

endmodule
