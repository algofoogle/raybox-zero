`default_nettype none
`timescale 1ns / 1ps

//NOTE: The falling edge of 'run' should cause the current traced values to
// present on the 'side' and 'size' outputs.
`include "fixed_point_params.v"

`define UQ6_9    [5:-9] // UQ6.9, able to represent player position in range [0,64) with 1/512 resolution.
`define SQ2_9    [1:-9] // SQ2.9, able to represent facing/vplane in range [-2.0,2.0) with 1/512 resolution.

module pov(
  input clk,
  input reset,
  input i_sclk, i_ss_n, i_mosi, // SPI input.
  input load_if_ready, // Will go high at the moment that buffered data can go live.
  output `F playerX, playerY, facingX, facingY, vplaneX, vplaneY
);

  // Some good starting parameters...
`ifdef QUARTUS
  localparam SCALER = 1<<9; // The vectors below use 9 fractional bits.
  localparam real FSCALER = SCALER;
  localparam `UQ6_9 playerInitX  =  1.5 * FSCALER;  // 15'b000001_100000000;
  localparam `UQ6_9 playerInitY  =  1.5 * FSCALER;  // 15'b000001_100000000;
  localparam `SQ2_9 facingInitX  =  0.0 * FSCALER;  // 11'b____00_000000000;
  localparam `SQ2_9 facingInitY  =  1.0 * FSCALER;  // 11'b_____1_000000000;
  localparam `SQ2_9 vplaneInitX  = -0.5 * FSCALER;  // 11'b____11_100000000;
  localparam `SQ2_9 vplaneInitY  =  0.0 * FSCALER;  // 11'b____00_000000000;
`else
  localparam `UQ6_9 playerInitX  = 15'($rtoi(`realF( 1.5))); // ...
  localparam `UQ6_9 playerInitY  = 15'($rtoi(`realF( 1.5))); // ...Player is starting in a safe bet; middle of map cell (1,1).
  localparam `SQ2_9 facingInitX  = 11'($rtoi(`realF( 0.0))); // ...
  localparam `SQ2_9 facingInitY  = 11'($rtoi(`realF( 1.0))); // ...Player is facing (0,1); "south" or "downwards" on map, i.e. birds-eye.
  localparam `SQ2_9 vplaneInitX  = 11'($rtoi(`realF(-0.5))); // Viewplane dir is (-0.5,0); "west" or "left" on map...
  localparam `SQ2_9 vplaneInitY  = 11'($rtoi(`realF( 0.0))); // ...makes FOV ~52deg. Too small, but makes maths easy for now.
