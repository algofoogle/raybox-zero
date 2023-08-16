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

  //NOTE: I'm bringing in code from
  // https://github.com/algofoogle/raybox/blob/main/src/rtl/tracer.v
  // and working on modifying it to work with slightly different control inputs
  // and outputs that suit our row-based approach and no trace buffer memory.
  // I will also exclude sprite stuff for now.

  // Map cell we're testing:
  reg `I mapX, mapY;

  // Ray DEFLECTION vector, i.e. ray direction OFFSET (full precision; before scaling):
  reg `F rayAddendX, rayAddendY;
  // `rayAddend` is a deflection from the central `facing` vector which is used to form
  // the `rayDir`. It starts off being -vplane*(rows/2) and accumulates +vplane per row until
  // reaching +vplane*(rows/2). It's scaled back to a normal fractional value with >>>8 when
  // it gets added to `facing`.
  //NOTE: For now it's called the "addend" because it gets added to the base ray ('facing').

  // Ray direction vector, for the ray we're tracing on any given row:
  wire `F rayDirX = facingX + (rayAddendX>>>8);
  wire `F rayDirY = facingY + (rayAddendY>>>8);
  // Why >>>8? Normally 1x 'vplane' represents the FULL range of one side of the camera.
  // We're actually adding it IN FULL to rayAddend (instead of adding a line-by-line
  // fraction of it), in order to maintain full precision. >>>8 scales it back to
  // something more normal, but note that adjusting this (I think) can contribute to
  // changing the FOV.

  // Ray dir increment/decrement flag for each of X and Y:
  wire rxi = rayDirX > 0; // Is ray X direction positive?
  wire ryi = rayDirY > 0; // Is ray Y direction positive?
  // This is used to help work out which map cell directions we walk.

  // trackXdist and trackYdist are not a vector; they're separate trackers
  // for distance travelled along X and Y gridlines:
  //NOTE: These are defined as UNSIGNED because in some cases they may get such a big
  // number added to them that they wrap around and appear negative, and this would
  // otherwise break comparisons. I expect this to be OK because such a huge addend
  // cannot exceed its normal positive range anyway, AND would only get added once
  // to an existing non-negative number, which would cause it to stop accumulating
  // without further wrapping beyond its possible unsigned range.
  reg `UF trackXdist;
  reg `UF trackYdist;

  // Get fractional part [0,1) of where the ray hits the wall,
  // i.e. how far along the individual wall cell the hit occurred,
  // which will then be used to determine the wall texture stripe.
  //TODO: Surely there's a way to optimise this. For starters, I think we only
  // need one multiplier, which uses `side` to determine its multiplicand.
  wire `F2 rayFullHitX = visualWallDist*rayDirX;
  wire `F2 rayFullHitY = visualWallDist*rayDirY;
  wire `F wallPartial = side
      ? playerX + `FF(rayFullHitX)
      : playerY + `FF(rayFullHitY);
  // Use the wall hit fractional value to determine the wall texture offset
  // in the range [0,63]:
  assign tex = wallPartial[-1:-6];

  //SMELL: Do these need to be signed? They should only ever be positive, anyway.
  // Get integer player position:
  wire `I playerXint  = `FI(playerX);
  wire `I playerYint  = `FI(playerY);
  // Get fractional player position:
  wire `f playerXfrac = `Ff(playerX);
  wire `f playerYfrac = `Ff(playerY);

  // Work out size of the initial partial ray step, and whether it's towards a lower or higher cell:
  //NOTE: a playerfrac could be 0, in which case the partial must be 1.0 if the rayDir is increasing,
  // or 0 otherwise. playerfrac cannot be 1.0, however, since by definition it is the fractional part
  // of the player position.
  wire `F partialX = rxi ? `intF(1)-`fF(playerXfrac) : `fF(playerXfrac); //SMELL: Why does Quartus think these are 32 bits being assigned?
  wire `F partialY = ryi ? `intF(1)-`fF(playerYfrac) : `fF(playerYfrac);
  //SMELL: We're using full `F fixed-point numbers here so we can include the possibility of an integer
  // part because of the 1.0 case, mentioned above. However, we really only need 1 extra bit to support
  // this, if that makes any difference.
  //TODO: Optimise this, if it actually makes a difference during synth anyway.

  // What distance (i.e. what extension of our ray's vector) do we go when travelling by 1 cell in the...
  wire `F stepXdist;  // ...map X direction...
  wire `F stepYdist;  // ...may Y direction...
  // ...which are values generated combinationally by the `reciprocal` instances below.
  //NOTE: If we needed to save space, we could have just one reciprocal, sharing via different states.
  // That would probably work OK since we don't need to CONSTANTLY be getting the reciprocals.
  reciprocal #(.M(`Qm),.N(`Qn)) flipX (.i_data(rayDirX), .i_abs(1), .o_data(stepXdist), .o_sat(satX));
  reciprocal #(.M(`Qm),.N(`Qn)) flipY (.i_data(rayDirY), .i_abs(1), .o_data(stepYdist), .o_sat(satY));
  //TODO: Try making these into a single shared reciprocal instance.
  // These capture the "saturation" (i.e. overflow) state of our reciprocal calculators:
  wire satX;
  wire satY;
  // These are not needed currently, but we might use them as we improve the design,
  // in order to stop tracing on a given axis?

  // This is the reciprocal that the early version of Raybox used to calculate absolute wall height,
  // but it was commented out when texture mapping was implemented (because it was done a little
  // differently outside of the tracer):
  // wire satHeight;
  // reciprocal #(.M(`Qm),.N(`Qn)) height_scaler (.i_data(visualWallDist),   .i_abs(1), .o_data(heightScale),.o_sat(satHeight));

  // Generate the initial tracking distances, as a portion of the full
  // step distances, relative to where our player is (fractionally) in the map cell:
  //SMELL: These only need to capture the middle half of the result,
  // i.e. if we're using Q12.12, our result should still be the [11:-12] bits
  // extracted from the product:
  wire `F2 trackXinit = stepXdist * partialX;
  wire `F2 trackYinit = stepYdist * partialY;
  //TODO: This could again share 1 multiplier, given a state ID for each of X and Y.

  // Send the current tested map cell to the map ROM:
  assign map_col = mapX[MAP_SIZE_BITS-1:0];
  assign map_row = mapY[MAP_SIZE_BITS-1:0];

  //SMELL: Can we optimise the subtractors out of this, e.g. by regs for previous values?
  wire `F visualWallDist = side ? trackYdist-stepYdist : trackXdist-stepXdist;
  assign vdist = visualWallDist[6:-9]; //HACK:
  //HACK: Range [6:-9] are enough bits to get the precision and limits we want for distance,
  // i.e. UQ7.9 allows distance to have 1/512 precision and range of [0,127).
  //TODO: Explain this, i.e. it's used by a texture mapper to work out scaling.
  //TODO: Consider replacing with an exponent (floating-point-like) alternative?

  // // Output current line (row) counter value:
  // assign column = line_counter;

  // Used to indicate whether X/Y-stepping is the next target:
  wire needStepX = trackXdist < trackYdist; //NOTE: UNSIGNED comparison per def'n of trackX/Ydist.

  //DEBUG: Used to count actual clock cycles it takes to trace a frame:
  integer trace_cycle_count;


  always @(posedge clk) begin
    if (vsync) begin
      // Reset FSM to start a new frame.
//@@@
    end
  end

//@@@ not finished


endmodule
