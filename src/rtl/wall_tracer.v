`default_nettype none
// `timescale 1ns / 1ps

`ifndef RBZ_OPTIONS
  // These are Verilator/VSCode hints, only. RBZ_OPTIONS should otherwise always be defined for deploying raybox-zero.
  `include "helpers.v"
  `include "fixed_point_params.v"
`endif


//NOTE: I tend to use 'row' and 'line' interchangeably in these comments,
// because 'line' is usually in the context of the screen (i.e. a scanline)
// and 'row' means the same thing but in the context of a traced wall slice.

// How does this FSM work?
// - Sometime during VBLANK, load initial state for being able to trace the
//   first row (top-most) but also for tracing all rows.
// - Stop tracing after the final row (or don't; save on logic?)
// - Advance one row at a time.
// - When needed, control inputs to the shared reciprocal and shared multiplier.

`define RESET_TO_KNOWN  // Include explicit reset logic, to avoid unknown states in simulation?
//NOTE: This will generate extra logic, but means greater predictability. If my design is right,
// it's not strictly necessary to do this (if we want to reduce logic/floorplan), because the
// design should settle to a predictable state within 1 full frame, but it's better to do this than
// not. Also, it's probably essential for good, reliable automated tests. On the other hand, we
// could try using Verilator to set random states to try and test possible 'bad startup' conditions.


module wall_tracer #(
  parameter MAP_WALLBITS  = 3, // No. of bits per map cell wall ID.
  parameter MAP_WBITS     = 4,
  parameter MAP_HBITS     = 4,
  parameter HALF_SIZE     = 320   // Half the visible screen width.
) (
  input                   clk,
  input                   reset,  //SMELL: Not used. Should we??
  input                   vsync,  // High: hold FSM in reset. Low; let FSM run.
  input                   hmax,   // High: Present last trace result on o_size and start next line.
  input `F playerX, playerY, facingX, facingY, vplaneX, vplaneY,
  input [5:0]             otherx, othery,

`ifndef NO_DIV_WALLS
  input [5:0]             mapdx, mapdy, // Map dividers X and Y: 0 means 'none'
  input [MAP_WALLBITS-1:0] mapdxw, mapdyw, // Wall ID for map dividers
`endif // NO_DIV_WALLS

`ifdef USE_DOORS
  // Yosys doesn't support arrayed ports?
  // input [23:0]            i_doors [0:3],
  input wire [23:0]       i_doors0,
  input wire [23:0]       i_doors1,
  input wire [23:0]       i_doors2,
  input wire [23:0]       i_doors3,
`endif // USE_DOORS

`ifdef USE_WAITS_CONFIG
  input wire [2:0]        i_waits,
`endif // USE_WAITS_CONFIG

  // Interface to map ROM:
  output [MAP_WBITS-1:0]  o_map_col,
  output [MAP_HBITS-1:0]  o_map_row,
  input [MAP_WALLBITS-1:0] i_map_val,

`ifdef TRACE_STATE_DEBUG
  output [3:0]            o_state,
`endif//TRACE_STATE_DEBUG

  // Tracing result, per line:
`ifndef NO_EXTERNAL_TEXTURES
  // HOT (LIVE) values as they are being calculated. This allows the texture memory to generate its address early
  // (assuming the trace has actually finished before we get to about hpos==600).
  // We separate these from the outputs below, because the 'hot' outputs can change early,
  // but the non-hot outputs must not (as they are actively in use for rendering the
  // line for all 640 pixels).
  output reg `WALL        o_wall_hot,
  output reg              o_side_hot,
  output reg [5:0]        o_texu_hot,
`endif // NO_EXTERNAL_TEXTURES
  output reg `WALL        o_wall,     // Wall ID that we hit (per map).
  output reg              o_side,     // Light or dark side?
  output reg [10:0]       o_size,     // Wall half-size.
  output reg [5:0]        o_texu,     // Texture 'u' coordinate (i.e. how far along the wall the hit was).
  output reg `F           o_texa,     // Addend for texv coord; actually visualWallDist: equiv to o_size rcp, used for texture scaling.
  output reg `F           o_texVinit  // Initial texV (if o_size exceeds screen HALF_SIZE).
);


  reg [2:0] w; // Wait states for heavy combo maths.
  wire [2:0] waits;
