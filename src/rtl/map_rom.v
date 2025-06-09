`default_nettype none
// `timescale 1ns / 1ps

module map_rom #(
  parameter MAP_WALLBITS = 3,
  parameter MAP_WBITS   = 4,
  parameter MAP_HBITS   = 4
) (
  input [2:0] map_mode, // 0=Classic map; 1=Tweaked map; 2=Funky map; 3=Interesting map
  input [MAP_WBITS-1:0] i_col,
  input [MAP_HBITS-1:0] i_row,
  output [MAP_WALLBITS-1:0] o_val
);

  localparam COL_COUNT = (1<<MAP_WBITS);
  localparam ROW_COUNT = (1<<MAP_HBITS);
  localparam MAX_COL = COL_COUNT-1;
  localparam MAX_ROW = ROW_COUNT-1;

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

  assign o_val =
    ({bit1,bit0} == 0)              ? 0 :
    map_mode == 2                   ? ss[2:0]: // Funky mode.
    // Classic mode:
    (ss[1:0] == 0 && i_col[0] == 0) ? {1'b1, bit1, bit0}:
    (i_row[4:3] != ~i_col[4:3])      ? {1'b0, bit1, bit0}:
                                      ss[2:0];
                          // {(ss[1:0] == 0 && i_col[0] == 0), bit1, bit0}; // Classic mode.
  //({bit1,bit0} == 0) ? 0 : (ss[1] ^ i_row[1]);
  // assign o_val =   {bit2,bit1,bit0};
  // ss[2:0];//{bit2,bit1,bit0};

endmodule
