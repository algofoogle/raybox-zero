`default_nettype none
`timescale 1ns / 1ps

//NOTE: The falling edge of 'run' should cause the current traced values to
// present on the 'side' and 'size' outputs.
`include "fixed_point_params.v"


module wall_tracer(
  input               clk,
  input               reset,
  input               vsync,
  input [9:0]         i_row,
  input               i_run,    // While low, hold FSM in reset. While high, let FSM run the trace.
  input `F playerX, playerY, facingX, facingY, vplaneX, vplaneY,
  output reg          o_side,
  output reg [10:0]   o_size
);

  reg `I mapX, mapY;
  reg `F rayAddendX, rayAddendY; // Ray direction offset (full precision; before scaling).
  // `rayAddend` is a deflection from the central `facing` vector which is used to form
  // the `rayDir`. It starts off being -vplane*(rows/2) and accumulates +vplane per row until
  // reaching +vplane*(rows/2). It's scaled back to a normal fractional value with >>>8 when
  // it gets added to `facing`.

  // Ray direction vector, for the ray we're tracing on any given row:
  wire `F rayDirX = facingX + (rayAddendX>>>8);
  wire `F rayDirY = facingY + (rayAddendY>>>8);
  // Why >>>8? Normally vplane represents the FULL range of one side of the camera.
  // We're actually adding it IN FULL to rayAddend (instead of adding a line-by-line
  // fraction of it), in order to maintain full precision. >>>8 scales it back to
  // something more normal, but note that adjusting this (I think) can contribute to
  // changing the FOV.

  always @(posedge clk) begin
    if (vsync) begin
      // Reset FSM to start a new frame.
//@@@
    end
  end

//@@@ not finished

  // reg [9:0] dividend;
  // reg [9:0] divisor;
  // reg [10:0] quotient;

  // always @(posedge clk) begin
  //   if (!i_run) begin
  //     // Reset FSM to start a new line,
  //     // while also presenting our traced value at our outputs.
  //     dividend <= 1000;
  //     divisor <= i_row;
  //     quotient <= 0;
  //     o_side <= dividend==0; // Remainder is 0?
  //     o_size <= quotient;
  //   end else begin
  //     if (dividend >= divisor) begin
  //       dividend <= dividend - divisor;
  //       quotient <= quotient + 1;
  //     end
  //   end
  // end

endmodule