`endif

  reg ready; // Is ready_buffer valid?

  //SMELL: Should we put ALL the clocked stuff together in here, or instead
  // create a separate clocked section for each register target (as we do with SPI)?
  // e.g. ready <= reset ? 0 : spi_done;

  // Registered versions of the vectors, before they get padded up to `F (SQ10.10) format on output ports.
  reg `UQ6_9 playerRX, playerRY;
  reg `SQ2_9 facingRX, facingRY, vplaneRX, vplaneRY;

  //NOTE: If we have the following:
  // - playerX/Y: UQ6.9 - 30 bits
  // - facingX/Y: Q2.9 - 22 bits
  // - vplaneX/Y: Q2.9 - 22 bits
  // ...then SPI needs to receive/buffer 74 bits.
  localparam totalBits = (15*2)+(11*2)+(11*2); // 74.
  localparam finalBit = totalBits-1;

  // The below outputs our more-truncated vectors (at various Qm.n precisions) as conventional `F (SQ10.10) ports...

  // playerX/Y are UQ6.9 made up of 6x zero MSBs, then Q6.9, then 3x zero LSBs.
  // This is enough for the player moving within a 64x64 map to a granularity of 1/512 units.
  // This granularity is ~0.002 of a block. Given a block 'feels' like about 1.8m wide this granularity is about ~3.5mm.
  //NOTE: Sign bit not needed (hence 0) because player position should never be negative anyway? i.e. it's in the range [0,64)
  localparam PadUQ6_9Hi = `Qm-6;
  localparam PadUQ6_9Lo = `Qn-9;
  assign playerX = { {PadUQ6_9Hi{1'b0}}, playerRX, {PadUQ6_9Lo{1'b0}} };
  assign playerY = { {PadUQ6_9Hi{1'b0}}, playerRY, {PadUQ6_9Lo{1'b0}} };

  // facing/vplaneX/Y are SQ2.9 made up of 11x sign extension MSBs (collectively the Q2nd), then Q1.9, then 3x zero LSBs.
  // These have much smaller magnitude because normally each vector won't exceed 1.0...
  // we allow a range of [-2.0,+2.0) because that's more than enough for some effects, FOV control (?) etc.
  localparam PadSQ2_9Hi = `Qm-1; // Not 2, because of sign bit repetition.
  localparam PadSQ2_9Lo = `Qn-9;
  assign facingX = { {PadSQ2_9Hi{facingRX[1]}}, facingRX[0:-9], {PadSQ2_9Lo{1'b0}} };
  assign facingY = { {PadSQ2_9Hi{facingRY[1]}}, facingRY[0:-9], {PadSQ2_9Lo{1'b0}} };
  assign vplaneX = { {PadSQ2_9Hi{vplaneRX[1]}}, vplaneRX[0:-9], {PadSQ2_9Lo{1'b0}} };
  assign vplaneY = { {PadSQ2_9Hi{vplaneRY[1]}}, vplaneRY[0:-9], {PadSQ2_9Lo{1'b0}} };

  always @(posedge clk) begin
    if (reset) begin

      ready <= 0;
      //SMELL: Could do this via ready_buffer instead?
      {playerRX, playerRY} <= {playerInitX, playerInitY}; // 15b x 2 = 30b
      {facingRX, facingRY} <= {facingInitX, facingInitY}; // 11b x 2 = 22b
      {vplaneRX, vplaneRY} <= {vplaneInitX, vplaneInitY}; // 11b x 2 = 22b

    end else begin

      if (load_if_ready && ready) begin
        // Load buffered vectors into live vector registers:
        {
          playerRX, playerRY,
          facingRX, facingRY,
          vplaneRX, vplaneRY
        } <= ready_buffer;
      end

      if (spi_done) begin
        // Last bit was clocked in, so copy the whole spi_buffer into our ready_buffer:
        ready_buffer <= spi_buffer;
        ready <= 1;
        spi_done <= 0;
      end else if (ss_active && sclk_rise && spi_frame_end) begin
        // Last bit is being clocked in...
        spi_done <= 1;
      end

    end

  end

  //SMELL: ------------------ NEED TO IMPLEMENT/RESPECT RESETS FOR ALL THIS?? --------------------
  // The following synchronises the 3 SPI inputs using the typical DFF pair approach
  // for metastability avoidance at the 2nd stage, but note that for SCLK and /SS this
  // rolls into a 3rd stage so that we can use the state of stages 2 and 3 to detect
  // a rising or falling edge...

  // Sync SCLK using 3-bit shift reg (to catch rising/falling edges):
  reg [2:0] sclk_buffer; always @(posedge clk) sclk_buffer <= {sclk_buffer[1:0], i_sclk};
  wire sclk_rise = (sclk_buffer[2:1]==2'b01);
  // wire sclk_fall = (sclk_buffer[2:1]==2'b10);

  // Sync /SS; only needs 2 bits because we don't care about edges:
  reg [1:0] ss_buffer; always @(posedge clk) ss_buffer <= {ss_buffer[0], i_ss_n};
  wire ss_active = ~ss_buffer[1];

  // Sync MOSI:
  reg [1:0] mosi_buffer; always @(posedge clk) mosi_buffer <= {mosi_buffer[0], i_mosi};
  wire mosi = mosi_buffer[1];
  //SMELL: Do we actually need to sync MOSI? It should be stable when we check it at the SCLK rising edge.

  // Expect each complete SPI frame to be 74 bits, made up of (in order, MSB first):
  // playerX, playerY, // 15b x 2 = 30b
  // facingX, facingY, // 11b x 2 = 22b
  // vplaneX, vplaneY. // 11b x 2 = 22b
  reg [6:0] spi_counter; // Should be sized to totalBits. Here, it's enough to do 74 counts (0..73)
  reg [finalBit:0] spi_buffer; // Receives the SPI bit stream.
  reg spi_done;
  wire spi_frame_end = (spi_counter == finalBit); // Indicates whether we've reached the SPI frame end or not.
  always @(posedge clk) begin
    if (!ss_active) begin
      // When /SS is not asserted, reset the SPI bit stream counter:
      spi_counter <= 0;
    end else if (sclk_rise) begin
      // We detected a SCLK rising edge, while /SS is asserted, so this means we're clocking in a bit...
      // SPI bit stream counter wraps around after the expected number of bits, so that the master can
      // theoretically keep sending frames while /SS is asserted.
      spi_counter <= spi_frame_end ? 0 : (spi_counter + 1);
      spi_buffer <= {spi_buffer[finalBit-1:0], mosi};
    end
  end

  reg [finalBit:0] ready_buffer; // Last buffered (complete) SPI bit stream that is ready for next loading as vector data.

endmodule
