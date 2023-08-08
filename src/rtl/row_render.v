`default_nettype none
`timescale 1ns / 1ps

module row_render #(
  localparam H_VIEW = 640
) (
  input wire side,
  input wire [10:0] size, // Supports 0..2047; remember this is mirrored, too.
  input wire [9:0] hpos,  // Current horizontal trace position.
  output wire [1:0] r, g, b,
  output wire hit         // Are we in this row or not?    
);
  localparam HALF_SIZE = H_VIEW/2;
  //SMELL: Instead of combo logic, could use a register and check for enter/leave:
  assign hit =
    (size > HALF_SIZE) ||
    ((HALF_SIZE-size <= {1'b0,hpos}) && ({1'b0,hpos} <= HALF_SIZE+size));
  //SMELL: For now, just arbitrarily assign a colour based on side. Later, do textures.
  assign {r,g,b} = side ?
    6'b00_00_11 :
    6'b00_00_10;

endmodule