`ifdef USE_WAITS_CONFIG
  assign waits = i_waits;
`else
  // Use a static default for number of wait states:
  localparam [2:0] WAITS = 7;
  assign waits = WAITS;
`endif // !USE_WAITS_CONFIG

  localparam `F HALF_SIZE_CLIP = HALF_SIZE[`QMNI:0]<<(`Qn-8); //SMELL: I can't remember what this shift is for.

/* verilator lint_off REALCVT */
  // Minimum trace distance. Lower than this will lead to texture scaler overflow,
  // so we might as well keep tracing if we haven't exceeded this value.
  localparam MIN_DIST = 0.125; // i.e. 1/8
`ifdef QUARTUS
  localparam SCALER = 1<<9; // The vectors below use 9 fractional bits.
  localparam real FSCALER = SCALER;
  localparam `F MIN_DIST_F = MIN_DIST * FSCALER;
`else
  localparam `F MIN_DIST_F = `Qmnc'($rtoi(`realF(MIN_DIST)));
`endif
/* verilator lint_on REALCVT */

  // States for getting stepDistX = 1.0/rayDirX:
  localparam SDXPrep      = 0;

  // States for getting stepDistY = 1.0/rayDirY:
  localparam SDYPrep      = 1;

  // States for main line trace process:
  localparam TracePrepX   = 2;
  localparam TracePrepY   = 3;
  localparam TraceStep    = 4;

  // States for wall rendered size reciprocal:
  localparam SizePrep     = 5;

  // States that share the multiplier, for working out texture coordinates stuff:
  localparam CalcTexU     = 6;
  localparam CalcTexVInit = 7;

  // Final trace state, where it waits for hmax before presenting the result:
  localparam TraceDone    = 8;
  //NOTE: If changing the highest state number, also update vga_mux.v re trace_state_debug.

  reg [3:0] state; //SMELL: Size this according to actual no. of states.

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

  // Holds texture 'u' coordinate value until it needs to be presented at output:
  reg [5:0] texu;

  wire `F mul_in_a, mul_in_b;
  wire `F2 mul_out;

  reg `WALL wall;
  reg side;

  // Get fractional part [0,1) of where the ray hits the wall,
  // i.e. how far along the individual wall cell the hit occurred,
  // which will then be used to determine the wall texture stripe.
  //TODO: visualWallDist is also a function of 'side'... can we do any tricks with that?
  //NOTE: When wallPartial actually gets used, the inputs to the multiplier (hence driving mul_out)
  // are visualWallDist as the multiplier, with multiplicand being either rayDirX or Y depending on side.
  wire `F wallPartial = `FF(mul_out) + (side ? playerX : playerY);
  wire [7:0] wallPartialTexU8b = wallPartial[-1:-8]; //NOTE: We get 8 bits of resolution, but *mostly* only use the upper 6.
  wire texu_mirror = side ? ryi : ~rxi;
  //NOTE: The FSM CalcTexU step will use a fractional part of
  // wallPartial to determine the wall texture offset.
  wire [7:0] wall_partial_with_flip = wallPartialTexU8b ^ {8{texu_mirror}};
  //NOTE: wallPartialTexU8b is also used with hit_door_pos to determine door position offset.

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
  wire `F partialX = rxi ? `intF(`Qmnc'd1)-`fF(playerFracX) : `fF(playerFracX); //SMELL: Why does Quartus think these are 32 bits being assigned?
  wire `F partialY = ryi ? `intF(`Qmnc'd1)-`fF(playerFracY) : `fF(playerFracY);
  //SMELL: We're using full `F fixed-point numbers here so we can include the possibility of an integer
  // part because of the 1.0 case, mentioned above. However, we really only need 1 extra bit to support
  // this, if that makes any difference.
  //TODO: Optimise this, if it actually makes a difference during synth anyway.

  // What distance (i.e. what extension of our ray's vector) do we go when travelling by 1 cell in the...
  reg `F stepDistX;  // ...map X direction...
  reg `F stepDistY;  // ...may Y direction...
  // ...which are values generated combinationally by the `reciprocal` instances below.

  reg `F visualWallDist;
  // wire [6:-9] vdist = visualWallDist[6:-9]; // Do we actually need this anymore?
  // //HACK: Range [6:-9] are enough bits to get the precision and limits we want for distance,
  // // i.e. UQ7.9 allows distance to have 1/512 precision and range of [0,127).

  reg rcp_start;
  reg `F rcp_in;

  wire `F rcp_out; // Output; reciprocal of rcp_in.
  wire    rcp_sat; // These capture the "saturation" (i.e. overflow) state of our reciprocal calculator.
  wire    rcp_done;
  //NOTE: rcp_sat is not needed currently, but we might use it as we improve the design,
  // in order to stop tracing on a given axis?
  reg `F size_full;
  wire [10:0] size = size_full[2:-8];

  `ifdef RESET_TO_KNOWN
    wire do_reset = vsync || reset;
  `else//!RESET_TO_KNOWN
    wire do_reset = vsync;
  `endif//RESET_TO_KNOWN


  reciprocal_fsm #(.M(`Qm),.N(`Qn)) rcp_fsm (
    .i_clk    (clk),
    .i_reset  (do_reset), //@@@: SMELL: Should this be do_reset or just reset?
    .i_start  (rcp_start),
    .i_data   (rcp_in),
    .i_abs    (1'b1),
    .o_data   (rcp_out),
    .o_sat    (rcp_sat),
    .o_done   (rcp_done)
  );
  //NOTE: size is 11-bit limit of (1/visualWallDist)<<8, or 256/visualWallDist,
  // hence a visualWallDist of 1 means size is 256, which gets doubled (mirrored) to yield a screen height of 512.

  // Generate the initial tracking distances, as a portion of the full
  // step distances, relative to where our player is (fractionally) in the map cell:
  //SMELL: These only need to capture the middle half of the result,
  // e.g. if we're using Q12.12, our result should still be the [11:-12] bits
  // extracted from the product:
  //SMELL: Use a case instead?
  //NOTE: The input muxes here are reactive to the state in which the RESULT of mul_out is used,
  // so (for example) we set mul_in_a to stepDistX WHILE state==TracePrepX, because that state will
  // then directly sample the resulting mul_out value 'within' the TracePrepX state
  // (or more-accurately, as it leaves that state).

  assign mul_in_a =
    (state==TracePrepX) ? stepDistX:
    (state==TracePrepY) ? stepDistY:
    (state==CalcTexU)   ? ( side ? rayDirX : rayDirY ):
    // state==CalcTexVInit:
                          (size_full-HALF_SIZE_CLIP);

  assign mul_in_b =
    (state==TracePrepX) ? partialX:
    (state==TracePrepY) ? partialY:
    // state==CalcTexU or CalcTexVInit:
                          visualWallDist;

  assign mul_out = mul_in_a * mul_in_b;
  //NOTE: Try making these unsigned, since I think we're always going to be using them for non-negative values.

  // Map cell we're testing:
  reg `I mapX, mapY;
  // Send the current tested map cell to the map ROM:
  assign o_map_col = mapX[MAP_WBITS-1:0];
  assign o_map_row = mapY[MAP_HBITS-1:0];
  //SMELL: Either mapX/Y or map_col/row seem redundant. However, maybe mapX/Y are defined
  // as full `I range to be compatible with comparisons/assignments? Maybe there's a better
  // way to deal with this using wires.
  //TODO: Optimise.

  // Used to indicate whether X/Y-stepping is the next target:
  wire needStepX = trackDistX < trackDistY; //NOTE: UNSIGNED comparison per def'n of trackX/Ydist.


`ifdef USE_DOORS
  reg         is_door;
  wire        hit_door;
  wire [7:0]  hit_door_pos;
  wire [7:0]  wall_partial_door_pos_offset = wallPartialTexU8b - hit_door_pos;
`else // !USE_DOORS
  wire        hit_door = 0;
`endif // USE_DOORS
  wire `WALL  hit_wall_id;
  wire        valid_hit;

  wall_id_resolver #(
    .MAP_WALLBITS (MAP_WALLBITS),
    .MAP_WBITS    (MAP_WBITS),
    .MAP_HBITS    (MAP_HBITS)
  ) wall_id_resolver(
    // --- Inputs ---
    // Map cell to resolve:
    .mapx           (o_map_col), //mapX),
    .mapy           (o_map_row), //mapY),
    // Base map cell:
    .map_cell       (i_map_val),
`ifndef NO_DIV_WALLS
    // Parameters from map "dividing walls" registers:
    .mapdivx        (mapdx[4:0]),  .mapdivx_wall(mapdxw),
    .mapdivy        (mapdy[4:0]),  .mapdivy_wall(mapdyw),
`endif // NO_DIV_WALLS
    // Parameters from "OTHER" cell:
    .otherx         (otherx[4:0]),
    .othery         (othery[4:0]),
`ifdef USE_DOORS
    // Door registers:
    .doors0         (i_doors0),
    .doors1         (i_doors1),
    .doors2         (i_doors2),
    .doors3         (i_doors3),
`endif // USE_DOORS

    // --- Outputs ---
`ifdef USE_DOORS
    .o_hit_door     (hit_door),
    .o_hit_door_pos (hit_door_pos),
`endif // USE_DOORS
    .o_hit_wall_id  (hit_wall_id),
    .o_valid_hit    (valid_hit)
  );

