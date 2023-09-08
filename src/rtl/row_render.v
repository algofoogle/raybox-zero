`default_nettype none
`timescale 1ns / 1ps

module row_render #(
  parameter H_VIEW = 640
) (
  input wire side,
  input wire [10:0] size, // Supports 0..2047; remember this is mirrored, too.
  input wire  [9:0] hpos, // Current horizontal trace position.
  input wire  [5:0] texu, // Texture 'u' coordinate, 0..63
  input wire  [5:0] texv, // Texture 'v' coordinate, 0..63
  output wire [5:0] rgb,  //NOTE: BBGGRR bit order.
  output wire hit         // Are we in this row or not?    
);
  localparam HALF_SIZE = H_VIEW/2;
  //SMELL: Instead of combo logic, could use a register and check for enter/leave:
  assign hit =
    (size > HALF_SIZE) ||
    ((HALF_SIZE-size <= {1'b0,hpos}) && ({1'b0,hpos} <= HALF_SIZE+size));
  //SMELL: For now, just arbitrarily assign a colour based on side. Later, do textures.
  assign rgb = {texu[0],side,texu[2],side,texu[4],side} ^ {texv[0],1'b0,texv[2],1'b0,texv[4],1'b0};
  
  // wire check = texu[0]^texv[0];
  // assign rgb =
  //   side  ?   { 2'b11, check,1'b0, 2'b00 } :
  //             { 2'b10, 1'b0,check, 2'b00 };
    // { texu[2],1'b0, texu[1],1'b0, texu[0],1'b0 } >> side;
    // texu == 0   ? 6'b11_10_00 :
    // texu == 63  ? 6'b01_00_00 :
    // side        ? 6'b11_00_00 :
    //               6'b10_00_00;

endmodule
