`default_nettype none
`timescale 1ns / 1ps

//NOTE: The falling edge of 'run' should cause the current traced values to
// present on the 'side' and 'size' outputs.
`include "fixed_point_params.v"


module wall_tracer(
  input               clk,
  input               reset,
  input [9:0]         i_row,
  input               i_run,    // While low, hold FSM in reset. While high, let FSM run the trace.
  input `F playerX, playerY, facingX, facingY, vplaneX, vplaneY,
  output reg          o_side,
  output reg [10:0]   o_size
);
  reg [9:0] dividend;
  reg [9:0] divisor;
  reg [10:0] quotient;

  always @(posedge clk) begin
    if (!i_run) begin
      // Reset FSM to start a new line,
      // while also presenting our traced value at our outputs.
      dividend <= 1000;
      divisor <= i_row;
      quotient <= 0;
      o_side <= dividend==0; // Remainder is 0?
      o_size <= quotient;
    end else begin
      if (dividend >= divisor) begin
        dividend <= dividend - divisor;
        quotient <= quotient + 1;
      end
    end
  end

endmodule