`ifdef DEBUG_RAY_LINE_COUNTER
  int line_counter; // DEBUG.
`endif // DEBUG_RAY_LINE_COUNTER

  wire player_in_trace_cell = (mapX==playerMapX && mapY==playerMapY);

  // Hit is not valid if it's in the same map cell as the player, or if it's too close:
  //SMELL: For doors, we need to ensure the door is fully open before the player can be inside
  // the map cell (at all). Distance calculation to the wall half-width (which is the door panel)
  // is not currently supported.
  wire valid_distance = visualWallDist >= MIN_DIST_F && !player_in_trace_cell;

`ifdef USE_DOORS
  wire valid_door_distance = (visualWallDist + (side ? (stepDistY>>1) : (stepDistX>>1))) >= MIN_DIST_F && !player_in_trace_cell;
  wire do_door_check = valid_door_distance && valid_hit && hit_door && !is_door;
  wire door_plane_hit_x = ((trackDistX - (stepDistX>>1)) < trackDistY) && !side; //@@@ SHOULD ">>" BE ">>>" for both axes?
  wire door_plane_hit_y = ((trackDistY - (stepDistY>>1)) < trackDistX) && side;
  wire door_with_frame = wall[7:5]==3'b010 && wall[0]; // Doors are 010x_xxxx, and LSB==1 means it's framed.
`else // !USE_DOORS
  wire door_with_frame = 0;
