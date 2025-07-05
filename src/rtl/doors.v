`default_nettype none

// The following is all combinatorial logic to determine whether the specified map cell (mapx/y)
// has something of interest (wall or door), and what specifically.

//NOTE: If o_hit_door is true, then the lowest bit of o_hit_wall_id indicates whether this
// door also requires a frame.

module wall_id_resolver #(
    parameter MAP_WALLBITS = 3,
    parameter MAP_WBITS = 4,
    parameter MAP_HBITS = 4
) (
    // --- Inputs ---
    // Map cell to test, comes from wall_tracer.o_map_col/row:
    input [MAP_WBITS-1:0]       mapx,
    input [MAP_HBITS-1:0]       mapy,
    // Base map cell value:
    input [MAP_WALLBITS-1:0]    map_cell, // Comes from i_map_val.
`ifndef NO_DIV_WALLS
    // Map dividing wall columns/rows, and their respective wall IDs:
    input [MAP_WBITS-1:0]       mapdivx,    input [MAP_WALLBITS-1:0] mapdivx_wall,
    input [MAP_HBITS-1:0]       mapdivy,    input [MAP_WALLBITS-1:0] mapdivy_wall,
`endif // NO_DIV_WALLS
    // 'Other' cell:
    input [MAP_WBITS-1:0]       otherx,
    input [MAP_HBITS-1:0]       othery,
`ifdef USE_DOORS
    // Door registers:
    input [23:0]                doors0,
    input [23:0]                doors1,
    input [23:0]                doors2,
    input [23:0]                doors3,
`endif // USE_DOORS

    // --- Outputs ---
`ifdef USE_DOORS
    output reg                  o_hit_door,     // Whether the hit was a door cell.
    output reg [7:0]            o_hit_door_pos, // If a door cell, what's the door's sliding position? 0=closed, 254=mostly open, 255=fully open.
`endif // USE_DOORS
    output reg [7:0]            o_hit_wall_id,  // Which wall ID was hit (if any).
    output reg                  o_valid_hit     // Do we have a valid hit (door or wall) at all?
);
    // Intermediate map wall cell resolvers:
    reg wall_hit; // Intermediate flag to indicate if a valid map wall cell was hit.
    reg [MAP_WALLBITS-1:0] wall; // The base wall ID.

    always @(*) begin
        wall_hit = 1;
        if (mapx == otherx && mapy == othery) begin
            wall = 0; // OTHER cell uses wall ID 0.
        end
`ifndef NO_DIV_WALLS
        else if (mapx != 0 && mapx == mapdivx) begin
            wall = mapdivx_wall;
        end else if (mapy != 0 && mapy == mapdivy) begin
            wall = mapdivy_wall;
        end
`endif // NO_DIV_WALLS
        else if (map_cell != 0) begin
            wall = map_cell;
        end else begin
            wall = 0;
            wall_hit = 0;
        end
    end

`ifdef USE_DOORS
    // Unpack the door regs:
    //SMELL: Hard-coded widths, since the door regs themselves have fixed bitfields...
    wire [4:0]  dx [0:3]; // Door X
    wire [4:0]  dy [0:3]; // Door Y
    wire [2:0]  dw [0:3]; // Door wall
    wire [7:0]  dp [0:3]; // Door pos
    wire        df [0:3]; // Whether the door has a frame
    //NOTE: Bits 17 and 23 are currently reserved.
    assign {dx[0], dy[0], dw[0], df[0], dp[0]} = { doors0[22:18], doors0[16:12], doors0[11:9], doors0[8], doors0[7:0] };
    assign {dx[1], dy[1], dw[1], df[1], dp[1]} = { doors1[22:18], doors1[16:12], doors1[11:9], doors1[8], doors1[7:0] };
    assign {dx[2], dy[2], dw[2], df[2], dp[2]} = { doors2[22:18], doors2[16:12], doors2[11:9], doors2[8], doors2[7:0] };
    assign {dx[3], dy[3], dw[3], df[3], dp[3]} = { doors3[22:18], doors3[16:12], doors3[11:9], doors3[8], doors3[7:0] };

    // Intermediate door resolvers:
    reg door_hit; // Was a door hit?
    reg [2:0] door; // What door base texture is selected by the door reg?
    reg door_framed; // Does this door get a frame?

    wire valid_door_cell = ({mapx,mapy} != 0); // Doors cannot exist at (0,0).

    always @(*) begin
        door_hit = 1; // Assume hit by default, but final 'else' will override this.
        /**/ if ( valid_door_cell && dx[0]==mapx && dy[0]==mapy ) {door, door_framed, o_hit_door_pos} = {dw[0], df[0], dp[0]};
        else if ( valid_door_cell && dx[1]==mapx && dy[1]==mapy ) {door, door_framed, o_hit_door_pos} = {dw[1], df[1], dp[1]};
        else if ( valid_door_cell && dx[2]==mapx && dy[2]==mapy ) {door, door_framed, o_hit_door_pos} = {dw[2], df[2], dp[2]};
        else if ( valid_door_cell && dx[3]==mapx && dy[3]==mapy ) {door, door_framed, o_hit_door_pos} = {dw[3], df[3], dp[3]};
        else begin
            door_hit = 0;
            {door, door_framed, o_hit_door_pos} = 0;
        end
    end
`endif // USE_DOORS

    always @(*) begin
`ifdef USE_DOORS
        if (door_hit) begin
            o_valid_hit = 1;
            o_hit_door = 1;
            if (door==0)
                // Door reg doesn't specify a wall ID (i.e. it's 0), so derive the wall ID from the door's underlying map cell:
                o_hit_wall_id = {4'b0101, wall, door_framed};
            else
                // Door reg specifies a wall ID in the range 1-7, so use it:
                o_hit_wall_id = {4'b0100, door, door_framed};
        end else
`endif // USE_DOORS
        /*else*/ if (wall_hit) begin
            o_valid_hit = 1;
            o_hit_door = 0;
            o_hit_wall_id = {5'b00000, wall};
        end else begin
            o_valid_hit = 0;
            o_hit_door = 0;
            o_hit_wall_id = 0;
        end
    end

endmodule
