`default_nettype none
`timescale 1ns / 1ps

module row_render #(
  parameter H_VIEW = 640
) (
  input wire  [1:0] wall, // Wall texture ID.
  input wire        side, // Light or dark side? side==1 is light.
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

  // wire [5:0] texuo = texu-5;

  assign rgb =
    // Fancy colourful XOR pattern:
    wall == 1 ? ({texu[0],side,texu[2],side,texu[4],side} ^ {texv[0],1'b0,texv[2],1'b0,texv[4],1'b0}): // Fancy.
    // Blue bricks:
    wall == 2 ? (side ?
                  ( // Light side.
                    (texv[2:0]==7 || (texu[4:1]==3&&texv[3]==0) || (texu[4:1]==12&&texv[3]==1)) ? 6'b10_10_10 : // Mortar.
                    (texv[2:0]==6) ? 6'b11_01_00 : // Top sheen.
                    (texv[2:0]==0) ? 6'b01_00_00 : // Bottom shade.
                    6'b11_00_00
                  ):( // Dark side.
                    (texv[2:0]==7 || (texu[4:1]==3&&texv[3]==0) || (texu[4:1]==12&&texv[3]==1)) ? 6'b01_01_01 : // Mortar.
                    (texv[2:0]==6) ? 6'b11_00_00 : // Top sheen.
                    (texv[2:0]==0) ? 6'b00_00_00 : // Bottom shade.
                    6'b10_00_00
                  )
                ):
    // Purple panels:
    wall == 3 ? (side ?
                  ( // Light side.
                    (texu[3:1]==0 || texv[3:1]==7) ? 6'b11_01_11 : // Bright bevel.
                    (texu[3:1]==7 || texv[3:1]==0) ? 6'b10_00_10 : // Shadow bevel.
                    6'b10_00_11 // Panel middle.
                  ):( // Dark side.
                    (texu[3:1]==0 || texv[3:1]==7) ? 6'b10_00_10 : // Bright bevel.
                    (texu[3:1]==7 || texv[3:1]==0) ? 6'b01_00_01 : // Shadow bevel.
                    6'b01_00_10 // Panel middle.
                  )
                ): // Purple, with borders
    /*wall==0?*/(side ? 6'b00_00_11 : 6'b00_00_10); // Red.

endmodule
