`default_nettype none
// `timescale 1ns / 1ps

module map_rom #(
  parameter MAP_WALLBITS = 3,
  parameter MAP_WBITS   = 4,
  parameter MAP_HBITS   = 4
) (
`ifdef USE_MAP_RECT
  input [5:0]   mapr_ax,
  input [5:0]   mapr_ay,
  input [5:0]   mapr_bx,
  input [5:0]   mapr_by,
  input         mapr_erase,
  input [2:0]   mapr_wall,
`endif // USE_MAP_RECT
  input [2:0] map_mode, // 0=Classic map; 1=Tweaked map; 2=Funky map; 3=Interesting map
  input [MAP_WBITS-1:0] i_col,
  input [MAP_HBITS-1:0] i_row,
  output [MAP_WALLBITS-1:0] o_val
);

  localparam COL_COUNT = (1<<MAP_WBITS);
  localparam ROW_COUNT = (1<<MAP_HBITS);
  localparam MAX_COL = COL_COUNT-1;
  localparam MAX_ROW = ROW_COUNT-1;

  wire [2:0] interesting_wall;

  interesting_map interesting_map(
    .x    (i_col),
    .y    (i_row),
    .wall (interesting_wall)
  );

  wire bit0 = 
    i_col == 0 || i_col == MAX_COL || // Left and right borders.
    i_row == 0 || i_row == MAX_ROW || // Top and bottom borders.
      ((~i_row[2:0]==i_col[2:0]) & ~i_row[3] & ~i_col[3]) || // Diagonal in top-left corner of map.
      (((
        (i_row[1] ^ i_col[2]) ^ (i_row[0] & i_col[1])
      ) & i_row[2] & i_col[1]) | (~i_row[0]&~i_col[0]))
      & (i_row[2]^~i_col[2])
    ;

  wire f1 = i_col[3];
  wire f2 = i_col[2];
  wire f3 = i_col[1];
  wire f4 = i_col[0];

  wire a6 = i_row[3];
  wire b6 = i_row[2];
  wire c6 = i_row[1];
  wire d6 = i_row[0];

  wire [MAP_WBITS-1:0] ss = i_col + {1'b0,i_row[MAP_HBITS-1:1]} + (i_col[MAP_WBITS-1] ? 5'd3 : 5'd0);

  wire bit1 = ((((f3^d6) & (f2^a6)) & (f4^b6)) & (f1^c6)) | (i_col==8 && i_row==10);

  wire [5:0] wcol = { {(6-MAP_WBITS){1'b0}}, i_col };
  wire [5:0] wrow = { {(6-MAP_WBITS){1'b0}}, i_row };

`ifdef USE_MAP_RECT
  wire in_rect = ((wcol >= mapr_ax && wcol < mapr_bx) && (wrow >= mapr_ay && wrow < mapr_by));
  wire in_rect_border = (mapr_wall != 0) && in_rect && (
    (wcol == mapr_ax || wcol == (mapr_bx-1) || wrow == mapr_ay || wrow == (mapr_by-1))
  );
`endif // USE_MAP_RECT

  wire [2:0] wall_id_fallback = 
    map_mode == 0                   ? {1'b0,bit1,bit0} :
    map_mode == 3                   ? interesting_wall :
    ({bit1,bit0} == 0)              ? 0 :
    map_mode == 2                   ? ss[2:0]: // Funky mode.
    // Classic mode:
    (ss[1:0] == 0 && i_col[0] == 0) ? {1'b1, bit1, bit0}:
    (i_row[4:3] != ~i_col[4:3])      ? {1'b0, bit1, bit0}:
                                      ss[2:0];
  assign o_val =
`ifdef USE_MAP_RECT
    in_rect_border          ? mapr_wall:  // We're in the rectangle border, and it's not wallID==0, so it wins.
    (in_rect && mapr_erase) ? 0:          // We're in the rectangle (but not the border), and erase is enabled, so erase.
`endif // USE_MAP_RECT
                              wall_id_fallback;

endmodule



module interesting_map (
    input  wire [4:0] x,
    input  wire [4:0] y,
    output reg  [2:0] wall
);
    // Bitwise logic, no multiplication
    wire [4:0] x_inv = ~x;
    wire [4:0] y_inv = ~y;

    wire [4:0] p1 = x ^ y;
    wire [4:0] p2 = x_inv ^ y;
    wire [4:0] p3 = x | y_inv;

    wire [2:0] h1 = p1[4:2] ^ p2[2:0];
    wire [2:0] h2 = p3[2:0] ^ {x[1], y[2], x[0]};

    wire parity1 = ^h1;
    wire parity2 = ^h2;

    wire boundary = (x == 5'd0) | (y == 5'd0) | (x == 5'd31) | (y == 5'd31);
    wire base_wall = ((parity1 & ~x[2]) | (parity2 & y[1])) ^ boundary;

    // Special open regions
    wire open_h = (y == 5'd12) && (x > 5'd4) && (x < 5'd27);
    wire open_v = (x == 5'd16) && (y > 5'd4) && (y < 5'd27);
    wire box1 = (x >= 5'd8 && x <= 5'd10) && (y >= 5'd6 && y <= 5'd8);
    wire box2 = (x >= 5'd20 && x <= 5'd23) && (y >= 5'd18 && y <= 5'd21);
    wire shard1 = (x[2:0] == 3'b011) && y[2];
    wire shard2 = (y[2:0] == 3'b100) && x[3];

    wire hole1 = (x == 5'd6 && y == 5'd16);
    wire hole2 = (x == 5'd20 && y == 5'd28);

    wire open_region = open_h | open_v | box1 | box2 | shard1 | shard2 | hole1 | hole2;

    // Red wall frame
    wire red_wall = ((y == 5'd11 || y == 5'd13) && (x > 5'd4 && x < 5'd27)) ||
                    ((x == 5'd15 || x == 5'd17) && (y > 5'd4 && y < 5'd27));

    // Hash for color variation
    wire [2:0] hash = (x[2:0] ^ y[2:0]) ^ {x[3], y[3], x[4] ^ y[4]};
    wire [4:0] wcluster = ((x >> 2) + (y >> 2)) >> 1;
    // wire [2:0] cluster = wcluster[2:0];
    wire [4:0] clusterhash = wcluster + {2'd0,hash};
    // wire [2:0] biased = (cluster + hash) >> 1;
    wire [4:0] wbiased = clusterhash >> 1;
    wire [2:0] biased = wbiased[2:0];
    wire [2:0] final_code = (biased == 3'b000) ? 3'b001 : biased;

    // Sparse white injection: hardcoded locations (at least 3)
    wire forced_white =
        (x == 5'd7  && y == 5'd11) ||  // manually selected safe white spots
        (x == 5'd22 && y == 5'd13) ||
        (x == 5'd15 && y == 5'd19);

    always @* begin
        if (open_region)
            wall = 3'b000;  // black/open
        else if (forced_white)
            wall = 3'b111;  // white flicker
        else if (red_wall)
            wall = 3'b100;  // red frame
        else if (base_wall)
            wall = final_code;  // wall color
        else
            wall = 3'b000;  // fallback
    end
endmodule
