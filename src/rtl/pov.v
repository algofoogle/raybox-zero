`default_nettype none
`timescale 1ns / 1ps

//NOTE: The falling edge of 'run' should cause the current traced values to
// present on the 'side' and 'size' outputs.
`include "fixed_point_params.v"

module pov(
  input clk,
  input reset,
  input i_sclk, i_ss_n, i_mosi, // SPI input.
  input load_if_ready, // Will go high at the moment that buffered data can go live.
  output reg `F playerX, playerY, facingX, facingY, vplaneX, vplaneY
);
/* verilator lint_off REALCVT */
  // Some good starting parameters...
  localparam `F playerXstart  = `Qmn'($rtoi(`realF( 1.5))); // ...
  localparam `F playerYstart  = `Qmn'($rtoi(`realF( 1.5))); // ...Player is starting in a safe bet; middle of map cell (1,1).
  localparam `F facingXstart  = `Qmn'($rtoi(`realF( 0.0))); // ...
  localparam `F facingYstart  = `Qmn'($rtoi(`realF( 1.0))); // ...Player is facing (0,1); "south" or "downwards" on map, i.e. birds-eye.
  localparam `F vplaneXstart  = `Qmn'($rtoi(`realF(-0.5))); // Viewplane dir is (-0.5,0); "west" or "left" on map...
  localparam `F vplaneYstart  = `Qmn'($rtoi(`realF( 0.0))); // ...makes FOV ~52deg. Too small, but makes maths easy for now.
/* verilator lint_on REALCVT */

  reg ready; // Is ready_buffer valid?

  always @(posedge clk) begin
    if (reset) begin
      ready <= 0;
      //SMELL: Could do this via ready_buffer instead?
      {playerX,playerY} <= {playerXstart,playerYstart};
      {facingX,facingY} <= {facingXstart,facingYstart};
      {vplaneX,vplaneY} <= {vplaneXstart,vplaneYstart};
    end else if (load_if_ready && ready) begin
      // Load buffered vectors into live vector registers:
      {playerX,playerY,facingX,facingY,vplaneX,vplaneY} <= ready_buffer;
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
  wire sclk_fall = (sclk_buffer[2:1]==2'b10);

  // Sync /SS; only needs 2 bits because we don't care about edges:
  reg [1:0] ss_buffer; always @(posedge clk) ss_buffer <= {ss_buffer[0], i_ss_n};
  wire ss_active = ~ss_buffer[1];

  // Sync MOSI:
  reg [1:0] mosi_buffer; always @(posedge clk) mosi_buffer <= {mosi_buffer[0], i_mosi};
  wire mosi = mosi_buffer[1];
  //SMELL: Do we actually need to sync MOSI? It should be stable when we check it at the SCLK rising edge.

  // Expect each complete SPI frame to be 144 bits, made up of (in order, 24 bits each, MSB first):
  // playerX, playerY,
  // facingX, facingY,
  // vplaneX, vplaneY.
  reg [7:0] spi_counter; // Enough to do 144 counts.
  reg [143:0] spi_buffer; // Receives the SPI bit stream.
  reg spi_done;
  wire spi_frame_end = (spi_counter == 143); // Indicates whether we've reached the SPI frame end or not.
  always @(posedge clk) begin
    if (!ss_active) begin
      // When /SS is not asserted, reset the SPI bit stream counter:
      spi_counter <= 0;
    end else if (sclk_rise) begin
      // We detected a SCLK rising edge, while /SS is asserted, so this means we're clocking in a bit...
      // SPI bit stream counter wraps around after the expected number of bits, so that the master can
      // theoretically keep sending frames while /SS is asserted.
      spi_counter <= spi_frame_end ? 0 : (spi_counter + 1);
      spi_buffer <= {spi_buffer[142:0], mosi};
    end
  end

  reg [143:0] ready_buffer; // Last buffered (complete) SPI bit stream that is ready for next loading as vector data.
  always @(posedge clk) begin
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

endmodule