`endif // USE_DOORS

  always @(posedge clk) begin
    if (do_reset) begin
`ifdef DEBUG_RAY_LINE_COUNTER
      line_counter = 0; // DEBUG.
`endif // DEBUG_RAY_LINE_COUNTER
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
      // (the Vertical Back porch) which is 33 lines, this is equivalent to starting
      // at -vplane*273. However, the trace result always displays on the NEXT line, so
      // we want to jump the gun by 1 line, hence -vplane*272. This happens to need
      // the least logic overall (I think) in order to get a perfectly balanced display.

      rcp_start <= 0;
`ifdef USE_DOORS
      is_door <= 0;
`endif // USE_DOORS
      wall <= 0;

      `ifdef RESET_TO_KNOWN
        // Set a known initial state for stuff:
        //SMELL: Don't actually need this, except to make simulation clearer,
        // because all of this stuff will naturally settle after 1 full frame anyway...?
        //SMELL: Do we ACTUALLY want to reset o_size/side on vsync? Wouldn't we want to
        // keep it in case it needs to be reused?
        o_size <= 0;
        o_side <= 0;
        o_texu <= 0;
        o_texa <= 0;
        o_texVinit <= 0;
        side <= 0;
        texu <= 0;
        rcp_in <= 0;
        // rcp_sel <= RCP_RDX; // Reciprocal's data source is initially rayDirX.
        visualWallDist <= 0;
        stepDistX <= 0;
        stepDistY <= 0;

        w <= 0;
        trackDistX <= 0;
        trackDistY <= 0;
        mapX <= 0;
        mapY <= 0;
        o_wall <= 0;
        `ifndef NO_EXTERNAL_TEXTURES
          o_wall_hot <= 0;
          o_side_hot <= 0;
          o_texu_hot <= 0;
        `endif // NO_EXTERNAL_TEXTURES
        size_full <= 0;
      `endif//RESET_TO_KNOWN

    end else begin

      // BEWARE, if adding more states: mul_in_a/b are sensitive to 'state'.

      case (state)

        // Get stepDistX from rayDirX:
        SDXPrep: begin
          rcp_in <= rayDirX;
          rcp_start <= 1;
          state <= SDYPrep;
        end
        SDYPrep: if (rcp_start) begin
          rcp_start <= 0;
        end else if (rcp_done) begin
          stepDistX <= rcp_out;
          rcp_in <= rayDirY;
          rcp_start <= 1;
          state <= TracePrepX;
        end
        TracePrepX: if (rcp_start) begin
          rcp_start <= 0;
        end else if (rcp_done) begin
          stepDistY <= rcp_out;
          //NOTE: track init comes from stepDist, comes from rayDir, comes from rayAddend.
          //NOTE: mul inputs (and hence mul_out) react to 'state'.
          trackDistX <= `FF(mul_out);
          // Get the cell the player's currently in:
          mapX <= playerMapX;
          mapY <= playerMapY;
          w <= waits; // Makes us linger on the next step (while mul_out settles).
          state <= TracePrepY;
        end

        TracePrepY: begin
