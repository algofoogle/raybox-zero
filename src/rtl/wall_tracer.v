`default_nettype none
`timescale 1ns / 1ps

`include "fixed_point_params.v"

//NOTE: I tend to use 'row' and 'line' interchangeably in these comments,
// because 'line' is usually in the context of the screen (i.e. a scanline)
// and 'row' means the same thing but in the context of a traced wall slice.

// How should this FSM work?
// - Sometime during VBLANK, load initial state for being able to trace the
//   first row (top-most) but also for tracing all rows.
// - Stop tracing after the final row (or don't; save on logic?)
// - Advance one row at a time.



module wall_tracer(
  input               clk,
  input               reset,  //SMELL: Not used. Should we??
  input               vsync,  // High: hold FSM in reset. Low; let FSM run.
  input               hmax,   // High: Present last trace result on o_size and start next line.
  input `F playerX, playerY, facingX, facingY, vplaneX, vplaneY,
  output reg          o_side,
  output reg [10:0]   o_size
);

  // TO BE DEFINED:
  // - map outputs (map_row/map_col) and input (map_val)
  // - tex
  // - vdist??

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
  // Why >>>8? Normally 1x 'vplane' represents the FULL range of one side of the camera,
  // so it would *seem* more normal to actually accumulate a *fraction* of vplane per camera
  // line. However, a fractional addend would lose too much precision so instead rayAddend is
  // actually accumulating a FULL vplane per line.
  // >>>8 scales it back to something more normal, but note that adjusting this
  // (I think) can contribute to changing the FOV.

  // Ray dir increment/decrement flag for each of X and Y:
  wire rxi = rayDirX > 0; // Is ray X direction positive?
  wire ryi = rayDirY > 0; // Is ray Y direction positive?
  // This is used to help work out which map cell directions we walk.

  // trackDistX and trackDistY are not a vector; they're separate trackers
  // for distance travelled along X and Y gridlines:
  //NOTE: These are defined as UNSIGNED because in some cases they may get such a big
  // number added to them that they wrap around and appear negative, and this would
  // otherwise break comparisons. I expect this to be OK because such a huge addend
  // cannot exceed its normal positive range anyway, AND would only get added once
  // to an existing non-negative number, which would cause it to stop accumulating
  // without further wrapping beyond its possible unsigned range.
  reg `UF trackDistX;
  reg `UF trackDistY;

  // Get fractional part [0,1) of where the ray hits the wall,
  // i.e. how far along the individual wall cell the hit occurred,
  // which will then be used to determine the wall texture stripe.
  //TODO: Surely there's a way to optimise this. For starters, I think we only
  // need one multiplier, which uses `side` to determine its multiplicand.
  wire `F2 rayFullHitX = visualWallDist*rayDirX;
  wire `F2 rayFullHitY = visualWallDist*rayDirY;
  wire `F wallPartial = o_side
      ? playerX + `FF(rayFullHitX)
      : playerY + `FF(rayFullHitY);
  // Use the wall hit fractional value to determine the wall texture offset
  // in the range [0,63]:
  assign tex = wallPartial[-1:-6];

  //SMELL: Do these need to be signed? They should only ever be positive, anyway.
  // Get integer player position:
  wire `I playerMapX  = `FI(playerX);
  wire `I playerMapY  = `FI(playerY);
  // Get fractional player position:
  wire `f playerFracX = `Ff(playerX);
  wire `f playerFracY = `Ff(playerY);

  // Work out size of the initial partial ray step, and whether it's towards a lower or higher cell:
  //NOTE: a playerfrac could be 0, in which case the partial must be 1.0 if the rayDir is increasing,
  // or 0 otherwise. playerfrac cannot be 1.0, however, since by definition it is the fractional part
  // of the player position.
  wire `F partialX = rxi ? `intF(1)-`fF(playerFracX) : `fF(playerFracX); //SMELL: Why does Quartus think these are 32 bits being assigned?
  wire `F partialY = ryi ? `intF(1)-`fF(playerFracY) : `fF(playerFracY);
  //SMELL: We're using full `F fixed-point numbers here so we can include the possibility of an integer
  // part because of the 1.0 case, mentioned above. However, we really only need 1 extra bit to support
  // this, if that makes any difference.
  //TODO: Optimise this, if it actually makes a difference during synth anyway.

  // What distance (i.e. what extension of our ray's vector) do we go when travelling by 1 cell in the...
  wire `F stepDistX;  // ...map X direction...
  wire `F stepDistY;  // ...may Y direction...
  // ...which are values generated combinationally by the `reciprocal` instances below.
  //NOTE: If we needed to save space, we could have just one reciprocal, sharing via different states.
  // That would probably work OK since we don't need to CONSTANTLY be getting the reciprocals.
  reciprocal #(.M(`Qm),.N(`Qn)) flipX (.i_data(rayDirX), .i_abs(1), .o_data(stepDistX), .o_sat(satX));
  reciprocal #(.M(`Qm),.N(`Qn)) flipY (.i_data(rayDirY), .i_abs(1), .o_data(stepDistY), .o_sat(satY));
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
  wire `F2 trackInitX = stepDistX * partialX;
  wire `F2 trackInitY = stepDistY * partialY;
  //TODO: This could again share 1 multiplier, given a state ID for each of X and Y.

  // Map cell we're testing:
  reg `I mapX, mapY;
  // Send the current tested map cell to the map ROM:
  assign map_col = mapX[MAP_SIZE_BITS-1:0];
  assign map_row = mapY[MAP_SIZE_BITS-1:0];
  //SMELL: Either mapX/Y or map_col/row seem redundant. However, maybe mapX/Y are defined
  // as full `I range to be compatible with comparisons/assignments? Maybe there's a better
  // way to deal with this using wires.
  //TODO: Optimise.

  //SMELL: Can we optimise the subtractors out of this, e.g. by regs for previous values?
  wire `F visualWallDist = o_side ? trackDistY-stepDistY : trackDistX-stepDistX;
  assign vdist = visualWallDist[6:-9]; //HACK:
  //HACK: Range [6:-9] are enough bits to get the precision and limits we want for distance,
  // i.e. UQ7.9 allows distance to have 1/512 precision and range of [0,127).
  //TODO: Explain this, i.e. it's used by a texture mapper to work out scaling.
  //TODO: Consider replacing with an exponent (floating-point-like) alternative?

  // // Output current line (row) counter value:
  // assign column = line_counter;

  // Used to indicate whether X/Y-stepping is the next target:
  wire needStepX = trackDistX < trackDistY; //NOTE: UNSIGNED comparison per def'n of trackX/Ydist.

  localparam PREP = 0;
  localparam STEP = 1;
  localparam TEST = 2;
  localparam DONE = 3;
  

  reg [1:0] state; //SMELL: Size this according to actual no. of states.

  always @(posedge clk) begin
    if (vsync) begin
      // While VSYNC is asserted, reset FSM to start a new frame.
      state <= PREP;

      // Get the initial ray direction (top row)...
      rayAddendX <= -(vplaneX<<<8)-(vplaneX<<<4);
      rayAddendY <= -(vplaneY<<<8)-(vplaneY<<<4);
      // This is the same as rayAddendX = -vplaneX*272.
      //HACK: Why 272? Well, it's an interesting one...
      // Screen height is 480, so our first visible line is basically at -240
      // (240 lines above middle). Hence that top line is derived from -vplane*240.
      // However, we don't *need* to waste logic on waiting for that first visible line,
      // so it happens that if we start tracing immediately from the start of VB
      // (the Veritcal Back porch) which is 33 lines, this is equivalent to starting
      // at -vplane*273. However, the trace result always displays on the NEXT line, so
      // we want to jump the gun by 1 line, hence -vplane*272. This happens to need
      // the least logic overall (I think) in order to get a perfectly balanced display.

      // Set a known initial state for the side:
      o_side <= 0;
      //SMELL: Don't actually need this, except to make simulation clearer,
      // because side will be determined during tracing, anyway?
    end else begin
      case (state)
        PREP: begin
          // Get the cell the player's currently in:
          mapX <= playerMapX;
          mayY <= playerMapY;

          //SMELL: Could we get better precision with these trackers, by scaling?
          trackDistX <= `FF(trackInitX);
          trackDistY <= `FF(trackInitY);
          //NOTE: track init comes from stepDist, comes from rayDir, comes from rayAddend.
          //SMELL: Could we get rid of 'DONE' (or just merge with 'PREP') and then
          // only do this state change based on hmax?
          state <= STEP;
        end
        STEP: begin
          //SMELL: Can we explicitly set different states to match which trace/step we're doing?
          if (needStepX) begin
            mapX <= rxi ? mapX+1'b1 : mapX-1'b1;
            trackDistX <= trackDistX + stepDistX;
            o_side <= 0;
          end else begin
            mapY <= ryi ? mapY+1'b1 : mapY-1'b1;
            trackDistY <= trackDistY + stepDistY;
            o_side <= 1;
          end
          state <= TEST;
        end
        TEST: begin
          //SMELL: Combine this with STEP, above.
          // Check if we've hit a wall yet.
          if (map_val!=0) begin
            // Hit a wall, so stop tracing this line and wait until the next is ready.
            state <= DONE;
          end else begin
            // No hit yet; keep going.
            state <= STEP;
          end
        end
        DONE: begin
          // Trace of the current line is done.
          // Wait for hmax...
          if (hmax) begin
            // Upon hmax, output our new result and start the next line.
            //SMELL: @@@ NEED TO DECIDE WHAT TYPE OF RESULT WE'LL RETURN HERE...
            // @@@ Will it be the distance in ~Q7.9, or floating-point-style
            // @@@ (LZC & unshifted reciprocal), or height (from reciprocal)?
            o_size <= @@@
            // Increment rayAddend:
            rayAddendX <= rayAddendX + vplaneX;
            rayAddendY <= rayAddendY + vplaneY;
            state <= PREP;
            //SMELL: If (say) reciprocal propagation time, etc, is of concern then
            // we could insert extra states before getting to PREP (which is where
            // the rayAddend change trickle-down will ultimately be used).
          end
        end
      endcase
    end

  end

endmodule
