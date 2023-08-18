`default_nettype none
`timescale 1ns / 1ps

//NOTE: The falling edge of 'run' should cause the current traced values to
// present on the 'side' and 'size' outputs.
`include "fixed_point_params.v"

module pov(
  input clk,
  input vsync,
  output `F playerX, playerY, facingX, facingY, vplaneX, vplaneY
);
/* verilator lint_off REALCVT */
  // Some good starting parameters...
  localparam `F playerXstart  = `realF( 1.5); // ...
  localparam `F playerYstart  = `realF( 1.5); // ...Player is starting in a safe bet; middle of map cell (1,1).
  localparam `F facingXstart  = `realF( 0.0); // ...
  localparam `F facingYstart  = `realF( 1.0); // ...Player is facing (0,1); "south" or "downwards" on map, i.e. birds-eye.
  localparam `F vplaneXstart  = `realF(-0.5); // Viewplane dir is (-0.5,0); "west" or "left" on map...
  localparam `F vplaneYstart  = `realF( 0.0); // ...makes FOV ~52deg. Too small, but makes maths easy for now.
/* verilator lint_on REALCVT */

  reg `F px,py;
  initial {px,py} = {playerXstart,playerYstart};

  reg [2:0] vsyncS;
  always @(posedge clk) vsyncS <= {vsyncS[1:0],vsync};
  wire vsync_start_edge = vsyncS[2:1] == 2'b01;

  always @(posedge clk) begin
    if (vsync_start_edge) begin
      px <= px + 15;
      py <= py + 3;
    end
  end

  assign playerX = px;
  assign playerY = py;
  assign facingX = facingXstart;
  assign facingY = facingYstart;
  assign vplaneX = vplaneXstart;
  assign vplaneY = vplaneYstart;

endmodule