`ifdef USE_DOORS
          // This helps set up for rendering a door frame when the player is standing in a door cell...
          // We do it here because this is when mapX and mapY are known:
          wall <= (hit_door && hit_wall_id[0]) ? hit_wall_id : 0;
`endif // USE_DOORS
          if (w!=0) begin
            w <= w - 1;
          end else begin
            //NOTE: track init comes from stepDist, comes from rayDir, comes from rayAddend.
            //NOTE: mul inputs (and hence mul_out) react to 'state'.
            trackDistY <= `FF(mul_out);
            w <= waits; // Makes us linger on the next step (while mul_out settles).
            state <= TraceStep;
          end
        end

        TraceStep: begin

`ifdef USE_DOORS
          if (do_door_check && door_plane_hit_x) begin
            // Hit X-aligned door plane.
            is_door <= 1;
            wall <= hit_wall_id;
            visualWallDist <= visualWallDist + (stepDistX>>1);
            state <= SizePrep;
          end else if (do_door_check && door_plane_hit_y) begin
            // Hit Y-aligned door plane.
            is_door <= 1;
            wall <= hit_wall_id;
            visualWallDist <= visualWallDist + (stepDistY>>1);
            state <= SizePrep;
          end else
`endif // USE_DOORS
          if (valid_distance && valid_hit && !hit_door) begin
            // Hit a wall.
            if (!door_with_frame) begin
              // Not a door frame; normal wall texture.
              wall <= hit_wall_id;
            end // ...else 'wall' already specifies which door frame to render.
            state <= SizePrep;
          end else begin
            // No hit; still tracing.
`ifdef USE_DOORS
            if (valid_hit && hit_door) begin // && !is_door) begin
              // Passing *through* a door with a frame.
              wall <= hit_wall_id; // This determines the door frame.
            end else begin
              //@@@ NOTE: If is_door is set at this point, then we should be immediately past a door cell hit, so frame is REQUIRED?
              // Beyond the door (if there was one).
              wall <= 0;
            end
            is_door <= 0;
