`default_nettype none
`timescale 1ns / 1ps

`include "fixed_point_params.v"

// wall_tracer with SHARED RECIPROCAL IMPLEMENTATION

//NOTE: I tend to use 'row' and 'line' interchangeably in these comments,
// because 'line' is usually in the context of the screen (i.e. a scanline)
// and 'row' means the same thing but in the context of a traced wall slice.

// How should this FSM work?
// - Sometime during VBLANK, load initial state for being able to trace the
//   first row (top-most) but also for tracing all rows.
// - Stop tracing after the final row (or don't; save on logic?)
// - Advance one row at a time.

`define RESET_TO_KNOWN  // Include explicit reset logic, to avoid unknown states in simulation?
//NOTE: This will generate extra logic, but means greater predictability. If my design is right,
// it's not strictly necessary to do this (if we want to reduce logic/floorplan), because the
// design should settle to a predictable state within 1 full frame, but it's better to do this than
// not. Also, it's probably essential for good, reliable automated tests. On the other hand, we
// could try using Verilator to set random states to try and test possible 'bad startup' conditions.


module wall_tracer #(
  parameter MAP_WIDTH_BITS = 4,
  parameter MAP_HEIGHT_BITS = 4
) (
  input                         clk,
  input                         reset,  //SMELL: Not used. Should we??
  input                         vsync,  // High: hold FSM in reset. Low; let FSM run.
  input                         hmax,   // High: Present last trace result on o_size and start next line.
  input `F playerX, playerY, facingX, facingY, vplaneX, vplaneY,

  // Interface to map ROM:
  output [MAP_WIDTH_BITS-1:0]   o_map_col,
  output [MAP_HEIGHT_BITS-1:0]  o_map_row,
  input                         i_map_val,

`ifdef TRACE_STATE_DEBUG
  output [3:0]                  o_state,
`endif//TRACE_STATE_DEBUG

  // Tracing result, per line:
  output reg                    o_side,
  output reg [10:0]             o_size // Wall half-size.
);

  //SMELL: Still need to define the function of 'tex'

  // States for getting stepDistX = 1.0/rayDirX:
  localparam SDXPrep    = 0;
  localparam SDXWait    = 1;
  localparam SDXLoad    = 2;

  // States for getting stepDistY = 1.0/rayDirY:
  localparam SDYPrep    = 3;
  localparam SDYWait    = 4;
  localparam SDYLoad    = 5;

  // States for main line trace process:
  localparam TracePrep  = 6;
  localparam TraceStep  = 7;
  localparam TraceTest  = 8;
  localparam TraceHit   = 9;

  // States for wall rendered size reciprocal:
  localparam SizePrep   = 10;
  localparam SizeWait   = 11;
  localparam SizeLoad   = 12;

  // Final trace state, where it waits for hmax before presenting the result:
  localparam TraceDone  = 13;

  // Symbols representing different data sources for the reciprocal:
  localparam [1:0] RCP_RDX    = 2'd0; // rayDirX.
  localparam [1:0] RCP_RDY    = 2'd1; // rayDirY.
  localparam [1:0] RCP_VDIST  = 2'd2; // vdist.

`ifdef TRACE_STATE_DEBUG
  assign o_state = state;
`endif//TRACE_STATE_DEBUG

  // Examples of things which could share logic instead of needing simultaneous combo logic:
  // - rayFullHit multiplier -- doesn't even need sharing if using 'side' to mux the multiplicand.
  // - rayDir add/shift? -- an added mux might take away the benefit of sharing, though.
  // - flip reciprocal (and later height_scaler)
  // - partialXY only ever *needs* fractional part, so can save 12 bits?
  //SMELL: Don't optimise until key parts of the design is finished! Otherwise we can't
  // tell whether our optimisations have actually made an improvement or not.
  // ALSO: Try testing each optimisation on its own, and then all together. It's hard to
  // predict synth optimisations that might occur in combos.

  //NOTE: I'm bringing in code from
  // https://github.com/algofoogle/raybox/blob/main/src/rtl/tracer.v
  // and working on modifying it to work with slightly different control inputs
  // and outputs that suit our row-based approach and no trace buffer memory.
  // I will also exclude sprite stuff for now.

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

  // // Get fractional part [0,1) of where the ray hits the wall,
  // // i.e. how far along the individual wall cell the hit occurred,
  // // which will then be used to determine the wall texture stripe.
  // //TODO: Surely there's a way to optimise this. For starters, I think we only
  // // need one multiplier, which uses `side` to determine its multiplicand.
  // //NOTE: visualWallDist is also a function of 'side'... can we do any tricks with that?
  // wire `F2 rayFullHitX = visualWallDist*rayDirX;
  // wire `F2 rayFullHitY = visualWallDist*rayDirY;
  // wire `F wallPartial = side
  //     ? playerX + `FF(rayFullHitX)
  //     : playerY + `FF(rayFullHitY);
  // // Use the wall hit fractional value to determine the wall texture offset
  // // in the range [0,63]:
  // assign tex = wallPartial[-1:-6];
  // wire [5:0] tex; //SMELL: Placeholder for now. Later would form part of the registered traced result outputs.

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
  reg `F stepDistX;  // ...map X direction...
  reg `F stepDistY;  // ...may Y direction...
  // ...which are values generated combinationally by the `reciprocal` instances below.

  // Shared reciprocal input source selection; value we want to find the reciprocal of:
  reg [1:0] rcp_sel; // This muxes between rayDirX, rayDirY, vdist.
  wire `F rcp_in =
    (rcp_sel==RCP_RDX) ?  rayDirX :
    (rcp_sel==RCP_RDY) ?  rayDirY :
                          {5'b0,vdist,3'b0};
  wire `F rcp_out; // Output; reciprocal of rcp_in.
  wire    rcp_sat; // These capture the "saturation" (i.e. overflow) state of our reciprocal calculator.
  //NOTE: rcp_sat is not needed currently, but we might use it as we improve the design,
  // in order to stop tracing on a given axis?
  reciprocal #(.M(`Qm),.N(`Qn)) shared_reciprocal (
    .i_data (rcp_in),
    .i_abs  (1'b1),
    .o_data (rcp_out),
    .o_sat  (rcp_sat)
  );

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
  assign o_map_col = mapX[MAP_WIDTH_BITS-1:0];
  assign o_map_row = mapY[MAP_HEIGHT_BITS-1:0];
  //SMELL: Either mapX/Y or map_col/row seem redundant. However, maybe mapX/Y are defined
  // as full `I range to be compatible with comparisons/assignments? Maybe there's a better
  // way to deal with this using wires.
  //TODO: Optimise.

  //SMELL: Can we optimise the subtractors out of this, e.g. by regs for previous values?
  wire `F visualWallDist = side ? trackDistY-stepDistY : trackDistX-stepDistX;
  assign vdist = visualWallDist[6:-9]; //HACK:
  wire [6:-9] vdist;
  //HACK: Range [6:-9] are enough bits to get the precision and limits we want for distance,
  // i.e. UQ7.9 allows distance to have 1/512 precision and range of [0,127).
  //TODO: Explain this, i.e. it's used by a texture mapper to work out scaling.
  //TODO: Consider replacing with an exponent (floating-point-like) alternative?

  // Used to indicate whether X/Y-stepping is the next target:
  wire needStepX = trackDistX < trackDistY; //NOTE: UNSIGNED comparison per def'n of trackX/Ydist.

  reg side;
  reg [3:0] state; //SMELL: Size this according to actual no. of states.

  `ifdef RESET_TO_KNOWN
    wire do_reset = vsync || reset;
  `else//!RESET_TO_KNOWN
    wire do_reset = vsync;
  `endif//RESET_TO_KNOWN

  always @(posedge clk) begin
    if (do_reset) begin
      // While VSYNC is asserted, reset FSM to start a new frame.
      state <= SDXPrep;

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

      `ifdef RESET_TO_KNOWN
        // Set a known initial state for stuff:
        //SMELL: Don't actually need this, except to make simulation clearer,
        // because all of this stuff will naturally settle after 1 full frame anyway...?
        //SMELL: Do we ACTUALLY want to reset o_size/side on vsync? Wouldn't we want to
        // keep it in case it needs to be reused?
        o_size <= 0;
        o_side <= 0;
        side <= 0;
        rcp_sel <= RCP_RDX; // Reciprocal's data source is initially rayDirX.
        // stepDistX <= 0;
        // stepDistY <= 0;
      `endif//RESET_TO_KNOWN

    end else begin
      case (state)

        // Get stepDistX from rayDirX:
        SDXPrep: begin  state <= SDXWait;   rcp_sel <= RCP_RDX; end
        SDXWait: begin  state <= SDXLoad;   end // Do nothing; just wait for reciprocal to settle.
        SDXLoad: begin  state <= SDYPrep;   stepDistX <= rcp_out; end

        // Get stepDistY from rayDirY:
        SDYPrep: begin  state <= SDYWait;   rcp_sel <= RCP_RDY; end
        SDYWait: begin  state <= SDYLoad;   end // Do nothing; just wait for reciprocal to settle.
        SDYLoad: begin  state <= TracePrep; stepDistY <= rcp_out; end

        TracePrep: begin
          // Get the cell the player's currently in:
          mapX <= playerMapX;
          mapY <= playerMapY;

          //SMELL: Could we get better precision with these trackers, by scaling?
          trackDistX <= `FF(trackInitX);
          trackDistY <= `FF(trackInitY);
          //NOTE: track init comes from stepDist, comes from rayDir, comes from rayAddend.
          state <= TraceStep;
        end
        TraceStep: begin
          if (i_map_val==0) begin
            //SMELL: Can we explicitly set different states to match which trace/step we're doing?
            if (needStepX) begin
              mapX <= rxi ? mapX+1'b1 : mapX-1'b1;
              trackDistX <= trackDistX + stepDistX;
              side <= 0;
            end else begin
              mapY <= ryi ? mapY+1'b1 : mapY-1'b1;
              trackDistY <= trackDistY + stepDistY;
              side <= 1;
            end
          end else begin
            state <= TraceHit;
          end
        end
        // TraceTest: begin
        //   //SMELL: Combine this with TraceStep, above... or does it need to be separate for the map ROM's sake?
        //   // Check if we've hit a wall yet.
        //   if (i_map_val==0) begin
        //     // No hit yet; keep going.
        //     state <= TraceStep;
        //   end else begin
        //     // Hit a wall, so stop tracing this line and wait until the next is ready.
        //     state <= TraceHit;
        //   end
        // end
        TraceHit: begin
          // Tracing stops because we hit something.
          //SMELL: This state is not required.
          state <= SizePrep;
        end
        SizePrep: begin
          rcp_sel <= RCP_VDIST;
          state <= SizeWait;
        end
        SizeWait: begin
          state <= SizeLoad;
        end
        SizeLoad: begin
          //SMELL: This state is not required.
          state <= TraceDone;
        end
        TraceDone: begin
          // No more work to do, so hang around in this state waiting for hmax...
          if (hmax) begin
            // Upon hmax, present our new result and start the next line.
            o_size <= rcp_out[2:-8];
            o_side <= side;
            // Increment rayAddend:
            rayAddendX <= rayAddendX + vplaneX;
            rayAddendY <= rayAddendY + vplaneY;
            state <= SDXPrep;
          end
        end
      endcase
    end

  end

endmodule
