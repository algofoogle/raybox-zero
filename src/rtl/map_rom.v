`default_nettype none
`timescale 1ns / 1ps

module map_rom #(
  parameter MAP_WBITS   = 4,
  parameter MAP_HBITS   = 4
) (
  input [MAP_WBITS-1:0] i_col,
  input [MAP_HBITS-1:0] i_row,
  output                o_val
);

  localparam COL_COUNT = (1<<MAP_WBITS);
  localparam ROW_COUNT = (1<<MAP_HBITS);
  localparam MAX_COL = COL_COUNT-1;
  localparam MAX_ROW = ROW_COUNT-1;

  assign o_val =
    i_col == 0 || i_col == MAX_COL || // Left and right borders.
    i_row == 0 || i_row == MAX_ROW || // Top and bottom borders.
      ((~i_row[2:0]==i_col[2:0]) & ~i_row[3] & ~i_col[3]) || // Diagonal in top-left corner of map.
      (((
        (i_row[1] ^ i_col[2]) ^ (i_row[0] & i_col[1])
      ) & i_row[2] & i_col[1]) | (~i_row[0]&~i_col[0]))
      & (i_row[2]^~i_col[2])
    ;   

endmodule