`endif // USE_DOORS
            // Advance the ray.
            if (needStepX) begin
              mapX <= rxi ? mapX+1'b1 : mapX-1'b1;
              trackDistX <= trackDistX + stepDistX;
              visualWallDist <= trackDistX;
              side <= 0;
            end else begin
              mapY <= ryi ? mapY+1'b1 : mapY-1'b1;
              trackDistY <= trackDistY + stepDistY;
              visualWallDist <= trackDistY;
              side <= 1;
            end
          end

        end

        // We get to SizePrep once the nearest hit is found:
        SizePrep: begin
          rcp_in <= visualWallDist;
          rcp_start <= 1;
          state <= CalcTexU;
        end

        // Use the wall hit fractional value (6 bits of it) to determine the
        // wall texture offset in the range [0,63]...
        // By changing this we could change one axis of texture resolution or tiling.
        CalcTexU: if (rcp_start) begin
          rcp_start <= 0;
        end else if (rcp_done) begin
          size_full <= rcp_out;
          w <= waits;
          state <= CalcTexVInit;
`ifdef USE_DOORS
          if (is_door) begin
            if (wallPartialTexU8b < hit_door_pos) begin
              // Looking through a door's opening...
              texu <= 0;
              visualWallDist <= visualWallDist - (side ? (stepDistY>>1) : (stepDistX>>1)); // Step back a bit to resume the trace.
              state <= TraceStep; // Will default to stepping the ray due to is_door==1 
            end else begin
              // Unlike wall textures, doors do not get texu_mirror applied:
              texu <= wall_partial_door_pos_offset[7:2]; // wallPartial depends on `FF(mul_out). //NOTE: [7:2]; 6 MSB used for texture 0..63
              // Make sure door frame bit is cleared, as we're rendering the door itself:
              wall[0] <= 0;
              //@@@NOTE: Possible hack to fix rendering of door at extremes (i.e. 1-texu under/overflow):
              // If texu8b==0 or texu8b==255, then set (special)wall=doorframe, and texu=31 -- this will repeat 1 tiny sliver either end of the door that is the same as where it meets the frame.
            end
          end else
`endif // USE_DOORS
          begin
            texu <= wall_partial_with_flip[7:2]; // wallPartial depends on `FF(mul_out).
          end
        end

        // This state is used by shmul to determine inputs for calculating o_texVinit:
        CalcTexVInit: begin
          if (w!=0) begin
            w <= w - 1;
          end else begin
            state <= TraceDone;
            `ifndef NO_EXTERNAL_TEXTURES
              o_wall_hot <= wall;
              o_side_hot <= side;
              o_texu_hot <= texu;
            `endif // NO_EXTERNAL_TEXTURES
          end
        end 
        //SMELL: Multiplier is not in use after TracePrepX/Y so it doesn't actually need its own state... could be used in parallel, in other states.

        TraceDone: begin
          // No more work to do, so hang around in this state waiting for hmax...
          if (hmax) begin
`ifdef DEBUG_RAY_LINE_COUNTER
            line_counter = line_counter + 1; // DEBUG.
`endif // DEBUG_RAY_LINE_COUNTER
            // Upon hmax, present our new result and start the next line.
            o_wall <= wall;
            o_size <= size;
            o_side <= side;
            o_texu <= texu;
            o_texa <= visualWallDist;
            o_texVinit <= { mul_out[(`Qm-8)-1:-8], {`Qn{1'b0}} };//`FF(mul_out)<<8;
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
