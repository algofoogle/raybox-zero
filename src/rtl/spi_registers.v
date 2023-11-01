`default_nettype none
`timescale 1ns / 1ps

`include "helpers.v"

// Well this is a funky SPI module! I'm sure there's a better way to do this...
// Should it really be storing registers itself?

module spi_registers(
  input             clk,
  input             reset,
  input             i_sclk, i_ss_n, i_mosi, // SPI input.

  output reg `RGB   sky, floor,     // Sky and floor colours.
  output reg [5:0]  leak,           // Floor 'leak'.
  output reg [5:0]  otherx, othery, // 'Other' map cell position.
  output reg [5:0]  vshift,         // Texture V axis shift (texv addend).
  output reg        vinf,           // Infinite V/height setting.
  output reg [5:0]  mapdx, mapdy,   // Map 'dividing walls' on X and Y. 0=none
  output reg [1:0]  mapdxw, mapdyw, // Map dividing wall, wall IDs (texture) for X and Y respectively
  output reg [23:0] texadd [0:3],   // Texture address addends (array of 4)

  input             load_new // Will go high at the moment that buffered data can go live.
);

  reg spi_done;

  // Value in waiting:          | Is value ready to be presented? //
  reg `RGB    new_sky;          reg got_new_sky;
  reg `RGB    new_floor;        reg got_new_floor;
  reg [5:0]   new_leak;         reg got_new_leak;
  reg [11:0]  new_other;        reg got_new_other;    // otherx and othery combined.
  reg [5:0]   new_vshift;       reg got_new_vshift;
  reg         new_vinf;         reg got_new_vinf;
  reg [15:0]  new_mapd;         reg got_new_mapd;     // mapdx,mapdy, mapdxw,mapdyw combined.
  reg [23:0]  new_texadd [0:3]; reg got_new_texadd [0:3];
  //---------------------|---------------------------------//

  //SMELL: If we don't want to waste space with all these extra registers,
  // could we just transfer one 'waiting' value into a SINGLE selected register?
  // Only problem with doing so is that we can then only update 1 per frame
  // (unless we implement the 'immediate' option and the host waits for VBLANK).

  // assign texadd[0] = 24'hA5A5A5;
  // assign texadd[1] = 24'hAA55AA;
  // assign texadd[2] = 24'h55AA55;
  // assign texadd[3] = 24'h123ABC;

  always @(posedge clk) begin

    if (reset) begin
      
      spi_done <= 0;
      // Load default values, and flag that we have no ready values in waiting.
      sky       <= 6'b01_01_01; got_new_sky     <= 0;
      floor     <= 6'b10_10_10; got_new_floor   <= 0;
      leak      <= 6'd0;        got_new_leak    <= 0;
      vshift    <= 6'd0;        got_new_vshift  <= 0;
      vinf      <= 1'b0;        got_new_vinf    <= 0;
      otherx    <= 6'd0;        got_new_other   <= 0;
      othery    <= 6'd0;
      mapdx     <= 6'd0;        got_new_mapd    <= 0;
      mapdy     <= 6'd0;
      mapdxw    <= 2'd0;
      mapdyw    <= 2'd0;
      texadd[0] <= 24'd0;       got_new_texadd[0] <= 0;
      texadd[1] <= 24'd0;       got_new_texadd[1] <= 0;
      texadd[2] <= 24'd0;       got_new_texadd[2] <= 0;
      texadd[3] <= 24'd0;       got_new_texadd[3] <= 0;

    end else begin

      if (load_new) begin
        if (got_new_sky       ) begin sky             <= new_sky;       got_new_sky       <= 0; end
        if (got_new_floor     ) begin floor           <= new_floor;     got_new_floor     <= 0; end
        if (got_new_leak      ) begin leak            <= new_leak;      got_new_leak      <= 0; end
        if (got_new_other     ) begin {otherx,othery} <= new_other;     got_new_other     <= 0; end
        if (got_new_vshift    ) begin vshift          <= new_vshift;    got_new_vshift    <= 0; end
        if (got_new_vinf      ) begin vinf            <= new_vinf;      got_new_vinf      <= 0; end
        if (got_new_mapd      ) begin {mapdx,mapdy,
                                      mapdxw,mapdyw}  <= new_mapd;      got_new_mapd      <= 0; end
        if (got_new_texadd[0] ) begin texadd[0]       <= new_texadd[0]; got_new_texadd[0] <= 0; end
        if (got_new_texadd[1] ) begin texadd[1]       <= new_texadd[1]; got_new_texadd[1] <= 0; end
        if (got_new_texadd[2] ) begin texadd[2]       <= new_texadd[2]; got_new_texadd[2] <= 0; end
        if (got_new_texadd[3] ) begin texadd[3]       <= new_texadd[3]; got_new_texadd[3] <= 0; end
      end

      if (spi_done) begin
        spi_done <= 0;
        if (spi_cmd == CMD_SKY    ) begin   new_sky       <= spi_buffer`RGB;    got_new_sky       <= 1; end
        if (spi_cmd == CMD_FLOOR  ) begin   new_floor     <= spi_buffer`RGB;    got_new_floor     <= 1; end
        if (spi_cmd == CMD_LEAK   ) begin   new_leak      <= spi_buffer[5:0];   got_new_leak      <= 1; end
        if (spi_cmd == CMD_OTHER  ) begin   new_other     <= spi_buffer[11:0];  got_new_other     <= 1; end
        if (spi_cmd == CMD_VSHIFT ) begin   new_vshift    <= spi_buffer[5:0];   got_new_vshift    <= 1; end
        if (spi_cmd == CMD_VINF   ) begin   new_vinf      <= spi_buffer[0];     got_new_vinf      <= 1; end
        if (spi_cmd == CMD_MAPD   ) begin   new_mapd      <= spi_buffer[15:0];  got_new_mapd      <= 1; end
        if (spi_cmd == CMD_TEXADD0) begin   new_texadd[0] <= spi_buffer[23:0];  got_new_texadd[0] <= 1; end
        if (spi_cmd == CMD_TEXADD1) begin   new_texadd[1] <= spi_buffer[23:0];  got_new_texadd[1] <= 1; end
        if (spi_cmd == CMD_TEXADD2) begin   new_texadd[2] <= spi_buffer[23:0];  got_new_texadd[2] <= 1; end
        if (spi_cmd == CMD_TEXADD3) begin   new_texadd[3] <= spi_buffer[23:0];  got_new_texadd[3] <= 1; end
      end else if (ss_active && sclk_rise && spi_frame_end) begin
        // Last bit is being clocked in...
        spi_done <= 1;
      end

    end

  end // clk.


  //SMELL: ------------------ NEED TO IMPLEMENT/RESPECT RESETS FOR ALL THIS?? --------------------
  // The following synchronises the 3 SPI inputs using the typical DFF pair approach
  // for metastability avoidance at the 2nd stage, but note that for SCLK and /SS this
  // rolls into a 3rd stage so that we can use the state of stages 2 and 3 to detect
  // a rising or falling edge...

  // Sync SCLK using 3-bit shift reg (to catch rising/falling edges):
  reg [2:0] sclk_buffer; always @(posedge clk) if (!reset) sclk_buffer <= {sclk_buffer[1:0], i_sclk};
  wire sclk_rise = (sclk_buffer[2:1]==2'b01);
  // wire sclk_fall = (sclk_buffer[2:1]==2'b10);

  // Sync /SS; only needs 2 bits because we don't care about edges:
  reg [1:0] ss_buffer; always @(posedge clk) if (!reset) ss_buffer <= {ss_buffer[0], i_ss_n};
  wire ss_active = ~ss_buffer[1];

  // Sync MOSI:
  reg [1:0] mosi_buffer; always @(posedge clk) if (!reset) mosi_buffer <= {mosi_buffer[0], i_mosi};
  wire mosi = mosi_buffer[1];
  //SMELL: Do we actually need to sync MOSI? It should be stable when we check it at the SCLK rising edge.

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
  wire spi_command_end = (spi_counter == SPI_CMD_BITS-1);
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
  reg [SPI_CMD_BITS-1:0] spi_cmd;
  reg [6:0] spi_counter; // Enough to count the largest frame we support (74 counts, 0..73, for vectors).
  reg [SPI_BUFFER_LIMIT:0] spi_buffer; // Receives the SPI data (after the command).

  always @(posedge clk) begin
    if (reset || !ss_active) begin
      // Deactivated; reset SPI:
      spi_counter <= 0;
    end else if (sclk_rise) begin
      // SPI is active, and we've got a rising SCLK edge, so this is a bit being clocked in:
      if (spi_counter < SPI_CMD_BITS) begin
        // Receiving a command.
        spi_counter <= spi_counter + 1'd1;
        spi_cmd <= {spi_cmd[SPI_CMD_BITS-2:0], mosi};
      end else begin
        // Receiving the data that goes along with the command.
        spi_counter <= spi_frame_end ? 7'd0 : (spi_counter + 1'd1);
        spi_buffer <= {spi_buffer[SPI_BUFFER_LIMIT-1:0], mosi};
      end
    end
  end

endmodule
